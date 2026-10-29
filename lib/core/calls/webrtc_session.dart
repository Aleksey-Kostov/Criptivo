import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_models.dart';

/// 1:1 WebRTC сесия (P2P). Медията е DTLS-SRTP.
class WebRtcSession {
  RTCPeerConnection? _pc;
  MediaStream? _local;
  MediaStream? _remote;

  final _remoteController = StreamController<MediaStream?>.broadcast();
  final _localController = StreamController<MediaStream?>.broadcast();
  final _iceController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _connController = StreamController<RTCPeerConnectionState>.broadcast();

  Stream<MediaStream?> get remoteStream$ => _remoteController.stream;
  Stream<MediaStream?> get localStream$ => _localController.stream;
  Stream<Map<String, dynamic>> get iceCandidate$ => _iceController.stream;
  Stream<RTCPeerConnectionState> get connectionState$ => _connController.stream;

  MediaStream? get localStream => _local;
  MediaStream? get remoteStream => _remote;

  bool _isVideo = false;
  bool _micMuted = false;
  bool _camOff = false;

  bool get isMicMuted => _micMuted;
  bool get isCamOff => _camOff;

  /// STUN за dev. За production добави TURN (coturn / Twilio).
  static const iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    // Prod пример:
    // {
    //   'urls': 'turn:turn.criptivo.example:3478',
    //   'username': '...',
    //   'credential': '...',
    // },
  };

  Future<void> start({required CallKind kind}) async {
    await dispose();
    _isVideo = kind == CallKind.video;

    _pc = await createPeerConnection({
      ...iceServers,
      'sdpSemantics': 'unified-plan',
    });

    _pc!.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate == null || c.candidate!.isEmpty) return;
      _iceController.add({
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };

    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('WebRTC connection: $state');
      _connController.add(state);
    };

    _pc!.onTrack = (RTCTrackEvent e) {
      if (e.streams.isEmpty) return;
      _remote = e.streams.first;
      _remoteController.add(_remote);
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

    _local = await navigator.mediaDevices.getUserMedia(constraints);
    _localController.add(_local);

    for (final track in _local!.getTracks()) {
      await _pc!.addTrack(track, _local!);
    }
  }

  Future<Map<String, dynamic>> createOffer() async {
    final pc = _pc;
    if (pc == null) throw StateError('WebRTC not started');

    final offer = await pc.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': _isVideo ? 1 : 0,
    });
    await pc.setLocalDescription(offer);
    return _sdpToMap(offer);
  }

  Future<Map<String, dynamic>> createAnswer(
    Map<String, dynamic> remoteOffer,
  ) async {
    final pc = _pc;
    if (pc == null) throw StateError('WebRTC not started');

    await pc.setRemoteDescription(_mapToSdp(remoteOffer));
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    return _sdpToMap(answer);
  }

  Future<void> setRemoteDescription(Map<String, dynamic> sdp) async {
    final pc = _pc;
    if (pc == null) return;
    await pc.setRemoteDescription(_mapToSdp(sdp));
  }

  Future<void> addIceCandidate(Map<String, dynamic> json) async {
    final pc = _pc;
    if (pc == null) return;
    final candidate = json['candidate'] as String?;
    if (candidate == null || candidate.isEmpty) return;
    try {
      await pc.addCandidate(RTCIceCandidate(
        candidate,
        json['sdpMid'] as String?,
        json['sdpMLineIndex'] as int?,
      ));
    } catch (e) {
      debugPrint('ICE add error: $e');
    }
  }

  Future<void> setMicMuted(bool muted) async {
    _micMuted = muted;
    final tracks = _local?.getAudioTracks() ?? [];
    for (final t in tracks) {
      t.enabled = !muted;
    }
  }

  Future<void> setCameraEnabled(bool enabled) async {
    if (!_isVideo) return;
    _camOff = !enabled;
    final tracks = _local?.getVideoTracks() ?? [];
    for (final t in tracks) {
      t.enabled = enabled;
    }
  }

  Future<void> switchCamera() async {
    if (!_isVideo) return;
    final tracks = _local?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (e) {
      debugPrint('switchCamera: $e');
    }
  }

  Future<void> setSpeakerphone(bool on) async {
    try {
      await Helper.setSpeakerphoneOn(on);
    } catch (e) {
      debugPrint('setSpeakerphoneOn: $e');
    }
  }

  Map<String, dynamic> _sdpToMap(RTCSessionDescription sdp) => {
        'type': sdp.type,
        'sdp': sdp.sdp,
      };

  RTCSessionDescription _mapToSdp(Map<String, dynamic> map) {
    return RTCSessionDescription(
      map['sdp'] as String?,
      map['type'] as String?,
    );
  }

  Future<void> dispose() async {
    try {
      for (final t in _local?.getTracks() ?? []) {
        await t.stop();
      }
      await _local?.dispose();
    } catch (_) {}
    _local = null;
    _remote = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
  }

  Future<void> closeFully() async {
    await dispose();
    await _remoteController.close();
    await _localController.close();
    await _iceController.close();
    await _connController.close();
  }
}