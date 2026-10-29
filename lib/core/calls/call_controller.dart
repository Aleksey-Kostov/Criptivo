import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth_service.dart';
import 'call_models.dart';
import 'call_signaling_service.dart';

/// Глобална state machine за 1:1 обаждания.
///
/// WebRTC се свързва чрез onNeedOffer / onNeedAnswer /
/// onRemoteSdp / onRemoteIce.
///
/// CallStatus.active се задава само след потвърждение
/// за действително установена WebRTC връзка.
class CallController extends ChangeNotifier {
  CallController._();

  static final instance = CallController._();

  static const _ringTimeout = Duration(seconds: 45);
  static const _endedDisplayDuration = Duration(milliseconds: 400);
  static const _uuid = Uuid();

  ActiveCall? _call;
  CallSignalingService? _signaling;
  Timer? _ringTimer;

  bool _finishing = false;

  /// Hooks за WebRTC медията.
  Future<Map<String, dynamic>?> Function(CallKind kind)? onNeedOffer;
  Future<Map<String, dynamic>?> Function(Map<String, dynamic> offer)?
  onNeedAnswer;
  Future<void> Function(Map<String, dynamic> sdp)? onRemoteSdp;
  Future<void> Function(Map<String, dynamic> candidate)? onRemoteIce;
  Future<void> Function()? onHangupMedia;

  ActiveCall? get call => _call;

  CallStatus get status => _call?.status ?? CallStatus.idle;

  bool get hasActiveCall {
    final current = _call;
    return current != null &&
        current.status != CallStatus.idle &&
        current.status != CallStatus.ended;
  }

  String? get _myId => AuthService.currentUser?.id;

