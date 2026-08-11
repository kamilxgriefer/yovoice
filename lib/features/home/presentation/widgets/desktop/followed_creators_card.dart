import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// "Top creators you follow" — the desktop right column, under Premium.
///
/// Deliberately NOT the same job as Voice Trending directly above it:
/// Trending is about what is loud right now across the product, this is
/// about the specific people this account already chose to follow. It
/// never falls back to suggested people — an account that follows nobody
/// gets an empty state and one way to go find someone, so the two ideas
/// stay separate.
///
/// DATA:
///  - who → [FollowService.watchFollowing] for the signed-in uid, i.e.
///    the real `users/{uid}/following` edges
///  - live signal → [RoomService.watchLivePublicRooms], matched on
///    `hostId`: a creator who is HOSTING a live public room right now
///  - moment signal → [HomeFeedService.watchSocialMoments], which already
///    carries followed creators' published Moments
///
/// There are no follower counts, listen counts or engagement numbers here
/// on purpose: nothing in the schema would make them true for a creator
/// this user merely follows.
///
/// LIMIT: room presence is read from the room documents alone, so a
/// creator who is *speaking in* someone else's room shows no live signal
/// — only hosting does. Reading every live room's participant
/// subcollection from the right column would double Home's listener
/// count to surface a rarer case. See docs/Decisions.md ADR-036.
class FollowedCreatorsCard extends StatefulWidget {
  const FollowedCreatorsCard({
    required this.currentUserId,
    required this.onOpenCreator,
    required this.onViewAll,
    required this.onDiscover,
    this.followService,
    this.feedService,
    this.roomService,
    super.key,
  });

  final String currentUserId;

  /// Opens that creator's existing profile surface.
  final ValueChanged<FollowUser> onOpenCreator;

  /// The existing Following list for this account.
  final VoidCallback onViewAll;

  /// Discover, in the fixed desktop shell's content slot.
  final VoidCallback onDiscover;

  final FollowService? followService;
  final HomeFeedService? feedService;
  final RoomService? roomService;

  /// A Moment is worth calling out for a day after it is posted.
  static const Duration recentWindow = Duration(hours: 24);

  /// Five rows: enough to be a real list, short enough to sit under the
  /// Premium card without turning the rail into a second feed.
  static const int visibleRows = 5;

  @override
  State<FollowedCreatorsCard> createState() => _FollowedCreatorsCardState();
}

class _FollowedCreatorsCardState extends State<FollowedCreatorsCard> {
  Stream<List<FollowUser>>? _following;
  Stream<List<VoiceMoment>>? _moments;
  Stream<List<VoiceRoom>>? _liveRooms;

