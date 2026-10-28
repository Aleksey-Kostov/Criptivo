part of 'chat_page.dart';

extension _ChatPageLifecycle on _ChatPageState {
  Future<void> _initChat() async {
    try {
      // Fail closed: the chat must not use a stale peer public key.
      await _refreshTheirPublicKey();
      if (!mounted) return;

      await _loadConversationMeta();
      if (!mounted) return;

      final theirKey = _theirPublicKey;
      if (theirKey != null && theirKey.isNotEmpty) {
        await _startSeal();
      }

      await _loadMessages();
      if (!mounted) return;

      await ChatService.markMessagesAsRead(widget.conversationId);
      if (!mounted) return;

      _subscribeToMessages();
      _startPollFallback();
      _startExpireWatcher();

      final uid = AuthService.currentUser?.id;

      if (uid != null) {
        _typingService = TypingService(
          conversationId: widget.conversationId,
          myUserId: uid,
          onPeerTypingChanged: (typing) {
            if (!mounted) return;

            _safeSetState(() {
              _peerTyping = typing;
            });
          },
        )..start();
      }

      if (!mounted) return;

      _safeSetState(() {
        _error = null;
        _loading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Chat initialization failed: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      _safeSetState(() {
        _theirPublicKey = null;
        _error = 'Чатът не можа да бъде зареден. Провери връзката и ключовете и опитай отново.';
        _loading = false;
      });
    }
  }

  Future<void> _refreshTheirPublicKey() async {
    final otherId = _otherUserId;

    // Clear the old key first so it cannot be reused if refresh fails.
    if (mounted) {
      _safeSetState(() {
        _theirPublicKey = null;
      });
    }

    if (otherId == null || otherId.isEmpty) {
      throw StateError(
        'Cannot verify the peer public key: the peer user ID is missing.',
      );
    }

    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('public_key')
          .eq('id', otherId)
          .maybeSingle();

      if (!mounted) return;

      final rawKey = row?['public_key'];
      final publicKey = rawKey is String ? rawKey.trim() : '';

      if (publicKey.isEmpty) {
        throw StateError('The peer profile does not have a valid public key.');
      }

      _safeSetState(() {
        _theirPublicKey = publicKey;
      });
    } catch (e) {
      debugPrint('Failed to refresh peer public key: $e');

      if (mounted) {
        _safeSetState(() {
          _theirPublicKey = null;
        });
      }

      rethrow;
    }
  }

  Future<void> _loadConversationMeta() async {
    try {
      final row = await Supabase.instance.client
          .from('conversations')
          .select('created_at, disappear_seconds')
          .eq('id', widget.conversationId)
          .maybeSingle();

      if (row == null) {
        _conversationCreatedAt ??= DateTime.now().toUtc();

        if (mounted) {
          _safeSetState(() {
            _disappearSeconds = null;
          });
        }

        return;
      }

      final createdAt = row['created_at'];
      final parsedCreatedAt = createdAt == null
          ? DateTime.now().toUtc()
          : DateTime.parse(createdAt.toString()).toUtc();

      final rawSeconds = row['disappear_seconds'];
      final seconds = rawSeconds is int
          ? rawSeconds
          : rawSeconds is num
          ? rawSeconds.toInt()
          : null;

      _conversationCreatedAt = parsedCreatedAt;

      if (!mounted) return;

      _safeSetState(() {
        _disappearSeconds = seconds;
      });
    } catch (e) {
      debugPrint('Conversation metadata load failed: $e');
      _conversationCreatedAt ??= DateTime.now().toUtc();
    }
  }

  void _startExpireWatcher() {
    _expireTimer?.cancel();

    _expireTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _messages.isEmpty) return;

      final now = DateTime.now().toUtc();
      final previousLength = _messages.length;

      _messages.removeWhere((message) {
        final expiresAt = message['expires_at'];

        if (expiresAt == null) return false;

        try {
          final expiry = DateTime.parse(expiresAt.toString()).toUtc();
          return !expiry.isAfter(now);
        } catch (e) {
          debugPrint('Invalid message expiry timestamp: $e');
          return false;
        }
      });

      if (_messages.length != previousLength && mounted) {
        _safeSetState(() {});
      }
    });
  }

  Future<void> _showDisappearSheet() async {
    if (!mounted) return;

    _safeSetState(() {
      _showEmojiPicker = false;
    });

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: CriptivoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
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
              for (final option in _ChatPageState._disappearOptions)
                ListTile(
                  title: Text(
                    option.$1,
                    style: const TextStyle(color: CriptivoColors.textPrimary),
                  ),
                  trailing: _disappearSeconds == option.$2
                      ? const Icon(
                          Icons.check_rounded,
                          color: CriptivoColors.neon,
                        )
                      : null,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();

                    try {
                      await ChatService.setDisappearSeconds(
                        conversationId: widget.conversationId,
                        seconds: option.$2,
                      );

                      if (!mounted) return;

                      _safeSetState(() {
                        _disappearSeconds = option.$2;
                      });
                    } catch (e) {
                      debugPrint('Failed to update disappearing messages: $e');

                      if (!mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Неуспешна промяна на настройката.'),
                        ),
                      );
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

    if (!mounted) return;

    _sealTimer?.cancel();

    _sealTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        _updateSeal();
      }
    });
  }

  Future<void> _updateSeal() async {
    final theirKey = _theirPublicKey;
    final conversationCreatedAt = _conversationCreatedAt;

    if (theirKey == null || theirKey.isEmpty || conversationCreatedAt == null) {
      return;
    }

    try {
      final sessionSecret = await MessageCrypto.sessionSecretBytes(
        theirPublicKeyBase64: theirKey,
      );

      final seal = GlagoliticSeal(
        sessionSecret: sessionSecret,
        conversationId: widget.conversationId,
      );

      final glyph = await seal.currentGlyph(
        conversationCreatedAt: conversationCreatedAt,
      );

      if (!mounted) return;

      // Do not display a result calculated with a key that changed
      // while the asynchronous operation was running.
      if (_theirPublicKey != theirKey ||
          _conversationCreatedAt != conversationCreatedAt) {
        return;
      }

      _safeSetState(() {
        _sealGlyph = glyph;
      });
    } catch (e) {
      debugPrint('Glagolitic Seal update failed: $e');
    }
  }
}
