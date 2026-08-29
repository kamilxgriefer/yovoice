import 'package:flutter/material.dart';

/// Semantic YO Voice colours for surfaces that must work in both themes.
///
/// [AppColors] remains the canonical brand/status palette. This extension
/// describes roles that change with brightness: canvas, cards, readable copy,
/// chrome and focus. New or migrated UI should ask for a semantic role instead
/// of copying a dark hex value into a widget.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.backgroundTop,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.navigationSurface,
    required this.navigationInactive,
    required this.shadow,
    required this.scrim,
    required this.focus,
    required this.dangerSurface,
    required this.successSurface,
  });

  final Color background;
  final Color backgroundTop;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color navigationSurface;
  final Color navigationInactive;
  final Color shadow;
  final Color scrim;
  final Color focus;
  final Color dangerSurface;
  final Color successSurface;

  static const dark = AppPalette(
    background: Color(0xFF080711),
    backgroundTop: Color(0xFF130A22),
    surface: Color(0xFF12101D),
    surfaceMuted: Color(0xFF1A1424),
    surfaceRaised: Color(0xFF20182A),
    surfaceSunken: Color(0xFF0C0814),
    border: Color(0xFF30263F),
    borderStrong: Color(0xFF7C6790),
    textPrimary: Color(0xFFF8F5FC),
    textSecondary: Color(0xFFB8AFC2),
    textTertiary: Color(0xFF958B9F),
    navigationSurface: Color(0xFF17111F),
    navigationInactive: Color(0xFF9189A6),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF09050F),
    focus: Color(0xFFD986FF),
    dangerSurface: Color(0xFF32131D),
    successSurface: Color(0xFF10271C),
  );

  /// Pearl — warm white rather than clinical white, with ink copy and a
  /// restrained plum shadow. Purple stays an accent instead of tinting every
  /// surface, which is what keeps the daytime theme premium and calm.
  static const light = AppPalette(
    background: Color(0xFFF6F2F8),
    backgroundTop: Color(0xFFFFFCFF),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF0E9F4),
    surfaceRaised: Color(0xFFFCFAFD),
    surfaceSunken: Color(0xFFE9E1EF),
    border: Color(0xFFD6C8DF),
    borderStrong: Color(0xFF9D88AC),
    textPrimary: Color(0xFF211629),
    textSecondary: Color(0xFF5D5067),
    textTertiary: Color(0xFF74667E),
    navigationSurface: Color(0xFFFFFCFF),
    navigationInactive: Color(0xFF594B63),
    shadow: Color(0xFF3D1F50),
    scrim: Color(0xFF1A1021),
    focus: Color(0xFF6F1DCE),
    dangerSurface: Color(0xFFFDEDF1),
    successSurface: Color(0xFFE8F7EF),
  );

  static AppPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  LinearGradient get backgroundGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundTop, background],
    stops: const [0, .72],
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? backgroundTop,
    Color? surface,
    Color? surfaceMuted,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? navigationSurface,
    Color? navigationInactive,
    Color? shadow,
    Color? scrim,
    Color? focus,
    Color? dangerSurface,
    Color? successSurface,
  }) => AppPalette(
    background: background ?? this.background,
    backgroundTop: backgroundTop ?? this.backgroundTop,
    surface: surface ?? this.surface,
    surfaceMuted: surfaceMuted ?? this.surfaceMuted,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceSunken: surfaceSunken ?? this.surfaceSunken,
    border: border ?? this.border,
    borderStrong: borderStrong ?? this.borderStrong,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    navigationSurface: navigationSurface ?? this.navigationSurface,
    navigationInactive: navigationInactive ?? this.navigationInactive,
    shadow: shadow ?? this.shadow,
    scrim: scrim ?? this.scrim,
    focus: focus ?? this.focus,
    dangerSurface: dangerSurface ?? this.dangerSurface,
    successSurface: successSurface ?? this.successSurface,
  );

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      backgroundTop: Color.lerp(backgroundTop, other.backgroundTop, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      navigationSurface: Color.lerp(
        navigationSurface,
        other.navigationSurface,
        t,
      )!,
      navigationInactive: Color.lerp(
        navigationInactive,
        other.navigationInactive,
        t,
      )!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      dangerSurface: Color.lerp(dangerSurface, other.dangerSurface, t)!,
      successSurface: Color.lerp(successSurface, other.successSurface, t)!,
    );
  }
}

extension AppPaletteBuildContext on BuildContext {
  AppPalette get appPalette => AppPalette.of(this);
}
