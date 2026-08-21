import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/features/rooms/data/models/room_message.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_context_action.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The room chat quick-reaction set (board screen 2). Persistent,
/// rules-backed message reactions — not ephemeral confetti.
const roomReactionEmojis = ['❤️', '😂', '👏', '🔥', '💯'];

/// The real room chat surface. It is permanently visible beside the stage on
/// desktop and fills the room workspace when selected on a compact viewport.
class RoomChatPanel extends StatefulWidget {
  const RoomChatPanel({
    required this.roomId,
    required this.isHost,
    required this.accent,
    this.onClose,
    this.scrollController,
    this.service,
    this.currentUserId,
    super.key,
  });

  final String roomId;
  final bool isHost;
  final Color accent;
  final VoidCallback? onClose;
  final ScrollController? scrollController;
  final RoomService? service;
  final String? currentUserId;

  @override
  State<RoomChatPanel> createState() => _RoomChatPanelState();
}

class _RoomChatPanelState extends State<RoomChatPanel> {
  late final _service = widget.service ?? RoomService();
  final _composer = TextEditingController();
  late final Stream<List<RoomMessage>> _messages = _service.watchRoomMessages(
    widget.roomId,
  );
  bool _sending = false;
  bool _emojiRowOpen = false;

  String get _uid =>
      widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '';

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
        SnackBar(
          content: Text(intentionalOrFriendly(error, fallback: fallback)),
        ),
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

  /// Inserts one of the room's quick emojis at the caret. Reuses the same
  /// vocabulary as message reactions — one set, no invented catalog.
  void _insertEmoji(String emoji) {
    final value = _composer.value;
    final selection = value.selection;
    if (!selection.isValid) {
      _composer.text = value.text + emoji;
      _composer.selection = TextSelection.collapsed(
        offset: _composer.text.length,
      );
      return;
    }
    final text = value.text.replaceRange(
      selection.start,
      selection.end,
      emoji,
    );
    _composer.value = value.copyWith(
      text: text,
      selection: TextSelection.collapsed(
        offset: selection.start + emoji.length,
      ),
      composing: TextRange.empty,
    );
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
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(
        context,
        maxWidth: 520,
      ),
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
    return Container(
      key: const ValueKey('room-chat-surface'),
      decoration: BoxDecoration(
        color: const Color(0xFF110B19),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 8),
            child: Row(
              children: [
                Icon(Icons.forum_rounded, color: widget.accent, size: 19),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'Room chat',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (widget.onClose != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Back to stage',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.white70,
                  ),
                ],
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
                final messages = snapshot.data ?? const <RoomMessage>[];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Say something — the room can hear you type.',
                      style: TextStyle(color: Color(0xFF9E92A8)),
                    ),
                  );
                }
                return ListView.builder(
                  controller: widget.scrollController,
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
                      onReactionTap: (emoji) => _toggleReaction(message, emoji),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(left: 10, right: 12, top: 8, bottom: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The quick-emoji row: the same five reactions the room
                  // already uses, inserted into the composer. Opt-in, so
                  // the resting composer stays a single calm line.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    child: !_emojiRowOpen
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Wrap(
                              spacing: 4,
                              alignment: WrapAlignment.center,
                              children: [
                                for (final emoji in roomReactionEmojis)
                                  InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () => _insertEmoji(emoji),
                                    child: Padding(
                                      padding: const EdgeInsets.all(7),
                                      child: Text(
                                        emoji,
                                        style: const TextStyle(fontSize: 21),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Quick emoji',
                        onPressed: () =>
                            setState(() => _emojiRowOpen = !_emojiRowOpen),
                        icon: Icon(
                          _emojiRowOpen
                              ? Icons.keyboard_alt_outlined
                              : Icons.emoji_emotions_outlined,
                          size: 22,
                        ),
                        color: _emojiRowOpen
                            ? widget.accent
                            : const Color(0xFF9E92A8),
                      ),
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
                            hintStyle: const TextStyle(
                              color: Color(0xFF766B80),
                            ),
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
                ],
              ),
            ),
          ),
        ],
      ),
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
          Semantics(
            button: true,
            label: 'Open ${message.senderName} profile',
            child: Tooltip(
              message: 'Open ${message.senderName} profile',
              child: InkResponse(
                onTap: onAvatarTap,
                radius: 22,
                child: UserAvatar(
                  radius: 16,
                  photoUrl: message.senderPhotoUrl,
                  displayName: message.senderName,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AccessibleContextAction(
              onOpen: onLongPress,
              semanticLabel: 'Open actions for ${message.senderName} message',
              borderRadius: 16,
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
                      const SizedBox(width: 6),
                      UserIdentityBadges(uid: message.senderId),
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
