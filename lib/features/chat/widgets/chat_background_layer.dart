import 'package:flutter/material.dart';

import '../../../core/theme/chat_background_style.dart';
import '../../../core/theme/criptivo_theme.dart';

/// Фон + scrim за chat body. Ползва се в Stack под съобщенията.
class ChatBackgroundLayer extends StatelessWidget {
  const ChatBackgroundLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final asset = ChatBackgroundStyle.assetFor(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          asset,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            // Ако light/dark файлът липсва → legacy
            return Image.asset(
              ChatBackgroundStyle.assetLegacy,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: CriptivoColors.background),
            );
          },
        ),
        ColoredBox(color: ChatBackgroundStyle.scrimFor(context)),
      ],
    );
  }
}
