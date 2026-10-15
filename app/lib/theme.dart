import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ProxyProof look: deep academic navy, warm gold accents, ivory paper.
/// Headings in Playfair Display (classic, elegant), everything else in Inter (crisp, legible).
class Brand {
  static const navy = Color(0xFF0B1B3F);
  static const navy2 = Color(0xFF13285A);
  static const navy3 = Color(0xFF1E3A7A);
  static const gold = Color(0xFFD4A73A);
  static const goldSoft = Color(0xFFF1D58A);
  static const ivory = Color(0xFFF8F5EE);
  static const ink = Color(0xFF16203A);
  static const present = Color(0xFF1F8A5B);
  static const review = Color(0xFFC77D12);
  static const absent = Color(0xFFC0392B);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navy, navy2, navy3],
  );

  static const goldGradient = LinearGradient(colors: [Color(0xFFE9C46A), gold, Color(0xFFB8862A)]);

  static List<BoxShadow> softShadow(BuildContext c) => [
    BoxShadow(
      color: (Theme.of(c).brightness == Brightness.dark ? Colors.black : navy).withValues(alpha: 0.10),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];

  static TextStyle display(BuildContext c, {double size = 28, Color? color}) => GoogleFonts.playfairDisplay(
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: color ?? Theme.of(c).colorScheme.onSurface,
    height: 1.15,
  );
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.navy,
    brightness: brightness,
    primary: dark ? Brand.goldSoft : Brand.navy,
    onPrimary: dark ? Brand.navy : Colors.white,
    secondary: Brand.gold,
    onSecondary: Brand.navy,
    surface: dark ? const Color(0xFF0E1630) : Brand.ivory,
    onSurface: dark ? const Color(0xFFE8ECF6) : Brand.ink,
    surfaceContainerLowest: dark ? const Color(0xFF111B3A) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF15204A) : const Color(0xFFFFFDF8),
    error: Brand.absent,
  );
  final text = GoogleFonts.interTextTheme(ThemeData(brightness: brightness).textTheme)
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text,
    // Smooth, modern transitions everywhere (fade + slight slide, supports predictive back).
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: dark ? Colors.white10 : const Color(0xFFE9E3D3)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: dark ? Brand.gold : Brand.navy,
        foregroundColor: dark ? Brand.navy : Colors.white,
        minimumSize: const Size.fromHeight(54),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: dark ? Colors.white24 : const Color(0xFFD9D2BE)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF15204A) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: dark ? Colors.white12 : const Color(0xFFE6DFCC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.gold, width: 1.6),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF0B1330) : Colors.white,
      indicatorColor: Brand.gold.withValues(alpha: dark ? 0.30 : 0.22),
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Brand.navy,
      contentTextStyle: GoogleFonts.inter(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    sliderTheme: const SliderThemeData(activeTrackColor: Brand.gold, thumbColor: Brand.gold),
  );
}
