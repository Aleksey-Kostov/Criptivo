import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth_service.dart';
import 'call_models.dart';
import 'call_signaling_service.dart';

/// Global state machine for 1:1 calls.
class CallController extends ChangeNotifier {
  CallController._();

  static final instance = CallController._();

  static const _ringTimeout = Duration(seconds: 45);
  static const _finishDelay = Duration(milliseconds: 400);
  static const _uuid = Uuid();

  ActiveCall? _call;
  CallSignalingService? _signaling;
  Timer? _ringTimer;

  bool _disposed = false;
  String? _finishingCallId;

  Future<Map<String, dynamic>> Function(CallKind kind)? onNeedOffer;

  Future<Map<String, dynamic>?> Function(Map<String, dynamic> offer)?
  onNeedAnswer;

  Future<void> Function(Map<String, dynamic> sdp)? onRemoteSdp;
  Future<void> Function(Map<String, dynamic> candidate)? onRemoteIce;
  Future<void> Function()? onHangupMedia;

  ActiveCall? get call => _call;

  CallStatus get status => _call?.status ?? CallStatus.idle;

  bool get hasActiveCall {
    if (_finishingCallId != null) return true;

    final current = _call;
    return current != null &&
        current.status != CallStatus.idle &&
        current.status != CallStatus.ended;
  }

  String? get _myId => AuthService.currentUser?.id;

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  bool _isCurrentCall(String callId) => _call?.callId == callId;

