part of 'chat_page.dart';

extension _ChatPageMessageHelpers on _ChatPageState {
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

  Future<void> _rememberPreview({
    required String plaintext,
    required bool isMe,
    String? messageId,
    dynamic createdAt,
  }) async {
    DateTime? at;

    if (createdAt != null) {
      try {
        at = createdAt is DateTime
            ? createdAt.toUtc()
            : DateTime.parse(createdAt.toString()).toUtc();
      } catch (_) {}
    }

    try {
      await ConversationPreviewStore.save(
        conversationId: widget.conversationId,
        plaintext: plaintext,
        isMe: isMe,
        messageId: messageId,
        at: at,
      );
    } catch (e) {
      // Preview storage must not break message sending/receiving.
      debugPrint('Conversation preview save error: $e');
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

    if (media != null) {
      final name = media['name'] as String? ?? '';

      return switch (media['type']) {
        'image' => '🖼️ ${name.isEmpty ? 'снимка' : name}',
        'video' => '🎬 ${name.isEmpty ? 'видео' : name}',
        'audio' => '🎵 ${name.isEmpty ? 'аудио' : name}',
        'gif' => 'GIF',
        _ => '📎 ${name.isEmpty ? 'файл' : name}',
      };
    }

    // Reply JSON envelope
    try {
      final map = jsonDecode(plaintext);

      if (map is Map && map['t'] == 'text' && map['body'] is String) {
        return map['body'] as String;
      }
    } catch (_) {}

    return plaintext;
  }

  Map<String, dynamic> _messageFromPlaintext(
    Map<String, dynamic> row,
    String plaintext,
    bool isMe,
  ) {
    final media = MediaCrypto.tryParseEnvelope(plaintext);
    String? replyPreview;
    String? replyToId;

    if (media == null) {
      try {
        final map = jsonDecode(plaintext);

        if (map is Map && map['t'] == 'text') {
          replyPreview = map['reply_preview'] as String?;
          replyToId = map['reply_to'] as String?;
        }
      } catch (_) {}
    }

    return {
      ...row,
      'text': _displayFromPlaintext(plaintext),
      'plaintext_raw': plaintext,
      'is_me': isMe,
      'media': media,
      'reply_preview': replyPreview,
      'reply_to': replyToId,
      'reactions': <Map<String, dynamic>>[],
      'reactions_raw': <Map<String, dynamic>>[],
    };
  }

  // ── Emoji ────────────────────────────────────

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      _safeSetState(() => _showEmojiPicker = false);
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      _safeSetState(() => _showEmojiPicker = true);
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

    _safeSetState(() => _hasText = newText.trim().isNotEmpty);
  }

  void _onEmojiBackspace() {
    final text = _controller.text;
    if (text.isEmpty) return;

    final newText = text.characters.skipLast(1).toString();

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );

    _safeSetState(() => _hasText = newText.trim().isNotEmpty);
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

      _safeSetState(() {
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

    final text = (msg['text'] as String?) ?? '';
    final media = msg['media'] as Map<String, dynamic>?;
    final isMe = msg['is_me'] == true;

    await MessageActionsSheet.show(
      context,
      plaintextDisplay: text,
      media: media,
      isMe: isMe,
      onAction: (action) async {
        switch (action) {
          case MessageAction.reply:
            if (!mounted) return;

            _safeSetState(() {
              _replyTo = ReplyTarget(
                messageId: id,
                previewText: text,
                isMe: isMe,
              );
            });
            _focusNode.requestFocus();
            break;

          case MessageAction.copy:
            await MessageActionHandlers.copyText(text);

            if (mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Копирано')));
            }
            break;

          case MessageAction.share:
            if (media != null) {
              await MessageActionHandlers.shareOrDownloadMedia(
                media,
                share: true,
              );
            } else {
              await MessageActionHandlers.shareText(text);
            }
            break;

          case MessageAction.download:
            if (media != null) {
              try {
                final file = await MediaLocalCache.getDecryptedFile(
                  url: media['url'] as String,
                  keyBase64: media['key'] as String,
                  nonceBase64: media['nonce'] as String,
                  preferredName: media['name'] as String? ?? 'file',
                );

                await OpenFilex.open(file.path);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Грешка при отваряне на файла: $e')),
                  );
                }
              }
            }
            break;

          case MessageAction.viewOnceInfo:
            break;
        }
      },
    );

    // Quick react also available:
    // final emoji = await showReactionPicker(context);
  }

  Future<void> _refreshReactionsForMessage(String messageId) async {
    final map = await ReactionService.getForMessages([messageId]);
    final rows = map[messageId] ?? [];

    if (!mounted) return;

    _safeSetState(() {
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
}
