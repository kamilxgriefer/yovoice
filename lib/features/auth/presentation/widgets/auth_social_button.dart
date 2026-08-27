import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0x660D0618),
          disabledBackgroundColor: const Color(0x440D0618),
          foregroundColor: Colors.white,
          disabledForegroundColor: const Color(0xFF9189A6),
          side: BorderSide(
            color: onPressed == null
                ? const Color(0xFF46305F)
                : const Color(0xFF6E1FBD),
            width: 1.3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24),
        ),
        child: isLoading
            ? const SizedBox(
                width: 25,
                height: 25,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
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
                                  ? const Color(0xFF9189A6)
                                  : Colors.white,
                            ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: onPressed == null
                            ? const Color(0xFF9189A6)
                            : Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
      ),
    );
  }
}
