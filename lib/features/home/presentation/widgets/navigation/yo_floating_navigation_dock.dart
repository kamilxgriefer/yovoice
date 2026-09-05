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
    this.moreSelected = false,
    this.tourDestinationKeys,
    this.tourVoiceKey,
    super.key,
  });
  static const horizontalMargin = 14.0;
  static const topClearance = 4.0;
  static const minimumBottomClearance = 10.0;
  static const visualHeight = 92.0;
  static const accessibleVisualHeight = 154.0;
  static const expandedLabelScaleThreshold = 1.3;
  static const bodyTop = 28.0;
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
  static const _expandedLabelStyle = TextStyle(
    fontSize: 12,
    height: 1.15,
    fontWeight: FontWeight.w700,
  );
  static const _expandedLabelTop = 88.0;
  static const _expandedLabelBottom = 6.0;
  static const _expandedLabelInset = 16.0;
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 230,
    damping: 25,
  );
  late final AnimationController _position;
  bool _reduceMotion = false, _dragging = false;
  double _dragVelocity = 0;
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
      _dragVelocity = 0;
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
        tolerance: const Tolerance(distance: .0005, velocity: .005),
      ),
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
    setState(() {
      _dragging = false;
      _dragVelocity = 0;
    });
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
      copy.navigationRooms,
      copy.chats,
      copy.navigationYourMoments,
      copy.more,
    ];
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final width = math.min(460.0, availableWidth - 28);
    final labelWidth = math.max(48.0, (width - 96) / 4) + 16;
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: 10,
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
      final exceeds = painter.didExceedMaxLines || painter.height > 26;
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
          ? math.max(
              116.0,
              _expandedLabelTop + expandedLabelHeight + _expandedLabelBottom,
            )
          : 0.0,
      YoFloatingNavigationDock.visualHeightFor(textScale: textScale),
    );
    final rtl = Directionality.of(context) == TextDirection.rtl;
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
              child: Padding(
                padding: const EdgeInsets.only(
                  top: YoFloatingNavigationDock.topClearance,
                ),
                child: SizedBox(
                  height: height,
                  child: RepaintBoundary(
                    child: FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          // 48px touch targets and clearance between end sockets/corners.
                          const inset = 48.0;
                          final step = (width - inset * 2) / 4;
                          final diameter = width < 332 ? 44.0 : 48.0;
                          double centerFor(double slot) =>
                              inset + (rtl ? 4 - slot : slot) * step;
                          double slotFor(double x) {
                            final physical = ((x - inset) / step).clamp(
                              0.0,
                              4.0,
                            );
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
                                final center = Offset(
                                  centerFor(_position.value.clamp(0, 4)),
                                  YoFloatingNavigationDock.bodyTop,
                                );
                                if (_acceptedSlot == null ||
                                    (details.localPosition - center).distance >
                                        diameter / 2 + 12) {
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
                                _position.value = slotFor(
                                  details.localPosition.dx,
                                );
                              },
                              onHorizontalDragEnd: (_) {
                                if (!_dragging) return;
                                final target = _position.value.round().clamp(
                                  0,
                                  4,
                                );
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
                                  final position = _position.value.clamp(
                                    0.0,
                                    4.0,
                                  );
                                  final beadX = centerFor(position);
                                  final shown = _dragging
                                      ? position.round()
                                      : _acceptedSlot;
                                  final velocity = _reduceMotion
                                      ? 0.0
                                      : (_dragging
                                            ? _dragVelocity
                                            : _position.velocity *
                                                  (rtl ? -1 : 1));
                                  final color = _beadColor(position);
                                  final selectedInk =
                                      color.computeLuminance() > .179
                                      ? AppColors.contrastInk
                                      : AppColors.white;
                                  return Stack(
                                    key: const ValueKey(
                                      'yo-floating-navigation-dock',
                                    ),
                                    clipBehavior: Clip.none,
                                    children: [
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: CustomPaint(
                                            key: const ValueKey(
                                              'yo-meniscus-surface',
                                            ),
                                            painter: YoMeniscusPainter(
                                              center: _acceptedSlot == null
                                                  ? null
                                                  : beadX,
                                              radius: diameter / 2 + 4,
                                              velocity: velocity,
                                              palette: palette,
                                              accent: color,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_acceptedSlot != null)
                                        Positioned(
                                          left: beadX - diameter / 2,
                                          top:
                                              YoFloatingNavigationDock.bodyTop -
                                              diameter / 2,
                                          width: diameter,
                                          height: diameter,
                                          child: IgnorePointer(
                                            child: ExcludeSemantics(
                                              child: Container(
                                                key: const ValueKey(
                                                  'yo-meniscus-bead',
                                                ),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: [
                                                      Color.lerp(
                                                        color,
                                                        AppColors.white,
                                                        .16,
                                                      )!,
                                                      color,
                                                    ],
                                                  ),
                                                  border: Border.all(
                                                    color: Color.lerp(
                                                      color,
                                                      AppColors.white,
                                                      .45,
                                                    )!,
                                                    width: 1.2,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: color.withValues(
                                                        alpha: .25,
                                                      ),
                                                      blurRadius: 16,
                                                      spreadRadius: 1,
                                                    ),
                                                    BoxShadow(
                                                      color: palette.shadow
                                                          .withValues(
                                                            alpha: .24,
                                                          ),
                                                      blurRadius: 6,
                                                      offset: const Offset(
                                                        0,
                                                        3,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      for (var slot = 0; slot < 5; slot++)
                                        Positioned(
                                          left:
                                              centerFor(slot.toDouble()) -
                                              math.max(48, step) / 2,
                                          top: 0,
                                          width: math.max(48, step),
                                          height: 92,
                                          child: KeyedSubtree(
                                            key: widget
                                                .tourDestinationKeys?[slot],
                                            child: _MeniscusDestination(
                                              slot: slot,
                                              label: labels[slot],
                                              selected: _acceptedSlot == slot,
                                              lift: _acceptedSlot == null
                                                  ? 0
                                                  : (1 -
                                                            (position - slot)
                                                                    .abs() /
                                                                .62)
                                                        .clamp(0.0, 1.0),
                                              labelVisible:
                                                  !expanded && shown == slot,
                                              selectedInk: selectedInk,
                                              badgeEnd:
                                                  (math.max(48, step) -
                                                          diameter) /
                                                      2 -
                                                  (widget.unreadConversationCount >
                                                              99
                                                          ? 31
                                                          : widget.unreadConversationCount >
                                                                9
                                                          ? 23
                                                          : 19) /
                                                      2 +
                                                  4,
                                              unread: slot == 2
                                                  ? widget
                                                        .unreadConversationCount
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
                                                  style: _expandedLabelStyle
                                                      .copyWith(
                                                        color: palette
                                                            .interactiveForeground,
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
          ),
        ),
      ),
    );
  }

  Color _beadColor(double position) {
    const colors = [
      AppColors.primary,
      AppColors.voice,
      AppColors.accent,
      AppColors.secondary,
      AppColors.navigationPrimary,
    ];
    final lower = position.floor();
    return Color.lerp(
      colors[lower],
      colors[math.min(4, lower + 1)],
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
  });
  final double? center;
  final double radius, velocity;
  final AppPalette palette;
  final Color accent;
  Path pathFor(Size size) {
    const top = YoFloatingNavigationDock.bodyTop, corner = 14.0;
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
        75,
        Paint()
          ..shader = RadialGradient(
            colors: [
              accent.withValues(alpha: .10),
              accent.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: point, radius: 75)),
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
      oldDelegate.accent != accent;
}

class _MeniscusDestination extends StatefulWidget {
  const _MeniscusDestination({
    required this.slot,
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
    final icon = switch (widget.slot) {
      0 => Icons.home_outlined,
      1 => Icons.groups_2_outlined,
      2 => Icons.chat_bubble_outline_rounded,
      _ => Icons.tune_rounded,
    };
    final top = 51 - 35 * widget.lift;
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
            borderRadius: BorderRadius.circular(14),
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
                            borderRadius: BorderRadius.circular(14),
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
                  height: 24,
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
                        : Icon(icon, size: 23, color: color),
                  ),
                ),
                if (widget.labelVisible)
                  Positioned(
                    top: 64,
                    left: -8,
                    right: -8,
                    bottom: 2,
                    child: Center(
                      child: Text(
                        widget.label,
                        key: ValueKey('yo-destination-label-$slot'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          color: palette.interactiveForeground,
                          fontSize: 10,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                if (widget.unread > 0)
                  PositionedDirectional(
                    top: top - 20,
                    // Keep inactive unread badges inside their own slot;
                    // only the lifted icon uses the bead's outer corner.
                    end: 4 + (widget.badgeEnd - 4) * widget.lift,
                    child: Container(
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
                        widget.unread > 99 ? '99+' : widget.unread.toString(),
                        textAlign: TextAlign.center,
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          color: AppColors.onLive,
                          fontSize: 9,
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
