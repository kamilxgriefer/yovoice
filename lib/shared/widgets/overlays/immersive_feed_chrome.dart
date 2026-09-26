import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
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
/// | shape | large text + short glow line | smaller filter chips |
/// | selected | full ink + brand line + weight | ink-inverted chip + weight |
/// | type | 17 px, w800 selected | 13 px, w700 selected |
///
/// Refine-look §8.4 (Głos and Yeels ship together): the chips are the R8
/// chips — on the canvas an ink inversion (`textPrimary` fill, `background`
/// label) over hairline-edged unselected chips; over media a white chip with
/// the immersive canvas as its ink over black @ .55 plates — and the
/// switch's line is the logo's gradient.
///
/// No [TextDecoration] appears anywhere in this chrome. Selection is carried
/// by a separate line, weight AND by the `selected` semantic flag, never by
/// colour alone.
///
/// The chrome is deliberately theme-invariant: it sits directly over media,
/// not over a separate header surface, so Dark and Pearl are identical here.
/// The text shadows and the small action plates carry local contrast without
/// turning the top of every Yeel into an opaque black block.
class ImmersiveFeedChrome extends StatelessWidget {
  const ImmersiveFeedChrome({
    required this.gutter,
    required this.filters,
    required this.selectedFilterIndex,
    required this.onFilterSelected,
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

  /// Level 2.
  final List<ImmersiveChromeOption> filters;
  final int selectedFilterIndex;
  final ValueChanged<int> onFilterSelected;

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
    // Keep the whole header transparent. The populated phone layout places it
    // over the Yeel itself; painting a full-width scrim here produces the
    // reported black rectangle and visually detaches the controls from the
    // media. Each foreground atom already owns its contrast treatment.
    return Padding(
      // No safe-area inset is added here: every host that mounts this chrome
      // already sits inside a SafeArea, so reserving the notch again would
      // push the first row down by the status bar a second time.
      //
      // The two 48 px rows ARE the header (title row 4 + 48 ≤ 56). The
      // total height is deliberately unchanged by the Slim pass: the Yeels
      // stage measures this chrome and derives its shallow-frame geometry
      // (horizontal action row vs rail) from the media height left under it.
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
          // The one gap that makes two levels read as two levels.
          const SizedBox(height: AppRhythm.tight),
          Row(
            children: <Widget>[
              Expanded(
                child: ImmersiveFilterRow(
                  options: filters,
                  selectedIndex: selectedFilterIndex,
                  onSelected: onFilterSelected,
                  groupLabel: filterGroupLabel,
                  onCanvas: onCanvas,
                ),
              ),
              // Air between the strip's (faded) end and the pinned control,
              // so a chip scrolling under the edge never touches its circle.
              if (filterTrailing != null) ...<Widget>[
                const SizedBox(width: ImmersiveFilterRow.trailingGap),
                filterTrailing!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Row 1: the plates keep their places and the switch sits between them.
///
/// At ordinary sizes all three slots share one compact row. Large text gives
/// the edge actions their own row and the format labels the full width below.
/// This costs one short line of overlay height, but it preserves the reader's
/// requested text size and keeps both choices complete on a 320 px phone.
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
    final switchWidget = formatSwitch;
    final accessibilityLayout =
        MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    if (switchWidget != null &&
        accessibilityLayout &&
        (leading != null || trailing != null)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(children: <Widget>[?leading, const Spacer(), ?trailing]),
          const SizedBox(height: AppRhythm.hairline),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: switchWidget,
          ),
        ],
      );
    }
    return Row(
      children: <Widget>[
        if (leading != null) ...<Widget>[
          leading!,
          const SizedBox(width: AppRhythm.tight),
        ],
        if (switchWidget == null)
          const Spacer()
        else
          Expanded(
            // Bounded on purpose. A horizontal scroll view here handed the
            // switch unbounded width, so at 200 % text on a 320 px phone it
            // grew past the viewport and exactly ONE of the two formats was
            // ever visible: first the selected one sat off-screen, and once
            // the selection was scrolled into view the other one did. A
            // two-item format switch must show both items, so it takes the
            // room it has and the segments share it equally. At accessibility
            // sizes each segment trims only its horizontal breathing room;
            // the reader's requested label scale remains untouched.
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: switchWidget,
            ),
          ),
        ?trailing,
      ],
    );
  }
}

/// Level 1 -- two large, trackless text tabs over media or the page canvas.
///
/// The selected tab uses full ink (`textPrimary` on the canvas, white over
/// media), w800 and a short 30 × 3 line in the logo's gradient
/// ([AppGradients.primary]) with a soft brand glow; the other tab is quieter
/// (`textTertiary` w600 on the canvas; over media it keeps FULL white at
/// w600, because a dimmed white measured ≈ 1.06:1 against a light frame and
/// read as hollow, outlined letters — over footage the quieter tab is quiet
/// by weight and by the missing line, never by fading its ink).
/// The line is a separate shape rather than a text decoration, so it stays
/// crisp at large text sizes and supplies a non-colour selection cue. There
/// is deliberately no track, thumb or tile fill: the visual control is only
/// the two labels, while each label retains a full 48 px interaction target.
class ImmersiveSegmentedSwitch extends StatelessWidget {
  const ImmersiveSegmentedSwitch({
    required this.segments,
    required this.selectedIndex,
    required this.onSelected,
    this.groupLabel,
    this.onCanvas = false,
    this.segmentMinWidth = 72,
    super.key,
  }) : assert(segments.length > 0, 'A segmented switch needs a segment.');

