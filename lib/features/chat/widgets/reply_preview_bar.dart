import 'package:flutter/material.dart';

import '../../../core/theme/criptivo_theme.dart';

class ReplyTarget {
  final String messageId;
  final String previewText;
  final bool isMe;

  const ReplyTarget({
    required this.messageId,
    required this.previewText,
    required this.isMe,
  });
}

class ReplyPreviewBar extends StatelessWidget {
  final ReplyTarget target;
  final VoidCallback onClear;

  const ReplyPreviewBar({
    super.key,
    required this.target,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: CriptivoColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: CriptivoColors.neon, width: 3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, color: CriptivoColors.neon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.isMe ? 'Ти' : 'Отговор',
                  style: const TextStyle(
                    color: CriptivoColors.neon,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  target.previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CriptivoColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 18),
            color: CriptivoColors.textSecondary,
          ),
        ],
      ),
    );
  }
}