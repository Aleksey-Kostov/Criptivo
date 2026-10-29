import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_controller.dart';
import 'call_models.dart';
import 'call_permissions.dart';
import 'webrtc_session.dart';

/// Свързва CallController със WebRTC медията.
///
/// Използва се една активна 1:1 сесия.
/// SDP и ICE се изпращат през съществуващия CallController.
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
  bool _starting = false;

  Stream<MediaStream?> get localStream$ => _localController.stream;
  Stream<MediaStream?> get remoteStream$ => _remoteController.stream;

  Stream<RTCPeerConnectionState> get connectionState$ =>
      _stateController.stream;

  MediaStream? get localStream => _session?.localStream;
  MediaStream? get remoteStream => _session?.remoteStream;

  bool get isMicMuted => _session?.isMicMuted ?? false;
  bool get isCamOff => _session?.isCamOff ?? false;

  /// Извикай при стартиране на приложението или преди call screen.
  void attach(CallController controller) {
    if (_initialized) return;
    _initialized = true;

    controller.onNeedOffer = (kind) async {
      await _ensureStarted(kind, controller);
      return _session!.createOffer();
    };

    controller.onNeedAnswer = (offer) async {
      final kind = controller.call?.kind ?? CallKind.voice;
      await _ensureStarted(kind, controller);

      final answer = await _session!.createAnswer(offer);
      _remoteDescriptionSet = true;
      await _flushPendingIce();

      return answer;
    };

    controller.onRemoteSdp = (sdp) async {
      // createAnswer() вече задава remote offer.
      // Тук обработваме remote answer на инициатора.
      if (sdp['type'] == 'answer') {
        final kind = controller.call?.kind ?? CallKind.voice;
        await _ensureStarted(kind, controller);
        await _session!.setRemoteDescription(sdp);
        _remoteDescriptionSet = true;
        await _flushPendingIce();
      }
    };

    controller.onRemoteIce = (candidate) async {
      if (!_remoteDescriptionSet || _session == null) {
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

    // Не допускай две едновременни инициализации.
    while (_starting) {
      await Future<void>.delayed(const Duration(milliseconds: 30));

      if (_session != null && _callId == call.callId) {
        return;
      }
    }

    _starting = true;

    try {
      await _stopSession();

      final granted = await CallPermissions.ensure(kind);
      if (!granted) {
        throw StateError(
          'Необходим е достъп до микрофона'
          '${kind == CallKind.video ? ' и камерата' : ''}.',
        );
      }

      final session = WebRtcSession();
      _session = session;
      _callId = call.callId;

      _remoteDescriptionSet = false;
      _pendingIce.clear();

      _subscriptions.add(
        session.localStream$.listen((stream) {
          if (!_localController.isClosed) {
            _localController.add(stream);
          }
        }),
      );

      _subscriptions.add(
        session.remoteStream$.listen((stream) {
          if (!_remoteController.isClosed) {
            _remoteController.add(stream);
          }
        }),
      );

      _subscriptions.add(
        session.iceCandidate$.listen((candidate) {
          unawaited(controller.sendIce(candidate));
        }),
      );

      _subscriptions.add(
        session.connectionState$.listen((state) {
          if (!_stateController.isClosed) {
            _stateController.add(state);
          }

          if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
            controller.markConnected();
          } else if (state ==
                  RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
              state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
            unawaited(controller.hangUp());
          }
        }),
      );

      await session.start(kind: kind);
    } catch (_) {
      await _stopSession();
      rethrow;
    } finally {
      _starting = false;
    }
  }

  Future<void> _flushPendingIce() async {
    final session = _session;
    if (session == null || !_remoteDescriptionSet) return;

    final queued = List<Map<String, dynamic>>.from(_pendingIce);
    _pendingIce.clear();

    for (final candidate in queued) {
      await session.addIceCandidate(candidate);
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
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    final oldSession = _session;
    _session = null;
    _callId = null;
    _remoteDescriptionSet = false;
    _pendingIce.clear();

    if (!_localController.isClosed) _localController.add(null);
    if (!_remoteController.isClosed) _remoteController.add(null);

    if (oldSession != null) {
      await oldSession.closeFully();
    }
  }
}
