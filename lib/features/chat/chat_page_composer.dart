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
      final plaintext = _composePlaintext(text);
      final replyPreview = _replyTo?.previewText;
      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      setState(() {
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
        _hasText = false;
        _replyTo = null;
      });
      _controller.clear();
      _scrollHelper.scrollToBottom();
      final inserted = await ChatService.sendEncryptedMessage(
        conversationId: widget.conversationId,
        plaintext: plaintext,
        theirPublicKeyBase64: theirKey,
      );
      if (!mounted) return;
      setState(() {
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
      });
      await _rememberPreview(
        plaintext: plaintext,
        isMe: true,
        messageId: inserted['id']?.toString(),
        createdAt: inserted['created_at'],
      );
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
      setState(() {
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
      });
      await _rememberPreview(
        plaintext: ref.envelopeJson,
        isMe: true,
        messageId: inserted['id']?.toString(),
        createdAt: inserted['created_at'],
      );
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
      setState(() {
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
      await _rememberPreview(
        plaintext: uploaded.envelopeJson,
        isMe: true,
        messageId: inserted['id']?.toString(),
        createdAt: inserted['created_at'],
      );
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
