/// The dense presentation pieces the Discover surface is built from.
///
/// Before this file the feed drew one 236 x 210 cover slab per featured
/// Moment in a horizontal rail — a card that was mostly decorative
/// gradient, of which a phone showed about one and a half — and one
/// bordered card per Moment in the recent list. A tester saw two or three
/// blocks and nothing else. These widgets replace that with a compact
/// featured grid and a tight list row, and they carry the SAME
/// heard/unheard language the story tiles use so a Moment already listened
/// to reads as heard everywhere.
///
/// Nothing here invents a number. Every count is the document's own
/// counter and is printed only when it is greater than zero; there is no
/// play counter in the schema, so none is drawn.
library;

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// An author avatar wearing the Moments seen/unseen ring.
///
/// THE RING IS THE STATE, exactly as on [MomentStoryTile]: a brand
/// gradient means this account has not heard the Moment yet, a flat quiet
/// line plus a dimmed avatar means it has. The stops come from
/// [MomentStoryTile.ringColors], so the two surfaces cannot drift apart.
/// Unknown viewed state renders as UNSEEN (fail open) because that is what
/// the caller passes when the `momentViews` listener has not emitted.
class MomentSeenAvatar extends StatelessWidget {
  const MomentSeenAvatar({
    required this.seen,
    required this.diameter,
    this.userId,
    this.photoUrl,
    this.displayName,
    super.key,
  });

  final bool seen;
  final double diameter;
  final String? userId;
  final String? photoUrl;
  final String? displayName;

  static const double ringWidth = 2;
  static const double ringInset = 1.5;

  /// The heard/unheard phrase a surface appends to its own semantic label
  /// — word for word the one [MomentStoryTile] appends, so a screen reader
  /// hears one vocabulary across the whole feature.
  static String stateLabel(BuildContext context, {required bool seen}) {
    final copy = AppLocalizations.of(context);
    return seen
        ? copy.text('already heard', 'odsłuchane')
        : copy.text('not heard yet', 'nieodsłuchane');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      width: diameter,
      height: diameter,
      padding: const EdgeInsets.all(ringWidth),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // One gradient in both states so the geometry cannot shift when a
        // Moment flips from unheard to heard; only the stops change.
        gradient: seen
            ? LinearGradient(
                colors: MomentStoryTile.ringColors(context, seen: true),
              )
            : AppGradients.primary,
      ),
      child: Container(
        padding: const EdgeInsets.all(ringInset),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.surfaceSunken,
        ),
        child: Opacity(
          opacity: seen ? .62 : 1,
          // The initial inside an avatar is a GRAPHIC sized off the disc,
          // never copy: at 200 % text it grows past the circle and is
          // clipped mid-glyph. The labels around it scale normally.
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.noScaling),
            child: UserAvatar(
              radius: (diameter - (ringWidth + ringInset) * 2) / 2,
              userId: userId,
              photoUrl: photoUrl,
              displayName: displayName,
            ),
          ),
        ),
      ),
    );
  }
}

/// The round transport control. [playing] is the caller's REAL playback
/// state — the wide detail panel's player — so a Moment being played shows
/// a pause glyph instead of pretending it is idle.
class MomentPlayControl extends StatelessWidget {
  const MomentPlayControl({
    required this.playing,
    required this.enabled,
    required this.onTap,
    required this.diameter,
    required this.controlKey,
    super.key,
  });

