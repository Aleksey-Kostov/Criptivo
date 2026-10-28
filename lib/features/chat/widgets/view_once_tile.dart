import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/crypto/view_once.dart';
import '../../../core/storage/media_service.dart';
import '../../../core/theme/criptivo_theme.dart';

/// Locked tile → tap → показва N секунди → изгаря локално (не в DB).
class ViewOnceTile extends StatefulWidget {
  final Map<String, dynamic> media;
  final String messageId;

  const ViewOnceTile({
    super.key,
    required this.media,
    required this.messageId,
  });

  @override
  State<ViewOnceTile> createState() => _ViewOnceTileState();
}

class _ViewOnceTileState extends State<ViewOnceTile> {
  static final _opened = <String>{}; // per session / device

  bool _revealed = false;
  bool _consumed = false;
  Uint8List? _bytes;
  Timer? _timer;
  int _left = 0;

  @override
  void initState() {
    super.initState();
    if (_opened.contains(widget.messageId)) {
      _consumed = true;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    if (_consumed || _revealed) return;
    setState(() => _revealed = true);
    try {
      final bytes = await MediaService.downloadAndDecrypt(
        url: widget.media['url'] as String,
        keyBase64: widget.media['key'] as String,
        nonceBase64: widget.media['nonce'] as String,
      );
      if (!mounted) return;
      final sec = ViewOnce.seconds(widget.media);
      setState(() {
        _bytes = Uint8List.fromList(bytes);
        _left = sec;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (_left <= 1) {
          t.cancel();
          _opened.add(widget.messageId);
          setState(() {
            _consumed = true;
            _revealed = false;
            _bytes = null;
          });
        } else {
          setState(() => _left--);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _revealed = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_consumed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_off_outlined, color: CriptivoColors.textSecondary),
            SizedBox(width: 8),
            Text(
              'Отворено',
              style: TextStyle(color: CriptivoColors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_revealed && _bytes != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_bytes!, width: 220, fit: BoxFit.cover),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: CircleAvatar(
              radius: 14,
              backgroundColor: Colors.black54,
              child: Text(
                '$_left',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      );
    }

    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: CriptivoColors.neon.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CriptivoColors.neon.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility_outlined, color: CriptivoColors.neon),
            const SizedBox(width: 8),
            Text(
              'Покажи веднъж · ${ViewOnce.seconds(widget.media)}s',
              style: const TextStyle(color: CriptivoColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
