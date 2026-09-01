import 'package:flutter/material.dart';

/// Canonical motion timings for shared YO Voice components.
///
/// Product surfaces may choose a different curve when the interaction needs
/// it, but they should resolve the duration through [resolve] so the platform
/// Reduce Motion preference is never bypassed by a decorative transition.
class AppMotion {
  AppMotion._();

  static const Duration quick = Duration(milliseconds: 140);
  static const Duration standard = Duration(milliseconds: 180);
  static const Duration entrance = Duration(milliseconds: 320);

  static const Curve standardCurve = Curves.easeOut;
  static const Curve entranceCurve = Curves.easeOutCubic;

  static Duration resolve(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
