import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/shared/identity/public_identity.dart';

import '../data/models/achievement_definition.dart';
import 'achievement_localized_copy.dart';

/// The ONE rarity palette for every achievement surface — the title badge,
/// the Awards cards and rollups, the detail sheet, and the avatar ring /
/// name colour a selected title produces.
///
/// It replaces two drifting copies (the badge's `_BadgePalette` and the
/// Awards screen's `_RarityPalette`). Contract, enforced by
/// `test/title_badge_contrast_test.dart`:
///
///  * [badgeForeground] reads at >= 4.5:1 against EVERY point of the
///    [badgeGradient], sampled across the whole gradient, not only at its
///    stops — the compact 9.5px title on the profile rail depends on it;
///  * [accent] is the identity colour of the rarity (card title, progress,
///    rank/name colour). It is authored for the dark identity; surfaces
///    that host it on lighter grounds lightness-adjust it through
///    `contrastAdjusted` rather than picking a second palette;
///  * [frame] holds the avatar-ring gradient stops, bright enough to read
///    as a 2px ring on the dark canvas.
class AchievementRarityPalette {
  const AchievementRarityPalette({
    required this.accent,
    required this.badgeGradient,
    required this.badgeBorder,
    required this.badgeForeground,
    required this.glow,
    required this.cardBorder,
    required this.cardSurfaceStart,
    required this.cardSurfaceEnd,
    required this.frame,
  });

  final Color accent;
  final List<Color> badgeGradient;
  final Color badgeBorder;
  final Color badgeForeground;
  final Color glow;
  final Color cardBorder;
  final Color cardSurfaceStart;
  final Color cardSurfaceEnd;
  final List<Color> frame;

  static AchievementRarityPalette forRarity(AchievementRarity rarity) {
    return switch (rarity) {
      AchievementRarity.common => const AchievementRarityPalette(
        accent: Color(0xFFB8ADBF),
        badgeGradient: [Color(0xFF342A3B), Color(0xFF493A52)],
        badgeBorder: Color(0xFF65566D),
        badgeForeground: Color(0xFFF1EAF4),
        glow: Color(0xFF65566D),
        cardBorder: Color(0xFF594A62),
        cardSurfaceStart: Color(0xFF211827),
        cardSurfaceEnd: Color(0xFF15101B),
        frame: [Color(0xFFCEC4D6), Color(0xFF8F84A0)],
      ),
      AchievementRarity.uncommon => const AchievementRarityPalette(
        accent: Color(0xFF4DE09E),
        badgeGradient: [Color(0xFF124531), Color(0xFF1B7555)],
        badgeBorder: Color(0xFF49C894),
        badgeForeground: Color(0xFFE7FFF5),
        glow: Color(0xFF49C894),
        cardBorder: Color(0xFF267A5D),
        cardSurfaceStart: Color(0xFF122A22),
        cardSurfaceEnd: Color(0xFF0E1815),
        frame: [Color(0xFF7DF5BF), Color(0xFF35D07F), Color(0xFF1B7555)],
      ),
      AchievementRarity.rare => const AchievementRarityPalette(
        accent: Color(0xFF4B9DFF),
        badgeGradient: [Color(0xFF15355F), Color(0xFF276FD0)],
        badgeBorder: Color(0xFF5FAAFF),
        badgeForeground: Color(0xFFF0F7FF),
        glow: Color(0xFF5FAAFF),
        cardBorder: Color(0xFF2B65A9),
        cardSurfaceStart: Color(0xFF12253C),
        cardSurfaceEnd: Color(0xFF0C1624),
        frame: [Color(0xFF8CC4FF), Color(0xFF4B9DFF), Color(0xFF276FD0)],
      ),
      AchievementRarity.epic => const AchievementRarityPalette(
        accent: Color(0xFFC466FF),
        // Every stop stays above 4.5:1 against the 9.5px compact title.
        badgeGradient: [Color(0xFF4D1767), Color(0xFF8420CA)],
        badgeBorder: Color(0xFFD07CFF),
        badgeForeground: Color(0xFFFFF4FF),
        glow: Color(0xFFC052FF),
        cardBorder: Color(0xFF7B35A6),
        cardSurfaceStart: Color(0xFF2B1538),
        cardSurfaceEnd: Color(0xFF180D21),
        frame: [Color(0xFFE2A6FF), Color(0xFFC466FF), Color(0xFF8420CA)],
      ),
      AchievementRarity.legendary => const AchievementRarityPalette(
        accent: Color(0xFFFFA52B),
        badgeGradient: [Color(0xFF7D3A0D), Color(0xFF95500B)],
        badgeBorder: Color(0xFFFFC566),
        badgeForeground: Color(0xFFFFF8E8),
        glow: Color(0xFFFFA52B),
        cardBorder: Color(0xFFB2651C),
        cardSurfaceStart: Color(0xFF342010),
        cardSurfaceEnd: Color(0xFF1A100A),
        frame: [Color(0xFFFFD98A), Color(0xFFFFA52B), Color(0xFFFF7A1F)],
      ),
      AchievementRarity.mythic => const AchievementRarityPalette(
        accent: Color(0xFFFF6DDA),
        badgeGradient: [
          Color(0xFF7E1D76),
          Color(0xFF5A29C8),
          Color(0xFF8F22B8),
        ],
        badgeBorder: Color(0xFFFF77DF),
        badgeForeground: Color(0xFFFFFFFF),
        glow: Color(0xFFD84CFF),
        cardBorder: Color(0xFFB53AA8),
        cardSurfaceStart: Color(0xFF341437),
        cardSurfaceEnd: Color(0xFF160E22),
        frame: [
          Color(0xFFFF9BE8),
          Color(0xFFD84CFF),
          Color(0xFF7A6BFF),
          Color(0xFFFF6DDA),
        ],
      ),
    };
  }
}

/// The cosmetic an achievement title produces when it is the selected
/// title: the rank label (the title itself, localized when [copy] is
/// given), the rank colour used for the display name, and the avatar-ring
/// gradient. Presentation only — it carries no permission and is derived
/// from the catalog definition, never from a client-supplied colour.
AchievementStyle achievementStyleFor(
  AchievementDefinition definition, {
  AppLocalizations? copy,
}) {
  final palette = AchievementRarityPalette.forRarity(definition.rarity);
  return AchievementStyle(
    rankLabel: copy == null
        ? definition.title
        : localizedAchievementTitle(copy, definition),
    rankColor: palette.accent,
    frameColors: palette.frame,
  );
}
