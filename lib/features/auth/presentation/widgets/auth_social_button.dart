import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';

/// Shared Google/Apple control used by both authentication entry points.
///
/// Social authentication signs an existing user in and provisions a new
/// account when the provider identity has not been seen before, so Login and
/// Register must expose the exact same actions and loading/disabled states.
class AuthSocialButton extends StatelessWidget {
  const AuthSocialButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.svgIconPath,
    this.materialIcon,
    this.iconSize = 22,
    this.isLoading = false,
    this.statusLabel,
  }) : assert(
         svgIconPath != null || materialIcon != null,
         'An SVG icon path or Material icon must be provided.',
       );

  final String label;
  final VoidCallback? onPressed;
  final String? svgIconPath;
  final IconData? materialIcon;
  final double iconSize;
  final bool isLoading;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: label,
      value: isLoading ? copy.text('Loading', 'Ładowanie') : statusLabel,
      liveRegion: isLoading,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minHeight),
          child: OutlinedButton(
            onPressed: onPressed,
            // Slim: 48 px minimum, surface fill, 1 px outline from the
            // authSocial* roles, radius 12. `side` is a state property so the
            // keyboard focus boundary (2 px authFocus) is not lost to a static
            // border, which is what a plain `styleFrom(side:)` would do.
            style: OutlinedButton.styleFrom(
              backgroundColor: AppImmersiveColors.surface,
              disabledBackgroundColor: AppImmersiveColors.surface,
              foregroundColor: AppImmersiveColors.textPrimary,
              disabledForegroundColor: AppImmersiveColors.navigationInactive,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            ).copyWith(side: WidgetStateProperty.resolveWith(_resolveSide)),
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppImmersiveColors.textPrimary,
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: _iconBox,
                        height: _iconBox,
                        child: Center(
                          child: svgIconPath != null
                              ? SvgPicture.asset(
                                  svgIconPath!,
                                  width: iconSize,
                                  height: iconSize,
                                  fit: BoxFit.contain,
                                )
                              : Icon(
                                  materialIcon,
                                  size: iconSize,
                                  color: onPressed == null
                                      ? AppImmersiveColors.navigationInactive
                                      : AppImmersiveColors.textPrimary,
                                ),
                        ),
                      ),
                      const SizedBox(width: _iconGap),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: onPressed == null
                                    ? AppImmersiveColors.navigationInactive
                                    : AppImmersiveColors.textPrimary,
                                fontSize: 15,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (statusLabel != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                statusLabel!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: onPressed == null
                                      ? AppImmersiveColors.authTextTertiary
                                      : AppImmersiveColors.textSecondary,
                                  fontSize: 11.5,
                                  height: 1.2,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Mirrors the icon column so the label stays centred.
                      const SizedBox(width: _iconBox + _iconGap),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Minimum height; a `statusLabel` grows the control to its content.
  static const double minHeight = 48;
  static const double _iconBox = 28;
  static const double _iconGap = 8;

  static BorderSide _resolveSide(Set<WidgetState> states) {
    if (states.contains(WidgetState.focused)) {
      return const BorderSide(color: AppImmersiveColors.authFocus, width: 2);
    }
    if (states.contains(WidgetState.disabled)) {
      return const BorderSide(
        color: AppImmersiveColors.authSocialDisabledBorder,
      );
    }
    return const BorderSide(color: AppImmersiveColors.authSocialBorder);
  }
}
