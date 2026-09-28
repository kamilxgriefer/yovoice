import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/shared/widgets/navigation/yo_moments_icon.dart';

/// Every size the dock draws with, for one slot count.
///
/// [fiveTab] is the dock as it shipped through 3.4.0: Start · Serwery ·
/// Czaty · Momenty · Więcej. It stays the production dock until Premium
/// Pages are enabled for the signed-in account (spec premium-pages §2.1).
///
/// [sixTab] is ADR-232 ("six dock destinations, whole dock at 90 %"): the
/// same bead, socket and animations with every dimension scaled by 0.9 and a
/// sixth destination, Treści, between Czaty and Momenty. The numbers are the
/// owner-approved R1 render (`DockSpec.scaled('1', .9)`), not a restyle.
@immutable
class YoDockMetrics {
  const YoDockMetrics._({
    required this.slots,
    required this.topClearance,
    required this.minimumBottomClearance,
    required this.visualHeight,
    required this.accessibleVisualHeight,
    required this.accessibleGrowthPerScale,
    required this.expandedMinimumHeight,
    required this.bodyTop,
    required this.corner,
    required this.socketPad,
    required this.iconTop,
    required this.iconBox,
    required this.iconSize,
    required this.momentsIconSize,
    required this.lift,
    required this.labelSize,
    required this.labelTop,
    required this.labelBottom,
    required this.labelOverhang,
    required this.compactLabelMaxHeight,
    required this.tileRadius,
    required this.glow,
    required this.badgeScale,
    required this.shadowScale,
    required this.expandedLabelTop,
    required this.expandedLabelBottom,
    required this.expandedLabelInset,
  });

  static const fiveTab = YoDockMetrics._(
    slots: 5,
    topClearance: 4,
    minimumBottomClearance: 10,
    visualHeight: 92,
    accessibleVisualHeight: 154,
    accessibleGrowthPerScale: 26,
    expandedMinimumHeight: 116,
    bodyTop: 28,
    corner: 14,
    socketPad: 4,
    iconTop: 51,
    iconBox: 24,
    iconSize: 23,
    momentsIconSize: 24,
    lift: 35,
    labelSize: 10,
    labelTop: 64,
    labelBottom: 2,
    labelOverhang: 8,
    compactLabelMaxHeight: 26,
    tileRadius: 14,
    glow: 75,
    badgeScale: 1,
    shadowScale: 1,
    expandedLabelTop: 88,
    expandedLabelBottom: 6,
    expandedLabelInset: 16,
  );

  static const sixTab = YoDockMetrics._(
    slots: 6,
    topClearance: 3.6,
    minimumBottomClearance: 9,
    visualHeight: 82.8,
    accessibleVisualHeight: 138.6,
    accessibleGrowthPerScale: 23.4,
    expandedMinimumHeight: 104.4,
    bodyTop: 25.2,
    corner: 12.6,
    socketPad: 3.6,
    iconTop: 45.9,
    iconBox: 21.6,
    iconSize: 20.7,
    momentsIconSize: 21.6,
    lift: 31.5,
    labelSize: 9,
    labelTop: 57.6,
    labelBottom: 1.8,
    labelOverhang: 7.2,
    compactLabelMaxHeight: 23.4,
    tileRadius: 12.6,
    glow: 67.5,
    badgeScale: .9,
    shadowScale: .9,
    expandedLabelTop: 79.2,
    expandedLabelBottom: 5.4,
    // The caption keeps 12 px: it is user-scaled text (docs/UI.md).
    expandedLabelInset: 14.4,
  );

  final int slots;
  final double topClearance, minimumBottomClearance;
  final double visualHeight, accessibleVisualHeight, accessibleGrowthPerScale;
  final double expandedMinimumHeight, bodyTop, corner, socketPad;
  final double iconTop, iconBox, iconSize, momentsIconSize, lift;
  final double labelSize, labelTop, labelBottom, labelOverhang;
  final double compactLabelMaxHeight, tileRadius, glow;
  final double badgeScale, shadowScale;
  final double expandedLabelTop, expandedLabelBottom, expandedLabelInset;

  /// Centre of a resting destination glyph, measured from the dock's top.
  double get restingIconCenter => iconTop + iconBox / 2;

  double visualHeightFor(double textScale) =>
      textScale >= YoFloatingNavigationDock.expandedLabelScaleThreshold
      ? accessibleVisualHeight +
            math.max(0, textScale - 2) * accessibleGrowthPerScale
      : visualHeight;
}

