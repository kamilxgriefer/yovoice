import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart'
    show RoomVisual, RoomRosterList;
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/staff/presentation/widgets/room_staff_menu.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// One deduplicated room list for Home, and the widgets that render it.
///
/// Home used to ask the same question three times — `Live around you`,
/// `Featured Live` and `For you` were three presentations over
/// overlapping room streams, so the same room could appear three times on
/// one screen. [rankRoomsForHome] merges the sources into a single
/// ordered list with each room appearing exactly once, and
/// [HomeRoomBanner] renders it as one vertical column on every viewport.

/// Merges Home's room sources into one ordered, deduplicated list.
///
/// Priority, highest first:
///  1. live rooms hosted by someone the user follows;
///  2. any live room;
///  3. rooms hosted by someone the user follows;
///  4. everything else recommended.
///
/// Ordering inside a tier is by recency, which the callers' queries
/// already provide, so the result is stable between rebuilds — a feed
/// that reshuffles under the reader is worse than one that is slightly
/// stale.
List<VoiceRoom> rankRoomsForHome({
  required List<VoiceRoom> live,
  required List<VoiceRoom> recommended,
  Set<String> followedHostIds = const <String>{},
  int limit = 12,
}) {
  final seen = <String>{};
  final tiers = <List<VoiceRoom>>[[], [], [], []];

  void place(VoiceRoom room, {required bool isLive}) {
    if (!seen.add(room.id)) return; // never twice on one screen
    final followed = followedHostIds.contains(room.hostId);
    if (isLive && followed) {
      tiers[0].add(room);
    } else if (isLive) {
      tiers[1].add(room);
    } else if (followed) {
      tiers[2].add(room);
    } else {
      tiers[3].add(room);
    }
  }

  for (final room in live) {
    place(room, isLive: true);
  }
  for (final room in recommended) {
    place(room, isLive: room.isLive);
  }

  return [for (final tier in tiers) ...tier].take(limit).toList(growable: false);
}

/// 2400 → "2.4K". Every listener count on Home goes through this, so a
/// banner and the owned-room card under it can never disagree about how
/// big the same room is.
String compactCount(int count) {
  if (count < 1000) return '$count';
  final thousands = count / 1000;
  final text = thousands >= 10
      ? thousands.round().toString()
      : thousands.toStringAsFixed(1);
  return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}K';
}

/// A wide room banner: the room's own cover IS the card, and one primary
/// action sits on it.
///
/// The cover is full-bleed rather than a strip above the text, so the
/// section reads as a stack of places rather than a list of rows. Text
/// legibility over an arbitrary photo is bought with a scrim that is
/// darkest where the words are and clears by the right edge, so the cover
/// still reads as a picture rather than a texture.
class HomeRoomBanner extends StatelessWidget {
  const HomeRoomBanner({
    required this.room,
    required this.onJoin,
    this.roomService,
    this.compact = false,
    this.staffCapabilities,
    this.staffFunctions,
    this.onRoomDeleted,
    super.key,
  });

  final VoiceRoom room;
  final ValueChanged<VoiceRoom> onJoin;

  /// Feeds the face pile and the participant list behind it. Optional:
  /// without it the banner still renders, minus the faces — Home must
  /// degrade rather than throw when a service cannot be constructed.
  final RoomService? roomService;

  /// Phone density: tighter type and padding. Never a different layout —
  /// the reading order is identical on both.
  final bool compact;

  /// Server-derived capabilities. Null or [StaffCapabilities.none] renders
  /// the banner exactly as every ordinary account sees it — no shield, no
  /// gaps, no disabled controls.
  final StaffCapabilities? staffCapabilities;
  final FirebaseFunctions? staffFunctions;
  final VoidCallback? onRoomDeleted;

