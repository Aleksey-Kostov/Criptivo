import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_models.dart';

/// WebRTC сесия за 1:1 аудио и видео разговор.
///
/// WebRTC използва DTLS-SRTP за криптиране на медията при пренос.
/// Това само по себе си не удостоверява самоличността на отсрещния
/// потребител и не замества защитата на сигнализационния протокол.
class WebRtcSession {
  RTCPeerConnection? _pc;
  MediaStream? _local;
  MediaStream? _remote;

  final StreamController<MediaStream?> _remoteController =
      StreamController<MediaStream?>.broadcast();

  final StreamController<MediaStream?> _localController =
      StreamController<MediaStream?>.broadcast();

  final StreamController<Map<String, dynamic>> _iceController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<RTCPeerConnectionState> _connController =
      StreamController<RTCPeerConnectionState>.broadcast();

  Stream<MediaStream?> get remoteStream$ => _remoteController.stream;
  Stream<MediaStream?> get localStream$ => _localController.stream;
  Stream<Map<String, dynamic>> get iceCandidate$ => _iceController.stream;

  Stream<RTCPeerConnectionState> get connectionState$ => _connController.stream;

  MediaStream? get localStream => _local;
  MediaStream? get remoteStream => _remote;

  bool _isVideo = false;
  bool _micMuted = false;
  bool _camOff = false;
  bool _closed = false;

  bool get isMicMuted => _micMuted;
  bool get isCamOff => _camOff;

  /// STUN конфигурация за development.

  static const Map<String, dynamic> iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  Future<void> start({required CallKind kind}) async {
    if (_closed) {
      throw StateError('WebRTC сесията вече е затворена.');
    }

    await dispose();

    if (_closed) {
      throw StateError('WebRTC сесията е затворена.');
    }

    _isVideo = kind == CallKind.video;
    _micMuted = false;
    _camOff = false;

    RTCPeerConnection? pc;
    MediaStream? local;

    try {
      pc = await createPeerConnection(iceServers);

      if (_closed) {
        await pc.close();
        throw StateError('WebRTC сесията е затворена.');
      }

      _pc = pc;

      pc.onIceCandidate = (RTCIceCandidate candidate) {
        if (_closed || !identical(_pc, pc)) return;

        final value = candidate.candidate;
        if (value == null || value.isEmpty) return;

        if (!_iceController.isClosed) {
          _iceController.add({
            'candidate': value,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          });
        }
      };

      pc.onConnectionState = (RTCPeerConnectionState state) {
        if (_closed || !identical(_pc, pc)) return;

        debugPrint('WebRTC connection: $state');

        if (!_connController.isClosed) {
          _connController.add(state);
        }
      };

      pc.onTrack = (RTCTrackEvent event) {
        if (_closed || !identical(_pc, pc)) return;
        if (event.streams.isEmpty) return;

        _remote = event.streams.first;

        if (!_remoteController.isClosed) {
          _remoteController.add(_remote);
        }
      };

      final constraints = <String, dynamic>{
        'audio': true,
        'video': _isVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      };

      local = await navigator.mediaDevices.getUserMedia(constraints);

      if (_closed || !identical(_pc, pc)) {
        for (final track in local.getTracks()) {
          await track.stop();
        }
        await local.dispose();
        throw StateError('WebRTC сесията е прекратена при достъп до медията.');
      }

      _local = local;

      if (!_localController.isClosed) {
        _localController.add(local);
      }

      for (final track in local.getTracks()) {
        if (_closed || !identical(_pc, pc)) {
          throw StateError(
            'WebRTC сесията е прекратена при добавяне на track.',
          );
        }

        await pc.addTrack(track, local);
      }
    } catch (_) {
      // Освобождаваме частично създадените ресурси, ако стартирането
      // се провали по време на създаване на peer connection или media.
      if (identical(_pc, pc)) {
        await dispose();
      } else if (local != null && !identical(_local, local)) {
        try {
          for (final track in local.getTracks()) {
            await track.stop();
          }
          await local.dispose();
        } catch (_) {
          // Запазваме първоначалната грешка.
        }

        if (pc != null) {
          try {
            await pc.close();
          } catch (_) {
            // Запазваме първоначалната грешка.
          }
        }
      }

      rethrow;
    }
  }

