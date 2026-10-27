import 'package:flutter/material.dart';

/// Следи дали списъкът е близо до дъното и брои непрочетени докато си нагоре.
class ChatScrollHelper {
  ChatScrollHelper({
    required this.controller,
    this.threshold = 120,
    this.onChanged,
  }) {
    controller.addListener(_onScroll);
  }

  final ScrollController controller;
  final double threshold;
  final VoidCallback? onChanged;

  bool showButton = false;
  int unreadWhileAway = 0;

  bool get isNearBottom {
    if (!controller.hasClients) return true;
    final pos = controller.position;
    if (!pos.hasContentDimensions) return true;
    return pos.maxScrollExtent - pos.pixels < threshold;
  }

  void _onScroll() {
    final near = isNearBottom;
    var changed = false;

    if (near && (showButton || unreadWhileAway > 0)) {
      showButton = false;
      unreadWhileAway = 0;
      changed = true;
    } else if (!near && !showButton) {
      showButton = true;
      changed = true;
    }

    if (changed) onChanged?.call();
  }

  /// Ново входящо съобщение.
  void onIncomingMessage() {
    if (isNearBottom) {
      scrollToBottom();
      return;
    }
    showButton = true;
    unreadWhileAway++;
    onChanged?.call();
  }

  void scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) return;
      final target = controller.position.maxScrollExtent;
      if (animate) {
        controller.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        controller.jumpTo(target);
      }
      showButton = false;
      unreadWhileAway = 0;
      onChanged?.call();
    });
  }

  void dispose() {
    controller.removeListener(_onScroll);
  }
}