  @override
  Widget build(BuildContext context) {
    final tags = <String>[
      room.category.trim(),
      if (room.isBroadcast) 'Broadcast',
      room.language.trim(),
    ].where((tag) => tag.isNotEmpty).toList(growable: false);

    return Semantics(
      container: true,
      label:
          '${room.name}. ${room.isLive ? 'Live' : 'Not live'}. '
          '${room.participantCount} listening.',
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        constraints: BoxConstraints(minHeight: compact ? 168 : 156),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF12101D),
          border: Border.all(color: const Color(0xFF2C253B)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // RoomVisual owns imageUrl, the branded gradient fallback and
            // the broken-image case, so a banner can never show a
            // broken-image glyph.
            Positioned.fill(
              child: RoomVisual(room: room, expand: true, radius: 0),
            ),
            Positioned.fill(child: _CoverScrim(compact: compact)),
            Padding(
              padding: EdgeInsets.all(compact ? 14 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _StatusBadge(live: room.isLive),
                      const SizedBox(width: 9),
                      _CountChip(count: room.participantCount),
                      if (staffCapabilities?.hasRoomModeration ?? false) ...[
                        const Spacer(),
                        RoomStaffMenu(
                          room: room,
                          capabilities: staffCapabilities!,
                          functions: staffFunctions,
                          onRoomDeleted: onRoomDeleted,
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: compact ? 10 : 12),
                  Text(
                    room.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 19 : 22,
                      height: 1.15,
                      letterSpacing: -.3,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (room.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      room.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFFC4BAD3),
                        fontSize: compact ? 12.5 : 13.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                  SizedBox(height: compact ? 12 : 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: _TagRow(tags: tags)),
                      const SizedBox(width: 10),
                      _FacePile(
                        room: room,
                        roomService: roomService,
                        compact: compact,
                      ),
                      SizedBox(width: compact ? 8 : 12),
                      _JoinButton(
                        compact: compact,
                        onTap: () => onJoin(room),
                      ),
                    ],
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

/// Legibility for text sitting directly on someone's cover photo.
///
/// Two gradient passes rather than a blur: one horizontal ramp that is
/// nearly opaque where the words start and clears by the right edge, and
/// one vertical pass that seats the bottom row. A `BackdropFilter` here
/// would look marginally softer and cost a saved layer PER BANNER — with
/// up to a dozen banners in the board that is the kind of thing that
/// makes a CanvasKit build stutter, and it slowed the screenshot
/// rasteriser from seconds to minutes, which is the same work the
/// browser would be doing.
class _CoverScrim extends StatelessWidget {
  const _CoverScrim({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [
            Color(0xF50B0713),
            Color(0xEA0B0713),
            Color(0xB00B0713),
            Color(0x330B0713),
          ],
          stops: compact
              ? const [0, .45, .78, 1]
              : const [0, .34, .62, 1],
        ),
      ),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x000B0713), Color(0x000B0713), Color(0x9E0B0713)],
            stops: [0, .45, 1],
          ),
        ),
      ),
    );
  }
}

