import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth_service.dart';
import 'call_models.dart';
import 'call_signaling_service.dart';

/// Глобална state machine за 1:1 обаждания.
/// WebRTC се закача по-късно през [onNeedOffer] / [onRemoteSdp] / [onRemoteIce].
class CallController extends ChangeNotifier {
  CallController._();
  static final instance = CallController._();

  static const _ringTimeout = Duration(seconds: 45);
  static const _uuid = Uuid();

  ActiveCall? _call;
  CallSignalingService? _signaling;
  Timer? _ringTimer;

  /// Hooks за стъпка B (WebRTC) — засега no-op.
  Future<Map<String, dynamic>?> Function(CallKind kind)? onNeedOffer;
  Future<Map<String, dynamic>?> Function(Map<String, dynamic> offer)? onNeedAnswer;
  Future<void> Function(Map<String, dynamic> sdp)? onRemoteSdp;
  Future<void> Function(Map<String, dynamic> candidate)? onRemoteIce;
  Future<void> Function()? onHangupMedia;

  ActiveCall? get call => _call;
  CallStatus get status => _call?.status ?? CallStatus.idle;
  bool get hasActiveCall =>
      _call != null &&
      _call!.status != CallStatus.idle &&
      _call!.status != CallStatus.ended;

  String? get _myId => AuthService.currentUser?.id;

  /// Започва изходящо обаждане.
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
    if (myId == null) return;
    if (otherUserId == myId) return;

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

    await _ensureSignaling(conversationId);

    await _signaling!.send(CallSignal(
      type: CallSignalType.invite,
      callId: callId,
      conversationId: conversationId,
      fromUserId: myId,
      kind: kind,
      ts: DateTime.now().millisecondsSinceEpoch,
    ));

