import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';

class YoGlassCard extends StatefulWidget {
  const YoGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.onTap,
    this.blur = 18,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double blur;
  final bool selected;

  @override
  State<YoGlassCard> createState() => _YoGlassCardState();
}

class _YoGlassCardState extends State<YoGlassCard> {
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
    final surface = widget.selected
        ? Color.lerp(palette.surface, palette.focus, .1)!
        : palette.surface;

    Widget body = Padding(padding: widget.padding, child: widget.child);
    if (interactive) {
      body = Material(
        color: Colors.transparent,
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
          child: body,
        ),
      );
    }

    final content = Container(
      margin: widget.margin,
      child: ClipRRect(
        borderRadius: AppRadius.lg,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: surface.withValues(alpha: .92),
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
            child: body,
          ),
        ),
      ),
    );

    if (!interactive) return content;
    return Semantics(button: true, selected: widget.selected, child: content);
  }
}