  final List<ImmersiveChromeOption> segments;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Names the whole control to assistive technology, so the two levels are
  /// distinguishable without sight.
  final String? groupLabel;

  /// True when the switch sits on the page CANVAS instead of over media.
  ///
  /// Over media both labels are full white with the glyph-local dark
  /// outline, because the luminance beneath them is unknown. On the canvas the same trackless geometry uses the
  /// theme's text roles for Dark and Pearl.
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
    Widget segment(int index) => _SwitchSegment(
      key: segments[index].key,
      option: segments[index],
      selected: index == clamped,
      onCanvas: onCanvas,
      minWidth: segmentMinWidth,
      onTap: () => onSelected(index),
    );
    // Equal widths keep the ordinary row visually balanced. At large text,
    // intrinsic-width tabs use the available line efficiently; Wrap is the
    // final fallback for a longer locale rather than clipping either word.
    Widget body = accessibilityLayout
        ? LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 0,
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
    super.key,
  });

  final ImmersiveChromeOption option;
  final bool selected;
  final VoidCallback onTap;
  final bool onCanvas;
  final double minWidth;

  @override
  State<_SwitchSegment> createState() => _SwitchSegmentState();
}

class _SwitchSegmentState extends State<_SwitchSegment>
    with _KeepsSelectionVisible<_SwitchSegment> {
  bool _focused = false;

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
    // Selection is weight AND the separate gradient line (plus ink strength
    // on the canvas) — never colour alone. Over media both words are full
    // white and keep the glyph-local outline: an unplated word has nothing
    // else to hold it on a white frame, and white @ .78 there measured
    // ≈ 1.06:1 glyph against frame (the refine-look B5 review, A11Y-B5-06).
    final foreground = palette == null
        ? AppColors.white
        : (selected ? palette.textPrimary : palette.textTertiary);
    // The line's glow is the brand light: the palette's on the canvas, the
    // immersive (Dark) one over media, where both themes are the same.
    final glow = (palette ?? AppPalette.dark).brandGlow;
    final focusRing = palette == null ? Colors.white : palette.focus;
    final accessibilityLayout =
        MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    return Semantics(
      button: true,
      selected: selected,
      label: widget.option.semanticLabel ?? widget.option.label,
      // The node replaces its subtree, so the activation the ink well offers
      // a pointer has to be restated here -- and so must the focus and
      // enabled states the discarded InkWell node would have carried. The
      // ring was drawn but never spoken.
      onTap: widget.onTap,
      enabled: true,
      focusable: true,
      focused: _focused,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          // Selecting the current segment again changes nothing, but the
          // control stays live so keyboard focus can rest on it.
          onTap: selected ? () {} : widget.onTap,
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
                          gradient: selected ? AppGradients.primary : null,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(999),
                          ),
                          boxShadow: selected
                              ? <BoxShadow>[
                                  if (!onCanvas)
                                    const BoxShadow(
                                      color: Color(0xE6000000),
                                      blurRadius: 0,
                                      spreadRadius: 2,
                                    ),
                                  BoxShadow(color: glow, blurRadius: 8),
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
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
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
    );
  }
}

