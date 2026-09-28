import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:yovoice/core/theme/app_palette.dart';

/// Turns an arbitrary visual surface into a complete primary action.
///
/// Unlike a bare gesture recognizer this contributes a button node to the
/// semantics tree, responds to Enter/Space through [InkWell], keeps at least a
/// 44×44 target, and draws a high-contrast focus ring for keyboard users.
class AccessibleTapRegion extends StatefulWidget {
  const AccessibleTapRegion({
    required this.onTap,
    required this.semanticLabel,
    required this.child,
    this.tooltip,
    this.borderRadius = 12,
    this.circular = false,
    this.minimumSize = const Size(44, 44),
    this.selected,
    this.selectedBorderColor,
    this.onHover,
    this.focusContrastColor,
    this.focusNode,
    this.focusRingInsets = EdgeInsets.zero,
    this.onFocusChange,
    this.paintsIndicators = true,
    this.onLongPress,
    this.customSemanticsActions,
    super.key,
  });

  final VoidCallback? onTap;
  final String semanticLabel;
  final String? tooltip;
  final Widget child;
  final double borderRadius;
  final bool circular;
  final Size minimumSize;
  final bool? selected;

  /// The ring drawn while [selected] is true. Defaults to the palette's
  /// interactive foreground; overlays on artwork pass white so the ring stays
  /// visible on any frame, and a control whose selected state is already
  /// carried by its own fill passes [Colors.transparent] to keep the semantic
  /// state without a second visual.
  final Color? selectedBorderColor;
  final ValueChanged<bool>? onHover;

  /// Optional externally-owned focus target for flows that must restore
  /// keyboard focus after replacing content.
  final FocusNode? focusNode;

  /// Optional outer focus color for artwork whose luminance is unknown.
  ///
  /// The default violet ring is sufficient on ordinary app surfaces. Image
  /// cards can supply a dark contrast color to create a black/white two-tone
  /// indicator: at least one edge remains visible on every possible pixel.
  final Color? focusContrastColor;

  /// Draws the ring (focus, hover and selected) this far inside the tap
  /// region's edges instead of on them. A full-bleed region whose edges sit
  /// under the status bar or run through text laid over it (the profile
  /// hero's banner) keeps its ring on the part the user actually sees.
  final EdgeInsets focusRingInsets;

  /// Called when this region gains or loses keyboard focus.
  final ValueChanged<bool>? onFocusChange;

  /// False when the child draws every state itself: no focus, hover or
  /// selected ring on the region's edge and no ink wash or splash. The region
  /// still owns the button semantics, the tooltip, Enter/Space and the
  /// minimum target, and reports hover and focus through [onHover] and
  /// [onFocusChange] so the child can paint them. A control whose visible
  /// shape is smaller than its target (the Moments create ring, a 40 px
  /// circle in a 48 px target) uses this, because a ring on the region's own
  /// edge would touch or crowd the shape it belongs to.
  final bool paintsIndicators;

  /// An optional accelerator on a long press. Never the only path to an
  /// action: whatever it opens must also be reachable by a visible control,
  /// a menu or [customSemanticsActions]. Null leaves the region exactly as
  /// it was without it.
  final VoidCallback? onLongPress;

  /// Extra actions a screen reader offers on this region's node (for
  /// example "See who liked" on a like control). Null leaves the node
  /// exactly as it was without them.
  final Map<CustomSemanticsAction, VoidCallback>? customSemanticsActions;

  @override
  State<AccessibleTapRegion> createState() => _AccessibleTapRegionState();
}

class _AccessibleTapRegionState extends State<AccessibleTapRegion> {
  bool _showsFocusHighlight = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final borderRadius = widget.circular
        ? null
        : BorderRadius.circular(widget.borderRadius);
    final customBorder = widget.circular
        ? const CircleBorder()
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(widget.borderRadius),
          );
    final contrastedFocus = widget.focusContrastColor != null;
    final innerBorderRadius = widget.circular
        ? null
        : BorderRadius.circular(
            (widget.borderRadius - (contrastedFocus ? 2 : 0)).clamp(0, 1000),
          );

    Widget result = Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      enabled: widget.onTap != null,
      selected: widget.selected,
      label: widget.semanticLabel,
      onTap: widget.onTap,
      customSemanticsActions: widget.customSemanticsActions,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          focusNode: widget.focusNode,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onHover: (value) {
            if (_hovered != value) setState(() => _hovered = value);
            widget.onHover?.call(value);
          },
          onFocusChange: (focused) {
            if (_showsFocusHighlight != focused) {
              setState(() => _showsFocusHighlight = focused);
            }
            widget.onFocusChange?.call(focused);
          },
          customBorder: customBorder,
          borderRadius: borderRadius,
          mouseCursor: widget.onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          splashFactory: widget.paintsIndicators
              ? null
              : NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (!widget.paintsIndicators) return Colors.transparent;
            if (states.contains(WidgetState.pressed)) {
              return palette.interactiveForeground.withValues(alpha: .14);
            }
            if (states.contains(WidgetState.hovered)) {
              return palette.interactiveForeground.withValues(alpha: .07);
            }
            if (states.contains(WidgetState.focused)) {
              return palette.focus.withValues(alpha: .1);
            }
            return null;
          }),
          excludeFromSemantics: true,
          child: Stack(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: widget.minimumSize.width,
                  minHeight: widget.minimumSize.height,
                ),
                child: Align(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: widget.child,
                ),
              ),
              if (contrastedFocus && widget.paintsIndicators)
                Positioned.fill(
                  left: widget.focusRingInsets.left,
                  top: widget.focusRingInsets.top,
                  right: widget.focusRingInsets.right,
                  bottom: widget.focusRingInsets.bottom,
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        shape: widget.circular
                            ? BoxShape.circle
                            : BoxShape.rectangle,
                        borderRadius: borderRadius,
                        border: Border.all(
                          color: _showsFocusHighlight
                              ? widget.focusContrastColor!
                              : Colors.transparent,
                          width: 4,
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.paintsIndicators)
                Positioned.fill(
                  left: widget.focusRingInsets.left,
                  top: widget.focusRingInsets.top,
                  right: widget.focusRingInsets.right,
                  bottom: widget.focusRingInsets.bottom,
                  child: IgnorePointer(
                    child: Padding(
                      padding: EdgeInsets.all(contrastedFocus ? 2 : 0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        decoration: BoxDecoration(
                          shape: widget.circular
                              ? BoxShape.circle
                              : BoxShape.rectangle,
                          borderRadius: innerBorderRadius,
                          border: Border.all(
                            color: _showsFocusHighlight
                                ? contrastedFocus
                                      ? Colors.white
                                      : palette.focus
                                : widget.selected == true
                                ? widget.selectedBorderColor ??
                                      palette.interactiveForeground
                                : _hovered && widget.onTap != null
                                ? palette.borderStrong
                                : Colors.transparent,
                            width:
                                _showsFocusHighlight || widget.selected == true
                                ? 2
                                : 1,
                          ),
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

    final tooltip = widget.tooltip?.trim();
    if (tooltip != null && tooltip.isNotEmpty) {
      result = Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: result,
      );
    }
    return result;
  }
}
