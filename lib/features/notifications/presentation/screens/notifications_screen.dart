import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/notification_router.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const Color _background = Color(0xFF080711);
  static const Color _surface = Color(0xFF12101D);
  static const Color _border = Color(0xFF2C253B);
  static const Color _secondaryText = Color(0xFF9D95AD);
  static const Color _primary = Color(0xFFB348FF);

  final FriendService _friendService = FriendService();
  final MessageService _messageService = MessageService();
  final NotificationService _notificationService = NotificationService();

  late final Stream<List<FriendRequest>> _friendRequestsStream;
  late final Stream<List<Conversation>> _conversationsStream;

  final Set<String> _processingRequestIds = <String>{};
  int _notificationsLimit = 50;

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _friendRequestsStream = _friendService.watchFriendRequests();
    _conversationsStream = _messageService.watchConversations();
  }

  Future<void> _acceptRequest(FriendRequest request) async {
    await _processRequest(
      request,
      () => _friendService.acceptFriendRequest(request),
      'Friend request accepted.',
    );
  }

  Future<void> _declineRequest(FriendRequest request) async {
    await _processRequest(
      request,
      () => _friendService.declineFriendRequest(request.senderId),
      'Friend request declined.',
    );
  }

  Future<void> _processRequest(
    FriendRequest request,
    Future<void> Function() action,
    String successMessage,
  ) async {
    if (_processingRequestIds.contains(request.senderId)) {
      return;
    }

    setState(() => _processingRequestIds.add(request.senderId));

    try {
      await action();

      if (!mounted) {
        return;
      }

      _showMessage(successMessage);
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(_readableError(error), isError: true);
    } finally {
      if (mounted) {
        setState(() => _processingRequestIds.remove(request.senderId));
      }
    }
  }

  Future<void> _openConversation(Conversation conversation) async {
    final currentUserId = _currentUserId;
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

  Future<void> _openNotification(AppNotification notification) async {
    if (!notification.isRead) {
      unawaited(_notificationService.markAsRead(notification.id));
    }
    await NotificationRouter.route(
      type: notification.type,
      targetId: notification.targetId,
      actorId: notification.actorId,
    );
  }

  Future<void> _deleteNotification(AppNotification notification) async {
    try {
      await _notificationService.deleteNotification(notification.id);
    } catch (error) {
      if (!mounted) return;
      _showMessage(_readableError(error), isError: true);
    }
  }

  Future<void> _markAllNotificationsRead() async {
    try {
      await _notificationService.markAllAsRead();
    } catch (error) {
      if (!mounted) return;
      _showMessage(_readableError(error), isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError
            ? const Color(0xFF481C30)
            : const Color(0xFF203D2C),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  String _readableError(Object error) {
    final message = error.toString();

    if (message.contains('permission-denied')) {
      return 'Firestore permission denied. Check your security rules.';
    }

    if (message.contains('unavailable')) {
      return 'Service is temporarily unavailable.';
    }

    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.85, -0.95),
            radius: 1.25,
            colors: [Color(0xFF24103B), Color(0xFF100B1B), _background],
            stops: [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back',
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Friend requests, messages and activity',
                  style: TextStyle(
                    color: _secondaryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return StreamBuilder<List<FriendRequest>>(
      stream: _friendRequestsStream,
      builder: (context, friendSnapshot) {
        return StreamBuilder<List<Conversation>>(
          stream: _conversationsStream,
          builder: (context, conversationSnapshot) {
            return StreamBuilder<List<AppNotification>>(
              key: ValueKey(_notificationsLimit),
              stream: _notificationService.watchNotifications(
                limit: _notificationsLimit,
              ),
              builder: (context, notificationSnapshot) {
                final isLoading =
                    (friendSnapshot.connectionState ==
                            ConnectionState.waiting &&
                        !friendSnapshot.hasData) ||
                    (conversationSnapshot.connectionState ==
                            ConnectionState.waiting &&
                        !conversationSnapshot.hasData) ||
                    (notificationSnapshot.connectionState ==
                            ConnectionState.waiting &&
                        !notificationSnapshot.hasData);

                if (isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _primary,
                    ),
                  );
                }

                if (friendSnapshot.hasError ||
                    conversationSnapshot.hasError ||
                    notificationSnapshot.hasError) {
                  return const _EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Could not load notifications',
                    subtitle:
                        'Check your connection and Firestore permissions.',
                  );
                }

                final requests =
                    friendSnapshot.data ?? const <FriendRequest>[];
                final conversations =
                    conversationSnapshot.data ?? const <Conversation>[];
                final notifications =
                    notificationSnapshot.data ?? const <AppNotification>[];
                final unreadConversations = conversations
                    .where(
                      (conversation) =>
                          conversation.unreadCountFor(_currentUserId) > 0,
                    )
                    .toList(growable: false);
                final unreadNotificationCount = notifications
                    .where((notification) => !notification.isRead)
                    .length;
                final groupedNotifications = _groupByDay(notifications);

                if (requests.isEmpty &&
                    unreadConversations.isEmpty &&
                    notifications.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'You are all caught up',
                    subtitle:
                        'New friend requests, messages and activity will '
                        'appear here.',
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
                  children: [
                    if (requests.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'Friend requests',
                        count: requests.length,
                      ),
                      const SizedBox(height: 10),
                      for (final request in requests) ...[
                        _FriendRequestCard(
                          request: request,
                          isProcessing: _processingRequestIds.contains(
                            request.senderId,
                          ),
                          onAccept: () => _acceptRequest(request),
                          onDecline: () => _declineRequest(request),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                    if (unreadConversations.isNotEmpty) ...[
                      if (requests.isNotEmpty) const SizedBox(height: 14),
                      _SectionHeader(
                        title: 'Unread messages',
                        count: unreadConversations.fold<int>(
                          0,
                          (sum, conversation) =>
                              sum +
                              conversation.unreadCountFor(_currentUserId),
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final conversation in unreadConversations) ...[
                        _UnreadMessageCard(
                          conversation: conversation,
                          currentUserId: _currentUserId,
                          onTap: () => _openConversation(conversation),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                    if (notifications.isNotEmpty) ...[
                      if (requests.isNotEmpty || unreadConversations.isNotEmpty)
                        const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _SectionHeader(
                              title: 'Activity',
                              count: unreadNotificationCount,
                            ),
                          ),
                          if (unreadNotificationCount > 0)
                            TextButton(
                              onPressed: _markAllNotificationsRead,
                              child: const Text(
                                'Mark all read',
                                style: TextStyle(
                                  color: _primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      for (final entry in groupedNotifications.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              color: _secondaryText,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        for (final notification in entry.value) ...[
                          _NotificationCard(
                            notification: notification,
                            onTap: () => _openNotification(notification),
                            onDismissed: () =>
                                _deleteNotification(notification),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                      if (notifications.length >= _notificationsLimit)
                        Center(
                          child: TextButton(
                            onPressed: () => setState(
                              () => _notificationsLimit += 50,
                            ),
                            child: const Text(
                              'Load more',
                              style: TextStyle(
                                color: _secondaryText,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Map<String, List<AppNotification>> _groupByDay(
    List<AppNotification> notifications,
  ) {
    final grouped = <String, List<AppNotification>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final notification in notifications) {
      final createdAt = notification.createdAt;
      final String label;
      if (createdAt == null) {
        label = 'Earlier';
      } else {
        final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
        if (day == today) {
          label = 'Today';
        } else if (day == yesterday) {
          label = 'Yesterday';
        } else {
          label =
              '${day.day.toString().padLeft(2, '0')}/'
              '${day.month.toString().padLeft(2, '0')}/${day.year}';
        }
      }
      grouped.putIfAbsent(label, () => []).add(notification);
    }
    return grouped;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF8A2BE2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _FriendRequestCard extends StatelessWidget {
  const _FriendRequestCard({
    required this.request,
    required this.isProcessing,
    required this.onAccept,
    required this.onDecline,
  });

  final FriendRequest request;
  final bool isProcessing;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final name = request.senderName.trim().isNotEmpty
        ? request.senderName.trim()
        : request.senderEmail.split('@').first;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _NotificationsScreenState._surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _NotificationsScreenState._border),
      ),
      child: Row(
        children: [
          _Avatar(name: name, photoUrl: request.senderPhotoUrl ?? ''),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sent you a friend request',
                  style: TextStyle(
                    color: _NotificationsScreenState._secondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isProcessing)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: _NotificationsScreenState._primary,
              ),
            )
          else ...[
            IconButton(
              tooltip: 'Decline',
              onPressed: onDecline,
              icon: const Icon(Icons.close_rounded, color: Color(0xFFFF6F8E)),
            ),
            IconButton(
              tooltip: 'Accept',
              onPressed: onAccept,
              icon: const Icon(Icons.check_rounded, color: Color(0xFF54DB8C)),
            ),
          ],
        ],
      ),
    );
  }
}

class _UnreadMessageCard extends StatelessWidget {
  const _UnreadMessageCard({
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
    final name = conversation.displayNameFor(otherUserId);
    final unreadCount = conversation.unreadCountFor(currentUserId);
    final preview = conversation.lastMessage.trim().isEmpty
        ? 'New message'
        : conversation.lastMessage.trim();

    return Material(
      color: _NotificationsScreenState._surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _NotificationsScreenState._border),
          ),
          child: Row(
            children: [
              _Avatar(
                name: name,
                photoUrl: conversation.photoUrlFor(otherUserId),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _NotificationsScreenState._secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF426F),
                  shape: BoxShape.circle,
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
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF766D82)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onDismissed,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  static const Map<NotificationType, IconData> _icons = {
    NotificationType.friendRequest: Icons.person_add_alt_1_rounded,
    NotificationType.friendAccepted: Icons.people_alt_rounded,
    NotificationType.follow: Icons.favorite_rounded,
    NotificationType.clubInvite: Icons.groups_rounded,
    NotificationType.clubInviteAccepted: Icons.groups_rounded,
    NotificationType.roomInvite: Icons.mic_rounded,
    NotificationType.broadcastInvite: Icons.campaign_rounded,
    NotificationType.directMessage: Icons.chat_bubble_rounded,
    NotificationType.mention: Icons.alternate_email_rounded,
    NotificationType.reply: Icons.reply_rounded,
    NotificationType.achievementUnlocked: Icons.emoji_events_rounded,
    NotificationType.moderation: Icons.shield_rounded,
    NotificationType.system: Icons.info_rounded,
  };

  String _relativeTime(DateTime? time) {
    if (time == null) return '';
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.day.toString().padLeft(2, '0')}/'
        '${time.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF481C30),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      child: Material(
        color: _NotificationsScreenState._surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: notification.isRead
                    ? _NotificationsScreenState._border
                    : _NotificationsScreenState._primary.withValues(
                        alpha: 0.45,
                      ),
              ),
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    _Avatar(
                      name: notification.actorName,
                      photoUrl: notification.actorPhotoUrl ?? '',
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1B1730),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _icons[notification.type] ??
                              Icons.notifications_rounded,
                          color: _NotificationsScreenState._primary,
                          size: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _relativeTime(notification.createdAt),
                        style: const TextStyle(
                          color: _NotificationsScreenState._secondaryText,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!notification.isRead) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: _NotificationsScreenState._primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.photoUrl});

  final String name;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return Container(
      width: 50,
      height: 50,
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFC32BFF), Color(0xFF6D25FF)],
        ),
      ),
      child: ClipOval(
        child: Container(
          color: const Color(0xFF2A173C),
          child: photoUrl.trim().isNotEmpty
              ? Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      _AvatarInitial(initial: initial),
                )
              : _AvatarInitial(initial: initial),
        ),
      ),
    );
  }
}

class _AvatarInitial extends StatelessWidget {
  const _AvatarInitial({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 50),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _NotificationsScreenState._primary.withValues(
                  alpha: 0.15,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                icon,
                color: _NotificationsScreenState._primary,
                size: 35,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _NotificationsScreenState._secondaryText,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
