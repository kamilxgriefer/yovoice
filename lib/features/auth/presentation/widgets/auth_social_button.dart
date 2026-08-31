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
    this.iconSize = 30,
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
          constraints: const BoxConstraints(minHeight: 58),
          child: OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              backgroundColor: AppImmersiveColors.background.withValues(
                alpha: .4,
              ),
              disabledBackgroundColor: AppImmersiveColors.background.withValues(
                alpha: .27,
              ),
              foregroundColor: AppImmersiveColors.textPrimary,
              disabledForegroundColor: AppImmersiveColors.navigationInactive,
              side: BorderSide(
                color: onPressed == null
                    ? AppImmersiveColors.authSocialDisabledBorder
                    : AppImmersiveColors.authSocialBorder,
                width: 1.3,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 25,
                    height: 25,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppImmersiveColors.textPrimary,
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
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
                      const SizedBox(width: 10),
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
                                fontSize: 16,
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
                      const SizedBox(width: 46),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
