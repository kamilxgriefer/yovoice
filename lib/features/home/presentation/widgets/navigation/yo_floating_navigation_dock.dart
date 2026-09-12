import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/shared/widgets/navigation/yo_moments_icon.dart';

/// The mobile bottom bar: a flat navigation surface, five equal cells and one
/// rounded violet wash that slides to the accepted destination. Drag previews
/// paint only; release requests one destination and the shell remains
/// authoritative.
///
/// Slots are stable identities, not screen indices: 0 Home, 1 Servers
/// ([roomsTabIndex]), 2 Chats, 3 Moments ([momentsTabIndex]), 4 More.
class YoFloatingNavigationDock extends StatefulWidget {
  const YoFloatingNavigationDock({
    required this.selectedTabIndex,
    required this.momentsTabIndex,
    required this.unreadConversationCount,
    required this.onDestinationSelected,
    required this.onVoicePressed,
    required this.onMorePressed,
    this.roomsTabIndex = 3,
    this.moreSelected = false,
    this.tourDestinationKeys,
    this.tourVoiceKey,
    super.key,
  });

  /// The bar is full-bleed: no floating side margin and no top clearance.
  /// Both constants stay so every host reserves space through one formula.
  static const horizontalMargin = 0.0;
  static const topClearance = 0.0;
  static const minimumBottomClearance = 10.0;
  static const visualHeight = 64.0;
  static const accessibleVisualHeight = 154.0;
  static const expandedLabelScaleThreshold = 1.3;

  /// Vertical centre of the 24 px icon row inside [visualHeight].
  static const bodyTop = 24.0;

  /// The active wash: at most 64 wide (a full cell on a 320 px phone), 56
  /// tall, `AppRadius.md`, `navigationPrimary @ .14`.
  static const activeIndicatorWidth = 64.0;
  static const activeIndicatorHeight = 56.0;
  final int selectedTabIndex,
      momentsTabIndex,
      roomsTabIndex,
      unreadConversationCount;
  final ValueChanged<int> onDestinationSelected;

  /// Source compatibility for hosted routes; creation now lives on Home/Rooms.
  final VoidCallback onVoicePressed;
  final VoidCallback onMorePressed;
  final bool moreSelected;
  final Map<int, GlobalKey>? tourDestinationKeys;
  final GlobalKey? tourVoiceKey;
  static BorderSide outlineSideFor(AppPalette palette) =>
      BorderSide(color: palette.navigationOutline, width: 1);
  static double visualHeightFor({required double textScale}) =>
      textScale >= expandedLabelScaleThreshold
      ? accessibleVisualHeight + math.max(0, textScale - 2) * 26
      : visualHeight;
  static double reservedHeightFor({
    required double safeBottom,
    double textScale = 1,
  }) =>
      topClearance +
      visualHeightFor(textScale: textScale) +
      math.max(safeBottom, minimumBottomClearance);
  static int? visualSlotForTab(
    int tab, {
    required int momentsTabIndex,
    int roomsTabIndex = 3,
  }) {
    if (tab == 0) return 0;
    if (tab == roomsTabIndex) return 1;
    if (tab == 1) return 2;
    if (tab == momentsTabIndex) return 3;
    return null;
  }

  @override
  State<YoFloatingNavigationDock> createState() =>
      _YoFloatingNavigationDockState();
}

