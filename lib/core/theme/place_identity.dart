import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'space_identity.dart';

/// The five kinds of place a person can belong to, as Home presents them.
///
/// A PRESENTATION vocabulary, not a data model: the legacy club document
/// carries only `community` and `family`, and the V1 server root carries the
/// five server types. Home reads whichever it is handed and asks here for the
/// tint, glyph and readable foreground — it never derives colour from a
/// feature it may not import.
enum PlaceKind {
  friends,
  community,
  podcast,
  family,
  company;

  /// Maps a legacy club `type` string (`club.dart` `ClubType.fromValue`
  /// semantics: `'family'` → family, anything else → community) without
  /// making the theme depend on the clubs feature.
  static PlaceKind fromClubTypeName(Object? value) =>
      value == 'family' ? PlaceKind.family : PlaceKind.community;

  /// Maps a server-type name (`friends`, `community`, `podcast`, `family`,
  /// `company`) with the community default every unknown value already gets
  /// in the data layer.
  static PlaceKind fromServerTypeName(Object? value) => switch (value) {
    'friends' => PlaceKind.friends,
    'podcast' => PlaceKind.podcast,
    'family' => PlaceKind.family,
    'company' => PlaceKind.company,
    _ => PlaceKind.community,
  };
}

/// One place that decides what a place kind looks like on Home.
///
/// Every colour is an existing token: community, podcast and family mirror
/// [SpaceIdentity]; friends is the brand cyan [AppColors.accent]; company is
/// the brand blue [AppColors.info]. No hex literal lives in this file, so the
/// palette guard in `app_colors.dart` / `space_identity.dart` remains the
/// single source of truth.
@immutable
class PlaceIdentity {
  const PlaceIdentity._({
    required this.kind,
    required this.primary,
    required this.accent,
    required this.icon,
  });

  final PlaceKind kind;

  /// The identity colour: icon container, border, selected wash.
  final Color primary;

  /// The lighter partner, for an eyebrow or glow.
  final Color accent;

  /// The glyph a place tile shows when it has no avatar.
  final IconData icon;

  static const friends = PlaceIdentity._(
    kind: PlaceKind.friends,
    primary: AppColors.accent,
    accent: AppColors.accent,
    icon: Icons.people_alt_rounded,
  );

  static final community = PlaceIdentity._(
    kind: PlaceKind.community,
    primary: SpaceIdentity.community.primary,
    accent: SpaceIdentity.community.accent,
    icon: SpaceIdentity.community.icon,
  );

  static final podcast = PlaceIdentity._(
    kind: PlaceKind.podcast,
    primary: SpaceIdentity.podcast.primary,
    accent: SpaceIdentity.podcast.accent,
    icon: SpaceIdentity.podcast.icon,
  );

  static final family = PlaceIdentity._(
    kind: PlaceKind.family,
    primary: SpaceIdentity.family.primary,
    accent: SpaceIdentity.family.accent,
    icon: SpaceIdentity.family.icon,
  );

  static const company = PlaceIdentity._(
    kind: PlaceKind.company,
    primary: AppColors.info,
    accent: AppColors.info,
    icon: Icons.business_center_rounded,
  );

  static PlaceIdentity of(PlaceKind kind) => switch (kind) {
    PlaceKind.friends => friends,
    PlaceKind.community => community,
    PlaceKind.podcast => podcast,
    PlaceKind.family => family,
    PlaceKind.company => company,
  };

  /// The [SpaceIdentity] this place mirrors, when one exists. Friends and
  /// company have no space identity: they are server-only kinds.
  SpaceIdentity? get spaceIdentity => switch (kind) {
    PlaceKind.community => SpaceIdentity.community,
    PlaceKind.podcast => SpaceIdentity.podcast,
    PlaceKind.family => SpaceIdentity.family,
    PlaceKind.friends || PlaceKind.company => null,
  };

  /// Resolves the stable identity into theme-aware tints for a place tile,
  /// row or card. The alpha recipe is the one the servers directory tile
  /// already paints (`primary @ .12` fill, `@ .25` border), computed here so
  /// Home never imports a feature for a number.
  PlaceIdentityVisuals resolve(Brightness brightness) {
    final light = brightness == Brightness.light;
    final foreground =
        spaceIdentity?.resolve(brightness).foreground ??
        ColorScheme.fromSeed(seedColor: primary, brightness: brightness).primary;
    return PlaceIdentityVisuals(
      icon: icon,
      iconSurface: primary.withValues(alpha: .12),
      iconBorder: primary.withValues(alpha: .25),
      cardWash: primary.withValues(alpha: light ? .045 : .085),
      selectedWash: primary.withValues(alpha: light ? .08 : .16),
      foreground: foreground,
    );
  }
}

/// Theme-aware presentation roles derived from a stable [PlaceIdentity].
@immutable
class PlaceIdentityVisuals {
  const PlaceIdentityVisuals({
    required this.icon,
    required this.iconSurface,
    required this.iconBorder,
    required this.cardWash,
    required this.selectedWash,
    required this.foreground,
  });

  /// Glyph for a place without an avatar.
  final IconData icon;

  /// Soft identity fill behind the glyph (a 40–48 px square).
  final Color iconSurface;

  /// Meaningful identity boundary for [iconSurface].
  final Color iconBorder;

  /// The faint wash a place card or row rests on.
  final Color cardWash;

  /// The stronger wash of a selected or pressed place control.
  final Color selectedWash;

  /// Identity-coloured copy or icon that stays readable on the app's
  /// semantic surfaces in both brightnesses.
  final Color foreground;
}
