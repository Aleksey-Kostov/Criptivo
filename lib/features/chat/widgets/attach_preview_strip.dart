import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/criptivo_theme.dart';

/// Чакащ прикачен файл преди send.
class PendingAttachment {
  final Uint8List? imageBytes; // за снимка preview
  final String name;
  final String mime;
  final String kind; // image | video | file | audio
  final Future<UploadedMediaRef> Function() upload; // криптира+качва при Send

  PendingAttachment({
    required this.name,
    required this.mime,
    required this.kind,
    required this.upload,
    this.imageBytes,
  });
}

/// Минимален резултат след upload (за да не дърпаме целия MediaService тук).
class UploadedMediaRef {
  final String envelopeJson;
  UploadedMediaRef(this.envelopeJson);
}

class AttachPreviewStrip extends StatelessWidget {
  final PendingAttachment attachment;
  final VoidCallback onClear;
  final bool busy;

  const AttachPreviewStrip({
    super.key,
    required this.attachment,
    required this.onClear,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: CriptivoColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CriptivoColors.neon.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          if (attachment.imageBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                attachment.imageBytes!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CriptivoColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(switch (attachment.kind) {
                'video' => Icons.videocam_outlined,
                'audio' => Icons.mic_none_rounded,
                'image' => Icons.image_outlined,
                _ => Icons.insert_drive_file_outlined,
              }, color: CriptivoColors.neon),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CriptivoColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  busy ? 'Качване…' : 'Готово за изпращане',
                  style: TextStyle(
                    color: CriptivoColors.textSecondary.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: busy ? null : onClear,
            icon: const Icon(Icons.close_rounded),
            color: CriptivoColors.textSecondary,
          ),
        ],
      ),
    );
  }
}
