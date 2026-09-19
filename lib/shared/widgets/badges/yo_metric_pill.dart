import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart';

/// How a [YoMetricPill] sits on its surface.
enum YoMetricPillTone {
  /// Filled `colorScheme.primary` with `onPrimary` ink: a count that asks
  /// for attention (the inbox's pending requests and unread messages).
  accent,

  /// `palette.surface` behind a 1 px `palette.border` with `textSecondary`
  /// ink: a quiet tally beside a heading (the Awards category count).
  outlined,

  /// `palette.surfaceMuted` with `textPrimary` ink and a `textSecondary`
  /// icon, no border: a fact chip on a card (people, members).
  tonal,

  /// The documented media plate ([overlayPlateColor]) with white ink, for a
  /// count drawn over artwork or a thumbnail.
  overlay,
}

/// A small pill carrying one short, real value — a count, a duration — with
/// an optional leading glyph.
///
/// The caller owns everything that makes the number true: the data source,
/// the formatting ("99+", `compactCount`), the decision not to mount the pill
/// at all when there is nothing real to say (a zero, an unknown), and the
/// localized [semanticLabel]. The pill never invents a value and never draws
/// a placeholder. Without a [semanticLabel] the visible [value] is what a
/// screen reader hears; with one, the label replaces it (the full sentence
/// with the exact number, e.g. "842 listening").
class YoMetricPill extends StatelessWidget {
  const YoMetricPill({
    required this.value,
    this.icon,
    this.tone = YoMetricPillTone.tonal,
    this.semanticLabel,
    this.iconColor,
    super.key,
  });

  /// Already-formatted short value, rendered verbatim on one line.
  final String value;

  /// Optional leading glyph, sized to the value's cap height.
  final IconData? icon;

  final YoMetricPillTone tone;

  /// Localized sentence that replaces [value] for assistive technology.
  final String? semanticLabel;

  /// Overrides the glyph's ink only (an identity accent); the value keeps
  /// the tone's AA-paired ink.
  final Color? iconColor;

  static const double iconSize = 13;
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 3,
  );

  /// The fill, border and inks for [tone] in the ambient theme. Exposed so
  /// contrast tests read the same pairs the widget paints.
  static ({Color? fill, Color? border, Color ink, Color iconInk}) colorsFor(
    BuildContext context,
    YoMetricPillTone tone,
  ) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    return switch (tone) {
      YoMetricPillTone.accent => (
        fill: scheme.primary,
        border: null,
        ink: scheme.onPrimary,
        iconInk: scheme.onPrimary,
      ),
      YoMetricPillTone.outlined => (
        fill: palette.surface,
        border: palette.border,
        ink: palette.textSecondary,
        iconInk: palette.textSecondary,
      ),
      YoMetricPillTone.tonal => (
        fill: palette.surfaceMuted,
        border: null,
        ink: palette.textPrimary,
        iconInk: palette.textSecondary,
      ),
      YoMetricPillTone.overlay => (
        fill: overlayPlateColor,
        border: null,
        ink: AppColors.white,
        iconInk: AppColors.white,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = colorsFor(context, tone);
    Widget pill = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: AppRadius.pill,
        border: colors.border == null
            ? null
            : Border.all(color: colors.border!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: iconSize, color: iconColor ?? colors.iconInk),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelMedium.copyWith(
                color: colors.ink,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    final label = semanticLabel?.trim();
    if (label != null && label.isNotEmpty) {
      pill = Semantics(label: label, excludeSemantics: true, child: pill);
    }
    return pill;
  }
}
