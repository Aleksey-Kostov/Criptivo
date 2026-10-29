import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';
import 'call_models.dart';

/// Сигнализация за 1:1 разговори.
///
/// Чрез канала се изпращат control съобщения, SDP и ICE кандидати.
/// Аудио и видео потоците не се изпращат през Supabase Broadcast.
///
/// Private каналът и клиентските проверки не заместват правилно
/// конфигурираните Supabase Realtime Authorization/RLS политики.
class CallSignalingService {
  CallSignalingService({required this.conversationId, required this.onSignal});

  final String conversationId;
  final void Function(CallSignal signal) onSignal;

  static final SupabaseClient _supabase = Supabase.instance.client;

  static const Duration _subscribeTimeout = Duration(seconds: 15);

  RealtimeChannel? _channel;
  bool _joined = false;

  bool _disposed = false;

  int _lifecycleGeneration = 0;
  Future<void>? _startFuture;

  String? _myId;
  Set<String> _participantIds = <String>{};

  String get _topic => 'call:$conversationId';

  Future<void> start() async {
    if (_disposed) {
      throw StateError('Услугата за сигнализация вече е затворена.');
    }

    if (_joined) return;

    final existingStart = _startFuture;
    if (existingStart != null) {
      await existingStart;
      if (_joined) return;
    }

    final generation = _lifecycleGeneration;
    final future = _startInternal(generation);

    _startFuture = future;

    try {
      await future;
    } finally {
      if (identical(_startFuture, future)) {
        _startFuture = null;
      }
    }
  }

  Future<void> _startInternal(int generation) async {
    RealtimeChannel? channel;

    try {
      _ensureCurrent(generation);

      final myId = AuthService.currentUser?.id;
      if (myId == null || myId.isEmpty) {
        throw StateError('Трябва да си влязъл в акаунта.');
      }

      if (conversationId.trim().isEmpty) {
        throw StateError('Липсва идентификатор на разговора.');
      }

      // Това е допълнителна проверка в приложението.
      // Реалният контрол на достъпа трябва да се прилага и от сървъра.
      final conversation = await _supabase
          .from('conversations')
          .select('participant_1, participant_2')
          .eq('id', conversationId)
          .maybeSingle();

      _ensureCurrent(generation);

      if (conversation == null) {
        throw StateError('Разговорът не беше намерен.');
      }

      final p1 = conversation['participant_1']?.toString();
      final p2 = conversation['participant_2']?.toString();

      final participants = <String>{
        if (p1 != null && p1.isNotEmpty) p1,
        if (p2 != null && p2.isNotEmpty) p2,
      };

      if (participants.length != 2 || !participants.contains(myId)) {
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
          if (!_isCurrent(generation) ||
              !_joined && !identical(_channel, channel)) {
            return;
          }

          try {
            final raw = payload['payload'] ?? payload;
            final signal = CallSignal.tryParse(raw);

            if (signal == null) return;
            if (signal.conversationId != conversationId) return;
            if (signal.callId.trim().isEmpty) return;

            // Не обработваме собствени съобщения или сигнали от
            // потребител, който не е участник в разговора.
            if (signal.fromUserId == _myId) return;
            if (!_participantIds.contains(signal.fromUserId)) return;

            // SDP/ICE сигналите трябва да носят подходящ payload.
            if (!_hasValidPayload(signal)) return;

            onSignal(signal);
          } catch (error, stackTrace) {
            debugPrint('Call signaling callback failed: $error');
            debugPrintStack(stackTrace: stackTrace);
          }
        },
      );

      _channel = channel;

      final subscribed = Completer<void>();

      channel.subscribe((status, [error]) {
        if (!_isCurrent(generation)) {
          if (!subscribed.isCompleted) {
            subscribed.completeError(StateError('Абонирането е отменено.'));
          }
          return;
        }

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
                'Абонирането за канала се провали: '
                '$status${error == null ? '' : ' — $error'}',
              ),
            );
          }
        }
      });

      try {
        await subscribed.future.timeout(_subscribeTimeout);
      } on TimeoutException {
        throw StateError(
          'Изтече времето за свързване със сигнализационния канал.',
        );
      } catch (error) {
        if (!_isCurrent(generation)) {
          throw StateError('Стартирането на сигнализацията е отменено.');
        }

        if (error is StateError) rethrow;

        throw StateError('Сигнализационният канал не можа да бъде отворен.');
      }

      _ensureCurrent(generation);

      _joined = true;
      debugPrint('Private call signaling channel connected.');
    } catch (_) {
      if (identical(_channel, channel)) {
        _channel = null;
      }

      _joined = false;

      if (_isCurrent(generation)) {
        _myId = null;
        _participantIds = <String>{};
      }

      if (channel != null) {
        try {
          await _supabase.removeChannel(channel);
        } catch (cleanupError) {
          debugPrint('Call signaling cleanup failed: $cleanupError');
        }
      }

      rethrow;
    }
  }

  bool _hasValidPayload(CallSignal signal) {
    switch (signal.type) {
      case CallSignalType.offer:
        return _hasValidSdp(signal.sdp, 'offer');

      case CallSignalType.answer:
        return _hasValidSdp(signal.sdp, 'answer');

      case CallSignalType.ice:
        final candidate = signal.candidate;
        final value = candidate?['candidate'];
        return value is String && value.isNotEmpty;

      case CallSignalType.invite:
      case CallSignalType.accept:
      case CallSignalType.reject:
      case CallSignalType.hangup:
      case CallSignalType.busy:
        return true;
    }
  }

  bool _hasValidSdp(Map<String, dynamic>? sdp, String expectedType) {
    if (sdp == null || sdp['type'] != expectedType) return false;

    final value = sdp['sdp'];
    return value is String && value.trim().isNotEmpty;
  }

  Future<void> send(CallSignal signal) async {
    if (_disposed) {
      throw StateError('Услугата за сигнализация е затворена.');
    }

    final channel = _channel;
    final myId = _myId;

    if (!_joined || channel == null || myId == null) {
      throw StateError('Сигнализационният канал не е готов.');
    }

    if (signal.conversationId != conversationId ||
        signal.fromUserId != myId ||
        !_participantIds.contains(myId) ||
        signal.callId.trim().isEmpty) {
      throw StateError('Сигналът не съответства на текущия разговор.');
    }

    if (!_hasValidPayload(signal)) {
      throw StateError('Сигналът съдържа невалидни данни.');
    }

    // Изпращането е само през вече абонирания private канал.
    await channel.sendBroadcastMessage(
      event: 'signal',
      payload: signal.toJson(),
    );

    if (_disposed || !identical(_channel, channel) || !_joined) {
      throw StateError('Сигнализационният канал беше затворен при изпращане.');
    }
  }

  bool _isCurrent(int generation) {
    return !_disposed && _lifecycleGeneration == generation;
  }

  void _ensureCurrent(int generation) {
    if (!_isCurrent(generation)) {
      throw StateError('Операцията за сигнализация е отменена.');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;
    _lifecycleGeneration++;

    final channel = _channel;

    _channel = null;
    _joined = false;
    _myId = null;
    _participantIds = <String>{};

    if (channel != null) {
      try {
        await _supabase.removeChannel(channel);
      } catch (error) {
        debugPrint('Call signaling cleanup failed: $error');
      }
    }
  }
}
