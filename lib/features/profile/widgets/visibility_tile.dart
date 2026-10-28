import 'package:flutter/material.dart';

import '../../../core/profile/profile_privacy.dart';
import '../../../core/theme/criptivo_theme.dart';

class VisibilityTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final ProfileVisibility value;
  final ValueChanged<ProfileVisibility> onChanged;

  const VisibilityTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: CriptivoColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CriptivoColors.neon.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: CriptivoColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: CriptivoColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<ProfileVisibility>(
            segments: const [
              ButtonSegment(
                value: ProfileVisibility.nobody,
                label: Text('Само аз'),
                icon: Icon(Icons.lock_outline, size: 16),
              ),
              ButtonSegment(
                value: ProfileVisibility.everyone,
                label: Text('Всички'),
                icon: Icon(Icons.public, size: 16),
              ),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.black;
                }
                return CriptivoColors.textSecondary;
              }),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return CriptivoColors.neon;
                }
                return CriptivoColors.surface;
              }),
            ),
          ),
        ],
      ),
    );
  }
}