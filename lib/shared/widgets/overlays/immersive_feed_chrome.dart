import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart';

/// A glyph-local outline for words that sit directly on unknown footage.
///
/// The crisp offsets make the immediately adjacent colour dark on bright
/// frames, while the shared soft shadows separate the same glyphs from dark
/// or detailed frames. This preserves a transparent header without relying on
/// a full-width contrast scrim.
const List<Shadow> _immersiveChromeTextShadows = <Shadow>[
  Shadow(color: Color(0xE6000000), offset: Offset(-1.5, 0)),
  Shadow(color: Color(0xE6000000), offset: Offset(1.5, 0)),
  Shadow(color: Color(0xE6000000), offset: Offset(0, -1.5)),
  Shadow(color: Color(0xE6000000), offset: Offset(0, 1.5)),
  Shadow(color: Color(0xD9000000), offset: Offset(-1, -1)),
  Shadow(color: Color(0xD9000000), offset: Offset(1, -1)),
  Shadow(color: Color(0xD9000000), offset: Offset(-1, 1)),
  Shadow(color: Color(0xD9000000), offset: Offset(1, 1)),
  ...overlayTextShadows,
];

/// The same glyph treatment, for a word a host sets in the chrome's row in
/// place of the format switch (the Yeels "Twoje Yeels" title), so it reads
/// exactly like the format labels it stands in for.
const List<Shadow> immersiveChromeTextShadows = _immersiveChromeTextShadows;

/// The row-1 pieces an immersive feed's HOST owns.
///
/// A feed screen knows about its own pool, never about what formats exist
/// beside it, so the format switch and the create action are handed in rather
/// than invented here. Passing them as named slots instead of one opaque
/// widget is what lets the chrome place them on its own two-shape row.
@immutable
class ImmersiveFeedHeaderSlots {
  const ImmersiveFeedHeaderSlots({
    this.formatSwitch,
    this.leading,
    this.trailing,
  });

  final Widget? formatSwitch;
  final Widget? leading;
  final Widget? trailing;
}

/// One choice inside an [ImmersiveSegmentedSwitch] or an [ImmersiveFilterRow].
@immutable
class ImmersiveChromeOption {
  const ImmersiveChromeOption({
    required this.label,
    this.key,
    this.semanticLabel,
  });

  final String label;
  final Key? key;

  /// Read to assistive technology instead of [label] when the visible word is
  /// too short to stand alone.
  final String? semanticLabel;
}

/// The two levels of chrome above an immersive feed stage.
///
/// Level 1 names the CONTENT FORMAT and level 2 names the POOL inside that
/// format. They previously shared one visual language -- white text on one
/// gradient, distinguished by weight plus a text underline, four pixels apart
/// -- which read as a single indistinct block of words.
///
/// They are now separated by three independent differentiators, so the eye
/// cannot parse them as one row even at an accessibility text size:
///
/// | | level 1 | level 2 |
/// | shape | large text + short gradient line | 36 px chips in 48 targets |
/// | selected | strongest ink + line + weight | ink-inverted chip + weight |
/// | type | 17 px, w800 selected | 13 px, w700 selected |
///
/// No [TextDecoration] appears anywhere in this chrome. Selection is carried
/// by a separate line or an inverted fill, weight AND by the `selected`
/// semantic flag, never by colour alone. (Refine-look §8.4 / R8: the line is
/// the logo's gradient with a brand glow; the chips invert — `textPrimary`
/// fill with canvas ink on the page, a white fill with the immersive canvas
/// as ink over media.)
///
/// The chrome is deliberately theme-invariant: it sits directly over media,
/// not over a separate header surface, so Dark and Pearl are identical here.
/// The text shadows and the small action plates carry local contrast without
/// turning the top of every Yeel into an opaque black block.
class ImmersiveFeedChrome extends StatelessWidget {
  const ImmersiveFeedChrome({
    required this.gutter,
    this.filters = const <ImmersiveChromeOption>[],
    this.selectedFilterIndex = 0,
    this.onFilterSelected,
    this.filterBar,
    this.filterGroupLabel,
    this.formatSwitch,
    this.leading,
    this.trailing,
    this.filterTrailing,
    this.onCanvas = false,
    super.key,
  });

  /// Level 1. Supplied by the host that owns the format, so this widget never
  /// has to know what a format is.
  final Widget? formatSwitch;

