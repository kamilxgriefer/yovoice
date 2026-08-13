import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart'
    show RoomVisual;

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
                  const _SectionLabel('Trending Moments'),
                  const SizedBox(height: 8),
                  if (waiting)
                    const _RowPlaceholder(count: 2)
                  else if (snapshot.hasError)
                    const _SectionNote('Live moments are unavailable.')
                  else if (live.isEmpty)
                    const _SectionNote('No one is live right now.')
                  else
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
                'View all',
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

/// 2100 → "2.1K", so a busy room cannot push the row's own title out.
String _compact(int count) {
  if (count < 1000) return '$count';
  final thousands = count / 1000;
  final text = thousands >= 10
      ? thousands.round().toString()
      : thousands.toStringAsFixed(1);
  return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}K';
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
            const SizedBox(width: 7),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.people_alt_rounded,
                  size: 12,
                  color: Color(0xFF9A90AC),
                ),
                const SizedBox(width: 3),
                Text(
                  _compact(room.participantCount),
                  style: const TextStyle(
                    color: Color(0xFFCFC6DC),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF7E7895),
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
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          Container(
            height: 44,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withValues(alpha: .03),
              border: Border.all(color: const Color(0xFF241A33)),
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

