import 'package:flutter/material.dart';

/// The desktop app's look (desktop/frontend/src/styles.css): the same colours,
/// gradients and rounded cards, light or dark as the phone is set.
@immutable
class VdColors extends ThemeExtension<VdColors> {
  const VdColors({
    required this.bg,
    required this.surface,
    required this.sunken,
    required this.border,
    required this.text,
    required this.muted,
    required this.faint,
    required this.accent,
  });

  final Color bg;
  final Color surface;
  final Color sunken;
  final Color border;
  final Color text;
  final Color muted;
  final Color faint;
  final Color accent;

  /// Purple to cyan: the mic button, headings, progress.
  static const grad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6D5DFC), Color(0xFF9B5CF6), Color(0xFF22C3EE)],
    stops: [0, 0.45, 1],
  );

  /// Red to orange: recording.
  static const gradRec = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF4D6D), Color(0xFFFF8A4C)],
  );

  /// Amber: paused.
  static const gradPaused = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF0B35A), Color(0xFFE88A3A)],
  );

  static const glow = Color(0xFF6D5DFC);
  static const rec = Color(0xFFFF4D6D);
  static const danger = Color(0xFFE5484D);
  static const ok = Color(0xFF12A37F);
  static const warn = Color(0xFFE8A13A);

  static const light = VdColors(
    bg: Color(0xFFF5F6FB),
    surface: Color(0xFFFCFCFE),
    sunken: Color(0x090F1228),
    border: Color(0x1414183C),
    text: Color(0xFF12142B),
    muted: Color(0xFF6A6F8C),
    faint: Color(0xFF9AA0BB),
    accent: Color(0xFF6D5DFC),
  );

  static const dark = VdColors(
    bg: Color(0xFF0B0C16),
    surface: Color(0xFF151624),
    sunken: Color(0x09FFFFFF),
    border: Color(0x12FFFFFF),
    text: Color(0xFFECEEFB),
    muted: Color(0xFF979CBA),
    faint: Color(0xFF686D8A),
    accent: Color(0xFF8B7DFF),
  );

  @override
  VdColors copyWith() => this;

  @override
  VdColors lerp(ThemeExtension<VdColors>? other, double t) => t < 0.5 || other is! VdColors ? this : other;
}

extension VdTheme on BuildContext {
  /// The Voice Desk colours (the plain light or dark ones under another theme, e.g. in tests).
  VdColors get vd {
    final theme = Theme.of(this);
    return theme.extension<VdColors>() ?? (theme.brightness == Brightness.dark ? VdColors.dark : VdColors.light);
  }
}

ThemeData vdTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? VdColors.dark : VdColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: brightness,
    primary: c.accent,
    surface: c.bg,
    onSurface: c.text,
    onSurfaceVariant: c.muted,
    outline: c.border,
    outlineVariant: c.border,
    error: VdColors.danger,
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: BorderSide(color: c.border),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
    cardTheme: CardThemeData(color: c.surface, elevation: 0, margin: EdgeInsets.zero, shape: shape),
    appBarTheme: AppBarTheme(backgroundColor: c.bg, surfaceTintColor: Colors.transparent, foregroundColor: c.text),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accent.withValues(alpha: 0.16),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.border),
      ),
    ),
    dialogTheme: DialogThemeData(backgroundColor: c.surface, surfaceTintColor: Colors.transparent),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    textTheme: Typography.material2021().black
        .apply(bodyColor: c.text, displayColor: c.text)
        .copyWith(
          headlineSmall: TextStyle(
            fontSize: 26,
            height: 1.2,
            letterSpacing: -0.5,
            fontWeight: FontWeight.w700,
            color: c.text,
          ),
        ),
  );
}
