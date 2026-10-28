import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../core/storage/media_local_cache.dart';
import '../../../core/theme/criptivo_theme.dart';

/// Viber-like: muted auto-preview ~5s loop докато е видимо;
/// Play → цялото видео със звук.
class VideoMessageTile extends StatefulWidget {
  final Map<String, dynamic> media; // envelope map: url, key, nonce, name, ...
  final double width;

  const VideoMessageTile({super.key, required this.media, this.width = 240});

  @override
  State<VideoMessageTile> createState() => _VideoMessageTileState();
}

class _VideoMessageTileState extends State<VideoMessageTile> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;
  bool _visible = false;
  bool _expanded = false; // full play with sound
  Timer? _previewTimer;

  String get _url => widget.media['url'] as String;
  String get _key => widget.media['key'] as String;
  String get _nonce => widget.media['nonce'] as String;
  String get _name => (widget.media['name'] as String?) ?? 'video.mp4';

  @override
  void dispose() {
    _previewTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _ensureController() async {
    if (_controller != null || _error != null) return;
    setState(() => _loading = true);
    try {
      final file = await MediaLocalCache.getDecryptedFile(
        url: _url,
        keyBase64: _key,
        nonceBase64: _nonce,
        preferredName: _name,
      );
      if (!mounted) return;
      final c = VideoPlayerController.file(File(file.path));
      await c.initialize();
      await c.setLooping(false);
      await c.setVolume(0);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _loading = false;
      });
      _syncPlayback();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Видеото не може да се зареди';
        _loading = false;
      });
    }
  }

  void _onVisibility(VisibilityInfo info) {
    final visible = info.visibleFraction >= 0.55;
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
      _ensureController();
    }
    _syncPlayback();
  }

  void _syncPlayback() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    if (!_visible && !_expanded) {
      _previewTimer?.cancel();
      if (c.value.isPlaying) c.pause();
      return;
    }

    if (_expanded) {
      _previewTimer?.cancel();
      c.setVolume(1.0);
      if (!c.value.isPlaying) c.play();
      return;
    }

    // Preview mode: muted, 5s then seek 0 and again
    c.setVolume(0);
    _startPreviewLoop(c);
  }

  void _startPreviewLoop(VideoPlayerController c) {
    _previewTimer?.cancel();
    c.seekTo(Duration.zero);
    c.play();
    _previewTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || _expanded || !_visible) {
        _previewTimer?.cancel();
        return;
      }
      final pos = c.value.position;
      if (pos >= const Duration(seconds: 5) ||
          pos >= c.value.duration - const Duration(milliseconds: 100)) {
        c.seekTo(Duration.zero);
        c.play();
      } else if (!c.value.isPlaying) {
        c.play();
      }
    });
  }

  Future<void> _toggleExpand() async {
    final c = _controller;
    if (c == null) {
      await _ensureController();
    }
    if (!mounted) return;
    setState(() => _expanded = !_expanded);
    final ctrl = _controller;
    if (ctrl == null) return;
    if (_expanded) {
      _previewTimer?.cancel();
      await ctrl.setVolume(1.0);
      await ctrl.seekTo(Duration.zero);
      await ctrl.play();
    } else {
      await ctrl.setVolume(0);
      _syncPlayback();
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('video_${_url.hashCode}'),
      onVisibilityChanged: _onVisibility,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: widget.width,
          color: Colors.black,
          child: AspectRatio(
            aspectRatio: _controller?.value.isInitialized == true
                ? _controller!.value.aspectRatio
                : 16 / 9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_controller?.value.isInitialized == true)
                  VideoPlayer(_controller!)
                else if (_loading)
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: CriptivoColors.neon,
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error ?? '🎬',
                      style: const TextStyle(
                        color: CriptivoColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                // gradient + play
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.45),
                        ],
                      ),
                    ),
                  ),
                ),
                Material(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _toggleExpand,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        _expanded && (_controller?.value.isPlaying ?? false)
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ),
                if (!_expanded)
                  const Positioned(
                    left: 8,
                    bottom: 8,
                    child: Text(
                      'Preview · muted',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
