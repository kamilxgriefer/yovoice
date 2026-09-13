import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart';

/// `0:06`. Seconds are always two digits so a row of times never jitters.
String reelClockLabel(Duration value) {
  final total = value.inSeconds < 0 ? 0 : value.inSeconds;
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// How far a Reel has played, as a bar.
///
/// One source of truth: the bar, the labels beside it and the spoken value
/// all read the coordinator's own clock (`ReelPlaybackCoordinator.position`).
/// That clock is a [ValueListenable] rather than a notifier tick, and every
/// piece here sits under a [RepaintBoundary], so a running Reel repaints the
/// bar alone and never rebuilds the card around it (spec §9 line 167).
///
/// Colour never carries the meaning on its own: the same fact is the bar's
/// length, the numeric labels of [ReelProgressTimes], and the spoken value.
class ReelProgressBar extends StatelessWidget {
  const ReelProgressBar({
    required this.position,
    required this.total,
    this.onMedia = true,
    super.key,
  });

  /// The engine clock, in timeline units (0 → [total]).
  final ValueListenable<Duration> position;

  /// The published timeline length. Zero while it is not known yet, which
  /// leaves the track empty instead of inventing a full bar.
  final Duration total;

  /// True while the bar is drawn over footage of unknown luminance, which
  /// decides the unplayed track: white at 32 % over media, a semantic tint
  /// on an app surface.
  final bool onMedia;

  static const double trackHeight = 4;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final unplayed = onMedia
        ? Colors.white.withValues(alpha: .32)
        : palette.textPrimary.withValues(alpha: .20);
    return RepaintBoundary(
      child: ValueListenableBuilder<Duration>(
        valueListenable: position,
        builder: (context, value, _) {
          final fraction = total.inMilliseconds <= 0
              ? 0.0
              : (value.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
          return Semantics(
            container: true,
            label: copy.contextualText(
              'reels.playbackPosition',
              'Playback position',
              'Pozycja odtwarzania',
            ),
            value: copy.template(
              '{position} of {total}',
              '{position} z {total}',
              values: <String, Object>{
                'position': reelClockLabel(value),
                'total': reelClockLabel(total),
              },
            ),
            excludeSemantics: true,
            child: ClipRRect(
              key: const ValueKey<String>('reel-progress-bar'),
              borderRadius: BorderRadius.circular(trackHeight / 2),
              child: SizedBox(
                height: trackHeight,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(child: ColoredBox(color: unplayed)),
                    FractionallySizedBox(
                      widthFactor: fraction,
                      alignment: AlignmentDirectional.centerStart,
                      child: ColoredBox(color: palette.audioAccent),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// `0:06 / 0:18` — the same clock as [ReelProgressBar], in numbers.
///
/// The bar already carries the spoken value, so these are excluded from
/// semantics: one announcement per fact.
class ReelProgressTimes extends StatelessWidget {
  const ReelProgressTimes({
    required this.position,
    required this.total,
    this.onMedia = true,
    super.key,
  });

  final ValueListenable<Duration> position;
  final Duration total;
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final totalLabel = reelClockLabel(total);
    return RepaintBoundary(
      child: ExcludeSemantics(
        child: ValueListenableBuilder<Duration>(
          valueListenable: position,
          builder: (context, value, _) => Text(
            '${reelClockLabel(value)} / $totalLabel',
            key: const ValueKey<String>('reel-progress-times'),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: onMedia ? Colors.white : palette.textSecondary,
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              shadows: onMedia ? overlayTextShadows : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar and its times on one line: the shape the stage uses at the widths
/// where the frame has room for both inside its bottom inset.
class ReelProgressRow extends StatelessWidget {
  const ReelProgressRow({
    required this.position,
    required this.total,
    this.onMedia = true,
    super.key,
  });

  final ValueListenable<Duration> position;
  final Duration total;
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        // On a frame this narrow the times would take the whole line and
        // leave no bar at all. The bar keeps the spoken value either way, so
        // the numbers are what gives way — never the progress itself.
        final showTimes =
            !constraints.hasBoundedWidth || constraints.maxWidth >= 160 * scale;
        return Row(
          key: const ValueKey<String>('reel-progress-row'),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: ReelProgressBar(
                position: position,
                total: total,
                onMedia: onMedia,
              ),
            ),
            if (showTimes) ...<Widget>[
              const SizedBox(width: 12),
              Flexible(
                child: ReelProgressTimes(
                  position: position,
                  total: total,
                  onMedia: onMedia,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
