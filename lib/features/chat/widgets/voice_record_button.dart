import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/chat/voice_recorder_service.dart';
import '../../../core/theme/criptivo_theme.dart';

/// Viber-like mic: hold to record, slide up to lock.
class VoiceRecordButton extends StatefulWidget {
  final VoiceRecorderService recorder;
  final Future<void> Function(VoiceRecording recording) onRecorded;
  final VoidCallback? onCancel;
  final bool enabled;

  const VoiceRecordButton({
    super.key,
    required this.recorder,
    required this.onRecorded,
    this.onCancel,
    this.enabled = true,
  });

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton> {
  bool _recording = false;
  bool _locked = false;
  bool _willCancel = false;
  Duration _elapsed = Duration.zero;
  StreamSubscription<Duration>? _sub;

  static const _lockOffsetY = -56.0;
  static const _cancelOffsetX = -72.0;

  Future<void> _begin() async {
    if (!widget.enabled || _recording) return;
    final ok = await widget.recorder.start();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Няма достъп до микрофона')),
        );
      }
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _locked = false;
      _willCancel = false;
      _elapsed = Duration.zero;
    });
    _sub?.cancel();
    _sub = widget.recorder.elapsedStream.listen((d) {
      if (mounted) setState(() => _elapsed = d);
    });
  }

  Future<void> _finish({required bool cancel}) async {
    _sub?.cancel();
    _sub = null;
    final result = await widget.recorder.stop(cancel: cancel);
    if (!mounted) return;
    setState(() {
      _recording = false;
      _locked = false;
      _willCancel = false;
      _elapsed = Duration.zero;
    });
    if (cancel || result == null) {
      widget.onCancel?.call();
      return;
    }
    await widget.onRecorded(result);
  }

  void _onLongPressStart(LongPressStartDetails _) => _begin();

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    if (!_recording || _locked) return;
    final dy = d.offsetFromOrigin.dy;
    final dx = d.offsetFromOrigin.dx;

    final lock = dy < _lockOffsetY;
    final cancel = dx < _cancelOffsetX;

    if (lock && !_locked) {
      HapticFeedback.selectionClick();
      widget.recorder.lock();
      setState(() {
        _locked = true;
        _willCancel = false;
      });
      return;
    }
    if (!_locked && cancel != _willCancel) {
      setState(() => _willCancel = cancel);
    }
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    if (!_recording) return;
    if (_locked) return; // чака Stop
    _finish(cancel: _willCancel);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_recording) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_locked) ...[
            IconButton(
              onPressed: () => _finish(cancel: true),
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            ),
            Text(
              _fmt(_elapsed),
              style: const TextStyle(
                color: CriptivoColors.neon,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            IconButton(
              onPressed: () => _finish(cancel: false),
              icon: const Icon(Icons.send_rounded, color: CriptivoColors.neon),
            ),
          ] else ...[
            Icon(
              _willCancel ? Icons.delete_outline : Icons.mic,
              color: _willCancel ? Colors.redAccent : CriptivoColors.neon,
            ),
            const SizedBox(width: 8),
            Text(
              _willCancel ? 'Пусни за отмяна' : '↑ lock  ·  ← отмяна  ${_fmt(_elapsed)}',
              style: TextStyle(
                color: CriptivoColors.textSecondary.withValues(alpha: 0.9),
                fontSize: 12,
              ),
            ),
          ],
        ],
      );
    }

    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMove,
      onLongPressEnd: _onLongPressEnd,
      child: Icon(
        Icons.mic_none_rounded,
        color: widget.enabled
            ? CriptivoColors.neon
            : CriptivoColors.textSecondary,
        size: 26,
      ),
    );
  }
}
