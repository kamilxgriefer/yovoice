import 'dart:async';

// Narrowed on purpose: the unrestricted export carries `count`/`sum`
// aggregate helpers that collide with this file's own callback parameters.
import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/badges/yo_metric_pill.dart';
import 'package:yovoice/shared/widgets/branding/yo_logo.dart';
import 'package:flutter/semantics.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_icons.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/presentation/screens/add_friend_screen.dart';
import 'package:yovoice/features/friends/presentation/widgets/friend_request_decision.dart';
import 'package:yovoice/features/home/presentation/first_steps_copy.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/pages/data/services/pages_availability.dart';
import 'package:yovoice/features/pages/presentation/page_navigation.dart';
import 'package:yovoice/features/pages/presentation/page_notice_copy.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/notification_router.dart';
import 'package:yovoice/features/notifications/presentation/widgets/yo_top_notification_host.dart';
import 'package:yovoice/shared/widgets/layout/home_section_header.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    this.isRootTab = false,
    this.friendService,
    this.messageService,
    this.notificationService,
    this.currentUserId,
    this.firestore,
    this.auth,
    this.acknowledgeOnVisible = true,
    this.openNotification,
    this.pagesEnabled,
    this.onFindPages,
    this.onAddFriends,
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

  /// Test-only as well, and for the same reason. The profile preview opened
  /// from a friend-request row resolves a real Firestore/Auth pair in
  /// production; a widget test has neither, so it injects its fakes here
  /// rather than the sheet reaching for the singletons.
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;

  /// Keeps the bell honest: visiting Activity acknowledges its unread rows and
  /// dismisses any foreground notification already covering that destination.
  /// Tests that intentionally inspect unread styling can disable the lifecycle
  /// side effect while still exercising the production widgets.
  final bool acknowledgeOnVisible;

  /// Test-only, like the services above: what a tap on a row's body does.
  /// Production passes nothing and routes through [NotificationRouter],
  /// which needs an initialised Firebase app a widget test does not have.
  final Future<void> Function(AppNotification notification)? openNotification;

  /// The empty screen's one action (firstSteps A). While Treści exists for
  /// the account it is "Znajdź strony do obserwowania" and opens Find Pages
  /// through the shell; otherwise it is "Dodaj znajomych" and opens the Add
  /// friend screen, so the screen is never a dead end. Test seams, as above:
  /// production passes nothing and uses [PagesAvailability.instance], the
  /// shell's [PagesShellBridge.findHost] and a pushed [AddFriendScreen].
  final ValueListenable<bool>? pagesEnabled;
  final Future<void> Function(BuildContext context)? onFindPages;
  final VoidCallback? onAddFriends;

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

  /// senderId → the decision in flight (true = Accept, false = Decline).
  /// One entry drives both the Friend requests card and the activity row for
  /// the same person, so neither can start a second call.
  final Map<String, bool> _processingRequests = <String, bool>{};

  /// What an Accept / Decline on this screen resolved to, by senderId,
  /// together with the `createdAt` of the request that was answered. The
  /// server removes the request and its activity row in one transaction, but
  /// the two streams do not update in the same frame; this keeps the row
  /// honest ("You and Ada are now friends") instead of flashing a stale
  /// state in between. A newer request from the same person (a different
  /// `createdAt`) is a new decision and shows the buttons again.
  final Map<
    String,
    ({FriendRequestResponseOutcome outcome, DateTime? requestCreatedAt})
  >
  _resolvedRequests =
      <
        String,
        ({FriendRequestResponseOutcome outcome, DateTime? requestCreatedAt})
      >{};
  int _notificationsLimit = 50;
  StreamSubscription<int>? _unreadCountSubscription;
  bool _isVisible = false;
  bool _acknowledgingVisibleNotifications = false;
  bool _visibleAcknowledgementRequested = false;

  String get _currentUserId =>
      widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _friendRequestsStream = _friendService.watchFriendRequests();
    _conversationsStream = _messageService.watchConversations();
    if (widget.acknowledgeOnVisible) {
      _unreadCountSubscription = _notificationService.watchUnreadCount().listen(
        (count) {
          if (_isVisible && count > 0) {
            _visibleAcknowledgementRequested = true;
            unawaited(_acknowledgeVisibleNotifications());
          }
        },
        onError: (_) {
          // The feed owns its visible error state. A badge acknowledgement
          // failure must never take the whole Activity screen down.
        },
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    final becameVisible = visible && !_isVisible;
    _isVisible = visible;
    if (!widget.acknowledgeOnVisible || !becameVisible) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isVisible) return;
      YoTopNotificationHost.maybeOf(context)?.clear();
      unawaited(_acknowledgeVisibleNotifications());
    });
  }

  @override
  void dispose() {
    unawaited(_unreadCountSubscription?.cancel());
    super.dispose();
  }

  Future<void> _acknowledgeVisibleNotifications() async {
    if (!_isVisible) return;
    _visibleAcknowledgementRequested = true;
    if (_acknowledgingVisibleNotifications) return;
    _acknowledgingVisibleNotifications = true;
    try {
      do {
        _visibleAcknowledgementRequested = false;
        await _notificationService.markAllAsRead();
      } while (mounted && _isVisible && _visibleAcknowledgementRequested);
    } catch (error) {
      debugPrint(
        'NotificationsScreen: automatic inbox acknowledgement failed '
        '(${error.runtimeType}).',
      );
    } finally {
      _acknowledgingVisibleNotifications = false;
    }
  }

  Future<void> _acceptRequest(FriendRequest request) => _respondToRequest(
    request.senderId,
    request.senderName,
    accept: true,
    requestCreatedAt: request.createdAt,
  );

  Future<void> _declineRequest(FriendRequest request) => _respondToRequest(
    request.senderId,
    request.senderName,
    accept: false,
    requestCreatedAt: request.createdAt,
  );

  /// The inbox answers "who is this?" the same way every other surface
  /// does. Injected services are forwarded when a test supplied them;
  /// production passes nothing and the preview resolves its own Firebase.
  Future<void> _previewRequester(FriendRequest request) {
    final name = request.senderName.trim();
    return showProfilePreview(
      context,
      userId: request.senderId,
      displayName: name.isEmpty ? null : name,
      firestore: widget.firestore,
      auth: widget.auth,
      friendService: widget.friendService,
      // showProfilePreview refuses a MessageService without the matching
      // Auth, so the pair travels together or not at all.
      messageService: widget.auth == null ? null : widget.messageService,
    );
  }

  /// The one Accept / Decline path for this screen, from the Friend
  /// requests card and from a friend-request activity row alike. The answer
  /// shown is the server's: a request that was cancelled, answered on
  /// another device or cut off by a block says so instead of failing.
  Future<void> _respondToRequest(
    String senderId,
    String senderName, {
    required bool accept,
    required DateTime? requestCreatedAt,
  }) async {
    if (_processingRequests.containsKey(senderId)) return;
    setState(() => _processingRequests[senderId] = accept);

    try {
      final outcome = await _friendService.respondToFriendRequest(
        senderId,
        accept: accept,
      );
      if (!mounted) return;
      setState(
        () => _resolvedRequests[senderId] = (
          outcome: outcome,
          requestCreatedAt: requestCreatedAt,
        ),
      );
      _showMessage(
        friendRequestResponseMessage(
          AppLocalizations.of(context),
          outcome,
          name: senderName,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(_readableError(error), isError: true);
    } finally {
      if (mounted) {
        setState(() => _processingRequests.remove(senderId));
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
    final injected = widget.openNotification;
    if (injected != null) return injected(notification);
    await NotificationRouter.route(
      type: notification.type,
      targetId: notification.targetId,
      actorId: notification.actorId,
      notificationId: notification.id,
      targetSubId: notification.targetSubId,
      sourcePath: notification.sourcePath,
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

  /// The empty feed's one action (firstSteps A). While Treści exists for the
  /// account and the shell can host Find Pages, it is "Znajdź strony do
  /// obserwowania"; otherwise it is "Dodaj znajomych" — both lead to a real
  /// place, and the label follows the Pages kill switch live.
  Widget _buildEmptyAction() {
    return ValueListenableBuilder<bool>(
      valueListenable:
          widget.pagesEnabled ?? PagesAvailability.instance.enabled,
      builder: (context, pagesEnabled, _) {
        final copy = FirstStepsCopy(AppLocalizations.of(context));
        final findPages = widget.onFindPages ?? PagesShellBridge.findHost;
        final toPages = pagesEnabled && findPages != null;
        return FilledButton.icon(
          key: ValueKey(
            toPages
                ? 'notifications-empty-find-pages'
                : 'notifications-empty-add-friends',
          ),
          onPressed: toPages
              ? () => unawaited(findPages(context))
              : _openAddFriends,
          style:
              AppFinish.tonalAccent(
                context.appPalette,
                highContrast: MediaQuery.highContrastOf(context),
              ).copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(64, 44)),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                ),
              ),
          icon: Icon(
            toPages ? Icons.search_rounded : AppIcons.addFriend,
            size: 20,
          ),
          label: Text(
            toPages ? copy.findPagesToFollow : copy.addFriends,
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }

  void _openAddFriends() {
    final override = widget.onAddFriends;
    if (override != null) {
      override();
      return;
    }
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AddFriendScreen(friendService: _friendService),
        ),
      ),
    );
  }

  String _readableError(Object error) {
    final copy = AppLocalizations.of(context);
    final message = error.toString();

    if (message.contains('permission-denied')) {
      return copy.text(
        "You don't have permission to do that.",
        'Brak uprawnień do wykonania tej operacji.',
      );
    }

    if (message.contains('unavailable')) {
      return copy.text(
        'Service is temporarily unavailable.',
        'Usługa jest chwilowo niedostępna.',
      );
    }

    return copy.text(
      'Something went wrong. Please try again.',
      'Coś poszło nie tak. Spróbuj ponownie.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: palette.background,
      body: YoPageBackground(
        key: const ValueKey('notifications-background'),
        // Refine-look R1: the one shared canvas radial (Chats / Friends /
        // Settings), replacing this screen's own primaryContainer @ .68
        // bloom, which read about twice as strong as its siblings and broke
        // the light budget (Notifications emits no light). Omitted under
        // high contrast.
        decoration: MediaQuery.highContrastOf(context)
            ? null
            : BoxDecoration(gradient: palette.canvasGlow(colors.primary)),
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
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    return Padding(
      // Without a Back button the title starts on the list's 18 px gutter.
      padding: EdgeInsets.fromLTRB(widget.isRootTab ? 18 : 10, 10, 18, 10),
      child: Row(
        children: [
          if (!widget.isRootTab) ...[
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: copy.text('Back', 'Wróć'),
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
                // The screen's one headline: `screenTitle` (22 w700 -0.5).
                // "Powiadomienia" is one long word: at 200 % text it is
                // wider than a phone row and used to break mid-word, so the
                // single line scales down only as far as it must to fit.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    copy.notifications,
                    maxLines: 1,
                    style: AppTypography.screenTitle.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  copy.text(
                    'Friend requests, messages and activity',
                    'Zaproszenia, wiadomości i aktywność',
                  ),
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
    final copy = AppLocalizations.of(context);
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
                    title: copy.text(
                      'Could not load your activity',
                      'Nie udało się wczytać aktywności',
                    ),
                    subtitle: denied
                        ? copy.text(
                            'This account is not allowed to read its activity '
                                'feed. Sign out and back in to refresh it.',
                            'To konto nie może odczytać swojej aktywności. '
                                'Wyloguj się i zaloguj ponownie.',
                          )
                        : copy.text(
                            'Check your connection and try again.',
                            'Sprawdź połączenie i spróbuj ponownie.',
                          ),
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
                  return _EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: copy.text(
                      'You are all caught up',
                      'Wszystko jest już sprawdzone',
                    ),
                    subtitle: copy.text(
                      'New friend requests, messages and activity will '
                          'appear here.',
                      'Nowe zaproszenia, wiadomości i aktywność pojawią się tutaj.',
                    ),
                    action: _buildEmptyAction(),
                  );
                }

                return ListView(
                  // The section headings own the vertical rhythm
                  // (AppRhythm.section above their ink, AppRhythm.title
                  // below), so the list adds no air of its own above the
                  // first heading, after a heading, or between sections;
                  // card gaps sit only BETWEEN cards.
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
                  children: [
                    if (auxiliaryFailed) ...[
                      const SizedBox(height: 10),
                      const _DegradedNotice(),
                    ],
                    if (requests.isNotEmpty) ...[
                      HomeSectionHeader(
                        title: copy.text(
                          'Friend requests',
                          'Zaproszenia do znajomych',
                        ),
                        trailing: _countPill(requests.length),
                      ),
                      for (final (index, request) in requests.indexed) ...[
                        if (index > 0) const SizedBox(height: 10),
                        _FriendRequestCard(
                          request: request,
                          pendingDecision:
                              _processingRequests[request.senderId],
                          onAccept: () => _acceptRequest(request),
                          onDecline: () => _declineRequest(request),
                          onOpenProfile: () =>
                              unawaited(_previewRequester(request)),
                        ),
                      ],
                    ],
                    if (unreadConversations.isNotEmpty) ...[
                      HomeSectionHeader(
                        title: copy.text(
                          'Unread messages',
                          'Nieprzeczytane wiadomości',
                        ),
                        trailing: _countPill(
                          unreadConversations.fold<int>(
                            0,
                            (sum, conversation) =>
                                sum +
                                conversation.unreadCountFor(_currentUserId),
                          ),
                        ),
                      ),
                      for (final (index, conversation)
                          in unreadConversations.indexed) ...[
                        if (index > 0) const SizedBox(height: 10),
                        _UnreadMessageCard(
                          conversation: conversation,
                          currentUserId: _currentUserId,
                          onTap: () => _openConversation(conversation),
                        ),
                      ],
                    ],
                    if (notifications.isNotEmpty) ...[
                      _ActivityHeader(
                        count: unreadNotificationCount,
                        onMarkAllRead: unreadNotificationCount > 0
                            ? _markAllNotificationsRead
                            : null,
                      ),
                      for (final entry in groupedNotifications.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
                          child: Text(
                            entry.key,
                            // Group label (Slim): 11 px w700 with tracking.
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 11 * .08,
                            ),
                          ),
                        ),
                        for (final notification in entry.value) ...[
                          _NotificationCard(
                            notification: notification,
                            onTap: () => _openNotification(notification),
                            onDismissed: () =>
                                _deleteNotification(notification),
                            requestDecision: _requestDecisionFor(
                              notification,
                              requests: requests,
                              requestsKnown:
                                  friendSnapshot.hasData &&
                                  !friendSnapshot.hasError,
                            ),
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
                              copy.text('Load more', 'Wczytaj więcej'),
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

  /// The inline Accept / Decline state for a friend-request activity row,
  /// or null for every other type. While the request list is still loading
  /// (or failed) nothing is claimed either way.
  _RequestDecision? _requestDecisionFor(
    AppNotification notification, {
    required List<FriendRequest> requests,
    required bool requestsKnown,
  }) {
    if (notification.type != NotificationType.friendRequest) return null;
    final senderId = notification.actorId;
    if (senderId.isEmpty) return null;
    FriendRequest? pending;
    for (final request in requests) {
      if (request.senderId == senderId) {
        pending = request;
        break;
      }
    }
    final answered = _resolvedRequests[senderId];
    // The answer only covers the request it was given to. A pending request
    // with a different createdAt was sent after it (say, after a Decline),
    // so it gets its own Accept / Decline again.
    final resolved =
        answered != null &&
            (pending == null || pending.createdAt == answered.requestCreatedAt)
        ? answered.outcome
        : null;
    if (pending == null && resolved == null && !requestsKnown) return null;
    final name = notification.actorName;
    return _RequestDecision(
      senderId: senderId,
      pending: pending != null && resolved == null,
      resolved:
          resolved ??
          (pending == null
              ? FriendRequestResponseOutcome.noLongerAvailable
              : null),
      pendingDecision: _processingRequests[senderId],
      onAccept: () => unawaited(
        _respondToRequest(
          senderId,
          name,
          accept: true,
          requestCreatedAt: pending?.createdAt,
        ),
      ),
      onDecline: () => unawaited(
        _respondToRequest(
          senderId,
          name,
          accept: false,
          requestCreatedAt: pending?.createdAt,
        ),
      ),
    );
  }

  Map<String, List<AppNotification>> _groupByDay(
    List<AppNotification> notifications,
  ) {
    final copy = AppLocalizations.of(context);
    final grouped = <String, List<AppNotification>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final notification in notifications) {
      final createdAt = notification.createdAt;
      final String label;
      if (createdAt == null) {
        label = copy.earlier;
      } else {
        final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
        if (day == today) {
          label = copy.today;
        } else if (day == yesterday) {
          label = copy.yesterday;
        } else {
          label = copy.calendarDate(day);
        }
      }
      grouped.putIfAbsent(label, () => []).add(notification);
    }
    return grouped;
  }
}

/// The inbox's count, mounted as a section heading's trailer: the accent
/// [YoMetricPill] (filled primary, `onPrimary` copy) clamped at "99+" — the
/// badge this screen has always drawn.
YoMetricPill _countPill(int count) => YoMetricPill(
  value: count > 99 ? '99+' : '$count',
  tone: YoMetricPillTone.accent,
);

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader({required this.count, required this.onMarkAllRead});

  final int count;
  final VoidCallback? onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
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
                  copy.text(
                    'Mark all read',
                    'Oznacz wszystkie jako przeczytane',
                  ),
                  // Beside the heading the action may take two lines, so a
                  // long locale wraps the ACTION instead of breaking the
                  // heading mid-word ("Aktywn / ość" on a 390 px phone).
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  // `interactiveForeground`, not `colors.primary`: 12 px
                  // #7B2FF7 on the Dark canvas was 3.35:1, under AA for
                  // text; this is 7.37:1 Dark / 6.27:1 Pearl.
                  style: TextStyle(
                    color: palette.interactiveForeground,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
        final title = copy.text('Activity', 'Aktywność');
        final pill = _countPill(count);

        // A narrow phone at large text puts the action under the heading,
        // as it always has; the heading's own 16 px bottom step is the gap.
        if (shouldStack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HomeSectionHeader(title: title, trailing: pill),
              ?markAllButton,
            ],
          );
        }

        // Otherwise pill and button ride the heading's trailer slot, which
        // centres them on the title's ink and keeps the box at
        // section + ink + title whatever the button's 48 px target adds.
        // The trailer is capped at half the row so the title always keeps
        // the other half; the button's label wraps inside its share.
        return HomeSectionHeader(
          title: title,
          trailing: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                pill,
                if (markAllButton != null) ...[
                  const SizedBox(width: 8),
                  Flexible(child: markAllButton),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FriendRequestCard extends StatelessWidget {
  const _FriendRequestCard({
    required this.request,
    required this.pendingDecision,
    required this.onAccept,
    required this.onDecline,
    required this.onOpenProfile,
  });

  final FriendRequest request;

  /// The decision in flight for this sender, or null when idle.
  final bool? pendingDecision;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final name = request.senderName.trim().isNotEmpty
        ? request.senderName.trim()
        : copy.text('YO Voice user', 'Użytkownik YO Voice');

    final openLabel = copy.template(
      'Open profile of {name}',
      'Otwórz profil: {name}',
      values: <String, Object>{'name': name},
    );
    final identity = Row(
      children: [
        // The avatar alone, not the row: the name shares its column with
        // the request line, and the trailing Accept/Decline pair must keep
        // every pixel of its own targets. The disc is 44 px inside a 48 px
        // target, so nothing about this card reflows.
        AccessibleTapRegion(
          key: ValueKey('notification-request-profile-${request.senderId}'),
          onTap: onOpenProfile,
          semanticLabel: openLabel,
          tooltip: openLabel,
          circular: true,
          minimumSize: const Size(_Avatar.diameter + 4, _Avatar.diameter + 4),
          child: ExcludeSemantics(
            child: _Avatar(
              userId: request.senderId,
              name: name,
              photoUrl: request.senderPhotoUrl ?? '',
            ),
          ),
        ),
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
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  UserIdentityBadges(uid: request.senderId),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                copy.text(
                  'Sent you a friend request',
                  'Wysyła Ci zaproszenie do znajomych',
                ),
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
    // Two labelled buttons, never an icon-only check and X: accepting is a
    // consent decision, and the pair must read as one (ADR on explicit
    // friend-request consent). They sit under the identity at every width,
    // so both labels always fit and neither hides at the card's edge.
    final controls = FriendRequestDecisionButtons(
      acceptKey: ValueKey('notification-request-accept-${request.senderId}'),
      declineKey: ValueKey('notification-request-decline-${request.senderId}'),
      name: name,
      busyAccept: pendingDecision == true,
      busyDecline: pendingDecision == false,
      onAccept: onAccept,
      onDecline: onDecline,
    );

    // A card because it groups its own actions; Slim flattens it to one
    // layer (1 px border, radius 12) with the 56–68 px row padding.
    return Container(
      key: ValueKey('notification-request-card-${request.senderId}'),
      padding: _notificationCardPadding,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(_notificationCardRadius),
        border: Border.all(color: _cardEdge(context)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Wide rows keep the pair beside the identity, capped so it never
          // stretches into a desktop-wide bar; narrow rows put it below.
          final besideIdentity =
              constraints.maxWidth >= 620 &&
              MediaQuery.textScalerOf(context).scale(14) < 21;
          if (besideIdentity) {
            return Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: AppRhythm.item),
                SizedBox(width: 320, child: controls),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: AppRhythm.item),
              controls,
            ],
          );
        },
      ),
    );
  }
}

/// The inline response state of one friend-request activity row.
class _RequestDecision {
  const _RequestDecision({
    required this.senderId,
    required this.pending,
    required this.resolved,
    required this.pendingDecision,
    required this.onAccept,
    required this.onDecline,
  });

  final String senderId;

  /// The request still exists: offer Accept / Decline.
  final bool pending;

  /// What happened to it, when it no longer exists.
  final FriendRequestResponseOutcome? resolved;
  final bool? pendingDecision;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
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
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final otherUserId = conversation.otherUserId(currentUserId);
    final name = conversation.displayNameFor(otherUserId);
    final unreadCount = conversation.unreadCountFor(currentUserId);
    final preview = conversation.lastMessage.trim().isEmpty
        ? copy.text('New message', 'Nowa wiadomość')
        : localizedMessageTombstone(conversation.lastMessage.trim(), copy);

    const radius = BorderRadius.all(Radius.circular(_notificationCardRadius));
    return Material(
      color: palette.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: _notificationCardPadding,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: _cardEdge(context)),
          ),
          child: Row(
            children: [
              _Avatar(
                userId: otherUserId,
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
                        fontWeight: FontWeight.w700,
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
                    fontWeight: FontWeight.w700,
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
    this.requestDecision,
  });

  final AppNotification notification;

  /// Opens the destination (for a friend request: the request list). It
  /// never answers a request; only the labelled buttons below do.
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  /// Only for a friendRequest row whose state is known.
  final _RequestDecision? requestDecision;

  static const Map<NotificationType, IconData> _icons = {
    NotificationType.friendRequest: Icons.person_add_alt_1_rounded,
    NotificationType.friendAccepted: Icons.people_alt_rounded,
    NotificationType.follow: Icons.favorite_rounded,
    NotificationType.clubInvite: Icons.hub_rounded,
    NotificationType.clubInviteAccepted: Icons.hub_rounded,
    NotificationType.roomInvite: Icons.spatial_audio_off_rounded,
    NotificationType.broadcastInvite: Icons.campaign_rounded,
    NotificationType.liveStarted: Icons.sensors_rounded,
    NotificationType.directMessage: Icons.chat_bubble_rounded,
    NotificationType.directCall: Icons.call_rounded,
    NotificationType.missedCall: Icons.call_missed_rounded,
    NotificationType.mention: Icons.alternate_email_rounded,
    NotificationType.reply: Icons.reply_rounded,
    NotificationType.momentComment: Icons.mode_comment_rounded,
    NotificationType.reelComment: Icons.mode_comment_rounded,
    NotificationType.commentMention: Icons.alternate_email_rounded,
    NotificationType.serverEventReminder: Icons.event_available_rounded,
    NotificationType.serverRole: Icons.workspace_premium_rounded,
    NotificationType.pagePostComment: Icons.mode_comment_rounded,
    NotificationType.pageModeration: Icons.shield_rounded,
    NotificationType.pageLapse: Icons.article_rounded,
    NotificationType.achievementUnlocked: Icons.emoji_events_rounded,
    NotificationType.moderation: Icons.shield_rounded,
    NotificationType.system: Icons.info_rounded,
  };

  String _relativeTime(BuildContext context, DateTime? time) {
    if (time == null) return '';
    return AppLocalizations.of(context).relativeCompactTime(time);
  }

  String _localizedTitle(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final actor = notification.actorName.trim().isEmpty
        ? copy.text('YO Voice user', 'Użytkownik YO Voice')
        : notification.actorName.trim();
    final label = notification.targetLabel?.trim();
    final hasLabel = label != null && label.isNotEmpty;

    return switch (notification.type) {
      NotificationType.friendRequest => copy.template(
        '{actor} sent you a friend request',
        '{actor} wysyła Ci zaproszenie do znajomych',
        values: {'actor': actor},
      ),
      NotificationType.friendAccepted => copy.template(
        '{actor} accepted your friend request',
        '{actor} przyjmuje Twoje zaproszenie do znajomych',
        values: {'actor': actor},
      ),
      NotificationType.follow => copy.template(
        '{actor} started following you',
        '{actor} zaczyna Cię obserwować',
        values: {'actor': actor},
      ),
      NotificationType.clubInvite =>
        hasLabel
            ? copy.template(
                '{actor} invited you to {label}',
                '{actor} zaprasza Cię do serwera {label}',
                values: {'actor': actor, 'label': label},
              )
            : copy.template(
                '{actor} invited you to a server',
                '{actor} zaprasza Cię do serwera',
                values: {'actor': actor},
              ),
      NotificationType.clubInviteAccepted =>
        hasLabel
            ? copy.template(
                '{actor} joined {label}',
                '{actor} dołącza do serwera {label}',
                values: {'actor': actor, 'label': label},
              )
            : copy.template(
                '{actor} accepted your server invitation',
                '{actor} przyjmuje Twoje zaproszenie do serwera',
                values: {'actor': actor},
              ),
      NotificationType.roomInvite =>
        hasLabel
            ? copy.template(
                '{actor} invited you to {label}',
                '{actor} zaprasza Cię do kanału głosowego {label}',
                values: {'actor': actor, 'label': label},
              )
            : copy.template(
                '{actor} invited you to a voice channel',
                '{actor} zaprasza Cię do kanału głosowego',
                values: {'actor': actor},
              ),
      NotificationType.broadcastInvite =>
        hasLabel
            ? copy.template(
                '{actor} invited you to {label}',
                '{actor} zaprasza Cię do transmisji {label}',
                values: {'actor': actor, 'label': label},
              )
            : copy.template(
                '{actor} invited you to a broadcast',
                '{actor} zaprasza Cię do transmisji',
                values: {'actor': actor},
              ),
      NotificationType.liveStarted =>
        hasLabel
            ? copy.template(
                '{actor} is live: {label}',
                '{actor} prowadzi teraz: {label}',
                values: {'actor': actor, 'label': label},
              )
            : copy.template(
                '{actor} is live now',
                '{actor} jest teraz na żywo',
                values: {'actor': actor},
              ),
      NotificationType.directMessage => copy.template(
        '{actor} sent you a message request',
        '{actor} wysyła Ci prośbę o wiadomość',
        values: {'actor': actor},
      ),
      NotificationType.directCall => copy.template(
        '{actor} is calling you',
        '{actor} dzwoni do Ciebie',
        values: {'actor': actor},
      ),
      NotificationType.missedCall => copy.template(
        'Missed call from {actor}',
        'Nieodebrane połączenie od {actor}',
        values: {'actor': actor},
      ),
      NotificationType.mention =>
        hasLabel
            ? copy.template(
                '{actor} mentioned you in {label}',
                '{actor} wspomina o Tobie w {label}',
                values: {'actor': actor, 'label': label},
              )
            : copy.template(
                '{actor} mentioned you',
                '{actor} wspomina o Tobie',
                values: {'actor': actor},
              ),
      NotificationType.reply =>
        hasLabel
            ? copy.template(
                '{actor} replied to you in {label}',
                '{actor} odpowiada Ci w {label}',
                values: {'actor': actor, 'label': label},
              )
            : copy.template(
                '{actor} replied to you',
                '{actor} odpowiada Ci',
                values: {'actor': actor},
              ),
      NotificationType.momentComment => copy.template(
        '{actor} commented on your Moment',
        '{actor} komentuje Twój Moment',
        values: {'actor': actor},
      ),
      NotificationType.reelComment => copy.template(
        '{actor} commented on your Yeel',
        '{actor} komentuje Twojego Yeela',
        values: {'actor': actor},
      ),
      NotificationType.commentMention => copy.template(
        '{actor} mentioned you in a comment',
        '{actor} oznacza Cię w komentarzu',
        values: {'actor': actor},
      ),
      NotificationType.serverEventReminder =>
        hasLabel
            ? copy.template(
                'Starting soon: {label}',
                'Niedługo start: {label}',
                values: {'label': label},
              )
            : copy.text(
                'An event is starting soon',
                'Wydarzenie niedługo się zacznie',
              ),
      NotificationType.serverRole =>
        hasLabel
            ? copy.template(
                '{actor} promoted you in {label}',
                '{actor} awansuje Cię na serwerze {label}',
                values: {'actor': actor, 'label': label},
              )
            : copy.template(
                '{actor} promoted you in a server',
                '{actor} awansuje Cię na serwerze',
                values: {'actor': actor},
              ),
      NotificationType.pagePostComment => copy.template(
        '{actor} commented on your Page post',
        '{actor} komentuje Twój post na stronie',
        values: {'actor': actor},
      ),
      NotificationType.pageModeration => PageNoticeCopy(
        copy,
      ).moderation(notification),
      NotificationType.pageLapse => PageNoticeCopy(copy).lapse(notification),
      NotificationType.achievementUnlocked =>
        hasLabel
            ? copy.template(
                'Achievement unlocked: {label}',
                'Odblokowano osiągnięcie: {label}',
                values: {'label': label},
              )
            : copy.text('Achievement unlocked', 'Odblokowano osiągnięcie'),
      NotificationType.moderation =>
        hasLabel
            ? label
            : copy.text(
                'A moderator took action on your account',
                'Moderator wykonał działanie na Twoim koncie',
              ),
      NotificationType.system => hasLabel ? label : 'YO Voice',
    };
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final scaledBodySize = MediaQuery.textScalerOf(context).scale(14);
    final usesLargeText = scaledBodySize >= 21;
    final localizedTitle = _localizedTitle(context);

    // Only a notice with no actor is YO Voice itself; a system row that
    // names a person keeps that person's avatar.
    final systemSender =
        (notification.type == NotificationType.system &&
            notification.actorId.isEmpty) ||
        notification.type == NotificationType.pageModeration ||
        notification.type == NotificationType.pageLapse;
    // The system sender is the real logo, bare (refine-look §4): the type
    // badge would cut into the mark, and the logo already says who sent it.
    // The badge is decoration without semantics, so nothing is lost.
    final avatar = systemSender
        ? const _Avatar(
            userId: '',
            name: 'YO Voice',
            photoUrl: '',
            systemSender: true,
          )
        : Stack(
            children: [
              _Avatar(
                userId: notification.actorId,
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
    final notificationCopy = Column(
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
                  ? localizations.template(
                      'Read notification. {title}',
                      'Przeczytane powiadomienie. {title}',
                      values: {'title': localizedTitle},
                    )
                  : localizations.template(
                      'Unread notification. {title}',
                      'Nieprzeczytane powiadomienie. {title}',
                      values: {'title': localizedTitle},
                    ),
              child: ExcludeSemantics(
                child: Text(
                  localizedTitle,
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
          _relativeTime(context, notification.createdAt),
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
      tooltip: localizations.text(
        'Notification actions',
        'Działania powiadomienia',
      ),
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
              Expanded(
                child: Text(
                  localizations.text(
                    'Delete notification',
                    'Usuń powiadomienie',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final decision = requestDecision;
    final Widget? requestActions = decision == null
        ? null
        : Padding(
            key: ValueKey('notification-request-actions-${notification.id}'),
            padding: const EdgeInsets.only(top: AppRhythm.item),
            // Capped so a desktop-wide row keeps a button pair, not a bar.
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: decision.pending
                    ? FriendRequestDecisionButtons(
                        acceptKey: ValueKey(
                          'notification-row-accept-${notification.id}',
                        ),
                        declineKey: ValueKey(
                          'notification-row-decline-${notification.id}',
                        ),
                        name: notification.actorName,
                        busyAccept: decision.pendingDecision == true,
                        busyDecline: decision.pendingDecision == false,
                        onAccept: decision.onAccept,
                        onDecline: decision.onDecline,
                      )
                    : FriendRequestResolvedNotice(
                        outcome:
                            decision.resolved ??
                            FriendRequestResponseOutcome.noLongerAvailable,
                        name: notification.actorName,
                      ),
              ),
            ),
          );

    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(
          label: localizations.text(
            'Delete notification',
            'Usuń powiadomienie',
          ),
        ): onDismissed,
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
            borderRadius: BorderRadius.circular(_notificationCardRadius),
          ),
          child: Icon(
            Icons.delete_outline_rounded,
            color: colors.onErrorContainer,
          ),
        ),
        // One flat layer (radius 12, 1 px border). The unread border keeps
        // its tint: it carries the unread state together with the dot.
        child: Material(
          color: palette.surface,
          borderRadius: BorderRadius.circular(_notificationCardRadius),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(_notificationCardRadius),
            child: Container(
              padding: _notificationCardPadding,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_notificationCardRadius),
                border: Border.all(
                  color: _cardEdge(context, unread: !notification.isRead),
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
                        notificationCopy,
                        ?requestActions,
                      ],
                    );
                  }

                  final row = Row(
                    children: [
                      avatar,
                      const SizedBox(width: 12),
                      Expanded(child: notificationCopy),
                      const SizedBox(width: 4),
                      unreadIndicator,
                      actions,
                    ],
                  );
                  if (requestActions == null) return row;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [row, requestActions],
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
  const _Avatar({
    required this.userId,
    required this.name,
    required this.photoUrl,
    this.systemSender = false,
  });

  final String userId;
  final String name;
  final String photoUrl;

  /// A notice YO Voice itself sent: a `system` row with no actor. It shows
  /// the real logo, bare, instead of a letter disc (refine-look §4).
  final bool systemSender;

  /// Slim avatar: 44 px (40–48 band), no decorative gradient ring.
  static const double diameter = 44;

  /// The system sender's logo box inside the 44 px slot.
  static const double logoSize = 40;

  @override
  Widget build(BuildContext context) {
    if (systemSender) {
      return const SizedBox(
        width: diameter,
        height: diameter,
        child: Center(
          child: YoBrandMark(
            key: ValueKey('notification-system-sender-logo'),
            size: logoSize,
            light: YoBrandLight.none,
          ),
        ),
      );
    }
    return SizedBox(
      width: diameter,
      height: diameter,
      child: ClipOval(
        // R10 brand finish: the one letter gradient and a hairline ring.
        child: UserAvatar(
          radius: diameter / 2,
          userId: userId,
          photoUrl: photoUrl,
          displayName: name,
          finish: UserAvatarFinish.brand,
        ),
      ),
    );
  }
}

/// The 1 px edge of the inbox's cards. They stay one flat `surface` layer
/// in every mode; the edge is `border` (an unread activity row keeps its
/// primary @ .55 tint, which carries the unread state with the dot). High
/// contrast brings back `borderStrong`, and an unread row gets the full
/// `interactiveForeground` instead of a translucent tint.
Color _cardEdge(BuildContext context, {bool unread = false}) {
  final palette = context.appPalette;
  if (MediaQuery.highContrastOf(context)) {
    return unread ? palette.interactiveForeground : palette.borderStrong;
  }
  return unread
      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.55)
      : palette.border;
}

/// Slim card geometry shared by the inbox's three card kinds: radius 12 and
/// a 12 / 10 px inset, so a row with a 48 px action target lands at 68 px.
const double _notificationCardRadius = 12;
const EdgeInsets _notificationCardPadding = EdgeInsets.symmetric(
  horizontal: 12,
  vertical: 10,
);

/// Shown when an AUXILIARY section could not load. The activity feed
/// itself is fine and stays on screen — this says which part is missing
/// rather than pretending the page is complete.
class _DegradedNotice extends StatelessWidget {
  const _DegradedNotice();

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
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
              copy.text(
                'Friend requests and unread messages could not be loaded. '
                    'Your activity below is up to date.',
                'Nie udało się wczytać zaproszeń i nieprzeczytanych wiadomości. '
                    'Aktywność poniżej jest aktualna.',
              ),
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
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Present only on the feed's own error state, so a failure the user
  /// can do something about is retryable instead of terminal.
  final VoidCallback? onRetry;

  /// The one next step of the genuinely empty feed (firstSteps A), under the
  /// message. Never drawn beside [onRetry].
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
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
                fontWeight: FontWeight.w700,
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
            if (action != null && onRetry == null) ...[
              const SizedBox(height: 20),
              action!,
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              TextButton(
                onPressed: onRetry,
                child: Text(
                  copy.text('Try again', 'Spróbuj ponownie'),
                  // AA text contrast in Dark (primary was ≈ 3.4:1).
                  style: TextStyle(
                    color: palette.interactiveForeground,
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
