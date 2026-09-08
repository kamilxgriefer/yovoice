import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';

/// The Reel stage while the first page is still loading.
///
/// It holds the exact geometry the real card will take — same 9:16 frame,
/// same radius, border and shadow — so the feed does not jump when the data
/// arrives. Deliberately static: one 260 ms fade, no shimmer, because a feed
/// that never settles is the thing this redesign is removing.
///
/// It carries no semantics of its own; the loading state's live region
/// belongs to the indicator above it.
class ReelCardSkeleton extends StatelessWidget {
  const ReelCardSkeleton({this.borderRadius = 24, super.key});

  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final bar = palette.border.withValues(alpha: .6);

    Widget line(double width, double height) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: bar,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );

    return IgnorePointer(
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: AppMotion.resolve(
            context,
            const Duration(milliseconds: 260),
          ),
          curve: AppMotion.standardCurve,
          builder: (context, value, child) =>
              Opacity(opacity: value, child: child),
          child: Center(
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      palette.surfaceSunken,
                      palette.surfaceMuted,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(color: palette.border),
                  boxShadow: reelCardShadow(context),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 12, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            line(120, 14),
                            line(220, 12),
                            line(160, 12),
                            line(140, 10),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          for (var index = 0; index < 3; index++)
                            Padding(
                              padding: EdgeInsets.only(
                                top: index == 0 ? 0 : 14,
                              ),
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: bar,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