/// Level 2 -- the quieter one, by construction.
///
/// No track, no thumb, no container of its own: a row of R8 chips (36 ink
/// in a 48 target, 14 px side padding, 13 px labels). Over media the
/// selected chip is white with the immersive canvas as its ink and the
/// others sit on black @ .55 plates with white words; on the canvas
/// the selected chip is an ink inversion and the others are hairline-edged.
/// It scrolls horizontally and never wraps, which is the existing filter
/// behaviour.
///
/// **Finished edges** (refine-look §1 #10, the B5 review): with hairline
/// chips a hard viewport cut read as a broken pill ("Najbardzie|"). An edge
/// that still has chips beyond it therefore dissolves over [edgeFade]
/// (a `ShaderMask` in `dstIn`, the pattern §8.1 uses for the Start chats
/// rail): the end edge while more chips follow, the start edge once the
/// strip has scrolled. It is mirrored in RTL and gone at either scroll end,
/// so a strip that fits is drawn exactly as before. The mask is always in
/// the tree (only its stops change), so a fade appearing or leaving never
/// rebuilds the scroller or loses its offset.
class ImmersiveFilterRow extends StatefulWidget {
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

  /// On the page canvas the chips take the theme's roles (R8 ink
  /// inversion); over media (default) the fixed white / black-plate pair.
  final bool onCanvas;

  /// Scroll padding, so a full-bleed row can keep the page gutter as the
  /// distance its first and last chip stop at.
  final EdgeInsetsGeometry padding;

  /// How far a chip cut by a scrolling edge dissolves.
  static const double edgeFade = 28;

  /// The air a host leaves between this strip and a control pinned beside
  /// it (the refresh circle), so a chip under the fade never touches it.
  static const double trailingGap = AppRhythm.tight;

  /// The inner ring that marks keyboard focus on the SELECTED chip.
  static const Key selectedFocusRingKey = ValueKey<String>(
    'immersive-chip-selected-focus-ring',
  );

  @override
  State<ImmersiveFilterRow> createState() => ImmersiveFilterRowState();
}

/// Tracks whether chips lie beyond either edge of the strip.
class ImmersiveFilterRowState extends State<ImmersiveFilterRow> {
  bool _moreBefore = false;
  bool _moreAfter = false;

  // The latest reported edges; the painted ones catch up after a frame
  // when the report arrived mid-layout.
  bool _reportedBefore = false;
  bool _reportedAfter = false;

  /// Chips are hidden past the START edge (the strip has scrolled).
  @visibleForTesting
  bool get fadesStart => _moreBefore;

  /// Chips are hidden past the END edge.
  @visibleForTesting
  bool get fadesEnd => _moreAfter;

  bool _track(ScrollMetrics metrics) {
    if (metrics.axis != Axis.horizontal || !metrics.hasContentDimensions) {
      return false;
    }
    final before = metrics.extentBefore > .5;
    final after = metrics.extentAfter > .5;
    if (before == _reportedBefore && after == _reportedAfter) return false;
    _reportedBefore = before;
    _reportedAfter = after;
    void apply() {
      if (!mounted) return;
      if (_moreBefore == _reportedBefore && _moreAfter == _reportedAfter) {
        return;
      }
      setState(() {
        _moreBefore = _reportedBefore;
        _moreAfter = _reportedAfter;
      });
    }

    // A change reported while the frame is being laid out waits for the
    // frame to finish; a scroll reported between frames applies at once.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
    return false;
  }