  final bool playing;
  final bool enabled;
  final VoidCallback onTap;
  final double diameter;
  final Key controlKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final label = !enabled
        ? copy.text('Still uploading', 'Nadal przesyłamy')
        : playing
        ? copy.text('Pause this Moment', 'Wstrzymaj ten Moment')
        : copy.text('Play this Moment', 'Odtwórz ten Moment');
    return Semantics(
      button: enabled,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: colors.primary.withValues(alpha: enabled ? 1 : .25),
          shape: const CircleBorder(),
          child: InkWell(
            key: controlKey,
            onTap: enabled ? onTap : null,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: diameter,
              height: diameter,
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: diameter * .62,
                color: colors.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The recent list's leading control: the author's seen-ringed avatar with
/// the transport badge on it. One 44 pt target, so the row does not have to
/// spend a second 40 pt column on a separate play button.
class MomentAvatarPlayControl extends StatelessWidget {
  const MomentAvatarPlayControl({
    required this.moment,
    required this.seen,
    required this.playing,
    required this.enabled,
    required this.onTap,
    required this.controlKey,
    this.diameter = 44,
    super.key,
  });

  final VoiceMoment moment;
  final bool seen;
  final bool playing;
  final bool enabled;
  final VoidCallback onTap;
  final Key controlKey;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    final badge = diameter * .42;
    final label = !enabled
        ? copy.text('Still uploading', 'Nadal przesyłamy')
        : playing
        ? copy.text('Pause this Moment', 'Wstrzymaj ten Moment')
        : copy.text('Play this Moment', 'Odtwórz ten Moment');
    return Semantics(
      button: enabled,
      label: '$label, ${MomentSeenAvatar.stateLabel(context, seen: seen)}',
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: diameter,
          height: diameter,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              key: controlKey,
              onTap: enabled ? onTap : null,
              customBorder: const CircleBorder(),
              child: Stack(
                children: [
                  MomentSeenAvatar(
                    seen: seen,
                    diameter: diameter,
                    userId: moment.authorId,
                    photoUrl: moment.authorPhotoUrl,
                    displayName: moment.authorName,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: badge,
                      height: badge,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.primary.withValues(
                          alpha: enabled ? 1 : .35,
                        ),
                        border: Border.all(
                          color: palette.surfaceSunken,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: badge * .66,
                        color: colors.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Details, plus Delete on the caller's OWN Moment or Report on somebody
/// else's. One definition, used by the featured grid and the recent list,
/// so an action can never exist on one and be missing from the other.
///
/// [keyPrefix] keeps the keys unique when the same Moment is on screen
/// twice — a featured Moment is also a row in the list underneath.
class MomentOverflowMenu extends StatelessWidget {
  const MomentOverflowMenu({
    required this.moment,
    required this.isOwn,
    required this.uploading,
    required this.keyPrefix,
    required this.onOpenDetail,
    required this.onReport,
    required this.onDelete,
    this.iconSize = 20,
    super.key,
  });

  final VoiceMoment moment;
  final bool isOwn;

  /// A draft still on its way up. Details is withheld for it: the detail
  /// page's gone-check reads any unpublished doc as "reached the end of
  /// its availability", which would tell an author mid-upload that their
  /// brand-new Moment was deleted.
  final bool uploading;
  final String keyPrefix;
  final VoidCallback onOpenDetail;
  final VoidCallback onReport;
  final VoidCallback onDelete;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      key: ValueKey('$keyPrefix-menu-${moment.id}'),
      tooltip: copy.text('More', 'Więcej'),
      color: palette.surfaceRaised,
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.more_vert_rounded,
        size: iconSize,
        color: palette.textSecondary,
      ),
      onSelected: (value) {
        if (value == 'details') onOpenDetail();
        if (value == 'report') onReport();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (context) => [
        if (!uploading)
          PopupMenuItem<String>(
            key: ValueKey('$keyPrefix-details-${moment.id}'),
            value: 'details',
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  copy.text('Details', 'Szczegóły'),
                  style: TextStyle(color: palette.textPrimary),
                ),
              ],
            ),
          ),
        // Delete on OWN Moments only — the author's exit, and for a
        // permanent Moment the only one. Report only on others':
        // reporting yourself is not a real intent.
        if (isOwn)
          PopupMenuItem<String>(
            key: ValueKey('$keyPrefix-delete-${moment.id}'),
            value: 'delete',
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: colors.error,
                ),
                const SizedBox(width: 8),
                Text(
                  copy.text('Delete', 'Usuń'),
                  style: TextStyle(color: colors.error),
                ),
              ],
            ),
          )
        else
          PopupMenuItem<String>(
            key: ValueKey('$keyPrefix-report-${moment.id}'),
            value: 'report',
            child: Row(
              children: [
                Icon(
                  Icons.flag_outlined,
                  size: 18,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  copy.text('Report', 'Zgłoś'),
                  style: TextStyle(color: palette.textPrimary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One real counter with its icon. Renders nothing at all for zero: an
/// invented "0" is the kind of fake activity this project refuses.
class MomentCountChip extends StatelessWidget {
  const MomentCountChip({
    required this.count,
    required this.icon,
    required this.semanticLabel,
    required this.tint,
    this.fontSize = 11.5,
    super.key,
  });

  final int count;
  final IconData icon;
  final String semanticLabel;
  final Color tint;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: fontSize, color: tint),
          const SizedBox(width: 3),
          Text(
            '$count',
            maxLines: 1,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// How many featured tiles sit side by side in [width] logical pixels.
///
/// Decided on the width the grid actually receives, never on a device
/// label, and divided down when the reader's text preference means each
/// tile needs the room two of them would otherwise split — at 200 % text a
/// two-up grid is two columns of clipped words, so it becomes one.
int momentFeaturedColumns(double width, {double textScale = 1}) {
  final effective = width / (textScale > 1.35 ? 2 : 1);
  if (effective >= 900) return 4;
  if (effective >= 620) return 3;
  // 340 is measured, not guessed: two-up below it leaves each cell about
  // 130 pt, which cannot hold a 44 pt transport target, a duration and two
  // counters without shrinking them. A 320 pt phone therefore gets one
  // full-width compact tile rather than two broken ones.
  if (effective >= 340) return 2;
  return 1;
}

/// The compact featured cell: identity, one caption line, the transport,
/// the real duration and the real counters, plus the same overflow menu
/// the list rows carry.
class MomentFeaturedTile extends StatelessWidget {
  const MomentFeaturedTile({
    required this.moment,
    required this.seen,
    required this.playing,
    required this.isOwn,
    required this.onTap,
    required this.onPlay,
    required this.onOpenDetail,
    required this.onReport,
    required this.onDelete,
    super.key,
  });

  final VoiceMoment moment;
  final bool seen;
  final bool playing;
  final bool isOwn;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback onOpenDetail;
  final VoidCallback onReport;
  final VoidCallback onDelete;

  bool get _uploading => !moment.isPublished;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label:
          '${copy.template('Featured Moment by {name}', 'Polecany Moment użytkownika {name}', values: {'name': moment.authorName})}, '
          '${MomentSeenAvatar.stateLabel(context, seen: seen)}',
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 2, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Identity and the overflow share the top line; the
                // caption gets a line of its OWN below them. Stacking the
                // caption beside the avatar left it about 70 pt wide in a
                // two-up cell — "A delibera…" — which teases nothing.
                Row(
                  children: [
                    MomentSeenAvatar(
                      seen: seen,
                      diameter: 32,
                      userId: moment.authorId,
                      photoUrl: moment.authorPhotoUrl,
                      displayName: moment.authorName,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        moment.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          // Heard stays readable: it is quieter through
                          // the ring and the dimmed avatar, never through
                          // copy nobody can make out.
                          color: seen
                              ? palette.textSecondary
                              : palette.textPrimary,
                          fontSize: 12.5,
                          height: 1.25,
                          fontWeight: seen ? FontWeight.w600 : FontWeight.w700,
                        ),
                      ),
                    ),
                    MomentOverflowMenu(
                      moment: moment,
                      isOwn: isOwn,
                      uploading: _uploading,
                      keyPrefix: 'moment-featured',
                      iconSize: 18,
                      onOpenDetail: onOpenDetail,
                      onReport: onReport,
                      onDelete: onDelete,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 8),
                  child: Text(
                    moment.caption.trim().isEmpty
                        ? copy.text('Voice Moment', 'Voice Moment')
                        : moment.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textTertiary,
                      fontSize: 11.5,
                      height: 1.25,
                    ),
                  ),
                ),
                Row(
                  children: [
                    MomentPlayControl(
                      controlKey: ValueKey('moment-featured-play-${moment.id}'),
                      playing: playing,
                      enabled: !_uploading,
                      onTap: onPlay,
                      diameter: 40,
                    ),
                    const SizedBox(width: 8),
                    // Scaled down rather than clipped: a two-up cell on a
                    // small phone can be narrower than "10:05" plus two
                    // four-digit counters, and a shrunk-but-whole number
                    // beats a truncated one or an overflow stripe.
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerEnd,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_uploading)
                              Text(
                                copy.text('Uploading…', 'Przesyłanie…'),
                                style: TextStyle(
                                  color: palette.textTertiary,
                                  fontSize: 11.5,
                                ),
                              )
                            else if (moment.durationSeconds > 0)
                              Text(
                                moment.durationLabel,
                                maxLines: 1,
                                style: TextStyle(
                                  color: palette.textTertiary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (moment.likeCount > 0) ...[
                              const SizedBox(width: 10),
                              MomentCountChip(
                                count: moment.likeCount,
                                icon: Icons.favorite_rounded,
                                tint: AppColors.secondary,
                                fontSize: 11,
                                semanticLabel: copy.template(
                                  '{count} likes',
                                  'Polubienia: {count}',
                                  values: {'count': moment.likeCount},
                                ),
                              ),
                            ],
                            if (moment.commentCount > 0) ...[
                              const SizedBox(width: 10),
                              MomentCountChip(
                                count: moment.commentCount,
                                icon: Icons.mode_comment_rounded,
                                tint: palette.textSecondary,
                                fontSize: 11,
                                semanticLabel: copy.template(
                                  '{count} comments',
                                  'Komentarze: {count}',
                                  values: {'count': moment.commentCount},
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The featured section: engagement-ranked Moments laid out as an
/// equal-height grid whose column count comes from
/// [momentFeaturedColumns].
///
/// A grid rather than the old horizontal rail because a rail showed about
/// one and a half of four cards on a phone and hid the rest behind a
/// gesture nothing advertised. [IntrinsicHeight] equalises a row's cells
/// instead of a hard-coded height: a fixed height is what clipped the
/// caption at a 2x text scale before.
class MomentFeaturedGrid extends StatelessWidget {
  const MomentFeaturedGrid({
    required this.moments,
    required this.viewedIds,
    required this.currentUserId,
    required this.playingId,
    required this.isPlaying,
    required this.onTap,
    required this.onPlay,
    required this.onOpenDetail,
    required this.onReport,
    required this.onDelete,
    super.key,
  });

  final List<VoiceMoment> moments;
  final Set<String> viewedIds;
  final String currentUserId;
  final String? playingId;
  final bool isPlaying;
  final ValueChanged<VoiceMoment> onTap;
  final ValueChanged<VoiceMoment> onPlay;
  final ValueChanged<VoiceMoment> onOpenDetail;
  final ValueChanged<VoiceMoment> onReport;
  final ValueChanged<VoiceMoment> onDelete;

  static const double gap = 10;

  @override
  Widget build(BuildContext context) {
    if (moments.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = momentFeaturedColumns(
          constraints.maxWidth,
          textScale: MediaQuery.textScalerOf(context).scale(12) / 12,
        );
        // At most two rows, and never a row with holes in it. One column
        // on a narrow phone means two tiles, not four: four stacked cells
        // would push the recent list off the first screen, which is the
        // very complaint this redesign answers. Nothing is lost — every
        // featured Moment is also a row in the list below.
        var shown = moments.length.clamp(0, columns * 2);
        if (shown > columns) shown -= shown % columns;
        final visible = moments.take(shown).toList(growable: false);
        final rows = <Widget>[];
        for (var start = 0; start < visible.length; start += columns) {
          final slice = visible
              .skip(start)
              .take(columns)
              .toList(growable: false);
          final last = start + columns >= visible.length;
          rows.add(
            Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : gap),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0) const SizedBox(width: gap),
                      Expanded(
                        child: column < slice.length
                            ? _tile(slice[column])
                            // A short last row keeps its cells the width
                            // the full rows have, so the grid stays a grid
                            // instead of stretching two tiles across four
                            // columns.
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        );
      },
    );
  }

  Widget _tile(VoiceMoment moment) => MomentFeaturedTile(
    key: ValueKey('moment-featured-${moment.id}'),
    moment: moment,
    seen: viewedIds.contains(moment.id),
    playing: isPlaying && playingId == moment.id,
    isOwn: currentUserId.isNotEmpty && moment.authorId == currentUserId,
    onTap: () => onTap(moment),
    onPlay: () => onPlay(moment),
    onOpenDetail: () => onOpenDetail(moment),
    onReport: () => onReport(moment),
    onDelete: () => onDelete(moment),
  );
}
