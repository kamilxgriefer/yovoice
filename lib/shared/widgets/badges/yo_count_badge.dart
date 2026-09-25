import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';

/// The unread count of YO Voice (refine-look R11): a small gradient pill with
/// a white tabular count.
///
/// * Fill [AppGradients.primaryAction]; at least 20 × 20, 5 px side padding,
///   pill radius; no shadow.
/// * Label white 11 / w700 with tabular figures, capped at "99+".
/// * [ring] — a 2 px ring in the HOST's colour (`palette.background` on the
///   canvas, white @ .28 over media) so the badge reads as cut out of the
///   control it sits on. It is drawn inside the 20 px floor, exactly like
///   the badges it replaces.
/// * The count grows with the reader's text size, as every badge it
///   replaced did (they had no clamp), up to [maxTextScale] — 1.5 × by
///   default, a 16.5 px count — and the floor and padding grow with it, so
///   the pill keeps its proportions. Past that a count would blot out the
///   control it counts. A host that pins the badge to a control's corner
///   reads [growthFor] and lets it grow up and outward, never over the
///   glyph. (The dock's own red badge is not this widget and stays
///   unscaled.)
///
/// The badge carries no semantics of its own: the control it decorates says
/// the count in its label. Unchanged elsewhere: the dock's red badge, the
/// sidebar badges, `YoMetricPill`, role and identity badges, `YoBadge.live`.
class YoCountBadge extends StatelessWidget {
  const YoCountBadge({
    required this.count,
    this.ring,
    this.maxTextScale = defaultMaxTextScale,
    super.key,
  });

  final int count;
  final Color? ring;
  final double maxTextScale;

  static const double minSize = 20;
  static const double ringWidth = 2;
  static const double paddingH = 5;

  /// The largest text scale the count follows by default.
  static const double defaultMaxTextScale = 1.5;

  static double get _fontSize => AppTypography.count.fontSize!;

  /// The printed value: the count, or "99+" above 99.
  static String label(int count) => count > 99 ? '99+' : '$count';

  /// How much the badge is scaled at [context]'s text size: 1 up to 100 %
  /// (a smaller system font never shrinks the 20 px floor), [maxTextScale]
  /// at most.
  static double scaleFor(
    BuildContext context, {
    double maxTextScale = defaultMaxTextScale,
  }) {
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: maxTextScale);
    return math.max(1.0, scaler.scale(_fontSize) / _fontSize);
  }

  /// How many px taller the badge's floor is than at 100 % — the distance a
  /// host shifts a corner-pinned badge up (and out) so it grows away from
  /// the glyph it counts instead of over it.
  static double growthFor(
    BuildContext context, {
    double maxTextScale = defaultMaxTextScale,
  }) => minSize * (scaleFor(context, maxTextScale: maxTextScale) - 1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: maxTextScale);
    final scale = scaleFor(context, maxTextScale: maxTextScale);
    final ringColor = ring;
    return ExcludeSemantics(
      child: Container(
        constraints: BoxConstraints(
          minWidth: minSize * scale,
          minHeight: minSize * scale,
        ),
        padding: EdgeInsets.symmetric(horizontal: paddingH * scale),
        decoration: BoxDecoration(
          gradient: AppGradients.primaryAction(scheme),
          borderRadius: AppRadius.pill,
          border: ringColor == null
              ? null
              : Border.all(color: ringColor, width: ringWidth),
        ),
        // Hug the count: a bare `alignment` on the Container would make the
        // badge fill any loosely constrained parent (a Center, a Row slot).
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            label(count),
            maxLines: 1,
            textAlign: TextAlign.center,
            textScaler: scaler,
            style: AppTypography.count.copyWith(
              color: AppColors.white,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