  /// Започва изходящо обаждане.
  Future<void> startOutgoing({
    required String conversationId,
    required String otherUserId,
    required String otherDisplayName,
    String? otherAvatarUrl,
    required CallKind kind,
  }) async {
    if (hasActiveCall || _finishing) {
      debugPrint('Call: already in a call or finishing.');
      return;
    }

    final myId = _myId;

    if (myId == null) {
      throw StateError('Трябва да си влязъл в акаунта.');
    }

    if (otherUserId == myId) {
      throw StateError('Не можеш да се обадиш на собствения си акаунт.');
    }

    final callId = _uuid.v4();

    _call = ActiveCall(
      callId: callId,
      conversationId: conversationId,
      otherUserId: otherUserId,
      otherDisplayName: otherDisplayName,
      otherAvatarUrl: otherAvatarUrl,
      kind: kind,
      isOutgoing: true,
      status: CallStatus.outgoing,
      startedAt: DateTime.now(),
    );

    notifyListeners();

    try {
      await _ensureSignaling(conversationId);

      // Проверяваме дали повикването не е прекратено,
      // докато изчаквахме отварянето на канала.
      if (_call?.callId != callId) return;

      await _signaling!.send(
        CallSignal(
          type: CallSignalType.invite,
          callId: callId,
          conversationId: conversationId,
          fromUserId: myId,
          kind: kind,
          ts: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      if (_call?.callId == callId && _call?.status == CallStatus.outgoing) {
        _armRingTimeout();
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to start outgoing call: $error');

      if (_call?.callId == callId) {
        await _finish(CallEndReason.failed);
      }

      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Слуша за входящи повиквания в даден разговор.
  ///
  /// Извиква се от ChatPage / Home.
  Future<void> attachConversation(String conversationId) async {
    await _ensureSignaling(conversationId);
  }

  /// Приема входящо повикване.
  Future<void> acceptIncoming() async {
    final c = _call;
    final myId = _myId;

    if (c == null || myId == null) return;
    if (c.status != CallStatus.incoming) return;

    _ringTimer?.cancel();

    _call = c.copyWith(status: CallStatus.connecting);
    notifyListeners();

    try {
      await _signaling?.send(
        CallSignal(
          type: CallSignalType.accept,
          callId: c.callId,
          conversationId: c.conversationId,
          fromUserId: myId,
          kind: c.kind,
          ts: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      // Callee създава answer, когато получи offer.
      // Тук все още не отбелязваме разговора като активен.
    } catch (error, stackTrace) {
      debugPrint('Failed to accept call: $error');

      if (_call?.callId == c.callId) {
        await _finish(CallEndReason.failed);
      }

      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Отказва входящо повикване.
  Future<void> rejectIncoming() async {
    final c = _call;
    final myId = _myId;

    if (c == null || myId == null) return;
    if (c.status != CallStatus.incoming) return;

    Object? sendError;
    StackTrace? sendStackTrace;

    try {
      await _signaling?.send(
        CallSignal(
          type: CallSignalType.reject,
          callId: c.callId,
          conversationId: c.conversationId,
          fromUserId: myId,
          kind: c.kind,
          ts: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (error, stackTrace) {
      sendError = error;
      sendStackTrace = stackTrace;
      debugPrint('Failed to send call rejection: $error');
    } finally {
      if (_call?.callId == c.callId) {
        await _finish(CallEndReason.rejected);
      }
    }

    if (sendError != null) {
      Error.throwWithStackTrace(sendError, sendStackTrace!);
    }
  }

  /// Прекратява текущото повикване.
  ///
  /// Локалната медийна сесия се освобождава дори ако
  /// изпращането на hangup сигнала се провали.
  Future<void> hangUp() async {
    final c = _call;
    final myId = _myId;

    if (c == null || myId == null) return;
    if (c.status == CallStatus.ended || c.status == CallStatus.idle) {
      return;
    }

    _ringTimer?.cancel();

    _call = c.copyWith(status: CallStatus.ending);
    notifyListeners();

    Object? sendError;
    StackTrace? sendStackTrace;

    try {
      await _signaling?.send(
        CallSignal(
          type: CallSignalType.hangup,
          callId: c.callId,
          conversationId: c.conversationId,
          fromUserId: myId,
          kind: c.kind,
          ts: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (error, stackTrace) {
      sendError = error;
      sendStackTrace = stackTrace;
      debugPrint('Failed to send hangup signal: $error');
    } finally {
      if (_call?.callId == c.callId) {
        await _finish(CallEndReason.localHangup);
      }
    }

    if (sendError != null) {
      Error.throwWithStackTrace(sendError, sendStackTrace!);
    }
  }

  /// Изпраща SDP offer/answer.
  Future<void> sendSdp({
    required bool isOffer,
    required Map<String, dynamic> sdp,
  }) async {
    final c = _call;
    final myId = _myId;

    if (c == null || myId == null) {
      throw StateError('Няма активен разговор за изпращане на SDP.');
    }

    await _signaling!.send(
      CallSignal(
        type: isOffer ? CallSignalType.offer : CallSignalType.answer,
        callId: c.callId,
        conversationId: c.conversationId,
        fromUserId: myId,
        kind: c.kind,
        sdp: sdp,
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Изпраща ICE кандидат.
  Future<void> sendIce(Map<String, dynamic> candidate) async {
    final c = _call;
    final myId = _myId;

    if (c == null || myId == null) return;

    // Не изпращаме кандидати след приключване на повикването.
    if (c.status == CallStatus.ended ||
        c.status == CallStatus.ending ||
        c.status == CallStatus.idle) {
      return;
    }

    await _signaling!.send(
      CallSignal(
        type: CallSignalType.ice,
        callId: c.callId,
        conversationId: c.conversationId,
        fromUserId: myId,
        kind: c.kind,
        candidate: candidate,
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Извиква се от CallMediaBridge само при реално
  /// установена WebRTC връзка.
  void markConnected() {
    final c = _call;

    if (c == null) return;
    if (c.status == CallStatus.active ||
        c.status == CallStatus.ending ||
        c.status == CallStatus.ended ||
        c.status == CallStatus.idle) {
      return;
    }

    _ringTimer?.cancel();

    _call = c.copyWith(status: CallStatus.active, connectedAt: DateTime.now());

    notifyListeners();
  }

  Future<void> _ensureSignaling(String conversationId) async {
    if (_signaling != null &&
        _call != null &&
        _call!.conversationId == conversationId) {
      return;
    }

    await _signaling?.dispose();
    _signaling = null;

    final signaling = CallSignalingService(
      conversationId: conversationId,
      onSignal: _onSignal,
    );

    _signaling = signaling;

    try {
      await signaling.start();
    } catch (_) {
      if (identical(_signaling, signaling)) {
        _signaling = null;
      }

      await signaling.dispose();
      rethrow;
    }
  }

  void _onSignal(CallSignal signal) {
    unawaited(_handleSignalSafely(signal));
  }

  Future<void> _handleSignalSafely(CallSignal signal) async {
    try {
      await _handleSignal(signal);
    } catch (error, stackTrace) {
      debugPrint('Call signaling handler failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (_call?.callId == signal.callId) {
        await _finish(CallEndReason.failed);
      }
    }
  }

  Future<void> _handleSignal(CallSignal signal) async {
    final myId = _myId;
    if (myId == null) return;

    switch (signal.type) {
      case CallSignalType.invite:
        if (hasActiveCall || _finishing) {
          await _signaling?.send(
            CallSignal(
              type: CallSignalType.busy,
              callId: signal.callId,
              conversationId: signal.conversationId,
              fromUserId: myId,
              kind: signal.kind,
              ts: DateTime.now().millisecondsSinceEpoch,
            ),
          );
          return;
        }

        _call = ActiveCall(
          callId: signal.callId,
          conversationId: signal.conversationId,
          otherUserId: signal.fromUserId,
          otherDisplayName: 'Обаждане',
          kind: signal.kind,
          isOutgoing: false,
          status: CallStatus.incoming,
          startedAt: DateTime.now(),
        );

        notifyListeners();
        _armRingTimeout();

      case CallSignalType.accept:
        final c = _call;

        if (c == null || c.callId != signal.callId) return;
        if (!c.isOutgoing || c.status != CallStatus.outgoing) return;

        _ringTimer?.cancel();

        _call = c.copyWith(status: CallStatus.connecting);
        notifyListeners();

        // Caller създава offer.
        // Не маркираме разговора като активен тук.
        final offer = await onNeedOffer?.call(c.kind);

        if (offer != null && _call?.callId == c.callId) {
          await sendSdp(isOffer: true, sdp: offer);
        }

      case CallSignalType.reject:
        if (_call?.callId == signal.callId) {
          await _finish(CallEndReason.rejected);
        }

      case CallSignalType.busy:
        if (_call?.callId == signal.callId) {
          await _finish(CallEndReason.busy);
        }

      case CallSignalType.hangup:
        if (_call?.callId == signal.callId) {
          await _finish(CallEndReason.remoteHangup);
        }

      case CallSignalType.offer:
        final c = _call;

        if (c == null || c.callId != signal.callId) return;
        if (signal.sdp == null) return;

        await onRemoteSdp?.call(signal.sdp!);

        final answer = await onNeedAnswer?.call(signal.sdp!);

        if (answer != null && _call?.callId == c.callId) {
          await sendSdp(isOffer: false, sdp: answer);
        }

      // Създаването и изпращането на answer не доказва,
      // че ICE/WebRTC връзката е установена.

      case CallSignalType.answer:
        final c = _call;

        if (c == null || c.callId != signal.callId) return;
        if (!c.isOutgoing || signal.sdp == null) return;

        await onRemoteSdp?.call(signal.sdp!);

      // CallMediaBridge ще извика markConnected()
      // при RTCPeerConnectionStateConnected.

      case CallSignalType.ice:
        if (_call?.callId != signal.callId) return;

        final candidate = signal.candidate;
        if (candidate != null) {
          await onRemoteIce?.call(candidate);
        }
    }
  }

  void _armRingTimeout() {
    _ringTimer?.cancel();

    _ringTimer = Timer(_ringTimeout, () async {
      final c = _call;

      if (c == null) return;

      if (c.status == CallStatus.outgoing || c.status == CallStatus.incoming) {
        await _finish(CallEndReason.timeout);
      }
    });
  }

  Future<void> _finish(CallEndReason reason) async {
    if (_finishing) return;

    final c = _call;
    if (c == null) return;

    _finishing = true;
    _ringTimer?.cancel();

    _call = c.copyWith(status: CallStatus.ended, endReason: reason);

    notifyListeners();

    try {
      // Винаги се опитваме да спрем локалната медия,
      // включително при timeout, отказ или мрежова грешка.
      await onHangupMedia?.call();
    } catch (error, stackTrace) {
      debugPrint('Call media cleanup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    try {
      await Future<void>.delayed(_endedDisplayDuration);
    } finally {
      // Не изтриваме случайно друг разговор, ако състоянието
      // е било променено отвън.
      if (_call?.callId == c.callId) {
        _call = null;
        notifyListeners();
      }

      _finishing = false;
    }
  }

  /// При изход от чат не прекратяваме активен разговор.
  Future<void> detachIfIdle() async {
    if (hasActiveCall || _finishing) return;

    await _signaling?.dispose();
    _signaling = null;
  }

  @override
  void dispose() {
    _ringTimer?.cancel();
    unawaited(_signaling?.dispose());
    super.dispose();
  }
}
