import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The desktop right column's top card: "Voice Trending" — two curated
/// sections over REAL data.
///
///  - Trending Moments: the live public rooms already powering Home's
///    LIVE NOW hero ([RoomService.watchLivePublicRooms]).
///  - People to Follow: real suggestions from the server-side social
///    graph ([SocialGraphService.getFriendSuggestions]).
///
/// Both sections hide themselves when their real source is empty rather
/// than showing placeholder people or invented activity.
class VoiceTrendingCard extends StatefulWidget {
  const VoiceTrendingCard({
    required this.onOpenRoom,
    required this.onSeeAll,
    this.roomService,
    this.socialGraphService,
    this.profileService,
    super.key,
  });

  final ValueChanged<VoiceRoom> onOpenRoom;
  final VoidCallback onSeeAll;
  final RoomService? roomService;
  final SocialGraphService? socialGraphService;
  final ProfileService? profileService;

  @override
  State<VoiceTrendingCard> createState() => _VoiceTrendingCardState();
}

class _VoiceTrendingCardState extends State<VoiceTrendingCard> {
  RoomService? _rooms;
  ProfileService? _profiles;

  Future<List<SuggestedFriend>> _suggestions = Future.value(
    const <SuggestedFriend>[],
  );

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
    try {
      _profiles = widget.profileService ?? ProfileService();
    } catch (_) {
      _profiles = null;
    }
    try {
      final social = widget.socialGraphService ?? SocialGraphService();
      _suggestions = social
          .getFriendSuggestions(limit: 2)
          .catchError((_) => const <SuggestedFriend>[]);
    } catch (_) {
      _suggestions = Future.value(const <SuggestedFriend>[]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color(0xFF120C1D).withValues(alpha: .9),
        border: Border.all(color: const Color(0xFF2E2140)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: .07),
            blurRadius: 28,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Voice Trending',
            style: TextStyle(
              color: Colors.white,
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
              if (live.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('Trending Moments'),
                  const SizedBox(height: 8),
                  for (final room in live)
                    _MomentRow(
                      room: room,
                      onTap: () => widget.onOpenRoom(room),
                    ),
                  const SizedBox(height: 14),
                ],
              );
            },
          ),
          FutureBuilder<List<SuggestedFriend>>(
            future: _suggestions,
            builder: (context, snapshot) {
              final people = (snapshot.data ?? const <SuggestedFriend>[])
                  .take(2)
                  .toList(growable: false);
              if (people.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('People to Follow'),
                  const SizedBox(height: 8),
                  for (final person in people)
                    _PersonRow(
                      person: person,
                      profileService: _profiles,
                      key: ValueKey(person.uid),
                      onTap: () => showProfilePreview(
                        context,
                        userId: person.uid,
                        displayName: person.displayName,
                        photoUrl: person.photoUrl,
                      ),
                    ),
                ],
              );
            },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.onSeeAll,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'See all',
                style: TextStyle(
                  color: Color(0xFFD3A5FF),
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
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _MomentRow extends StatelessWidget {
  const _MomentRow({required this.room, required this.onTap});

  final VoiceRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
            UserAvatar(
              radius: 19,
              photoUrl: room.imageUrl ?? room.hostPhotoUrl,
              displayName: room.name,
              backgroundColor: const Color(0xFF3B1D5C),
              fallbackIcon: Icons.graphic_eq_rounded,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9A90AC),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const _LivePill(),
          ],
        ),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: AppColors.secondary.withValues(alpha: .18),
        border: Border.all(color: AppColors.secondary.withValues(alpha: .5)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6, color: Color(0xFFE879F9)),
          SizedBox(width: 5),
          Text(
            'Live',
            style: TextStyle(
              color: Color(0xFFE9B8FF),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.profileService,
    required this.onTap,
    super.key,
  });

  final SuggestedFriend person;
  final ProfileService? profileService;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            UserAvatar(
              radius: 19,
              photoUrl: person.photoUrl,
              displayName: person.displayName,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Their own words first (the profile bio/vibe), with the
                  // real mutual-friend count as the fallback — never an
                  // invented "content" blurb.
                  StreamBuilder<UserProfile>(
                    stream: profileService?.watchProfile(person.uid),
                    builder: (context, snapshot) {
                      final bio = snapshot.data?.bio.trim() ?? '';
                      final text = bio.isNotEmpty
                          ? bio
                          : person.mutualCount > 0
                          ? '${person.mutualCount} mutual '
                                '${person.mutualCount == 1 ? 'friend' : 'friends'}'
                          : 'Suggested for you';
                      return Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF9A90AC),
                          fontSize: 11.5,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
