import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/chat/voice_recorder_service.dart';
import '../../../core/theme/criptivo_theme.dart';

/// Viber-style mic:
/// - hold → record + pulse
/// - release → send
/// - slide up → lock → Send / Delete
/// - slide left → cancel on release
class VoiceRecordButton extends StatefulWidget {
  final VoiceRecorderService recorder;
  final Future<void> Function(VoiceRecording recording) onRecorded;
  final VoidCallback? onCancel;
  final ValueChanged<bool>? onRecordingChanged;
  final bool enabled;

  const VoiceRecordButton({
    super.key,
    required this.recorder,
    required this.onRecorded,
    this.onCancel,
    this.onRecordingChanged,
    this.enabled = true,
  });

  @override
  State<VoiceRecordButton> createState() => VoiceRecordButtonState();
}

class VoiceRecordButtonState extends State<VoiceRecordButton>
    with SingleTickerProviderStateMixin {
  bool _recording = false;
  bool _locked = false;
  bool _willCancel = false;
  Duration _elapsed = Duration.zero;
  StreamSubscription<Duration>? _sub;

  late final AnimationController _pulse;

  static const _lockOffsetY = -48.0;
  static const _cancelOffsetX = -64.0;

  bool get isRecording => _recording;
  bool get isLocked => _locked;
  Duration get elapsed => _elapsed;
  bool get willCancel => _willCancel;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> begin() async {
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
    widget.onRecordingChanged?.call(true);
    _pulse.repeat(reverse: true);
    _sub?.cancel();
    _sub = widget.recorder.elapsedStream.listen((d) {
      if (mounted) setState(() => _elapsed = d);
    });
  }

  Future<void> finish({required bool cancel}) async {
    if (!_recording) return;
    _sub?.cancel();
    _sub = null;
    _pulse.stop();
    _pulse.value = 0;

    final result = await widget.recorder.stop(cancel: cancel);
    if (!mounted) return;

    setState(() {
      _recording = false;
      _locked = false;
      _willCancel = false;
      _elapsed = Duration.zero;
    });
    widget.onRecordingChanged?.call(false);

    if (cancel || result == null) {
      widget.onCancel?.call();
      return;
    }
    await widget.onRecorded(result);
  }

  void handleMove(Offset offsetFromOrigin) {
    if (!_recording || _locked) return;
    final dy = offsetFromOrigin.dy;
    final dx = offsetFromOrigin.dx;

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

  void handleRelease() {
    if (!_recording) return;
    if (_locked) return; // чака явни Send / Delete
    finish(cancel: _willCancel);
  }

  String formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // Само mic бутонът. Записният strip е в ChatInputBar.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: widget.enabled && !_recording ? (_) => begin() : null,
      onPointerMove: _recording && !_locked
          ? (e) {
              // локално отместване от центъра на бутона
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final origin = box.size.center(Offset.zero);
              final local = box.globalToLocal(e.position);
              handleMove(local - origin);
            }
          : null,
      onPointerUp: _recording && !_locked ? (_) => handleRelease() : null,
      onPointerCancel: _recording && !_locked
          ? (_) => finish(cancel: true)
          : null,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final scale = _recording ? 1.15 + (_pulse.value * 0.12) : 1.0;
          final glow = _recording ? 0.35 + (_pulse.value * 0.35) : 0.0;
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _recording
                    ? (_willCancel
                          ? CriptivoColors.error.withValues(alpha: 0.2)
                          : CriptivoColors.neon.withValues(alpha: 0.18))
                    : Colors.transparent,
                boxShadow: _recording && !_willCancel
                    ? [
                        BoxShadow(
                          color: CriptivoColors.neon.withValues(alpha: glow),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                _willCancel ? Icons.delete_outline : Icons.mic_rounded,
                color: !widget.enabled
                    ? CriptivoColors.textSecondary
                    : _willCancel
                    ? CriptivoColors.error
                    : CriptivoColors.neon,
                size: 26,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Пълна лента при запис (слага се вместо input row).
class VoiceRecordingStrip extends StatelessWidget {
  final VoiceRecordButtonState? micState;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  const VoiceRecordingStrip({
    super.key,
    required this.micState,
    required this.onCancel,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final locked = micState?.isLocked ?? false;
    final cancel = micState?.willCancel ?? false;
    final elapsed = micState?.elapsed ?? Duration.zero;
    final time = micState?.formatElapsed(elapsed) ?? '00:00';

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: CriptivoColors.surface.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: cancel
              ? CriptivoColors.error.withValues(alpha: 0.5)
              : CriptivoColors.neon.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.delete_outline, color: CriptivoColors.error),
            tooltip: 'Отмени',
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: cancel ? CriptivoColors.error : CriptivoColors.neon,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            time,
            style: const TextStyle(
              color: CriptivoColors.neon,
              fontSize: 16,
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              locked
                  ? 'Заключено — натисни изпрати'
                  : cancel
                  ? 'Пусни за отмяна'
                  : '↑ заключи   ·   ← отмени   ·   пусни = изпрати',
              style: TextStyle(
                color: CriptivoColors.textSecondary.withValues(alpha: 0.95),
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (locked)
            Material(
              color: CriptivoColors.neon,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onSend,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.send_rounded,
                    color: Colors.black,
                    size: 20,
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 44),
        ],
      ),
    );
  }
}
