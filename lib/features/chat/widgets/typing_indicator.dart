import 'package:flutter/material.dart';

import '../../../core/theme/criptivo_theme.dart';

class TypingIndicator extends StatelessWidget {
  final String name;
  final bool visible;

  const TypingIndicator({
    super.key,
    required this.name,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: visible
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$name пише…',
                  style: TextStyle(
                    color: CriptivoColors.neon.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
