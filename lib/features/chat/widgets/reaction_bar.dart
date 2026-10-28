import 'package:flutter/material.dart';

import '../../../core/theme/criptivo_theme.dart';

/// Chip-ове под bubble: ❤️ 2  👍 1
class ReactionBar extends StatelessWidget {
  final List<Map<String, dynamic>> aggregated; // from ReactionService.aggregate
  final void Function(String emoji) onToggle;

  const ReactionBar({
    super.key,
    required this.aggregated,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (aggregated.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final r in aggregated)
            GestureDetector(
              onTap: () => onToggle(r['emoji'] as String),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (r['mine'] == true)
                      ? CriptivoColors.neon.withValues(alpha: 0.15)
                      : CriptivoColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (r['mine'] == true)
                        ? CriptivoColors.neon.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Text(
                  '${r['emoji']} ${r['count']}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
