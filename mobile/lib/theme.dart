import 'package:flutter/material.dart';

/// MachineNova palette (from the logo): purple → magenta brand, teal accent.
/// Jobs keep their own colour so the operator always knows what they're doing:
/// teal = check-in, amber = mobilize.
class AppColors {
  // Brand
  static const purple = Color(0xFF8B2CF5);
  static const purpleDark = Color(0xFF6A1FD0);
  static const purpleSoft = Color(0xFFF3EBFF);
  static const magenta = Color(0xFFE030C0);
  static const ink = Color(0xFF17121F);

  // Jobs (teal is the logo teal, deepened so white text on it stays readable)
  static const teal = Color(0xFF0C9278);
  static const tealDark = Color(0xFF087A64);
  static const tealSoft = Color(0xFFE2F7F2);
  static const amber = Color(0xFFE0891A);
  static const amberSoft = Color(0xFFFDF1DF);

  // Status
  static const green = Color(0xFF1C8A4B);
  static const greenSoft = Color(0xFFE3F4EA);
  static const red = Color(0xFFC8372D);
  static const redSoft = Color(0xFFFBE7E5);

  // Surfaces
  static const bg = Color(0xFFF6F4FB);
  static const border = Color(0xFFE7E1F0);
  static const muted = Color(0xFF6F6880);
}

/// The logo's purple → magenta sweep.
const brandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF7A22E8), AppColors.purple, AppColors.magenta],
  stops: [0, .45, 1],
);

const fontFamily = 'Lexend';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.purple,
    primary: AppColors.purple,
    secondary: AppColors.teal,
    surface: Colors.white,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: fontFamily);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.border)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.purple, width: 1.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: AppColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        side: const BorderSide(color: AppColors.border, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentTextStyle: const TextStyle(fontFamily: fontFamily, color: Colors.white),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor:
          WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.purple : null),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.purple),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
  );
}
