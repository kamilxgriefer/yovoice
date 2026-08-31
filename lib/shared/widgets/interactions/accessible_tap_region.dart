import 'package:flutter/material.dart';

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
    this.onHover,
    this.focusContrastColor,
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
  final ValueChanged<bool>? onHover;

  /// Optional outer focus color for artwork whose luminance is unknown.
  ///
  /// The default violet ring is sufficient on ordinary app surfaces. Image
  /// cards can supply a dark contrast color to create a black/white two-tone
  /// indicator: at least one edge remains visible on every possible pixel.
  final Color? focusContrastColor;

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
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (value) {
            if (_hovered != value) setState(() => _hovered = value);
            widget.onHover?.call(value);
          },
          onFocusChange: (focused) {
            if (_showsFocusHighlight != focused) {
              setState(() => _showsFocusHighlight = focused);
            }
          },
          customBorder: customBorder,
          borderRadius: borderRadius,
          mouseCursor: widget.onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          overlayColor: WidgetStateProperty.resolveWith((states) {
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
              if (contrastedFocus)
                Positioned.fill(
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
              Positioned.fill(
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
                              ? palette.interactiveForeground
                              : _hovered && widget.onTap != null
                              ? palette.borderStrong
                              : Colors.transparent,
                          width: _showsFocusHighlight || widget.selected == true
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
