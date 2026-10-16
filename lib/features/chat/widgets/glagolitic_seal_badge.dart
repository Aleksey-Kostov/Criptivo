import 'package:flutter/material.dart';

import '../../../core/theme/criptivo_theme.dart';

/// Жив Glagolitic Seal — визуална проверка за E2EE.
///
/// - Пулсираща neon аура
/// - Плавна смяна при нов глиф
/// - Long-press → Safety Number
class GlagoliticSealBadge extends StatefulWidget {
  final String glyph;
  final VoidCallback? onLongPress;
  final double size;

  const GlagoliticSealBadge({
    super.key,
    required this.glyph,
    this.onLongPress,
    this.size = 28,
  });

  @override
  State<GlagoliticSealBadge> createState() => _GlagoliticSealBadgeState();
}

class _GlagoliticSealBadgeState extends State<GlagoliticSealBadge>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _swapController;
  late final Animation<double> _pulse;
  late final Animation<double> _fade;

  String _currentGlyph = '';
  String _incomingGlyph = '';

  static const _glyphStyle = TextStyle(
    fontFamily: 'NotoSansGlagolitic',
    color: CriptivoColors.neon,
    fontWeight: FontWeight.w500,
    height: 1,
  );

  @override
  void initState() {
    super.initState();
    _currentGlyph = widget.glyph;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _swapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _swapController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didUpdateWidget(covariant GlagoliticSealBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.glyph != widget.glyph && widget.glyph != _currentGlyph) {
      _incomingGlyph = widget.glyph;
      _swapController.forward(from: 0).then((_) {
        if (!mounted) return;
        setState(() {
          _currentGlyph = _incomingGlyph;
          _incomingGlyph = '';
        });
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _swapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Жив печат (E2EE)\nЗадръж за Safety Number',
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulseController, _swapController]),
          builder: (context, _) {
            final glow = _pulse.value;

            return Container(
              width: widget.size + 16,
              height: widget.size + 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: CriptivoColors.neon.withValues(alpha: glow * 0.45),
                    blurRadius: 14 + glow * 10,
                    spreadRadius: glow * 2,
                  ),
                ],
                border: Border.all(
                  color: CriptivoColors.neon.withValues(
                    alpha: 0.25 + glow * 0.35,
                  ),
                  width: 1.2,
                ),
                gradient: RadialGradient(
                  colors: [
                    CriptivoColors.neon.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Старият глиф (избледнява)
                  Opacity(
                    opacity: 1.0 - _fade.value,
                    child: Text(
                      _currentGlyph,
                      style: _glyphStyle.copyWith(fontSize: widget.size),
                    ),
                  ),
                  // Новият глиф (появява се)
                  if (_incomingGlyph.isNotEmpty)
                    Opacity(
                      opacity: _fade.value,
                      child: Transform.scale(
                        scale: 0.85 + (_fade.value * 0.15),
                        child: Text(
                          _incomingGlyph,
                          style: _glyphStyle.copyWith(fontSize: widget.size),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