    _armRingTimeout();
  }

  /// Слуша за входящи в даден разговор (викай от ChatPage / Home).
  Future<void> attachConversation(String conversationId) async {
    await _ensureSignaling(conversationId);
  }

  Future<void> acceptIncoming() async {
    final c = _call;
    final myId = _myId;
    if (c == null || myId == null) return;
    if (c.status != CallStatus.incoming) return;

    _ringTimer?.cancel();
    _call = c.copyWith(status: CallStatus.connecting);
    notifyListeners();

    await _signaling?.send(CallSignal(
      type: CallSignalType.accept,
      callId: c.callId,
      conversationId: c.conversationId,
      fromUserId: myId,
      kind: c.kind,
      ts: DateTime.now().millisecondsSinceEpoch,
    ));

    // Callee създава answer след като получи offer (стъпка B).
  }

  Future<void> rejectIncoming() async {
    final c = _call;
    final myId = _myId;
    if (c == null || myId == null) return;

    await _signaling?.send(CallSignal(
      type: CallSignalType.reject,
      callId: c.callId,
      conversationId: c.conversationId,
      fromUserId: myId,
      kind: c.kind,
      ts: DateTime.now().millisecondsSinceEpoch,
    ));

    await _finish(CallEndReason.rejected);
  }

  Future<void> hangUp() async {
    final c = _call;
    final myId = _myId;
    if (c == null || myId == null) return;
    if (c.status == CallStatus.ended || c.status == CallStatus.idle) return;

    _call = c.copyWith(status: CallStatus.ending);
    notifyListeners();

    await _signaling?.send(CallSignal(
      type: CallSignalType.hangup,
      callId: c.callId,
      conversationId: c.conversationId,
      fromUserId: myId,
      kind: c.kind,
      ts: DateTime.now().millisecondsSinceEpoch,
    ));

    await onHangupMedia?.call();
    await _finish(CallEndReason.localHangup);
  }

  /// Изпраща SDP offer/answer (след WebRTC).
  Future<void> sendSdp({
    required bool isOffer,
    required Map<String, dynamic> sdp,
  }) async {
    final c = _call;
    final myId = _myId;
    if (c == null || myId == null) return;

    await _signaling?.send(CallSignal(
      type: isOffer ? CallSignalType.offer : CallSignalType.answer,
      callId: c.callId,
      conversationId: c.conversationId,
      fromUserId: myId,
      kind: c.kind,
      sdp: sdp,
      ts: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> sendIce(Map<String, dynamic> candidate) async {
    final c = _call;
    final myId = _myId;
    if (c == null || myId == null) return;

    await _signaling?.send(CallSignal(
      type: CallSignalType.ice,
      callId: c.callId,
      conversationId: c.conversationId,
      fromUserId: myId,
      kind: c.kind,
      candidate: candidate,
      ts: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  void markConnected() {
    final c = _call;
    if (c == null) return;
    if (c.status == CallStatus.active) return;
    _ringTimer?.cancel();
    _call = c.copyWith(
      status: CallStatus.active,
      connectedAt: DateTime.now(),
    );
    notifyListeners();
  }

  Future<void> _ensureSignaling(String conversationId) async {
    if (_signaling != null &&
        _call != null &&
        _call!.conversationId == conversationId) {
      return;
    }
    await _signaling?.dispose();
    _signaling = CallSignalingService(
      conversationId: conversationId,
      onSignal: _onSignal,
    );
    await _signaling!.start();
  }

  void _onSignal(CallSignal signal) {
    unawaited(_handleSignal(signal));
  }

  Future<void> _handleSignal(CallSignal signal) async {
    final myId = _myId;
    if (myId == null) return;

    switch (signal.type) {
      case CallSignalType.invite:
        if (hasActiveCall) {
          await _signaling?.send(CallSignal(
            type: CallSignalType.busy,
            callId: signal.callId,
            conversationId: signal.conversationId,
            fromUserId: myId,
            kind: signal.kind,
            ts: DateTime.now().millisecondsSinceEpoch,
          ));
          return;
        }
        _call = ActiveCall(
          callId: signal.callId,
          conversationId: signal.conversationId,
          otherUserId: signal.fromUserId,
          otherDisplayName: 'Обаждане', // UI попълва име от профил
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
        if (!c.isOutgoing) return;
        _ringTimer?.cancel();
        _call = c.copyWith(status: CallStatus.connecting);
        notifyListeners();
        // Caller: създай offer (стъпка B)
        final offer = await onNeedOffer?.call(c.kind);
        if (offer != null) {
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
          await onHangupMedia?.call();
          await _finish(CallEndReason.remoteHangup);
        }

      case CallSignalType.offer:
        if (_call?.callId != signal.callId) return;
        if (signal.sdp != null) {
          await onRemoteSdp?.call(signal.sdp!);
          final answer = await onNeedAnswer?.call(signal.sdp!);
          if (answer != null) {
            await sendSdp(isOffer: false, sdp: answer);
            markConnected();
          }
        }

      case CallSignalType.answer:
        if (_call?.callId != signal.callId) return;
        if (signal.sdp != null) {
          await onRemoteSdp?.call(signal.sdp!);
          markConnected();
        }

      case CallSignalType.ice:
        if (_call?.callId != signal.callId) return;
        if (signal.candidate != null) {
          await onRemoteIce?.call(signal.candidate!);
        }
    }
  }

  void _armRingTimeout() {
    _ringTimer?.cancel();
    _ringTimer = Timer(_ringTimeout, () async {
      if (_call?.status == CallStatus.outgoing ||
          _call?.status == CallStatus.incoming) {
        await _finish(CallEndReason.timeout);
      }
    });
  }

  Future<void> _finish(CallEndReason reason) async {
    _ringTimer?.cancel();
    final c = _call;
    if (c != null) {
      _call = c.copyWith(status: CallStatus.ended, endReason: reason);
      notifyListeners();
    }
    // Кратко задържане за UI, после idle
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _call = null;
    notifyListeners();
  }

  /// При изход от чат — не убивай активен call, само ако idle.
  Future<void> detachIfIdle() async {
    if (hasActiveCall) return;
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