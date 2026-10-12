import 'package:flutter/material.dart';

/// Teal = check-in, amber = mobilize — the colour tells the operator which job they're doing.
class AppColors {
  static const teal = Color(0xFF0F8A7A);
  static const tealDark = Color(0xFF0B6B5F);
  static const tealSoft = Color(0xFFE3F4F1);
  static const amber = Color(0xFFE0891A);
  static const amberSoft = Color(0xFFFDF1DF);
  static const green = Color(0xFF1C8A4B);
  static const greenSoft = Color(0xFFE3F4EA);
  static const red = Color(0xFFC8372D);
  static const redSoft = Color(0xFFFBE7E5);
  static const bg = Color(0xFFF4F7F6);
  static const muted = Color(0xFF64746F);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.teal, primary: AppColors.teal, secondary: AppColors.amber);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.bg, elevation: 0, scrolledUnderElevation: 0),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE3E9E7))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
