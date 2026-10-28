import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/chat/link_preview_service.dart';
import '../../../core/theme/criptivo_theme.dart';

class LinkPreviewCard extends StatefulWidget {
  final String text;

  const LinkPreviewCard({super.key, required this.text});

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  LinkPreviewData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = LinkPreviewService.firstUrl(widget.text);
    if (url == null) {
      setState(() => _loading = false);
      return;
    }
    final data = await LinkPreviewService.fetch(url);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Future<void> _open() async {
    final url = _data?.url;
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 4,
        child: LinearProgressIndicator(
          color: CriptivoColors.neon,
          backgroundColor: Colors.transparent,
        ),
      );
    }
    final d = _data;
    if (d == null) return const SizedBox.shrink();

    final yt = LinkPreviewService.isYoutube(d.url);

    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CriptivoColors.neon.withValues(alpha: 0.2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (d.imageUrl != null && d.imageUrl!.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  d.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: CriptivoColors.surfaceLight,
                    alignment: Alignment.center,
                    child: Icon(
                      yt ? Icons.play_circle_outline : Icons.link,
                      color: CriptivoColors.neon,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (d.siteName != null)
                    Text(
                      d.siteName!,
                      style: const TextStyle(
                        color: CriptivoColors.neon,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (d.title != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      d.title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CriptivoColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (d.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      d.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CriptivoColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
