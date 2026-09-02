import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

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
      final copy = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            copy.isPolish
                ? 'Nie udało się wykonać tej operacji. Spróbuj ponownie.'
                : intentionalOrFriendly(
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
    final copy = AppLocalizations.of(context);
    final items = _visible;
    final filters = [
      ('all', copy.text('All', 'Wszyscy')),
      ('speakers', copy.text('Stage', 'Scena')),
      ('listeners', copy.text('Audience', 'Publiczność')),
      ('hands', copy.text('Raised hands', 'Zgłoszenia')),
    ];

    return Column(
      children: [
        YoModalSheetChrome(
          sheetLabel: copy.text('podcast participants', 'uczestnicy podcastu'),
          surfaceColor: BroadcastRoomColors.surface,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  copy.text('Podcast participants', 'Uczestnicy podcastu'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Icon(
                Icons.groups_rounded,
                color: BroadcastRoomColors.accentSoft,
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final filter in filters)
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
              ? Center(
                  child: Text(
                    copy.text('Nobody here yet.', 'Nikogo tu jeszcze nie ma.'),
                    style: const TextStyle(color: BroadcastRoomColors.muted),
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
                        userId: person.userId,
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
                            ? copy.text('Host', 'Gospodarz')
                            : person.isSpeaker
                            ? copy.text(
                                'Speaker${person.isMuted ? ' • muted' : ''}',
                                'Mówca${person.isMuted ? ' • wyciszony' : ''}',
                              )
                            : person.isHandRaised
                            ? copy.text(
                                'Listener • hand raised',
                                'Słuchacz • prosi o głos',
                              )
                            : copy.text('Listener', 'Słuchacz'),
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
                                  tooltip: copy.text(
                                    'Bring to stage',
                                    'Zaproś na scenę',
                                  ),
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
                                  tooltip: copy.text('Decline', 'Odrzuć'),
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
                                  PopupMenuItem(
                                    value: 'stage',
                                    child: Text(
                                      copy.text(
                                        'Invite to stage',
                                        'Zaproś na scenę',
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                if (person.isSpeaker)
                                  PopupMenuItem(
                                    value: 'audience',
                                    child: Text(
                                      copy.text(
                                        'Move to audience',
                                        'Przenieś do publiczności',
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                if (person.isSpeaker && !person.isMuted)
                                  PopupMenuItem(
                                    value: 'mute',
                                    child: Text(
                                      copy.text(
                                        'Mute participant',
                                        'Wycisz uczestnika',
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                if (person.isSpeaker && person.isMuted)
                                  PopupMenuItem(
                                    value: 'unmute',
                                    child: Text(
                                      copy.text(
                                        'Allow microphone',
                                        'Zezwól na mikrofon',
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text(
                                    copy.text(
                                      'Remove from room',
                                      'Usuń z pokoju',
                                    ),
                                    style: const TextStyle(
                                      color: Color(0xFFFF6A76),
                                    ),
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