  /// True when the chrome sits on the page CANVAS rather than over media
  /// (the Voice feed): level 2 then draws the theme-aware canvas chips. The
  /// host hands a matching canvas [formatSwitch] and plates. Default false
  /// keeps the over-media look unchanged.
  final bool onCanvas;

  /// Horizontal gutter, shared with the stage below.
  final double gutter;

  /// Level 2: the chip row. Empty (the default) with no [filterBar] means
  /// the surface has no level 2 at all, and the chrome is one row tall.
  final List<ImmersiveChromeOption> filters;
  final int selectedFilterIndex;
  final ValueChanged<int>? onFilterSelected;

  /// Level 2 drawn by the host instead of the chip row (the Voice feed's
  /// text tabs). When set, [filters] is ignored.
  final Widget? filterBar;

  /// Names level 2 to assistive technology, so the two levels are
  /// distinguishable without sight.
  final String? filterGroupLabel;

  /// Leading plate on row 1 -- Back, when this surface was pushed as a route.
  final Widget? leading;

  /// Trailing plate on row 1 -- the create action.
  final Widget? trailing;

  /// Trailing plate on row 2 -- refresh. It keeps its own key and focus node
  /// because it is also the focus-recovery target after an expiry removal.
  final Widget? filterTrailing;

  @override
  Widget build(BuildContext context) {
    // The chrome itself paints no backdrop. Each foreground atom owns its
    // contrast treatment, and a host that needs more lays it UNDER its own
    // controls: the Yeels phone overlay fades the top of the media inside the
    // Yeel's media layer (Y3), so no control of the Yeel is ever dimmed. A
    // full-width fill painted here is what produced the reported black
    // rectangle over the footage.
    return Padding(
      // No safe-area inset is added here: every host that mounts this chrome
      // already sits inside a SafeArea, so reserving the notch again would
      // push the first row down by the status bar a second time.
      //
      // Row 1 is one 48 px row (it stacks into two only when the format
      // switch cannot keep its width beside the plates); level 2, when a
      // host has one, adds a second. Hosts measure the result rather than
      // assuming a height: the Yeels stage derives its shallow-frame
      // geometry (horizontal action row vs rail) from the media height the
      // measured chrome leaves under it.
      padding: EdgeInsetsDirectional.fromSTEB(
        gutter,
        AppRhythm.hairline,
        gutter,
        10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _FormatRow(
            formatSwitch: formatSwitch,
            leading: leading,
            trailing: trailing,
          ),
          if (filterBar != null || filters.isNotEmpty) ...<Widget>[
            // The one gap that makes two levels read as two levels.
            const SizedBox(height: AppRhythm.tight),
            Row(
              children: <Widget>[
                Expanded(
                  child:
                      filterBar ??
                      ImmersiveFilterRow(
                        options: filters,
                        selectedIndex: selectedFilterIndex,
                        onSelected: onFilterSelected ?? (_) {},
                        groupLabel: filterGroupLabel,
                        onCanvas: onCanvas,
                      ),
                ),
                ?filterTrailing,
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Row 1: the plates keep their places and the switch sits between them.
///
/// At ordinary sizes all three slots share one compact row. When the switch
/// cannot keep its natural width between the plates — large text, or a narrow
/// phone whose row also carries Back and more than one action — the edge
/// actions get their own row and the format labels the full width below.
/// That costs one short line of overlay height, but it preserves the reader's
/// requested text size and keeps both choices complete, never "Ye…".
///
/// The switch is always BOUNDED. A horizontal scroll view here once handed it
/// unbounded width, so at 200 % text on a 320 px phone exactly one of the two
/// formats was ever visible; a two-item format switch must show both items.
class _FormatRow extends StatelessWidget {
  const _FormatRow({
    required this.formatSwitch,
    required this.leading,
    required this.trailing,
  });

  final Widget? formatSwitch;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _AdaptiveFormatRow(
      leading: leading,
      center: formatSwitch,
      trailing: trailing,
      // Accessibility sizes always stack: there the segments drop their side
      // padding and may wrap, so their width is not a single-line measure.
      forceStacked: MediaQuery.textScalerOf(context).scale(1) >= 1.6,
      textDirection: Directionality.of(context),
    );
  }
}

enum _FormatSlot { leading, center, trailing }

class _AdaptiveFormatRow
    extends SlottedMultiChildRenderObjectWidget<_FormatSlot, RenderBox> {
  const _AdaptiveFormatRow({
    required this.leading,
    required this.center,
    required this.trailing,
    required this.forceStacked,
    required this.textDirection,
  });

  final Widget? leading;
  final Widget? center;
  final Widget? trailing;
  final bool forceStacked;
  final TextDirection textDirection;

  @override
  Iterable<_FormatSlot> get slots => _FormatSlot.values;

  @override
  Widget? childForSlot(_FormatSlot slot) => switch (slot) {
    _FormatSlot.leading => leading,
    _FormatSlot.center => center,
    _FormatSlot.trailing => trailing,
  };

  @override
  _RenderAdaptiveFormatRow createRenderObject(BuildContext context) =>
      _RenderAdaptiveFormatRow(
        forceStacked: forceStacked,
        textDirection: textDirection,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAdaptiveFormatRow renderObject,
  ) {
    renderObject
      ..forceStacked = forceStacked
      ..textDirection = textDirection;
  }
}

/// Lays row 1 out as the old `Row` / `Column` pair did — leading, an 8 px
/// gap, the switch start-aligned in the room that is left, trailing at the
/// end, all vertically centred; or, stacked, the plates on one line and the
/// switch start-aligned 4 px under them — and picks between the two by
/// MEASURING the switch against the room it would get (keeping 8 px clear of
/// the trailing actions, so a word never touches a plate), instead of by the
/// text scale alone.
class _RenderAdaptiveFormatRow extends RenderBox
    with SlottedContainerRenderObjectMixin<_FormatSlot, RenderBox> {
  _RenderAdaptiveFormatRow({
    required bool forceStacked,
    required TextDirection textDirection,
  }) : _forceStacked = forceStacked,
       _textDirection = textDirection;

  static const double _leadingGap = AppRhythm.tight;
  static const double _trailingGap = AppRhythm.tight;
  static const double _runGap = AppRhythm.hairline;

  bool get forceStacked => _forceStacked;
  bool _forceStacked;
  set forceStacked(bool value) {
    if (value == _forceStacked) return;
    _forceStacked = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  RenderBox? get _leading => childForSlot(_FormatSlot.leading);
  RenderBox? get _center => childForSlot(_FormatSlot.center);
  RenderBox? get _trailing => childForSlot(_FormatSlot.trailing);

  /// Reading order, so semantics and focus see leading → switch → trailing.
  Iterable<RenderBox> get _ordered =>
      <RenderBox?>[_leading, _center, _trailing].whereType<RenderBox>();

  @override
  void visitChildren(RenderObjectVisitor visitor) => _ordered.forEach(visitor);

  bool get _hasEdges => _leading != null || _trailing != null;

  double get _gap => _leading == null ? 0 : _leadingGap;

  double get _endGap => _trailing == null ? 0 : _trailingGap;

  Size _run(
    BoxConstraints constraints, {
    required bool dry,
    bool position = false,
  }) {
    final width = constraints.maxWidth;
    final loose = BoxConstraints(maxWidth: width);
    Size measure(RenderBox? child, BoxConstraints childConstraints) {
      if (child == null) return Size.zero;
      if (dry) return child.getDryLayout(childConstraints);
      child.layout(childConstraints, parentUsesSize: true);
      return child.size;
    }

    final lead = measure(_leading, loose);
    final trail = measure(_trailing, loose);
    final room = math.max(
      0.0,
      width - lead.width - _gap - trail.width - _endGap,
    );
    var stacked = false;
    var center = Size.zero;
    final centerChild = _center;
    if (centerChild != null) {
      if (_hasEdges) {
        if (_forceStacked) {
          stacked = true;
        } else {
          // The switch at the full row width is its natural width; if that
          // does not fit between the plates, it gets a line of its own.
          final natural = measure(centerChild, loose);
          stacked = natural.width > room + precisionErrorTolerance;
        }
      }
      center = measure(
        centerChild,
        BoxConstraints(maxWidth: stacked ? width : room),
      );
    }

    final resolvedWidth = width.isFinite
        ? width
        : lead.width + _gap + center.width + trail.width;
    final rowHeight = stacked
        ? math.max(lead.height, trail.height)
        : math.max(lead.height, math.max(center.height, trail.height));
    final height = stacked ? rowHeight + _runGap + center.height : rowHeight;
    final size = constraints.constrain(Size(resolvedWidth, height));

    if (position && !dry) {
      void place(RenderBox? child, double start, double top) {
        if (child == null) return;
        final x = _textDirection == TextDirection.ltr
            ? start
            : size.width - start - child.size.width;
        (child.parentData! as BoxParentData).offset = Offset(x, top);
      }

      place(_leading, 0, (rowHeight - lead.height) / 2);
      place(
        _trailing,
        size.width - trail.width,
        (rowHeight - trail.height) / 2,
      );
      if (stacked) {
        place(centerChild, 0, rowHeight + _runGap);
      } else {
        place(centerChild, lead.width + _gap, (rowHeight - center.height) / 2);
      }
    }
    return size;
  }

  @override
  void performLayout() {
    size = _run(constraints, dry: false, position: true);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _run(constraints, dry: true);

  @override
  double computeMinIntrinsicWidth(double height) {
    final lead = _leading?.getMinIntrinsicWidth(height) ?? 0;
    final trail = _trailing?.getMinIntrinsicWidth(height) ?? 0;
    final center = _center?.getMinIntrinsicWidth(height) ?? 0;
    return math.max(lead + _gap + trail, center);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final lead = _leading?.getMaxIntrinsicWidth(height) ?? 0;
    final trail = _trailing?.getMaxIntrinsicWidth(height) ?? 0;
    final center = _center?.getMaxIntrinsicWidth(height) ?? 0;
    return lead + _gap + center + _endGap + trail;
  }

  double _intrinsicHeight(double width, {required bool max}) {
    double of(RenderBox? child) => child == null
        ? 0
        : max
        ? child.getMaxIntrinsicHeight(width)
        : child.getMinIntrinsicHeight(width);
    final edges = math.max(of(_leading), of(_trailing));
    final center = of(_center);
    final centerChild = _center;
    if (centerChild == null || !_hasEdges) return math.max(edges, center);
    final room =
        width -
        (_leading?.getMaxIntrinsicWidth(double.infinity) ?? 0) -
        _gap -
        (_trailing?.getMaxIntrinsicWidth(double.infinity) ?? 0) -
        _endGap;
    final stacked =
        _forceStacked ||
        centerChild.getMaxIntrinsicWidth(double.infinity) > room;
    return stacked ? edges + _runGap + center : math.max(edges, center);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _intrinsicHeight(width, max: false);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _intrinsicHeight(width, max: true);

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in _ordered) {
      context.paintChild(
        child,
        offset + (child.parentData! as BoxParentData).offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in _ordered.toList(growable: false).reversed) {
      final offset = (child.parentData! as BoxParentData).offset;
      final hit = result.addWithPaintOffset(
        offset: offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }
}

/// Level 1 -- two large, trackless text tabs over media or the page canvas.
///
/// The selected tab uses the strongest ink (`textPrimary` on the canvas,
/// white over media), w800 and a short glowing line: a 30 × 3 bar in the
/// logo's gradient ([AppGradients.primary]) with a `brandGlow` shadow. The
/// unselected tab is `textTertiary` w600 on the canvas and white @ .78 over
/// media. The line is a separate shape rather than a text decoration, so it
/// stays crisp at large text sizes and supplies a non-colour selection cue.
/// There is deliberately no track, thumb or tile fill: the visual control is
/// only the two labels, while each label retains a full 48 px interaction
/// target.
///
/// Over media the words keep their 8-way glyph outline. The softer
/// three-shadow stack the refine spec proposes is gated on an Accessibility
/// measurement on a pure-white frame; until that passes, the outline — the
/// spec's named fallback — stays. Under high contrast the line is a solid
/// bar without the glow.
class ImmersiveSegmentedSwitch extends StatelessWidget {
  const ImmersiveSegmentedSwitch({
    required this.segments,
    required this.selectedIndex,
    required this.onSelected,
    this.groupLabel,
    this.onCanvas = false,
    this.segmentMinWidth = 72,
    this.onReselected,
    this.reselectHint,
    super.key,
  }) : assert(segments.length > 0, 'A segmented switch needs a segment.');

  final List<ImmersiveChromeOption> segments;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// What activating the ALREADY selected segment does. Null (the default)
  /// keeps it inert; the Yeels host passes its refresh here, the familiar
  /// "tap the current tab again" gesture.
  final ValueChanged<int>? onReselected;

  /// Spoken on the selected segment when [onReselected] is set, so the
  /// second activation is discoverable without sight.
  final String? reselectHint;

  /// Names the whole control to assistive technology, so the two levels are
  /// distinguishable without sight.
  final String? groupLabel;

  /// True when the switch sits on the page CANVAS instead of over media.
  ///
  /// Over media the labels are white (the inactive one at .78) with a glyph
  /// outline because the luminance beneath them is unknown. On the canvas
  /// the same trackless geometry uses theme-aware text roles for Dark and
  /// Pearl.
  final bool onCanvas;

  /// The narrowest a segment may be. Over media 72 keeps the two-item
  /// switch inside a 320 px phone; the canvas host asks for the board's
  /// wider segments.
  final double segmentMinWidth;

  /// Every text tab keeps a full 48 px target even though it has no tile.
  static const double _trackHeight = 48;

  @override
  Widget build(BuildContext context) {
    final count = segments.length;
    final clamped = selectedIndex.clamp(0, count - 1);
    final label = groupLabel;
    final accessibilityLayout =
        MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final reselected = onReselected;
    Widget segment(int index) => _SwitchSegment(
      key: segments[index].key,
      option: segments[index],
      selected: index == clamped,
      onCanvas: onCanvas,
      minWidth: segmentMinWidth,
      onTap: () => onSelected(index),
      onReselect: reselected == null ? null : () => reselected(index),
      reselectHint: reselected == null ? null : reselectHint,
    );
    // Equal widths keep the ordinary row visually balanced. At large text,
    // intrinsic-width tabs use the available line efficiently; Wrap is the
    // final fallback for a longer locale rather than clipping either word.
    Widget body = accessibilityLayout
        ? LayoutBuilder(
            builder: (context, constraints) => Wrap(
              // The segments drop their side padding at this size, so the
              // Wrap keeps the two words apart ("Głos Yeels", never
              // "GłosYeels").
              spacing: AppRhythm.item,
              runSpacing: AppRhythm.hairline,
              children: <Widget>[
                for (var index = 0; index < count; index++) segment(index),
              ],
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.max,
            children: <Widget>[
              for (var index = 0; index < count; index++)
                Expanded(child: segment(index)),
            ],
          );

    body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _trackHeight),
      child: accessibilityLayout ? body : IntrinsicWidth(child: body),
    );
    return label == null
        ? body
        : Semantics(container: true, label: label, child: body);
  }
}

/// Keeps the selected child of a horizontally scrolling chrome row inside
/// the viewport it lives in.
///
/// The filter row scrolls horizontally and carried no controller, so it
/// always rendered at offset 0: with the four Polish pool filters the SELECTED
/// chip sat off-screen at default text size on every phone width, and at
/// 200 % text even the two Reels filters lost their selection. The format
/// switch is deliberately not scrollable any more (both of its items must be
/// visible), so on a switch segment this mixin finds no Scrollable and does
/// nothing; it stays mixed in so a future scrolling host is covered.
///
/// Revealing on first layout matters as much as revealing on change: a feed
/// can mount with the far chip already selected.
mixin _KeepsSelectionVisible<T extends StatefulWidget> on State<T> {
  /// Whether this particular child is the one that must stay visible.
  bool get isSelectedForScroll;

  /// How the reveal moves. Over media it eases (Reduce Motion collapses it
  /// to a jump). A canvas row jumps ALWAYS: a `Scrollable` ignores pointers
  /// for as long as it is animating, so an eased reveal would swallow the
  /// next tap on a neighbouring chip for 140 ms — on the canvas the row is
  /// short and the jump is imperceptible, over media the scrim hides it.
  Duration get revealDuration => AppMotion.resolve(context, AppMotion.quick);

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  /// Call from `didUpdateWidget` with the previous selected flag.
  void revealIfSelectionGained(bool wasSelected) {
    if (isSelectedForScroll && !wasSelected) _scheduleReveal();
  }

  void _scheduleReveal() {
    if (!isSelectedForScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !isSelectedForScroll) return;
      // A chrome row is not required to scroll: above 600 px it is laid out
      // on the page canvas with room for everything.
      if (Scrollable.maybeOf(context) == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: revealDuration,
        curve: AppMotion.standardCurve,
      );
    });
  }
}

class _SwitchSegment extends StatefulWidget {
  const _SwitchSegment({
    required this.option,
    required this.selected,
    required this.onTap,
    this.onCanvas = false,
    this.minWidth = 72,
    this.onReselect,
    this.reselectHint,
    super.key,
  });

  final ImmersiveChromeOption option;
  final bool selected;
  final VoidCallback onTap;
  final bool onCanvas;
  final double minWidth;

  /// Runs instead of nothing when the selected segment is activated again.
  final VoidCallback? onReselect;
  final String? reselectHint;

  @override
  State<_SwitchSegment> createState() => _SwitchSegmentState();
}

class _SwitchSegmentState extends State<_SwitchSegment>
    with _KeepsSelectionVisible<_SwitchSegment> {
  bool _focused = false;

  /// Keeps the segment's own subtree — its focus node and its indicator
  /// animation — when the reselect tooltip wraps it or lets it go.
  final GlobalKey _body = GlobalKey(debugLabel: 'immersive switch segment');

  @override
  bool get isSelectedForScroll => widget.selected;

  @override
  void didUpdateWidget(covariant _SwitchSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    revealIfSelectionGained(oldWidget.selected);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final onCanvas = widget.onCanvas;
    final palette = onCanvas ? context.appPalette : null;
    final highContrast = MediaQuery.highContrastOf(context);
    // Canvas: the strongest ink selected, the tertiary one resting. Over
    // media: white, the resting tab at .78; the glyph outline carries the
    // local contrast on any frame.
    final Color foreground;
    if (palette != null) {
      foreground = selected ? palette.textPrimary : palette.textTertiary;
    } else {
      foreground = selected
          ? AppColors.white
          : AppColors.white.withValues(alpha: .78);
    }
    final focusRing = palette == null ? Colors.white : palette.focus;
    // The line: the logo's gradient with an emitted brand glow — a solid
    // bar and no glow under high contrast.
    final lineGlow = (palette ?? AppPalette.dark).brandGlow;
    final lineSolid = palette?.textPrimary ?? AppColors.white;
    final accessibilityLayout =
        MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final reselectHint = widget.onReselect == null ? null : widget.reselectHint;
    return Semantics(
      button: true,
      selected: selected,
      label: widget.option.semanticLabel ?? widget.option.label,
      hint: selected ? reselectHint : null,
      // The node replaces its subtree, so the activation the ink well offers
      // a pointer has to be restated here -- and so must the focus and
      // enabled states the discarded InkWell node would have carried. The
      // ring was drawn but never spoken.
      onTap: selected ? (widget.onReselect ?? widget.onTap) : widget.onTap,
      enabled: true,
      focusable: true,
      focused: _focused,
      excludeSemantics: true,
      child: _withReselectTooltip(
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            // Selecting the current segment again changes nothing unless the
            // host asked for a reselect action, but the control stays live so
            // keyboard focus can rest on it.
            onTap: selected ? (widget.onReselect ?? () {}) : widget.onTap,
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            onFocusChange: (focused) {
              if (_focused != focused) setState(() => _focused = focused);
            },
            child: Stack(
              children: <Widget>[
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: ImmersiveSegmentedSwitch._trackHeight,
                    minWidth: widget.minWidth,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      // The labels keep the reader's full text scale. On a
                      // narrow phone, including the Back and Create plates,
                      // reclaim only decorative side padding once large text
                      // is active so both words remain complete and tappable.
                      horizontal: accessibilityLayout ? 0 : AppRhythm.item,
                      vertical: 4,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          widget.option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 17,
                            letterSpacing: accessibilityLayout ? -2 : null,
                            height: 1.15,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            shadows: onCanvas
                                ? null
                                : _immersiveChromeTextShadows,
                          ),
                        ),
                        const SizedBox(height: 3),
                        AnimatedContainer(
                          key: ValueKey<String>(
                            'immersive-format-indicator-${widget.option.label}',
                          ),
                          duration: AppMotion.resolve(
                            context,
                            AppMotion.standard,
                          ),
                          curve: AppMotion.standardCurve,
                          width: selected ? 30 : 0,
                          height: 3,
                          decoration: BoxDecoration(
                            color: !selected
                                ? Colors.transparent
                                : highContrast
                                ? lineSolid
                                : null,
                            gradient: selected && !highContrast
                                ? AppGradients.primary
                                : null,
                            borderRadius: AppRadius.pill,
                            boxShadow: selected
                                ? <BoxShadow>[
                                    if (!onCanvas)
                                      const BoxShadow(
                                        color: Color(0xE6000000),
                                        blurRadius: 0,
                                        spreadRadius: 2,
                                      ),
                                    if (!highContrast)
                                      BoxShadow(color: lineGlow, blurRadius: 8),
                                  ]
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: AppMotion.resolve(context, AppMotion.quick),
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(8),
                        ),
                        border: Border.all(
                          color: _focused ? focusRing : Colors.transparent,
                          width: 2,
                        ),
                        boxShadow: _focused && !onCanvas
                            ? const <BoxShadow>[
                                BoxShadow(
                                  color: Color(0xE6000000),
                                  blurRadius: 0,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        selected ? reselectHint : null,
      ),
    );
  }

  /// A pointer reader learns what the selected tab does now, too; the spoken
  /// hint already carries it, so the tooltip stays out of semantics. The
  /// GlobalKey reparents the ink well rather than rebuilding it when the
  /// tooltip comes and goes with the selection.
  Widget _withReselectTooltip(Widget body, String? message) {
    final keyed = KeyedSubtree(key: _body, child: body);
    if (message == null) return keyed;
    return Tooltip(message: message, excludeFromSemantics: true, child: keyed);
  }
}

/// Level 2 -- the quieter one, by construction: refine-look R8 chips.
///
/// No track and no container of its own; each chip is 36 px of ink inside a
/// 48 px target. Over media the selected chip is a white fill with the
/// immersive canvas as ink (w700) and the others sit on a translucent black
/// plate with white w600 labels. It scrolls horizontally and never wraps,
/// which is the existing filter behaviour.
class ImmersiveFilterRow extends StatelessWidget {
  const ImmersiveFilterRow({
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    this.groupLabel,
    this.onCanvas = false,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final List<ImmersiveChromeOption> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String? groupLabel;

  /// On the page canvas the chips take the palette's R8 finish: the selected
  /// one is an ink inversion (`textPrimary` fill, canvas-coloured w700
  /// label, no edge), the others a transparent fill with a control hairline
  /// and a `textSecondary` w600 label. Over media (default) the white /
  /// translucent-plate pair described above.
  final bool onCanvas;

  /// Scroll padding, so a full-bleed row can keep the page gutter as the
  /// distance its first and last chip stop at.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final label = groupLabel;
    final row = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var index = 0; index < options.length; index++) ...<Widget>[
            if (index > 0)
              SizedBox(width: onCanvas ? AppRhythm.tight : AppRhythm.hairline),
            _FilterInk(
              key: options[index].key,
              option: options[index],
              selected: index == selectedIndex,
              onCanvas: onCanvas,
              onTap: () => onSelected(index),
            ),
          ],
        ],
      ),
    );
    return label == null
        ? row
        : Semantics(container: true, label: label, child: row);
  }
}

class _FilterInk extends StatefulWidget {
  const _FilterInk({
    required this.option,
    required this.selected,
    required this.onTap,
    this.onCanvas = false,
    super.key,
  });

  final ImmersiveChromeOption option;
  final bool selected;
  final VoidCallback onTap;
  final bool onCanvas;

  @override
  State<_FilterInk> createState() => _FilterInkState();
}

class _FilterInkState extends State<_FilterInk>
    with _KeepsSelectionVisible<_FilterInk> {
  bool _focused = false;

  @override
  bool get isSelectedForScroll => widget.selected;

  @override
  Duration get revealDuration =>
      widget.onCanvas ? Duration.zero : super.revealDuration;

  @override
  void didUpdateWidget(covariant _FilterInk oldWidget) {
    super.didUpdateWidget(oldWidget);
    revealIfSelectionGained(oldWidget.selected);
  }

  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    if (widget.onCanvas) return _buildOnCanvas(context, selected);
    // Over media: a white chip with canvas ink when chosen, a translucent
    // black plate with white ink otherwise. The plate darkens a step under
    // a pointer or a press. The resting label keeps the glyph outline, so
    // it holds its contrast even where the plate sits on a white frame; the
    // chosen label is dark ink on white and needs none.
    final plate = AppFinish.chipOverMediaFill(selected: selected);
    final fill = selected || !(_hovered || _pressed)
        ? plate
        : plate.withValues(alpha: plate.a + (_pressed ? .24 : .14));
    return Semantics(
      button: true,
      selected: selected,
      label: widget.option.semanticLabel ?? widget.option.label,
      onTap: widget.onTap,
      enabled: true,
      focusable: true,
      focused: _focused,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: selected ? () {} : widget.onTap,
          customBorder: const StadiumBorder(),
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          onHover: _setHovered,
          onHighlightChanged: _setPressed,
          onFocusChange: (focused) {
            if (_focused != focused) setState(() => _focused = focused);
          },
          // The ink is 36 high and centred inside a 48 target: the chip reads
          // as quiet without ever shrinking what a finger has to hit.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Center(
              child: AnimatedContainer(
                duration: AppMotion.resolve(context, AppMotion.quick),
                constraints: const BoxConstraints(
                  minHeight: AppFinish.chipHeight,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppFinish.chipPaddingH,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: AppRadius.pill,
                  // The focus ring must differ from the fill it sits on: a
                  // white ring vanished into the chosen chip's white fill
                  // (the default-selected "Odkrywaj"), so there it is the
                  // chip's own dark ink. The dark halo below keeps the
                  // chip's edge on a light frame either way.
                  border: Border.all(
                    color: !_focused
                        ? Colors.transparent
                        : selected
                        ? AppFinish.chipOverMediaLabel(selected: true)
                        : Colors.white,
                    width: 2,
                  ),
                  boxShadow: _focused
                      ? const <BoxShadow>[
                          BoxShadow(
                            color: Color(0xE6000000),
                            blurRadius: 0,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  widget.option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppFinish.chipOverMediaLabel(selected: selected),
                    fontSize: AppFinish.chipFontSize,
                    height: 1.2,
                    fontWeight: AppFinish.chipWeight(selected: selected),
                    shadows: selected ? null : _immersiveChromeTextShadows,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The canvas chip (R8): the same 36-in-48 ink and the same semantics, in
  /// palette roles. Selection is carried by the ink inversion AND the
  /// weight AND the `selected` flag, never by colour alone; a resting chip
  /// is a hairline outline with no fill, glass under a pointer and a
  /// textPrimary @ .10 wash while pressed. High contrast brings back
  /// `borderStrong`.
  Widget _buildOnCanvas(BuildContext context, bool selected) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    // The 1 px edge is always there (transparent on the chosen chip), and
    // focus paints its 2 px ring as a foreground, so neither selecting nor
    // focusing a chip ever changes its size or nudges its neighbours.
    final edge = AppFinish.chipBorder(
      palette,
      selected: selected,
      highContrast: highContrast,
    );
    final focusRing = AppFinish.chipBorder(
      palette,
      selected: selected,
      focused: true,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: widget.option.semanticLabel ?? widget.option.label,
      onTap: widget.onTap,
      enabled: true,
      focusable: true,
      focused: _focused,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: selected ? () {} : widget.onTap,
          customBorder: const StadiumBorder(),
          // The fill carries hover and press; no second wash, no ripple.
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          onHover: _setHovered,
          onHighlightChanged: _setPressed,
          onFocusChange: (focused) {
            if (_focused != focused) setState(() => _focused = focused);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Center(
              child: AnimatedContainer(
                duration: AppMotion.resolve(context, AppMotion.quick),
                constraints: const BoxConstraints(
                  minHeight: AppFinish.chipHeight,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppFinish.chipPaddingH,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppFinish.chipFill(
                    palette,
                    selected: selected,
                    hovered: _hovered,
                    pressed: _pressed,
                    highContrast: highContrast,
                  ),
                  borderRadius: AppRadius.pill,
                  border:
                      edge ?? Border.all(color: Colors.transparent, width: 1),
                ),
                foregroundDecoration: _focused
                    ? BoxDecoration(
                        borderRadius: AppRadius.pill,
                        border: focusRing,
                      )
                    : null,
                child: Text(
                  widget.option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppFinish.chipLabel(palette, selected: selected),
                    fontSize: AppFinish.chipFontSize,
                    height: 1.2,
                    fontWeight: AppFinish.chipWeight(selected: selected),
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
