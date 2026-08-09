import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/features/rooms/data/models/room_message.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The room chat quick-reaction set (board screen 2). Persistent,
/// rules-backed message reactions — not ephemeral confetti.
const roomReactionEmojis = ['❤️', '😂', '👏', '🔥', '💯'];

/// Opens the live room chat as a draggable sheet over the stage — chat
/// belongs to the room, the audio never stops, and every row uses the
/// canonical avatar component. [accent] matches the room's visual
/// family; [isHost] unlocks moderation (delete).
Future<void> showRoomChatSheet(
  BuildContext context, {
  required String roomId,
  required bool isHost,
  Color accent = const Color(0xFF9D20FF),
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => RoomChatSheet(
      roomId: roomId,
      isHost: isHost,
      accent: accent,
    ),
  );
}

class RoomChatSheet extends StatefulWidget {
  const RoomChatSheet({
    required this.roomId,
    required this.isHost,
    required this.accent,
    super.key,
  });

  final String roomId;
  final bool isHost;
  final Color accent;

  @override
  State<RoomChatSheet> createState() => _RoomChatSheetState();
}

class _RoomChatSheetState extends State<RoomChatSheet> {
  final _service = RoomService();
  final _composer = TextEditingController();
  late final Stream<List<RoomMessage>> _messages =
      _service.watchRoomMessages(widget.roomId);
  bool _sending = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  void _snack(Object error, String fallback) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(intentionalOrFriendly(error, fallback: fallback))),
      );
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.sendRoomMessage(roomId: widget.roomId, text: text);
      _composer.clear();
    } catch (error) {
      _snack(error, "Couldn't send that message. Please try again.");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleReaction(RoomMessage message, String emoji) async {
    try {
      await _service.toggleRoomMessageReaction(
        roomId: widget.roomId,
        messageId: message.id,
        emoji: emoji,
      );
    } catch (error) {
      _snack(error, "Couldn't react. Please try again.");
    }
  }

  Future<void> _messageActions(RoomMessage message) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF171021),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in roomReactionEmojis)
                    InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _toggleReaction(message, emoji);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.isHost)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFFF6A76),
                ),
                title: const Text(
                  'Delete message',
                  style: TextStyle(color: Color(0xFFFF6A76)),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    await _service.deleteRoomMessage(
                      roomId: widget.roomId,
                      messageId: message.id,
                    );
                  } catch (error) {
                    _snack(error, "Couldn't delete that message.");
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .62,
      minChildSize: .4,
      maxChildSize: .92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF120C1B),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(
              top: BorderSide(color: widget.accent.withValues(alpha: .4)),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF51475E),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Room chat',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Icon(Icons.forum_rounded, color: widget.accent, size: 20),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<RoomMessage>>(
                  stream: _messages,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          friendlyErrorMessage(
                            snapshot.error!,
                            fallback: "Couldn't load the chat.",
                          ),
                          style: const TextStyle(color: Color(0xFFA69CAF)),
                        ),
                      );
                    }
                    final messages =
                        snapshot.data ?? const <RoomMessage>[];
                    if (messages.isEmpty) {
                      return const Center(
                        child: Text(
                          'Say something — the room can hear you type.',
                          style: TextStyle(color: Color(0xFF9E92A8)),
                        ),
                      );
                    }
                    return ListView.builder(
                      controller: scrollController,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        return _MessageRow(
                          message: message,
                          accent: widget.accent,
                          isMine: message.senderId == _uid,
                          onLongPress: () => _messageActions(message),
                          onAvatarTap: () => showProfilePreview(
                            context,
                            userId: message.senderId,
                            displayName: message.senderName,
                            photoUrl: message.senderPhotoUrl,
                          ),
                          onReactionTap: (emoji) =>
                              _toggleReaction(message, emoji),
                        );
                      },
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 14,
                    right: 14,
                    top: 8,
                    bottom: 10 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _composer,
                          maxLength: 500,
                          style: const TextStyle(color: Colors.white),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: 'Say something…',
                            hintStyle:
                                const TextStyle(color: Color(0xFF766B80)),
                            filled: true,
                            fillColor: const Color(0xFF1C1428),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: const BorderSide(
                                color: Color(0xFF3A2C49),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: const BorderSide(
                                color: Color(0xFF3A2C49),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _sending ? null : _send,
                        style: IconButton.styleFrom(
                          backgroundColor: widget.accent,
                          minimumSize: const Size(46, 46),
                        ),
                        icon: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.accent,
    required this.isMine,
    required this.onLongPress,
    required this.onAvatarTap,
    required this.onReactionTap,
  });

  final RoomMessage message;
  final Color accent;
  final bool isMine;
  final VoidCallback onLongPress;
  final VoidCallback onAvatarTap;
  final ValueChanged<String> onReactionTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onAvatarTap,
            child: UserAvatar(
              radius: 16,
              photoUrl: message.senderPhotoUrl,
              displayName: message.senderName,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onLongPress: onLongPress,
              borderRadius: BorderRadius.circular(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          message.senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isMine ? accent : const Color(0xFFCFC5D8),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1428),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF2C2138)),
                    ),
                    child: Text(
                      message.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ),
                  if (message.reactions.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final entry in message.reactions.entries)
                          InkWell(
                            onTap: () => onReactionTap(entry.key),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: .14),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: accent.withValues(alpha: .4),
                                ),
                              ),
                              child: Text(
                                '${entry.key} ${entry.value.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
