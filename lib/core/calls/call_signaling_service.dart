import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import 'call_models.dart';

/// Сигнализация за 1:1 разговори.
/// Каналът е private, а достъпът се ограничава и чрез Supabase RLS.
/// През него се изпращат само control съобщения, SDP и ICE —
/// никога аудио/видео потоци или лични съобщения.
class CallSignalingService {
  CallSignalingService({required this.conversationId, required this.onSignal});

  final String conversationId;
  final void Function(CallSignal signal) onSignal;

  static final SupabaseClient _supabase = Supabase.instance.client;

  static const Duration _subscribeTimeout = Duration(seconds: 15);

  RealtimeChannel? _channel;
  bool _joined = false;
  bool _starting = false;

  String? _myId;
  Set<String> _participantIds = {};

  String get _topic => 'call:$conversationId';

  Future<void> start() async {
    if (_joined) return;

    // Изчакваме евентуален текущ опит за свързване.
    while (_starting) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      if (_joined) return;
    }

    _starting = true;

    RealtimeChannel? channel;

    try {
      final myId = AuthService.currentUser?.id;

      if (myId == null) {
        throw StateError('Трябва да си влязъл в акаунта.');
      }

      // Проверка в приложението — допълнителна защита,
      // но не замества RLS политиките в Supabase.
      final conversation = await _supabase
          .from('conversations')
          .select('participant_1, participant_2')
          .eq('id', conversationId)
          .maybeSingle();

      if (conversation == null) {
        throw StateError('Разговорът не беше намерен.');
      }

      final p1 = conversation['participant_1']?.toString();
      final p2 = conversation['participant_2']?.toString();

      final participants = <String>{
        if (p1 != null && p1.isNotEmpty) p1,
        if (p2 != null && p2.isNotEmpty) p2,
      };

      if (!participants.contains(myId) || participants.length != 2) {
        throw StateError('Нямаш право да участваш в този разговор.');
      }

      _myId = myId;
      _participantIds = participants;

      channel = _supabase.channel(
        _topic,
        opts: const RealtimeChannelConfig(self: false, private: true),
      );

      channel.onBroadcast(
        event: 'signal',
        callback: (payload) {
          try {
            final raw = payload['payload'] ?? payload;
            final signal = CallSignal.tryParse(raw);

            if (signal == null) return;

            // Проверки за невалидни и несвързани сигнали.
            if (signal.conversationId != conversationId) return;
            if (signal.fromUserId == _myId) return;
            if (!_participantIds.contains(signal.fromUserId)) return;

            onSignal(signal);
          } catch (e) {
            debugPrint('Call signal parse error: $e');
          }
        },
      );

      _channel = channel;

      // subscribe() връща RealtimeChannel, а не статуса на абониране.
      // Реалният статус пристига чрез callback.
      final subscribed = Completer<void>();

      channel.subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (!subscribed.isCompleted) {
            subscribed.complete();
          }
          return;
        }

        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.closed) {
          if (!subscribed.isCompleted) {
            subscribed.completeError(
              StateError(
                'Абонирането за защитения канал се провали '
                '($status)${error == null ? '' : ': $error'}',
              ),
            );
          }
        }
      });

      try {
        await subscribed.future.timeout(_subscribeTimeout);
      } on TimeoutException {
        throw StateError(
          'Изтече времето за свързване със защитения канал за разговори.',
        );
      } catch (_) {
        throw StateError(
          'Защитеният канал за разговори не можа да бъде отворен.',
        );
      }

      _joined = true;
      debugPrint('Private call signaling channel connected.');
    } catch (_) {
      _joined = false;
      _myId = null;
      _participantIds = {};

      if (channel != null) {
        try {
          await _supabase.removeChannel(channel);
        } catch (cleanupError) {
          debugPrint('Call signaling cleanup failed: $cleanupError');
        }

        if (identical(_channel, channel)) {
          _channel = null;
        }
      }

      rethrow;
    } finally {
      _starting = false;
    }
  }

  Future<void> send(CallSignal signal) async {
    final channel = _channel;
    final myId = _myId;

    if (!_joined || channel == null || myId == null) {
      throw StateError('Защитеният канал за разговори не е готов.');
    }

    if (signal.conversationId != conversationId ||
        signal.fromUserId != myId ||
        !_participantIds.contains(myId)) {
      throw StateError('Сигналът не съответства на текущия разговор.');
    }

    await channel.sendBroadcastMessage(
      event: 'signal',
      payload: signal.toJson(),
    );
  }

  Future<void> dispose() async {
    final channel = _channel;

    _channel = null;
    _joined = false;
    _myId = null;
    _participantIds = {};

    if (channel != null) {
      try {
        await _supabase.removeChannel(channel);
      } catch (e) {
        debugPrint('Call signaling cleanup failed: $e');
      }
    }
  }
}
