import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_immersive_colors.dart';
import 'app_palette.dart';
import 'app_radius.dart';
import 'app_typography.dart';

/// How much light a gradient disc gives off (refine-look R6 / R14).
///
/// * [rest] — a contact shadow only: the bead sits on the surface.
/// * [lift] — the icon-only CTA's coloured lift (the screen's one CTA).
/// * [lit] — emitted brand light, only for the one clip that is playing.
enum YoDiscEmphasis { rest, lift, lit }

/// The finish recipes of YO Voice 3.x (refine-look spec §3): tokens →
/// `AppFinish` → one primitive per block type. Screens opt in; widgets never
/// hand-roll these decorations or add hex literals of their own.
///
/// **The light budget.** Emitted light (a bloom or a glow) comes only from
/// the real logo, a block that is really LIVE and a voice that is actually
/// playing or recording. Each screen gets at most ONE CTA lift
/// ([actionLift] / [YoDiscEmphasis.lift]) and at most ONE lead block with a
/// [cornerTint]. Every other surface is [block]: a top-lit gradient fill and
/// a hairline, plus a plum contact shadow in Pearl. Dark surfaces emit light;
/// Pearl surfaces receive it.
///
/// **High contrast** brings `borderStrong` back everywhere and removes every
/// decorative gradient, tint and glow; each recipe below takes
/// `highContrast` for that. The exception is a fill that IS the control: the
/// R5 action gradient (white label 5.79:1 or more on both stops) and the R14
/// bead keep their gradient and drop only the lift or glow.
///
/// **Where high contrast reaches.** Flutter reports it on iOS (Increase
/// Contrast) and on the web only under forced colours (Windows contrast
/// themes); Android never reports it and the app has no in-app switch. So no
/// WCAG 1.4.11 boundary may depend on it: every hairline control carries its
/// own identifier at 3:1 or more in the default themes — the icon button's
/// glyph, the chip's label, the search pill's magnifier — and a text input
/// without a glyph keeps `borderStrong`. High contrast is an enhancement on
/// top, never the fallback a control relies on.
///
/// All values are pinned by `test/app_finish_test.dart`.
abstract final class AppFinish {
  // -------------------------------------------------------------------------
  // R2 — block surface
  // -------------------------------------------------------------------------

  /// A complete block decoration: fill, hairline edge, radius and lift. Use
  /// it where a block paints through `Ink` / `DecoratedBox` directly. A block
  /// that clips content (a corner tint) paints [blockFill] behind the clip
  /// and [blockEdge] as a foreground so the tint never covers the edge.
  static BoxDecoration block(
    AppPalette p, {
    BorderRadius radius = AppRadius.block,
    bool hovered = false,
    bool elevated = true,
    bool highContrast = false,
  }) {
    final fill = blockFill(
      p,
      radius: radius,
      hovered: hovered,
      elevated: elevated,
      highContrast: highContrast,
    );
    return BoxDecoration(
      color: fill.color,
      gradient: fill.gradient,
      borderRadius: radius,
      boxShadow: fill.boxShadow,
      border: blockEdge(p, hovered: hovered, highContrast: highContrast),
    );
  }

  /// The block's fill, radius and shadows, without the edge.
  static BoxDecoration blockFill(
    AppPalette p, {
    BorderRadius radius = AppRadius.block,
    bool hovered = false,
    bool elevated = true,
    bool highContrast = false,
  }) => BoxDecoration(
    // Keep `color` null behind the gradient (see `yo_button.dart`).
    color: highContrast ? p.surface : null,
    gradient: highContrast ? null : p.blockGradient,
    borderRadius: radius,
    boxShadow: blockShadows(
      p,
      hovered: hovered,
      elevated: elevated,
      highContrast: highContrast,
    ),
  );

  /// The block's 1 px edge: `hairline`, `hairlineHover` under a pointer,
  /// `borderStrong` under high contrast.
  static Border blockEdge(
    AppPalette p, {
    bool hovered = false,
    bool highContrast = false,
  }) => Border.all(
    color: highContrast
        ? p.borderStrong
        : hovered
        ? p.hairlineHover
        : p.hairline,
  );

