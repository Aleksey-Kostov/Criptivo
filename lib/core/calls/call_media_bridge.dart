import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_controller.dart';
import 'call_models.dart';
import 'call_permissions.dart';
import 'webrtc_session.dart';

/// Свързва CallController с WebRTC медията.
///
/// Поддържа една активна 1:1 сесия.
/// SDP и ICE се изпращат през CallController.
class CallMediaBridge {
  CallMediaBridge._();

  static final CallMediaBridge instance = CallMediaBridge._();

  WebRtcSession? _session;
  String? _callId;

  final StreamController<MediaStream?> _localController =
      StreamController<MediaStream?>.broadcast();

  final StreamController<MediaStream?> _remoteController =
      StreamController<MediaStream?>.broadcast();

  final StreamController<RTCPeerConnectionState> _stateController =
      StreamController<RTCPeerConnectionState>.broadcast();

  final List<Map<String, dynamic>> _pendingIce = [];
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  bool _initialized = false;
  bool _remoteDescriptionSet = false;

  Future<void>? _startingFuture;
  int _lifecycleGeneration = 0;

  Stream<MediaStream?> get localStream$ => _localController.stream;
  Stream<MediaStream?> get remoteStream$ => _remoteController.stream;

  Stream<RTCPeerConnectionState> get connectionState$ =>
      _stateController.stream;

  MediaStream? get localStream => _session?.localStream;
  MediaStream? get remoteStream => _session?.remoteStream;

  bool get isMicMuted => _session?.isMicMuted ?? false;
  bool get isCamOff => _session?.isCamOff ?? false;

  /// Извиква се при стартиране на приложението или преди call screen.
  void attach(CallController controller) {
    if (_initialized) return;

    _initialized = true;

    controller.onNeedOffer = (kind) async {
      await _ensureStarted(kind, controller);

      final session = _session;
      if (session == null) {
        throw StateError('WebRTC сесията не е стартирана.');
      }

      return session.createOffer();
    };

    controller.onNeedAnswer = (offer) async {
      final call = controller.call;
      if (call == null) {
        throw StateError('Няма активен разговор.');
      }

      await _ensureStarted(call.kind, controller);

      final session = _session;
      if (session == null || _callId != call.callId) {
        throw StateError('WebRTC сесията вече не е активна.');
      }

      final answer = await session.createAnswer(offer);

      if (_session != session || _callId != call.callId) {
        throw StateError('Разговорът е прекратен при създаване на отговора.');
      }

      _remoteDescriptionSet = true;
      await _flushPendingIce(session, call.callId);

      return answer;
    };

    controller.onRemoteSdp = (sdp) async {
      // createAnswer() вече задава remote offer.
      // Тук обработваме remote answer при инициатора.
      if (sdp['type'] != 'answer') return;

      final call = controller.call;
      if (call == null) {
        throw StateError('Няма активен разговор за remote SDP.');
      }

      await _ensureStarted(call.kind, controller);

      final session = _session;
      if (session == null || _callId != call.callId) {
        throw StateError('WebRTC сесията вече не е активна.');
      }

      await session.setRemoteDescription(sdp);

      if (_session != session || _callId != call.callId) {
        throw StateError('Разговорът е прекратен при задаване на remote SDP.');
      }

      _remoteDescriptionSet = true;
      await _flushPendingIce(session, call.callId);
    };

    controller.onRemoteIce = (candidate) async {
      final call = controller.call;
      if (call == null) return;

      if (_session == null ||
          _callId != call.callId ||
          !_remoteDescriptionSet) {
        // Не смесваме ICE кандидати от различни разговори.
        _pendingIce.add(Map<String, dynamic>.from(candidate));
        return;
      }

      await _session!.addIceCandidate(candidate);
    };

    controller.onHangupMedia = _stopSession;
  }

  Future<void> _ensureStarted(CallKind kind, CallController controller) async {
    final call = controller.call;
    if (call == null) {
      throw StateError('Няма активен разговор.');
    }

    if (_session != null && _callId == call.callId) {
      return;
    }

    final pendingStart = _startingFuture;
    if (pendingStart != null) {
      await pendingStart;

      final currentCall = controller.call;
      if (currentCall == null) {
        throw StateError('Разговорът е прекратен при стартиране на медията.');
      }

      if (_session != null && _callId == currentCall.callId) {
        return;
      }

      // Ако междувременно е започнал друг разговор, проверяваме него.
      return _ensureStarted(currentCall.kind, controller);
    }

    final future = _startSession(
      callId: call.callId,
      kind: kind,
      controller: controller,
    );

    _startingFuture = future;

    try {
      await future;
    } finally {
      if (identical(_startingFuture, future)) {
        _startingFuture = null;
      }
    }

    final currentCall = controller.call;
    if (currentCall == null ||
        currentCall.callId != call.callId ||
        _session == null ||
        _callId != call.callId) {
      throw StateError('Разговорът е прекратен при стартиране на медията.');
    }
  }

