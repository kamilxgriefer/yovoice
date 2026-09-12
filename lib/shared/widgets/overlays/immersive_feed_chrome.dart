import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart';

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
/// | shape | contained track + solid thumb | free text, no container |
/// | selected | solid fill, dark ink on it | low-opacity wash, white ink |
/// | type | 15 px, w800 selected | 13 px, w700 selected |
///
/// No [TextDecoration] appears anywhere in this chrome. Selection is carried
/// by fill AND by the `selected` semantic flag, never by colour alone and
/// never by a decoration.
///
/// The chrome is deliberately theme-invariant: it sits over content of
/// unknown luminance, not over the page canvas, so Dark and Pearl are
/// identical here. That is the same principle the overlay plates already
/// prove. Every foreground clears 4.5:1 against the composited track even
/// over pure-white media.
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        // Unchanged: the scrim that makes any media legible beneath the
        // chrome. A media overlay may stay dark in both appearances.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xF0000000), Color(0xB8000000)],
        ),
      ),
      child: Padding(
        // No safe-area inset is added here: every host that mounts this
        // chrome already sits inside a SafeArea, so reserving the notch again
        // would push the first row down by the status bar a second time.
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
      ),
    );
  }
}

/// Row 1: the plates keep their places and the switch sits between them.
///
/// Deliberately ONE shape at every text size. An earlier cut moved the switch
/// to its own line at accessibility sizes, which read well but roughly doubled
/// the height of the chrome — and this chrome is overlaid, so every pixel it
/// takes is taken from the stage. At 320 px / 200 % that covered the authored
/// links on the frame beneath it. The switch is horizontally scrollable
/// instead, so it can never force a second line or overflow.
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
            // room it has and the segments share it equally; the labels stop
            // scaling at 1.6x (see ImmersiveSegmentedSwitch) well before an
            // ellipsis is ever needed.
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

/// Level 1 -- a CONTAINED segmented control over media.
///
/// The selected segment is named by a filled surface, not by a text
/// decoration: a rounded track with a solid white thumb, dark brand ink on
/// the thumb and white ink beside it. This is the app's own pill grammar
/// restated for a surface whose background is unknown, which is why it uses
/// fixed white/ink rather than the palette's track and primary thumb.
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
  /// Over media the control is theme-invariant (dark plate, white thumb,
  /// shadowed copy) because the luminance beneath it is unknown. On the
  /// canvas that luminance is the palette's own, so the same geometry is
  /// restated in palette roles: `surfaceMuted` track with a hairline,
  /// `colorScheme.primary` thumb, white on the thumb and `textSecondary`
  /// beside it, no shadows. Default false keeps every existing host
  /// byte-for-byte.
  final bool onCanvas;

  /// The narrowest a segment may be. Over media 72 keeps the two-item
  /// switch inside a 320 px phone; the canvas host asks for the board's
  /// wider segments.
  final double segmentMinWidth;

  /// Track 48, thumb inset 4, so the thumb is 40 and every segment's tap
  /// target is the full 48 -- the inset belongs to the thumb, not the button.
  static const double _trackHeight = 48;
  static const double _trackInset = 4;

  /// Upper bound for the segment labels' text scale. See [build].
  static const double _maxLabelScale = 1.6;

  @override
  Widget build(BuildContext context) {
    final count = segments.length;
    final clamped = selectedIndex.clamp(0, count - 1);
    final thumbX = count == 1 ? 0.0 : -1 + 2 * clamped / (count - 1);
    final label = groupLabel;
    final palette = onCanvas ? context.appPalette : null;
    final thumbColor = onCanvas
        ? Theme.of(context).colorScheme.primary
        : Colors.white;

    Widget body = Stack(
      children: <Widget>[
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(_trackInset),
            child: IgnorePointer(
              child: AnimatedAlign(
                duration: AppMotion.resolve(context, AppMotion.standard),
                curve: AppMotion.standardCurve,
                alignment: AlignmentDirectional(thumbX, 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / count,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: thumbColor,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Equal-width segments are what make a 1/count thumb correct. While
        // the segments were content-sized, the thumb landed on the neighbour
        // in every locale whose two labels differ in width -- English is the
        // one case where "Voice" and "Reels" happen to measure the same,
        // which is why every harness run missed it. The selected label is
        // painted in contrast ink with no shadow because it is assumed to sit
        // on the white thumb, so where the thumb had slid away that ink fell
        // on the dark track at roughly 1.2:1 and became unreadable.
        // IntrinsicWidth sizes the track to count x the widest segment, and
        // equal flex then divides it exactly.
        Row(
          mainAxisSize: MainAxisSize.max,
          children: <Widget>[
            for (var index = 0; index < count; index++)
              Expanded(
                child: _SwitchSegment(
                  key: segments[index].key,
                  option: segments[index],
                  selected: index == clamped,
                  onCanvas: onCanvas,
                  minWidth: segmentMinWidth,
                  onTap: () => onSelected(index),
                ),
              ),
          ],
        ),
      ],
    );

    body = MediaQuery.withClampedTextScaling(
      // Both labels must stay on screen at the narrowest supported width.
      // The 48 px target and the track never depend on the text size, so
      // capping the LABEL scale keeps every realistic locale fully laid out
      // at 320 px with 200 % system text while the page around the switch
      // still scales to 200 %. Equal-width segments plus an ellipsis remain
      // the last resort beyond that, never a hidden segment.
      maxScaleFactor: _maxLabelScale,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _trackHeight),
        child: DecoratedBox(
          decoration: palette == null
              ? const BoxDecoration(
                  color: overlayPlateColor,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                )
              : BoxDecoration(
                  color: palette.surfaceMuted,
                  border: Border.all(color: palette.border),
                  borderRadius: const BorderRadius.all(Radius.circular(999)),
                ),
          child: IntrinsicWidth(child: body),
        ),
      ),
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
  Duration get revealDuration =>
      AppMotion.resolve(context, AppMotion.quick);

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
    // Over media: dark brand ink on the white thumb (16.6:1); white beside
    // it on the composited track (9.1:1 even over pure-white media). On the
    // canvas: white on the primary thumb (5.85:1), textSecondary beside it.
    final foreground = palette == null
        ? (selected ? AppColors.contrastInk : Colors.white)
        : (selected
              ? Theme.of(context).colorScheme.onPrimary
              : palette.textSecondary);
    final focusRing = palette == null
        // Two-tone by construction: the ring is dark on the white thumb and
        // white on the dark track, so it is visible in both states over any
        // media.
        ? (selected ? AppColors.contrastInk : Colors.white)
        : palette.focus;
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
          customBorder: const StadiumBorder(),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppRhythm.title,
                    vertical: 6,
                  ),
                  child: Align(
                    alignment: Alignment.center,
                    child: Text(
                      widget.option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        // White copy laid on media keeps its shadow stack;
                        // ink on the solid thumb, and any canvas copy, does
                        // not need one.
                        shadows: selected || onCanvas
                            ? null
                            : overlayTextShadows,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: AppMotion.resolve(context, AppMotion.quick),
                    margin: const EdgeInsets.all(
                      ImmersiveSegmentedSwitch._trackInset,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.all(
                        Radius.circular(999),
                      ),
                      border: Border.all(
                        color: _focused ? focusRing : Colors.transparent,
                        width: 2,
                      ),
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
                    shadows: overlayTextShadows,
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
                    color: selected ? palette.textPrimary : palette.textSecondary,
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
