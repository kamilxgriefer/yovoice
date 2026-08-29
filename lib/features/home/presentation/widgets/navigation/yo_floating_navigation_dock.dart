import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';

@immutable
class YoNavigationDestinationConfig {
  const YoNavigationDestinationConfig({
    required this.label,
    required this.semanticLabel,
    required this.icon,
    required this.selectedIcon,
    required this.visualSlot,
    required this.isSelected,
    required this.onPressed,
    this.badgeCount = 0,
  });

  final String label;
  final String semanticLabel;
  final IconData icon;
  final IconData selectedIcon;
  final int visualSlot;
  final bool isSelected;
  final VoidCallback onPressed;
  final int badgeCount;
}

/// The production mobile navigation surface shared by [MainShell] and every
/// shell-hosted destination.
///
/// Domain tab indexes deliberately stay outside this widget. In particular,
/// Moments is tab 5 even though it occupies visual slot 3, while the centre
/// YO control and More remain actions rather than invented content pages.
class YoFloatingNavigationDock extends StatefulWidget {
  const YoFloatingNavigationDock({
    required this.selectedTabIndex,
    required this.momentsTabIndex,
    required this.unreadConversationCount,
    required this.onDestinationSelected,
    required this.onVoicePressed,
    required this.onMorePressed,
    this.moreSelected = false,
    super.key,
  });

  static const double horizontalMargin = 14;
  static const double topClearance = 12;
  static const double minimumBottomClearance = 10;
  static const double visualHeight = 86;
  static const double accessibleVisualHeight = 112;
  static const double cornerRadius = 30;
  static const double notchCenterFromTop = 24;
  static const double notchGap = 5;
  static const double expandedLabelScaleThreshold = 1.6;

  final int selectedTabIndex;
  final int momentsTabIndex;
  final int unreadConversationCount;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onVoicePressed;
  final VoidCallback onMorePressed;
  final bool moreSelected;

  /// Exact vertical space reserved by the Scaffold bottom-navigation child.
  /// Keeping this calculation public prevents content-inset tests or future
  /// overlays from growing a second device-specific magic number.
  static double visualHeightFor({required double textScale}) =>
      textScale >= expandedLabelScaleThreshold
      ? accessibleVisualHeight
      : visualHeight;

  static double reservedHeightFor({
    required double safeBottom,
    double textScale = 1,
  }) {
    return topClearance +
        visualHeightFor(textScale: textScale) +
        (safeBottom > minimumBottomClearance
            ? safeBottom
            : minimumBottomClearance);
  }

  static int? visualSlotForTab(int tabIndex, {required int momentsTabIndex}) {
    return switch (tabIndex) {
      0 => 0,
      1 => 1,
      _ when tabIndex == momentsTabIndex => 3,
      _ => null,
    };
  }

  @override
  State<YoFloatingNavigationDock> createState() =>
      _YoFloatingNavigationDockState();
}

class _YoFloatingNavigationDockState extends State<YoFloatingNavigationDock> {
  static const _premiumCurve = Cubic(0.22, 1, 0.36, 1);
  static const _breathingTravel = Duration(milliseconds: 2800);
  static const _breathingCadence = Duration(milliseconds: 3100);

  Timer? _breathingTimer;
  bool _breathingHigh = false;
  bool? _reduceMotion;
  int _breathingGeneration = 0;

