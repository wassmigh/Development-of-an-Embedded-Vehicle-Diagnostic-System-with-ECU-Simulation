import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Backgrounds
  static const Color scaffold = Color(0xFF0D1117);
  static const Color card = Color(0xFF151A23);
  static const Color cardBorder = Color(0xFF1E2A3A);
  static const Color cardHighlight = Color(0xFF1A2332);

  // Accent
  static const Color cyan = Color(0xFF00E5FF);
  static const Color cyanDark = Color(0xFF008B9E);
  static const Color cyanSubtle = Color(0xFF0A2E38);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF6E7681);
  static const Color textMuted = Color(0xFF484F58);

  // Semantic
  static const Color error = Color(0xFFFF453A);
  static const Color warningOrange = Color(0xFFFF9500);
  static const Color warningYellow = Color(0xFFFFD60A);
  static const Color success = Color(0xFF30D158);

  // Gauge
  static const Color gaugeTrack = Color(0xFF1E2A3A);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.scaffold,
      primaryColor: AppColors.cyan,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.cyan,
        secondary: AppColors.cyan,
        surface: AppColors.card,
        error: AppColors.error,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      cardTheme: CardTheme(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.scaffold,
        selectedItemColor: AppColors.cyan,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}
