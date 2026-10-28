import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Режим на фона в чата.
enum ChatBackgroundMode {
  /// Следва системната тема (light/dark).
  system,

  /// Винаги тъмен фон.
  dark,

  /// Винаги светъл фон.
  light,
}

class ChatBackgroundStyle {
  static const _prefsKey = 'criptivo_chat_bg_mode';

  static const assetDark = 'assets/images/chat_background_dark.png';
  static const assetLight = 'assets/images/chat_background_light.png';

  /// Fallback ако още нямаш преименувани файлове.
  static const assetLegacy = 'assets/images/chat_background.png';

  static ChatBackgroundMode _mode = ChatBackgroundMode.system;

  static ChatBackgroundMode get mode => _mode;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      _mode = ChatBackgroundMode.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => ChatBackgroundMode.system,
      );
    } catch (_) {
      _mode = ChatBackgroundMode.system;
    }
  }

  static Future<void> setMode(ChatBackgroundMode mode) async {
    _mode = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {}
  }

  /// Кой asset да ползваме според mode + Brightness.
  static String assetFor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    switch (_mode) {
      case ChatBackgroundMode.dark:
        return assetDark;
      case ChatBackgroundMode.light:
        return assetLight;
      case ChatBackgroundMode.system:
        return brightness == Brightness.dark ? assetDark : assetLight;
    }
  }

  /// Затъмняване върху снимката — по-силно на dark, по-слабо на light.
  static Color scrimFor(BuildContext context) {
    final asset = assetFor(context);
    final isLight = asset == assetLight;
    if (isLight) {
      return const Color(0xFF050805).withValues(alpha: 0.18);
    }
    return const Color(0xFF050805).withValues(alpha: 0.55);
  }

  static bool isLightSurface(BuildContext context) {
    return assetFor(context) == assetLight;
  }
}
