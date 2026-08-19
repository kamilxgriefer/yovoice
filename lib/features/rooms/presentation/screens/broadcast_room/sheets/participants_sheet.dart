import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

class AnalyticsTile extends StatelessWidget {
  const AnalyticsTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BroadcastRoomColors.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BroadcastRoomColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: BroadcastRoomColors.accentSoft),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: BroadcastRoomColors.muted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class BroadcastParticipantsSheet extends StatefulWidget {
  const BroadcastParticipantsSheet({
    super.key,
    required this.roomId,
    required this.participants,
    required this.isHost,
    required this.initialFilter,
    required this.service,
  });

  final String roomId;
  final List<RoomParticipant> participants;
  final bool isHost;
  final String initialFilter;
  final RoomService service;

  @override
  State<BroadcastParticipantsSheet> createState() =>
      _BroadcastParticipantsSheetState();
}

class _BroadcastParticipantsSheetState
    extends State<BroadcastParticipantsSheet> {
  late String _filter = widget.initialFilter;

  List<RoomParticipant> get _visible {
    return switch (_filter) {
      'speakers' => widget.participants.where((p) => p.isSpeaker).toList(),
      'listeners' => widget.participants.where((p) => !p.isSpeaker).toList(),
      'hands' => widget.participants.where((p) => p.isHandRaised).toList(),
      _ => widget.participants,
    };
  }

  Future<void> _action(Future<void> Function() callback) async {
    try {
      await callback();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            intentionalOrFriendly(
              error,
              fallback: "That didn't work. Please try again.",
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;

    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Podcast participants',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(Icons.groups_rounded, color: BroadcastRoomColors.accentSoft),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final filter in const [
                ('all', 'All'),
                ('speakers', 'Stage'),
                ('listeners', 'Audience'),
                ('hands', 'Raised hands'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: _filter == filter.$1,
                    onSelected: (_) => setState(() => _filter = filter.$1),
                    label: Text(filter.$2),
                    selectedColor: const Color(0xFF762333),
                    backgroundColor: const Color(0xFF2B1117),
                    labelStyle: const TextStyle(color: Colors.white),
                    side: BorderSide.none,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text(
                    'Nobody here yet.',
                    style: TextStyle(color: BroadcastRoomColors.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 22),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Color(0xFF3B171E), height: 1),
                  itemBuilder: (context, index) {
                    final person = items[index];

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 5,
                      ),
                      // No dead avatars: any row opens the person's
                      // profile preview without leaving the room.
                      onTap: () => showProfilePreview(
                        context,
                        userId: person.userId,
                        displayName: person.displayName,
                        photoUrl: person.photoUrl,
                      ),
                      // Canonical avatar component — same loader, error
                      // state and caching as every other surface.
                      leading: UserAvatar(
                        radius: 20,
                        photoUrl: person.photoUrl,
                        displayName: person.displayName,
                        backgroundColor: const Color(0xFF792032),
                      ),
                      title: Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            person.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          UserIdentityBadges(uid: person.userId),
                        ],
                      ),
                      subtitle: Text(
                        person.isHost
                            ? 'Host'
                            : person.isSpeaker
                            ? 'Speaker${person.isMuted ? ' • muted' : ''}'
                            : person.isHandRaised
                            ? 'Listener • hand raised'
                            : 'Listener',
                        style: TextStyle(
                          color: person.isHandRaised
                              ? BroadcastRoomColors.accentSoft
                              : BroadcastRoomColors.muted,
                        ),
                      ),
                      trailing: !widget.isHost || person.isHost
                          ? Icon(
                              person.isHandRaised
                                  ? Icons.back_hand_rounded
                                  : person.isSpeaker
                                  ? Icons.mic_rounded
                                  : Icons.headphones_rounded,
                              color: person.isHandRaised
                                  ? BroadcastRoomColors.accentSoft
                                  : BroadcastRoomColors.muted,
                            )
                          // A raised hand is a REQUEST — answer it in
                          // one tap, not through a buried menu.
                          : person.isHandRaised
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Bring to stage',
                                  onPressed: () => _action(
                                    () => widget.service
                                        .setParticipantSpeakerStatus(
                                          roomId: widget.roomId,
                                          participantId: person.userId,
                                          isSpeaker: true,
                                        ),
                                  ),
                                  icon: const Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF35D07F),
                                    size: 28,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Decline',
                                  onPressed: () => _action(
                                    () => widget.service.moderateHandLowered(
                                      roomId: widget.roomId,
                                      participantId: person.userId,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.cancel_rounded,
                                    color: Color(0xFFFF6A76),
                                    size: 28,
                                  ),
                                ),
                              ],
                            )
                          : PopupMenuButton<String>(
                              color: const Color(0xFF261016),
                              iconColor: Colors.white,
                              onSelected: (value) {
                                switch (value) {
                                  case 'stage':
                                    _action(
                                      () => widget.service
                                          .setParticipantSpeakerStatus(
                                            roomId: widget.roomId,
                                            participantId: person.userId,
                                            isSpeaker: true,
                                          ),
                                    );
                                  case 'audience':
                                    _action(
                                      () => widget.service
                                          .setParticipantSpeakerStatus(
                                            roomId: widget.roomId,
                                            participantId: person.userId,
                                            isSpeaker: false,
                                          ),
                                    );
                                  case 'mute':
                                    _action(
                                      () => widget.service
                                          .moderateParticipantMute(
                                            roomId: widget.roomId,
                                            participantId: person.userId,
                                            isMuted: true,
                                          ),
                                    );
                                  case 'unmute':
                                    _action(
                                      () => widget.service
                                          .moderateParticipantMute(
                                            roomId: widget.roomId,
                                            participantId: person.userId,
                                            isMuted: false,
                                          ),
                                    );
                                  case 'remove':
                                    _action(
                                      () => widget.service.removeParticipant(
                                        roomId: widget.roomId,
                                        participantId: person.userId,
                                      ),
                                    );
                                }
                              },
                              itemBuilder: (_) => [
                                if (!person.isSpeaker)
                                  const PopupMenuItem(
                                    value: 'stage',
                                    child: Text(
                                      'Invite to stage',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                if (person.isSpeaker)
                                  const PopupMenuItem(
                                    value: 'audience',
                                    child: Text(
                                      'Move to audience',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                if (person.isSpeaker && !person.isMuted)
                                  const PopupMenuItem(
                                    value: 'mute',
                                    child: Text(
                                      'Mute participant',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                if (person.isSpeaker && person.isMuted)
                                  const PopupMenuItem(
                                    value: 'unmute',
                                    child: Text(
                                      'Allow microphone',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text(
                                    'Remove from room',
                                    style: TextStyle(color: Color(0xFFFF6A76)),
                                  ),
                                ),
                              ],
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
