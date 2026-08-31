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
    this.tourDestinationKeys,
    this.tourVoiceKey,
    super.key,
  });

  static const double horizontalMargin = 14;
  static const double topClearance = 4;
  static const double minimumBottomClearance = 10;
  static const double visualHeight = 104;
  static const double accessibleVisualHeight = 112;
  static const double cornerRadius = 31;
  static const double centralRise = 30;
  static const double expandedLabelScaleThreshold = 1.6;

  /// The dock outline is navigation chrome, not a generic card boundary and
  /// not a focus indicator. Keeping the mapping named makes that distinction
  /// testable without exposing the private custom shape.
  @visibleForTesting
  static BorderSide outlineSideFor(AppPalette palette) =>
      BorderSide(color: palette.navigationOutline, width: 1.15);

  final int selectedTabIndex;
  final int momentsTabIndex;
  final int unreadConversationCount;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onVoicePressed;
  final VoidCallback onMorePressed;
  final bool moreSelected;

  /// Optional semantic anchors owned by MainShell's guided product tour.
  /// Keys use visual slots (Chats = 1, Moments = 3, More = 4), not domain
  /// indexes, so the dock's non-contiguous Moments index never leaks into the
  /// presentation layer.
  final Map<int, GlobalKey>? tourDestinationKeys;
  final GlobalKey? tourVoiceKey;

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

