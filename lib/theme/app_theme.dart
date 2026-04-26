import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/theme_controller.dart';

class AppTheme {
  static ThemeController? _controller;
  static void init(ThemeController controller) => _controller = controller;

  // Dark aesthetic palette
  static const Color darkBackground = Color(0xFF1E1E1E);
  static const Color darkSurface = Color(0xFF282828);
  static const Color darkSidebar = Color(0xFF1A1A1A);
  static const Color darkTextPrimary = Color(0xFFE2E2E2);
  static const Color darkTextSecondary = Color(0xFFA0A0A0);
  static const Color darkBorder = Color(0xFF333333);

  // Light aesthetic palette
  static const Color lightBackground = Color(0xFFF5F5F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSidebar = Color(0xFFF0F0F2);
  static const Color lightTextPrimary = Color(0xFF1D1D1F);
  static const Color lightTextSecondary = Color(0xFF86868B);
  static const Color lightBorder = Color(0xFFD2D2D7);

  static const Color accent = Color(0xFF3B82F6);
  static const Color success = Color(0xFF10B981);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  // Dynamic getters based on current theme mode
  static Color get background =>
      (_controller?.isDarkMode ?? true) ? darkBackground : lightBackground;
  static Color get surface =>
      (_controller?.isDarkMode ?? true) ? darkSurface : lightSurface;
  static Color get sidebarBackground =>
      (_controller?.isDarkMode ?? true) ? darkSidebar : lightSidebar;
  static Color get textPrimary =>
      (_controller?.isDarkMode ?? true) ? darkTextPrimary : lightTextPrimary;
  static Color get textSecondary =>
      (_controller?.isDarkMode ?? true) ? darkTextSecondary : lightTextSecondary;
  static Color get border =>
      (_controller?.isDarkMode ?? true) ? darkBorder : lightBorder;

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      primaryColor: accent,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        surface: darkSurface,
        secondary: accent,
        error: error,
      ),
      textTheme: TextTheme(
        bodyMedium: GoogleFonts.inter(color: darkTextPrimary),
        bodySmall: GoogleFonts.inter(color: darkTextSecondary),
        headlineMedium: GoogleFonts.outfit(
          color: darkTextPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        space: 1,
        thickness: 1,
      ),
      iconTheme: const IconThemeData(color: darkTextSecondary, size: 20),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      primaryColor: accent,
      colorScheme: const ColorScheme.light(
        primary: accent,
        surface: lightSurface,
        secondary: accent,
        error: error,
      ),
      textTheme: TextTheme(
        bodyMedium: GoogleFonts.inter(color: lightTextPrimary),
        bodySmall: GoogleFonts.inter(color: lightTextSecondary),
        headlineMedium: GoogleFonts.outfit(
          color: lightTextPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: lightBorder,
        space: 1,
        thickness: 1,
      ),
      iconTheme: const IconThemeData(color: lightTextSecondary, size: 20),
    );
  }

  static TextStyle get uiStyle => GoogleFonts.outfit();

  static TextStyle get codeTextStyle {
    return GoogleFonts.firaCode(fontSize: 14, height: 1.5);
  }
}
