import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/friends/presentation/screens/add_friend_screen.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  static const Color _background = Color(0xFF080711);
  static const Color _surface = Color(0xFF12101D);
  static const Color _border = Color(0xFF2C253B);
  static const Color _secondaryText = Color(0xFF9D95AD);

  final MessageService _messageService = MessageService();

  late final Stream<List<Conversation>> _conversationsStream;

  @override
  void initState() {
    super.initState();
    _conversationsStream = _messageService.watchConversations();
  }

  Future<void> _openAddFriend() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const AddFriendScreen(),
      ),
    );
  }

  Future<void> _openConversation(Conversation conversation) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == null) {
      return;
    }

    final otherUserId = conversation.otherUserId(currentUserId);

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          conversationId: conversation.id,
          otherUserId: otherUserId,
          otherDisplayName: conversation.displayNameFor(otherUserId),
          otherEmail: conversation.emailFor(otherUserId),
          otherPhotoUrl: conversation.photoUrlFor(otherUserId),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.85, -0.95),
            radius: 1.25,
            colors: <Color>[
              Color(0xFF24103B),
              Color(0xFF100B1B),
              _background,
            ],
            stops: <double>[0, 0.38, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _MessagesHeader(onAddFriend: _openAddFriend),
              Expanded(
                child: StreamBuilder<List<Conversation>>(
                  stream: _conversationsStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFB348FF),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return _MessagesError(
                        message: _readableError(snapshot.error),
                      );
                    }

                    final conversations =
                        snapshot.data ?? const <Conversation>[];

                    if (conversations.isEmpty || currentUserId == null) {
                      return _EmptyMessages(onAddFriend: _openAddFriend);
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 118),
                      itemCount: conversations.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final conversation = conversations[index];

                        return _ConversationTile(
                          conversation: conversation,
                          currentUserId: currentUserId,
                          onTap: () => _openConversation(conversation),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _readableError(Object? error) {
    final message = error.toString();

    if (message.contains('failed-precondition') || message.contains('index')) {
      return 'Firestore needs an index for conversations. Open the Firebase link shown in the debug console and create it.';
    }

    if (message.contains('permission-denied')) {
      return 'Firestore permission denied. Check your security rules.';
    }

    return 'Could not load your conversations.';
  }
}

class _MessagesHeader extends StatelessWidget {
  const _MessagesHeader({required this.onAddFriend});

  final VoidCallback onAddFriend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Messages',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Stay close to your people.',
                  style: TextStyle(
                    color: _MessagesScreenState._secondaryText,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: _MessagesScreenState._surface,
            borderRadius: BorderRadius.circular(15),
            child: InkWell(
              onTap: onAddFriend,
              borderRadius: BorderRadius.circular(15),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _MessagesScreenState._border),
                ),
                child: const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
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
    final displayName = conversation.displayNameFor(otherUserId);
    final photoUrl = conversation.photoUrlFor(otherUserId);
    final unreadCount = conversation.unreadCountFor(currentUserId);
    final hasUnread = unreadCount > 0;
    final isMine = conversation.lastMessageSenderId == currentUserId;

    return Material(
      color: _MessagesScreenState._surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: hasUnread
                  ? const Color(0xFF7130A5)
                  : _MessagesScreenState._border,
            ),
          ),
          child: Row(
            children: [
              _Avatar(
                displayName: displayName,
                photoUrl: photoUrl,
                size: 54,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: hasUnread
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatConversationTime(
                            context,
                            conversation.updatedAt,
                          ),
                          style: TextStyle(
                            color: hasUnread
                                ? const Color(0xFFC05AFF)
                                : _MessagesScreenState._secondaryText,
                            fontSize: 11,
                            fontWeight: hasUnread
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _previewText(
                              conversation,
                              isMine: isMine,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasUnread
                                  ? const Color(0xFFE8E2ED)
                                  : _MessagesScreenState._secondaryText,
                              fontSize: 13,
                              fontWeight: hasUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 9),
                          Container(
                            constraints: const BoxConstraints(minWidth: 22),
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF9D20FF),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _previewText(
    Conversation conversation, {
    required bool isMine,
  }) {
    if (conversation.lastMessage.isEmpty) {
      return 'Start a conversation';
    }

    final prefix = isMine ? 'You: ' : '';

    switch (conversation.lastMessageType) {
      case MessageType.voice:
        return '${prefix}Voice message';
      case MessageType.image:
        return '${prefix}Photo';
      case MessageType.text:
        return '$prefix${conversation.lastMessage}';
    }
  }

  static String _formatConversationTime(
    BuildContext context,
    DateTime dateTime,
  ) {
    if (dateTime.millisecondsSinceEpoch == 0) {
      return '';
    }

    final local = dateTime.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(local.year, local.month, local.day);
    final difference = today.difference(messageDay).inDays;

    if (difference == 0) {
      return MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(local),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
    }

    if (difference == 1) {
      return 'Yesterday';
    }

    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.displayName,
    required this.photoUrl,
    required this.size,
  });

  final String displayName;
  final String photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = displayName.trim().isEmpty
        ? '?'
        : displayName.trim().characters.first.toUpperCase();

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: <Color>[Color(0xFFC32BFF), Color(0xFF6D25FF)],
        ),
      ),
      child: ClipOval(
        child: photoUrl.trim().isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return _AvatarFallback(initial: initial);
                },
              )
            : _AvatarFallback(initial: initial),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF271834),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages({required this.onAddFriend});

  final VoidCallback onAddFriend;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 120),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: const Color(0xFF9C42FF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Color(0xFFB348FF),
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No conversations yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add a friend and start your first conversation.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _MessagesScreenState._secondaryText,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAddFriend,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add friend'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF9D20FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagesError extends StatelessWidget {
  const _MessagesError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.fromLTRB(18, 20, 18, 120),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF21121B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF5B293C)),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFCDB3BD),
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}