  Shader _edgeMask(Rect bounds, TextDirection direction) {
    final width = bounds.width;
    final fade = width <= 0
        ? 0.0
        : (ImmersiveFilterRow.edgeFade / width).clamp(0.0, .5);
    return LinearGradient(
      begin: AlignmentDirectional.centerStart,
      end: AlignmentDirectional.centerEnd,
      colors: <Color>[
        _moreBefore ? Colors.transparent : Colors.black,
        Colors.black,
        Colors.black,
        _moreAfter ? Colors.transparent : Colors.black,
      ],
      stops: <double>[0, fade, 1 - fade, 1],
    ).createShader(bounds, textDirection: direction);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.groupLabel;
    final options = widget.options;
    final onCanvas = widget.onCanvas;
    final direction = Directionality.of(context);
    final scroller = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: widget.padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var index = 0; index < options.length; index++) ...<Widget>[
            if (index > 0)
              SizedBox(width: onCanvas ? AppRhythm.tight : AppRhythm.hairline),
            _FilterInk(
              key: options[index].key,
              option: options[index],
              selected: index == widget.selectedIndex,
              onCanvas: onCanvas,
              onTap: () => widget.onSelected(index),
            ),
          ],
        ],
      ),
    );
    final row = NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) =>
          notification.depth == 0 && _track(notification.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) =>
            notification.depth == 0 && _track(notification.metrics),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => _edgeMask(bounds, direction),
          child: scroller,
        ),
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

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    if (widget.onCanvas) return _buildOnCanvas(context, selected);
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
          onFocusChange: (focused) {
            if (_focused != focused) setState(() => _focused = focused);
          },
          onHover: (hovered) {
            if (_hovered != hovered) setState(() => _hovered = hovered);
          },
          // The chip carries its own hover and press fills.
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          // The ink is 36 high and centred inside a 48 target: the chip reads
          // as quiet without ever shrinking what a finger has to hit.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Center(
              child: _withSelectedFocusRing(
                ink: AppFinish.chipOverMediaLabel(selected: true),
                chip: AnimatedContainer(
                  duration: AppMotion.resolve(context, AppMotion.quick),
                  constraints: const BoxConstraints(
                    minHeight: AppFinish.chipHeight,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppFinish.chipPaddingH,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    // R8 over media: a white chip for the choice, a black
                    // plate (a touch deeper on hover) for the others.
                    color: selected
                        ? AppFinish.chipOverMediaFill(selected: true)
                        : _hovered
                        ? Color.alphaBlend(
                            AppFinish.overlayChipColor,
                            AppFinish.overlayChipColor,
                          )
                        : AppFinish.chipOverMediaFill(selected: false),
                    borderRadius: const BorderRadius.all(Radius.circular(999)),
                    border: Border.all(
                      color: _focused ? Colors.white : Colors.transparent,
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
                      // Dark ink on the white chip needs no outline. White
                      // words on the plate get only the soft overlay shadow:
                      // the plate itself carries their contrast (4.74:1 even
                      // over a pure-white frame), and stacking the hard 8-way
                      // stroke on it read as a meme caption (B5 review, V6).
                      // The stroke stays on the UNPLATED switch words above.
                      shadows: selected ? null : overlayTextShadows,
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

  /// The keyboard-focus cue of a SELECTED chip. The selected fill is the
  /// same colour as the focus ring drawn on the chip's edge (white over
  /// media; on the canvas the ring meets an ink-inverted fill at ≈ 2:1), so
  /// the ring alone would all but vanish on it. A 2 px ring in the chip's
  /// own ink, inset 2 px inside the edge, marks focus against the fill at
  /// ≥ 15:1 whatever lies behind the chip (WCAG 2.4.7). Unselected chips
  /// keep the edge ring alone.
  Widget _withSelectedFocusRing({required Color ink, required Widget chip}) {
    return Stack(
      children: <Widget>[
        chip,
        if (widget.selected && _focused)
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: DecoratedBox(
                  key: ImmersiveFilterRow.selectedFocusRingKey,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.circular(999)),
                    border: Border.all(color: ink, width: 2),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The canvas chip (R8): the same 36-in-48 ink and the same semantics, in
  /// palette roles. Selection is an ink inversion (`textPrimary` fill,
  /// `background` label, w700) AND the semantic flag, never colour alone;
  /// an unselected chip is transparent with a 1 px `hairlineControl` edge
  /// and a `textSecondary` w600 label, `glass` on hover and textPrimary
  /// @ .10 while pressed. Focus is a 2 px `focus` ring (plus, on the
  /// selected chip, an inner ring in its own ink). Under high contrast the
  /// edge returns to `borderStrong`.
  Widget _buildOnCanvas(BuildContext context, bool selected) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
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
          onFocusChange: (focused) {
            if (_focused != focused) setState(() => _focused = focused);
          },
          onHover: (hovered) {
            if (_hovered != hovered) setState(() => _hovered = hovered);
          },
          onHighlightChanged: (pressed) {
            if (_pressed != pressed) setState(() => _pressed = pressed);
          },
          // The chip carries its own hover and press fills.
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Center(
              child: _withSelectedFocusRing(
                ink: AppFinish.chipLabel(palette, selected: true),
                chip: AnimatedContainer(
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
                    borderRadius: const BorderRadius.all(Radius.circular(999)),
                    border: AppFinish.chipBorder(
                      palette,
                      selected: selected,
                      focused: _focused,
                      highContrast: highContrast,
                    ),
                  ),
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
      ),
    );
  }
}
