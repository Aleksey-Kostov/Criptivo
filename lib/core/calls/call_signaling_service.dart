import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import 'call_models.dart';

/// Ephemeral signaling през Supabase Realtime broadcast.
/// Медията НЕ минава оттук — само SDP / ICE / control.
class CallSignalingService {
  CallSignalingService({
    required this.conversationId,
    required this.onSignal,
  });

  final String conversationId;
  final void Function(CallSignal signal) onSignal;

  RealtimeChannel? _channel;
  bool _joined = false;

  static final _supabase = Supabase.instance.client;

  String get _topic => 'call:$conversationId';

  Future<void> start() async {
    if (_joined) return;
    final myId = AuthService.currentUser?.id;
    if (myId == null) {
      throw StateError('Call signaling: not authenticated');
    }

    _channel = _supabase.channel(
      _topic,
      opts: const RealtimeChannelConfig(self: false),
    );

    _channel!.onBroadcast(
      event: 'signal',
      callback: (payload) {
        try {
          final raw = payload['payload'] ?? payload;
          final signal = CallSignal.tryParse(raw);
          if (signal == null) return;
          // Игнорирай собствените (self: false помага, но double-check)
          if (signal.fromUserId == myId) return;
          if (signal.conversationId != conversationId) return;
          onSignal(signal);
        } catch (e) {
          debugPrint('Call signal parse error: $e');
        }
      },
    );

    final status = await _channel!.subscribe();
    _joined = status == RealtimeSubscribeStatus.subscribed;
    debugPrint('Call signaling $_topic → $status');
  }

  Future<void> send(CallSignal signal) async {
    final ch = _channel;
    if (ch == null || !_joined) {
      debugPrint('Call signaling not ready, drop ${signal.type}');
      return;
    }
    await ch.sendBroadcastMessage(
      event: 'signal',
      payload: signal.toJson(),
    );
  }

  Future<void> dispose() async {
    final ch = _channel;
    _channel = null;
    _joined = false;
    if (ch != null) {
      try {
        await _supabase.removeChannel(ch);
      } catch (e) {
        debugPrint('Call signaling dispose: $e');
      }
    }
  }
}