/// One width regime of the dock (spec premium-pages §4.1.2): the side
/// margin, the end inset from the dock edge to the first and last
/// destination centre, and the bead diameter.
@immutable
class YoDockRegime {
  const YoDockRegime({
    required this.name,
    required this.margin,
    required this.inset,
    required this.bead,
  });

  final String name;
  final double margin, inset, bead;

  @override
  bool operator ==(Object other) =>
      other is YoDockRegime &&
      other.name == name &&
      other.margin == margin &&
      other.inset == inset &&
      other.bead == bead;

  @override
  int get hashCode => Object.hash(name, margin, inset, bead);

  @override
  String toString() =>
      'YoDockRegime($name, margin: $margin, inset: $inset, bead: $bead)';
}

/// One moving bead and concave socket. Drag previews paint only; release
/// requests one destination and the shell remains authoritative.
class YoFloatingNavigationDock extends StatefulWidget {
  const YoFloatingNavigationDock({
    required this.selectedTabIndex,
    required this.momentsTabIndex,
    required this.unreadConversationCount,
    required this.onDestinationSelected,
    required this.onVoicePressed,
    required this.onMorePressed,
    this.roomsTabIndex = 3,
    this.contentTabIndex,
    this.moreSelected = false,
    this.tourDestinationKeys,
    this.tourVoiceKey,
    super.key,
  });

  // Five-tab constants, unchanged since 3.4.0. The six-tab dock reads
  // [YoDockMetrics.sixTab] and [sixTabRegimeFor] instead.
  static const horizontalMargin = 14.0;
  static const topClearance = 4.0;
  static const minimumBottomClearance = 10.0;
  static const visualHeight = 92.0;
  static const accessibleVisualHeight = 154.0;
  static const expandedLabelScaleThreshold = 1.3;
  static const bodyTop = 28.0;

  /// The six-tab dock switches between its wide and narrow bead exactly at
  /// this viewport width (spec §4.1.2: Narrow A above it, Narrow B below).
  static const narrowBeadBelowWidth = 342.8;

  final int selectedTabIndex,
      momentsTabIndex,
      roomsTabIndex,
      unreadConversationCount;

  /// The shell's content slot for Treści (Premium Pages). Null keeps the
  /// five-tab dock; a value shows the six-tab ×0.9 dock with Treści as the
  /// fourth destination. The shell passes it only while Pages are enabled
  /// for the signed-in account.
  final int? contentTabIndex;
  final ValueChanged<int> onDestinationSelected;

  /// Source compatibility for hosted routes; creation now lives on Home/Servers.
  final VoidCallback onVoicePressed;
  final VoidCallback onMorePressed;
  final bool moreSelected;

  /// Keyed by visual slot: 0 Start, 1 Serwery, 2 Czaty, then Momenty and
  /// Więcej at 3 and 4 (five tabs) or Treści, Momenty and Więcej at 3, 4 and
  /// 5 (six tabs).
  final Map<int, GlobalKey>? tourDestinationKeys;
  final GlobalKey? tourVoiceKey;

  static BorderSide outlineSideFor(AppPalette palette) =>
      BorderSide(color: palette.navigationOutline, width: 1);

  static YoDockMetrics metricsFor({required bool sixTabs}) =>
      sixTabs ? YoDockMetrics.sixTab : YoDockMetrics.fiveTab;

  static double visualHeightFor({
    required double textScale,
    bool sixTabs = false,
  }) => metricsFor(sixTabs: sixTabs).visualHeightFor(textScale);

  static double reservedHeightFor({
    required double safeBottom,
    double textScale = 1,
    bool sixTabs = false,
  }) {
    final metrics = metricsFor(sixTabs: sixTabs);
    return metrics.topClearance +
        metrics.visualHeightFor(textScale) +
        math.max(safeBottom, metrics.minimumBottomClearance);
  }

  /// The six-tab dock's settled regime for a viewport [width] (spec §4.1.2).
  /// Every destination stays at least 48 px wide down to 314 px, where the
  /// side margin has reached 0; below that the inset absorbs the rest.
  static YoDockRegime sixTabRegimeFor(double width) =>
      width >= narrowBeadBelowWidth
      ? _sixTabWideRegime(width)
      : _sixTabNarrowRegime(width);

  static YoDockRegime _sixTabWideRegime(double width) => width >= 351.6
      ? const YoDockRegime(
          name: 'regular',
          margin: 12.6,
          inset: 43.2,
          bead: 43.2,
        )
      : YoDockRegime(
          name: 'narrowA',
          margin: 12.6,
          inset: math.max(0, (width - 265.2) / 2),
          bead: 43.2,
        );