  /// Starts an outgoing call.
  Future<void> startOutgoing({
    required String conversationId,
    required String otherUserId,
    required String otherDisplayName,
    String? otherAvatarUrl,
    required CallKind kind,
  }) async {
    if (hasActiveCall) {
      debugPrint('Call: already in a call');
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

    _notifySafely();

    try {
      await _ensureSignaling(conversationId);

      if (!_isCurrentCall(callId)) return;

      final signaling = _signaling;
      if (signaling == null) {
        throw StateError('Сигнализацията не е готова.');
      }

      await signaling.send(
        CallSignal(
          type: CallSignalType.invite,
          callId: callId,
          conversationId: conversationId,
          fromUserId: myId,
          kind: kind,
          ts: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      if (!_isCurrentCall(callId)) return;

      _armRingTimeout(callId);
    } catch (_) {
      await _finish(CallEndReason.failed, expectedCallId: callId);
      rethrow;
    }
  }

  /// Attaches signaling for a conversation.
  Future<void> attachConversation(String conversationId) async {
    await _ensureSignaling(conversationId);
  }

  /// Accepts an incoming call.
  Future<void> acceptIncoming() async {
    final current = _call;
    final myId = _myId;

    if (current == null ||
        myId == null ||
        current.status != CallStatus.incoming) {
      return;
    }

    final callId = current.callId;

    _ringTimer?.cancel();
    _call = current.copyWith(status: CallStatus.connecting);
    _notifySafely();

    try {
      final signaling = _signaling;
      if (signaling == null) {
        throw StateError('Сигнализацията не е готова.');
      }

      await signaling.send(
        CallSignal(
          type: CallSignalType.accept,
          callId: callId,
          conversationId: current.conversationId,
          fromUserId: myId,
          kind: current.kind,
          ts: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (_) {
      await _finish(CallEndReason.failed, expectedCallId: callId);
      rethrow;
    }

    // The answer is created when the offer arrives.
    // The call becomes active after WebRTC connects.
  }

  /// Rejects an incoming call.
  Future<void> rejectIncoming() async {
    final current = _call;
    final myId = _myId;

    if (current == null || myId == null) return;

    final callId = current.callId;

    try {
      final signaling = _signaling;
      if (signaling != null) {
        await signaling.send(
          CallSignal(
            type: CallSignalType.reject,
            callId: callId,
            conversationId: current.conversationId,
            fromUserId: myId,
            kind: current.kind,
            ts: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    } catch (error) {
      debugPrint('Call reject signaling failed: $error');
    } finally {
      await _finish(CallEndReason.rejected, expectedCallId: callId);
    }
  }

  /// Ends the current call.
  Future<void> hangUp() async {
    final current = _call;
    final myId = _myId;

    if (current == null ||
        myId == null ||
        current.status == CallStatus.ended ||
        current.status == CallStatus.idle ||
        _finishingCallId == current.callId) {
      return;
    }

    final callId = current.callId;

    _call = current.copyWith(status: CallStatus.ending);
    _notifySafely();

    try {
      final signaling = _signaling;
      if (signaling != null) {
        await signaling.send(
          CallSignal(
            type: CallSignalType.hangup,
            callId: callId,
            conversationId: current.conversationId,
            fromUserId: myId,
            kind: current.kind,
            ts: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    } catch (error) {
      debugPrint('Call hangup signaling failed: $error');
    } finally {
      await _finish(CallEndReason.localHangup, expectedCallId: callId);
    }
  }

  /// Sends an SDP offer or answer.
  Future<void> sendSdp({
    required bool isOffer,
    required Map<String, dynamic> sdp,
  }) async {
    final current = _call;
    final myId = _myId;

    if (current == null || myId == null) {
      throw StateError('Няма активен разговор за изпращане на SDP.');
    }

    if (current.status == CallStatus.ending ||
        current.status == CallStatus.ended ||
        _finishingCallId == current.callId) {
      throw StateError('Разговорът вече се прекратява.');
    }

    final expectedType = isOffer ? 'offer' : 'answer';

    if (sdp['type'] != expectedType ||
        sdp['sdp'] is! String ||
        (sdp['sdp'] as String).trim().isEmpty) {
      throw FormatException('Невалиден SDP $expectedType.');
    }

    final signaling = _signaling;
    if (signaling == null) {
      throw StateError('Сигнализацията не е готова.');
    }

    await signaling.send(
      CallSignal(
        type: isOffer ? CallSignalType.offer : CallSignalType.answer,
        callId: current.callId,
        conversationId: current.conversationId,
        fromUserId: myId,
        kind: current.kind,
        sdp: sdp,
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Sends a local ICE candidate.
  Future<void> sendIce(Map<String, dynamic> candidate) async {
    final current = _call;
    final myId = _myId;

    if (current == null || myId == null) {
      throw StateError('Няма активен разговор за изпращане на ICE.');
    }

    if (current.status == CallStatus.ending ||
        current.status == CallStatus.ended ||
        _finishingCallId == current.callId) {
      return;
    }

    final value = candidate['candidate'];
    if (value is! String || value.isEmpty) {
      throw const FormatException('Невалиден ICE кандидат.');
    }

    final signaling = _signaling;
    if (signaling == null) {
      throw StateError('Сигнализацията не е готова.');
    }

    await signaling.send(
      CallSignal(
        type: CallSignalType.ice,
        callId: current.callId,
        conversationId: current.conversationId,
        fromUserId: myId,
        kind: current.kind,
        candidate: candidate,
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Called by CallMediaBridge after WebRTC connects.
  void markConnected() {
    final current = _call;

    if (current == null ||
        current.status == CallStatus.active ||
        current.status == CallStatus.ending ||
        current.status == CallStatus.ended ||
        _finishingCallId == current.callId) {
      return;
    }

    _ringTimer?.cancel();

    _call = current.copyWith(
      status: CallStatus.active,
      connectedAt: DateTime.now(),
    );

    _notifySafely();
  }

  Future<void> _ensureSignaling(String conversationId) async {
    if (_signaling != null && _call?.conversationId == conversationId) {
      return;
    }

    final oldSignaling = _signaling;
    _signaling = null;

    await oldSignaling?.dispose();

    final signaling = CallSignalingService(
      conversationId: conversationId,
      onSignal: _onSignal,
    );

    _signaling = signaling;

    try {
      await signaling.start();

      if (!identical(_signaling, signaling)) {
        await signaling.dispose();
      }
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
      debugPrint('Call signal handling failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      final current = _call;
      if (current != null &&
          current.callId == signal.callId &&
          current.conversationId == signal.conversationId) {
        await _finish(CallEndReason.failed, expectedCallId: signal.callId);
      }
    }
  }

  Future<void> _handleSignal(CallSignal signal) async {
    final myId = _myId;
    if (myId == null || signal.fromUserId == myId) return;

    switch (signal.type) {
      case CallSignalType.invite:
        if (signal.conversationId.isEmpty ||
            signal.callId.isEmpty ||
            signal.fromUserId.isEmpty) {
          return;
        }

        final current = _call;

        // Ignore duplicate invitations for the same call.
        if (current?.callId == signal.callId &&
            current?.conversationId == signal.conversationId) {
          return;
        }

        if (hasActiveCall) {
          final signaling = _signaling;
          if (signaling != null) {
            await signaling.send(
              CallSignal(
                type: CallSignalType.busy,
                callId: signal.callId,
                conversationId: signal.conversationId,
                fromUserId: myId,
                kind: signal.kind,
                ts: DateTime.now().millisecondsSinceEpoch,
              ),
            );
          }
          return;
        }

        // The invitation must match the subscribed conversation.
        if (_signaling == null ||
            signal.conversationId != _callConversationIdForSignaling()) {
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

        _notifySafely();
        _armRingTimeout(signal.callId);
        return;

      case CallSignalType.accept:
        final current = _call;

        if (current == null ||
            current.callId != signal.callId ||
            current.conversationId != signal.conversationId ||
            !current.isOutgoing ||
            current.status != CallStatus.outgoing) {
          return;
        }

        _ringTimer?.cancel();

        _call = current.copyWith(status: CallStatus.connecting);
        _notifySafely();

        final offerCallback = onNeedOffer;
        if (offerCallback == null) {
          throw StateError('WebRTC offer обработчикът не е настроен.');
        }

        // CallMediaBridge creates and sends the offer through sendSdp().
        await offerCallback(current.kind);

        if (!_isCurrentCall(signal.callId)) return;

        // Wait for the WebRTC connection-state callback before marking
        // the call as active.
        return;

      case CallSignalType.reject:
        if (_isMatchingSignal(signal)) {
          await _finish(CallEndReason.rejected, expectedCallId: signal.callId);
        }
        return;

      case CallSignalType.busy:
        if (_isMatchingSignal(signal)) {
          await _finish(CallEndReason.busy, expectedCallId: signal.callId);
        }
        return;

      case CallSignalType.hangup:
        if (_isMatchingSignal(signal)) {
          await _finish(
            CallEndReason.remoteHangup,
            expectedCallId: signal.callId,
          );
        }
        return;

      case CallSignalType.offer:
        final current = _call;

        if (current == null ||
            current.callId != signal.callId ||
            current.conversationId != signal.conversationId ||
            current.isOutgoing ||
            (current.status != CallStatus.connecting &&
                current.status != CallStatus.incoming) ||
            signal.sdp == null ||
            signal.sdp!['type'] != 'offer') {
          return;
        }

        final answerCallback = onNeedAnswer;
        if (answerCallback == null) {
          throw StateError('WebRTC offer обработчикът не е настроен.');
        }

        final answer = await answerCallback(signal.sdp!);

        if (!_isCurrentCall(signal.callId) || answer == null) return;

        await sendSdp(isOffer: false, sdp: answer);

        // WebRTC connection state determines when the call is active.
        return;

      case CallSignalType.answer:
        final current = _call;

        if (current == null ||
            current.callId != signal.callId ||
            current.conversationId != signal.conversationId ||
            !current.isOutgoing ||
            current.status != CallStatus.connecting ||
            signal.sdp == null ||
            signal.sdp!['type'] != 'answer') {
          return;
        }

        final remoteSdpCallback = onRemoteSdp;
        if (remoteSdpCallback == null) {
          throw StateError('WebRTC SDP обработчикът не е настроен.');
        }

        await remoteSdpCallback(signal.sdp!);

        // Do not mark connected before WebRTC confirms the connection.
        return;

      case CallSignalType.ice:
        final current = _call;

        if (current == null ||
            current.callId != signal.callId ||
            current.conversationId != signal.conversationId ||
            signal.candidate == null) {
          return;
        }

        final iceCallback = onRemoteIce;
        if (iceCallback == null) {
          throw StateError('WebRTC ICE обработчикът не е настроен.');
        }

        await iceCallback(signal.candidate!);
        return;
    }
  }

  String? _callConversationIdForSignaling() {
    return _call?.conversationId;
  }

  bool _isMatchingSignal(CallSignal signal) {
    final current = _call;

    return current != null &&
        current.callId == signal.callId &&
        current.conversationId == signal.conversationId;
  }

  void _armRingTimeout(String callId) {
    _ringTimer?.cancel();

    _ringTimer = Timer(_ringTimeout, () async {
      final current = _call;

      if (current == null ||
          current.callId != callId ||
          (current.status != CallStatus.outgoing &&
              current.status != CallStatus.incoming)) {
        return;
      }

      await _finish(CallEndReason.timeout, expectedCallId: callId);
    });
  }

  Future<void> _finish(CallEndReason reason, {String? expectedCallId}) async {
    final current = _call;
    if (current == null) return;

    if (expectedCallId != null && current.callId != expectedCallId) {
      return;
    }

    if (_finishingCallId == current.callId) return;

    _finishingCallId = current.callId;
    _ringTimer?.cancel();
    _ringTimer = null;

    _call = current.copyWith(status: CallStatus.ended, endReason: reason);

    _notifySafely();

    try {
      try {
        await onHangupMedia?.call();
      } catch (error) {
        debugPrint('Call media cleanup failed: $error');
      }

      await Future<void>.delayed(_finishDelay);
    } finally {
      // Do not clear a newer call if the previous cleanup finishes late.
      if (_call?.callId == current.callId) {
        _call = null;
        _notifySafely();
      }

      if (_finishingCallId == current.callId) {
        _finishingCallId = null;
      }
    }
  }

  /// Detaches signaling when no call is active.
  Future<void> detachIfIdle() async {
    if (hasActiveCall) return;

    final signaling = _signaling;
    _signaling = null;

    await signaling?.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    _ringTimer?.cancel();
    _ringTimer = null;

    final signaling = _signaling;
    _signaling = null;

    if (signaling != null) {
      unawaited(signaling.dispose());
    }

    final cleanup = onHangupMedia;
    if (cleanup != null) {
      unawaited(
        cleanup().catchError((Object error) {
          debugPrint('Call media disposal failed: $error');
        }),
      );
    }

    super.dispose();
  }
}