class _YoFloatingNavigationDockState extends State<YoFloatingNavigationDock>
    with SingleTickerProviderStateMixin {
  static const _labelStyle = TextStyle(
    fontSize: 11,
    height: 1.1,
    fontWeight: FontWeight.w700,
  );
  static const _expandedLabelStyle = TextStyle(
    fontSize: 12,
    height: 1.15,
    fontWeight: FontWeight.w700,
  );

  /// A cell label may take two lines at ordinary text sizes; anything taller
  /// switches the bar to the full-width label row below the icons.
  static const _compactLabelMaxHeight = 26.0;
  static const _labelInset = 4.0;
  static const _expandedLabelTop = YoFloatingNavigationDock.visualHeight;
  static const _expandedLabelBottom = 6.0;
  static const _expandedLabelInset = 16.0;
  late final AnimationController _position;
  bool _reduceMotion = false, _dragging = false;
  int? _pendingSlot;
  int? get _acceptedSlot => widget.moreSelected
      ? 4
      : YoFloatingNavigationDock.visualSlotForTab(
          widget.selectedTabIndex,
          momentsTabIndex: widget.momentsTabIndex,
          roomsTabIndex: widget.roomsTabIndex,
        );
  @override
  void initState() {
    super.initState();
    _position = AnimationController.unbounded(
      vsync: this,
      value: (_acceptedSlot ?? 0).toDouble(),
    );
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
      _position.value = (_acceptedSlot ?? 0).toDouble();
    }
  }

  @override
  void didUpdateWidget(YoFloatingNavigationDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTabIndex == widget.selectedTabIndex &&
        oldWidget.moreSelected == widget.moreSelected &&
        oldWidget.roomsTabIndex == widget.roomsTabIndex &&
        oldWidget.momentsTabIndex == widget.momentsTabIndex) {
      return;
    }
    _dragging = false;
    if (_pendingSlot == _acceptedSlot) {
      unawaited(HapticFeedback.selectionClick());
    }
    _pendingSlot = null;
    _settle();
  }

  /// Slides the active wash to the accepted slot from wherever it is now, so
  /// a reversal mid-travel retargets instead of teleporting. Reduce Motion
  /// settles immediately.
  void _settle() {
    final target = (_acceptedSlot ?? 0).toDouble();
    if (_reduceMotion || _acceptedSlot == null) {
      _position.value = target;
      return;
    }
    _position.animateTo(
      target,
      duration: AppMotion.standard,
      curve: AppMotion.standardCurve,
    );
  }

  void _request(int slot, {bool reselect = true}) {
    if (slot == _acceptedSlot && !reselect) {
      _settle();
      return;
    }
    // Tapping the selected root still lets a hosted detail route pop to it.
    // Returning a drag to its original slot is deliberately paint-only.
    _pendingSlot = slot == _acceptedSlot ? null : slot;
    switch (slot) {
      case 0:
        widget.onDestinationSelected(0);
      case 1:
        widget.onDestinationSelected(widget.roomsTabIndex);
      case 2:
        widget.onDestinationSelected(1);
      case 3:
        widget.onDestinationSelected(widget.momentsTabIndex);
      case 4:
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
    setState(() => _dragging = false);
    _settle();
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _buildForWidth(context, constraints.maxWidth),
  );

  Widget _buildForWidth(BuildContext context, double availableWidth) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final labels = [
      copy.home,
      copy.navigationServers,
      copy.chats,
      copy.navigationYourMoments,
      copy.more,
    ];
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final safe = MediaQuery.paddingOf(context);
    final width = math.max(
      1.0,
      (availableWidth.isFinite ? availableWidth : 390.0) -
          safe.left -
          safe.right,
    );
    final labelWidth = math.max(1.0, width / 5 - _labelInset * 2);
    final style = Theme.of(context).textTheme.bodyMedium!.merge(_labelStyle);
    bool exceedsCompactLabel(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 2,
      )..layout(maxWidth: labelWidth);
      final exceeds =
          painter.didExceedMaxLines || painter.height > _compactLabelMaxHeight;
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
        )..layout(maxWidth: math.max(1, width - _expandedLabelInset * 2));
        expandedLabelHeight = math.max(
          expandedLabelHeight,
          painter.height.ceilToDouble(),
        );
        painter.dispose();
      }
    }
    final height = math.max(
      expanded
          ? _expandedLabelTop + expandedLabelHeight + _expandedLabelBottom
          : 0.0,
      YoFloatingNavigationDock.visualHeightFor(textScale: textScale),
    );
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      key: const ValueKey('yo-floating-navigation-semantics'),
      container: true,
      explicitChildNodes: true,
      // The surface paints down to the screen edge, under the safe inset, so
      // the bar and the home-indicator strip read as one flat plane.
      child: DecoratedBox(
        key: const ValueKey('yo-dock-surface'),
        decoration: BoxDecoration(
          color: palette.navigationSurface,
          border: Border(top: YoFloatingNavigationDock.outlineSideFor(palette)),
        ),
        child: SafeArea(
          key: const ValueKey('yo-floating-navigation-safe-area'),
          top: false,
          minimum: const EdgeInsets.only(
            bottom: YoFloatingNavigationDock.minimumBottomClearance,
          ),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: RepaintBoundary(
              child: FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    // Five equal cells; every cell is a ≥ 48 px target.
                    final cellWidth = width / 5;
                    final indicatorWidth = math.min(
                      YoFloatingNavigationDock.activeIndicatorWidth,
                      cellWidth,
                    );
                    double centerFor(double slot) =>
                        ((rtl ? 4 - slot : slot) + .5) * cellWidth;
                    double slotFor(double x) {
                      final physical = (x / cellWidth - .5).clamp(0.0, 4.0);
                      return rtl ? 4 - physical : physical;
                    }

                    return Listener(
                      // A recognized drag can report dragEnd for a raw
                      // PointerCancel. Clear preview before arena routing.
                      onPointerCancel: (_) => _cancelDrag(),
                      child: GestureDetector(
                        dragStartBehavior: DragStartBehavior.down,
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragStart: (details) {
                          if (_acceptedSlot == null) return;
                          final center = centerFor(_position.value.clamp(0, 4));
                          if ((details.localPosition.dx - center).abs() >
                              indicatorWidth / 2 + 12) {
                            return;
                          }
                          _position.stop();
                          setState(() => _dragging = true);
                        },
                        onHorizontalDragUpdate: (details) {
                          if (!_dragging) return;
                          _position.value = slotFor(details.localPosition.dx);
                        },
                        onHorizontalDragEnd: (_) {
                          if (!_dragging) return;
                          final target = _position.value.round().clamp(0, 4);
                          setState(() => _dragging = false);
                          _request(target, reselect: false);
                        },
                        onHorizontalDragCancel: _cancelDrag,
                        child: AnimatedBuilder(
                          animation: _position,
                          builder: (context, _) {
                            final position = _position.value.clamp(0.0, 4.0);
                            final shown = _dragging
                                ? position.round()
                                : _acceptedSlot;
                            return Stack(
                              key: const ValueKey(
                                'yo-floating-navigation-dock',
                              ),
                              clipBehavior: Clip.none,
                              children: [
                                if (_acceptedSlot != null)
                                  Positioned(
                                    left:
                                        centerFor(position) -
                                        indicatorWidth / 2,
                                    top:
                                        (YoFloatingNavigationDock.visualHeight -
                                            YoFloatingNavigationDock
                                                .activeIndicatorHeight) /
                                        2,
                                    width: indicatorWidth,
                                    height: YoFloatingNavigationDock
                                        .activeIndicatorHeight,
                                    child: IgnorePointer(
                                      child: ExcludeSemantics(
                                        child: DecoratedBox(
                                          key: const ValueKey(
                                            'yo-dock-active-indicator',
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.navigationPrimary
                                                .withValues(alpha: .14),
                                            borderRadius: AppRadius.md,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                for (var slot = 0; slot < 5; slot++)
                                  Positioned(
                                    left:
                                        centerFor(slot.toDouble()) -
                                        cellWidth / 2,
                                    top: 0,
                                    width: cellWidth,
                                    height:
                                        YoFloatingNavigationDock.visualHeight,
                                    child: KeyedSubtree(
                                      key: widget.tourDestinationKeys?[slot],
                                      child: _DockDestination(
                                        slot: slot,
                                        label: labels[slot],
                                        labelStyle: style,
                                        selected: _acceptedSlot == slot,
                                        lift: _acceptedSlot == null
                                            ? 0
                                            : (1 -
                                                      (position - slot).abs() /
                                                          .62)
                                                  .clamp(0.0, 1.0),
                                        labelVisible: !expanded,
                                        unread: slot == 2
                                            ? widget.unreadConversationCount
                                            : 0,
                                        onPressed: () => _request(slot),
                                      ),
                                    ),
                                  ),
                                if (expanded && shown != null)
                                  Positioned(
                                    left: _expandedLabelInset,
                                    right: _expandedLabelInset,
                                    top: _expandedLabelTop,
                                    bottom: _expandedLabelBottom,
                                    child: IgnorePointer(
                                      child: ExcludeSemantics(
                                        child: Center(
                                          child: Text(
                                            labels[shown],
                                            key: const ValueKey(
                                              'yo-meniscus-accessible-label',
                                            ),
                                            textAlign: TextAlign.center,
                                            style: _expandedLabelStyle.copyWith(
                                              color:
                                                  palette.interactiveForeground,
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
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One cell: a 24 px glyph over an 11 px label, both fading between the
/// resting `navigationInactive` and the active `interactiveForeground` as the
/// wash approaches. The Chats unread badge sits beside the glyph — touching,
/// never covering it — so it stays inside its own cell at 320 px.
class _DockDestination extends StatefulWidget {
  const _DockDestination({
    required this.slot,
    required this.label,
    required this.labelStyle,
    required this.selected,
    required this.lift,
    required this.labelVisible,
    required this.unread,
    required this.onPressed,
  });
  final int slot, unread;
  final String label;
  final TextStyle labelStyle;
  final bool selected, labelVisible;
  final double lift;
  final VoidCallback onPressed;
  @override
  State<_DockDestination> createState() => _DockDestinationState();
}

class _DockDestinationState extends State<_DockDestination> {
  bool _focused = false, _pressed = false;
  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final color = Color.lerp(
      palette.navigationInactive,
      palette.interactiveForeground,
      widget.lift,
    )!;
    final label = widget.unread > 0
        ? AppLocalizations.of(
            context,
          ).navigationUnreadLabel(widget.label, widget.unread)
        : widget.label;
    final icon = switch (widget.slot) {
      0 => Icons.home_outlined,
      1 => Icons.hub_outlined,
      2 => Icons.chat_bubble_outline_rounded,
      _ => Icons.tune_rounded,
    };
    final slot = widget.slot;
    final glyph = SizedBox.square(
      dimension: 24,
      child: Center(
        child: slot == 3
            ? YoMomentsIcon(
                state: _pressed
                    ? YoMomentsIconState.pressed
                    : widget.lift > .7
                    ? YoMomentsIconState.active
                    : YoMomentsIconState.inactive,
                color: color,
                size: 24,
              )
            : Icon(icon, size: 24, color: color),
      ),
    );
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
            borderRadius: AppRadius.md,
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStatePropertyAll(
              palette.focus.withValues(alpha: .05),
            ),
            child: Stack(
              fit: StackFit.expand,
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
                            borderRadius: AppRadius.md,
                            border: Border.all(color: palette.focus, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          glyph,
                          if (widget.unread > 0) ...[
                            const SizedBox(width: 2),
                            Container(
                              key: const ValueKey('yo-chats-unread-badge'),
                              width: widget.unread > 99
                                  ? 31
                                  : widget.unread > 9
                                  ? 23
                                  : 19,
                              height: 19,
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.live,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: palette.navigationSurface,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                widget.unread > 99
                                    ? '99+'
                                    : widget.unread.toString(),
                                textAlign: TextAlign.center,
                                textScaler: TextScaler.noScaling,
                                style: const TextStyle(
                                  color: AppColors.onLive,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (widget.labelVisible) ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal:
                                _YoFloatingNavigationDockState._labelInset,
                          ),
                          child: Text(
                            widget.label,
                            key: ValueKey('yo-destination-label-$slot'),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: widget.labelStyle.copyWith(color: color),
                          ),
                        ),
                      ],
                    ],
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
