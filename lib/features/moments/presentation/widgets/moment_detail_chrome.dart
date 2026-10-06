import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';

/// The Voice Moment detail's own top row: Back, the page name and — when the
/// Moment can be shared — Share. Shared with the link destination, whose
/// loading and unavailable states carry the same row without Share.
class MomentDetailHeader extends StatelessWidget {
  const MomentDetailHeader({required this.onBack, this.onShare, super.key});

  final VoidCallback onBack;

  /// Null where there is nothing to share (a link that did not resolve).
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('moment-detail-back'),
            onPressed: onBack,
            tooltip: copy.text('Back', 'Wstecz'),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(AppSizing.standardControlHeight),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            icon: Icon(Icons.arrow_back_rounded, color: palette.textPrimary),
          ),
          const SizedBox(width: AppRhythm.hairline),
          Expanded(
            child: Text(
              copy.text('Voice Moment', 'Voice Moment'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleLarge.copyWith(
                color: palette.textPrimary,
              ),
            ),
          ),
          if (onShare != null)
            IconButton(
              key: const ValueKey('moment-detail-share-top'),
              onPressed: onShare,
              tooltip: copy.text('Share this Moment', 'Udostępnij ten Moment'),
              style: IconButton.styleFrom(
                minimumSize: const Size.square(AppSizing.standardControlHeight),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              icon: Icon(Icons.share_outlined, color: palette.textPrimary),
            ),
        ],
      ),
    );
  }
}

/// The gone-state of one Voice Moment: expired, deleted, or never loaded. A
/// real explanation and a way back. The detail screen shows it in place of
/// the player; a `?moment=` link that does not resolve shows it on its own.
class MomentGoneCard extends StatelessWidget {
  const MomentGoneCard({required this.onBack, this.backFocusNode, super.key});

  final VoidCallback onBack;
  final FocusNode? backFocusNode;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Container(
      key: const ValueKey('moment-detail-gone'),
      decoration: AppFinish.block(
        palette,
        highContrast: MediaQuery.highContrastOf(context),
      ),
      padding: const EdgeInsets.all(AppRhythm.section),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            copy.text('Voice Moment', 'Voice Moment').toUpperCase(),
            style: AppTypography.eyebrow.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppRhythm.item),
          Icon(
            Icons.timer_off_outlined,
            size: 34,
            color: palette.textSecondary,
          ),
          const SizedBox(height: AppRhythm.item),
          Text(
            copy.text(
              'This Moment is no longer available',
              'Ten Moment nie jest już dostępny',
            ),
            textAlign: TextAlign.center,
            style: AppTypography.titleLarge.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppRhythm.tight),
          Text(
            copy.text(
              'It reached the end of its availability or was deleted by '
                  'its author.',
              'Minął czas jego dostępności lub autor go usunął.',
            ),
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: palette.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppRhythm.title),
          FilledButton(
            key: const ValueKey('moment-detail-gone-back'),
            focusNode: backFocusNode,
            onPressed: onBack,
            child: Text(copy.text('Back to Moments', 'Wróć do Momentów')),
          ),
        ],
      ),
    );
  }
}
