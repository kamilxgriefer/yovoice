import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';

/// One choice inside a [YoSegmentedPill].
@immutable
class YoSegmentedPillSegment {
  const YoSegmentedPillSegment({
    required this.label,
    this.icon,
    this.key,
    this.semanticLabel,
  });

  final String label;
  final IconData? icon;

  /// Applied to the segment's tappable region so tests and tours can address
  /// it without knowing how the pill is built.
  final Key? key;

  /// Read to assistive technology instead of [label] when the visible word is
  /// too short to stand alone.
  final String? semanticLabel;
}

/// A single-choice pill switch in the app's own chip grammar: a muted track,
/// a sliding primary thumb and one button per segment.
///
/// This is the one control for "which of these lists am I looking at" —
/// Voice/Reels, Discover/Your Reels — so the two places it appears cannot
/// drift into different design systems. Segments share one width, sized to
/// the widest label, so the thumb can slide instead of resizing.
///
/// Every segment is a focusable, keyboard-activatable button with a visible
/// focus ring and `selected` semantics. The selected segment stays focusable
/// (activating it is a no-op) so keyboard traversal never skips a control.
///
/// A segment's tap target is the whole cell, track padding and hairline
/// included — the inset belongs to the sliding thumb, not to the button. That
/// is what lets a 44 px pill carry two 44 px targets instead of two 36 px ones
/// with an untappable margin around them.
class YoSegmentedPill extends StatelessWidget {
  const YoSegmentedPill({
    required this.segments,
    required this.selectedIndex,
    required this.onSelected,
    this.width,
    this.trackPadding = 3,
    this.segmentMinHeight = 38,
    this.iconSize = 17,
    this.fontSize = 13,
    this.labelMaxLines = 1,
    super.key,
  }) : assert(segments.length > 0, 'A segmented pill needs a segment.');

  final List<YoSegmentedPillSegment> segments;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Null shrinks the pill to its content; `double.infinity` stretches it to
  /// the parent. Either way every segment gets the same width.
  final double? width;

  /// How far the sliding thumb is inset from the track's edge. It does not
  /// shrink the tap target: the segment cell still spans the whole track.
  final double trackPadding;

  /// Height of the visible thumb. The pill — and therefore every segment's
  /// target — is this plus twice [trackPadding].
  final double segmentMinHeight;
  final double iconSize;
  final double fontSize;

  /// At accessibility text sizes a stretched pill may let labels wrap rather
  /// than truncate; the compact toolbar keeps one line.
  final int labelMaxLines;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final count = segments.length;
    final clampedIndex = selectedIndex.clamp(0, count - 1);
    final thumbX = count == 1 ? 0.0 : -1 + 2 * clampedIndex / (count - 1);

    Widget body = Stack(
      children: <Widget>[
        // The thumb is what the track padding insets. Drawing it here rather
        // than padding the whole row keeps the buttons full-height.
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.all(trackPadding),
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
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Row(
          children: <Widget>[
            for (var index = 0; index < count; index++)
              Expanded(
                child: _Segment(
                  key: segments[index].key,
                  segment: segments[index],
                  selected: index == clampedIndex,
                  onTap: () => onSelected(index),
                  minHeight: segmentMinHeight + 2 * trackPadding,
                  ringInset: trackPadding,
                  iconSize: iconSize,
                  fontSize: fontSize,
                  maxLines: labelMaxLines,
                ),
              ),
          ],
        ),
      ],
    );
    if (width == null) body = IntrinsicWidth(child: body);

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      // A painted-over hairline instead of a laid-out one: a border that
      // consumed layout space would push the pill past the toolbar row and
      // cost every segment two pixels of target.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: body,
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.segment,
    required this.selected,
    required this.onTap,
    required this.minHeight,
    required this.ringInset,
    required this.iconSize,
    required this.fontSize,
    required this.maxLines,
    super.key,
  });

  final YoSegmentedPillSegment segment;
  final bool selected;
  final VoidCallback onTap;
  final double minHeight;

  /// Keeps the focus ring on the thumb's edge rather than on the track's.
  final double ringInset;
  final double iconSize;
  final double fontSize;
  final int maxLines;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final foreground = selected ? colors.onPrimary : palette.textSecondary;
    final icon = widget.segment.icon;
    return Semantics(
      button: true,
      selected: selected,
      label: widget.segment.semanticLabel ?? widget.segment.label,
      // The node replaces its subtree, so the activation the ink well offers
      // a pointer has to be restated here or assistive technology would face
      // a button it cannot press.
      onTap: widget.onTap,
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
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return (selected
                      ? colors.onPrimary
                      : palette.interactiveForeground)
                  .withValues(alpha: .14);
            }
            if (states.contains(WidgetState.hovered)) {
              return (selected
                      ? colors.onPrimary
                      : palette.interactiveForeground)
                  .withValues(alpha: .07);
            }
            return null;
          }),
          child: Stack(
            children: <Widget>[
              Container(
                constraints: BoxConstraints(minHeight: widget.minHeight),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Icon(icon, size: widget.iconSize, color: foreground),
                      const SizedBox(width: 7),
                    ],
                    Flexible(
                      child: Text(
                        widget.segment.label,
                        maxLines: widget.maxLines,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: foreground,
                          fontSize: widget.fontSize,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: AppMotion.resolve(context, AppMotion.quick),
                    margin: EdgeInsets.all(widget.ringInset),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        // On the primary thumb the palette focus colour is too
                        // close to the fill; the thumb's own foreground stays
                        // visible on it.
                        color: _focused
                            ? (selected ? colors.onPrimary : palette.focus)
                            : Colors.transparent,
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
