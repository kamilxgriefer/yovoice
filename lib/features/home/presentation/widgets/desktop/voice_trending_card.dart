import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_boundary.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart'
    show RoomVisual;
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart'
    show compactCount;

/// The desktop right column's top card: "Voice Trending" — two sections
/// over REAL data, each labelled with what it actually contains.
///
///  - **Live rooms**: the live public rooms already powering Home's LIVE
///    NOW hero ([RoomService.watchLivePublicRooms]). This section was
///    previously headed "Trending Moments" while listing rooms — a
///    mislabel, and a bad one in a codebase where rooms and Moments are
///    separate products. Its "See all rooms" link goes to Discover.
///  - **Most liked Moments**: real published Voice Moments ordered by
///    `likeCount` ([MomentDiscoveryService.topLikedMoments]). Ordered on
///    likes alone, so it says "Most liked" and not "Trending".
///
/// The card's "View all" goes to Moments.
///
/// Every section states its own empty and error case rather than
/// vanishing — a card that shrinks to a title and a link reads as
/// breakage, and a slow stream is otherwise indistinguishable from an
/// empty one.
class VoiceTrendingCard extends StatefulWidget {
  const VoiceTrendingCard({
    required this.onOpenRoom,
    required this.onSeeAll,
    required this.onSeeAllRooms,
    this.roomService,
    this.socialGraphService,
    this.profileService,
    this.discoveryService,
    this.isVisible,
    super.key,
  });

  final ValueChanged<VoiceRoom> onOpenRoom;

  /// The card's "View all" — the Moments destination.
  final VoidCallback onSeeAll;

  /// The live-rooms section's own link — Discover.
  final VoidCallback onSeeAllRooms;
  final RoomService? roomService;
  final SocialGraphService? socialGraphService;
  final ProfileService? profileService;
  final MomentDiscoveryService? discoveryService;
  final ValueListenable<bool>? isVisible;

  @override
  State<VoiceTrendingCard> createState() => _VoiceTrendingCardState();
}

class _VoiceTrendingCardState extends State<VoiceTrendingCard> {
  RoomService? _rooms;
  Future<List<VoiceMoment>>? _topMoments;
  MomentDiscoveryService? _discovery;
  final FocusNode _expiryRecoveryFocus = FocusNode(
    debugLabel: 'View all Moments after trending expiry',
  );
  final MomentExpiryAnnouncer _expiryAnnouncer = MomentExpiryAnnouncer();

  @override
  void initState() {
    super.initState();
    // Every dependency here is optional at RUNTIME: a card in the nav
    // shell must degrade to an empty section rather than throw if a
    // service cannot be constructed (no session yet, dev harness).
    try {
      _rooms = widget.roomService ?? RoomService();
    } catch (_) {
      _rooms = null;
    }
    _loadTopMoments();
    widget.isVisible?.addListener(_handleVisibility);
  }

  void _loadTopMoments() {
    try {
      // One-shot, not a listener: refresh only when retained Home becomes
      // visible instead of subscribing to every like near the boundary.
      _discovery ??= widget.discoveryService ?? MomentDiscoveryService();
      _topMoments = _discovery!.topLikedMoments();
    } catch (_) {
      _topMoments = null;
    }
  }

  void _handleVisibility() {
    if (!mounted || widget.isVisible?.value != true) return;
    setState(_loadTopMoments);
  }

