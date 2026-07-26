import 'package:flutter/material.dart';

/// Fixed palette from DESIGN.md §1.1 — deliberately not Material You dynamic
/// color. The same warm, low-stimulation surface every time, independent of
/// device wallpaper.
abstract final class AppColors {
  // Dark ("void") — default.
  static const voidBg = Color(0xFF0A0A0B);
  static const card = Color(0xFF16150F);
  static const line = Color(0xFF2A2823);
  static const ink = Color(0xFFF3F1EC);
  static const inkMuted = Color(0xFF96938C);
  static const ember = Color(0xFFD69A52);

  // Light — same ember accent, per DESIGN.md §1.1.
  static const lightBg = Color(0xFFFAF9F6);
  static const lightInk = Color(0xFF1C1B18);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightLine = Color(0xFFE4E1D8);
  static const lightInkMuted = Color(0xFF716E67);
}

abstract final class AppTheme {
  static ThemeData get dark => _buildTheme(
        ColorScheme(
          brightness: Brightness.dark,
          primary: AppColors.ember,
          onPrimary: AppColors.voidBg,
          secondary: AppColors.ember,
          onSecondary: AppColors.voidBg,
          surface: AppColors.voidBg,
          onSurface: AppColors.ink,
          surfaceContainerHighest: AppColors.card,
          onSurfaceVariant: AppColors.inkMuted,
          outline: AppColors.line,
          error: const Color(0xFFCF6679),
          onError: AppColors.voidBg,
        ),
      );

  static ThemeData get light => _buildTheme(
        ColorScheme(
          brightness: Brightness.light,
          primary: AppColors.ember,
          onPrimary: AppColors.lightBg,
          secondary: AppColors.ember,
          onSecondary: AppColors.lightBg,
          surface: AppColors.lightBg,
          onSurface: AppColors.lightInk,
          surfaceContainerHighest: AppColors.lightCard,
          onSurfaceVariant: AppColors.lightInkMuted,
          outline: AppColors.lightLine,
          error: const Color(0xFFB3261E),
          onError: Colors.white,
        ),
      );

  static ThemeData _buildTheme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: scheme.onSurface,
          foregroundColor: scheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHighest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
    );
  }
}
