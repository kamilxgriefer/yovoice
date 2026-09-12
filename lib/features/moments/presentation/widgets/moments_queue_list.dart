import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_progress_ring.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The loaded, authorised neighbours of the Moment a viewer has open.
///
/// This is a HAND-OFF, not a transport queue and not a cache: the feed
/// publishes the pool it has already loaded and filtered for this account,
/// and the expanded player reads it to offer "what else is here". Nothing
/// is fetched for it, no media grant is minted for it (a grant nobody plays
/// is a leaked capability), and nothing in it ever starts playing on its
/// own.
///
/// It is keyed to the viewer: a snapshot published for one account is
/// ignored by any other, and signing out clears it.
@immutable
class MomentNeighbourSnapshot {
  const MomentNeighbourSnapshot({
    required this.viewerUid,
    required this.moments,
  });

  const MomentNeighbourSnapshot.empty() : viewerUid = '', moments = const [];

  final String viewerUid;
  final List<VoiceMoment> moments;

  bool belongsTo(String uid) => viewerUid.isNotEmpty && viewerUid == uid;
}

/// Publishes [MomentNeighbourSnapshot]s from the feed to the expanded
/// player. A [ValueNotifier] rather than a service: it holds no identity of
/// its own, performs no I/O and can be replaced per test.
class MomentNeighbourQueue extends ValueNotifier<MomentNeighbourSnapshot> {
  MomentNeighbourQueue() : super(const MomentNeighbourSnapshot.empty());

  /// The instance production wires up. Tests construct their own.
  static final MomentNeighbourQueue shared = MomentNeighbourQueue();

  void publish({required String viewerUid, required List<VoiceMoment> moments}) {
    value = MomentNeighbourSnapshot(
      viewerUid: viewerUid,
      moments: List<VoiceMoment>.unmodifiable(moments),
    );
  }

  void clear() => value = const MomentNeighbourSnapshot.empty();
}

/// "KOLEJNE MOMENTY" — the local panel's navigation list on the widest
/// layout of board 07.
///
/// It never auto-advances. Selecting an item is the same hand-off the feed
/// already performs: the current recording is released first and the Moment
/// that opens waits for a deliberate play. The active item is the one being
/// listened to and is the ONLY row that shows progress; the rest show the
/// author and the real length of the recording.
class MomentsQueueList extends StatelessWidget {
  const MomentsQueueList({
    required this.current,
    required this.upcoming,
    required this.progress,
    required this.onOpen,
    super.key,
  });

  /// The Moment the player is on. Rendered as the selected row so the list
  /// reads as a position in a list, not as a queue that will play itself.
  final VoiceMoment current;

  /// Already filtered to active, authorised, loaded neighbours.
  final List<VoiceMoment> upcoming;

  /// The same position value the ring, waveform and slider read.
  final ValueListenable<double> progress;

  final ValueChanged<VoiceMoment> onOpen;

  /// The board lists three; the contract caps the hand-off at six so the
  /// panel never becomes a second feed.
  static const int maxItems = 6;
  static const double rowHeight = 56;

  @override
  Widget build(BuildContext context) {
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final items = upcoming.take(maxItems).toList(growable: false);
    return Column(
      key: const ValueKey('moments-queue-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: AppRhythm.section,
            bottom: AppRhythm.tight,
            left: AppRhythm.item,
            right: AppRhythm.item,
          ),
          child: Text(
            copy.text('Next Moments', 'Kolejne Momenty').toUpperCase(),
            style: AppTypography.eyebrow.copyWith(color: palette.textTertiary),
          ),
        ),
        _QueueRow(
          moment: current,
          active: true,
          progress: progress,
          onTap: null,
        ),
        for (final moment in items)
          Padding(
            padding: const EdgeInsets.only(top: AppRhythm.hairline),
            child: _QueueRow(
              moment: moment,
              active: false,
              progress: progress,
              onTap: () => onOpen(moment),
            ),
          ),
      ],
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.moment,
    required this.active,
    required this.progress,
    required this.onTap,
  });

  final VoiceMoment moment;
  final bool active;
  final ValueListenable<double> progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final caption = moment.caption.trim();
    final title = caption.isEmpty
        ? copy.text('Voice Moment', 'Voice Moment')
        : caption;
    final subtitle = '${moment.authorName} · ${_clock(moment.durationSeconds)}';
    final avatar = UserAvatar(
      radius: active ? 14 : 20,
      userId: moment.authorId,
      photoUrl: moment.authorPhotoUrl,
      displayName: moment.authorName,
    );

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppRhythm.item,
        vertical: AppRhythm.tight,
      ),
      child: Row(
        children: [
          if (active)
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (context, value, _) => MomentProgressRing(
                progress: value,
                avatarDiameter: 28,
                strokeWidth: 3,
                child: avatar,
              ),
            )
          else
            SizedBox.square(dimension: 40, child: avatar),
          const SizedBox(width: AppRhythm.item),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.md,
        color: active ? colors.primary.withValues(alpha: .16) : null,
        border: active
            ? Border.all(color: colors.primary.withValues(alpha: .40))
            : null,
      ),
      child: content,
    );

    if (onTap == null) {
      return Semantics(
        selected: true,
        container: true,
        label: copy.template(
          'Now playing: {caption}',
          'Teraz odtwarzasz: {caption}',
          values: <String, Object>{'caption': title},
        ),
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: MomentsQueueList.rowHeight,
            ),
            child: decorated,
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: copy.template(
        'Open Voice Moment: {caption}, {author}',
        'Otwórz Voice Moment: {caption}, {author}',
        values: <String, Object>{
          'caption': title,
          'author': moment.authorName,
        },
      ),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.md,
        child: InkWell(
          key: ValueKey('moments-queue-item-${moment.id}'),
          borderRadius: AppRadius.md,
          onTap: onTap,
          // A minimum, not a fixed height: at a large text scale the row
          // grows instead of clipping the caption it exists to show.
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: MomentsQueueList.rowHeight,
            ),
            child: decorated,
          ),
        ),
      ),
    );
  }
}

String _clock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}
