import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
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
  static const Color _surface2 = Color(0xFF1A1424);
  static const Color _border = Color(0xFF30263F);
  static const Color _muted = Color(0xFF9D95AD);
  static const Color _primary = Color(0xFF9D20FF);

  final MessageService _messageService = MessageService();
  final FriendService _friendService = FriendService();
  final TextEditingController _searchController = TextEditingController();

  late final Stream<List<Conversation>> _conversationsStream;
  late final Stream<List<FriendUser>> _friendsStream;

  String _query = '';
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _conversationsStream = _messageService.watchConversations(
      includeArchived: true,
    );
    _friendsStream = _friendService.watchFriends();
    _searchController.addListener(_handleSearch);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearch)
      ..dispose();
    super.dispose();
  }

  void _handleSearch() {
    final value = _searchController.text.trim().toLowerCase();

    if (value == _query) {
      return;
    }

    setState(() => _query = value);
  }

  Future<void> _openConversation(Conversation conversation) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == null) {
      return;
    }

    final otherUserId = conversation.otherUserId(currentUserId);

    if (conversation.isArchivedFor(currentUserId)) {
      await _messageService.unarchiveConversation(conversation.id);
    }

    if (!mounted) {
      return;
    }

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

  Future<void> _startChat(FriendUser friend) async {
    try {
      final conversationId = await _messageService.openOrCreateConversation(
        otherUserId: friend.id,
        otherDisplayName: friend.displayName,
        otherEmail: friend.email,
        otherPhotoUrl: friend.photoUrl ?? '',
      );

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            otherUserId: friend.id,
            otherDisplayName: friend.displayName,
            otherEmail: friend.email,
            otherPhotoUrl: friend.photoUrl ?? '',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _showNewMessageSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _NewMessageSheet(
          friendsStream: _friendsStream,
          onFriendSelected: (friend) {
            Navigator.pop(sheetContext);
            unawaited(_startChat(friend));
          },
        );
      },
    );
  }

  Future<void> _archiveConversation(Conversation conversation) async {
    try {
      await _messageService.archiveConversation(conversation.id);
      if (mounted) {
        _showMessage('Conversation archived.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not archive this conversation.');
      }
    }
  }

  Future<void> _toggleMute(Conversation conversation, bool isMuted) async {
    try {
      await _messageService.setConversationMuted(
        conversationId: conversation.id,
        muted: !isMuted,
      );

      if (mounted) {
        _showMessage(
          isMuted ? 'Notifications turned on.' : 'Conversation muted.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not update notifications.');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2A1939),
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
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
            center: Alignment(-.86, -.96),
            radius: 1.25,
            colors: [Color(0xFF28103F), Color(0xFF100B1B), _background],
            stops: [0, .38, 1],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _MessagesHeader(
                showArchived: _showArchived,
                onNewMessage: _showNewMessageSheet,
                onToggleArchived: () {
                  setState(() => _showArchived = !_showArchived);
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 13),
                child: _SearchField(controller: _searchController),
              ),
              _FriendsRow(
                friendsStream: _friendsStream,
                onFriendSelected: _startChat,
                onAdd: _showNewMessageSheet,
              ),
              const SizedBox(height: 9),
              Expanded(
                child: StreamBuilder<List<Conversation>>(
                  stream: _conversationsStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: _primary,
                          strokeWidth: 2.5,
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return _MessagesError(
                        message: _readableError(snapshot.error),
                      );
                    }

                    if (currentUserId == null) {
                      return const _MessagesError(
                        message: 'Sign in to open your chats.',
                      );
                    }

                    final allConversations =
                        snapshot.data ?? const <Conversation>[];
                    final conversations = allConversations
                        .where((conversation) {
                          final archived = conversation.isArchivedFor(
                            currentUserId,
                          );

                          if (_showArchived != archived) {
                            return false;
                          }

                          if (_query.isEmpty) {
                            return true;
                          }

                          final otherId = conversation.otherUserId(
                            currentUserId,
                          );
                          final name = conversation
                              .displayNameFor(otherId)
                              .toLowerCase();
                          final email = conversation
                              .emailFor(otherId)
                              .toLowerCase();
                          final preview = conversation
                              .previewFor(currentUserId)
                              .toLowerCase();

                          return name.contains(_query) ||
                              email.contains(_query) ||
                              preview.contains(_query);
                        })
                        .toList(growable: false);

                    if (conversations.isEmpty) {
                      return _EmptyMessages(
                        archived: _showArchived,
                        hasSearch: _query.isNotEmpty,
                        onNewMessage: _showNewMessageSheet,
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 118),
                      itemCount: conversations.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final conversation = conversations[index];
                        final muted = conversation.isMutedFor(currentUserId);

                        return _ConversationTile(
                          conversation: conversation,
                          currentUserId: currentUserId,
                          muted: muted,
                          onTap: () => _openConversation(conversation),
                          onArchive: () => _archiveConversation(conversation),
                          onToggleMute: () => _toggleMute(conversation, muted),
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

    if (message.contains('permission-denied')) {
      return 'Firestore permission denied. Check your security rules.';
    }

    if (message.contains('failed-precondition') || message.contains('index')) {
      return 'Firestore needs an index for conversations.';
    }

    return 'Could not load your conversations.';
  }
}

class _MessagesHeader extends StatelessWidget {
  const _MessagesHeader({
    required this.showArchived,
    required this.onNewMessage,
    required this.onToggleArchived,
  });

  final bool showArchived;
  final VoidCallback onNewMessage;
  final VoidCallback onToggleArchived;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showArchived ? 'Archived' : 'Chats',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.9,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  showArchived
                      ? 'Conversations kept out of your inbox.'
                      : 'Private conversations with your friends.',
                  style: const TextStyle(
                    color: _MessagesScreenState._muted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          _HeaderButton(
            icon: showArchived ? Icons.inbox_rounded : Icons.archive_outlined,
            onTap: onToggleArchived,
          ),
          const SizedBox(width: 9),
          _HeaderButton(
            icon: Icons.edit_square,
            onTap: onNewMessage,
            highlighted: true,
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted
          ? _MessagesScreenState._primary
          : _MessagesScreenState._surface,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: highlighted
                ? null
                : Border.all(color: _MessagesScreenState._border),
          ),
          child: Icon(icon, color: Colors.white, size: 21),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Search',
        hintStyle: const TextStyle(color: _MessagesScreenState._muted),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: _MessagesScreenState._muted,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) {
              return const SizedBox.shrink();
            }

            return IconButton(
              onPressed: controller.clear,
              icon: const Icon(
                Icons.close_rounded,
                color: _MessagesScreenState._muted,
              ),
            );
          },
        ),
        filled: true,
        fillColor: _MessagesScreenState._surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: _MessagesScreenState._border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: _MessagesScreenState._border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: _MessagesScreenState._primary),
        ),
      ),
    );
  }
}

