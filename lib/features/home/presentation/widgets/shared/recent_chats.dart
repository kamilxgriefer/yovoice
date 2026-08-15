import 'package:flutter/material.dart';

import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// A compact Home preview of this account's three most recently updated DMs.
/// [MessageService.watchConversations] already supplies the list newest-first
/// and excludes archived conversations, so this widget only presents it.
class RecentChats extends StatelessWidget {
  const RecentChats({
    required this.snapshot,
    required this.currentUserId,
    required this.onOpenConversation,
    required this.onFindFriends,
    super.key,
  });

  final AsyncSnapshot<List<Conversation>> snapshot;
  final String currentUserId;
  final ValueChanged<Conversation> onOpenConversation;
  final VoidCallback onFindFriends;

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return const SizedBox(
        height: 132,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }

    if (snapshot.hasError) {
      return const _RecentChatsMessage(
        icon: Icons.cloud_off_rounded,
        text: 'Your recent chats could not be loaded.',
      );
    }

    final conversations = (snapshot.data ?? const <Conversation>[])
        .take(3)
        .toList(growable: false);
    if (conversations.isEmpty) {
      return _RecentChatsMessage(
        icon: Icons.chat_bubble_outline_rounded,
        text: 'Your latest chats with friends will appear here.',
        actionLabel: 'Find friends',
        onAction: onFindFriends,
      );
    }

    return SizedBox(
      height: 132,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < conversations.length; index++) ...[
            if (index > 0) const SizedBox(width: 10),
            Expanded(
              child: _RecentChatCard(
                conversation: conversations[index],
                currentUserId: currentUserId,
                onTap: () => onOpenConversation(conversations[index]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentChatCard extends StatelessWidget {
  const _RecentChatCard({
    required this.conversation,
    required this.currentUserId,
    required this.onTap,
  });

  final Conversation conversation;
  final String currentUserId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final otherUserId = conversation.otherUserId(currentUserId);
    final unread = conversation.unreadCountFor(currentUserId);
    return SizedBox(
      height: 132,
      child: Material(
        color: const Color(0xFF181122),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF332641)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UserAvatar(
                      displayName: conversation.displayNameFor(otherUserId),
                      photoUrl: conversation.photoUrlFor(otherUserId),
                      radius: 20,
                    ),
                    const Spacer(),
                    if (unread > 0)
                      Container(
                        constraints: const BoxConstraints(minWidth: 20),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9D20FF),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  conversation.displayNameFor(otherUserId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  conversation.previewFor(currentUserId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFA69CB2),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentChatsMessage extends StatelessWidget {
  const _RecentChatsMessage({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181122),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF332641)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFC985FF)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Color(0xFFA69CB2), fontSize: 13),
            ),
          ),
          if (onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
