import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/criptivo_theme.dart';

/// Тъмен emoji panel в стил Criptivo.
class ChatEmojiPanel extends StatelessWidget {
  final ValueChanged<String> onEmojiSelected;
  final VoidCallback onBackspace;

  const ChatEmojiPanel({
    super.key,
    required this.onEmojiSelected,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: EmojiPicker(
        onEmojiSelected: (category, emoji) {
          onEmojiSelected(emoji.emoji);
        },
        onBackspacePressed: onBackspace,
        config: Config(
          height: 280,
          checkPlatformCompatibility: true,
          emojiViewConfig: EmojiViewConfig(
            backgroundColor: CriptivoColors.surface,
            columns: 8,
            emojiSizeMax: 28,
            recentsLimit: 28,
            noRecents: const Text(
              'Няма скорошни',
              style: TextStyle(
                color: CriptivoColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          categoryViewConfig: CategoryViewConfig(
            backgroundColor: CriptivoColors.surface,
            indicatorColor: CriptivoColors.neon,
            iconColorSelected: CriptivoColors.neon,
            iconColor: CriptivoColors.textSecondary,
            dividerColor: CriptivoColors.surfaceLight,
          ),
          bottomActionBarConfig: BottomActionBarConfig(
            backgroundColor: CriptivoColors.surface,
            buttonColor: CriptivoColors.surfaceLight,
            buttonIconColor: CriptivoColors.neon,
          ),
          searchViewConfig: SearchViewConfig(
            backgroundColor: CriptivoColors.surface,
            buttonIconColor: CriptivoColors.neon,
            hintText: 'Търси emoji...',
          ),
        ),
      ),
    );
  }
}