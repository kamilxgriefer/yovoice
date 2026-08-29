import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';

/// One placement's content. Immutable and tiny on purpose: it is the seam
/// a real campaign would arrive through later, not an advertising
/// platform. There is no backend, no schema, no tracking and no SDK
/// behind it.
@immutable
class SponsoredPlacement {
  const SponsoredPlacement({
    required this.headline,
    required this.body,
    this.ctaLabel,
    this.destination,
    this.isExample = true,
  });

  final String headline;
  final String body;

  /// Null when the placement has nothing to click.
  final String? ctaLabel;

  /// Null in demonstration mode. A real placement supplies an absolute
  /// https URL; anything else is refused by [hasLaunchableDestination]
  /// rather than handed to a launcher.
  final Uri? destination;

  /// Demonstration content, disclosed as such. A real campaign sets this
  /// false — and must then also carry its own disclosure copy.
  final bool isExample;

  /// The single gate every caller must pass before treating the CTA as
  /// actionable. Only absolute https survives: no javascript:, no data:,
  /// no file:, no scheme-relative host.
  bool get hasLaunchableDestination {
    final uri = destination;
    if (uri == null) return false;
    if (!uri.isAbsolute) return false;
    if (uri.scheme.toLowerCase() != 'https') return false;
    return uri.host.isNotEmpty;
  }

  /// What ships today. No brand, no quote, no metrics, no customer —
  /// abstract artwork and copy that says outright what it is.
  static const example = SponsoredPlacement(
    headline: 'Your campaign could sit here',
    body:
        'A place for a partner message beside the community, in the same '
        'visual language as the rest of YO Voice.',
    ctaLabel: 'Learn more',
  );
}

/// The right column's sponsored slot.
///
/// Deliberately quieter than the organic cards above it: no gradient
/// fill, no glow, a thinner border. Sponsored material should be legible
/// as sponsored at a glance and should never out-shout the product's own
/// recommendations.
class SponsoredCard extends StatelessWidget {
  const SponsoredCard({
    this.placement = SponsoredPlacement.example,
    this.onOpen,
    super.key,
  });

  final SponsoredPlacement placement;

  /// Invoked ONLY when [SponsoredPlacement.hasLaunchableDestination] is
  /// true. In demonstration mode the CTA is rendered as a visibly
  /// disabled preview instead — an apparently clickable dead button
  /// would be worse than no button.
  final ValueChanged<Uri>? onOpen;

  @override
  Widget build(BuildContext context) {
    final actionable = placement.hasLaunchableDestination && onOpen != null;
    final disclosure = placement.isExample ? 'Sponsored example' : 'Sponsored';
    final colors = Theme.of(context).colorScheme;
    final palette = context.appPalette;

    return Container(
      key: const ValueKey('desktop-sponsored-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: palette.surfaceMuted,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: palette.surfaceRaised,
                  border: Border.all(color: palette.borderStrong),
                ),
                child: Text(
                  disclosure.toUpperCase(),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          // Abstract artwork drawn from theme tokens — no logo, no stock
          // photograph, nothing that could read as a real company.
          Container(
            height: 74,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withValues(alpha: .22),
                  AppColors.secondary.withValues(alpha: .14),
                ],
              ),
              border: Border.all(color: palette.border),
            ),
            child: Center(
              child: Icon(
                Icons.campaign_rounded,
                size: 26,
                color: palette.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 11),
          Text(
            placement.headline,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            placement.body,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
          if (placement.ctaLabel != null) ...[
            const SizedBox(height: 12),
            if (actionable)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => onOpen!(placement.destination!),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.primary,
                    side: BorderSide(color: palette.borderStrong),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  child: Text(
                    placement.ctaLabel!,
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else
              // Not a button: no onPressed, no focus stop, and it says
              // why. Nothing here can be activated by mouse or keyboard.
              Semantics(
                label:
                    '${placement.ctaLabel!}, preview only — this example '
                    'placement has no destination',
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    '${placement.ctaLabel!} · preview',
                    style: TextStyle(
                      color: palette.textTertiary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
