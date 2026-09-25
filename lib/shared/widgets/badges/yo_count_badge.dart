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
/// * The count does not grow with the reader's text size by default
///   ([maxTextScale] 1), the same convention as the dock's unread badge
///   (`TextScaler.noScaling`): at 200 % an 11 px count grew into a 22 px
///   blot that covered the bell it counts. The control carries the number
///   in its own label, and a host may pass a larger [maxTextScale].
///
/// The badge carries no semantics of its own: the control it decorates says
/// the count in its label. Unchanged elsewhere: the dock's red badge, the
/// sidebar badges, `YoMetricPill`, role and identity badges, `YoBadge.live`.
class YoCountBadge extends StatelessWidget {
  const YoCountBadge({
    required this.count,
    this.ring,
    this.maxTextScale = 1,
    super.key,
  });

  final int count;
  final Color? ring;
  final double maxTextScale;

  static const double minSize = 20;
  static const double ringWidth = 2;

  /// The printed value: the count, or "99+" above 99.
  static String label(int count) => count > 99 ? '99+' : '$count';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: maxTextScale);
    final ringColor = ring;
    return ExcludeSemantics(
      child: Container(
        constraints: const BoxConstraints(
          minWidth: minSize,
          minHeight: minSize,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 5),
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
