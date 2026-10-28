part of 'chat_page.dart';

extension _ChatPageComposer on _ChatPageState {
  Future<void> _sendOrPending() async {
    if (_pending != null) {
      await _sendPending();
      return;
    }
    await _send();
  }

  String _composePlaintext(String text) {
    final reply = _replyTo;
    if (reply == null) return text;

    return jsonEncode({
      't': 'text',
      'body': text,
      'reply_to': reply.messageId,
      'reply_preview': reply.previewText,
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending || _uploadingMedia) return;

    String? tempId;

    _safeSetState(() {
      _sending = true;
      _error = null;
      _showEmojiPicker = false;
    });

    await _typingService?.setTyping(false);

    try {
      // Verify the current peer key before preparing the message.
      await _refreshTheirPublicKey();
      if (!mounted) return;

      final theirKey = _theirPublicKey;
      if (theirKey == null || theirKey.isEmpty) {
        throw StateError('Другият потребител няма потвърден публичен ключ.');
      }

      final replyAtSend = _replyTo;
      final plaintext = _composePlaintext(text);
      final replyPreview = replyAtSend?.previewText;

      tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';

      _safeSetState(() {
        _messages.add({
          'id': tempId,
          'text': text,
          'plaintext_raw': plaintext,
          'is_me': true,
          'sender_id': AuthService.currentUser?.id,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'read_at': null,
          'media': null,
          'reply_preview': replyPreview,
          'reactions': <Map<String, dynamic>>[],
        });
      });

      _scrollHelper.scrollToBottom();

      final inserted = await ChatService.sendEncryptedMessage(
        conversationId: widget.conversationId,
        plaintext: plaintext,
        theirPublicKeyBase64: theirKey,
      );

      if (!mounted) return;

      _safeSetState(() {
        final i = _messages.indexWhere((m) => m['id'] == tempId);

        if (i != -1) {
          _messages[i] = {
            ...inserted,
            'text': text,
            'plaintext_raw': plaintext,
            'is_me': true,
            'media': null,
            'reply_preview': replyPreview,
            'reactions': <Map<String, dynamic>>[],
          };
        }

        // Clear only the text that was actually sent. If the user typed
        // something else while the request was running, preserve it.
        if (_controller.text.trim() == text) {
          _controller.clear();
          _hasText = false;
        }

        // Do not clear a newer reply selection.
        if (identical(_replyTo, replyAtSend)) {
          _replyTo = null;
        }
      });

      _scrollHelper.scrollToBottom();

      try {
        await _rememberPreview(
          plaintext: plaintext,
          isMe: true,
          messageId: inserted['id']?.toString(),
          createdAt: inserted['created_at'],
        );
      } catch (e) {
        // The message was sent successfully. A preview failure must not
        // make the send appear to have failed or encourage duplicate sends.
        debugPrint('Failed to remember sent message preview: $e');
      }
    } catch (e, stackTrace) {
      debugPrint('Message send failed: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      _safeSetState(() {
        if (tempId != null) {
          _messages.removeWhere((m) => m['id'] == tempId);
        }

        // Keep the text and reply selection so the user can retry.
        _error = 'Грешка при изпращане: $e';
        _hasText = _controller.text.trim().isNotEmpty;
      });
    } finally {
      if (mounted) {
        _safeSetState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _sendPending() async {
    final p = _pending;
    if (p == null || _sending || _uploadingMedia) return;

    String? tempId;

    _safeSetState(() {
      _uploadingMedia = true;
      _error = null;
      _showEmojiPicker = false;
    });

    try {
      // Verify the peer key before uploading media.
      await _refreshTheirPublicKey();
      if (!mounted) return;

      final theirKey = _theirPublicKey;
      if (theirKey == null || theirKey.isEmpty) {
        throw StateError('Другият потребител няма потвърден публичен ключ.');
      }

      final ref = await p.upload();
      if (!mounted) return;

      final media = MediaCrypto.tryParseEnvelope(ref.envelopeJson);
      final preview = _displayFromPlaintext(ref.envelopeJson);

      tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';

      _safeSetState(() {
        _messages.add({
          'id': tempId,
          'text': preview,
          'plaintext_raw': ref.envelopeJson,
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

      _safeSetState(() {
        final i = _messages.indexWhere((m) => m['id'] == tempId);

        if (i != -1) {
          _messages[i] = {
            ...inserted,
            'text': preview,
            'plaintext_raw': ref.envelopeJson,
            'is_me': true,
            'media': media,
            'reactions': <Map<String, dynamic>>[],
          };
        }

        // Remove the attachment from the composer only after the message
        // has been accepted by the message service.
        if (identical(_pending, p)) {
          _pending = null;
        }
      });

      _scrollHelper.scrollToBottom();

      try {
        await _rememberPreview(
          plaintext: ref.envelopeJson,
          isMe: true,
          messageId: inserted['id']?.toString(),
          createdAt: inserted['created_at'],
        );
      } catch (e) {
        debugPrint('Failed to remember media message preview: $e');
      }
    } catch (e, stackTrace) {
      debugPrint('Media send failed: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      _safeSetState(() {
        if (tempId != null) {
          _messages.removeWhere((m) => m['id'] == tempId);
        }

        // Keep the pending attachment so the user can retry.
        _error = 'Медия: $e';
      });
    } finally {
      if (mounted) {
        _safeSetState(() {
          _uploadingMedia = false;
        });
      }
    }
  }

  Future<void> _onVoiceRecorded(VoiceRecording rec) async {
    if (_sending || _uploadingMedia) return;

    String? tempId;

    _safeSetState(() {
      _uploadingMedia = true;
      _error = null;
    });

    try {
      // Verify the peer key before uploading the voice recording.
      await _refreshTheirPublicKey();
      if (!mounted) return;

      final theirKey = _theirPublicKey;
      if (theirKey == null || theirKey.isEmpty) {
        throw StateError('Другият потребител няма потвърден публичен ключ.');
      }

      final uploaded = await MediaService.uploadVoiceFile(
        filePath: rec.filePath,
        durationMs: rec.durationMs,
      );

      if (uploaded == null || !mounted) return;

      final media = MediaCrypto.tryParseEnvelope(uploaded.envelopeJson);
      final preview = _displayFromPlaintext(uploaded.envelopeJson);

      tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';

      _safeSetState(() {
        _messages.add({
          'id': tempId,
          'text': preview,
          'plaintext_raw': uploaded.envelopeJson,
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

      _safeSetState(() {
        final i = _messages.indexWhere((m) => m['id'] == tempId);

        if (i != -1) {
          _messages[i] = {
            ...inserted,
            'text': preview,
            'plaintext_raw': uploaded.envelopeJson,
            'is_me': true,
            'media': media,
            'reactions': <Map<String, dynamic>>[],
          };
        }
      });

      _scrollHelper.scrollToBottom();

      try {
        await _rememberPreview(
          plaintext: uploaded.envelopeJson,
          isMe: true,
          messageId: inserted['id']?.toString(),
          createdAt: inserted['created_at'],
        );
      } catch (e) {
        debugPrint('Failed to remember voice message preview: $e');
      }
    } catch (e, stackTrace) {
      debugPrint('Voice message send failed: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        _safeSetState(() {
          if (tempId != null) {
            _messages.removeWhere((m) => m['id'] == tempId);
          }

          _error = 'Глас: $e';
        });
      }
    } finally {
      if (mounted) {
        _safeSetState(() {
          _uploadingMedia = false;
        });
      }
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

    _safeSetState(() {
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
      if (picked == null || !mounted) return;

      _setPendingBytes(
        bytes: picked.bytes,
        name: picked.name,
        mime: picked.mime,
        kind: 'image',
        imageBytes: Uint8List.fromList(picked.bytes),
      );
    } catch (e) {
      if (mounted) {
        _safeSetState(() => _error = e.toString());
      }
    }
  }

  Future<void> _pickPendingVideo() async {
    try {
      final picked = await MediaService.pickVideoLocal();
      if (picked == null || !mounted) return;

      _setPendingBytes(
        bytes: picked.bytes,
        name: picked.name,
        mime: picked.mime,
        kind: 'video',
      );
    } catch (e) {
      if (mounted) {
        _safeSetState(() => _error = e.toString());
      }
    }
  }

  Future<void> _pickPendingFile() async {
    try {
      final picked = await MediaService.pickFileLocal();
      if (picked == null || !mounted) return;

      _setPendingBytes(
        bytes: picked.bytes,
        name: picked.name,
        mime: picked.mime,
        kind: 'file',
      );
    } catch (e) {
      if (mounted) {
        _safeSetState(() => _error = e.toString());
      }
    }
  }

  void _showAttachSheet() {
    if (!mounted) return;

    _safeSetState(() => _showEmojiPicker = false);

    showModalBottomSheet<void>(
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
                leading: const Icon(
                  Icons.photo_outlined,
                  color: CriptivoColors.neon,
                ),
                title: const Text(
                  'Снимка',
                  style: TextStyle(color: CriptivoColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPendingImage();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.videocam_outlined,
                  color: CriptivoColors.neon,
                ),
                title: const Text(
                  'Видео',
                  style: TextStyle(color: CriptivoColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPendingVideo();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.attach_file,
                  color: CriptivoColors.neon,
                ),
                title: const Text(
                  'Файл',
                  style: TextStyle(color: CriptivoColors.textPrimary),
                ),
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
}
