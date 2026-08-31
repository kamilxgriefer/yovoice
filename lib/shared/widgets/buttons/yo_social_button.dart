import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';

class YoSocialButton extends StatelessWidget {
  const YoSocialButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.svgIconPath,
    this.icon,
    this.iconSize = 28,
    this.isLoading = false,
  }) : assert(
         svgIconPath != null || icon != null,
         'Provide svgIconPath or icon.',
       );

  final String label;
  final VoidCallback? onPressed;
  final String? svgIconPath;
  final IconData? icon;
  final double iconSize;
  final bool isLoading;

  bool get _blocked => onPressed == null || isLoading;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final foreground = _blocked ? palette.textTertiary : palette.textPrimary;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    Widget button = SizedBox(
      width: double.infinity,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: OutlinedButton(
          onPressed: _blocked ? null : onPressed,
          style: ButtonStyle(
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled) && _blocked) {
                return palette.surfaceMuted;
              }
              return palette.surfaceRaised;
            }),
            foregroundColor: WidgetStatePropertyAll(foreground),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return palette.interactiveForeground.withValues(alpha: .14);
              }
              if (states.contains(WidgetState.hovered)) {
                return palette.interactiveForeground.withValues(alpha: .08);
              }
              if (states.contains(WidgetState.focused)) {
                return palette.focus.withValues(alpha: .12);
              }
              return null;
            }),
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.focused)) {
                return BorderSide(color: palette.focus, width: 2);
              }
              if (states.contains(WidgetState.hovered)) {
                return BorderSide(
                  color: palette.interactiveForeground,
                  width: 1.5,
                );
              }
              if (states.contains(WidgetState.disabled) && _blocked) {
                return BorderSide(color: palette.border);
              }
              return BorderSide(color: palette.borderStrong);
            }),
            shape: const WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: AppRadius.lg),
            ),
            minimumSize: const WidgetStatePropertyAll(Size(44, 58)),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: isLoading
                ? SizedBox(
                    key: ValueKey('loading'),
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: foreground,
                    ),
                  )
                : Row(
                    key: const ValueKey('content'),
                    children: [
                      SizedBox(
                        width: 42,
                        child: Center(
                          child: svgIconPath != null
                              ? Opacity(
                                  opacity: _blocked ? .52 : 1,
                                  child: SvgPicture.asset(
                                    svgIconPath!,
                                    width: iconSize,
                                    height: iconSize,
                                  ),
                                )
                              : Icon(icon, size: iconSize, color: foreground),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: textScale >= 1.6 ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AppTypography.titleMedium.copyWith(
                            color: foreground,
                          ),
                        ),
                      ),
                      const SizedBox(width: 42),
                    ],
                  ),
          ),
        ),
      ),
    );

    if (!isLoading) return button;
    return Semantics(
      button: true,
      enabled: false,
      label: '$label, loading',
      excludeSemantics: true,
      child: button,
    );
  }
}
