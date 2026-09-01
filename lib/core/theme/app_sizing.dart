/// Shared interaction and control measurements.
///
/// The visual may be smaller than [minimumTouchTarget] when the surrounding
/// hit region remains at least this large (for example a compact icon glyph).
class AppSizing {
  AppSizing._();

  static const double minimumTouchTarget = 44;
  static const double standardControlHeight = 48;
  static const double primaryControlHeight = 58;
}
