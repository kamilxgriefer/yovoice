import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';

/// Shared error state: explains what happened in plain language and, when
/// a retry makes sense, how to fix it. Never interpolates a raw exception
/// — pass the caught [error] and this maps it through [friendlyErrorMessage]
/// automatically, or pass an explicit [message] for a bespoke case.
class YoErrorState extends StatelessWidget {
  const YoErrorState({
    super.key,
    this.error,
    this.message,
    this.onRetry,
    this.compact = false,
  }) : assert(
         error != null || message != null,
         'Provide either error or message.',
       );

  final Object? error;
  final String? message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final String text = message ?? friendlyErrorMessage(error!, copy: copy);
    final palette = context.appPalette;
    final duration = AppMotion.resolve(context, AppMotion.entrance);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: AppMotion.entranceCurve,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: compact ? AppSpacing.lg : AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Semantics(
              container: true,
              liveRegion: true,
              label:
                  '${copy.text('Something went wrong.', 'Coś poszło nie tak.')} $text',
              excludeSemantics: true,
              child: Column(
                children: <Widget>[
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: palette.dangerSurface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.cloud_off_rounded,
                      size: 34,
                      color: palette.dangerForeground,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    copy.text('Something went wrong', 'Coś poszło nie tak'),
                    textAlign: TextAlign.center,
                    style: AppTypography.titleLarge.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              YoButton(
                label: copy.text('Try again', 'Spróbuj ponownie'),
                onPressed: onRetry,
                variant: YoButtonVariant.secondary,
                fullWidth: false,
                height: 48,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
