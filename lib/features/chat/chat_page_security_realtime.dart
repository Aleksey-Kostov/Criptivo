part of 'chat_page.dart';

extension _ChatPageSecurityRealtime on _ChatPageState {
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

    showModalBottomSheet<void>(
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

              if (!mounted) return;

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

            _safeSetState(() => _messages.add(msg));

            await _rememberPreview(
              plaintext: plaintext,
              isMe: false,
              messageId: row['id']?.toString(),
              createdAt: row['created_at'],
            );

            if (!mounted) return;

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

            if (i == -1 || !mounted) return;

            _safeSetState(() {
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
      if (!mounted) return;

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
        _safeSetState(() => _messages = decrypted);

        if (decrypted.isNotEmpty) {
          final last = decrypted.last;

          await _rememberPreview(
            plaintext:
                last['plaintext_raw'] as String? ??
                last['text'] as String? ??
                '',
            isMe: last['is_me'] == true,
            messageId: last['id']?.toString(),
            createdAt: last['created_at'],
          );
        }

        if (!mounted) return;

        if (grew) {
          _scrollHelper.onIncomingMessage();
        }
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
    if (!mounted) return;

    _safeSetState(() {
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

      _safeSetState(() {
        _messages = decrypted;
        _loading = false;
      });

      if (decrypted.isNotEmpty) {
        final last = decrypted.last;
        final raw =
            last['plaintext_raw'] as String? ?? last['text'] as String? ?? '';

        await _rememberPreview(
          plaintext: raw,
          isMe: last['is_me'] == true,
          messageId: last['id']?.toString(),
          createdAt: last['created_at'],
        );
      }

      if (!mounted) return;

      _scrollHelper.scrollToBottom();
    } catch (e) {
      if (!mounted) return;

      _safeSetState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── Send ─────────────────────────────────────
}
