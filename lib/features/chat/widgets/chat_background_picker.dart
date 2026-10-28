import 'package:flutter/material.dart';

import '../../../core/theme/chat_background_style.dart';
import '../../../core/theme/criptivo_theme.dart';

/// Sheet за избор: Система / Нощ / Ден.
class ChatBackgroundPicker {
  static Future<void> show(BuildContext context, {VoidCallback? onChanged}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: CriptivoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    'Фон на чата',
                    style: TextStyle(
                      color: CriptivoColors.neon,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _tile(
                  ctx,
                  mode: ChatBackgroundMode.system,
                  title: 'Система',
                  subtitle: 'Ден/нощ според устройството',
                  icon: Icons.brightness_auto_rounded,
                  onChanged: onChanged,
                ),
                _tile(
                  ctx,
                  mode: ChatBackgroundMode.dark,
                  title: 'Нощ',
                  subtitle: 'Тъмен фон',
                  icon: Icons.dark_mode_rounded,
                  onChanged: onChanged,
                ),
                _tile(
                  ctx,
                  mode: ChatBackgroundMode.light,
                  title: 'Ден',
                  subtitle: 'Светъл фон',
                  icon: Icons.light_mode_rounded,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _tile(
    BuildContext ctx, {
    required ChatBackgroundMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    VoidCallback? onChanged,
  }) {
    final selected = ChatBackgroundStyle.mode == mode;
    return ListTile(
      leading: Icon(icon, color: CriptivoColors.neon),
      title: Text(
        title,
        style: const TextStyle(color: CriptivoColors.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: CriptivoColors.textSecondary,
          fontSize: 12,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: CriptivoColors.neon)
          : null,
      onTap: () async {
        await ChatBackgroundStyle.setMode(mode);
        onChanged?.call();
        if (ctx.mounted) Navigator.pop(ctx);
      },
    );
  }
}
