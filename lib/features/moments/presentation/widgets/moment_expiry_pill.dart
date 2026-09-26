import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/badges/yo_progress_ring.dart';

/// The availability of a Voice Moment as one calm pill (refine-look R12).
///
/// It carries the SAME string the card and the detail page printed before —
/// "Wygasa za 23 godz.", "Dostępny do usunięcia" — in the same place; the
/// pill only changes how it sits: a `glass` fill, a 1 px `hairline`, pill
/// radius, `textSecondary` ink with tabular figures. It is neutral by
/// default and turns amber (`warningForeground`) only in the last hour, so
/// the one warning colour on a card means "about to disappear" again
/// instead of decorating every Moment.
///
/// A deadline with a known window draws the 14 px [YoProgressRing] in front
/// of the words: the share of the availability window that is LEFT,
/// `(expiresAt − now) / (expiresAt − createdAt)`, computed from the
/// document's two real timestamps and nothing else. A permanent Moment has
/// no deadline and a document without `createdAt` has no known window, so
/// neither draws a ring — no ring is ever invented. The ring is excluded
/// from semantics; the words carry the fact.
///
/// The ring reads as a GAUGE, not a control (the B5 review, V3 and
/// A11Y-B5-09; a spec amendment to R12): its track is `waveUnplayed` — the
/// "not yet / no longer" grey of the voice bars, ≈ 2:1 on the Dark pill and
/// ≈ 1.6:1 on Pearl's — so the whole circle is always drawn and the arc
/// sits inside it. R12's `border` track measured 1.09:1 on the Dark glass,
/// which left a bare arc that read as a loading spinner at 18-21 h and a
/// hollow radio button at 23 h. The arc is the words' own `textSecondary`
/// (≈ 3.5:1 on its track Dark, ≈ 4.6:1 Pearl): the pill's one neutral ink,
/// not the interactive violet, since the fact is not something to tap. In
/// the last hour both turn `warningForeground`.
///
/// At an accessibility text size the words wrap onto a second line and the
/// ring stays top-aligned with the first.
class MomentExpiryPill extends StatelessWidget {
  const MomentExpiryPill({
    required this.label,
    this.expiresAt,
    this.createdAt,
    this.now,
    this.labelKey,
    super.key,
  });

  /// The already-localized availability line.
  final String label;

  /// The real deadline, or null for a Moment that stays until deleted.
  final DateTime? expiresAt;

  /// The real publication time; with [expiresAt] it defines the window.
  final DateTime? createdAt;

  /// The clock the caller used for [label]; defaults to now.
  final DateTime? now;

  /// Goes on the label [Text], where the surfaces' tests have always found
  /// the availability line by key.
  final Key? labelKey;

  static const double ringSize = 14;
  static const Duration urgentBelow = Duration(hours: 1);

  /// The ring's always-drawn track.
  static Color trackColor(AppPalette palette) => palette.waveUnplayed;

  /// Whether the deadline is less than [urgentBelow] away.
  static bool isUrgent(DateTime? expiresAt, {DateTime? now}) {
    if (expiresAt == null) return false;
    final remaining = expiresAt.difference(now ?? DateTime.now());
    return !remaining.isNegative && remaining < urgentBelow;
  }

  /// The share of the availability window that is left, 0..1, or null when
  /// the window is not known (no deadline, no `createdAt`, or an empty or
  /// inverted window).
  static double? remainingFraction(
    DateTime? expiresAt,
    DateTime? createdAt, {
    DateTime? now,
  }) {
    if (expiresAt == null || createdAt == null) return null;
    final window = expiresAt.difference(createdAt).inMilliseconds;
    if (window <= 0) return null;
    final left = expiresAt.difference(now ?? DateTime.now()).inMilliseconds;
    return (left / window).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final clock = now ?? DateTime.now();
    final urgent = isUrgent(expiresAt, now: clock);
    final fraction = remainingFraction(expiresAt, createdAt, now: clock);
    final ink = urgent ? palette.warningForeground : palette.textSecondary;
    final style = AppTypography.labelMedium.copyWith(
      color: ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // The ring's box follows the first line's height, so at 200 % text it
    // stays level with the first line of the wrapped words.
    final lineHeight = MediaQuery.textScalerOf(context).scale(12) * 1.35;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: highContrast ? palette.surface : palette.glass,
        borderRadius: AppRadius.pill,
        border: Border.all(
          color: highContrast ? palette.borderStrong : palette.hairline,
        ),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          fraction == null ? 11 : 8,
          5,
          11,
          5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fraction != null) ...[
              SizedBox(
                height: lineHeight,
                child: Center(
                  child: YoProgressRing(
                    value: fraction,
                    size: ringSize,
                    trackColor: trackColor(palette),
                    arcColor: ink,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                key: labelKey,
                softWrap: true,
                // Once the words wrap, the pill hugs the longest line
                // instead of stretching to the whole column.
                textWidthBasis: TextWidthBasis.longestLine,
                style: style.copyWith(height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