class _FriendsRow extends StatelessWidget {
  const _FriendsRow({
    required this.friendsStream,
    required this.onFriendSelected,
    required this.onAdd,
  });

  final Stream<List<FriendUser>> friendsStream;
  final ValueChanged<FriendUser> onFriendSelected;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: StreamBuilder<List<FriendUser>>(
        stream: friendsStream,
        builder: (context, snapshot) {
          final friends = snapshot.data ?? const <FriendUser>[];

          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            children: [
              _FriendStory(label: 'New', icon: Icons.add_rounded, onTap: onAdd),
              ...friends
                  .take(12)
                  .map(
                    (friend) => _FriendStory(
                      label: friend.displayName,
                      friend: friend,
                      onTap: () => onFriendSelected(friend),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _FriendStory extends StatelessWidget {
  const _FriendStory({
    required this.label,
    required this.onTap,
    this.friend,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final FriendUser? friend;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final user = friend;
    final hasPhoto = user?.photoUrl?.trim().isNotEmpty == true;

    return SizedBox(
      width: 76,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFFF416C),
                        Color(0xFFB42DFF),
                        Color(0xFF5D00D7),
                      ],
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 27,
                    backgroundColor: _MessagesScreenState._surface2,
                    backgroundImage: hasPhoto
                        ? NetworkImage(user!.photoUrl!)
                        : null,
                    child: icon != null
                        ? Icon(icon, color: Colors.white, size: 26)
                        : hasPhoto
                        ? null
                        : Text(
                            user?.initial ?? '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
                if (user?.isOnline == true)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: const Color(0xFF20D66B),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _MessagesScreenState._background,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.currentUserId,
    required this.muted,
    required this.onTap,
    required this.onArchive,
    required this.onToggleMute,
  });

  final Conversation conversation;
  final String currentUserId;
  final bool muted;
  final VoidCallback onTap;
  final VoidCallback onArchive;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    final otherUserId = conversation.otherUserId(currentUserId);
    final name = conversation.displayNameFor(otherUserId);
    final photoUrl = conversation.photoUrlFor(otherUserId);
    final unread = conversation.unreadCountFor(currentUserId);
    final preview = conversation.previewFor(currentUserId);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showActions(context),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: unread > 0 ? const Color(0x141E8BFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              _ConversationAvatar(
                name: name,
                photoUrl: photoUrl,
                userId: otherUserId,
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
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: unread > 0
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _relativeTime(conversation.updatedAt),
                          style: TextStyle(
                            color: unread > 0
                                ? const Color(0xFFD174FF)
                                : _MessagesScreenState._muted,
                            fontSize: 11,
                            fontWeight: unread > 0
                                ? FontWeight.w800
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: unread > 0
                                  ? Colors.white
                                  : _MessagesScreenState._muted,
                              fontSize: 13,
                              fontWeight: unread > 0
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (muted) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.notifications_off_outlined,
                            color: _MessagesScreenState._muted,
                            size: 16,
                          ),
                        ],
                        if (unread > 0) ...[
                          const SizedBox(width: 9),
                          Container(
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: const BoxDecoration(
                              color: _MessagesScreenState._primary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
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

  Future<void> _showActions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _ConversationActionsSheet(
          muted: muted,
          onMute: () {
            Navigator.pop(sheetContext);
            onToggleMute();
          },
          onArchive: () {
            Navigator.pop(sheetContext);
            onArchive();
          },
        );
      },
    );
  }

  static String _relativeTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (date.millisecondsSinceEpoch == 0) {
      return '';
    }

    if (difference.inMinutes < 1) {
      return 'now';
    }

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    }

    if (difference.inHours < 24) {
      return '${difference.inHours}h';
    }

    if (difference.inDays < 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[date.weekday - 1];
    }

    return '${date.day}/${date.month}';
  }
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({
    required this.name,
    required this.photoUrl,
    required this.userId,
  });

  final String name;
  final String photoUrl;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final service = MessageService();

    return StreamBuilder<ChatPresence>(
      stream: service.watchUserPresence(userId),
      builder: (context, snapshot) {
        final online = snapshot.data?.isOnline ?? false;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 29,
              backgroundColor: const Color(0xFF67259A),
              backgroundImage: photoUrl.trim().isNotEmpty
                  ? NetworkImage(photoUrl)
                  : null,
              child: photoUrl.trim().isNotEmpty
                  ? null
                  : Text(
                      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
            if (online)
              Positioned(
                right: 1,
                bottom: 1,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFF20D66B),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _MessagesScreenState._background,
                      width: 3,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ConversationActionsSheet extends StatelessWidget {
  const _ConversationActionsSheet({
    required this.muted,
    required this.onMute,
    required this.onArchive,
  });

  final bool muted;
  final VoidCallback onMute;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        18 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF15101E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 14),
          ListTile(
            onTap: onMute,
            leading: Icon(
              muted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              color: Colors.white,
            ),
            title: Text(
              muted ? 'Unmute messages' : 'Mute messages',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          ListTile(
            onTap: onArchive,
            leading: const Icon(Icons.archive_outlined, color: Colors.white),
            title: const Text(
              'Archive conversation',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewMessageSheet extends StatefulWidget {
  const _NewMessageSheet({
    required this.friendsStream,
    required this.onFriendSelected,
  });

  final Stream<List<FriendUser>> friendsStream;
  final ValueChanged<FriendUser> onFriendSelected;

  @override
  State<_NewMessageSheet> createState() => _NewMessageSheetState();
}

class _NewMessageSheetState extends State<_NewMessageSheet> {
  final TextEditingController _controller = TextEditingController();

  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final value = _controller.text.trim().toLowerCase();

      if (value != _query) {
        setState(() => _query = value);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .76,
      minChildSize: .5,
      maxChildSize: .94,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF120D1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 11),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Row(
                  children: [
                    Text(
                      'New message',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: _SearchField(controller: _controller),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: StreamBuilder<List<FriendUser>>(
                  stream: widget.friendsStream,
                  builder: (context, snapshot) {
                    final friends = snapshot.data ?? const <FriendUser>[];
                    final filtered = friends
                        .where((friend) {
                          if (_query.isEmpty) {
                            return true;
                          }

                          return friend.displayName.toLowerCase().contains(
                                _query,
                              ) ||
                              friend.email.toLowerCase().contains(_query);
                        })
                        .toList(growable: false);

                    if (snapshot.connectionState == ConnectionState.waiting &&
                        friends.isEmpty) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: _MessagesScreenState._primary,
                        ),
                      );
                    }

                    if (filtered.isEmpty) {
                      return const Center(
                        child: Text(
                          'No friends found.',
                          style: TextStyle(color: _MessagesScreenState._muted),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final friend = filtered[index];

                        return ListTile(
                          onTap: () => widget.onFriendSelected(friend),
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 25,
                                backgroundColor: const Color(0xFF67259A),
                                backgroundImage:
                                    friend.photoUrl?.trim().isNotEmpty == true
                                    ? NetworkImage(friend.photoUrl!)
                                    : null,
                                child:
                                    friend.photoUrl?.trim().isNotEmpty == true
                                    ? null
                                    : Text(
                                        friend.initial,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                              ),
                              if (friend.isOnline)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF20D66B),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF120D1A),
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Text(
                            friend.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            friend.isOnline ? 'Active now' : friend.email,
                            style: const TextStyle(
                              color: _MessagesScreenState._muted,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: _MessagesScreenState._muted,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages({
    required this.archived,
    required this.hasSearch,
    required this.onNewMessage,
  });

  final bool archived;
  final bool hasSearch;
  final VoidCallback onNewMessage;

  @override
  Widget build(BuildContext context) {
    final title = hasSearch
        ? 'No matching chats'
        : archived
        ? 'No archived chats'
        : 'Your inbox is quiet';
    final subtitle = hasSearch
        ? 'Try another name or message.'
        : archived
        ? 'Archived conversations will appear here.'
        : 'Start a private conversation with one of your friends.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFB82FFF), Color(0xFF6D19E7)],
                ),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Icon(
                archived
                    ? Icons.archive_outlined
                    : Icons.chat_bubble_outline_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _MessagesScreenState._muted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (!archived && !hasSearch) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onNewMessage,
                style: FilledButton.styleFrom(
                  backgroundColor: _MessagesScreenState._primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                ),
                icon: const Icon(Icons.edit_square),
                label: const Text(
                  'New message',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
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
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _MessagesScreenState._muted,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
