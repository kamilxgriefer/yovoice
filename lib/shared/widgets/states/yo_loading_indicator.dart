import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';

/// A themed replacement for bare `CircularProgressIndicator()` loading
/// screens — fades in instead of popping in instantly, and can carry an
/// optional message so the user isn't left guessing what's loading.
class YoLoadingIndicator extends StatelessWidget {
  const YoLoadingIndicator({super.key, this.message, this.size = 32})
    : _fullscreen = false;

  /// Fills the available space and centers the indicator — the direct
  /// replacement for `Center(child: CircularProgressIndicator())`.
  const YoLoadingIndicator.fullscreen({super.key, this.message})
    : size = 36,
      _fullscreen = true;

  final String? message;
  final double size;
  final bool _fullscreen;

  @override
  Widget build(BuildContext context) {
    final Widget content = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(scale: 0.9 + (0.1 * value), child: child),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: size,
            height: size,
            child: const CircularProgressIndicator(
              strokeWidth: 2.6,
              color: AppColors.primary,
            ),
          ),
          if (message != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium,
            ),
          ],
        ],
      ),
    );

    if (!_fullscreen) return content;

    return Center(child: content);
  }
}