class _YoFloatingNavigationDockState extends State<YoFloatingNavigationDock>
    with TickerProviderStateMixin {
  static const _premiumCurve = Cubic(0.22, 1, 0.36, 1);
  static const _capsuleSize = 52.0;
  static const double _yoFadeInnerRadius = 22;
  static const double _yoFadeOuterRadius = 52;

  final GlobalKey _geometryRootKey = GlobalKey();
  final Map<int, GlobalKey> _destinationGeometryKeys = {
    0: GlobalKey(),
    1: GlobalKey(),
    3: GlobalKey(),
    4: GlobalKey(),
  };

  late final AnimationController _selectionController = AnimationController(
    vsync: this,
    value: 1,
  );

  Timer? _pendingSelectionExpiry;
  bool? _reduceMotion;
  bool _geometrySyncScheduled = false;
  bool _selectionLaidOut = false;
  bool _selectionCrossesYo = false;
  int? _selectionTargetSlot;
  int? _pendingSelectionSlot;
  Offset _selectionFrom = Offset.zero;
  Offset _selectionTo = Offset.zero;
  Map<int, Offset> _destinationCenters = const {};

  int? get _activeVisualSlot => widget.moreSelected
      ? 4
      : YoFloatingNavigationDock.visualSlotForTab(
          widget.selectedTabIndex,
          momentsTabIndex: widget.momentsTabIndex,
        );

  double get _selectionProgress =>
      _premiumCurve.transform(_selectionController.value.clamp(0.0, 1.0));

  Offset get _renderedSelectionCenter =>
      Offset.lerp(_selectionFrom, _selectionTo, _selectionProgress) ??
      _selectionTo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion && _selectionLaidOut) {
      _selectionController.stop();
      _selectionFrom = _selectionTo;
      _selectionCrossesYo = false;
      _selectionController.value = 1;
    }
    _scheduleGeometrySync();
  }

  @override
  void didUpdateWidget(YoFloatingNavigationDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldAcceptedSlot = oldWidget.moreSelected
        ? 4
        : YoFloatingNavigationDock.visualSlotForTab(
            oldWidget.selectedTabIndex,
            momentsTabIndex: oldWidget.momentsTabIndex,
          );
    final acceptedSlot = _activeVisualSlot;
    if (oldAcceptedSlot != acceptedSlot) {
      _retargetAcceptedSelection(acceptedSlot);
    }
    _scheduleGeometrySync();
  }

  void _retargetAcceptedSelection(int? acceptedSlot) {
    if (acceptedSlot == null) {
      _selectionController.stop();
      _selectionLaidOut = false;
      _selectionTargetSlot = null;
      _selectionCrossesYo = false;
      return;
    }

    final requestedCenter = _destinationCenters[acceptedSlot];
    final rootObject = _geometryRootKey.currentContext?.findRenderObject();
    if (requestedCenter == null ||
        rootObject is! RenderBox ||
        !rootObject.hasSize) {
      return;
    }

    if (!_selectionLaidOut || _selectionTargetSlot == null) {
      _selectionLaidOut = true;
      _selectionTargetSlot = acceptedSlot;
      _selectionFrom = requestedCenter;
      _selectionTo = requestedCenter;
      _selectionCrossesYo = false;
      _selectionController.value = 1;
      _clearPendingSelection(acceptedSlot: acceptedSlot);
      return;
    }

    if (_selectionTargetSlot == acceptedSlot) return;

    final previousSlot = _selectionTargetSlot!;
    final currentCenter = _renderedSelectionCenter;
    final rootCenter = rootObject.size.width / 2;
    final crossesYo = _selectionTravelsBehindYo(
      from: currentCenter,
      to: requestedCenter,
      rootCenter: rootCenter,
    );

    _selectionTargetSlot = acceptedSlot;
    _selectionFrom = currentCenter;
    _selectionTo = requestedCenter;
    _selectionCrossesYo = crossesYo;

    if (_pendingSelectionSlot == acceptedSlot) {
      unawaited(HapticFeedback.selectionClick());
    }
    _clearPendingSelection(acceptedSlot: acceptedSlot);

    if (_reduceMotion ?? false) {
      _selectionCrossesYo = false;
      _selectionController.value = 1;
    } else {
      _selectionController.duration = _selectionDuration(
        previousSlot,
        acceptedSlot,
        crossesYo,
      );
      _selectionController.forward(from: 0);
    }
  }

  void _scheduleGeometrySync() {
    if (_geometrySyncScheduled) return;
    _geometrySyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geometrySyncScheduled = false;
      if (!mounted) return;
      _syncDestinationGeometry();
    });
  }

  void _syncDestinationGeometry() {
    final rootObject = _geometryRootKey.currentContext?.findRenderObject();
    if (rootObject is! RenderBox || !rootObject.hasSize) return;

    final centres = <int, Offset>{};
    for (final entry in _destinationGeometryKeys.entries) {
      final object = entry.value.currentContext?.findRenderObject();
      if (object is! RenderBox || !object.hasSize) return;
      final topLeft = object.localToGlobal(Offset.zero, ancestor: rootObject);
      centres[entry.key] = topLeft + object.size.center(Offset.zero);
    }

    final requested = _activeVisualSlot;
    if (requested == null) {
      if (!_selectionLaidOut && _centresEqual(_destinationCenters, centres)) {
        return;
      }
      _selectionController.stop();
      setState(() {
        _destinationCenters = centres;
        _selectionLaidOut = false;
        _selectionTargetSlot = null;
        _selectionCrossesYo = false;
      });
      return;
    }

    final requestedCenter = centres[requested];
    if (requestedCenter == null) return;

    if (!_selectionLaidOut || _selectionTargetSlot == null) {
      setState(() {
        _destinationCenters = centres;
        _selectionLaidOut = true;
        _selectionTargetSlot = requested;
        _selectionFrom = requestedCenter;
        _selectionTo = requestedCenter;
        _selectionCrossesYo = false;
      });
      _selectionController.value = 1;
      _clearPendingSelection(acceptedSlot: requested);
      return;
    }

    if (_selectionTargetSlot == requested) {
      final moved = (_selectionTo - requestedCenter).distance > .25;
      if (_centresEqual(_destinationCenters, centres) && !moved) return;
      setState(() {
        _destinationCenters = centres;
        if (moved) {
          _selectionFrom = requestedCenter;
          _selectionTo = requestedCenter;
          _selectionCrossesYo = false;
        }
      });
      if (moved) _selectionController.value = 1;
      return;
    }

    final previousSlot = _selectionTargetSlot!;
    final currentCenter = _renderedSelectionCenter;
    final crossesYo = _selectionTravelsBehindYo(
      from: currentCenter,
      to: requestedCenter,
      rootCenter: rootObject.size.width / 2,
    );
    final duration = _selectionDuration(previousSlot, requested, crossesYo);

    setState(() {
      _destinationCenters = centres;
      _selectionTargetSlot = requested;
      _selectionFrom = currentCenter;
      _selectionTo = requestedCenter;
      _selectionCrossesYo = crossesYo;
    });

    if (_pendingSelectionSlot == requested) {
      unawaited(HapticFeedback.selectionClick());
    }
    _clearPendingSelection(acceptedSlot: requested);

    if (_reduceMotion ?? false) {
      _selectionCrossesYo = false;
      _selectionController.value = 1;
    } else {
      _selectionController.duration = duration;
      _selectionController.forward(from: 0);
    }
  }

  static bool _centresEqual(Map<int, Offset> a, Map<int, Offset> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || (entry.value - other).distance > .25) return false;
    }
    return true;
  }

  bool _selectionTravelsBehindYo({
    required Offset from,
    required Offset to,
    required double rootCenter,
  }) {
    final changesSide =
        (from.dx < rootCenter && to.dx > rootCenter) ||
        (from.dx > rootCenter && to.dx < rootCenter);
    final reversesInsideFadeZone =
        _selectionCrossesYo &&
        (from.dx - rootCenter).abs() < _yoFadeOuterRadius;
    return changesSide || reversesInsideFadeZone;
  }

  static Duration _selectionDuration(int from, int to, bool crossesYo) {
    final distance = (from - to).abs();
    if (!crossesYo) return const Duration(milliseconds: 330);
    return switch (distance) {
      >= 4 => const Duration(milliseconds: 620),
      3 => const Duration(milliseconds: 560),
      _ => const Duration(milliseconds: 480),
    };
  }

  void _clearPendingSelection({required int acceptedSlot}) {
    if (_pendingSelectionSlot != acceptedSlot) return;
    _pendingSelectionExpiry?.cancel();
    _pendingSelectionExpiry = null;
    _pendingSelectionSlot = null;
  }

  void _select(YoNavigationDestinationConfig destination) {
    if (!destination.isSelected) {
      _pendingSelectionSlot = destination.visualSlot;
      _pendingSelectionExpiry?.cancel();
      _pendingSelectionExpiry = Timer(const Duration(milliseconds: 900), () {
        if (!mounted || _pendingSelectionSlot != destination.visualSlot) return;
        _pendingSelectionSlot = null;
      });
    }
    destination.onPressed();
  }

  Widget _tourDestinationAnchor(int slot, Widget child) {
    final key = widget.tourDestinationKeys?[slot];
    return key == null ? child : KeyedSubtree(key: key, child: child);
  }

  Widget _tourVoiceAnchor(Widget child) {
    final key = widget.tourVoiceKey;
    return key == null ? child : KeyedSubtree(key: key, child: child);
  }

  @override
  void dispose() {
    _pendingSelectionExpiry?.cancel();
    _selectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final tokens = _DockMaterialTokens.of(context);
    final reduceMotion = _reduceMotion ?? false;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final expandedLabels =
        textScale >= YoFloatingNavigationDock.expandedLabelScaleThreshold;
    final dockVisualHeight = YoFloatingNavigationDock.visualHeightFor(
      textScale: textScale,
    );
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
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: YoFloatingNavigationDock.topClearance,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final narrow = width < 332;
                          final slotWidth = width / 5;
                          final destinationWidth = math.min(
                            narrow ? 52.0 : 56.0,
                            slotWidth - 2,
                          );
                          final destinationHeight = expandedLabels
                              ? 68.0
                              : 52.0;
                          final destinationTop = expandedLabels ? 37.0 : 41.0;
                          final centerDiameter = narrow ? 64.0 : 68.0;
                          final centerLogoAssetSize = narrow ? 68.0 : 76.0;
                          const centerLogoOpticalOffset = 19.0;
                          final centerLogoTop =
                              (centerDiameter - centerLogoAssetSize) / 2 +
                              centerLogoOpticalOffset;
                          final centerHitWidth = centerDiameter;
                          final centerHitHeight = math.max(
                            centerDiameter,
                            centerLogoTop + centerLogoAssetSize,
                          );
                          final centerHitLeft = (width - centerHitWidth) / 2;
                          final shape = _YoSculptedDockShape(
                            cornerRadius: YoFloatingNavigationDock.cornerRadius,
                            riseHeight: YoFloatingNavigationDock.centralRise,
                            side: YoFloatingNavigationDock.outlineSideFor(
                              palette,
                            ),
                            rimColors: tokens.rimColors,
                          );

                          _scheduleGeometrySync();

                          return Stack(
                            key: _geometryRootKey,
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: DecoratedBox(
                                  key: const ValueKey(
                                    'yo-floating-navigation-dock',
                                  ),
                                  decoration: ShapeDecoration(
                                    gradient: tokens.shellGradient,
                                    shape: shape,
                                    shadows: tokens.shellShadows,
                                  ),
                                  child: ClipPath(
                                    key: const ValueKey(
                                      'yo-dock-sculpted-clip',
                                    ),
                                    clipper: ShapeBorderClipper(shape: shape),
                                    child: CustomPaint(
                                      painter: _DockSurfaceFinishPainter(
                                        shape: shape,
                                        highlight: tokens.innerHighlight,
                                        lowerShade: tokens.lowerShade,
                                      ),
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                                ),
                              ),
                              if (_selectionLaidOut &&
                                  _selectionTargetSlot != null)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: AnimatedBuilder(
                                      animation: _selectionController,
                                      builder: (context, child) {
                                        final center = _renderedSelectionCenter;
                                        final travel = math.sin(
                                          math.pi * _selectionController.value,
                                        );
                                        final centerDistance =
                                            (center.dx - width / 2).abs();
                                        final centerVisibility =
                                            _selectionCrossesYo
                                            ? ((centerDistance -
                                                          _yoFadeInnerRadius) /
                                                      (_yoFadeOuterRadius -
                                                          _yoFadeInnerRadius))
                                                  .clamp(0.0, 1.0)
                                            : 1.0;
                                        final stretch = reduceMotion
                                            ? 1.0
                                            : 1 +
                                                  travel *
                                                      (_selectionCrossesYo
                                                          ? .06
                                                          : .11) *
                                                      centerVisibility;
                                        final contract =
                                            .78 + .22 * centerVisibility;
                                        return Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Positioned(
                                              left:
                                                  center.dx - _capsuleSize / 2,
                                              top: center.dy - _capsuleSize / 2,
                                              child: Opacity(
                                                key: const ValueKey(
                                                  'yo-active-capsule-opacity',
                                                ),
                                                opacity: centerVisibility,
                                                child: Transform.scale(
                                                  key: const ValueKey(
                                                    'yo-active-capsule-scale',
                                                  ),
                                                  scaleX: stretch * contract,
                                                  scaleY: contract,
                                                  child: SizedBox.square(
                                                    key: const ValueKey(
                                                      'yo-active-capsule-position',
                                                    ),
                                                    dimension: _capsuleSize,
                                                    child: child,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                      child: _ActiveCapsule(
                                        tokens: tokens,
                                        reduceMotion: reduceMotion,
                                      ),
                                    ),
                                  ),
                                ),
                              for (final slot in [0, 1, 3, 4])
                                Positioned(
                                  key: ValueKey(
                                    'yo-destination-position-$slot',
                                  ),
                                  left:
                                      slotWidth * (slot + .5) -
                                      destinationWidth / 2,
                                  top: destinationTop,
                                  width: destinationWidth,
                                  height: destinationHeight,
                                  child: _tourDestinationAnchor(
                                    slot,
                                    _YoDockDestination(
                                      key: ValueKey(
                                        'yo-destination-widget-$slot',
                                      ),
                                      geometryKey:
                                          _destinationGeometryKeys[slot]!,
                                      config: bySlot[slot]!,
                                      expandedLabel: expandedLabels,
                                      reduceMotion: reduceMotion,
                                      onPressed: () => _select(bySlot[slot]!),
                                    ),
                                  ),
                                ),
                              Positioned(
                                left: centerHitLeft,
                                top: 0,
                                width: centerHitWidth,
                                height: centerHitHeight,
                                child: FocusTraversalOrder(
                                  order: const NumericFocusOrder(2),
                                  child: _tourVoiceAnchor(
                                    _YoCenterActionButton(
                                      diameter: centerDiameter,
                                      logoAssetSize: centerLogoAssetSize,
                                      logoOpticalOffset:
                                          centerLogoOpticalOffset,
                                      onPressed: widget.onVoicePressed,
                                      reduceMotion: reduceMotion,
                                    ),
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
      ),
    );
  }
}

@immutable
class _DockMaterialTokens {
  const _DockMaterialTokens({
    required this.shellGradient,
    required this.rimColors,
    required this.shellShadows,
    required this.innerHighlight,
    required this.lowerShade,
    required this.selectionGradient,
    required this.selectionBorder,
    required this.selectionGlow,
  });

  factory _DockMaterialTokens.of(BuildContext context) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _DockMaterialTokens(
      shellGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? [
                Color.lerp(
                  palette.navigationSurface,
                  palette.surfaceRaised,
                  .12,
                )!.withValues(alpha: .98),
                palette.navigationSurface.withValues(alpha: .98),
                palette.surfaceSunken.withValues(alpha: .99),
              ]
            : [
                palette.surfaceRaised.withValues(alpha: .98),
                palette.navigationSurface.withValues(alpha: .97),
                palette.surfaceMuted.withValues(alpha: .91),
              ],
      ),
      rimColors: [
        palette.textPrimary.withValues(alpha: dark ? .48 : .42),
        palette.navigationOutline.withValues(alpha: .92),
        AppColors.secondary.withValues(alpha: dark ? .88 : .72),
        AppColors.navigationPrimary.withValues(alpha: dark ? .82 : .68),
      ],
      shellShadows: [
        BoxShadow(
          color: palette.shadow.withValues(alpha: dark ? .42 : .12),
          blurRadius: dark ? 25 : 18,
          offset: Offset(0, dark ? 11 : 8),
        ),
        BoxShadow(
          color: AppColors.navigationPrimary.withValues(
            alpha: dark ? .10 : .08,
          ),
          blurRadius: dark ? 30 : 24,
          spreadRadius: dark ? 1 : 0,
        ),
      ],
      innerHighlight: palette.textPrimary.withValues(alpha: dark ? .13 : .42),
      lowerShade: palette.shadow.withValues(alpha: dark ? .18 : .08),
      selectionGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? [
                Color.lerp(
                  palette.surfaceRaised,
                  scheme.primaryContainer,
                  .28,
                )!,
                palette.surfaceMuted,
              ]
            : [
                palette.surfaceRaised,
                Color.lerp(palette.surfaceMuted, scheme.primaryContainer, .34)!,
              ],
      ),
      selectionBorder: Color.lerp(
        palette.navigationOutline,
        scheme.primary,
        dark ? .54 : .42,
      )!,
      selectionGlow: scheme.primary.withValues(alpha: dark ? .17 : .14),
    );
  }

  final LinearGradient shellGradient;
  final List<Color> rimColors;
  final List<BoxShadow> shellShadows;
  final Color innerHighlight;
  final Color lowerShade;
  final LinearGradient selectionGradient;
  final Color selectionBorder;
  final Color selectionGlow;
}

/// One continuous vector outline: the central rise and the pill body share the
/// same path, border and shadow. There is deliberately no FAB notch or cutout.
class _YoSculptedDockShape extends ShapeBorder {
  const _YoSculptedDockShape({
    required this.cornerRadius,
    required this.riseHeight,
    required this.side,
    required this.rimColors,
  });

  final double cornerRadius;
  final double riseHeight;
  final BorderSide side;
  final List<Color> rimColors;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  ShapeBorder scale(double t) => _YoSculptedDockShape(
    cornerRadius: cornerRadius * t,
    riseHeight: riseHeight * t,
    side: side.scale(t),
    rimColors: rimColors,
  );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _pathFor(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _pathFor(rect.deflate(side.width));

  Path _pathFor(Rect rect) {
    final radius = math.min(
      cornerRadius,
      math.min(rect.width / 2, (rect.height - riseHeight) / 2),
    );
    final center = rect.center.dx;
    final shoulder = math.min(64.0, rect.width * .18);
    final innerControl = math.min(39.0, shoulder * .62);
    final outerControl = math.min(47.0, shoulder * .75);
    final bodyTop = rect.top + riseHeight;

    return Path()
      ..moveTo(rect.left + radius, bodyTop)
      ..lineTo(center - shoulder, bodyTop)
      ..cubicTo(
        center - outerControl,
        bodyTop,
        center - innerControl,
        rect.top,
        center,
        rect.top,
      )
      ..cubicTo(
        center + innerControl,
        rect.top,
        center + outerControl,
        bodyTop,
        center + shoulder,
        bodyTop,
      )
      ..lineTo(rect.right - radius, bodyTop)
      ..quadraticBezierTo(rect.right, bodyTop, rect.right, bodyTop + radius)
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
      ..lineTo(rect.left, bodyTop + radius)
      ..quadraticBezierTo(rect.left, bodyTop, rect.left + radius, bodyTop)
      ..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    final paint = side.toPaint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side.width
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: rimColors,
      ).createShader(rect);
    canvas.drawPath(getOuterPath(rect), paint);
  }
}

class _DockSurfaceFinishPainter extends CustomPainter {
  const _DockSurfaceFinishPainter({
    required this.shape,
    required this.highlight,
    required this.lowerShade,
  });

  final ShapeBorder shape;
  final Color highlight;
  final Color lowerShade;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect);
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(
      shape.getOuterPath(rect.deflate(1.25)),
      Paint()
        ..color = highlight
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
    canvas.drawLine(
      Offset(34, size.height - 1.5),
      Offset(size.width - 34, size.height - 1.5),
      Paint()
        ..color = lowerShade
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DockSurfaceFinishPainter oldDelegate) =>
      oldDelegate.highlight != highlight ||
      oldDelegate.lowerShade != lowerShade ||
      oldDelegate.shape != shape;
}

class _ActiveCapsule extends StatelessWidget {
  const _ActiveCapsule({required this.tokens, required this.reduceMotion});

  final _DockMaterialTokens tokens;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: ValueKey(
        reduceMotion
            ? 'yo-active-capsule-reduced-motion'
            : 'yo-active-capsule-static',
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: tokens.selectionGradient,
        border: Border.all(color: tokens.selectionBorder),
        boxShadow: [
          BoxShadow(
            color: tokens.selectionGlow.withValues(alpha: .68),
            blurRadius: 11,
          ),
        ],
      ),
    );
  }
}