  @override
  void initState() {
    super.initState();
    try {
      if (widget.currentUserId.isNotEmpty) {
        _following = (widget.followService ?? FollowService()).watchFollowing(
          widget.currentUserId,
        );
      }
    } catch (_) {
      _following = null;
    }
    try {
      _moments = (widget.feedService ?? HomeFeedService()).watchSocialMoments();
    } catch (_) {
      _moments = null;
    }
    try {
      _liveRooms = (widget.roomService ?? RoomService()).watchLivePublicRooms();
    } catch (_) {
      _liveRooms = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FollowUser>>(
      stream: _following,
      builder: (context, followSnapshot) {
        final creators = (followSnapshot.data ?? const <FollowUser>[])
            .where((creator) => creator.uid != widget.currentUserId)
            .toList(growable: false);

        return StreamBuilder<List<VoiceRoom>>(
          stream: _liveRooms,
          builder: (context, roomSnapshot) {
            return StreamBuilder<List<VoiceMoment>>(
              stream: _moments,
              builder: (context, momentSnapshot) {
                final hosting = <String, VoiceRoom>{
                  for (final room
                      in (roomSnapshot.data ?? const <VoiceRoom>[]).reversed)
                    room.hostId: room,
                };
                final newestMoment = <String, VoiceMoment>{};
                for (final moment
                    in momentSnapshot.data ?? const <VoiceMoment>[]) {
                  newestMoment.putIfAbsent(moment.authorId, () => moment);
                }

                final ranked = [...creators]
                  ..sort((a, b) {
                    // Live first, then whoever posted most recently, then
                    // the follow order the list already came in.
                    final rankA = _rank(a, hosting, newestMoment);
                    final rankB = _rank(b, hosting, newestMoment);
                    if (rankA != rankB) return rankA.compareTo(rankB);
                    final momentA = newestMoment[a.uid]?.createdAt;
                    final momentB = newestMoment[b.uid]?.createdAt;
                    if (momentA != null && momentB != null) {
                      return momentB.compareTo(momentA);
                    }
                    return 0;
                  });

                return Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: const Color(0xFF120C1D).withValues(alpha: .9),
                    border: Border.all(color: const Color(0xFF2E2140)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Top creators you follow',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (creators.isNotEmpty)
                            _ViewAllButton(onTap: widget.onViewAll),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (creators.isEmpty)
                        _NoCreatorsState(onDiscover: widget.onDiscover)
                      else
                        for (final creator in ranked.take(
                          FollowedCreatorsCard.visibleRows,
                        ))
                          _CreatorRow(
                            key: ValueKey(creator.uid),
                            creator: creator,
                            hostedRoom: hosting[creator.uid],
                            moment: newestMoment[creator.uid],
                            onTap: () => widget.onOpenCreator(creator),
                          ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  static int _rank(
    FollowUser creator,
    Map<String, VoiceRoom> hosting,
    Map<String, VoiceMoment> moments,
  ) {
    if (hosting.containsKey(creator.uid)) return 0;
    final createdAt = moments[creator.uid]?.createdAt;
    if (createdAt != null &&
        DateTime.now().difference(createdAt) <
            FollowedCreatorsCard.recentWindow) {
      return 1;
    }
    return 2;
  }
}

class _ViewAllButton extends StatelessWidget {
  const _ViewAllButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'View all',
            style: TextStyle(
              color: Color(0xFFD3A5FF),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(width: 3),
          Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFFD3A5FF)),
        ],
      ),
    );
  }
}

class _CreatorRow extends StatefulWidget {
  const _CreatorRow({
    required this.creator,
    required this.hostedRoom,
    required this.moment,
    required this.onTap,
    super.key,
  });

  final FollowUser creator;
  final VoiceRoom? hostedRoom;
  final VoiceMoment? moment;
  final VoidCallback onTap;

  @override
  State<_CreatorRow> createState() => _CreatorRowState();
}

class _CreatorRowState extends State<_CreatorRow> {
  bool _hover = false;

  /// The handle when the profile has one, otherwise nothing invented.
  String get _handle {
    final username = widget.creator.username.trim();
    if (username.isEmpty) return '';
    return '@${username.replaceAll(' ', '').toLowerCase()}';
  }

  static String _age(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.hostedRoom;
    final moment = widget.moment;
    final recent =
        moment?.createdAt != null &&
        DateTime.now().difference(moment!.createdAt!) <
            FollowedCreatorsCard.recentWindow;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: _hover
                ? Colors.white.withValues(alpha: .04)
                : Colors.transparent,
            border: Border.all(
              color: _hover
                  ? AppColors.primary.withValues(alpha: .30)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              UserAvatar(
                radius: 17,
                photoUrl: widget.creator.photoUrl,
                displayName: widget.creator.displayName,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.creator.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    // Exactly one signal, and only one the data proves:
                    // hosting a live room now, then a Moment from the last
                    // day, then just the handle.
                    if (room != null)
                      _LiveSignal(roomName: room.name)
                    else if (recent)
                      Text(
                        'New Moment · ${_age(moment.createdAt!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFE879F9),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else if (_handle.isNotEmpty)
                      Text(
                        _handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF9A90AC),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 130),
                opacity: _hover ? 1 : .45,
                child: const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Color(0xFFD3A5FF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveSignal extends StatelessWidget {
  const _LiveSignal({required this.roomName});

  final String roomName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.live,
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            'Live · $roomName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFFF7A93),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Follows nobody yet. Says so, says what will appear here, and offers
/// the one existing way to fix it — no substituted "people you may know".
class _NoCreatorsState extends StatelessWidget {
  const _NoCreatorsState({required this.onDiscover});

  final VoidCallback onDiscover;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: .02),
        border: Border.all(color: const Color(0xFF241A33)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The creators you follow will appear here — with what they '
            'are hosting and their latest Moments.',
            style: TextStyle(
              color: Color(0xFF9A90AC),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onDiscover,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.primary.withValues(alpha: .45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Discover creators',
              style: TextStyle(
                color: Color(0xFFD3A5FF),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
