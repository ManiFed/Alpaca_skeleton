import 'package:flutter/material.dart';

class BSTheme {
  // Design tokens from tour.html
  static const Color night = Color(0xFF02030A);
  static const Color ink = Color(0xFFF2F5FF);
  static const Color ink2 = Color(0xAAF2F5FF); // 66% opacity
  static const Color ink3 = Color(0x66F2F5FF); // 40% opacity
  static const Color accent = Color(0xFF8FD9FF);
  static const Color warm = Color(0xFFFFC07A);
  static const Color success = Color(0xFF5BD6A6);
  static const Color warning = warm;
  static const Color danger = Color(0xFFFF6B6B);
  static const Color glassBorder = Color(0x3DD7E4FF); // rgba(215,228,255,.24)
  static const Color glassBg = Color(0x0BA0B9FF);     // rgba(160,185,255,.045)
  static const Color btnPrimary = Color(0xFFCFEFFF);
  static const Color btnPrimaryFg = Color(0xFF04121C);

  static const String _font = 'Geist';

  static TextStyle? _scale(TextStyle? style, double factor) {
    if (style == null) return null;
    final size = style.fontSize;
    return size != null ? style.copyWith(fontSize: size * factor) : style;
  }

  static TextTheme _scaleTextTheme(TextTheme theme, double factor) {
    return TextTheme(
      displayLarge: _scale(theme.displayLarge, factor),
      displayMedium: _scale(theme.displayMedium, factor),
      displaySmall: _scale(theme.displaySmall, factor),
      headlineLarge: _scale(theme.headlineLarge, factor),
      headlineMedium: _scale(theme.headlineMedium, factor),
      headlineSmall: _scale(theme.headlineSmall, factor),
      titleLarge: _scale(theme.titleLarge, factor),
      titleMedium: _scale(theme.titleMedium, factor),
      titleSmall: _scale(theme.titleSmall, factor),
      bodyLarge: _scale(theme.bodyLarge, factor),
      bodyMedium: _scale(theme.bodyMedium, factor),
      bodySmall: _scale(theme.bodySmall, factor),
      labelLarge: _scale(theme.labelLarge, factor),
      labelMedium: _scale(theme.labelMedium, factor),
      labelSmall: _scale(theme.labelSmall, factor),
    );
  }

  static ThemeData dark() {
    final scheme = const ColorScheme.dark(
      primary: accent,
      onPrimary: btnPrimaryFg,
      secondary: warm,
      onSecondary: night,
      surface: Color(0xFF080C1A),
      onSurface: ink,
      error: danger,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: night,
      fontFamily: _font,
      visualDensity: VisualDensity.comfortable,
    );

    final scaledText = _scaleTextTheme(base.textTheme, 1.0).copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontFamily: _font,
        fontWeight: FontWeight.w600,
        letterSpacing: -2.0,
        color: ink,
        height: 1.0,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontFamily: _font,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.2,
        color: ink,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontFamily: _font,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.0,
        color: ink,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontFamily: _font,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.3,
        color: ink2,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontFamily: _font,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.2,
        color: ink2,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        fontFamily: _font,
        color: ink2,
        letterSpacing: -0.1,
        height: 1.6,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontFamily: _font,
        color: ink2,
        letterSpacing: -0.1,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        fontFamily: _font,
        color: ink3,
        letterSpacing: 0.5,
      ),
      labelSmall: base.textTheme.labelSmall?.copyWith(
        fontFamily: _font,
        color: ink3,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.8,
      ),
    );

    return base.copyWith(
      textTheme: scaledText,
      appBarTheme: const AppBarTheme(
        backgroundColor: night,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _font,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: glassBg,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: glassBorder, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: btnPrimary,
          foregroundColor: btnPrimaryFg,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
            fontFamily: _font,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.2,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink2,
          textStyle: const TextStyle(
            fontFamily: _font,
            fontSize: 15,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.1,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0x12B4D2FF), // rgba(180,210,255,.07)
        contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(100),
          borderSide: const BorderSide(color: glassBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(100),
          borderSide: const BorderSide(color: glassBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(100),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(100),
          borderSide: const BorderSide(color: danger, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(100),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
        hintStyle: const TextStyle(
          fontFamily: _font,
          color: Color(0x59F2F5FF), // 35% opacity
          fontSize: 15,
        ),
        prefixIconColor: ink3,
        suffixIconColor: ink3,
        errorStyle: const TextStyle(
          fontFamily: _font,
          fontSize: 12,
          color: danger,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF0F1428),
        contentTextStyle: TextStyle(
          fontFamily: _font,
          fontSize: 15,
          color: ink,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF080C1A),
        indicatorColor: Color(0x298FD9FF),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
            fontFamily: _font,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
            color: ink2,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: accent);
          }
          return const IconThemeData(color: ink3);
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: glassBorder,
        thickness: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
      ),
    );
  }
}