  Future<void> _startSession({
    required String callId,
    required CallKind kind,
    required CallController controller,
  }) async {
    await _stopSession();

    // Генерацията се взема след почистването. Ако hangup настъпи
    // по време на разрешенията или стартирането, тя ще се промени.
    final generation = _lifecycleGeneration;

    final currentCall = controller.call;
    if (currentCall == null || currentCall.callId != callId) {
      throw StateError('Разговорът вече не е активен.');
    }

    final granted = await CallPermissions.ensure(kind);

    if (generation != _lifecycleGeneration ||
        controller.call?.callId != callId) {
      throw StateError('Разговорът е прекратен по време на разрешенията.');
    }

    if (!granted) {
      throw StateError(
        'Необходим е достъп до микрофона'
        '${kind == CallKind.video ? ' и камерата' : ''}.',
      );
    }

    final session = WebRtcSession();
    _session = session;
    _callId = callId;

    _remoteDescriptionSet = false;
    _pendingIce.clear();

    _subscriptions.add(
      session.localStream$.listen((stream) {
        if (_session != session || _callId != callId) return;

        if (!_localController.isClosed) {
          _localController.add(stream);
        }
      }),
    );

    _subscriptions.add(
      session.remoteStream$.listen((stream) {
        if (_session != session || _callId != callId) return;

        if (!_remoteController.isClosed) {
          _remoteController.add(stream);
        }
      }),
    );

    _subscriptions.add(
      session.iceCandidate$.listen((candidate) {
        if (_session != session || _callId != callId) return;

        unawaited(_sendIceSafely(controller, callId, candidate));
      }),
    );

    _subscriptions.add(
      session.connectionState$.listen((state) {
        if (_session != session || _callId != callId) return;

        if (!_stateController.isClosed) {
          _stateController.add(state);
        }

        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          if (controller.call?.callId == callId) {
            controller.markConnected();
          }
          return;
        }

        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          unawaited(_hangUpSafely(controller, callId));
        }
      }),
    );

    try {
      await session.start(kind: kind);

      if (generation != _lifecycleGeneration ||
          _session != session ||
          _callId != callId ||
          controller.call?.callId != callId) {
        throw StateError('WebRTC сесията е прекратена по време на стартиране.');
      }
    } catch (_) {
      // Ако сесията все още е текущата, почисти я.
      // Ако hangup вече я е отделил, неговото почистване е отговорно
      // за освобождаването ѝ.
      if (_session == session && _callId == callId) {
        await _stopSession();
      }

      rethrow;
    }
  }

  Future<void> _sendIceSafely(
    CallController controller,
    String callId,
    Map<String, dynamic> candidate,
  ) async {
    if (controller.call?.callId != callId) return;

    try {
      await controller.sendIce(candidate);
    } catch (_) {
      // Сигнализационните грешки се обработват в CallController.
      // Не допускаме необработена async грешка от stream listener.
    }
  }

  Future<void> _hangUpSafely(CallController controller, String callId) async {
    final call = controller.call;

    if (call == null || call.callId != callId) return;
    if (call.status == CallStatus.ending ||
        call.status == CallStatus.ended ||
        call.status == CallStatus.idle) {
      return;
    }

    try {
      await controller.hangUp();
    } catch (_) {
      // CallController отговаря за завършването и сигнализационната грешка.
    }
  }

  Future<void> _flushPendingIce(WebRtcSession session, String callId) async {
    if (!_remoteDescriptionSet || _session != session || _callId != callId) {
      return;
    }

    final queued = List<Map<String, dynamic>>.from(_pendingIce);
    _pendingIce.clear();

    for (var i = 0; i < queued.length; i++) {
      if (_session != session || _callId != callId) {
        // Не губим неизпратените кандидати, ако сесията все още е
        // същата. При смяна на разговора те не трябва да се пренасят.
        return;
      }

      await session.addIceCandidate(queued[i]);
    }
  }

  Future<void> setMicMuted(bool muted) async {
    await _session?.setMicMuted(muted);
  }

  Future<void> setCameraEnabled(bool enabled) async {
    await _session?.setCameraEnabled(enabled);
  }

  Future<void> switchCamera() async {
    await _session?.switchCamera();
  }

  Future<void> setSpeakerphone(bool enabled) async {
    await _session?.setSpeakerphone(enabled);
  }

  Future<void> _stopSession() async {
    // Инвалидира стартирането, ако то още чака разрешения или WebRTC.
    _lifecycleGeneration++;

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    final oldSession = _session;

    _session = null;
    _callId = null;
    _remoteDescriptionSet = false;
    _pendingIce.clear();

    if (!_localController.isClosed) {
      _localController.add(null);
    }

    if (!_remoteController.isClosed) {
      _remoteController.add(null);
    }

    if (oldSession != null) {
      await oldSession.closeFully();
    }
  }
}
