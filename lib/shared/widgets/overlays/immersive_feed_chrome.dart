import 'package:flutter/material.dart';

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
/// | shape | large text + short glow line | smaller filter controls |
/// | selected | violet ink + line + weight | low-opacity wash + weight |
/// | type | 17 px, w800 selected | 13 px, w700 selected |
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
    super.key,
  });

  /// Level 1. Supplied by the host that owns the format, so this widget never
  /// has to know what a format is.
  final Widget? formatSwitch;

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
                ),
              ),
              ?filterTrailing,
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
/// The selected tab uses violet ink, stronger weight and a short glowing line.
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
  /// Over media the selected violet and white inactive label use the fixed
  /// immersive palette because the luminance beneath them is unknown. On the
  /// canvas the same trackless geometry uses theme-aware text and interaction
  /// roles for Dark and Pearl.
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
    // The fixed immersive violet clears AA against the header scrim even over
    // bright footage. Canvas tabs use theme-aware interaction and copy roles.
    // In both cases selection also changes weight and gains a separate line.
    final selectedForeground =
        palette?.interactiveForeground ?? AppPalette.dark.interactiveForeground;
    final foreground = palette == null
        ? (selected ? selectedForeground : Colors.white)
        : (selected ? selectedForeground : palette.textSecondary);
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
                          color: selected
                              ? selectedForeground
                              : Colors.transparent,
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
                                  BoxShadow(
                                    color: selectedForeground.withValues(
                                      alpha: .62,
                                    ),
                                    blurRadius: 8,
                                  ),
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
/// No track, no thumb, no container of its own. The selected filter gets a
/// low-opacity white wash; the unselected ones are plain text. It scrolls
/// horizontally and never wraps, which is the existing filter behaviour.
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

  /// On the page canvas the selected chip is a low-opacity PRIMARY wash with
  /// a primary hairline and the unselected ones carry the palette hairline
  /// (a chip's shape, so it is never mistaken for plain copy). Over media
  /// (default) the existing white wash and plain text stay unchanged.
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
          // The ink is 36 high and centred inside a 48 target: the chip reads
          // as quiet without ever shrinking what a finger has to hit.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Center(
              child: AnimatedContainer(
                duration: AppMotion.resolve(context, AppMotion.quick),
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsets.symmetric(horizontal: AppRhythm.item),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: .16)
                      : Colors.transparent,
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
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    shadows: _immersiveChromeTextShadows,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The canvas chip: the same 36-in-48 ink and the same semantics, in
  /// palette roles. Selection is carried by the primary wash AND the
  /// hairline AND the weight, never by colour alone.
  Widget _buildOnCanvas(BuildContext context, bool selected) {
    final palette = context.appPalette;
    final primary = Theme.of(context).colorScheme.primary;
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Center(
              child: AnimatedContainer(
                duration: AppMotion.resolve(context, AppMotion.quick),
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsets.symmetric(horizontal: AppRhythm.item),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? primary.withValues(alpha: .16)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.all(Radius.circular(999)),
                  border: Border.all(
                    color: _focused
                        ? palette.focus
                        : selected
                        ? primary.withValues(alpha: .40)
                        : palette.border,
                    width: _focused ? 2 : 1,
                  ),
                ),
                child: Text(
                  widget.option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? palette.textPrimary
                        : palette.textSecondary,
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