  static YoDockRegime _sixTabNarrowRegime(double width) => width >= 314
      ? YoDockRegime(
          name: 'narrowB',
          margin: ((width - 314) / 2).clamp(0.0, 12.6),
          inset: 37,
          bead: 39.6,
        )
      : YoDockRegime(
          name: 'belowFloor',
          margin: 0,
          inset: math.max(0, (width - 240) / 2),
          bead: 39.6,
        );

  /// Maps a shell content slot onto its visual dock slot, or null when the
  /// slot has no dock destination (Friends, desktop-only slots).
  static int? visualSlotForTab(
    int tab, {
    required int momentsTabIndex,
    int roomsTabIndex = 3,
    int? contentTabIndex,
  }) {
    if (tab == 0) return 0;
    if (tab == roomsTabIndex) return 1;
    if (tab == 1) return 2;
    if (contentTabIndex != null) {
      if (tab == contentTabIndex) return 3;
      if (tab == momentsTabIndex) return 4;
      return null;
    }
    if (tab == momentsTabIndex) return 3;
    return null;
  }

  @override
  State<YoFloatingNavigationDock> createState() =>
      _YoFloatingNavigationDockState();
}

enum _DockDestination { home, servers, chats, content, moments, more }

class _YoFloatingNavigationDockState extends State<YoFloatingNavigationDock>
    with TickerProviderStateMixin {
  static const _expandedLabelStyle = TextStyle(
    fontSize: 12,
    height: 1.15,
    fontWeight: FontWeight.w700,
  );
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 230,
    damping: 25,
  );
  static const _springTolerance = Tolerance(distance: .0005, velocity: .005);
  late final AnimationController _position;

  /// 0 = the wide bead (Regular / Narrow A), 1 = the narrow bead (Narrow B /
  /// below floor). Six tabs only; it moves on a width change, never on a tab
  /// change, and jumps under Reduce Motion.
  late final AnimationController _regime;
  bool? _narrowTarget;
  bool _regimeJump = false;
  bool _reduceMotion = false, _dragging = false;
  double _dragVelocity = 0;
  int? _pendingSlot;

  bool get _sixTabs => widget.contentTabIndex != null;
  YoDockMetrics get _metrics =>
      YoFloatingNavigationDock.metricsFor(sixTabs: _sixTabs);
  int get _lastSlot => _metrics.slots - 1;

  List<_DockDestination> get _destinations => _sixTabs
      ? _DockDestination.values
      : const [
          _DockDestination.home,
          _DockDestination.servers,
          _DockDestination.chats,
          _DockDestination.moments,
          _DockDestination.more,
        ];

  int? get _acceptedSlot => widget.moreSelected
      ? _lastSlot
      : YoFloatingNavigationDock.visualSlotForTab(
          widget.selectedTabIndex,
          momentsTabIndex: widget.momentsTabIndex,
          roomsTabIndex: widget.roomsTabIndex,
          contentTabIndex: widget.contentTabIndex,
        );

  @override
  void initState() {
    super.initState();
    _position = AnimationController.unbounded(
      vsync: this,
      value: (_acceptedSlot ?? 0).toDouble(),
    );
    _regime = AnimationController.unbounded(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    final disabled = media.disableAnimations || media.accessibleNavigation;
    if (_reduceMotion == disabled) return;
    _reduceMotion = disabled;
    if (disabled) {
      _dragging = false;
      _dragVelocity = 0;
      _position.value = (_acceptedSlot ?? 0).toDouble();
      final narrow = _narrowTarget;
      if (narrow != null && _regime.isAnimating) {
        _regime.stop();
        _regime.value = narrow ? 1 : 0;
      }
    }
  }

  @override
  void didUpdateWidget(YoFloatingNavigationDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentTabIndex != widget.contentTabIndex) {
      // The slot count changed (Pages were enabled or disabled): positions
      // from the old layout mean nothing in the new one, so the bead lands
      // on its destination without travelling.
      _position.stop();
      _dragging = false;
      _dragVelocity = 0;
      _pendingSlot = null;
      _position.value = (_acceptedSlot ?? 0).toDouble();
      _narrowTarget = null;
      return;
    }
    if (oldWidget.selectedTabIndex == widget.selectedTabIndex &&
        oldWidget.moreSelected == widget.moreSelected &&
        oldWidget.roomsTabIndex == widget.roomsTabIndex &&
        oldWidget.momentsTabIndex == widget.momentsTabIndex) {
      return;
    }
    _dragging = false;
    _dragVelocity = 0;
    if (_pendingSlot == _acceptedSlot) {
      unawaited(HapticFeedback.selectionClick());
    }
    _pendingSlot = null;
    _settle();
  }

  void _settle() {
    final target = (_acceptedSlot ?? 0).toDouble();
    if (_reduceMotion || _acceptedSlot == null) {
      _position.value = target;
      return;
    }
    _position.animateWith(
      SpringSimulation(
        _spring,
        _position.value,
        target,
        _position.velocity.clamp(-12.0, 12.0),
        tolerance: _springTolerance,
      ),
    );
  }

  /// The six-tab regime blend for this build. A width that crosses
  /// [YoFloatingNavigationDock.narrowBeadBelowWidth] springs the bead and
  /// inset to the new regime after this frame; the first layout, and any
  /// crossing under Reduce Motion, jumps straight there.
  double _regimeProgress(bool narrow) {
    final target = narrow ? 1.0 : 0.0;
    if (_narrowTarget != narrow) {
      final animate = _narrowTarget != null && !_reduceMotion;
      _narrowTarget = narrow;
      _regimeJump = !animate;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _narrowTarget != narrow) return;
        _regimeJump = false;
        if (animate && !_reduceMotion) {
          _regime.animateWith(
            SpringSimulation(
              _spring,
              _regime.value,
              target,
              _regime.velocity,
              tolerance: _springTolerance,
            ),
          );
        } else {
          _regime.stop();
          _regime.value = target;
        }
      });
    }
    return _regimeJump ? target : _regime.value.clamp(0.0, 1.0);
  }

  void _request(int slot, {bool reselect = true}) {
    if (slot == _acceptedSlot && !reselect) {
      _settle();
      return;
    }
    // Tapping the selected root still lets a hosted detail route pop to it.
    // Returning a drag to its original slot is deliberately paint-only.
    _pendingSlot = slot == _acceptedSlot ? null : slot;
    switch (_destinations[slot]) {
      case _DockDestination.home:
        widget.onDestinationSelected(0);
      case _DockDestination.servers:
        widget.onDestinationSelected(widget.roomsTabIndex);
      case _DockDestination.chats:
        widget.onDestinationSelected(1);
      case _DockDestination.content:
        widget.onDestinationSelected(widget.contentTabIndex!);
      case _DockDestination.moments:
        widget.onDestinationSelected(widget.momentsTabIndex);
      case _DockDestination.more:
        widget.onMorePressed();
    }
    // Denied or delayed navigation must not leave a preview selected.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dragging) return;
      _settle();
      _pendingSlot = null;
    });
  }

  void _cancelDrag() {
    if (!_dragging) return;
    setState(() {
      _dragging = false;
      _dragVelocity = 0;
    });
    _settle();
  }

  @override
  void dispose() {
    _position.dispose();
    _regime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _sixTabs
        ? AnimatedBuilder(
            animation: _regime,
            builder: (context, _) =>
                _buildForWidth(context, constraints.maxWidth),
          )
        : _buildForWidth(context, constraints.maxWidth),
  );

  String _labelFor(AppLocalizations copy, _DockDestination destination) =>
      switch (destination) {
        _DockDestination.home => copy.home,
        _DockDestination.servers => copy.navigationServers,
        _DockDestination.chats => copy.chats,
        _DockDestination.content => copy.navigationContent,
        _DockDestination.moments => copy.navigationYourMoments,
        _DockDestination.more => copy.more,
      };

  Widget _buildForWidth(BuildContext context, double availableWidth) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final metrics = _metrics;
    final slots = metrics.slots;
    final destinations = _destinations;
    final labels = [for (final d in destinations) _labelFor(copy, d)];
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    // Settled geometry decides the label mode, so a spring between regimes
    // never flips the dock between compact and expanded mid-flight.
    final double margin, settledInset, beadDiameter, insetNow;
    if (_sixTabs) {
      final settled = YoFloatingNavigationDock.sixTabRegimeFor(availableWidth);
      final narrow = availableWidth < YoFloatingNavigationDock.narrowBeadBelowWidth;
      final t = _regimeProgress(narrow);
      final wide = YoFloatingNavigationDock._sixTabWideRegime(availableWidth);
      final slim = YoFloatingNavigationDock._sixTabNarrowRegime(availableWidth);
      double blend(double a, double b) => a + (b - a) * t;
      margin = blend(wide.margin, slim.margin);
      insetNow = blend(wide.inset, slim.inset);
      beadDiameter = blend(wide.bead, slim.bead);
      settledInset = settled.inset;
    } else {
      margin = YoFloatingNavigationDock.horizontalMargin;
      // 48px touch targets and clearance between end sockets/corners.
      insetNow = settledInset = 48;
      beadDiameter = math.min(460.0, availableWidth - 28) < 332 ? 44 : 48;
    }
    final settledWidth = _sixTabs
        ? math.min(
            460.0,
            availableWidth -
                2 *
                    YoFloatingNavigationDock.sixTabRegimeFor(
                      availableWidth,
                    ).margin,
          )
        : math.min(460.0, availableWidth - 28);
    final labelWidth =
        math.max(48.0, (settledWidth - settledInset * 2) / (slots - 1)) +
        metrics.labelOverhang * 2;
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: metrics.labelSize,
      height: 1.1,
      fontWeight: FontWeight.w700,
    );
    bool exceedsCompactLabel(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 2,
      )..layout(maxWidth: labelWidth);
      final exceeds =
          painter.didExceedMaxLines ||
          painter.height > metrics.compactLabelMaxHeight;
      painter.dispose();
      return exceeds;
    }

    final expanded =
        textScale >= YoFloatingNavigationDock.expandedLabelScaleThreshold ||
        labels.any(exceedsCompactLabel);
    var expandedLabelHeight = 0.0;
    if (expanded) {
      // Long translations may wrap even in the full-width row. Reserve the
      // tallest label using the same inherited style as the actual Text so
      // changing tabs never clips copy or changes the dock's height.
      final expandedStyle = DefaultTextStyle.of(
        context,
      ).style.merge(_expandedLabelStyle);
      for (final label in labels) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: expandedStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(
            maxWidth: math.max(
              1,
              settledWidth - metrics.expandedLabelInset * 2,
            ),
          );
        expandedLabelHeight = math.max(
          expandedLabelHeight,
          painter.height.ceilToDouble(),
        );
        painter.dispose();
      }
    }
    final height = math.max(
      expanded
          ? math.max(
              metrics.expandedMinimumHeight,
              metrics.expandedLabelTop +
                  expandedLabelHeight +
                  metrics.expandedLabelBottom,
            )
          : 0.0,
      metrics.visualHeightFor(textScale),
    );
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      key: const ValueKey('yo-floating-navigation-semantics'),
      container: true,
      explicitChildNodes: true,
      child: SafeArea(
        key: const ValueKey('yo-floating-navigation-safe-area'),
        top: false,
        minimum: EdgeInsets.only(bottom: metrics.minimumBottomClearance),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: margin),
          child: Align(
            heightFactor: 1,
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: EdgeInsets.only(top: metrics.topClearance),
                child: SizedBox(
                  height: height,
                  child: RepaintBoundary(
                    child: FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: LayoutBuilder(
                        builder: (context, constraints) => _buildBar(
                          context,
                          width: constraints.maxWidth,
                          height: height,
                          inset: insetNow,
                          diameter: beadDiameter,
                          expanded: expanded,
                          rtl: rtl,
                          labels: labels,
                          palette: palette,
                        ),
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

  Widget _buildBar(
    BuildContext context, {
    required double width,
    required double height,
    required double inset,
    required double diameter,
    required bool expanded,
    required bool rtl,
    required List<String> labels,
    required AppPalette palette,
  }) {
    final metrics = _metrics;
    final last = _lastSlot.toDouble();
    final step = (width - inset * 2) / last;
    final tile = math.max(48.0, step);
    double centerFor(double slot) =>
        inset + (rtl ? last - slot : slot) * step;
    double slotFor(double x) {
      final physical = ((x - inset) / step).clamp(0.0, last);
      return rtl ? last - physical : physical;
    }

    return Listener(
      // A recognized drag can report dragEnd for a raw
      // PointerCancel. Clear preview before arena routing.
      onPointerCancel: (_) => _cancelDrag(),
      child: GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (details) {
          final center = Offset(
            centerFor(_position.value.clamp(0, last)),
            metrics.bodyTop,
          );
          if (_acceptedSlot == null ||
              (details.localPosition - center).distance > diameter / 2 + 12) {
            return;
          }
          _position.stop();
          setState(() {
            _dragging = true;
            _dragVelocity = 0;
          });
        },
        onHorizontalDragUpdate: (details) {
          if (!_dragging) return;
          _dragVelocity = details.primaryDelta ?? 0;
          _position.value = slotFor(details.localPosition.dx);
        },
        onHorizontalDragEnd: (_) {
          if (!_dragging) return;
          final target = _position.value.round().clamp(0, _lastSlot);
          setState(() {
            _dragging = false;
            _dragVelocity = 0;
          });
          _request(target, reselect: false);
        },
        onHorizontalDragCancel: _cancelDrag,
        child: AnimatedBuilder(
          animation: _position,
          builder: (context, _) {
            final position = _position.value.clamp(0.0, last);
            final beadX = centerFor(position);
            final shown = _dragging ? position.round() : _acceptedSlot;
            final velocity = _reduceMotion
                ? 0.0
                : (_dragging
                      ? _dragVelocity
                      : _position.velocity * (rtl ? -1 : 1));
            final color = _beadColor(position);
            // Anchor the caption under the destination it names. The band
            // stays full width — expandedLabelHeight reserves height against
            // that width — so a caption that fills it still centres, while a
            // short one slides to its own slot instead of naming whichever
            // destination sits in the middle.
            final captionX = shown == null
                ? 0.0
                : ((centerFor(shown.toDouble()) - width / 2) /
                          math.max(
                            1.0,
                            width / 2 - metrics.expandedLabelInset,
                          ))
                      .clamp(-1.0, 1.0);
            // With nothing selected the painter draws neither bead nor
            // socket, so the tiles have nothing to align to and large text
            // leaves them pinned under the top edge of a much taller bar.
            // Centre the resting icon row in the bar body in that state only.
            final destinationTop = expanded && _acceptedSlot == null
                ? ((metrics.bodyTop + height) / 2 - metrics.restingIconCenter)
                      .clamp(0.0, math.max(0.0, height - metrics.visualHeight))
                      .toDouble()
                : 0.0;
            final selectedInk = color.computeLuminance() > .179
                ? AppColors.contrastInk
                : AppColors.white;
            final unread = widget.unreadConversationCount;
            final badgeWidth =
                (unread > 99
                    ? 31
                    : unread > 9
                    ? 23
                    : 19) *
                metrics.badgeScale;
            final shadow = metrics.shadowScale;
            return Stack(
              key: const ValueKey('yo-floating-navigation-dock'),
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      key: const ValueKey('yo-meniscus-surface'),
                      painter: YoMeniscusPainter(
                        center: _acceptedSlot == null ? null : beadX,
                        radius: diameter / 2 + metrics.socketPad,
                        velocity: velocity,
                        palette: palette,
                        accent: color,
                        top: metrics.bodyTop,
                        corner: metrics.corner,
                        glow: metrics.glow,
                      ),
                    ),
                  ),
                ),
                if (_acceptedSlot != null)
                  Positioned(
                    left: beadX - diameter / 2,
                    top: metrics.bodyTop - diameter / 2,
                    width: diameter,
                    height: diameter,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: Container(
                          key: const ValueKey('yo-meniscus-bead'),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color.lerp(color, AppColors.white, .16)!,
                                color,
                              ],
                            ),
                            border: Border.all(
                              color: Color.lerp(color, AppColors.white, .45)!,
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: .25),
                                blurRadius: 16 * shadow,
                                spreadRadius: 1,
                              ),
                              BoxShadow(
                                color: palette.shadow.withValues(alpha: .24),
                                blurRadius: 6 * shadow,
                                offset: Offset(0, 3 * shadow),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                for (var slot = 0; slot < metrics.slots; slot++)
                  Positioned(
                    left: centerFor(slot.toDouble()) - tile / 2,
                    top: destinationTop,
                    width: tile,
                    height: metrics.visualHeight,
                    child: KeyedSubtree(
                      key: widget.tourDestinationKeys?[slot],
                      child: _MeniscusDestination(
                        slot: slot,
                        destination: _destinations[slot],
                        metrics: metrics,
                        label: labels[slot],
                        selected: _acceptedSlot == slot,
                        lift: _acceptedSlot == null
                            ? 0
                            : (1 - (position - slot).abs() / .62).clamp(
                                0.0,
                                1.0,
                              ),
                        labelVisible: !expanded && shown == slot,
                        selectedInk: selectedInk,
                        badgeEnd:
                            (tile - diameter) / 2 -
                            badgeWidth / 2 +
                            4 * metrics.badgeScale,
                        unread: _destinations[slot] == _DockDestination.chats
                            ? unread
                            : 0,
                        onPressed: () => _request(slot),
                      ),
                    ),
                  ),
                if (expanded && shown != null)
                  Positioned(
                    left: metrics.expandedLabelInset,
                    right: metrics.expandedLabelInset,
                    top: metrics.expandedLabelTop,
                    bottom: metrics.expandedLabelBottom,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: Align(
                          alignment: Alignment(captionX, 0),
                          child: Text(
                            labels[shown],
                            key: const ValueKey(
                              'yo-meniscus-accessible-label',
                            ),
                            textAlign: TextAlign.center,
                            style: _expandedLabelStyle.copyWith(
                              color: palette.interactiveForeground,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Color _beadColor(double position) {
    final colors = _sixTabs
        ? [
            AppColors.primary,
            AppColors.voice,
            AppColors.accent,
            // The fourth stop the six-tab dock gains for Treści (R1).
            Color.lerp(AppColors.accent, AppColors.secondary, .5)!,
            AppColors.secondary,
            AppColors.navigationPrimary,
          ]
        : const [
            AppColors.primary,
            AppColors.voice,
            AppColors.accent,
            AppColors.secondary,
            AppColors.navigationPrimary,
          ];
    final lower = position.floor();
    return Color.lerp(
      colors[lower],
      colors[math.min(colors.length - 1, lower + 1)],
      position - lower,
    )!;
  }
}

/// One continuous outline: circular bowl plus tangent shoulders. The moving
/// trailing shoulder is bounded before the endcaps, including narrow phones.
@visibleForTesting
class YoMeniscusPainter extends CustomPainter {
  const YoMeniscusPainter({
    required this.center,
    required this.radius,
    required this.velocity,
    required this.palette,
    required this.accent,
    this.top = YoFloatingNavigationDock.bodyTop,
    this.corner = 14,
    this.glow = 75,
  });
  final double? center;
  final double radius, velocity;
  final AppPalette palette;
  final Color accent;

  /// The bar body's top edge, its corner radius and the accent glow radius:
  /// 28 / 14 / 75 on the five-tab dock, ×0.9 on the six-tab dock.
  final double top, corner, glow;

  Path pathFor(Size size) {
    final path = Path()..moveTo(corner, top);
    final x = center;
    if (x != null) {
      final leftRoom = math.max(0.0, x - radius - corner - 1);
      final rightRoom = math.max(0.0, size.width - corner - x - radius - 1);
      final wake = velocity.clamp(-12.0, 12.0);
      final left = math.min(leftRoom, 8 + math.max(0, wake) * .8);
      final right = math.min(rightRoom, 8 + math.max(0, -wake) * .8);
      final dx = radius * .9063078, dy = radius * .4226183;
      path
        ..lineTo(x - radius - left, top)
        ..cubicTo(
          x - radius - left * .30,
          top,
          x - dx - dy * .23,
          top + dy - dx * .23,
          x - dx,
          top + dy,
        )
        ..arcTo(
          Rect.fromCircle(center: Offset(x, top), radius: radius),
          155 * math.pi / 180,
          -130 * math.pi / 180,
          false,
        )
        ..cubicTo(
          x + dx + dy * .23,
          top + dy - dx * .23,
          x + radius + right * .30,
          top,
          x + radius + right,
          top,
        );
    }
    return path
      ..lineTo(size.width - corner, top)
      ..quadraticBezierTo(size.width, top, size.width, top + corner)
      ..lineTo(size.width, size.height - corner)
      ..quadraticBezierTo(
        size.width,
        size.height,
        size.width - corner,
        size.height,
      )
      ..lineTo(corner, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - corner)
      ..lineTo(0, top + corner)
      ..quadraticBezierTo(0, top, corner, top)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = pathFor(size);
    canvas.drawShadow(path, palette.shadow.withValues(alpha: .35), 8, false);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.navigationSurface, palette.surfaceSunken],
        ).createShader(Offset.zero & size),
    );
    canvas.save();
    canvas.clipPath(path);
    if (center != null) {
      final point = Offset(center!, size.height);
      canvas.drawCircle(
        point,
        glow,
        Paint()
          ..shader = RadialGradient(
            colors: [
              accent.withValues(alpha: .10),
              accent.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: point, radius: glow)),
      );
    }
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.navigationOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(YoMeniscusPainter oldDelegate) =>
      oldDelegate.center != center ||
      oldDelegate.radius != radius ||
      oldDelegate.velocity != velocity ||
      oldDelegate.palette != palette ||
      oldDelegate.accent != accent ||
      oldDelegate.top != top ||
      oldDelegate.corner != corner ||
      oldDelegate.glow != glow;
}

class _MeniscusDestination extends StatefulWidget {
  const _MeniscusDestination({
    required this.slot,
    required this.destination,
    required this.metrics,
    required this.label,
    required this.selected,
    required this.lift,
    required this.labelVisible,
    required this.selectedInk,
    required this.badgeEnd,
    required this.unread,
    required this.onPressed,
  });
  final int slot, unread;
  final _DockDestination destination;
  final YoDockMetrics metrics;
  final String label;
  final bool selected, labelVisible;
  final double lift;
  final Color selectedInk;
  final double badgeEnd;
  final VoidCallback onPressed;
  @override
  State<_MeniscusDestination> createState() => _MeniscusDestinationState();
}

class _MeniscusDestinationState extends State<_MeniscusDestination> {
  bool _focused = false, _pressed = false;
  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final metrics = widget.metrics;
    final badgeScale = metrics.badgeScale;
    final color = Color.lerp(
      palette.navigationInactive,
      widget.selectedInk,
      widget.lift,
    )!;
    final label = widget.unread > 0
        ? AppLocalizations.of(
            context,
          ).navigationUnreadLabel(widget.label, widget.unread)
        : widget.label;
    final icon = switch (widget.destination) {
      _DockDestination.home => Icons.home_outlined,
      _DockDestination.servers => Icons.hub_outlined,
      _DockDestination.chats => Icons.chat_bubble_outline_rounded,
      // The outlined glyph in and out of the bead, as on the approved R1
      // render; no other destination swaps to a filled glyph either.
      _DockDestination.content => Icons.article_outlined,
      _DockDestination.moments || _DockDestination.more => Icons.tune_rounded,
    };
    final top = metrics.iconTop - metrics.lift * widget.lift;
    final slot = widget.slot;
    return FocusTraversalOrder(
      order: NumericFocusOrder(slot.toDouble()),
      child: Semantics(
        label: label,
        button: true,
        selected: widget.selected,
        sortKey: OrdinalSortKey(slot.toDouble()),
        excludeSemantics: true,
        onTap: widget.onPressed,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('yo-destination-$slot'),
            onTap: widget.onPressed,
            onFocusChange: (value) => setState(() => _focused = value),
            onHighlightChanged: (value) => setState(() => _pressed = value),
            borderRadius: BorderRadius.circular(metrics.tileRadius),
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStatePropertyAll(
              palette.focus.withValues(alpha: .05),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (_focused)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 1,
                          vertical: 2,
                        ),
                        child: DecoratedBox(
                          key: ValueKey('yo-destination-focus-$slot'),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              metrics.tileRadius,
                            ),
                            border: Border.all(color: palette.focus, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: top,
                  left: 0,
                  right: 0,
                  height: metrics.iconBox,
                  child: Center(
                    child: widget.destination == _DockDestination.moments
                        ? YoMomentsIcon(
                            state: _pressed
                                ? YoMomentsIconState.pressed
                                : widget.lift > .7
                                ? YoMomentsIconState.active
                                : YoMomentsIconState.inactive,
                            color: color,
                            size: metrics.momentsIconSize,
                          )
                        : Icon(icon, size: metrics.iconSize, color: color),
                  ),
                ),
                if (widget.labelVisible)
                  Positioned(
                    top: metrics.labelTop,
                    left: -metrics.labelOverhang,
                    right: -metrics.labelOverhang,
                    bottom: metrics.labelBottom,
                    child: Center(
                      child: Text(
                        widget.label,
                        key: ValueKey('yo-destination-label-$slot'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          color: palette.interactiveForeground,
                          fontSize: metrics.labelSize,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                if (widget.unread > 0)
                  PositionedDirectional(
                    top: top - 20 * badgeScale,
                    // Keep inactive unread badges inside their own slot;
                    // only the lifted icon uses the bead's outer corner.
                    end:
                        4 * badgeScale +
                        (widget.badgeEnd - 4 * badgeScale) * widget.lift,
                    child: Container(
                      key: const ValueKey('yo-chats-unread-badge'),
                      width:
                          (widget.unread > 99
                              ? 31
                              : widget.unread > 9
                              ? 23
                              : 19) *
                          badgeScale,
                      height: 19 * badgeScale,
                      constraints: BoxConstraints(
                        minWidth: 18 * badgeScale,
                        minHeight: 18 * badgeScale,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 4 * badgeScale,
                        vertical: badgeScale,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.live,
                        borderRadius: BorderRadius.circular(10 * badgeScale),
                        border: Border.all(
                          color: palette.navigationSurface,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        widget.unread > 99 ? '99+' : widget.unread.toString(),
                        textAlign: TextAlign.center,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          color: AppColors.onLive,
                          fontSize: 9 * badgeScale,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