  Future<Map<String, dynamic>> createOffer() async {
    final pc = _requirePeerConnection();

    final offer = await pc.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': _isVideo ? 1 : 0,
    });

    _ensureCurrent(pc);

    await pc.setLocalDescription(offer);
    _ensureCurrent(pc);

    return _sdpToMap(offer);
  }

  Future<Map<String, dynamic>> createAnswer(
    Map<String, dynamic> remoteOffer,
  ) async {
    final pc = _requirePeerConnection();
    _validateSdp(remoteOffer, expectedType: 'offer');

    await pc.setRemoteDescription(_mapToSdp(remoteOffer));
    _ensureCurrent(pc);

    final answer = await pc.createAnswer();
    _ensureCurrent(pc);

    await pc.setLocalDescription(answer);
    _ensureCurrent(pc);

    return _sdpToMap(answer);
  }

  Future<void> setRemoteDescription(Map<String, dynamic> sdp) async {
    final pc = _requirePeerConnection();
    _validateSdp(sdp, expectedType: 'answer');

    await pc.setRemoteDescription(_mapToSdp(sdp));
    _ensureCurrent(pc);
  }

  Future<void> addIceCandidate(Map<String, dynamic> json) async {
    final pc = _requirePeerConnection();

    final candidate = json['candidate'];
    if (candidate is! String || candidate.isEmpty) {
      return;
    }

    final mid = json['sdpMid'];
    final lineIndex = json['sdpMLineIndex'];

    if (mid != null && mid is! String) {
      throw const FormatException('Невалиден ICE sdpMid.');
    }

    if (lineIndex != null && lineIndex is! int) {
      throw const FormatException('Невалиден ICE sdpMLineIndex.');
    }

    try {
      await pc.addCandidate(
        RTCIceCandidate(candidate, mid as String?, lineIndex as int?),
      );

      _ensureCurrent(pc);
    } catch (error, stackTrace) {
      debugPrint('WebRTC add ICE candidate failed: $error');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> setMicMuted(bool muted) async {
    _ensureOpen();

    _micMuted = muted;

    final tracks = _local?.getAudioTracks() ?? [];
    for (final track in tracks) {
      track.enabled = !muted;
    }
  }

  Future<void> setCameraEnabled(bool enabled) async {
    _ensureOpen();

    if (!_isVideo) return;

    _camOff = !enabled;

    final tracks = _local?.getVideoTracks() ?? [];
    for (final track in tracks) {
      track.enabled = enabled;
    }
  }

  Future<void> switchCamera() async {
    _ensureOpen();

    if (!_isVideo) return;

    final tracks = _local?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;

    try {
      await Helper.switchCamera(tracks.first);
    } catch (error) {
      debugPrint('WebRTC switch camera failed: $error');
      rethrow;
    }
  }

  Future<void> setSpeakerphone(bool enabled) async {
    _ensureOpen();

    try {
      await Helper.setSpeakerphoneOn(enabled);
    } catch (error) {
      debugPrint('WebRTC speakerphone change failed: $error');
      rethrow;
    }
  }

  Map<String, dynamic> _sdpToMap(RTCSessionDescription sdp) {
    return {'type': sdp.type, 'sdp': sdp.sdp};
  }

  RTCSessionDescription _mapToSdp(Map<String, dynamic> map) {
    return RTCSessionDescription(map['sdp'] as String, map['type'] as String);
  }

  void _validateSdp(Map<String, dynamic> sdp, {required String expectedType}) {
    if (sdp['type'] != expectedType) {
      throw FormatException('Очаква се SDP тип "$expectedType".');
    }

    final value = sdp['sdp'];
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Липсва валидно SDP съдържание.');
    }
  }

  RTCPeerConnection _requirePeerConnection() {
    _ensureOpen();

    final pc = _pc;
    if (pc == null) {
      throw StateError('WebRTC не е стартиран.');
    }

    return pc;
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('WebRTC сесията е затворена.');
    }
  }

  void _ensureCurrent(RTCPeerConnection pc) {
    if (_closed || !identical(_pc, pc)) {
      throw StateError('WebRTC сесията вече не е активна.');
    }
  }

  /// Освобождава peer connection и локалните медийни ресурси.
  ///
  /// Stream контролерите остават отворени, за да може сесията да бъде
  /// стартирана повторно, докато не бъде извикан closeFully().
  Future<void> dispose() async {
    final local = _local;
    final pc = _pc;

    _local = null;
    _remote = null;
    _pc = null;

    if (!_localController.isClosed) {
      _localController.add(null);
    }

    if (!_remoteController.isClosed) {
      _remoteController.add(null);
    }

    if (local != null) {
      try {
        for (final track in local.getTracks()) {
          await track.stop();
        }
      } catch (error) {
        debugPrint('WebRTC stopping local tracks failed: $error');
      }

      try {
        await local.dispose();
      } catch (error) {
        debugPrint('WebRTC disposing local stream failed: $error');
      }
    }

    if (pc != null) {
      try {
        await pc.close();
      } catch (error) {
        debugPrint('WebRTC closing peer connection failed: $error');
      }
    }
  }

  /// Затваря сесията окончателно. След това повторно стартиране
  /// на същия обект не е позволено.
  Future<void> closeFully() async {
    if (_closed) return;

    _closed = true;

    await dispose();

    await _remoteController.close();
    await _localController.close();
    await _iceController.close();
    await _connController.close();
  }
}
