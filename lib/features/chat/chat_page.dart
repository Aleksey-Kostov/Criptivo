import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_service.dart';
import '../../core/chat/chat_service.dart';
import '../../core/crypto/glagolitic_seal.dart';
import '../../core/crypto/key_manager.dart';
import '../../core/crypto/message_crypto.dart';
import '../../core/crypto/safety_number.dart';
import '../../core/theme/criptivo_theme.dart';
import 'widgets/glagolitic_seal_badge.dart';

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

  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String? _theirPublicKey;

  RealtimeChannel? _channel;
  Timer? _sealTimer;
  Timer? _pollTimer;

  String _sealGlyph = '·';
  DateTime? _conversationCreatedAt;

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
    _initChat();
  }

  Future<void> _initChat() async {
    await _refreshTheirPublicKey();
    await _loadConversationMeta();
    if (_theirPublicKey != null && _theirPublicKey!.isNotEmpty) {
      await _startSeal();
    }
    await _loadMessages();
    _subscribeToMessages();
    _startPollFallback();
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
        _theirPublicKey =
            row?['public_key'] as String? ??
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
          .select('created_at')
          .eq('id', widget.conversationId)
          .maybeSingle();

      if (row != null && row['created_at'] != null) {
        _conversationCreatedAt = DateTime.parse(row['created_at'] as String)
            .toUtc();
      } else {
        _conversationCreatedAt = DateTime.now().toUtc();
      }
    } catch (e) {
      debugPrint('Conversation meta error: $e');
      _conversationCreatedAt = DateTime.now().toUtc();
    }
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

  // ─────────────────────────────────────────────
  // Safety Number
  // ─────────────────────────────────────────────

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Липсва твоят public key')));
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
                  'Ако съвпадат — връзката е защитена и няма man-in-the-middle атака.',
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

  // ─────────────────────────────────────────────
  // Realtime + Polling
  // ─────────────────────────────────────────────

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
            String text;

            try {
              if (_theirPublicKey == null || _theirPublicKey!.isEmpty) {
                await _refreshTheirPublicKey();
              }

              final theirKey = _theirPublicKey;
              if (theirKey == null || theirKey.isEmpty) {
                text = '[липсва ключ]';
              } else {
                text = await MessageCrypto.decrypt(
                  ciphertextBase64: row['ciphertext'] as String,
                  nonceBase64: row['nonce'] as String,
                  theirPublicKeyBase64: theirKey,
                );
              }
            } catch (e) {
              text = '[не може да се декриптира]';
              debugPrint('Realtime decrypt error: $e');
            }

            if (!mounted) return;
            setState(() {
              _messages.add({...row, 'text': text, 'is_me': isMe});
            });
            _scrollToBottom();
          },
        )
        .subscribe((status, [err]) {
          debugPrint('Realtime status: $status err: $err');
        });
  }

  void _startPollFallback() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_loading && !_sending) {
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
        String text;
        try {
          final theirKey = _theirPublicKey;
          if (theirKey == null || theirKey.isEmpty) {
            text = '[липсва ключ]';
          } else {
            text = await MessageCrypto.decrypt(
              ciphertextBase64: row['ciphertext'],
              nonceBase64: row['nonce'],
              theirPublicKeyBase64: theirKey,
            );
          }
        } catch (_) {
          text = '[не може да се декриптира]';
        }
        decrypted.add({...row, 'text': text, 'is_me': isMe});
      }

      if (!mounted) return;
      if (decrypted.length != _messages.length) {
        setState(() => _messages = decrypted);
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Poll error: $e');
    }
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
        String text;

        try {
          final theirKey = _theirPublicKey;
          if (theirKey == null || theirKey.isEmpty) {
            text = '[липсва ключ]';
          } else {
            text = await MessageCrypto.decrypt(
              ciphertextBase64: row['ciphertext'],
              nonceBase64: row['nonce'],
              theirPublicKeyBase64: theirKey,
            );
          }
        } catch (e) {
          text = '[не може да се декриптира]';
          debugPrint('Decrypt error: $e');
        }

        decrypted.add({...row, 'text': text, 'is_me': isMe});
      }

      if (!mounted) return;
      setState(() {
        _messages = decrypted;
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);

    try {
      await _refreshTheirPublicKey();
      await _updateSeal();

      final theirKey = _theirPublicKey;
      if (theirKey == null || theirKey.isEmpty) {
        setState(() => _error = 'Другият потребител няма public key');
        return;
      }

      await ChatService.sendEncryptedMessage(
        conversationId: widget.conversationId,
        plaintext: text,
        theirPublicKeyBase64: theirKey,
      );
      _controller.clear();
      await _loadMessages();
    } catch (e) {
      setState(() => _error = 'Грешка при изпращане: $e');
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _sealTimer?.cancel();
    _pollTimer?.cancel();
    _channel?.unsubscribe();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CriptivoColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(child: Text(_otherName, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            // Жив Glagolitic Seal
            GlagoliticSealBadge(
              glyph: _sealGlyph,
              onLongPress: _showSafetyNumber,
              size: 24,
            ),
          ],
        ),
        actions: [
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
              await _loadMessages();
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
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: CriptivoColors.neon,
                        ),
                      )
                    : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Няма съобщения. Напиши първото.',
                          style: TextStyle(color: CriptivoColors.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg['is_me'] == true;

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? CriptivoColors.bubbleMe
                                    : CriptivoColors.bubbleOther,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isMe
                                      ? CriptivoColors.neon.withValues(
                                          alpha: 0.35,
                                        )
                                      : Colors.white.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Text(
                                msg['text'] ?? '',
                                style: const TextStyle(
                                  color: CriptivoColors.textPrimary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: CriptivoColors.surface.withValues(alpha: 0.92),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: const TextStyle(
                            color: CriptivoColors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Съобщение...',
                            isDense: true,
                          ),
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _sending ? null : _send,
                        color: CriptivoColors.neon,
                        icon: _sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: CriptivoColors.neon,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
