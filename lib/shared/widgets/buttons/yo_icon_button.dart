import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';

class YoIconButton extends StatefulWidget {
  const YoIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 48,
    this.iconSize = 22,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.isLoading = false,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final bool isLoading;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;

  @override
  State<YoIconButton> createState() => _YoIconButtonState();
}

class _YoIconButtonState extends State<YoIconButton> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  bool _focused = false;
  bool _hovered = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  String? get _inferredLabel {
    if (widget.icon == Icons.arrow_back_rounded ||
        widget.icon == Icons.arrow_back_ios_new_rounded) {
      return 'Back';
    }
    if (widget.icon == Icons.close_rounded) return 'Close';
    if (widget.icon == Icons.settings_rounded) return 'Settings';
    if (widget.icon == Icons.search_rounded) return 'Search';
    if (widget.icon == Icons.add_rounded) return 'Add';
    if (widget.icon == Icons.more_horiz_rounded ||
        widget.icon == Icons.more_vert_rounded) {
      return 'More options';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focused = _focusNode.hasFocus;
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant YoIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) _focusNode.dispose();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
    _focused = _focusNode.hasFocus;
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted && _focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final targetSize = widget.size < 44 ? 44.0 : widget.size;
    final effectiveLabel =
        widget.semanticLabel ?? widget.tooltip ?? _inferredLabel;
    final foreground = _enabled
        ? widget.foregroundColor ?? palette.textPrimary
        : palette.textTertiary;
    final background = _enabled
        ? widget.backgroundColor ?? palette.surfaceRaised
        : palette.surfaceMuted;
    final border = _focused
        ? palette.focus
        : _hovered && _enabled
        ? palette.interactiveForeground
        : _enabled
        ? widget.borderColor ?? palette.borderStrong
        : palette.border;

    final button = IconButton(
      tooltip: widget.tooltip ?? effectiveLabel,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onPressed: _enabled ? widget.onPressed : null,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: targetSize,
        height: targetSize,
      ),
      splashRadius: targetSize / 2,
      style: ButtonStyle(
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return foreground.withValues(alpha: .16);
          }
          if (states.contains(WidgetState.hovered)) {
            return foreground.withValues(alpha: .08);
          }
          if (states.contains(WidgetState.focused)) {
            return palette.focus.withValues(alpha: .12);
          }
          return null;
        }),
      ),
      icon: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.md,
            border: Border.all(color: border, width: _focused ? 2 : 1),
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: widget.isLoading
                  ? SizedBox(
                      key: const ValueKey('loading'),
                      width: widget.iconSize,
                      height: widget.iconSize,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: foreground,
                      ),
                    )
                  : Icon(
                      widget.icon,
                      key: const ValueKey('icon'),
                      size: widget.iconSize,
                      color: foreground,
                    ),
            ),
          ),
        ),
      ),
    );

    return SizedBox(
      width: targetSize,
      height: targetSize,
      child: Semantics(
        button: true,
        enabled: _enabled,
        label: widget.isLoading && effectiveLabel != null
            ? '$effectiveLabel, loading'
            : effectiveLabel,
        onTap: _enabled ? widget.onPressed : null,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: _enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) {
            if (!_hovered) setState(() => _hovered = true);
          },
          onExit: (_) {
            if (_hovered) setState(() => _hovered = false);
          },
          child: button,
        ),
      ),
    );
  }
}