  /// Pearl's shadow pair (the drop sinks 10 → 14 on hover); none in Dark,
  /// for chip-like blocks (`elevated: false`) or under high contrast.
  static List<BoxShadow> blockShadows(
    AppPalette p, {
    bool hovered = false,
    bool elevated = true,
    bool highContrast = false,
  }) {
    if (!elevated || highContrast || p.isDark) return const <BoxShadow>[];
    final base = p.blockShadows;
    if (!hovered) return base;
    return <BoxShadow>[
      base.first,
      BoxShadow(
        color: base.last.color,
        blurRadius: base.last.blurRadius,
        offset: const Offset(0, 14),
        spreadRadius: base.last.spreadRadius,
      ),
    ];
  }

  /// The pressed wash over a block (textPrimary @ .06 Dark / .05 Pearl).
  static Color blockPressedWash(AppPalette p) =>
      p.textPrimary.withValues(alpha: p.isDark ? .06 : .05);

  /// The selected block fill (as today): the surface nudged toward focus.
  static Color blockSelectedFill(AppPalette p) =>
      Color.lerp(p.surface, p.focus, .08)!;

  // -------------------------------------------------------------------------
  // R3 — lead-block corner tint (at most one per screen)
  // -------------------------------------------------------------------------

  /// Fixed in px so it is never a wash on a wide card.
  static const double cornerTintSize = 240;
  static const double cornerTintTop = -90;
  static const double cornerTintEnd = -70;

  /// A soft circle of [color] in the top-end corner: peak `tintAlpha`
  /// (.16 Dark / .09 Pearl) fading out by 68 % of the radius.
  static RadialGradient cornerTint(Color color, AppPalette p) => RadialGradient(
    colors: [
      color.withValues(alpha: p.tintAlpha),
      color.withValues(alpha: 0),
    ],
    stops: const [0, .68],
  );

  // -------------------------------------------------------------------------
  // R4 — live block
  // -------------------------------------------------------------------------

  /// The corner light of a LIVE block: the identity accent at .28 / .14 from
  /// the top-end corner, its reach capped at 200 px whatever the card size.
  static RadialGradient liveCorner(
    Color accent,
    AppPalette p, {
    required double shortestSide,
  }) => RadialGradient(
    center: const AlignmentDirectional(.9, -1),
    radius: shortestSide <= 0 ? 1 : math.min(1.0, 200 / shortestSide),
    colors: [
      accent.withValues(alpha: p.isDark ? .28 : .14),
      accent.withValues(alpha: 0),
    ],
    stops: const [0, .72],
  );

  /// The live rim that replaces the block edge on a LIVE thumbnail.
  static Border liveRim(
    AppPalette p, {
    bool hovered = false,
    bool highContrast = false,
  }) {
    if (highContrast) return Border.all(color: AppColors.live, width: 1.5);
    return Border.all(
      color: AppColors.live.withValues(
        alpha: hovered
            ? .45
            : p.isDark
            ? .30
            : .28,
      ),
    );
  }

  /// The under-glow of a LIVE block. It replaces the block's own soft
  /// shadow (never both). Pearl adds a plum drop so the tile still sits on
  /// the paper.
  static List<BoxShadow> liveGlow(
    AppPalette p, {
    bool hovered = false,
    bool pressed = false,
    bool highContrast = false,
  }) {
    if (highContrast) return const <BoxShadow>[];
    final glow = p.liveGlow;
    return <BoxShadow>[
      BoxShadow(
        color: hovered ? glow.withValues(alpha: glow.a * 1.2) : glow,
        blurRadius: 32,
        offset: Offset(0, pressed ? 8 : 14),
        spreadRadius: -12,
      ),
      if (!p.isDark)
        BoxShadow(
          color: p.shadow.withValues(alpha: .10),
          blurRadius: 16,
          offset: const Offset(0, 6),
          spreadRadius: -8,
        ),
    ];
  }

