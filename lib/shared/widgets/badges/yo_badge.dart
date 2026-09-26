import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';

enum YoBadgeVariant { primary, success, warning, error, info, live }

/// The status badge of the design system.
///
/// [YoBadgeVariant.live] is the one NA ŻYWO marker of the product (Slim
/// redesign, phase 0): a filled [AppColors.live] pill, [AppColors.onLive] copy
/// at 10 px / w800 with a small dot that pulses briefly when the marker
/// appears and goes still under Reduce Motion, accessible navigation or a
/// paused [TickerMode]. The label is rendered verbatim — callers pass the
/// locale copy in the case the surface needs (`copy.serverLivePill`,
/// `copy.text('LIVE', 'NA ŻYWO')`), and the widget never transforms it. [icon] is ignored for the live variant: the dot
/// is its icon. Surfaces that count live markers pass their marker key through
/// [key]; the widget adds no key and no extra semantics of its own.
class YoBadge extends StatelessWidget {
  const YoBadge({
    super.key,
    required this.label,
    this.variant = YoBadgeVariant.primary,
    this.icon,
  });

  final String label;
  final YoBadgeVariant variant;
  final IconData? icon;

  /// The alpha of a tonal badge's edge (its ink at .32).
  static const double tonalEdgeAlpha = .32;

  @override
  Widget build(BuildContext context) {
    if (variant == YoBadgeVariant.live) return _buildLive();

    final colors = Theme.of(context).colorScheme;
    final palette = context.appPalette;
    final (:surface, :foreground) = _colors(palette, colors);
    // Refine-look R11: the tonal pill's edge is its ink at .32, so the fill
    // and the label carry the status instead of an opaque outline. High
    // contrast restores the full-strength edge.
    final edge = MediaQuery.highContrastOf(context)
        ? foreground
        : foreground.withValues(alpha: tonalEdgeAlpha);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: AppRadius.pill,
        border: Border.all(color: edge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }

  /// The NA ŻYWO pill. [AppColors.live] / [AppColors.onLive] are
  /// brightness-independent, so Dark and Pearl draw the same marker.
  ///
  /// Metrics are the server contract's: `labelSmall` (10 px, line height 1.2)
  /// plus 3 px of vertical padding keeps the pill taller than 26 px at 200 %
  /// text on a 320 px phone, and the single unwrapped line elides rather than
  /// breaking the word — a marker that says nothing is worse than none.
  Widget _buildLive() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: const BoxDecoration(
      color: AppColors.live,
      borderRadius: AppRadius.pill,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const ExcludeSemantics(child: _LivePulseDot()),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.onLive,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
            ),
          ),
        ),
      ],
    ),
  );

  ({Color surface, Color foreground}) _colors(
    AppPalette palette,
    ColorScheme colors,
  ) {
    switch (variant) {
      case YoBadgeVariant.primary:
        return (
          surface: colors.primaryContainer,
          foreground: colors.onPrimaryContainer,
        );
      case YoBadgeVariant.success:
        return (
          surface: palette.successSurface,
          foreground: palette.successForeground,
        );
      case YoBadgeVariant.warning:
        return (
          surface: palette.warningSurface,
          foreground: palette.warningForeground,
        );
      case YoBadgeVariant.error:
        return (
          surface: palette.dangerSurface,
          foreground: palette.dangerForeground,
        );
      case YoBadgeVariant.info:
        return (
          surface: palette.infoSurface,
          foreground: palette.infoForeground,
        );
      case YoBadgeVariant.live:
        return (surface: AppColors.live, foreground: AppColors.onLive);
    }
  }
}

/// The 6 px dot of the live badge: a decorative pulse (opacity 1 → .55 → 1,
/// three mirrored cycles over 3.6 s) that plays when the marker appears and
/// then rests at full opacity. It is bounded on purpose: a persistent server
/// screen must not tick forever for a decoration, and every surface that
/// mounts the badge must still settle. The pulse runs only when motion is
/// allowed — under Reduce Motion, accessible navigation or a disabled
/// [TickerMode] the controller is stopped and parked at 1, so no frame is
/// scheduled (the same guard `HeroLiveRoom` uses); when motion is allowed
/// again the pulse plays once more.
class _LivePulseDot extends StatefulWidget {
  const _LivePulseDot();

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  static const double _size = 6;
  static const int _cycles = 3;
  static const Duration _cycle = Duration(milliseconds: 1200);

  late final AnimationController _controller;
  late final Animation<double> _opacity;
  bool _pulsed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _cycle * _cycles,
      value: 1,
    );
    _opacity = TweenSequence<double>(<TweenSequenceItem<double>>[
      for (var i = 0; i < _cycles; i++) ...<TweenSequenceItem<double>>[
        TweenSequenceItem(
          tween: Tween<double>(
            begin: 1,
            end: .55,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: Tween<double>(
            begin: .55,
            end: 1,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 1,
        ),
      ],
    ]).animate(_controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motionAllowed =
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (motionAllowed) {
      if (!_pulsed) {
        _pulsed = true;
        _controller.forward(from: 0);
      }
    } else {
      _pulsed = false;
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _opacity,
    child: Container(
      width: _size,
      height: _size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.onLive,
      ),
    ),
  );
}
