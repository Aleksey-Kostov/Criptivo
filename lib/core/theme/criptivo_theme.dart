import 'package:flutter/material.dart';

class CriptivoColors {
  static const background = Color(0xFF050805);
  static const surface = Color(0xFF0B1210);
  static const surfaceLight = Color(0xFF121A17);
  static const neon = Color(0xFF00FF66);
  static const neonDim = Color(0xFF00CC52);
  static const textPrimary = Color(0xFFE8FFE8);
  static const textSecondary = Color(0xFF8FA898);
  static const error = Color(0xFFFF5555);
  static const bubbleMe = Color(0xFF0A3D28);
  static const bubbleOther = Color(0xFF1A2220);
}

class CriptivoTheme {
  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: null,
    );

    return base.copyWith(
      scaffoldBackgroundColor: CriptivoColors.background,
      colorScheme: const ColorScheme.dark(
        primary: CriptivoColors.neon,
        secondary: CriptivoColors.neonDim,
        surface: CriptivoColors.surface,
        error: CriptivoColors.error,
        onPrimary: Colors.black,
        onSurface: CriptivoColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: CriptivoColors.surface,
        foregroundColor: CriptivoColors.neon,
        elevation: 0,
        centerTitle: false,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: CriptivoColors.neon,
        foregroundColor: Colors.black,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CriptivoColors.surfaceLight,
        labelStyle: const TextStyle(color: CriptivoColors.textSecondary),
        hintStyle: const TextStyle(color: CriptivoColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: CriptivoColors.neonDim),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: CriptivoColors.neon.withValues(alpha: 0.35),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: CriptivoColors.neon, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: CriptivoColors.neon,
          foregroundColor: Colors.black,
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: CriptivoColors.neon),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: CriptivoColors.neon,
        textColor: CriptivoColors.textPrimary,
      ),
      dividerColor: CriptivoColors.neon.withValues(alpha: 0.15),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: CriptivoColors.surfaceLight,
        contentTextStyle: TextStyle(color: CriptivoColors.textPrimary),
      ),
    );
  }
}
