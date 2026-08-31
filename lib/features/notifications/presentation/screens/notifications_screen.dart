import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/notification_router.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';

Color _notificationSuccess(BuildContext context) =>
    context.appPalette.successForeground;

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    this.isRootTab = false,
    this.friendService,
    this.messageService,
    this.notificationService,
    this.currentUserId,
    super.key,
  });

  /// True when this screen IS the shell's current content (the desktop
  /// rail's Notifications slot) rather than a pushed route — same flag
  /// FriendsScreen uses, so a root tab shows no dead back button.
  final bool isRootTab;

  /// Injectable for tests only — production passes nothing and each
  /// service resolves its own Firebase instances, exactly as before.
  /// The activity feed's independence from the two auxiliary streams is
  /// only testable if those streams can be made to fail on demand.
  final FriendService? friendService;
  final MessageService? messageService;
  final NotificationService? notificationService;

  /// Test-only, for the same reason as the services above: reading it
  /// from FirebaseAuth needs an initialised Firebase app.
  final String? currentUserId;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final FriendService _friendService =
      widget.friendService ?? FriendService();
  late final MessageService _messageService =
      widget.messageService ?? MessageService.live;
  late final NotificationService _notificationService =
      widget.notificationService ?? NotificationService();

  late final Stream<List<FriendRequest>> _friendRequestsStream;
  late final Stream<List<Conversation>> _conversationsStream;

  final Set<String> _processingRequestIds = <String>{};
  int _notificationsLimit = 50;

  String get _currentUserId =>
      widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '';

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
          otherEmail: '',
          otherPhotoUrl: conversation.photoUrlFor(otherUserId),
        ),
      ),
    );
  }

  Future<void> _openNotification(AppNotification notification) async {
    await NotificationRouter.route(
      type: notification.type,
      targetId: notification.targetId,
      actorId: notification.actorId,
      notificationId: notification.id,
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
    final colors = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: isError ? TextStyle(color: colors.onErrorContainer) : null,
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? colors.errorContainer : null,
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: palette.background,
      body: Container(
        key: const ValueKey('notifications-background'),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.85, -0.95),
            radius: 1.25,
            colors: [
              colors.primaryContainer.withValues(alpha: .68),
              palette.backgroundTop,
              palette.background,
            ],
            stops: [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
          child: ResponsiveContentFrame(
            width: ResponsiveContentWidth.list,
            alignment: ResponsiveContentAlignment.topLeft,
            child: Column(
              key: const ValueKey('notifications-content-frame'),
              children: [
                _buildHeader(),
                Expanded(child: _buildContent()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
      child: Row(
        children: [
          if (!widget.isRootTab) ...[
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Back',
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: palette.textPrimary,
                size: 21,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Friend requests, messages and activity',
                  style: TextStyle(
                    color: palette.textSecondary,
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
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
                // The ACTIVITY FEED is the canonical content of this
                // screen. Friend requests and unread conversations are
                // auxiliary sections rendered alongside it, and neither
                // may decide whether the feed appears.
                //
                // Both used to. `isLoading` waited on all three streams,
                // so one auxiliary stream stuck in `waiting` held the
                // whole screen on a spinner; and a single `hasError`
                // across all three replaced everything — including
                // already-loaded activity — with one error state. A
                // Chats-side permission error blanked the bell inbox.
                final feedLoading =
                    notificationSnapshot.connectionState ==
                        ConnectionState.waiting &&
                    !notificationSnapshot.hasData;

                if (feedLoading) {
                  return Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: colors.primary,
                    ),
                  );
                }

                // Only a failure of the feed itself is fatal to the
                // screen, and only when it left nothing to show.
                if (notificationSnapshot.hasError &&
                    !notificationSnapshot.hasData) {
                  final denied = notificationSnapshot.error
                      .toString()
                      .toLowerCase()
                      .contains('permission');
                  return _EmptyState(
                    icon: denied
                        ? Icons.lock_outline_rounded
                        : Icons.error_outline_rounded,
                    title: 'Could not load your activity',
                    subtitle: denied
                        ? 'This account is not allowed to read its activity '
                              'feed. Sign out and back in to refresh it.'
                        : 'Check your connection and try again.',
                    onRetry: () => setState(() {}),
                  );
                }

                // An auxiliary stream that failed contributes nothing and
                // says so in its own section, rather than taking the
                // screen down with it.
                final requests = friendSnapshot.hasError
                    ? const <FriendRequest>[]
                    : friendSnapshot.data ?? const <FriendRequest>[];
                final conversations = conversationSnapshot.hasError
                    ? const <Conversation>[]
                    : conversationSnapshot.data ?? const <Conversation>[];
                final auxiliaryFailed =
                    friendSnapshot.hasError || conversationSnapshot.hasError;
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
                    notifications.isEmpty &&
                    !auxiliaryFailed) {
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
                    if (auxiliaryFailed) ...[
                      const _DegradedNotice(),
                      const SizedBox(height: 12),
                    ],
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
                              sum + conversation.unreadCountFor(_currentUserId),
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
                      _ActivityHeader(
                        count: unreadNotificationCount,
                        onMarkAllRead: unreadNotificationCount > 0
                            ? _markAllNotificationsRead
                            : null,
                      ),
                      const SizedBox(height: 10),
                      for (final entry in groupedNotifications.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              color: palette.textSecondary,
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
                            onPressed: () =>
                                setState(() => _notificationsLimit += 50),
                            child: Text(
                              'Load more',
                              style: TextStyle(
                                color: palette.textSecondary,
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            count > 99 ? '99+' : '$count',
            style: TextStyle(
              color: colors.onPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader({required this.count, required this.onMarkAllRead});

  final int count;
  final VoidCallback? onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledBodySize = MediaQuery.textScalerOf(context).scale(14);
        final shouldStack = constraints.maxWidth < 360 && scaledBodySize >= 21;
        final markAllButton = onMarkAllRead == null
            ? null
            : TextButton(
                key: const ValueKey('notifications-mark-all-read'),
                onPressed: onMarkAllRead,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Text(
                  'Mark all read',
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );

        if (shouldStack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(title: 'Activity', count: count),
              ?markAllButton,
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: _SectionHeader(title: 'Activity', count: count),
            ),
            ?markAllButton,
          ],
        );
      },
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final name = request.senderName.trim().isNotEmpty
        ? request.senderName.trim()
        : 'YO Voice user';

    final identity = Row(
      children: [
        _Avatar(name: name, photoUrl: request.senderPhotoUrl ?? ''),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  UserIdentityBadges(uid: request.senderId),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Sent you a friend request',
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
    final controls = isProcessing
        ? SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: colors.primary,
                ),
              ),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Decline',
                onPressed: onDecline,
                icon: Icon(Icons.close_rounded, color: colors.error),
              ),
              IconButton(
                tooltip: 'Accept',
                onPressed: onAccept,
                icon: Icon(
                  Icons.check_rounded,
                  color: _notificationSuccess(context),
                ),
              ),
            ],
          );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useStacked =
              MediaQuery.textScalerOf(context).scale(14) >= 21 &&
              constraints.maxWidth < 500;
          if (useStacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identity,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: controls),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 8),
              controls,
            ],
          );
        },
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final otherUserId = conversation.otherUserId(currentUserId);
    final name = conversation.displayNameFor(otherUserId);
    final unreadCount = conversation.unreadCountFor(currentUserId);
    final preview = conversation.lastMessage.trim().isEmpty
        ? 'New message'
        : conversation.lastMessage.trim();

    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border),
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
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.fade,
                      style: TextStyle(
                        color: palette.textSecondary,
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
                decoration: BoxDecoration(
                  color: colors.error,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: TextStyle(
                    color: colors.onError,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: palette.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

enum _NotificationMenuAction { delete }

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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final scaledBodySize = MediaQuery.textScalerOf(context).scale(14);
    final usesLargeText = scaledBodySize >= 21;

    final avatar = Stack(
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
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _icons[notification.type] ?? Icons.notifications_rounded,
              color: colors.primary,
              size: 13,
            ),
          ),
        ),
      ],
    );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              key: ValueKey('notification-state-${notification.id}'),
              container: true,
              label: notification.isRead
                  ? 'Read notification. ${notification.title}'
                  : 'Unread notification. ${notification.title}',
              child: ExcludeSemantics(
                child: Text(
                  notification.title,
                  key: ValueKey('notification-title-${notification.id}'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ),
            if (notification.actorId.isNotEmpty)
              UserIdentityBadges(uid: notification.actorId),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _relativeTime(notification.createdAt),
          style: TextStyle(color: palette.textSecondary, fontSize: 11.5),
        ),
      ],
    );
    final unreadIndicator = notification.isRead
        ? const SizedBox.shrink()
        : ExcludeSemantics(
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
            ),
          );
    final actions = PopupMenuButton<_NotificationMenuAction>(
      key: ValueKey('notification-actions-${notification.id}'),
      tooltip: 'Notification actions',
      icon: Icon(Icons.more_vert_rounded, color: palette.textSecondary),
      onSelected: (action) {
        if (action == _NotificationMenuAction.delete) onDismissed();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _NotificationMenuAction.delete,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: colors.error),
              const SizedBox(width: 10),
              const Expanded(child: Text('Delete notification')),
            ],
          ),
        ),
      ],
    );

    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: 'Delete notification'): onDismissed,
      },
      child: Dismissible(
        key: ValueKey(notification.id),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onDismissed(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: colors.errorContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(
            Icons.delete_outline_rounded,
            color: colors.onErrorContainer,
          ),
        ),
        child: Material(
          color: palette.surface,
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
                      ? palette.border
                      : colors.primary.withValues(alpha: 0.55),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final shouldStack =
                      usesLargeText && constraints.maxWidth < 600;
                  if (shouldStack) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            avatar,
                            const Spacer(),
                            unreadIndicator,
                            const SizedBox(width: 4),
                            actions,
                          ],
                        ),
                        const SizedBox(height: 12),
                        copy,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      avatar,
                      const SizedBox(width: 12),
                      Expanded(child: copy),
                      const SizedBox(width: 4),
                      unreadIndicator,
                      actions,
                    ],
                  );
                },
              ),
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
    final colors = Theme.of(context).colorScheme;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return Container(
      width: 50,
      height: 50,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [colors.primary, colors.secondary]),
      ),
      child: ClipOval(
        child: Container(
          color: colors.primary,
          child: photoUrl.trim().isNotEmpty
              ? Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _AvatarInitial(
                    initial: initial,
                    foreground: colors.onPrimary,
                  ),
                )
              : _AvatarInitial(initial: initial, foreground: colors.onPrimary),
        ),
      ),
    );
  }
}

class _AvatarInitial extends StatelessWidget {
  const _AvatarInitial({required this.initial, required this.foreground});

  final String initial;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          color: foreground,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Shown when an AUXILIARY section could not load. The activity feed
/// itself is fine and stays on screen — this says which part is missing
/// rather than pretending the page is complete.
class _DegradedNotice extends StatelessWidget {
  const _DegradedNotice();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      key: const ValueKey('notifications-degraded-notice'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: palette.warningSurface,
        border: Border.all(
          color: Color.alphaBlend(
            palette.warningForeground.withValues(alpha: .38),
            palette.border,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 16,
            color: palette.warningForeground,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Friend requests and unread messages could not be loaded. '
              'Your activity below is up to date.',
              style: TextStyle(
                color: palette.warningForeground,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Present only on the feed's own error state, so a failure the user
  /// can do something about is retryable instead of terminal.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
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
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, color: colors.onPrimaryContainer, size: 35),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              TextButton(
                onPressed: onRetry,
                child: Text(
                  'Try again',
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