/// The facets a room actually carries, on one line.
///
/// Anything that does not fit is clipped rather than wrapped: the banner
/// has no height for a second chip row, and a half-visible chip reads as
/// "there is more" better than a reflowed layout does.
class _TagRow extends StatelessWidget {
  const _TagRow({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 26,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          maxWidth: double.infinity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < tags.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _Tag(tags[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    // "Not live" rather than "Scheduled": rooms carry no start time in
    // Firestore, so a schedule badge would be claiming something the
    // backend cannot answer.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        color: live
            ? const Color(0xFFE11D48)
            : Colors.black.withValues(alpha: .58),
      ),
      child: Text(
        live ? 'LIVE' : 'NOT LIVE',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: .7,
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.people_alt_rounded,
          size: 13,
          color: Color(0xFFCFC6DC),
        ),
        const SizedBox(width: 5),
        Text(
          compactCount(count),
          style: const TextStyle(
            color: Color(0xFFE6E0EE),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: .09),
        border: Border.all(color: Colors.white.withValues(alpha: .13)),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: const TextStyle(
          color: Color(0xFFE0D9EA),
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _JoinButton extends StatelessWidget {
  const _JoinButton({required this.compact, required this.onTap});

  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 42 : 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.secondary],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: .35),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 22),
              child: Center(
                child: Text(
                  compact ? 'Join' : 'Join room',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `Your active rooms` — only rooms this account actually owns.
///
/// The owner-only edit affordance is gated on the room's own `hostId`,
/// and the settings screen it opens re-checks authorship; `firestore.rules`
/// then refuses any non-host write to a room's editable fields. Three
/// independent layers, so a non-owner sees no edit control and could not
/// use one if it were somehow rendered.
class HomeActiveRooms extends StatelessWidget {
  const HomeActiveRooms({
    required this.rooms,
    required this.currentUserId,
    required this.onEnter,
    required this.onEdit,
    required this.onCreateRoom,
    this.compact = false,
    super.key,
  });

  final List<VoiceRoom> rooms;
  final String currentUserId;
  final ValueChanged<VoiceRoom> onEnter;
  final ValueChanged<VoiceRoom> onEdit;
  final VoidCallback onCreateRoom;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final mine = rooms
        .where((room) => room.hostId == currentUserId)
        .toList(growable: false);

    if (mine.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF12101D),
          border: Border.all(color: const Color(0xFF2C253B)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'You have no rooms yet.',
              style: TextStyle(
                color: Color(0xFF9D95AD),
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: onCreateRoom,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create Room'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD3A5FF),
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: .45),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final side = compact ? 148.0 : 168.0;
    return SizedBox(
      height: side + 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        // One past the end: the last tile is the way to make another room,
        // so starting one never means leaving the section first.
        itemCount: mine.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          if (index == mine.length) {
            return _CreateRoomTile(side: side, onTap: onCreateRoom);
          }
          final room = mine[index];
          return _OwnedRoomCard(
            room: room,
            side: side,
            onEnter: () => onEnter(room),
            onEdit: () => onEdit(room),
          );
        },
      ),
    );
  }
}

/// The "one more" tile at the end of the owned-rooms row.
///
/// Dashed rather than solid so it reads as a slot to fill, not a room
/// that already exists.
class _CreateRoomTile extends StatelessWidget {
  const _CreateRoomTile({required this.side, required this.onTap});

  final double side;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: side,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: AppColors.primary.withValues(alpha: .55),
              radius: 16,
            ),
            child: SizedBox(
              height: side,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_rounded,
                    color: Color(0xFFD3A5FF),
                    size: 28,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Create room',
                    style: TextStyle(
                      color: Color(0xFFD3A5FF),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
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

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    // Walk the rounded rectangle and stroke every other segment.
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + 6;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + 5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

class _OwnedRoomCard extends StatelessWidget {
  const _OwnedRoomCard({
    required this.room,
    required this.side,
    required this.onEnter,
    required this.onEdit,
  });

  final VoiceRoom room;
  final double side;
  final VoidCallback onEnter;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: side,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: RoomVisual(room: room, size: side, radius: 16),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: Material(
                  color: Colors.black.withValues(alpha: .55),
                  shape: const CircleBorder(),
                  child: Tooltip(
                    message: 'Room settings',
                    child: IconButton(
                      onPressed: onEdit,
                      iconSize: 17,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      icon: const Icon(
                        Icons.settings_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
          Text(
            room.isLive
                ? 'Live · ${compactCount(room.participantCount)} here'
                : 'Not live',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF9D95AD), fontSize: 11.5),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton(
              onPressed: onEnter,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: EdgeInsets.zero,
              ),
              child: Text(
                room.isLive ? 'Enter' : 'Start',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Three real faces from the room, and the way into the rest of them.
///
/// The faces come from the room's own participant stream — the same
/// source the stage reads — so a banner never shows a person who is not
/// actually in there. A room with nobody in it shows no pile at all
/// rather than placeholder circles.
class _FacePile extends StatelessWidget {
  const _FacePile({
    required this.room,
    required this.roomService,
    required this.compact,
  });

  final VoiceRoom room;
  final RoomService? roomService;
  final bool compact;

  /// Host first, then whoever the room lists — the pile should lead with
  /// the person the room belongs to.
  List<RoomParticipant> _leading(List<RoomParticipant> participants) {
    final ordered = [...participants]
      ..sort((a, b) {
        int rank(RoomParticipant p) {
          if (p.isHost || p.userId == room.hostId) return 0;
          if (p.role == 'moderator') return 1;
          if (p.isSpeaker) return 2;
          return 3;
        }

        return rank(a).compareTo(rank(b));
      });
    return ordered.take(3).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final service = roomService;
    if (service == null) return const SizedBox.shrink();

    final radius = compact ? 15.0 : 16.0;
    return StreamBuilder<List<RoomParticipant>>(
      stream: service.watchParticipants(room.id),
      builder: (context, snapshot) {
        final shown = _leading(snapshot.data ?? const <RoomParticipant>[]);
        if (shown.isEmpty) return const SizedBox.shrink();

        return Semantics(
          button: true,
          label:
              '${room.participantCount} in ${room.name}. '
              'Open the participant list',
          child: Tooltip(
            message: 'See who is in the room',
            child: InkWell(
              onTap: () => _openRoster(context, room, service, compact),
              customBorder: const StadiumBorder(),
              child: SizedBox(
                height: radius * 2,
                width: radius * 2 + (shown.length - 1) * radius * 1.3,
                child: Stack(
                  children: [
                    for (var i = 0; i < shown.length; i++)
                      Positioned(
                        left: i * radius * 1.3,
                        child: Container(
                          padding: const EdgeInsets.all(1.6),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.secondary,
                              ],
                            ),
                          ),
                          child: UserAvatar(
                            radius: radius - 1.6,
                            photoUrl: shown[i].photoUrl,
                            displayName: shown[i].displayName,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Opens the full roster: a sheet on a phone, a dialog on a pointer
/// surface. The subscription behind it lives no longer than the surface
/// showing it.
void _openRoster(
  BuildContext context,
  VoiceRoom room,
  RoomService service,
  bool compact,
) {
  if (compact) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF120C1D),
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
        child: _RosterLoader(
          room: room,
          service: service,
          onDismiss: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    );
    return;
  }

  showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (dialogContext) => Dialog(
      backgroundColor: const Color(0xFF120C1D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF2E2140)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300, maxHeight: 380),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _RosterLoader(
            room: room,
            service: service,
            onDismiss: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      ),
    ),
  );
}

/// Subscribes to the roster for as long as the preview is open, and no
/// longer.
class _RosterLoader extends StatelessWidget {
  const _RosterLoader({
    required this.room,
    required this.service,
    required this.onDismiss,
  });

  final VoiceRoom room;
  final RoomService service;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RoomParticipant>>(
      stream: service.watchParticipants(room.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18, horizontal: 6),
            child: Text(
              'That room is no longer available.',
              style: TextStyle(color: Color(0xFF9A90AC), fontSize: 12.5),
            ),
          );
        }
        final participants = [...(snapshot.data ?? const <RoomParticipant>[])]
          ..sort((a, b) {
            int rank(RoomParticipant p) {
              if (p.isHost || p.userId == room.hostId) return 0;
              if (p.role == 'moderator') return 1;
              if (p.isSpeaker) return 2;
              return 3;
            }

            final byRole = rank(a).compareTo(rank(b));
            return byRole != 0
                ? byRole
                : a.displayName.toLowerCase().compareTo(
                    b.displayName.toLowerCase(),
                  );
          });

        return RoomRosterList(
          participants: participants,
          hostId: room.hostId,
          onDismiss: onDismiss,
        );
      },
    );
  }
}
