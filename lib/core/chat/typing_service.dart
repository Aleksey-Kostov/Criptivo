import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Ефимерен typing през Realtime Broadcast (без таблица).
class TypingService {
  TypingService({
    required this.conversationId,
    required this.myUserId,
    required this.onPeerTypingChanged,
  });

  final String conversationId;
  final String myUserId;
  final void Function(bool typing) onPeerTypingChanged;

  RealtimeChannel? _channel;
  Timer? _debounce;
  Timer? _peerExpire;
  bool _iAmTyping = false;

  void start() {
    _channel = Supabase.instance.client
        .channel('typing:$conversationId')
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final uid = payload['user_id'] as String?;
            final typing = payload['typing'] == true;
            if (uid == null || uid == myUserId) return;

            onPeerTypingChanged(typing);
            _peerExpire?.cancel();
            if (typing) {
              _peerExpire = Timer(const Duration(seconds: 3), () {
                onPeerTypingChanged(false);
              });
            }
          },
        )
        .subscribe();
  }

  void onTextChanged(String text) {
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      setTyping(false);
      return;
    }
    setTyping(true);
    _debounce = Timer(const Duration(milliseconds: 1600), () {
      setTyping(false);
    });
  }

  Future<void> setTyping(bool typing) async {
    if (_iAmTyping == typing) return;
    _iAmTyping = typing;
    try {
      await _channel?.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': myUserId, 'typing': typing},
      );
    } catch (_) {}
  }

  void dispose() {
    _debounce?.cancel();
    _peerExpire?.cancel();
    unawaited(setTyping(false));
    _channel?.unsubscribe();
    _channel = null;
  }
}