  @override
  void didUpdateWidget(covariant VoiceTrendingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible) {
      oldWidget.isVisible?.removeListener(_handleVisibility);
      widget.isVisible?.addListener(_handleVisibility);
    }
    if (oldWidget.discoveryService != widget.discoveryService) {
      _discovery = null;
      setState(_loadTopMoments);
    }
  }

  @override
  void dispose() {
    widget.isVisible?.removeListener(_handleVisibility);
    _expiryRecoveryFocus.dispose();
    super.dispose();
  }

  void _handleExpiryDeadline(DateTime deadline) {
    final previousFocus = FocusManager.instance.primaryFocus;
    final recoverFocus = momentExpiryFocusIsWithin(context, previousFocus);
    _expiryAnnouncer.announce(
      context,
      transition: 'trending-expiry-${deadline.microsecondsSinceEpoch}',
      message: AppLocalizations.of(context).text(
        'Voice Moment expired and was removed from Most liked.',
        'Voice Moment wygasł i został usunięty z najpopularniejszych.',
      ),
    );
    recoverMomentExpiryFocusAfterFrame(
      context: context,
      fallback: _expiryRecoveryFocus,
      previousFocus: recoverFocus ? previousFocus : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Container(
      key: const ValueKey('desktop-voice-trending-card'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: palette.surface,
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: .08),
            blurRadius: 28,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.text('Voice Trending', 'Popularne głosy'),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          StreamBuilder<List<VoiceRoom>>(
            stream: _rooms?.watchLivePublicRooms(),
            builder: (context, snapshot) {
              final live = (snapshot.data ?? const <VoiceRoom>[])
                  .take(2)
                  .toList(growable: false);
              // The section keeps its heading in every state. Vanishing
              // was the old behaviour and it reads as breakage: the card
              // shrinks to a title and a "See all" with no explanation,
              // and a slow stream is indistinguishable from an empty one.
              final waiting =
                  snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(
                    label: copy.text('Live rooms', 'Pokoje na żywo'),
                    actionLabel: copy.text(
                      'See all rooms',
                      'Zobacz wszystkie pokoje',
                    ),
                    onAction: widget.onSeeAllRooms,
                  ),
                  const SizedBox(height: 8),
                  if (waiting)
                    const _RowPlaceholder(count: 2)
                  else if (snapshot.hasError)
                    _SectionNote(
                      copy.text(
                        'Live rooms are unavailable.',
                        'Pokoje na żywo są niedostępne.',
                      ),
                    )
                  else if (live.isEmpty)
                    _SectionNote(
                      copy.text(
                        'No one is live right now.',
                        'Teraz nikt nie prowadzi pokoju na żywo.',
                      ),
                    )
                  else
                    for (final room in live)
                      _RoomRow(
                        room: room,
                        onTap: () => widget.onOpenRoom(room),
                      ),
                  const SizedBox(height: 14),
                ],
              );
            },
          ),
          // A REAL Moments section. Without it, "View all → Moments"
          // would sit under a list of rooms, which is the mislabel this
          // change exists to remove, only inverted.
          _SectionLabel(
            copy.text('Most liked Moments', 'Najbardziej lubiane Momenty'),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<VoiceMoment>>(
            future: _topMoments,
            builder: (context, snapshot) {
              if (_topMoments == null) {
                return _SectionNote(
                  copy.text(
                    'Voice Moments are unavailable.',
                    'Voice Momenty są niedostępne.',
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _RowPlaceholder(count: 2);
              }
              // Explicit, and BEFORE any read of `data`. A missing
              // composite index surfaces here as failed-precondition; if
              // it were folded into the empty case it would read as
              // "nobody has posted" forever.
              if (snapshot.hasError) {
                return _SectionNote(
                  copy.text(
                    'Moments could not be loaded.',
                    'Nie udało się wczytać Momentów.',
                  ),
                );
              }
              final moments = snapshot.data ?? const <VoiceMoment>[];
              if (moments.isEmpty) {
                return _SectionNote(
                  copy.text(
                    'No Voice Moments published yet.',
                    'Nie opublikowano jeszcze żadnych Voice Momentów.',
                  ),
                );
              }
              return MomentExpiryListBuilder(
                moments: moments,
                onDeadline: _handleExpiryDeadline,
                builder: (context, now) {
                  final live = moments
                      .where((moment) => moment.isActiveAt(now))
                      .toList(growable: false);
                  if (live.isEmpty) {
                    return _SectionNote(
                      copy.text(
                        'No live Voice Moments right now.',
                        'Teraz nie ma aktywnych Voice Momentów.',
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final moment in live)
                        _MomentRow(moment: moment, onTap: widget.onSeeAll),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              focusNode: _expiryRecoveryFocus,
              onPressed: widget.onSeeAll,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                copy.text('View all', 'Zobacz wszystkie'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Text(
      text,
      style: TextStyle(
        color: palette.textPrimary,
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// A section heading with its own link, so each section points at the
/// destination that actually holds more of ITS content.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.actionLabel,
    required this.onAction,
  });

  final String label;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: _SectionLabel(label)),
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            actionLabel,
            style: TextStyle(
              color: colors.primary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// One real published Voice Moment: its author, its caption, its real
/// like count. No invented counts and no placeholder authors — the
/// section renders nothing at all when the query comes back empty.
class _MomentRow extends StatelessWidget {
  const _MomentRow({required this.moment, required this.onTap});

  final VoiceMoment moment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final caption = moment.caption.trim();
    final palette = context.appPalette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            UserAvatar(
              radius: 20,
              userId: moment.authorId,
              photoUrl: moment.authorPhotoUrl,
              displayName: moment.authorName,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    moment.authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption.isNotEmpty
                        ? caption
                        : (moment.durationSeconds > 0
                              ? copy.text(
                                  'Voice Moment · ${moment.durationLabel}',
                                  'Voice Moment · ${moment.durationLabel}',
                                )
                              : copy.text('Voice Moment', 'Voice Moment')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.favorite_rounded,
                  size: 12,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: 3),
                Text(
                  compactCount(moment.likeCount),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomRow extends StatelessWidget {
  const _RoomRow({required this.room, required this.onTap});

  final VoiceRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final subtitle = room.description.trim().isNotEmpty
        ? room.description.trim()
        : room.category;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            // The room's own cover, square like the board's tiles —
            // RoomVisual owns the branded fallback and the broken-image
            // case, so a revoked cover never shows a broken glyph.
            RoomVisual(room: room, size: 40, radius: 11),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const _LivePill(),
            const SizedBox(width: 7),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.people_alt_rounded,
                  size: 12,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: 3),
                Text(
                  compactCount(room.participantCount),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One muted line standing in for a section that has nothing to show.
class _SectionNote extends StatelessWidget {
  const _SectionNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          color: palette.textTertiary,
          fontSize: 11.5,
          height: 1.35,
        ),
      ),
    );
  }
}

/// Inert bars matching a real row's height, so the card does not jump
/// when the data lands. No animation: this is a supporting card, and a
/// spinner here would pull attention from the content it supports.
class _RowPlaceholder extends StatelessWidget {
  const _RowPlaceholder({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          Container(
            height: 44,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: palette.surfaceMuted,
              border: Border.all(color: palette.border),
            ),
          ),
      ],
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: colors.errorContainer,
        border: Border.all(color: colors.error.withValues(alpha: .7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6, color: colors.error),
          const SizedBox(width: 5),
          Text(
            copy.text('Live', 'Na żywo'),
            style: TextStyle(
              color: colors.onErrorContainer,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
