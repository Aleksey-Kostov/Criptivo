import 'dart:async';
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_service.dart';
import '../../core/chat/chat_service.dart';
import '../../core/chat/reaction_service.dart';
import '../../core/chat/typing_service.dart';
import '../../core/chat/voice_recorder_service.dart';
import '../../core/crypto/glagolitic_seal.dart';
import '../../core/crypto/key_manager.dart';
import '../../core/crypto/media_crypto.dart';
import '../../core/crypto/message_crypto.dart';
import '../../core/crypto/safety_number.dart';
import '../../core/storage/media_service.dart';
import '../../core/theme/criptivo_theme.dart';
import 'helpers/chat_scroll_helper.dart';
import 'widgets/attach_preview_strip.dart';
import 'widgets/chat_emoji_panel.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/glagolitic_seal_badge.dart';
import 'widgets/reaction_bar.dart';
import 'widgets/reaction_picker.dart';
import 'widgets/scroll_to_bottom_button.dart';
import 'widgets/typing_indicator.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;
  final Map<String, dynamic> otherUser;

  const ChatPage({
    super.key,
    required this.conversationId,
    required this.otherUser,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  late final ChatScrollHelper _scrollHelper;
  TypingService? _typingService;
  VoiceRecorderService? _voiceRecorder;

  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _uploadingMedia = false;
  bool _showEmojiPicker = false;
  bool _hasText = false;
  bool _peerTyping = false;
  String? _error;
  String? _theirPublicKey;
  PendingAttachment? _pending;

  RealtimeChannel? _channel;
  Timer? _sealTimer;
  Timer? _pollTimer;
  Timer? _expireTimer;

  String _sealGlyph = 'Ⰰ';
  DateTime? _conversationCreatedAt;
  int? _disappearSeconds;

  static const _disappearOptions = <(String, int?)>[
    ('Изключено', null),
    ('30 секунди', 30),
    ('5 минути', 300),
    ('1 час', 3600),
    ('24 часа', 86400),
    ('7 дни', 604800),
  ];

  String get _otherName =>
      widget.otherUser['display_name'] ??
      widget.otherUser['username'] ??
      'Chat';

  String? get _otherUserId =>
      widget.otherUser['id'] as String? ??
      widget.otherUser['other_user_id'] as String?;

  @override
  void initState() {
    super.initState();
    _scrollHelper = ChatScrollHelper(
      controller: _scrollController,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    _voiceRecorder = VoiceRecorderService();
    _focusNode.addListener(_onFocusChange);
    _initChat();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus && _showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
    }
  }

  Future<void> _initChat() async {
    await _refreshTheirPublicKey();
    await _loadConversationMeta();
    if (_theirPublicKey != null && _theirPublicKey!.isNotEmpty) {
      await _startSeal();
    }
    await _loadMessages();
    await ChatService.markMessagesAsRead(widget.conversationId);
    _subscribeToMessages();
    _startPollFallback();
    _startExpireWatcher();

    final uid = AuthService.currentUser?.id;
    if (uid != null) {
      _typingService = TypingService(
        conversationId: widget.conversationId,
        myUserId: uid,
        onPeerTypingChanged: (t) {
          if (mounted) setState(() => _peerTyping = t);
        },
      )..start();
    }
  }

  Future<void> _refreshTheirPublicKey() async {
    final otherId = _otherUserId;
    if (otherId == null) {
      setState(() {
        _theirPublicKey = widget.otherUser['public_key'] as String?;
      });
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('public_key')
          .eq('id', otherId)
          .maybeSingle();
      setState(() {
        _theirPublicKey = row?['public_key'] as String? ??
            widget.otherUser['public_key'] as String?;
      });
    } catch (e) {
      debugPrint('Failed to refresh public key: $e');
      setState(() {
        _theirPublicKey = widget.otherUser['public_key'] as String?;
      });
    }
  }

  Future<void> _loadConversationMeta() async {
    try {
      final row = await Supabase.instance.client
          .from('conversations')
          .select('created_at, disappear_seconds')
          .eq('id', widget.conversationId)
          .maybeSingle();
      if (row != null) {
        if (row['created_at'] != null) {
          _conversationCreatedAt =
              DateTime.parse(row['created_at'] as String).toUtc();
        } else {
          _conversationCreatedAt = DateTime.now().toUtc();
        }
        final sec = row['disappear_seconds'] as int?;
        if (mounted) {
          setState(() => _disappearSeconds = sec);
        } else {
          _disappearSeconds = sec;
        }
      } else {
        _conversationCreatedAt = DateTime.now().toUtc();
      }
    } catch (e) {
      debugPrint('Conversation meta error: $e');
      _conversationCreatedAt = DateTime.now().toUtc();
    }
  }

  void _startExpireWatcher() {
    _expireTimer?.cancel();
    _expireTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final now = DateTime.now().toUtc();
      final before = _messages.length;
      _messages.removeWhere((m) {
        final exp = m['expires_at'];
        if (exp == null) return false;
        try {
          return !DateTime.parse(exp.toString()).toUtc().isAfter(now);
        } catch (_) {
          return false;
        }
      });
      if (_messages.length != before && mounted) setState(() {});
    });
  }

  Future<void> _showDisappearSheet() async {
    setState(() => _showEmojiPicker = false);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: CriptivoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Изчезващи съобщения',
                  style: TextStyle(
                    color: CriptivoColors.neon,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Новите съобщения се изтриват след избраното време '
                  'и за двамата участници.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: CriptivoColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final opt in _disappearOptions)
                ListTile(
                  title: Text(
                    opt.$1,
                    style: const TextStyle(color: CriptivoColors.textPrimary),
                  ),
                  trailing: _disappearSeconds == opt.$2
                      ? const Icon(Icons.check_rounded,
                          color: CriptivoColors.neon)
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await ChatService.setDisappearSeconds(
                        conversationId: widget.conversationId,
                        seconds: opt.$2,
                      );
                      if (mounted) {
                        setState(() => _disappearSeconds = opt.$2);
                      }
                    } catch (e) {
                      debugPrint('setDisappearSeconds: $e');
                    }
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startSeal() async {
    await _updateSeal();
    _sealTimer?.cancel();
    _sealTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updateSeal();
    });
  }

  Future<void> _updateSeal() async {
    final theirKey = _theirPublicKey;
    final created = _conversationCreatedAt;
    if (theirKey == null || theirKey.isEmpty || created == null) return;
    try {
      final secret = await MessageCrypto.sessionSecretBytes(
        theirPublicKeyBase64: theirKey,
      );
      final seal = GlagoliticSeal(
        sessionSecret: secret,
        conversationId: widget.conversationId,
      );
      final glyph = await seal.currentGlyph(conversationCreatedAt: created);
      if (mounted) setState(() => _sealGlyph = glyph);
    } catch (e) {
      debugPrint('Seal error: $e');
    }
  }

  String _formatTime(dynamic createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = createdAt is DateTime
          ? createdAt.toLocal()
          : DateTime.parse(createdAt.toString()).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }

  String? _expireLabel(dynamic expiresAt) {
    if (expiresAt == null) return null;
    try {
      final exp = DateTime.parse(expiresAt.toString()).toUtc();
      final sec = exp.difference(DateTime.now().toUtc()).inSeconds;
      if (sec <= 0) return null;
      if (sec < 60) return '⏱ ${sec}s';
      if (sec < 3600) return '⏱ ${sec ~/ 60}m';
      if (sec < 86400) return '⏱ ${sec ~/ 3600}h';
      return '⏱ ${sec ~/ 86400}d';
    } catch (_) {
      return null;
    }
  }

  String _displayFromPlaintext(String plaintext) {
    final media = MediaCrypto.tryParseEnvelope(plaintext);
    if (media == null) return plaintext;
    final name = media['name'] as String? ?? '';
    return switch (media['type']) {
      'image' => '🖼️ ${name.isEmpty ? 'снимка' : name}',
      'video' => '🎬 ${name.isEmpty ? 'видео' : name}',
      'audio' => '🎵 ${name.isEmpty ? 'аудио' : name}',
      'gif' => 'GIF',
      _ => '📎 ${name.isEmpty ? 'файл' : name}',
    };
  }

  Map<String, dynamic> _messageFromPlaintext(
    Map<String, dynamic> row,
    String plaintext,
    bool isMe,
  ) {
    final media = MediaCrypto.tryParseEnvelope(plaintext);
    return {
      ...row,
      'text': media != null ? _displayFromPlaintext(plaintext) : plaintext,
      'is_me': isMe,
      'media': media,
      'reactions': <Map<String, dynamic>>[],
      'reactions_raw': <Map<String, dynamic>>[],
    };
  }

  // ── Emoji ────────────────────────────────────

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      setState(() => _showEmojiPicker = true);
    }
  }

  void _onEmojiSelected(String emoji) {
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final newText = text.replaceRange(start, end, emoji);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    setState(() => _hasText = newText.trim().isNotEmpty);
  }

  void _onEmojiBackspace() {
    final text = _controller.text;
    if (text.isEmpty) return;
    final newText = text.characters.skipLast(1).toString();
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    setState(() => _hasText = newText.trim().isNotEmpty);
  }

  // ── Reactions ────────────────────────────────

  Future<void> _attachReactions(List<Map<String, dynamic>> list) async {
    final ids = list
        .map((m) => m['id'])
        .whereType<String>()
        .where((id) => !id.startsWith('temp_'))
        .toList();
    if (ids.isEmpty) return;
    try {
      final map = await ReactionService.getForMessages(ids);
      for (final m in list) {
        final id = m['id'] as String?;
        if (id == null) continue;
        final rows = map[id] ?? [];
        m['reactions_raw'] = rows;
        m['reactions'] = ReactionService.aggregate(rows);
      }
    } catch (e) {
      debugPrint('Reactions load error: $e');
    }
  }

  Future<void> _toggleReaction(String messageId, String emoji) async {
    if (messageId.startsWith('temp_')) return;
    try {
      await ReactionService.toggle(messageId: messageId, emoji: emoji);
      final map = await ReactionService.getForMessages([messageId]);
      final rows = map[messageId] ?? [];
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m['id'] == messageId);
        if (i != -1) {
          _messages[i] = {
            ..._messages[i],
            'reactions_raw': rows,
            'reactions': ReactionService.aggregate(rows),
          };
        }
      });
    } catch (e) {
      debugPrint('Reaction toggle error: $e');
    }
  }

  Future<void> _onBubbleLongPress(Map<String, dynamic> msg) async {
    final id = msg['id'] as String?;
    if (id == null || id.startsWith('temp_')) return;
    final emoji = await showReactionPicker(context);
    if (emoji == null) return;
    await _toggleReaction(id, emoji);
  }

  Future<void> _refreshReactionsForMessage(String messageId) async {
    final map = await ReactionService.getForMessages([messageId]);
    final rows = map[messageId] ?? [];
    if (!mounted) return;
    setState(() {
      final i = _messages.indexWhere((m) => m['id'] == messageId);
      if (i != -1) {
        _messages[i] = {
          ..._messages[i],
          'reactions_raw': rows,
          'reactions': ReactionService.aggregate(rows),
        };
      }
    });
  }

  // ── Safety Number ────────────────────────────

  Future<void> _showSafetyNumber() async {
    final theirKey = _theirPublicKey;
    if (theirKey == null || theirKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Липсва public key на събеседника')),
      );
      return;
    }
    final myPublicKey = await KeyManager.getPublicKeyBase64();
    if (myPublicKey == null || myPublicKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Липсва твоят public key')),
      );
      return;
    }
    final number = await SafetyNumber.generate(
      myPublicKeyBase64: myPublicKey,
      theirPublicKeyBase64: theirKey,
    );
    final formatted = SafetyNumber.format(number);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: CriptivoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: CriptivoColors.neon.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Safety Number',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: CriptivoColors.neon,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'с $_otherName',
                style: const TextStyle(
                  color: CriptivoColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: CriptivoColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: CriptivoColors.neon.withValues(alpha: 0.2),
                  ),
                ),
                child: const Text(
                  'Сравни този номер с този на другия човек '
                  '(на живо, по телефона или лично).\n'
                  'Ако съвпадат — връзката е защитена.',
                  style: TextStyle(
                    color: CriptivoColors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              SelectableText(
                formatted,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 17,
                  letterSpacing: 1.1,
                  height: 1.55,
                  color: CriptivoColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: formatted));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Safety Number копиран'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Копирай номера'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Затвори'),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Realtime + Polling ───────────────────────

  void _subscribeToMessages() {
    _channel?.unsubscribe();
    _channel = Supabase.instance.client
        .channel('messages:${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            final row = Map<String, dynamic>.from(payload.newRecord);
            if (row.isEmpty) return;
            if (row['conversation_id'] != widget.conversationId) return;
            final id = row['id'];
            if (_messages.any((m) => m['id'] == id)) return;
            final myId = AuthService.currentUser?.id;
            final isMe = row['sender_id'] == myId;
            if (isMe) return;

            String plaintext;
            try {
              if (_theirPublicKey == null || _theirPublicKey!.isEmpty) {
                await _refreshTheirPublicKey();
              }
              final theirKey = _theirPublicKey;
              if (theirKey == null || theirKey.isEmpty) {
                plaintext = '[липсва ключ]';
              } else {
                plaintext = await MessageCrypto.decrypt(
                  ciphertextBase64: row['ciphertext'] as String,
                  nonceBase64: row['nonce'] as String,
                  theirPublicKeyBase64: theirKey,
                );
              }
            } catch (e) {
              plaintext = '[не може да се декриптира]';
              debugPrint('Realtime decrypt error: $e');
            }

            if (!mounted) return;
            final msg = _messageFromPlaintext(row, plaintext, isMe);
            setState(() => _messages.add(msg));
            _scrollHelper.onIncomingMessage();
            await ChatService.markMessagesAsRead(widget.conversationId);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final row = Map<String, dynamic>.from(payload.newRecord);
            if (row['conversation_id'] != widget.conversationId) return;
            final id = row['id'];
            final readAt = row['read_at'];
            if (id == null || readAt == null) return;
            final i = _messages.indexWhere((m) => m['id'] == id);
            if (i == -1) return;
            if (!mounted) return;
            setState(() {
              _messages[i] = {..._messages[i], 'read_at': readAt};
            });
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          callback: (payload) async {
            final row = payload.newRecord.isNotEmpty
                ? payload.newRecord
                : payload.oldRecord;
            final messageId = row['message_id'] as String?;
            if (messageId == null) return;
            if (!_messages.any((m) => m['id'] == messageId)) return;
            await _refreshReactionsForMessage(messageId);
          },
        )
        .subscribe((status, [err]) {
          debugPrint('Realtime status: $status err: $err');
        });
  }

  void _startPollFallback() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_loading && !_sending && !_uploadingMedia) {
        _loadMessagesQuiet();
      }
    });
  }

  Future<void> _loadMessagesQuiet() async {
    try {
      final rows = await ChatService.getMessages(widget.conversationId);
      final myId = AuthService.currentUser?.id;
      final decrypted = <Map<String, dynamic>>[];
      for (final row in rows) {
        final isMe = row['sender_id'] == myId;
        String plaintext;
        try {
          final theirKey = _theirPublicKey;
          if (theirKey == null || theirKey.isEmpty) {
            plaintext = '[липсва ключ]';
          } else {
            plaintext = await MessageCrypto.decrypt(
              ciphertextBase64: row['ciphertext'],
              nonceBase64: row['nonce'],
              theirPublicKeyBase64: theirKey,
            );
          }
        } catch (_) {
          plaintext = '[не може да се декриптира]';
        }
        decrypted.add(_messageFromPlaintext(row, plaintext, isMe));
      }
      await _attachReactions(decrypted);
      if (!mounted) return;
      final grew = decrypted.length > _messages.length;
      final changed =
          decrypted.length != _messages.length || !_sameReadState(decrypted);
      if (changed) {
        setState(() => _messages = decrypted);
        if (grew) _scrollHelper.onIncomingMessage();
      }
    } catch (e) {
      debugPrint('Poll error: $e');
    }
  }

  bool _sameReadState(List<Map<String, dynamic>> next) {
    if (next.length != _messages.length) return false;
    for (var i = 0; i < next.length; i++) {
      if (next[i]['id'] != _messages[i]['id']) return false;
      if (next[i]['read_at'] != _messages[i]['read_at']) return false;
    }
    return true;
  }

  Future<void> _loadMessages() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ChatService.getMessages(widget.conversationId);
      final myId = AuthService.currentUser?.id;
      final decrypted = <Map<String, dynamic>>[];
      for (final row in rows) {
        final isMe = row['sender_id'] == myId;
        String plaintext;
        try {
          final theirKey = _theirPublicKey;
          if (theirKey == null || theirKey.isEmpty) {
            plaintext = '[липсва ключ]';
          } else {
            plaintext = await MessageCrypto.decrypt(
              ciphertextBase64: row['ciphertext'],
              nonceBase64: row['nonce'],
              theirPublicKeyBase64: theirKey,
            );
          }
        } catch (e) {
          plaintext = '[не може да се декриптира]';
          debugPrint('Decrypt error: $e');
        }
        decrypted.add(_messageFromPlaintext(row, plaintext, isMe));
      }
      await _attachReactions(decrypted);
      if (!mounted) return;
      setState(() {
        _messages = decrypted;
        _loading = false;
      });
      _scrollHelper.scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── Send ─────────────────────────────────────

  Future<void> _sendOrPending() async {
    if (_pending != null) {
      await _sendPending();
      return;
    }
    await _send();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending || _uploadingMedia) return;
    setState(() {
      _sending = true;
      _error = null;
      _showEmojiPicker = false;
    });
    await _typingService?.setTyping(false);
    try {
      await _refreshTheirPublicKey();
      final theirKey = _theirPublicKey;
      if (theirKey == null || theirKey.isEmpty) {
        setState(() => _error = 'Другият потребител няма public key');
        return;
      }
      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      setState(() {
        _messages.add({
          'id': tempId,
          'text': text,
          'is_me': true,
          'sender_id': AuthService.currentUser?.id,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'read_at': null,
          'media': null,
          'reactions': <Map<String, dynamic>>[],
        });
        _hasText = false;
      });
      _controller.clear();
      _scrollHelper.scrollToBottom();
      final inserted = await ChatService.sendEncryptedMessage(
        conversationId: widget.conversationId,
        plaintext: text,
        theirPublicKeyBase64: theirKey,
      );
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m['id'] == tempId);
        if (i != -1) {
          _messages[i] = {
            ...inserted,
            'text': text,
            'is_me': true,
            'media': null,
            'reactions': <Map<String, dynamic>>[],
          };
        }
      });
    } catch (e) {
      setState(() {
        _messages.removeWhere(
          (m) => m['id'] is String && (m['id'] as String).startsWith('temp_'),
        );
        _error = 'Грешка при изпращане: $e';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendPending() async {
    final p = _pending;
    if (p == null || _sending || _uploadingMedia) return;
    setState(() {
      _uploadingMedia = true;
      _error = null;
      _showEmojiPicker = false;
    });
    try {
      await _refreshTheirPublicKey();
      final theirKey = _theirPublicKey;
      if (theirKey == null || theirKey.isEmpty) {
        setState(() => _error = 'Другият потребител няма public key');
        return;
      }
      final ref = await p.upload();
      final media = MediaCrypto.tryParseEnvelope(ref.envelopeJson);
      final preview = _displayFromPlaintext(ref.envelopeJson);
      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      setState(() {
        _pending = null;
        _messages.add({
          'id': tempId,
          'text': preview,
          'is_me': true,
          'sender_id': AuthService.currentUser?.id,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'read_at': null,
          'media': media,
          'reactions': <Map<String, dynamic>>[],
        });
      });
      _scrollHelper.scrollToBottom();
      final inserted = await ChatService.sendEncryptedMessage(
        conversationId: widget.conversationId,
        plaintext: ref.envelopeJson,
        theirPublicKeyBase64: theirKey,
      );
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m['id'] == tempId);
        if (i != -1) {
          _messages[i] = {
            ...inserted,
            'text': preview,
            'is_me': true,
            'media': media,
            'reactions': <Map<String, dynamic>>[],
          };
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Медия: $e');
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  Future<void> _onVoiceRecorded(VoiceRecording rec) async {
    if (_sending || _uploadingMedia) return;
    setState(() {
      _uploadingMedia = true;
      _error = null;
    });
    try {
      await _refreshTheirPublicKey();
      final theirKey = _theirPublicKey;
      if (theirKey == null || theirKey.isEmpty) {
        setState(() => _error = 'Другият потребител няма public key');
        return;
      }
      final uploaded = await MediaService.uploadVoiceFile(
        filePath: rec.filePath,
        durationMs: rec.durationMs,
      );
      if (uploaded == null) return;
      final media = MediaCrypto.tryParseEnvelope(uploaded.envelopeJson);
      final preview = _displayFromPlaintext(uploaded.envelopeJson);
      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      setState(() {
        _messages.add({
          'id': tempId,
          'text': preview,
          'is_me': true,
          'sender_id': AuthService.currentUser?.id,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'media': media,
          'reactions': <Map<String, dynamic>>[],
        });
      });
      _scrollHelper.scrollToBottom();
      final inserted = await ChatService.sendEncryptedMessage(
        conversationId: widget.conversationId,
        plaintext: uploaded.envelopeJson,
        theirPublicKeyBase64: theirKey,
      );
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m['id'] == tempId);
        if (i != -1) {
          _messages[i] = {
            ...inserted,
            'text': preview,
            'is_me': true,
            'media': media,
            'reactions': <Map<String, dynamic>>[],
          };
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Глас: $e');
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  void _setPendingBytes({
    required List<int> bytes,
    required String name,
    required String mime,
    required String kind,
    Uint8List? imageBytes,
  }) {
    final copy = List<int>.from(bytes);
    setState(() {
      _pending = PendingAttachment(
        name: name,
        mime: mime,
        kind: kind,
        imageBytes: imageBytes,
        upload: () async {
          final u = await MediaService.uploadBytes(
            bytes: copy,
            name: name,
            mime: mime,
          );
          return UploadedMediaRef(u.envelopeJson);
        },
      );
    });
  }

  Future<void> _pickPendingImage() async {
    try {
      final picked = await MediaService.pickImageLocal();
      if (picked == null) return;
      _setPendingBytes(
        bytes: picked.bytes,
        name: picked.name,
        mime: picked.mime,
        kind: 'image',
        imageBytes: Uint8List.fromList(picked.bytes),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _pickPendingVideo() async {
    try {
      final picked = await MediaService.pickVideoLocal();
      if (picked == null) return;
      _setPendingBytes(
        bytes: picked.bytes,
        name: picked.name,
        mime: picked.mime,
        kind: 'video',
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _pickPendingFile() async {
    try {
      final picked = await MediaService.pickFileLocal();
      if (picked == null) return;
      _setPendingBytes(
        bytes: picked.bytes,
        name: picked.name,
        mime: picked.mime,
        kind: 'file',
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _showAttachSheet() {
    setState(() => _showEmojiPicker = false);
    showModalBottomSheet(
      context: context,
      backgroundColor: CriptivoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_outlined,
                    color: CriptivoColors.neon),
                title: const Text('Снимка',
                    style: TextStyle(color: CriptivoColors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPendingImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined,
                    color: CriptivoColors.neon),
                title: const Text('Видео',
                    style: TextStyle(color: CriptivoColors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPendingVideo();
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file,
                    color: CriptivoColors.neon),
                title: const Text('Файл',
                    style: TextStyle(color: CriptivoColors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPendingFile();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _sealTimer?.cancel();
    _pollTimer?.cancel();
    _expireTimer?.cancel();
    _channel?.unsubscribe();
    _scrollHelper.dispose();
    _typingService?.dispose();
    _voiceRecorder?.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CriptivoColors.surfaceLight,
              border: Border.all(
                color: CriptivoColors.neon.withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              size: 36,
              color: CriptivoColors.neon,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Защитен разговор',
            style: TextStyle(
              color: CriptivoColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Съобщенията са end-to-end криптирани.\nНапиши първото.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CriptivoColors.textSecondary.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final isMe = msg['is_me'] == true;
    final time = _formatTime(msg['created_at']);
    final text = msg['text'] ?? '';
    final isRead = msg['read_at'] != null;
    final media = msg['media'] as Map<String, dynamic>?;
    final reactions =
        (msg['reactions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final messageId = msg['id'] as String? ?? '';
    final expireLabel = _expireLabel(msg['expires_at']);

    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        bottom: 4,
        left: isMe ? 48 : 8,
        right: isMe ? 8 : 48,
      ),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _onBubbleLongPress(msg),
            child: Container(
              padding: media != null && media['type'] == 'image'
                  ? const EdgeInsets.all(6)
                  : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: isMe
                    ? LinearGradient(
                        colors: [
                          CriptivoColors.bubbleMe,
                          CriptivoColors.bubbleMe.withValues(alpha: 0.85),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isMe ? null : CriptivoColors.bubbleOther,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                border: Border.all(
                  color: isMe
                      ? CriptivoColors.neon.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.06),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: media != null && media['type'] == 'image'
                  ? _MediaImageThumb(media: media)
                  : Text(
                      text,
                      style: const TextStyle(
                        color: CriptivoColors.textPrimary,
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
            ),
          ),
          ReactionBar(
            aggregated: reactions,
            onToggle: (emoji) => _toggleReaction(messageId, emoji),
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (time.isNotEmpty)
                  Text(
                    time,
                    style: TextStyle(
                      color:
                          CriptivoColors.textSecondary.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                if (expireLabel != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    expireLabel,
                    style: TextStyle(
                      color: CriptivoColors.neon.withValues(alpha: 0.85),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isRead ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 14,
                    color: isRead
                        ? CriptivoColors.neon
                        : CriptivoColors.textSecondary.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _sending || _uploadingMedia;

    return Scaffold(
      backgroundColor: CriptivoColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Text(_otherName, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            GlagoliticSealBadge(
              glyph: _sealGlyph,
              onLongPress: _showSafetyNumber,
              size: 24,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _disappearSeconds != null
                  ? Icons.timer_rounded
                  : Icons.timer_off_outlined,
              color: _disappearSeconds != null ? CriptivoColors.neon : null,
            ),
            tooltip: 'Изчезващи съобщения',
            onPressed: _showDisappearSheet,
          ),
          IconButton(
            icon: const Icon(Icons.verified_user_outlined),
            tooltip: 'Safety Number',
            onPressed: _showSafetyNumber,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обнови',
            onPressed: () async {
              await _refreshTheirPublicKey();
              await _updateSeal();
              await _loadConversationMeta();
              await _loadMessages();
              await ChatService.markMessagesAsRead(widget.conversationId);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/chat_background.png',
              fit: BoxFit.cover,
              opacity: const AlwaysStoppedAnimation(0.30),
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          Positioned.fill(
            child: Container(
              color: CriptivoColors.background.withValues(alpha: 0.55),
            ),
          ),
          Column(
            children: [
              if (_error != null)
                MaterialBanner(
                  content: Text(_error!),
                  backgroundColor: CriptivoColors.surfaceLight,
                  actions: [
                    TextButton(
                      onPressed: () => setState(() => _error = null),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              if (_disappearSeconds != null)
                Material(
                  color: CriptivoColors.surfaceLight.withValues(alpha: 0.9),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_rounded,
                            size: 16, color: CriptivoColors.neon),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Изчезващи съобщения: включени',
                            style: TextStyle(
                              color: CriptivoColors.textSecondary
                                  .withValues(alpha: 0.95),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: CriptivoColors.neon,
                            ),
                          )
                        : _messages.isEmpty
                            ? _buildEmptyState()
                            : ListView.builder(
                                controller: _scrollController,
                                padding:
                                    const EdgeInsets.fromLTRB(4, 12, 4, 8),
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  return _buildMessageBubble(
                                      _messages[index]);
                                },
                              ),
                    if (_scrollHelper.showButton)
                      Positioned(
                        right: 16,
                        bottom: 12,
                        child: ScrollToBottomButton(
                          unreadCount: _scrollHelper.unreadWhileAway,
                          onTap: () => _scrollHelper.scrollToBottom(),
                        ),
                      ),
                  ],
                ),
              ),
              TypingIndicator(name: _otherName, visible: _peerTyping),
              ChatInputBar(
                controller: _controller,
                focusNode: _focusNode,
                busy: busy,
                showEmojiPicker: _showEmojiPicker,
                hasText: _hasText,
                pending: _pending,
                recorder: _voiceRecorder,
                onAttach: _showAttachSheet,
                onToggleEmoji: _toggleEmojiPicker,
                onSend: _sendOrPending,
                onChanged: (v) {
                  setState(() => _hasText = v.trim().isNotEmpty);
                  _typingService?.onTextChanged(v);
                },
                onClearPending: () => setState(() => _pending = null),
                onVoiceRecorded: _onVoiceRecorded,
              ),
              if (_showEmojiPicker)
                ChatEmojiPanel(
                  onEmojiSelected: _onEmojiSelected,
                  onBackspace: _onEmojiBackspace,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaImageThumb extends StatefulWidget {
  final Map<String, dynamic> media;

  const _MediaImageThumb({required this.media});

  @override
  State<_MediaImageThumb> createState() => _MediaImageThumbState();
}

class _MediaImageThumbState extends State<_MediaImageThumb> {
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await MediaService.downloadAndDecrypt(
        url: widget.media['url'] as String,
        keyBase64: widget.media['key'] as String,
        nonceBase64: widget.media['nonce'] as String,
      );
      if (!mounted) return;
      setState(() {
        _bytes = Uint8List.fromList(bytes);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не може да се зареди';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 160,
        height: 120,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: CriptivoColors.neon,
          ),
        ),
      );
    }
    if (_error != null || _bytes == null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          _error ?? '🖼️',
          style: const TextStyle(color: CriptivoColors.textSecondary),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        _bytes!,
        width: 220,
        fit: BoxFit.cover,
      ),
    );
  }
}
