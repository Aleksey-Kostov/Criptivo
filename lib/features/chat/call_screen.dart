import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/calls/call_controller.dart';
import '../../core/calls/call_media_bridge.dart';
import '../../core/calls/call_models.dart';
import '../../core/theme/criptivo_theme.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallController _controller = CallController.instance;
  final CallMediaBridge _media = CallMediaBridge.instance;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  StreamSubscription<MediaStream?>? _localSubscription;
  StreamSubscription<MediaStream?>? _remoteSubscription;

  bool _renderersReady = false;
  bool _muted = false;
  bool _cameraOff = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _media.attach(_controller);

      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      _localSubscription = _media.localStream$.listen((stream) {
        if (!mounted) return;
        _localRenderer.srcObject = stream;
        setState(() {});
      });

      _remoteSubscription = _media.remoteStream$.listen((stream) {
        if (!mounted) return;
        _remoteRenderer.srcObject = stream;
        setState(() {});
      });

      _localRenderer.srcObject = _media.localStream;
      _remoteRenderer.srcObject = _media.remoteStream;

      _controller.addListener(_onCallChanged);

      if (!mounted) return;
      setState(() => _renderersReady = true);
    } catch (error) {
      debugPrint('Call screen initialization failed: $error');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Неуспешно инициализиране на разговора.'),
          ),
        );
      }
    }
  }

  void _onCallChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _accept() async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      await _controller.acceptIncoming();
    } catch (error) {
      debugPrint('Accept call failed: $error');
      _showError('Неуспешно приемане на разговора.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hangUp() async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      await _controller.hangUp();
    } catch (error) {
      debugPrint('Hang up failed: $error');
      _showError('Разговорът не можа да бъде прекратен.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _reject() async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      await _controller.rejectIncoming();
    } catch (error) {
      debugPrint('Reject call failed: $error');
      _showError('Неуспешно отказване на разговора.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _toggleMic() async {
    final next = !_muted;

    try {
      await _media.setMicMuted(next);
      if (mounted) setState(() => _muted = next);
    } catch (error) {
      debugPrint('Microphone toggle failed: $error');
      _showError('Неуспешна промяна на микрофона.');
    }
  }

  Future<void> _toggleCamera() async {
    final next = !_cameraOff;

    try {
      await _media.setCameraEnabled(!next);
      if (mounted) setState(() => _cameraOff = next);
    } catch (error) {
      debugPrint('Camera toggle failed: $error');
      _showError('Неуспешна промяна на камерата.');
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _media.switchCamera();
    } catch (error) {
      debugPrint('Switch camera failed: $error');
      _showError('Неуспешна смяна на камерата.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _statusText(ActiveCall? call) {
    if (call == null) return 'Няма активен разговор';

    switch (call.status) {
      case CallStatus.idle:
        return 'Готовност';
      case CallStatus.outgoing:
        return 'Изходящо повикване…';
      case CallStatus.incoming:
        return 'Входящо повикване';
      case CallStatus.connecting:
        return 'Свързване…';
      case CallStatus.active:
        return 'Разговорът е активен';
      case CallStatus.ending:
        return 'Прекратяване…';
      case CallStatus.ended:
        return 'Разговорът приключи';
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onCallChanged);

    unawaited(_localSubscription?.cancel());
    unawaited(_remoteSubscription?.cancel());

    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;

    unawaited(_localRenderer.dispose());
    unawaited(_remoteRenderer.dispose());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = _controller.call;

    if (call == null) {
      return Scaffold(
        backgroundColor: CriptivoColors.background,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Разговорът е приключил',
                  style: TextStyle(
                    color: CriptivoColors.textPrimary,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Затвори'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isVideo = call.kind == CallKind.video;
    final incoming = call.status == CallStatus.incoming;
    final active = call.status == CallStatus.active;

    return Scaffold(
      backgroundColor: CriptivoColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            if (isVideo && _renderersReady && active)
              Positioned.fill(
                child: _remoteRenderer.srcObject != null
                    ? RTCVideoView(
                        _remoteRenderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            if (!isVideo || !active)
              Positioned.fill(
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: CriptivoColors.surfaceLight,
                        child: Icon(
                          isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                          color: CriptivoColors.neon,
                          size: 42,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        call.otherDisplayName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: CriptivoColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _statusText(call),
                        style: const TextStyle(
                          color: CriptivoColors.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (isVideo && _renderersReady && active)
              Positioned(
                top: 16,
                right: 16,
                width: 120,
                height: 176,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    color: CriptivoColors.surfaceLight,
                    child: _cameraOff || _localRenderer.srcObject == null
                        ? const Center(
                            child: Icon(
                              Icons.videocam_off_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          )
                        : RTCVideoView(
                            _localRenderer,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (active && isVideo)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Text(
                        call.otherDisplayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (incoming) ...[
                        _ActionButton(
                          icon: Icons.call_end_rounded,
                          color: Colors.red,
                          label: 'Откажи',
                          onPressed: _busy ? null : _reject,
                        ),
                        const SizedBox(width: 32),
                        _ActionButton(
                          icon: Icons.call_rounded,
                          color: Colors.green,
                          label: 'Приеми',
                          onPressed: _busy ? null : _accept,
                        ),
                      ] else ...[
                        _ActionButton(
                          icon: _muted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          color: _muted
                              ? Colors.orange
                              : CriptivoColors.surfaceLight,
                          label: 'Микрофон',
                          onPressed: active ? _toggleMic : null,
                        ),
                        if (isVideo) ...[
                          const SizedBox(width: 16),
                          _ActionButton(
                            icon: _cameraOff
                                ? Icons.videocam_off_rounded
                                : Icons.videocam_rounded,
                            color: _cameraOff
                                ? Colors.orange
                                : CriptivoColors.surfaceLight,
                            label: 'Камера',
                            onPressed: active ? _toggleCamera : null,
                          ),
                          const SizedBox(width: 16),
                          _ActionButton(
                            icon: Icons.cameraswitch_rounded,
                            color: CriptivoColors.surfaceLight,
                            label: 'Смени',
                            onPressed: active ? _switchCamera : null,
                          ),
                        ],
                        const SizedBox(width: 16),
                        _ActionButton(
                          icon: Icons.call_end_rounded,
                          color: Colors.red,
                          label: 'Затвори',
                          onPressed: _busy ? null : _hangUp,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 60,
          height: 60,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
            ),
            onPressed: onPressed,
            child: Icon(icon, size: 25),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}
