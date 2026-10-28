import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/storage/media_local_cache.dart';
import '../../../core/storage/media_service.dart';
import '../../../core/theme/criptivo_theme.dart';
import 'video_message_tile.dart';

/// Рендер на media envelope в bubble.
class MediaMessageContent extends StatelessWidget {
  final Map<String, dynamic> media;

  const MediaMessageContent({super.key, required this.media});

  String get _type => (media['type'] as String?) ?? 'file';

  @override
  Widget build(BuildContext context) {
    switch (_type) {
      case 'image':
        return _ImageThumb(media: media);
      case 'video':
        return VideoMessageTile(media: media);
      case 'audio':
        return _FileTile(
          media: media,
          icon: Icons.mic_none_rounded,
          label: media['name'] as String? ?? 'Гласово',
        );
      default:
        return _FileTile(
          media: media,
          icon: Icons.insert_drive_file_outlined,
          label: media['name'] as String? ?? 'Файл',
        );
    }
  }
}

class _ImageThumb extends StatefulWidget {
  final Map<String, dynamic> media;
  const _ImageThumb({required this.media});

  @override
  State<_ImageThumb> createState() => _ImageThumbState();
}

class _ImageThumbState extends State<_ImageThumb> {
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await MediaService.downloadAndDecrypt(
        url: widget.media['url'] as String,
        keyBase64: widget.media['key'] as String,
        nonceBase64: widget.media['nonce'] as String,
      );
      if (!mounted) return;
      setState(() {
        _bytes = Uint8List.fromList(bytes);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не може да се зареди';
        _loading = false;
      });
    }
  }

  void _openFull() {
    if (_bytes == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.memory(_bytes!),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 160,
        height: 120,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: CriptivoColors.neon,
          ),
        ),
      );
    }
    if (_error != null || _bytes == null) {
      return Text(
        _error ?? '🖼️',
        style: const TextStyle(color: CriptivoColors.textSecondary),
      );
    }
    return GestureDetector(
      onTap: _openFull,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(_bytes!, width: 220, fit: BoxFit.cover),
      ),
    );
  }
}

class _FileTile extends StatefulWidget {
  final Map<String, dynamic> media;
  final IconData icon;
  final String label;

  const _FileTile({
    required this.media,
    required this.icon,
    required this.label,
  });

  @override
  State<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends State<_FileTile> {
  bool _busy = false;

  Future<void> _downloadOpen() async {
    setState(() => _busy = true);
    try {
      final file = await MediaLocalCache.getDecryptedFile(
        url: widget.media['url'] as String,
        keyBase64: widget.media['key'] as String,
        nonceBase64: widget.media['nonce'] as String,
        preferredName: widget.media['name'] as String? ?? 'file',
      );
      await OpenFilex.open(file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сваляне: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.media['size'];
    final sizeLabel = size is int
        ? '${(size / 1024).toStringAsFixed(0)} KB'
        : '';

    return InkWell(
      onTap: _busy ? null : _downloadOpen,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: CriptivoColors.neon.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, color: CriptivoColors.neon),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CriptivoColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    _busy ? 'Отваряне…' : (sizeLabel.isEmpty ? 'Tap за отваряне' : sizeLabel),
                    style: const TextStyle(
                      color: CriptivoColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: CriptivoColors.neon,
                ),
              )
            else
              const Icon(Icons.download_rounded,
                  color: CriptivoColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}