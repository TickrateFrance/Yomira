import 'package:flutter/material.dart';

/// "Sakura Soft" theme: deep plum surfaces, sakura-pink accent, lavender
/// secondary, large rounded corners, soft gradients.
class AppTheme {
  // Palette
  static const Color bg = Color(0xFF1E1726); // scaffold
  static const Color surface = Color(0xFF2A2035);
  static const Color surfaceHigh = Color(0xFF362A45);
  static const Color pink = Color(0xFFFF8FB1); // accent
  static const Color lavender = Color(0xFFC4A7E7);
  static const Color text = Color(0xFFF3E9F0);
  static const Color muted = Color(0xFFB9A8C4);

  /// Signature soft gradient (used on splash, headers, nav brand).
  static const LinearGradient softGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3A2A4D), Color(0xFF2A2035), Color(0xFF1E1726)],
  );

  /// Pink → lavender accent gradient for highlights.
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF8FB1), Color(0xFFC4A7E7)],
  );

  static const ColorScheme _scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: pink,
    onPrimary: Color(0xFF45122A),
    primaryContainer: Color(0xFF5A2240),
    onPrimaryContainer: Color(0xFFFFD9E4),
    secondary: lavender,
    onSecondary: Color(0xFF2A1B3D),
    secondaryContainer: Color(0xFF3C2D52),
    onSecondaryContainer: Color(0xFFEADBFF),
    tertiary: Color(0xFF9FD8CB),
    onTertiary: Color(0xFF10322B),
    error: Color(0xFFFF6B81),
    onError: Color(0xFF400512),
    surface: bg,
    onSurface: text,
    onSurfaceVariant: muted,
    surfaceContainerLowest: Color(0xFF181020),
    surfaceContainerLow: Color(0xFF241B30),
    surfaceContainer: surface,
    surfaceContainerHigh: surfaceHigh,
    surfaceContainerHighest: Color(0xFF41324F),
    outline: Color(0xFF4D3F5C),
    outlineVariant: Color(0xFF332940),
    surfaceTint: pink,
  );

  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: _scheme,
      // Transparent so the app-wide background (default color, custom color, or
      // user image — see AppBackground) shows through every screen.
      scaffoldBackgroundColor: Colors.transparent,
      splashFactory: InkSparkle.splashFactory,
    );

    RoundedRectangleBorder r(double radius) =>
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: text,
        displayColor: text,
      ).copyWith(
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: r(18),
        clipBehavior: Clip.antiAlias,
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: _scheme.surfaceContainerHigh,
        selectedColor: _scheme.primaryContainer,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(color: text),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: pink),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(r(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: pink, width: 1.6),
        ),
        hintStyle: const TextStyle(color: muted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _scheme.surfaceContainerLow,
        indicatorColor: _scheme.primaryContainer,
        elevation: 0,
        height: 64,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted),
        ),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? pink : muted,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: _scheme.surfaceContainerLow,
        indicatorColor: _scheme.primaryContainer,
        selectedIconTheme: const IconThemeData(color: pink),
        unselectedIconTheme: const IconThemeData(color: muted),
        selectedLabelTextStyle: const TextStyle(color: text, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: const TextStyle(color: muted),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceHigh,
        shape: r(22),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: pink,
        thumbColor: pink,
        inactiveTrackColor: Color(0xFF41324F),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF332940),
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: muted,
        selectedColor: pink,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: pink),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(color: text),
        shape: r(14),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
