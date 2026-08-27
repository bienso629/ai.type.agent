import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Dark Backgrounds from templates/index.html
  static const Color bgDark = Color(0xFF0B0F19); // --bs-body-bg
  static const Color sidebarBg = Color(0xFF0D121F); // --tadu-sidebar-bg
  static const Color cardBg = Color(0xFF111827); // --tadu-card-bg
  static const Color inputBg = Color(0xFF070B14); // --tadu-input-bg
  static const Color borderDark = Color(0xFF1E293B); // --tadu-border
  static const Color borderLight = Color(0xFF334155);

  // Tadu Primary Red Palette
  static const Color primary = Color(0xFFDC2626); // Crimson Red (Red 600)
  static const Color primaryHover = Color(0xFFB91C1C); // Red 700
  static const Color primaryLight = Color(0xFFF87171); // Red 400
  static const Color primaryDark = Color(0xFF991B1B); // Red 800

  // Accents
  static const Color accent = Color(0xFF10B981); // Emerald Green
  static const Color accentCyan = Color(0xFF06B6D4); // Cyan 500
  static const Color warning = Color(0xFFF59E0B); // Amber 500
  static const Color danger = Color(0xFFEF4444); // Red 500

  // Aliases for compatibility
  static const Color surfaceDark = Color(0xFF0D121F);
  static const Color cardDark = Color(0xFF111827);

  // Text
  static const Color textWhite = Color(0xFFF8FAFC);
  static const Color textBody = Color(0xFFE2E8F0);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textDim = Color(0xFF64748B);

  // Terminal & Code
  static const Color terminalBg = Color(0xFF070A10);
  static const Color terminalGreen = Color(0xFF22C55E);
  static const Color codeBg = Color(0xFF0F172A);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bgDark,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.cardBg,
        error: AppColors.danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.textWhite,
        onError: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.dark().textTheme,
      ).apply(
        bodyColor: AppColors.textBody,
        displayColor: AppColors.textWhite,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textWhite,
        ),
        iconTheme: const IconThemeData(color: AppColors.textWhite),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: AppColors.borderDark, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputBg,
        hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cardBg,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.borderDark, width: 1),
        ),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.textWhite,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 13,
          color: AppColors.textBody,
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide.none,
          ),
          textStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w500),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return const Color(0xFF94A3B8);
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.inputBg;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.borderDark;
        }),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderDark,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