  /// The Dark specular top hairline of a LIVE block: `specular` at the
  /// light's (top-end) side fading out across 70 % of the width. `null` in
  /// Pearl and under high contrast.
  static LinearGradient? liveSpecular(
    AppPalette p, {
    bool highContrast = false,
  }) {
    if (!p.isDark || highContrast) return null;
    return LinearGradient(
      begin: AlignmentDirectional.centerEnd,
      end: AlignmentDirectional.centerStart,
      colors: [p.specular, p.specular.withValues(alpha: 0)],
      stops: const [0, .7],
    );
  }

  // -------------------------------------------------------------------------
  // R5 — labelled primary action lift (the rail CTA's exact values)
  // -------------------------------------------------------------------------

  /// A tight coloured lift under the screen's one labelled CTA. Hover .40 /
  /// blur 22; pressed sinks to y 3 at 60 % alpha. [strength] scales the
  /// alpha (a busy action keeps half its lift).
  static List<BoxShadow> actionLift(
    Color color, {
    bool hovered = false,
    bool pressed = false,
    double strength = 1,
  }) {
    var alpha = hovered ? .40 : .32;
    if (pressed) alpha *= .6;
    alpha *= strength.clamp(0.0, 1.0);
    return <BoxShadow>[
      BoxShadow(
        color: color.withValues(alpha: alpha),
        blurRadius: hovered ? 22 : 18,
        offset: Offset(0, pressed ? 3 : 5),
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // R6 / R14 — gradient disc
  // -------------------------------------------------------------------------

  /// Shadows of a gradient disc of [diameter] px. Geometry scales with the
  /// disc so a 34 px bubble bead and a 96 px record bead read alike. Hover
  /// adds .06 to the contact and the glow.
  static List<BoxShadow> discShadow(
    AppPalette p,
    double diameter,
    YoDiscEmphasis emphasis, {
    bool hovered = false,
  }) {
    final boost = hovered ? .06 : 0.0;
    final contact = BoxShadow(
      color: p.contactShadow.withValues(
        alpha: (p.contactShadow.a + boost).clamp(0.0, 1.0),
      ),
      blurRadius: 4,
      offset: const Offset(0, 2),
    );
    switch (emphasis) {
      case YoDiscEmphasis.rest:
        return <BoxShadow>[contact];
      case YoDiscEmphasis.lift:
        return <BoxShadow>[
          BoxShadow(
            color: p.brandGlow.withValues(
              alpha: (p.brandGlow.a * .6 + boost).clamp(0.0, 1.0),
            ),
            blurRadius: diameter * .36,
            offset: Offset(0, diameter * .14),
            spreadRadius: -diameter * .14,
          ),
        ];
      case YoDiscEmphasis.lit:
        return <BoxShadow>[
          contact,
          BoxShadow(
            color: p.brandGlow.withValues(
              alpha: (p.brandGlow.a + boost).clamp(0.0, 1.0),
            ),
            blurRadius: diameter * .45,
            offset: Offset(0, diameter * .18),
            spreadRadius: -diameter * .12,
          ),
        ];
    }
  }

  /// The bead's gloss: a white @ .28 highlight from the top-left.
  static const RadialGradient discGloss = RadialGradient(
    center: Alignment(-.40, -.60),
    radius: .60,
    colors: [Color(0x47FFFFFF), Color(0x00FFFFFF)],
  );

  /// The bead's 1 px inner rim: white @ .24 at the top, gone by 55 % of the
  /// height.
  static const LinearGradient discRim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x3DFFFFFF), Color(0x00FFFFFF)],
    stops: [0, .55],
  );

  // -------------------------------------------------------------------------
  // R13 / R15 — ink on the outgoing bubble (`AppGradients.primaryAction`)
  // -------------------------------------------------------------------------

  /// Meta text on an outgoing bubble (time, voice duration, "edited", read
  /// state): white @ .92 holds ≥ 5:1 on both stops of `primaryAction` in
  /// both themes. White @ .78 fell to 3.99:1 on the #A117D8 end, below
  /// WCAG 1.4.3 for 11 px text.
  static final Color outgoingMeta = AppColors.white.withValues(alpha: .92);

  /// Played bars of an outgoing voice bubble.
  static const Color outgoingWavePlayed = AppColors.white;

