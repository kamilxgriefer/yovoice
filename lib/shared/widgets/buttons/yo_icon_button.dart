import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_radius.dart';

class YoIconButton extends StatelessWidget {
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

  bool get _enabled => onPressed != null && !isLoading;

  String? get _inferredLabel {
    if (icon == Icons.arrow_back_rounded ||
        icon == Icons.arrow_back_ios_new_rounded) {
      return 'Back';
    }
    if (icon == Icons.close_rounded) return 'Close';
    if (icon == Icons.settings_rounded) return 'Settings';
    if (icon == Icons.search_rounded) return 'Search';
    if (icon == Icons.add_rounded) return 'Add';
    if (icon == Icons.more_horiz_rounded || icon == Icons.more_vert_rounded) {
      return 'More options';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final targetSize = size < 44 ? 44.0 : size;
    final effectiveLabel = semanticLabel ?? tooltip ?? _inferredLabel;
    final button = IconButton(
      tooltip: tooltip ?? effectiveLabel,
      focusNode: focusNode,
      autofocus: autofocus,
      onPressed: _enabled ? onPressed : null,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: targetSize,
        height: targetSize,
      ),
      splashRadius: targetSize / 2,
      icon: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor ?? AppColors.surface,
            borderRadius: AppRadius.md,
            border: Border.all(color: borderColor ?? AppColors.border),
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: isLoading
                  ? SizedBox(
                      key: const ValueKey('loading'),
                      width: iconSize,
                      height: iconSize,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      icon,
                      key: const ValueKey('icon'),
                      size: iconSize,
                      color: foregroundColor ?? AppColors.textPrimary,
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
        label: effectiveLabel,
        onTap: _enabled ? onPressed : null,
        excludeSemantics: true,
        child: button,
      ),
    );
  }
}
