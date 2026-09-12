import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The ONE colour that means "join the live conversation".
///
/// Home's accepted reference paints exactly one bright cyan control per
/// screen — the hero's "Dołącz do rozmowy" pill — and reuses the same hue,
/// sparingly, for the three facts that lead to it: the speaker rings on the
/// hero portraits, the eyebrow that names the live place, and the ring plus
/// badge on a friend who has a new Voice Moment. Nothing else in the app may
/// take this colour, which is why it lives behind a named identity rather
/// than as a loose `AppColors.accent` reference: a grep for [JoinAction]
/// answers "where does the join colour appear" exactly.
///
/// Both brightnesses are resolved here so no surface has to reason about
/// theme. Dark uses the brand cyan directly with [AppColors.contrastInk] on
/// it (11.0 : 1). Pearl cannot: `#5CE1E6` on white carries a 1.5 : 1 ink
/// contrast in either direction, so the light fill is the seeded tone from
/// the same hue, which keeps the identity while staying a real control.
abstract final class JoinAction {
  /// The hue the whole identity derives from.
  static const Color seed = AppColors.accent;

  static JoinActionVisuals resolve(Brightness brightness) =>
      brightness == Brightness.dark ? _dark() : _light();

  static JoinActionVisuals _dark() => JoinActionVisuals(
    fill: AppColors.accent,
    ink: AppColors.contrastInk,
    // Hover lightens the fill; pressed darkens it with its own ink. Both
    // are opaque so the control never reveals what is behind a hero cover.
    hover: Color.alphaBlend(
      AppColors.white.withValues(alpha: .06),
      AppColors.accent,
    ),
    pressed: Color.alphaBlend(
      AppColors.contrastInk.withValues(alpha: .12),
      AppColors.accent,
    ),
    ring: AppColors.accent,
    badge: AppColors.accent,
    onBadge: AppColors.contrastInk,
    glow: AppColors.accent.withValues(alpha: .10),
  );

  static JoinActionVisuals _light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    return JoinActionVisuals(
      fill: scheme.primary,
      ink: scheme.onPrimary,
      hover: Color.alphaBlend(
        scheme.onPrimary.withValues(alpha: .08),
        scheme.primary,
      ),
      pressed: Color.alphaBlend(
        Colors.black.withValues(alpha: .12),
        scheme.primary,
      ),
      ring: scheme.primary,
      badge: scheme.primary,
      onBadge: scheme.onPrimary,
      glow: scheme.primary.withValues(alpha: .08),
    );
  }
}

/// The resolved roles of the join identity for one brightness.
@immutable
class JoinActionVisuals {
  const JoinActionVisuals({
    required this.fill,
    required this.ink,
    required this.hover,
    required this.pressed,
    required this.ring,
    required this.badge,
    required this.onBadge,
    required this.glow,
  });

  /// The filled primary control (the hero CTA).
  final Color fill;

  /// Readable content ON [fill]. Also the 2 px focus boundary drawn INSIDE
  /// a filled control, per the UI guide's filled-control rule.
  final Color ink;

  final Color hover;
  final Color pressed;

  /// A 2–3 px ring that means "there is something live/new here": hero
  /// speakers, a friend's new Voice Moment.
  final Color ring;

  /// The small content badge's fill, with [onBadge] as its glyph.
  final Color badge;
  final Color onBadge;

  /// A single restrained radial behind the hero's portraits. Never animated.
  final Color glow;
}