class _YoDockDestination extends StatefulWidget {
  const _YoDockDestination({
    required this.geometryKey,
    required this.config,
    required this.expandedLabel,
    required this.reduceMotion,
    required this.onPressed,
    super.key,
  });

  final GlobalKey geometryKey;
  final YoNavigationDestinationConfig config;
  final bool expandedLabel;
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
  bool _focused = false;

  Duration get _duration =>
      widget.reduceMotion ? Duration.zero : const Duration(milliseconds: 310);

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (mounted && _focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final selected = config.isSelected;
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final iconColor = selected
        ? colors.onPrimaryContainer
        : palette.navigationInactive;
    final semanticsLabel = config.badgeCount > 0
        ? AppLocalizations.of(
            context,
          ).navigationUnreadLabel(config.semanticLabel, config.badgeCount)
        : config.semanticLabel;
    final selectedSlide = switch (config.visualSlot) {
      0 => const Offset(0, -.06),
      1 => const Offset(.025, -.035),
      3 => const Offset(0, -.045),
      4 => const Offset(0, -.02),
      _ => Offset.zero,
    };

    return SizedBox.expand(
      key: widget.geometryKey,
      child: FocusTraversalOrder(
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
                : Duration(milliseconds: _pressed ? 90 : 190),
            curve: _premiumCurve,
            scale: _pressed ? .96 : 1,
            child: Material(
              key: ValueKey('yo-destination-focus-${config.visualSlot}'),
              type: MaterialType.transparency,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: _focused ? palette.focus : Colors.transparent,
                  width: 2,
                ),
              ),
              child: InkWell(
                key: ValueKey('yo-destination-${config.visualSlot}'),
                focusNode: _focusNode,
                onTap: widget.onPressed,
                onHighlightChanged: (pressed) {
                  if (_pressed == pressed) return;
                  setState(() => _pressed = pressed);
                },
                borderRadius: BorderRadius.circular(18),
                overlayColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.focused)) {
                    return palette.focus.withValues(alpha: .10);
                  }
                  if (states.contains(WidgetState.pressed) ||
                      states.contains(WidgetState.hovered)) {
                    return AppColors.secondary.withValues(alpha: .08);
                  }
                  return null;
                }),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSlide(
                          key: ValueKey(
                            'yo-destination-icon-slide-${config.visualSlot}',
                          ),
                          duration: _duration,
                          curve: _premiumCurve,
                          offset: selected ? selectedSlide : Offset.zero,
                          child: AnimatedScale(
                            key: ValueKey(
                              'yo-destination-icon-scale-${config.visualSlot}',
                            ),
                            duration: _duration,
                            curve: _premiumCurve,
                            scale: selected ? 1 : .95,
                            child: AnimatedSwitcher(
                              duration: _duration,
                              reverseDuration: _duration,
                              switchInCurve: _premiumCurve,
                              switchOutCurve: Curves.easeOut,
                              transitionBuilder: (child, animation) {
                                final scale = TweenSequence<double>([
                                  TweenSequenceItem(
                                    tween: Tween(begin: .92, end: 1.04),
                                    weight: 68,
                                  ),
                                  TweenSequenceItem(
                                    tween: Tween(begin: 1.04, end: 1),
                                    weight: 32,
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
                                key: ValueKey('${config.visualSlot}-$selected'),
                                color: iconColor,
                                size: selected ? 26 : 25,
                              ),
                            ),
                          ),
                        ),
                        if (widget.expandedLabel) ...[
                          const SizedBox(height: 3),
                          SizedBox(
                            width: 52,
                            height: 18,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                config.label,
                                maxLines: 1,
                                overflow: TextOverflow.visible,
                                style: TextStyle(
                                  color: selected
                                      ? colors.onPrimaryContainer
                                      : palette.navigationInactive,
                                  fontSize: 11,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Positioned(
                      bottom: widget.expandedLabel ? 1 : 5,
                      child: AnimatedOpacity(
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
                                  alpha: .62,
                                ),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (config.badgeCount > 0)
                      Positioned(
                        top: -6,
                        right: 2,
                        child: _UnreadBadge(count: config.badgeCount),
                      ),
                  ],
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
    return UnconstrainedBox(
      child: Container(
        key: const ValueKey('yo-chats-unread-badge'),
        width: count > 99 ? 31 : 19,
        height: 19,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: count > 99 ? 3 : 0),
        decoration: BoxDecoration(
          color: AppColors.live,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.navigationSurface, width: 2),
          boxShadow: [
            BoxShadow(
              color: AppColors.live.withValues(alpha: .34),
              blurRadius: 8,
            ),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            count > 99 ? '99+' : '$count',
            maxLines: 1,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(
              color: AppColors.onLive,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _YoCenterActionButton extends StatefulWidget {
  const _YoCenterActionButton({
    required this.diameter,
    required this.logoAssetSize,
    required this.logoOpticalOffset,
    required this.onPressed,
    required this.reduceMotion,
  });

  final double diameter;
  final double logoAssetSize;
  final double logoOpticalOffset;
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
  late ({bool live, bool direct}) _voiceState;

  ({bool live, bool direct}) _readVoiceState() {
    final voice = VoiceCallService.instance;
    final live =
        voice.roomId != null &&
        voice.status != VoiceCallStatus.disconnected &&
        voice.status != VoiceCallStatus.failed;
    return (live: live, direct: live && voice.isDirectCall);
  }

  @override
  void initState() {
    super.initState();
    _voiceState = _readVoiceState();
    VoiceCallService.instance.addListener(_handleVoiceStateChange);
  }

  void _handleVoiceStateChange() {
    final next = _readVoiceState();
    if (!mounted || next == _voiceState) return;
    setState(() => _voiceState = next);
  }

  @override
  void didUpdateWidget(_YoCenterActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.reduceMotion && widget.reduceMotion) {
      _ripple?.stop();
      _ripple?.value = 0;
    }
  }

  @override
  void dispose() {
    VoiceCallService.instance.removeListener(_handleVoiceStateChange);
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
      if (mounted) setState(() {});
      ripple.forward(from: 0);
    }
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final semanticLabel = _voiceState.live
        ? _voiceState.direct
              ? copy.voiceActionsPrivateCallActive
              : copy.voiceActionsRoomActive
        : copy.openVoiceActions;
    final ripple = _ripple;

    return RepaintBoundary(
      child: Semantics(
        key: const ValueKey('yo-center-action-hit-target'),
        button: true,
        label: semanticLabel,
        onTap: _activate,
        excludeSemantics: true,
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            if (!widget.reduceMotion)
              IgnorePointer(
                child: AnimatedBuilder(
                  key: const ValueKey('yo-center-ripple'),
                  animation: ripple ?? kAlwaysDismissedAnimation,
                  builder: (context, child) {
                    final t = Curves.easeOutCubic.transform(ripple?.value ?? 0);
                    return Opacity(
                      opacity: ripple == null ? 0 : (1 - t) * .46,
                      child: Transform.scale(scale: 1 + .48 * t, child: child),
                    );
                  },
                  child: SizedBox.square(
                    dimension: widget.diameter,
                    child: CustomPaint(
                      painter: _OutlineRipplePainter(
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                ),
              ),
            AnimatedScale(
              key: const ValueKey('yo-center-press-scale'),
              duration: widget.reduceMotion
                  ? Duration.zero
                  : Duration(milliseconds: _pressed ? 90 : 230),
              curve: _premiumCurve,
              scale: _pressed ? .95 : 1,
              child: SizedBox.square(
                key: const ValueKey('yo-center-action-boundary'),
                dimension: widget.diameter,
                child: Material(
                  type: MaterialType.transparency,
                  child: Center(
                    child: Transform.translate(
                      offset: Offset(0, widget.logoOpticalOffset),
                      child: OverflowBox(
                        minWidth: widget.logoAssetSize,
                        maxWidth: widget.logoAssetSize,
                        minHeight: widget.logoAssetSize,
                        maxHeight: widget.logoAssetSize,
                        child: SizedBox.square(
                          dimension: widget.logoAssetSize,
                          child: Image.asset(
                            'assets/images/yo-voice-favicon-512.png',
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
            ),
            IgnorePointer(
              child: AnimatedContainer(
                key: const ValueKey('yo-center-focus-outline'),
                duration: widget.reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                width: widget.diameter,
                height: widget.diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _focused ? palette.focus : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: _focused
                      ? [
                          BoxShadow(
                            color: palette.focus.withValues(alpha: .24),
                            blurRadius: 9,
                            spreadRadius: 1,
                          ),
                        ]
                      : const [],
                ),
              ),
            ),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
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
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlineRipplePainter extends CustomPainter {
  const _OutlineRipplePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawOval(
      Offset.zero & size,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_OutlineRipplePainter oldDelegate) =>
      oldDelegate.color != color;
}
