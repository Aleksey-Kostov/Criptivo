import 'package:flutter/material.dart';

import '../../../core/theme/criptivo_theme.dart';
import 'glagolitic_seal_badge.dart';

/// Горен бар на чата — аватар, име, статус, seal, call / video.
class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final String sealGlyph;
  final bool peerTyping;
  final bool encrypted; // има public key
  final int? disappearSeconds;

  final VoidCallback? onBack;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onSealLongPress;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onDisappear;
  final VoidCallback? onRefresh;
  final VoidCallback? onSafetyNumber;

  const ChatAppBar({
    super.key,
    required this.displayName,
    required this.sealGlyph,
    this.username,
    this.avatarUrl,
    this.peerTyping = false,
    this.encrypted = true,
    this.disappearSeconds,
    this.onBack,
    this.onOpenProfile,
    this.onSealLongPress,
    this.onVoiceCall,
    this.onVideoCall,
    this.onDisappear,
    this.onRefresh,
    this.onSafetyNumber,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  String get _subtitle {
    if (peerTyping) return 'пише…';
    if (!encrypted) return 'Няма ключ · несигурно';
    if (disappearSeconds != null) {
      return 'E2EE · изчезват ${_formatDisappear(disappearSeconds!)}';
    }
    return 'End-to-end · Glagolitic Seal';
  }

  static String _formatDisappear(int sec) {
    if (sec < 60) return '${sec}s';
    if (sec < 3600) return '${sec ~/ 60} мин';
    if (sec < 86400) return '${sec ~/ 3600} ч';
    return '${sec ~/ 86400} д';
  }

  @override
  Widget build(BuildContext context) {
    final initial = displayName.isNotEmpty
        ? displayName.characters.first.toUpperCase()
        : '?';
    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;

    return AppBar(
      backgroundColor: CriptivoColors.surface.withValues(alpha: 0.96),
      elevation: 0,
      scrolledUnderElevation: 0,
      leadingWidth: 48,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        color: CriptivoColors.neon,
        onPressed: onBack ?? () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 0,
      title: InkWell(
        onTap: onOpenProfile,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            children: [
              _Avatar(
                hasAvatar: hasAvatar,
                avatarUrl: avatarUrl,
                initial: initial,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CriptivoColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GlagoliticSealBadge(
                          glyph: sealGlyph,
                          size: 20,
                          onLongPress: onSealLongPress ?? onSafetyNumber,
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: peerTyping
                            ? CriptivoColors.neon
                            : CriptivoColors.textSecondary.withValues(
                                alpha: 0.95,
                              ),
                        fontSize: 12,
                        fontWeight: peerTyping
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Обаждане',
          onPressed:
              onVoiceCall ??
              () => _soon(context, 'Гласовите обаждания идват скоро'),
          icon: const Icon(Icons.call_rounded, size: 22),
          color: CriptivoColors.neon,
        ),
        IconButton(
          tooltip: 'Видео',
          onPressed:
              onVideoCall ??
              () => _soon(context, 'Видео обажданията идват скоро'),
          icon: const Icon(Icons.videocam_rounded, size: 24),
          color: CriptivoColors.neon,
        ),
        PopupMenuButton<_ChatMenuAction>(
          tooltip: 'Още',
          color: CriptivoColors.surfaceLight,
          icon: const Icon(Icons.more_vert_rounded, color: CriptivoColors.neon),
          onSelected: (a) {
            switch (a) {
              case _ChatMenuAction.disappear:
                onDisappear?.call();
              case _ChatMenuAction.safety:
                onSafetyNumber?.call();
              case _ChatMenuAction.refresh:
                onRefresh?.call();
            }
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: _ChatMenuAction.disappear,
              child: Row(
                children: [
                  Icon(
                    disappearSeconds != null
                        ? Icons.timer_rounded
                        : Icons.timer_outlined,
                    color: CriptivoColors.neon,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    disappearSeconds != null
                        ? 'Изчезащи (${_formatDisappear(disappearSeconds!)})'
                        : 'Изчезащи съобщения',
                    style: const TextStyle(color: CriptivoColors.textPrimary),
                  ),
                ],
              ),
            ),
            const PopupMenuItem(
              value: _ChatMenuAction.safety,
              child: Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    color: CriptivoColors.neon,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Safety Number',
                    style: TextStyle(color: CriptivoColors.textPrimary),
                  ),
                ],
              ),
            ),
            const PopupMenuItem(
              value: _ChatMenuAction.refresh,
              child: Row(
                children: [
                  Icon(
                    Icons.refresh_rounded,
                    color: CriptivoColors.neon,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Обнови',
                    style: TextStyle(color: CriptivoColors.textPrimary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  static void _soon(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}

enum _ChatMenuAction { disappear, safety, refresh }

class _Avatar extends StatelessWidget {
  final bool hasAvatar;
  final String? avatarUrl;
  final String initial;

  const _Avatar({
    required this.hasAvatar,
    required this.avatarUrl,
    required this.initial,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: CriptivoColors.neon.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: CriptivoColors.neon.withValues(alpha: 0.12),
            blurRadius: 8,
          ),
        ],
      ),
      child: CircleAvatar(
        backgroundColor: CriptivoColors.surfaceLight,
        backgroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
        child: hasAvatar
            ? null
            : Text(
                initial,
                style: const TextStyle(
                  color: CriptivoColors.neon,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
      ),
    );
  }
}
