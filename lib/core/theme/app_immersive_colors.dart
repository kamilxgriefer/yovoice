import 'package:flutter/material.dart';

/// Explicit palette for product areas that intentionally stay dark in both
/// appearance preferences (voice/call rooms, recording, story/media review,
/// crop tools and the documented creator/staff workspaces).
///
/// These values must only be used inside a complete immersive atom, normally
/// one hosted by `YoImmersiveDarkSurface`. Normal product routes must use
/// `AppPalette` or `ColorScheme` so Pearl never inherits a dark literal.
class AppImmersiveColors {
  AppImmersiveColors._();

  static const Color background = Color(0xFF0D0618);
  static const Color surface = Color(0xFF191329);
  static const Color surfaceRaised = Color(0xFF241B39);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB4ADC8);
  static const Color textTertiary = Color(0xFF7E7895);
  static const Color authTextTertiary = Color(0xFF958B9F);
  static const Color navigationInactive = Color(0xFF9189A6);

  static const Color border = Color(0xFF3A3151);
  static const Color authBorderStrong = Color(0xFF7C6790);
  static const Color divider = Color(0xFF2B233F);

  /// Social-provider controls belong exclusively to the documented
  /// immersive authentication atom. Keeping these values here makes that
  /// fixed-dark contract explicit instead of disguising them as app-wide
  /// semantic colours.
  static const Color authSocialBorder = Color(0xFF7C6790);
  static const Color authSocialDisabledBorder = Color(0xFF5C506D);
}
