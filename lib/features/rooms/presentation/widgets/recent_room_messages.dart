import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/data/models/room_message.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The floating recent-messages strip over the live stage (board
/// screens 2 and 6): the newest one or two room messages as compact
/// bubbles, so conversation stays visible without opening the chat
/// sheet. Same `rooms/{id}/messages` backend as [RoomChatSheet] — this
/// is a window onto the existing chat, never a second chat system.
///
/// Tapping a bubble opens the full chat (via [onOpenChat]). Renders
/// nothing while the room has no messages.
class RecentRoomMessages extends StatelessWidget {
  const RecentRoomMessages({
    required this.roomId,
    required this.onOpenChat,
    this.service,
    super.key,
  });

  final String roomId;
  final VoidCallback onOpenChat;
  final RoomService? service;

  @override
  Widget build(BuildContext context) {
    final rooms = service ?? RoomService();
    return StreamBuilder<List<RoomMessage>>(
      stream: rooms.watchRoomMessages(roomId),
      builder: (context, snapshot) {
        // watchRoomMessages is newest-first; show the latest two in
        // top-down chronological order like the mockups.
        final latest = (snapshot.data ?? const <RoomMessage>[])
            .take(2)
            .toList(growable: false)
            .reversed
            .toList(growable: false);
        if (latest.isEmpty) return const SizedBox.shrink();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final message in latest)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _MessageBubble(message: message, onTap: onOpenChat),
              ),
          ],
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onTap});

  final RoomMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        UserAvatar(
          radius: 14,
          photoUrl: message.senderPhotoUrl,
          displayName: message.senderName,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF191329).withValues(alpha: .92),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: .10)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                message.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFEDE7F5), fontSize: 13),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
