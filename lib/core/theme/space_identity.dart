import 'package:flutter/material.dart';

/// The four kinds of space YO Voice can create.
///
/// Deliberately its own enum rather than a reuse of `RoomExperience` or
/// `ClubType`: those are DATA models with real persistence and product
/// invariants behind them, and this is a PRESENTATION concern. A room's
/// experience must never change because someone restyled a card.
enum SpaceKind { community, podcast, club, family }

/// One place that decides what a space type looks like.
///
/// Before this, accent colours were literals scattered across the create
/// selector, the creation screens and the overview — which is how the
/// Family flow ended up wearing Club violet. Every surface that needs to
/// look like a type asks here instead.
///
/// This is a small, closed identity palette, not four design systems: the
/// surfaces, radii, spacing and type scale stay shared, and colour is used for
/// identity, focus and state — never to tint body text.
///
/// The canonical swatches below remain stable because immersive room UI uses
/// them as part of each room family's identity. Normal product screens must
/// call [resolve] instead of placing those swatches directly on a themed
/// surface. The resolved treatment preserves the hue while selecting a tone
/// with accessible foreground and boundary pairs for Dark and Pearl.
@immutable
class SpaceIdentity {
  const SpaceIdentity({
    required this.kind,
    required this.label,
    required this.primary,
    required this.accent,
    required this.surface,
    required this.border,
    required this.icon,
  });

  final SpaceKind kind;

  /// The type's name as a person reads it.
  final String label;

  /// The identity colour: icon container, CTA, focus ring, selected
  /// state, badge.
  final Color primary;

  /// The lighter partner, for gradients, glow and the eyebrow.
  final Color accent;

  /// The dark tint a card or hero sits on. Always dark enough to keep
  /// white body text readable — the base app stays dark.
  final Color surface;

  final Color border;

  final IconData icon;

  static const community = SpaceIdentity(
    kind: SpaceKind.community,
    label: 'Community Room',
    primary: Color(0xFF8A2BE2),
    accent: Color(0xFFC026FF),
    // The existing YO Voice violet surface, unchanged — community is the
    // default experience and must keep looking like the product.
    surface: Color(0xFF171121),
    border: Color(0xFF3A2C49),
    icon: Icons.groups_rounded,
  );

  static const podcast = SpaceIdentity(
    kind: SpaceKind.podcast,
    label: 'Podcast Room',
    primary: Color(0xFFFF3D68),
    accent: Color(0xFFFF6B81),
    surface: Color(0xFF241318),
    border: Color(0xFF63303C),
    icon: Icons.podcasts_rounded,
  );

  static const club = SpaceIdentity(
    kind: SpaceKind.club,
    label: 'Club',
    primary: Color(0xFFD9A441),
    accent: Color(0xFFFFD166),
    surface: Color(0xFF231C10),
    border: Color(0xFF6B5527),
    icon: Icons.shield_rounded,
  );

  static const family = SpaceIdentity(
    kind: SpaceKind.family,
    label: 'Family Room',
    primary: Color(0xFF28D17C),
    accent: Color(0xFF35E58D),
    surface: Color(0xFF12231D),
    border: Color(0xFF286447),
    icon: Icons.family_restroom_rounded,
  );

  static const all = <SpaceIdentity>[community, podcast, club, family];

  static SpaceIdentity of(SpaceKind kind) => switch (kind) {
    SpaceKind.community => community,
    SpaceKind.podcast => podcast,
    SpaceKind.club => club,
    SpaceKind.family => family,
  };

  /// Resolves this stable identity into accessible colours for a normal,
  /// theme-aware product surface.
  ///
  /// Material's tonal palette is deliberately derived from [primary] instead
  /// of duplicating separate Club/Family light-theme literals. This keeps the
  /// identity recognisable while providing matched foreground/container pairs
  /// with WCAG-safe contrast in both brightnesses.
  SpaceIdentityVisuals resolve(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    );
    return SpaceIdentityVisuals(
      surface: scheme.primaryContainer,
      onSurface: scheme.onPrimaryContainer,
      foreground: scheme.primary,
      border: scheme.primary,
      cta: scheme.primary,
      onCta: scheme.onPrimary,
      spinner: scheme.onPrimary,
      heroGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [scheme.primary, scheme.secondary],
      ),
      heroForeground: scheme.onPrimary,
      heroGlow: scheme.primary.withValues(
        alpha: brightness == Brightness.dark ? .28 : .18,
      ),
    );
  }

  // ------------------------------------------------ derived treatments
  //
  // Named so call sites read as intent ("focus border") rather than as a
  // number, and so the alpha values stay consistent across surfaces.

  /// The soft fill behind an icon, chip or badge.
  Color get wash => primary.withValues(alpha: .17);

  /// A selected chip / checked box.
  Color get selected => primary.withValues(alpha: .22);

  /// The outline a focused text field takes.
  Color get focusBorder => primary;

  /// The card's resting outline.
  Color get outline => border;

  /// The subtle bloom under a card or CTA. Subtle on purpose — this is a
  /// dark product, and a strong glow on four cards at once reads as
  /// decoration rather than identity.
  Color get glow => accent.withValues(alpha: .12);

  /// The gradient a primary CTA carries.
  LinearGradient get ctaGradient => LinearGradient(colors: [primary, accent]);

  /// Text that is genuinely part of the identity — an eyebrow, a badge
  /// label, a benefit tick. Never body copy.
  Color get onSurfaceAccent => accent;
}

/// Theme-aware presentation roles derived from a stable [SpaceIdentity].
///
/// These roles are intentionally narrow. General page copy and cards still
/// use `AppPalette`; this object only styles the identity mark, identity copy,
/// branded hero and branded primary action.
@immutable
class SpaceIdentityVisuals {
  const SpaceIdentityVisuals({
    required this.surface,
    required this.onSurface,
    required this.foreground,
    required this.border,
    required this.cta,
    required this.onCta,
    required this.spinner,
    required this.heroGradient,
    required this.heroForeground,
    required this.heroGlow,
  });

  /// Tonal identity container used by compact marks and branded callouts.
  final Color surface;

  /// Readable icon or copy placed on [surface].
  final Color onSurface;

  /// Identity-coloured copy or icon placed on the app's semantic surfaces.
  final Color foreground;

  /// Meaningful identity boundary for [surface].
  final Color border;

  /// Accessible solid background for the primary space action.
  final Color cta;

  /// Foreground paired with [cta].
  final Color onCta;

  /// Progress indicator shown while the CTA is busy.
  final Color spinner;

  /// Accessible, restrained identity gradient for a celebratory hero.
  final LinearGradient heroGradient;

  /// Foreground that remains readable over both [heroGradient] endpoints.
  final Color heroForeground;

  /// Theme-adjusted bloom for the celebratory hero only.
  final Color heroGlow;
}
