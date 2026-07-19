import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_radius.dart';

enum YoButtonVariant { primary, secondary, outline, danger }

enum YoButtonSize { small, medium, large }

class YoButton extends StatefulWidget {
  const YoButton({
    required this.text,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    this.size = YoButtonSize.large,
    super.key,
  }) : variant = YoButtonVariant.primary;

  const YoButton.secondary({
    required this.text,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    this.size = YoButtonSize.large,
    super.key,
  }) : variant = YoButtonVariant.secondary;

  const YoButton.outline({
    required this.text,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    this.size = YoButtonSize.large,
    super.key,
  }) : variant = YoButtonVariant.outline;

  const YoButton.danger({
    required this.text,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    this.size = YoButtonSize.large,
    super.key,
  }) : variant = YoButtonVariant.danger;

  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expand;
  final YoButtonSize size;
  final YoButtonVariant variant;

  bool get isDisabled => onPressed == null || isLoading;

  @override
  State<YoButton> createState() => _YoButtonState();
}

class _YoButtonState extends State<YoButton> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails details) {
    if (widget.isDisabled) {
      return;
    }

    setState(() {
      _isPressed = true;
    });
  }

  void _handleTapUp(TapUpDetails details) {
    if (!_isPressed) {
      return;
    }

    setState(() {
      _isPressed = false;
    });
  }

  void _handleTapCancel() {
    if (!_isPressed) {
      return;
    }

    setState(() {
      _isPressed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dimensions = _YoButtonDimensions.fromSize(widget.size);

    final button = AnimatedScale(
      scale: _isPressed ? 0.975 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: widget.isDisabled && !widget.isLoading ? 0.52 : 1,
        duration: const Duration(milliseconds: 180),
        child: Container(
          height: dimensions.height,
          constraints: BoxConstraints(
            minWidth: widget.expand ? double.infinity : dimensions.minWidth,
          ),
          decoration: _buildDecoration(),
          child: Material(
            color: Colors.transparent,
            borderRadius: AppRadius.lg,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.isDisabled ? null : widget.onPressed,
              onTapDown: _handleTapDown,
              onTapUp: _handleTapUp,
              onTapCancel: _handleTapCancel,
              borderRadius: AppRadius.lg,
              splashColor: Colors.white.withValues(alpha: 0.10),
              highlightColor: Colors.white.withValues(alpha: 0.04),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: dimensions.horizontalPadding,
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: widget.isLoading
                        ? SizedBox(
                            key: const ValueKey<String>('loader'),
                            width: dimensions.loaderSize,
                            height: dimensions.loaderSize,
                            child: CircularProgressIndicator(
                              strokeWidth: dimensions.loaderStrokeWidth,
                              color: _foregroundColor,
                            ),
                          )
                        : _YoButtonContent(
                            key: const ValueKey<String>('content'),
                            text: widget.text,
                            icon: widget.icon,
                            fontSize: dimensions.fontSize,
                            iconSize: dimensions.iconSize,
                            foregroundColor: _foregroundColor,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.expand) {
      return SizedBox(width: double.infinity, child: button);
    }

    return IntrinsicWidth(child: button);
  }

  BoxDecoration _buildDecoration() {
    switch (widget.variant) {
      case YoButtonVariant.primary:
        return BoxDecoration(
          gradient: AppGradients.primary,
          borderRadius: AppRadius.lg,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.38),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        );

      case YoButtonVariant.secondary:
        return BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.lg,
          border: Border.all(color: AppColors.border, width: 1.2),
        );

      case YoButtonVariant.outline:
        return BoxDecoration(
          color: Colors.transparent,
          borderRadius: AppRadius.lg,
          border: Border.all(color: AppColors.primary, width: 1.4),
        );

      case YoButtonVariant.danger:
        return BoxDecoration(
          color: AppColors.error,
          borderRadius: AppRadius.lg,
          boxShadow: [
            BoxShadow(
              color: AppColors.error.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        );
    }
  }

  Color get _foregroundColor {
    switch (widget.variant) {
      case YoButtonVariant.primary:
      case YoButtonVariant.danger:
        return Colors.white;

      case YoButtonVariant.secondary:
        return AppColors.textPrimary;

      case YoButtonVariant.outline:
        return AppColors.primary;
    }
  }
}

class _YoButtonContent extends StatelessWidget {
  const _YoButtonContent({
    required this.text,
    required this.fontSize,
    required this.iconSize,
    required this.foregroundColor,
    this.icon,
    super.key,
  });

  final String text;
  final IconData? icon;
  final double fontSize;
  final double iconSize;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: foregroundColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: iconSize, color: foregroundColor),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foregroundColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}

class _YoButtonDimensions {
  const _YoButtonDimensions({
    required this.height,
    required this.minWidth,
    required this.horizontalPadding,
    required this.fontSize,
    required this.iconSize,
    required this.loaderSize,
    required this.loaderStrokeWidth,
  });

  factory _YoButtonDimensions.fromSize(YoButtonSize size) {
    switch (size) {
      case YoButtonSize.small:
        return const _YoButtonDimensions(
          height: 42,
          minWidth: 96,
          horizontalPadding: 18,
          fontSize: 14,
          iconSize: 18,
          loaderSize: 19,
          loaderStrokeWidth: 2,
        );

      case YoButtonSize.medium:
        return const _YoButtonDimensions(
          height: 50,
          minWidth: 120,
          horizontalPadding: 22,
          fontSize: 16,
          iconSize: 21,
          loaderSize: 22,
          loaderStrokeWidth: 2.2,
        );

      case YoButtonSize.large:
        return const _YoButtonDimensions(
          height: 58,
          minWidth: 140,
          horizontalPadding: 26,
          fontSize: 18,
          iconSize: 23,
          loaderSize: 25,
          loaderStrokeWidth: 2.5,
        );
    }
  }

  final double height;
  final double minWidth;
  final double horizontalPadding;
  final double fontSize;
  final double iconSize;
  final double loaderSize;
  final double loaderStrokeWidth;
}