  /// Unplayed bars of an outgoing voice bubble: white @ .35, so the played
  /// (white) part holds ≥ 3:1 against them on both stops (R13). At @ .50 it
  /// was 2.34 – 2.59:1.
  static final Color outgoingWaveUnplayed = AppColors.white.withValues(
    alpha: .35,
  );

  // -------------------------------------------------------------------------
  // R7 — tonal actions
  // -------------------------------------------------------------------------

  /// Neutral glass: the fill of every neutral tonal surface.
  ///
  /// Dark: hover × 1.6, pressed + .04 on the textPrimary tint. Pearl's glass
  /// is a lit surface, so it never darkens on hover — the edge moves to
  /// `hairlineHover` instead ([glassDecoration], [tonalNeutral]) — and a
  /// press lays the block's pressed wash over the lit fill.
  static Color glass(
    AppPalette p, {
    bool hovered = false,
    bool pressed = false,
  }) {
    if (!p.isDark) {
      return pressed ? Color.alphaBlend(blockPressedWash(p), p.glass) : p.glass;
    }
    final base = p.glass.a;
    if (pressed) return p.textPrimary.withValues(alpha: base + .04);
    if (hovered) return p.textPrimary.withValues(alpha: base * 1.6);
    return p.glass;
  }

  /// A neutral glass surface with its control hairline (a header disc, the
  /// neutral tonal action at rest).
  static BoxDecoration glassDecoration(
    AppPalette p, {
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? radius,
    bool hovered = false,
    bool highContrast = false,
  }) => BoxDecoration(
    color: highContrast ? p.surface : glass(p, hovered: hovered),
    shape: shape,
    borderRadius: shape == BoxShape.circle ? null : radius,
    border: Border.all(
      color: highContrast
          ? p.borderStrong
          : hovered
          ? p.hairlineHover
          : p.hairlineControl,
    ),
  );

  /// R7 neutral: glass fill, control hairline, `interactiveForeground` label
  /// (or [foreground], e.g. `textPrimary`). For `OutlinedButton`,
  /// `TextButton` or `FilledButton` — callers keep their widget types and
  /// keys and only pass this style.
  static ButtonStyle tonalNeutral(
    AppPalette p, {
    Color? foreground,
    OutlinedBorder shape = const StadiumBorder(),
    bool highContrast = false,
  }) {
    final ink = foreground ?? p.interactiveForeground;
    return _tonal(
      p,
      shape: shape,
      fill: (states) {
        if (states.contains(WidgetState.disabled)) return Colors.transparent;
        if (highContrast) return p.surface;
        return glass(
          p,
          hovered: states.contains(WidgetState.hovered),
          pressed: states.contains(WidgetState.pressed),
        );
      },
      side: (states) {
        if (states.contains(WidgetState.focused)) {
          return BorderSide(color: p.focus, width: 2);
        }
        if (states.contains(WidgetState.disabled)) {
          return BorderSide(color: p.border);
        }
        if (highContrast) return BorderSide(color: p.borderStrong);
        // Pearl's lit glass does not darken on hover; its edge does.
        if (!p.isDark && states.contains(WidgetState.hovered)) {
          return BorderSide(color: p.hairlineHover);
        }
        return BorderSide(color: p.hairlineControl);
      },
      ink: (states) =>
          states.contains(WidgetState.disabled) ? p.textTertiary : ink,
      weight: FontWeight.w600,
    );
  }

  /// R7 accent: the one voice-reply affordance per block. A faint
  /// `interactiveForeground` wash with a 1.5 px edge and a w700 label.
  static ButtonStyle tonalAccent(
    AppPalette p, {
    OutlinedBorder shape = const StadiumBorder(),
    bool highContrast = false,
  }) {
    final ink = p.interactiveForeground;
    return _tonal(
      p,
      shape: shape,
      fill: (states) {
        if (states.contains(WidgetState.disabled)) return Colors.transparent;
        if (highContrast) return p.surface;
        if (states.contains(WidgetState.pressed)) {
          return ink.withValues(alpha: .14);
        }
        if (states.contains(WidgetState.hovered)) {
          return ink.withValues(alpha: .10);
        }
        return ink.withValues(alpha: .06);
      },
      side: (states) {
        if (states.contains(WidgetState.focused)) {
          return BorderSide(color: p.focus, width: 2);
        }
        if (states.contains(WidgetState.disabled)) {
          return BorderSide(color: p.border);
        }
        return BorderSide(
          color: highContrast ? p.borderStrong : ink.withValues(alpha: .55),
          width: 1.5,
        );
      },
      ink: (states) =>
          states.contains(WidgetState.disabled) ? p.textTertiary : ink,
      weight: FontWeight.w700,
    );
  }

