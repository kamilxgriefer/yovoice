import 'package:flutter/material.dart' show Color, HSLColor;

/// WCAG 2.x relative-luminance contrast ratio between two opaque colours.
double contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final light = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final dark = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (light + .05) / (dark + .05);
}

/// Returns [color] unchanged when it already reads at [minimumRatio]
/// against [surface]; otherwise walks its lightness away from the surface
/// (darker on a light surface, lighter on a dark one) until it does.
///
/// Achievement cosmetics are authored once, for the dark identity, yet the
/// same title decorates the Pearl theme's white name plate and the desktop
/// sidebar card. Adjusting lightness keeps the hue — legendary stays amber,
/// rare stays blue — while every surface it lands on stays legible. The
/// hue never crosses into an official role colour because only lightness
/// moves.
Color contrastAdjusted(
  Color color, {
  required Color surface,
  double minimumRatio = 4.5,
}) {
  if (contrastRatio(color, surface) >= minimumRatio) return color;
  final darken = surface.computeLuminance() > .18;
  var hsl = HSLColor.fromColor(color);
  for (var step = 0; step < 40; step++) {
    final nextLightness = (hsl.lightness + (darken ? -.025 : .025)).clamp(
      0.0,
      1.0,
    );
    hsl = hsl.withLightness(nextLightness);
    if (contrastRatio(hsl.toColor(), surface) >= minimumRatio) break;
    if (nextLightness == 0 || nextLightness == 1) break;
  }
  return hsl.toColor();
}
