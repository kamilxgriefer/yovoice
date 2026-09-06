import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/shared/identity/identity_contrast.dart';
import 'package:yovoice/shared/identity/public_identity.dart';

/// A display name that takes its colour from the account's achievement
/// style — the cosmetic the owner asked for: a selected title changes the
/// nickname colour wherever the OWN identity is shown at full size.
///
/// Rules this widget enforces so a cosmetic can never damage legibility or
/// impersonate authority:
///
///  * without a style (or without a rank colour) it is the plain [style]
///    text — absence is always valid;
///  * the rank colour is lightness-adjusted against [surface] to at least
///    4.5:1 (see [contrastAdjusted]), so the same title reads on the dark
///    name plate, on Pearl's white cards and on the page background;
///  * it is only text — no pill, no icon — and it sits beside, never
///    instead of, the official role and VIP badges.
class IdentityName extends StatelessWidget {
  const IdentityName(
    this.name, {
    required this.style,
    this.achievementStyle,
    this.surface,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
    this.isHeader = false,
    super.key,
  });

  final String name;

  /// The base text style; only its colour changes when a rank colour applies.
  final TextStyle style;
  final AchievementStyle? achievementStyle;

  /// The colour behind the text. Defaults to the palette's raised surface,
  /// which is where every own-identity name plate draws.
  final Color? surface;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  /// Marks the text as a semantic header (the profile hero heading).
  final bool isHeader;

  /// The colour this widget will render [name] in.
  static Color resolveColor({
    required Color fallback,
    required Color surface,
    AchievementStyle? achievementStyle,
  }) {
    final rank = achievementStyle?.rankColor;
    if (rank == null) return fallback;
    return contrastAdjusted(rank, surface: surface);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final color = resolveColor(
      fallback: style.color ?? palette.textPrimary,
      surface: surface ?? palette.surfaceRaised,
      achievementStyle: achievementStyle,
    );
    final text = Text(
      name,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: style.copyWith(color: color),
    );
    if (!isHeader) return text;
    return Semantics(header: true, child: text);
  }
}