  static ButtonStyle _tonal(
    AppPalette p, {
    required OutlinedBorder shape,
    required Color Function(Set<WidgetState>) fill,
    required BorderSide Function(Set<WidgetState>) side,
    required Color Function(Set<WidgetState>) ink,
    required FontWeight weight,
  }) => ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(fill),
    foregroundColor: WidgetStateProperty.resolveWith(ink),
    iconColor: WidgetStateProperty.resolveWith(ink),
    // The fill carries hover and press; no second wash on top of it.
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    side: WidgetStateProperty.resolveWith(side),
    shape: WidgetStatePropertyAll(shape),
    elevation: const WidgetStatePropertyAll(0),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    // A full Inter style: a bare TextStyle here would replace the theme's
    // label style and drop the font family.
    textStyle: WidgetStatePropertyAll(
      AppTypography.labelLarge.copyWith(fontWeight: weight, letterSpacing: .1),
    ),
  );

  // -------------------------------------------------------------------------
  // R8 — single-select filter chips
  // -------------------------------------------------------------------------

  /// Visual chip height inside the unchanged 48 px target, and its padding.
  static const double chipHeight = 36;
  static const double chipPaddingH = 14;
  static const double chipFontSize = 13;

  /// Chip fill. Selected is an ink inversion (`textPrimary`); unselected is
  /// transparent, glass on hover, textPrimary @ .10 when pressed.
  static Color chipFill(
    AppPalette p, {
    required bool selected,
    bool hovered = false,
    bool pressed = false,
    bool highContrast = false,
  }) {
    if (selected) return p.textPrimary;
    if (pressed) return p.textPrimary.withValues(alpha: .10);
    if (hovered) return p.glass;
    return highContrast ? p.surface : Colors.transparent;
  }

  /// Chip edge: none when selected, the control hairline otherwise, a 2 px
  /// focus ring when focused.
  static Border? chipBorder(
    AppPalette p, {
    required bool selected,
    bool focused = false,
    bool highContrast = false,
  }) {
    if (focused) return Border.all(color: p.focus, width: 2);
    if (selected) return null;
    return Border.all(color: highContrast ? p.borderStrong : p.hairlineControl);
  }

  /// Chip label colour: the canvas on the inverted fill, `textSecondary`
  /// otherwise.
  static Color chipLabel(AppPalette p, {required bool selected}) =>
      selected ? p.background : p.textSecondary;

  static FontWeight chipWeight({required bool selected}) =>
      selected ? FontWeight.w700 : FontWeight.w600;

  /// Chips over media (Yeels): white selected fill with the immersive canvas
  /// as ink; a translucent black plate with white ink otherwise.
  static Color chipOverMediaFill({required bool selected}) =>
      selected ? AppColors.white : overlayChipColor;

  static Color chipOverMediaLabel({required bool selected}) =>
      selected ? AppImmersiveColors.background : AppColors.white;

  static const Color overlayChipColor = Color(0x59000000);

  // -------------------------------------------------------------------------
  // R16 — glyph box
  // -------------------------------------------------------------------------

  /// The glyph box of tiles, Settings and account rows: radius 12 and the
  /// scheme's existing container pair. The icon is `interactiveForeground`.
  static BoxDecoration glyphBox(
    ColorScheme scheme, {
    bool highContrast = false,
  }) => BoxDecoration(
    borderRadius: AppRadius.card,
    color: highContrast ? scheme.primaryContainer : null,
    gradient: highContrast
        ? null
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, scheme.secondaryContainer],
          ),
  );
}
