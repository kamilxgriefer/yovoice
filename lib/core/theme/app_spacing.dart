class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;
}

/// The VERTICAL rhythm of a page: six named steps, all multiples of four.
///
/// [AppSpacing] is the generic scale; `AppRhythm` names what each step
/// MEANS on a scrolling page, so a gap can be read from the source without
/// measuring a screenshot. Home is the first surface that consumes it end
/// to end — a vertical gap on Home that is not one of these six is a bug,
/// not a nuance.
///
/// The rule these steps depend on: a page child's LAYOUT box must equal its
/// INK box. Spacing lives BETWEEN boxes, never inside a hit target, so the
/// declared number and the number the eye sees are the same number. Where a
/// component has to reserve a 44 px target around smaller ink (the section
/// heading's "View all"), it subtracts that air from the gap it declares —
/// see `HomeSectionHeader`.
class AppRhythm {
  AppRhythm._();

  /// Inside one lockup: greeting → name, label → value.
  static const double hairline = AppSpacing.xs; // 4

  /// Parts of one control, or two rows inside one card.
  static const double tight = AppSpacing.sm; // 8

  /// Sibling blocks inside a section, and the pitch of a rail's tiles.
  ///
  /// The one literal in this class: [AppSpacing] has no 12, and this app
  /// already uses 12 everywhere as its "related blocks" gap.
  static const double item = 12;

  /// A section title → its own content. Also a card's inner padding and the
  /// page's top band.
  static const double title = AppSpacing.md; // 16

  /// Content → the NEXT section title.
  static const double section = AppSpacing.lg; // 24

  /// The last content → the end of the scroll.
  static const double page = AppSpacing.xl; // 32
}
