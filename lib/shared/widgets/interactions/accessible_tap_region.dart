import 'package:flutter/material.dart';

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

  @override
  State<AccessibleTapRegion> createState() => _AccessibleTapRegionState();
}

class _AccessibleTapRegionState extends State<AccessibleTapRegion> {
  bool _showsFocusHighlight = false;

  @override
  Widget build(BuildContext context) {
    final borderRadius = widget.circular
        ? null
        : BorderRadius.circular(widget.borderRadius);
    final customBorder = widget.circular
        ? const CircleBorder()
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(widget.borderRadius),
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
          onHover: widget.onHover,
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
                            ? const Color(0xFFD28AFF)
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
