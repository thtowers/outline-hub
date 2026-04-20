import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Dark aesthetic palette
  static const Color background = Color(0xFF1E1E1E); // Similar to Granite Dark
  static const Color surface = Color(0xFF282828); // Headerbar / Panels
  static const Color sidebarBackground = Color(0xFF1A1A1A);
  static const Color accent = Color(0xFF3B82F6); // Action color (blueish)
  static const Color textPrimary = Color(0xFFE2E2E2);
  static const Color textSecondary = Color(0xFFA0A0A0);
  static const Color border = Color(0xFF333333);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      colorScheme: const ColorScheme.dark(primary: accent, surface: surface),
      textTheme: TextTheme(
        bodyMedium: GoogleFonts.inter(color: textPrimary),
        bodySmall: GoogleFonts.inter(color: textSecondary),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        space: 1,
        thickness: 1,
      ),
      iconTheme: const IconThemeData(color: textSecondary, size: 20),
    );
  }

  // Code editor specific styling
  static TextStyle get codeTextStyle {
    return GoogleFonts.firaCode(fontSize: 14, color: textPrimary, height: 1.5);
  }
}
