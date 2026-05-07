// THEME LOCK: light — source: domain signal (consumer health, daytime use, trust/clarity)
// Scaffold.backgroundColor = AppTheme.backgroundLight — ALL screens

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Brand Colors (spec-mandated) ──────────────────────────────────────
  static const Color primaryBlue = Color(0xFF1976D2);
  static const Color primaryBlueDark = Color(0xFF90CAF9);
  static const Color primaryContainer = Color(0xFFD6E8FF);
  static const Color secondaryTeal = Color(0xFF00897B);
  static const Color secondaryContainer = Color(0xFFB2DFDB);
  static const Color errorRed = Color(0xFFD32F2F);
  static const Color errorContainer = Color(0xFFFFDAD6);

  // ── Surface / Background ───────────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFF5F5F5);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFEEF4FF);

  // ── Semantic Colors ────────────────────────────────────────────────────
  static const Color success = Color(0xFF2D7A4F);
  static const Color successContainer = Color(0xFFD4EDDA);
  static const Color warning = Color(0xFFB45309);
  static const Color warningContainer = Color(0xFFFFF3CD);
  static const Color categoryPill = Color(0xFFE91E8C);
  static const Color categoryFood = Color(0xFFFF6B35);
  static const Color categoryAppointment = Color(0xFF1976D2);
  static const Color categoryCalendar = Color(0xFF00897B);
  static const Color categoryShopping = Color(0xFF7B1FA2);
  static const Color categoryGeneral = Color(0xFF546E7A);

  // ── Dark surfaces ──────────────────────────────────────────────────────
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color surfaceVariantDark = Color(0xFF2C2C2C);

  // ── Light Theme ────────────────────────────────────────────────────────
  static ThemeData get lightTheme => _buildTheme(
    brightness: Brightness.light,
    primary: primaryBlue,
    primaryContainer: primaryContainer,
    secondary: secondaryTeal,
    secondaryContainer: secondaryContainer,
    surface: surfaceLight,
    background: backgroundLight,
    error: errorRed,
    errorContainer: errorContainer,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: const Color(0xFF1A1A1A),
    onBackground: const Color(0xFF1A1A1A),
    outline: const Color(0xFFBDBDBD),
    outlineVariant: const Color(0xFFE0E0E0),
  );

  static ThemeData get highContrastLightTheme => _buildTheme(
    brightness: Brightness.light,
    primary: primaryBlue,
    primaryContainer: const Color(0xFF82B1FF),
    secondary: secondaryTeal,
    secondaryContainer: const Color(0xFF80CBC4),
    surface: surfaceLight,
    background: Colors.white,
    error: errorRed,
    errorContainer: errorContainer,
    onPrimary: Colors.white,
    onSecondary: Colors.white,
    onSurface: Colors.black,
    onBackground: Colors.black,
    outline: Colors.black87,
    outlineVariant: Colors.black54,
  );

  // ── Dark Theme ─────────────────────────────────────────────────────────
  static ThemeData get darkTheme => _buildTheme(
    brightness: Brightness.dark,
    primary: primaryBlueDark,
    primaryContainer: const Color(0xFF1565C0),
    secondary: const Color(0xFF4DB6AC),
    secondaryContainer: const Color(0xFF00695C),
    surface: surfaceDark,
    background: backgroundDark,
    error: const Color(0xFFCF6679),
    errorContainer: const Color(0xFF93000A),
    onPrimary: const Color(0xFF003258),
    onSecondary: const Color(0xFF003731),
    onSurface: const Color(0xFFE6E6E6),
    onBackground: const Color(0xFFE6E6E6),
    outline: const Color(0xFF8A8A8A),
    outlineVariant: const Color(0xFF3A3A3A),
  );

  static ThemeData get highContrastDarkTheme => _buildTheme(
    brightness: Brightness.dark,
    primary: primaryBlueDark,
    primaryContainer: const Color(0xFF4D90E6),
    secondary: const Color(0xFF4DB6AC),
    secondaryContainer: const Color(0xFF00897B),
    surface: const Color(0xFF000000),
    background: const Color(0xFF090909),
    error: const Color(0xFFCF6679),
    errorContainer: const Color(0xFF93000A),
    onPrimary: const Color(0xFFB3E5FC),
    onSecondary: const Color(0xFFB2DFDB),
    onSurface: Colors.white,
    onBackground: Colors.white,
    outline: Colors.white70,
    outlineVariant: Colors.white30,
  );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color primary,
    required Color primaryContainer,
    required Color secondary,
    required Color secondaryContainer,
    required Color surface,
    required Color background,
    required Color error,
    required Color errorContainer,
    required Color onPrimary,
    required Color onSecondary,
    required Color onSurface,
    required Color onBackground,
    required Color outline,
    required Color outlineVariant,
  }) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: isDark
          ? const Color(0xFFD6E8FF)
          : const Color(0xFF003258),
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: isDark
          ? const Color(0xFFB2DFDB)
          : const Color(0xFF003731),
      surface: surface,
      onSurface: onSurface,
      error: error,
      onError: Colors.white,
      errorContainer: errorContainer,
      onErrorContainer: isDark
          ? const Color(0xFFFFDAD6)
          : const Color(0xFF410002),
      outline: outline,
      outlineVariant: outlineVariant,
      surfaceContainerHighest: isDark
          ? surfaceVariantDark
          : surfaceVariantLight,
      onSurfaceVariant: isDark
          ? const Color(0xFFBDBDBD)
          : const Color(0xFF616161),
    );

    final textTheme = GoogleFonts.nunitoSansTextTheme(
      TextTheme(
        displayLarge: TextStyle(
          fontSize: 57,
          fontWeight: FontWeight.w400,
          color: onBackground,
        ),
        displayMedium: TextStyle(
          fontSize: 45,
          fontWeight: FontWeight.w400,
          color: onBackground,
        ),
        displaySmall: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w400,
          color: onBackground,
        ),
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: onBackground,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: onBackground,
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: onBackground,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: onBackground,
        ),
        titleMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: onBackground,
        ),
        titleSmall: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: onBackground,
        ),
        bodyLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w400,
          height: 1.6,
          color: onBackground,
        ),
        bodyMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: onBackground,
        ),
        bodySmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.4,
          color: onBackground,
        ),
        labelLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          color: onPrimary,
        ),
        labelMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: onBackground,
        ),
        labelSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
          color: onBackground,
        ),
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      appBarTheme: AppBarThemeData(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        shadowColor: outline.withAlpha(77),
        titleTextStyle: GoogleFonts.nunitoSans(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        color: surface,
        shadowColor: outline.withAlpha(51),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 2,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.nunitoSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary, width: 1.5),
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.nunitoSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.nunitoSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: isDark ? surfaceVariantDark : const Color(0xFFF0F4FF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: error, width: 2),
        ),
        labelStyle: GoogleFonts.nunitoSans(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: onSurface.withAlpha(179),
        ),
        hintStyle: GoogleFonts.nunitoSans(
          fontSize: 16,
          color: onSurface.withAlpha(115),
        ),
        errorStyle: GoogleFonts.nunitoSans(
          fontSize: 13,
          color: error,
          fontWeight: FontWeight.w500,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: errorRed,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: GoogleFonts.nunitoSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.nunitoSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: primary,
            );
          }
          return GoogleFonts.nunitoSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: onSurface.withAlpha(153),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: primary, size: 24);
          }
          return IconThemeData(color: onSurface.withAlpha(153), size: 24);
        }),
        elevation: 4,
        shadowColor: outline.withAlpha(77),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryContainer;
          return outline.withAlpha(77);
        }),
      ),
      dividerTheme: DividerThemeData(
        color: outlineVariant,
        thickness: 1,
        space: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: isDark
            ? const Color(0xFF323232)
            : const Color(0xFF323232),
        contentTextStyle: GoogleFonts.nunitoSans(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        actionTextColor: primaryBlueDark,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: surface,
        elevation: 8,
        titleTextStyle: GoogleFonts.nunitoSans(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        contentTextStyle: GoogleFonts.nunitoSans(
          fontSize: 16,
          color: onSurface,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        elevation: 8,
      ),
    );
  }

  // ── Semantic color helpers ─────────────────────────────────────────────
  static Color categoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'pill':
        return categoryPill;
      case 'food':
        return categoryFood;
      case 'appointment':
        return categoryAppointment;
      case 'calendar':
        return categoryCalendar;
      case 'shopping':
        return categoryShopping;
      default:
        return categoryGeneral;
    }
  }
}
