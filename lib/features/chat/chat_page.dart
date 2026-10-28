import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_service.dart';
import '../../core/chat/chat_service.dart';
import '../../core/chat/conversation_preview_store.dart';
import '../../core/chat/link_preview_service.dart';
import '../../core/chat/reaction_service.dart';
import '../../core/chat/typing_service.dart';
import '../../core/chat/voice_recorder_service.dart';
import '../../core/crypto/glagolitic_seal.dart';
import '../../core/crypto/key_manager.dart';
import '../../core/crypto/media_crypto.dart';
import '../../core/crypto/message_crypto.dart';
import '../../core/crypto/safety_number.dart';
import '../../core/crypto/view_once.dart';
import '../../core/storage/media_local_cache.dart';
import '../../core/storage/media_service.dart';
import '../../core/theme/criptivo_theme.dart';
import 'helpers/chat_date_labels.dart';
import 'helpers/chat_scroll_helper.dart';
import 'widgets/attach_preview_strip.dart';
import 'widgets/chat_app_bar.dart';
import 'widgets/chat_background_layer.dart';
import 'widgets/chat_background_picker.dart';
import 'widgets/chat_date_separator.dart';
import 'widgets/chat_emoji_panel.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/ink_preview_card.dart';
import 'widgets/media_message_content.dart';
import 'widgets/message_actions_sheet.dart';
import 'widgets/reaction_bar.dart';
import 'widgets/reaction_picker.dart';
import 'widgets/reply_preview_bar.dart';
import 'widgets/scroll_to_bottom_button.dart';
import 'widgets/typing_indicator.dart';
import 'widgets/view_once_tile.dart';

part 'chat_page_lifecycle.dart';
part 'chat_page_message_helpers.dart';
part 'chat_page_security_realtime.dart';
part 'chat_page_composer.dart';
part 'chat_page_widgets.dart';

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
  ReplyTarget? _replyTo;

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

  /// Обновява състоянието само докато State обектът е монтиран.
  ///
  /// Може да се извиква от extension-ите в part файловете.
  void _safeSetState(VoidCallback callback) {
    if (!mounted) return;
    setState(callback);
  }

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

  @override
  Widget build(BuildContext context) {
    final busy = _sending || _uploadingMedia;
    final entries = buildChatListWithDates(_messages);

    return Scaffold(
      backgroundColor: CriptivoColors.background,
      appBar: ChatAppBar(
        displayName: _otherName,
        username: widget.otherUser['username'] as String?,
        avatarUrl: widget.otherUser['avatar_url'] as String?,
        sealGlyph: _sealGlyph,
        peerTyping: _peerTyping,
        encrypted: _theirPublicKey != null && _theirPublicKey!.isNotEmpty,
        disappearSeconds: _disappearSeconds,
        onSealLongPress: _showSafetyNumber,
        onSafetyNumber: _showSafetyNumber,
        onDisappear: _showDisappearSheet,
        onRefresh: _initChat,
        onOpenProfile: () {
          ChatBackgroundPicker.show(
            context,
            onChanged: () {
              if (mounted) setState(() {});
            },
          );
        },
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: ChatBackgroundLayer()),
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
                    TextButton(
                      onPressed: _initChat,
                      child: const Text('Опитай отново'),
                    ),
                  ],
                ),
              if (_disappearSeconds != null)
                Material(
                  color: CriptivoColors.surfaceLight.withValues(alpha: 0.9),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.timer_rounded,
                          size: 16,
                          color: CriptivoColors.neon,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Изчезващи съобщения: включени',
                            style: TextStyle(
                              color: CriptivoColors.textSecondary.withValues(
                                alpha: 0.95,
                              ),
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
                            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final e = entries[index];
                              return switch (e) {
                                ChatDateSeparatorEntry(:final label) =>
                                  ChatDateSeparator(label: label),
                                ChatMessageEntry(:final message) =>
                                  _buildMessageBubble(message),
                              };
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
              if (_replyTo != null)
                ReplyPreviewBar(
                  target: _replyTo!,
                  onClear: () => setState(() => _replyTo = null),
                ),
              ChatInputBar(
                controller: _controller,
                focusNode: _focusNode,
                busy: busy,
                showEmojiPicker: _showEmojiPicker,
                hasText: _hasText || _replyTo != null,
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
