import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/media/data/services/gif_message_controller.dart';

/// Shared pending/refused/retry presentation for direct, room and club chat.
/// The pending preview is text only: sending never overrides GIF auto-load.
class YoGifSendStatus extends StatelessWidget {
  const YoGifSendStatus({required this.controller, super.key});
  final GifMessageController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final asset = controller.asset;
      if (asset == null) return const SizedBox.shrink();
      final copy = AppLocalizations.of(context);
      final palette = context.appPalette;
      final status = controller.sending
          ? copy.text('Sending…', 'Wysyłanie…')
          : switch (controller.failure) {
              GifSendFailure.unavailable => copy.text(
                'Unavailable',
                'Niedostępne',
              ),
              GifSendFailure.refused => copy.text(
                'Not allowed yet',
                'Jeszcze niedozwolone',
              ),
              _ => copy.text('Not sent', 'Nie wysłano'),
            };
      return Material(
        color: palette.surfaceRaised,
        child: Padding(
          key: const ValueKey('gif-send-status'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              if (controller.sending)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.gif_box_outlined, color: palette.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      asset.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.textPrimary),
                    ),
                    Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.textPrimary),
                    ),
                  ],
                ),
              ),
              if (controller.canRetry)
                IconButton(
                  tooltip: copy.text('Retry', 'Spróbuj ponownie'),
                  onPressed: controller.retry,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              if (!controller.sending)
                IconButton(
                  tooltip: copy.text('Discard', 'Odrzuć'),
                  onPressed: controller.discard,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
      );
    },
  );
}
