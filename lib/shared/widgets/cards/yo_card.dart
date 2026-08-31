import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';

class YoCard extends StatefulWidget {
  const YoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final bool selected;

  @override
  State<YoCard> createState() => _YoCardState();
}

class _YoCardState extends State<YoCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final interactive = widget.onTap != null;
    final borderColor = _focused
        ? palette.focus
        : widget.selected
        ? palette.interactiveForeground
        : _hovered && interactive
        ? palette.borderStrong
        : palette.border;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      margin: widget.margin,
      decoration: BoxDecoration(
        color: widget.selected
            ? Color.lerp(palette.surface, palette.focus, .08)
            : palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(
          color: borderColor,
          width: _focused || widget.selected ? 2 : 1,
        ),
        boxShadow: _hovered && interactive
            ? <BoxShadow>[
                BoxShadow(
                  color: palette.shadow.withValues(alpha: .12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: interactive
          ? Material(
              color: Colors.transparent,
              borderRadius: AppRadius.lg,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                onFocusChange: (value) {
                  if (_focused != value) setState(() => _focused = value);
                },
                onHover: (value) {
                  if (_hovered != value) setState(() => _hovered = value);
                },
                overlayColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.pressed)) {
                    return palette.interactiveForeground.withValues(alpha: .14);
                  }
                  if (states.contains(WidgetState.hovered)) {
                    return palette.interactiveForeground.withValues(alpha: .06);
                  }
                  if (states.contains(WidgetState.focused)) {
                    return palette.focus.withValues(alpha: .08);
                  }
                  return null;
                }),
                child: Padding(padding: widget.padding, child: widget.child),
              ),
            )
          : Padding(padding: widget.padding, child: widget.child),
    );

    if (!interactive) return card;
    return Semantics(button: true, selected: widget.selected, child: card);
  }
}