  int? get _activeVisualSlot => widget.moreSelected
      ? 4
      : YoFloatingNavigationDock.visualSlotForTab(
          widget.selectedTabIndex,
          momentsTabIndex: widget.momentsTabIndex,
        );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    _configureBreathing();
  }

  void _configureBreathing() {
    _breathingTimer?.cancel();
    _breathingTimer = null;
    _breathingGeneration += 1;
    final generation = _breathingGeneration;

    if (_reduceMotion ?? true) {
      _breathingHigh = false;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _breathingGeneration) return;
      setState(() => _breathingHigh = true);
      _breathingTimer = Timer.periodic(_breathingCadence, (_) {
        if (!mounted) return;
        setState(() => _breathingHigh = !_breathingHigh);
      });
    });
  }

  @override
  void dispose() {
    _breathingGeneration += 1;
    _breathingTimer?.cancel();
    super.dispose();
  }

  void _select(YoNavigationDestinationConfig destination) {
    if (!destination.isSelected) {
      unawaited(HapticFeedback.selectionClick());
    }
    destination.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final reduceMotion = _reduceMotion ?? false;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final dockVisualHeight = YoFloatingNavigationDock.visualHeightFor(
      textScale: textScale,
    );
    final expandedLabels =
        textScale >= YoFloatingNavigationDock.expandedLabelScaleThreshold;
    final selectedTabIndex = widget.selectedTabIndex;
    final destinations = <YoNavigationDestinationConfig>[
      YoNavigationDestinationConfig(
        label: copy.home,
        semanticLabel: copy.home,
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        visualSlot: 0,
        isSelected: !widget.moreSelected && selectedTabIndex == 0,
        onPressed: () => widget.onDestinationSelected(0),
      ),
      YoNavigationDestinationConfig(
        label: copy.chats,
        semanticLabel: copy.chats,
        icon: Icons.chat_bubble_outline_rounded,
        selectedIcon: Icons.chat_bubble_rounded,
        visualSlot: 1,
        isSelected: !widget.moreSelected && selectedTabIndex == 1,
        badgeCount: widget.unreadConversationCount,
        onPressed: () => widget.onDestinationSelected(1),
      ),
      YoNavigationDestinationConfig(
        label: copy.moments,
        semanticLabel: copy.moments,
        icon: Icons.graphic_eq_outlined,
        selectedIcon: Icons.graphic_eq_rounded,
        visualSlot: 3,
        isSelected:
            !widget.moreSelected && selectedTabIndex == widget.momentsTabIndex,
        onPressed: () => widget.onDestinationSelected(widget.momentsTabIndex),
      ),
      YoNavigationDestinationConfig(
        label: copy.more,
        semanticLabel: copy.more,
        icon: Icons.grid_view_outlined,
        selectedIcon: Icons.grid_view_rounded,
        visualSlot: 4,
        isSelected: widget.moreSelected,
        onPressed: widget.onMorePressed,
      ),
    ];
    final bySlot = <int, YoNavigationDestinationConfig>{
      for (final destination in destinations)
        destination.visualSlot: destination,
    };

    return Semantics(
      key: const ValueKey('yo-floating-navigation-semantics'),
      container: true,
      explicitChildNodes: true,
      child: SafeArea(
        key: const ValueKey('yo-floating-navigation-safe-area'),
        top: false,
        minimum: const EdgeInsets.only(
          bottom: YoFloatingNavigationDock.minimumBottomClearance,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: YoFloatingNavigationDock.horizontalMargin,
          ),
          child: Align(
            heightFactor: 1,
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: RepaintBoundary(
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: SizedBox(
                    height:
                        YoFloatingNavigationDock.topClearance +
                        dockVisualHeight,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const horizontalContentPadding = 6.0;
                        final contentWidth =
                            constraints.maxWidth - horizontalContentPadding * 2;
                        final slotWidth = contentWidth / 5;
                        final capsuleWidth = (slotWidth + 8).clamp(64.0, 72.0);
                        final expandedCellWidth = contentWidth / 2;
                        final expandedCellHeight = (dockVisualHeight - 16) / 2;
                        final activeSlot = _activeVisualSlot;
                        final activeOnRight =
                            activeSlot == 3 || activeSlot == 4;
                        final activeOnBottom =
                            activeSlot == 1 || activeSlot == 4;
                        final centerDiameter = constraints.maxWidth < 332
                            ? 64.0
                            : 68.0;
                        final centerX = constraints.maxWidth / 2;
                        final centerLeft = centerX - centerDiameter / 2;
                        final centerTop =
                            YoFloatingNavigationDock.topClearance +
                            YoFloatingNavigationDock.notchCenterFromTop -
                            centerDiameter / 2;
                        final dockShape = _YoDockNotchedShape(
                          cornerRadius: YoFloatingNavigationDock.cornerRadius,
                          notchCenterX: centerX,
                          notchCenterY:
                              YoFloatingNavigationDock.notchCenterFromTop,
                          notchRadius:
                              centerDiameter / 2 +
                              YoFloatingNavigationDock.notchGap,
                          side: BorderSide(color: palette.border),
                        );

                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: YoFloatingNavigationDock.topClearance,
                              height: dockVisualHeight,
                              child: Container(
                                key: const ValueKey(
                                  'yo-floating-navigation-dock',
                                ),
                                decoration: ShapeDecoration(
                                  color: palette.navigationSurface.withValues(
                                    alpha: .97,
                                  ),
                                  shape: dockShape,
                                  shadows: [
                                    BoxShadow(
                                      color: palette.shadow.withValues(
                                        alpha: .30,
                                      ),
                                      blurRadius: 24,
                                      offset: const Offset(0, 10),
                                    ),
                                    BoxShadow(
                                      color: AppColors.navigationPrimary
                                          .withValues(alpha: .09),
                                      blurRadius: 32,
                                    ),
                                  ],
                                ),
                                child: ClipPath(
                                  key: const ValueKey('yo-dock-notch-clip'),
                                  clipper: ShapeBorderClipper(shape: dockShape),
                                  child: Stack(
                                    children: [
                                      if (activeSlot != null)
                                        AnimatedPositioned(
                                          key: const ValueKey(
                                            'yo-active-capsule-position',
                                          ),
                                          duration: reduceMotion
                                              ? Duration.zero
                                              : const Duration(
                                                  milliseconds: 290,
                                                ),
                                          curve: _premiumCurve,
                                          left: expandedLabels
                                              ? horizontalContentPadding +
                                                    (activeOnRight
                                                        ? expandedCellWidth
                                                        : 0) +
                                                    4
                                              : horizontalContentPadding +
                                                    slotWidth * activeSlot +
                                                    (slotWidth - capsuleWidth) /
                                                        2,
                                          top: expandedLabels
                                              ? 10 +
                                                    (activeOnBottom
                                                        ? expandedCellHeight
                                                        : 0)
                                              : 8,
                                          width: expandedLabels
                                              ? expandedCellWidth - 8
                                              : capsuleWidth,
                                          height: expandedLabels
                                              ? expandedCellHeight - 4
                                              : dockVisualHeight - 16,
                                          child: _ActiveCapsule(
                                            breathingHigh: _breathingHigh,
                                            reduceMotion: reduceMotion,
                                          ),
                                        ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: horizontalContentPadding,
                                          vertical: 8,
                                        ),
                                        child: expandedLabels
                                            ? Stack(
                                                children: [
                                                  for (final slot in [
                                                    0,
                                                    1,
                                                    3,
                                                    4,
                                                  ])
                                                    Positioned(
                                                      left:
                                                          slot == 3 || slot == 4
                                                          ? expandedCellWidth
                                                          : 0,
                                                      top:
                                                          slot == 1 || slot == 4
                                                          ? expandedCellHeight
                                                          : 0,
                                                      width: expandedCellWidth,
                                                      height:
                                                          expandedCellHeight,
                                                      child: _YoDockDestination(
                                                        config: bySlot[slot]!,
                                                        reduceMotion:
                                                            reduceMotion,
                                                        onPressed: () =>
                                                            _select(
                                                              bySlot[slot]!,
                                                            ),
                                                      ),
                                                    ),
                                                ],
                                              )
                                            : Row(
                                                children: [
                                                  for (
                                                    var slot = 0;
                                                    slot < 5;
                                                    slot++
                                                  )
                                                    Expanded(
                                                      child: slot == 2
                                                          ? const SizedBox.expand()
                                                          : _YoDockDestination(
                                                              config:
                                                                  bySlot[slot]!,
                                                              reduceMotion:
                                                                  reduceMotion,
                                                              onPressed: () =>
                                                                  _select(
                                                                    bySlot[slot]!,
                                                                  ),
                                                            ),
                                                    ),
                                                ],
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left:
                                  centerLeft -
                                  YoFloatingNavigationDock.notchGap,
                              top:
                                  centerTop - YoFloatingNavigationDock.notchGap,
                              width:
                                  centerDiameter +
                                  YoFloatingNavigationDock.notchGap * 2,
                              height:
                                  centerDiameter +
                                  YoFloatingNavigationDock.notchGap * 2,
                              child: IgnorePointer(
                                key: const ValueKey('yo-center-cradle'),
                                child: ExcludeSemantics(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        center: const Alignment(-.28, -.34),
                                        radius: .92,
                                        colors: [
                                          palette.surfaceRaised,
                                          palette.surfaceSunken,
                                        ],
                                      ),
                                      border: Border.all(
                                        color: palette.borderStrong,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: palette.shadow.withValues(
                                            alpha: .26,
                                          ),
                                          blurRadius: 12,
                                          offset: const Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: centerLeft,
                              top: centerTop,
                              width: centerDiameter,
                              height: centerDiameter,
                              child: FocusTraversalOrder(
                                order: const NumericFocusOrder(2),
                                child: _YoCenterActionButton(
                                  diameter: centerDiameter,
                                  onPressed: widget.onVoicePressed,
                                  reduceMotion: reduceMotion,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
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

/// A rounded dock outline with a real, tangent circular cradle for the YO
/// action. The notch is part of the surface geometry (rather than a circle
/// painted over a rectangular bar), so its rim, shadows and clipping all agree.
class _YoDockNotchedShape extends ShapeBorder {
  const _YoDockNotchedShape({
    required this.cornerRadius,
    required this.notchCenterX,
    required this.notchCenterY,
    required this.notchRadius,
    required this.side,
  });

  final double cornerRadius;
  final double notchCenterX;
  final double notchCenterY;
  final double notchRadius;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  ShapeBorder scale(double t) => _YoDockNotchedShape(
    cornerRadius: cornerRadius * t,
    notchCenterX: notchCenterX * t,
    notchCenterY: notchCenterY * t,
    notchRadius: notchRadius * t,
    side: side.scale(t),
  );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _notchedRoundedRectPath(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    final inset = side.width;
    if (inset == 0) return getOuterPath(rect);
    return _notchedRoundedRectPath(rect.deflate(inset));
  }

  Path _notchedRoundedRectPath(Rect rect) {
    final radius = cornerRadius.clamp(
      0.0,
      math.min(rect.width, rect.height) / 2,
    );
    final guestCenter = Offset(
      rect.left + notchCenterX,
      rect.top + notchCenterY,
    );
    final guestRadius = notchRadius;

    // This is the same tangent construction used by Material's circular FAB
    // notch, continued into YO's rounded floating-dock outline.
    const shoulder = 15.0;
    const edgeGap = 1.0;
    final a = -guestRadius - edgeGap;
    final b = rect.top - guestCenter.dy;
    final denominator = a * a + b * b;
    final discriminant = math.max(
      0.0,
      b *
          b *
          guestRadius *
          guestRadius *
          (denominator - guestRadius * guestRadius),
    );
    final root = math.sqrt(discriminant);
    final p2xA = (a * b * b - root) / denominator;
    final p2xB = (a * b * b + root) / denominator;
    final p2yA = math.sqrt(
      math.max(0, guestRadius * guestRadius - p2xA * p2xA),
    );
    final p2yB = math.sqrt(
      math.max(0, guestRadius * guestRadius - p2xB * p2xB),
    );
    final comparison = b < 0 ? -1.0 : 1.0;
    final tangent = comparison * p2yA > comparison * p2yB
        ? Offset(p2xA, p2yA)
        : Offset(p2xB, p2yB);
    final points = <Offset>[
      Offset(a - shoulder, b),
      Offset(a, b),
      tangent,
      Offset(-tangent.dx, tangent.dy),
      Offset(-a, b),
      Offset(-a + shoulder, b),
    ].map((point) => point + guestCenter).toList(growable: false);

    return Path()
      ..moveTo(rect.left + radius, rect.top)
      ..lineTo(points[0].dx, points[0].dy)
      ..quadraticBezierTo(
        points[1].dx,
        points[1].dy,
        points[2].dx,
        points[2].dy,
      )
      ..arcToPoint(
        points[3],
        radius: Radius.circular(guestRadius),
        clockwise: false,
      )
      ..quadraticBezierTo(
        points[4].dx,
        points[4].dy,
        points[5].dx,
        points[5].dy,
      )
      ..lineTo(rect.right - radius, rect.top)
      ..quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + radius)
      ..lineTo(rect.right, rect.bottom - radius)
      ..quadraticBezierTo(
        rect.right,
        rect.bottom,
        rect.right - radius,
        rect.bottom,
      )
      ..lineTo(rect.left + radius, rect.bottom)
      ..quadraticBezierTo(
        rect.left,
        rect.bottom,
        rect.left,
        rect.bottom - radius,
      )
      ..lineTo(rect.left, rect.top + radius)
      ..quadraticBezierTo(rect.left, rect.top, rect.left + radius, rect.top)
      ..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(
      getOuterPath(rect, textDirection: textDirection),
      side.toPaint()..style = PaintingStyle.stroke,
    );
  }
}

class _ActiveCapsule extends StatelessWidget {
  const _ActiveCapsule({
    required this.breathingHigh,
    required this.reduceMotion,
  });

  final bool breathingHigh;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      key: ValueKey(
        reduceMotion
            ? 'yo-active-capsule-reduced-motion'
            : 'yo-active-breathing-animation',
      ),
      duration: reduceMotion
          ? Duration.zero
          : _YoFloatingNavigationDockState._breathingTravel,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, palette.surfaceRaised],
        ),
        border: Border.all(color: colors.primary.withValues(alpha: .42)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navigationPrimary.withValues(alpha: .12),
            blurRadius: 12,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: AppColors.secondary.withValues(
              alpha: reduceMotion || !breathingHigh ? .10 : .16,
            ),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _YoDockDestination extends StatefulWidget {
  const _YoDockDestination({
    required this.config,
    required this.reduceMotion,
    required this.onPressed,
  });

  final YoNavigationDestinationConfig config;
  final bool reduceMotion;
  final VoidCallback onPressed;

  @override
  State<_YoDockDestination> createState() => _YoDockDestinationState();
}

class _YoDockDestinationState extends State<_YoDockDestination> {
  static const _premiumCurve = Cubic(0.22, 1, 0.36, 1);
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'YO dock ${widget.config.visualSlot}',
  );
  bool _pressed = false;

  Duration get _duration =>
      widget.reduceMotion ? Duration.zero : const Duration(milliseconds: 240);

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final selected = config.isSelected;
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final expandedLabels =
        MediaQuery.textScalerOf(context).scale(1) >=
        YoFloatingNavigationDock.expandedLabelScaleThreshold;
    final iconColor = selected
        ? colors.onPrimaryContainer
        : palette.navigationInactive;
    final semanticsLabel = config.badgeCount > 0
        ? '${config.semanticLabel}, ${config.badgeCount} unread conversations'
        : config.semanticLabel;

    return FocusTraversalOrder(
      order: NumericFocusOrder(config.visualSlot.toDouble()),
      child: Semantics(
        button: true,
        selected: selected,
        label: semanticsLabel,
        onTap: widget.onPressed,
        excludeSemantics: true,
        child: AnimatedScale(
          duration: widget.reduceMotion
              ? Duration.zero
              : Duration(milliseconds: _pressed ? 90 : 180),
          curve: _premiumCurve,
          scale: _pressed ? .96 : 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('yo-destination-${config.visualSlot}'),
              focusNode: _focusNode,
              onTap: widget.onPressed,
              onHighlightChanged: (pressed) {
                if (_pressed == pressed) return;
                setState(() => _pressed = pressed);
              },
              borderRadius: BorderRadius.circular(22),
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return palette.focus.withValues(alpha: .20);
                }
                if (states.contains(WidgetState.pressed) ||
                    states.contains(WidgetState.hovered)) {
                  return AppColors.secondary.withValues(alpha: .10);
                }
                return null;
              }),
              child: SizedBox.expand(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 1,
                    vertical: expandedLabels ? 0 : 3,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          AnimatedContainer(
                            duration: _duration,
                            curve: _premiumCurve,
                            width: expandedLabels ? 34 : 40,
                            height: expandedLabels ? 24 : 29,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected
                                  ? AppColors.secondary.withValues(alpha: .10)
                                  : Colors.transparent,
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: AppColors.secondary.withValues(
                                          alpha: .16,
                                        ),
                                        blurRadius: 10,
                                      ),
                                    ]
                                  : const [],
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: _duration,
                            reverseDuration: _duration,
                            switchInCurve: _premiumCurve,
                            switchOutCurve: Curves.easeOut,
                            transitionBuilder: (child, animation) {
                              final scale = TweenSequence<double>([
                                TweenSequenceItem(
                                  tween: Tween(begin: .92, end: 1.08),
                                  weight: 62,
                                ),
                                TweenSequenceItem(
                                  tween: Tween(begin: 1.08, end: 1),
                                  weight: 38,
                                ),
                              ]).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: scale,
                                  child: child,
                                ),
                              );
                            },
                            child: Icon(
                              selected ? config.selectedIcon : config.icon,
                              key: ValueKey(selected),
                              color: iconColor,
                              size: expandedLabels
                                  ? (selected ? 22 : 20)
                                  : (selected ? 26 : 24),
                            ),
                          ),
                          if (config.badgeCount > 0)
                            Positioned(
                              top: -7,
                              right: -13,
                              child: _UnreadBadge(count: config.badgeCount),
                            ),
                        ],
                      ),
                      SizedBox(height: expandedLabels ? 0 : 3),
                      AnimatedSlide(
                        duration: _duration,
                        curve: _premiumCurve,
                        offset: selected ? const Offset(0, -.09) : Offset.zero,
                        child: AnimatedDefaultTextStyle(
                          duration: _duration,
                          curve: _premiumCurve,
                          style: TextStyle(
                            color: selected
                                ? colors.onPrimaryContainer
                                : palette.navigationInactive,
                            fontFamily: Theme.of(
                              context,
                            ).textTheme.labelMedium?.fontFamily,
                            fontSize: selected ? 11.8 : 11.3,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            height: expandedLabels ? .90 : 1.05,
                          ),
                          child: Text(
                            config.label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: expandedLabels
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      SizedBox(height: expandedLabels ? 0 : 3),
                      AnimatedOpacity(
                        key: ValueKey('yo-active-line-${config.visualSlot}'),
                        duration: _duration,
                        opacity: selected ? 1 : 0,
                        child: Container(
                          width: 18,
                          height: 2,
                          decoration: BoxDecoration(
                            color: colors.onPrimaryContainer,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.secondary.withValues(
                                  alpha: .75,
                                ),
                                blurRadius: 7,
                              ),
                            ],
                          ),
                        ),
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

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.live,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.navigationSurface, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.live.withValues(alpha: .38),
            blurRadius: 8,
          ),
        ],
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: AppColors.background,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _YoCenterActionButton extends StatefulWidget {
  const _YoCenterActionButton({
    required this.diameter,
    required this.onPressed,
    required this.reduceMotion,
  });

  final double diameter;
  final VoidCallback onPressed;
  final bool reduceMotion;

  @override
  State<_YoCenterActionButton> createState() => _YoCenterActionButtonState();
}

class _YoCenterActionButtonState extends State<_YoCenterActionButton>
    with SingleTickerProviderStateMixin {
  static const _premiumCurve = Cubic(0.22, 1, 0.36, 1);
  late final FocusNode _focusNode = FocusNode(debugLabel: 'YO dock 2');
  AnimationController? _ripple;
  bool _pressed = false;
  bool _focused = false;

  @override
  void dispose() {
    _ripple?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _activate() {
    if (!widget.reduceMotion) {
      final ripple = _ripple ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 380),
      );
      setState(() {});
      ripple.forward(from: 0);
    }
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return ListenableBuilder(
      listenable: VoiceCallService.instance,
      builder: (context, _) {
        final voice = VoiceCallService.instance;
        final live =
            voice.roomId != null &&
            voice.status != VoiceCallStatus.disconnected &&
            voice.status != VoiceCallStatus.failed;
        final glow = live ? AppColors.live : AppColors.secondary;
        final semanticLabel = live
            ? voice.isDirectCall
                  ? 'Voice actions — private call active'
                  : 'Voice actions — live in a room'
            : 'Open voice actions';
        // The source asset's alpha bounds occupy about 81–84% of its box.
        // These boxes produce a real visible mark of roughly 48–51 px while
        // retaining at least 7 px to the circular edge.
        final logoSize = widget.diameter < 66 ? 59.0 : 60.0;
        final ripple = _ripple;

        return RepaintBoundary(
          key: const ValueKey('yo-center-action-boundary'),
          child: Semantics(
            button: true,
            label: semanticLabel,
            onTap: _activate,
            excludeSemantics: true,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (!widget.reduceMotion)
                  IgnorePointer(
                    child: AnimatedBuilder(
                      key: const ValueKey('yo-center-ripple'),
                      animation: ripple ?? kAlwaysDismissedAnimation,
                      builder: (context, child) {
                        final t = Curves.easeOutCubic.transform(
                          ripple?.value ?? 0,
                        );
                        return Opacity(
                          opacity: ripple == null ? 0 : (1 - t) * .34,
                          child: Transform.scale(
                            scale: 1 + .55 * t,
                            child: child,
                          ),
                        );
                      },
                      child: SizedBox.square(
                        dimension: widget.diameter,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.secondary,
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                AnimatedScale(
                  duration: widget.reduceMotion
                      ? Duration.zero
                      : Duration(milliseconds: _pressed ? 90 : 260),
                  curve: _premiumCurve,
                  scale: _pressed ? .94 : 1,
                  child: SizedBox.square(
                    dimension: widget.diameter,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.secondary,
                                  AppColors.navigationPrimary,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: glow.withValues(
                                    alpha: _pressed ? .18 : (live ? .38 : .28),
                                  ),
                                  blurRadius: _pressed ? 14 : 22,
                                  spreadRadius: 2,
                                ),
                                BoxShadow(
                                  color: palette.shadow.withValues(alpha: .38),
                                  blurRadius: 14,
                                  offset: const Offset(0, 7),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            focusNode: _focusNode,
                            onTap: _activate,
                            onFocusChange: (focused) {
                              if (_focused == focused) return;
                              setState(() => _focused = focused);
                            },
                            onHighlightChanged: (pressed) {
                              if (_pressed == pressed) return;
                              setState(() => _pressed = pressed);
                            },
                            customBorder: const CircleBorder(),
                            splashFactory: NoSplash.splashFactory,
                            focusColor: AppColors.secondary.withValues(
                              alpha: .20,
                            ),
                            highlightColor: AppColors.secondary.withValues(
                              alpha: .10,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: palette.navigationSurface,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: SizedBox.square(
                                    dimension: logoSize,
                                    child: Image.asset(
                                      'assets/images/logo.png',
                                      key: const ValueKey('dock-logo'),
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.graphic_eq_rounded,
                                        color: palette.textPrimary,
                                        size: 34,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        IgnorePointer(
                          child: AnimatedContainer(
                            key: const ValueKey('yo-center-focus-outline'),
                            duration: widget.reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 160),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _focused
                                    ? palette.focus
                                    : Colors.transparent,
                                width: 2,
                              ),
                              boxShadow: _focused
                                  ? [
                                      BoxShadow(
                                        color: palette.focus.withValues(
                                          alpha: .28,
                                        ),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : const [],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
