import 'package:flutter/material.dart';

import '../../../core/theme/criptivo_theme.dart';

class GlagoliticSealBadge extends StatefulWidget {
  final String glyph;
  final VoidCallback? onLongPress;
  final double size;

  const GlagoliticSealBadge({
    super.key,
    required this.glyph,
    this.onLongPress,
    this.size = 32,
  });

  @override
  State<GlagoliticSealBadge> createState() => _GlagoliticSealBadgeState();
}

class _GlagoliticSealBadgeState extends State<GlagoliticSealBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.4, end: 0.9).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Ако още няма глиф, показваме реална глаголица (не точка).
  String get _displayGlyph {
    final g = widget.glyph.trim();
    if (g.isEmpty || g == '·' || g == '.' || g == '•') {
      return 'Ⰰ'; // Azu — винаги видим fallback
    }
    return g;
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Жив печат (E2EE)\nЗадръж за Safety Number',
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final glow = _pulse.value;

            return Container(
              width: widget.size + 20,
              height: widget.size + 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CriptivoColors.surfaceLight,
                boxShadow: [
                  BoxShadow(
                    color: CriptivoColors.neon.withValues(alpha: glow * 0.55),
                    blurRadius: 16 + glow * 12,
                    spreadRadius: 1 + glow * 2,
                  ),
                ],
                border: Border.all(
                  color: CriptivoColors.neon.withValues(
                    alpha: 0.5 + glow * 0.4,
                  ),
                  width: 1.5,
                ),
              ),
              child: Text(
                _displayGlyph,
                textAlign: TextAlign.center,
                style: TextStyle(
                  // Важно: и family, и fallback с интервал
                  fontFamily: 'NotoSansGlagolitic',
                  fontFamilyFallback: const [
                    'Noto Sans Glagolitic',
                    'Segoe UI Historic',
                    'serif',
                  ],
                  fontSize: widget.size,
                  height: 1.0,
                  color: CriptivoColors.neon,
                  fontWeight: FontWeight.w600,
                  // Помага на някои браузъри
                  fontFeatures: const [],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
