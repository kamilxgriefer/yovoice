import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_palette.dart';

class AppGradients {
  AppGradients._();

  /// The logo's own gradient (#7B2FF7 → #C026FF): icon-only CTA discs and
  /// the voice bead.
  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.secondary],
  );

  /// The labelled primary action: the theme's primary into its AA-safe
  /// secondary (#7B2FF7 → #A117D8 Dark, #6F1FD1 → #A117D8 Pearl) — the same
  /// pair the desktop rail CTA and `YoButton` already paint. White labels
  /// hold at least 5.79:1 across the whole sweep.
  static LinearGradient primaryAction(
    ColorScheme scheme, {
    AlignmentGeometry begin = Alignment.centerLeft,
    AlignmentGeometry end = Alignment.centerRight,
  }) => LinearGradient(
    begin: begin,
    end: end,
    colors: [scheme.primary, scheme.secondary],
  );

  /// The one letter-avatar fill (#6542B8 → #6D1894): the voice violet and
  /// the brand magenta, each pulled toward the Dark canvas. White initials
  /// read 6.94:1 / 9.51:1. No per-person hues.
  static final LinearGradient letterAvatar = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.lerp(AppColors.voice, AppPalette.dark.background, .30)!,
      Color.lerp(AppColors.secondary, AppPalette.dark.background, .45)!,
    ],
  );
}
