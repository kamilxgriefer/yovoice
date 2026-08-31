import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/audio/ui_sound.dart';
import 'package:yovoice/core/audio/ui_sound_service.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/auth/presentation/navigation/auth_epoch_route_resetter.dart';
import 'package:yovoice/features/auth/presentation/screens/auth_gate.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/calls/presentation/widgets/direct_call_coordinator.dart';
import 'package:yovoice/features/messages/data/services/active_conversation_registry.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/presentation/notification_router.dart';

double foregroundNotificationBottomClearance(TextScaler textScaler) {
  final textScale = textScaler.scale(1);
  return 104.0 + 72.0 * ((textScale - 1.0).clamp(0.0, 1.0));
}

@visibleForTesting
void clearSessionSnackBars(ScaffoldMessengerState messenger) {
  // clearSnackBars removes the queue but animates the current banner away.
  // removeCurrentSnackBar completes that removal in this same frame so copy
  // from account A can never paint over Login or account B.
  messenger.clearSnackBars();
  messenger.removeCurrentSnackBar();
}

SnackBar buildForegroundNotificationBanner({
  required String title,
  required String? body,
  required NotificationType type,
  required String? targetId,
  required String? actorId,
  String? notificationId,
  double bottomClearance = 104,
  AppPalette? palette,
}) {
  final semanticPalette = palette ?? AppPalette.dark;
  final isAchievement = type == NotificationType.achievementUnlocked;
  if (isAchievement) {
    return SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(12, 12, 12, bottomClearance),
      padding: EdgeInsets.zero,
      elevation: 0,
      duration: const Duration(seconds: 2),
      backgroundColor: Colors.transparent,
      content: Align(
        alignment: Alignment.bottomRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Material(
            key: const ValueKey('achievement-toast'),
            color: semanticPalette.surfaceRaised,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: semanticPalette.borderStrong),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => NotificationRouter.route(
                type: type,
                targetId: targetId,
                actorId: actorId,
                notificationId: notificationId,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.emoji_events_rounded,
                      size: 22,
                      color: semanticPalette.warningForeground,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: semanticPalette.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: semanticPalette.interactiveForeground,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  return SnackBar(
    behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.fromLTRB(16, 16, 16, bottomClearance),
    duration: const Duration(seconds: 5),
    backgroundColor: semanticPalette.surfaceRaised,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: semanticPalette.borderStrong),
    ),
    content: Row(
      children: [
        Icon(
          Icons.notifications_active_rounded,
          color: semanticPalette.interactiveForeground,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: semanticPalette.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (body?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 2),
                Text(
                  body!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: semanticPalette.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
    action: SnackBarAction(
      label: 'Open',
      textColor: semanticPalette.interactiveForeground,
      onPressed: () => NotificationRouter.route(
        type: type,
        targetId: targetId,
        actorId: actorId,
        notificationId: notificationId,
      ),
    ),
  );
}

/// Decides which Firestore-delivered notifications earn a foreground
/// banner, independently of FCM — push is frequently unavailable (web
/// builds without a VAPID key, denied permission, simulators), and the
/// in-app banner must not depend on it.
///
/// Rules, in order:
///  * nothing shows until the first snapshot after (re)sign-in has been
///    recorded as the baseline — only arrivals newer than app start /
///    sign-in banner, never the backlog;
///  * a document banners at most once per session, whichever path (this
///    stream or the FCM foreground hook) gets to it first;
///  * documents that are already read or `bellSuppressed` (push-only
///    carriers, e.g. friend-DM records) never banner.
class ForegroundNotificationStreamSource {
  ForegroundNotificationStreamSource({
    required this.authStates,
    required this.watchNotifications,
    required this.showBanner,
  });

  final Stream<User?> authStates;

  /// Called lazily on each sign-in, never before one — the feed query
  /// requires a signed-in user.
  final Stream<List<AppNotification>> Function() watchNotifications;

  /// Returns true only after the app-level messenger accepted the banner.
  /// False keeps the notification pending so a later frame/snapshot can retry.
  final bool Function(AppNotification notification) showBanner;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<List<AppNotification>>? _feedSubscription;
  bool _baselineRecorded = false;
  final Set<String> _knownIds = <String>{};
  final Set<String> _banneredIds = <String>{};
  final Map<String, int> _pushClaims = <String, int>{};
  final Set<String> _retryFromFirestoreIds = <String>{};
  final Map<String, AppNotification> _pendingNotifications =
      <String, AppNotification>{};
  final Map<String, AppNotification> _latestNotifications =
      <String, AppNotification>{};
  int _nextClaimGeneration = 0;

  void start() {
    _authSubscription ??= authStates.listen(_handleAuthState);
  }

  void _handleAuthState(User? user) {
    unawaited(_feedSubscription?.cancel());
    _feedSubscription = null;
    _baselineRecorded = false;
    _knownIds.clear();
    _banneredIds.clear();
    _pushClaims.clear();
    _retryFromFirestoreIds.clear();
    _pendingNotifications.clear();
    _latestNotifications.clear();
    if (user == null) return;
    _feedSubscription = watchNotifications().listen(
      _handleSnapshot,
      // The bell screen owns surfacing feed errors; the banner layer
      // just goes quiet rather than crashing the whole app shell.
      onError: (Object _) {},
    );
  }

  void _handleSnapshot(List<AppNotification> notifications) {
    final snapshotIds = notifications
        .map((notification) => notification.id)
        .toSet();
    _latestNotifications.removeWhere((id, _) => !snapshotIds.contains(id));
    for (final notification in notifications) {
      _latestNotifications[notification.id] = notification;
    }
    if (!_baselineRecorded) {
      _baselineRecorded = true;
      for (final notification in notifications) {
        _knownIds.add(notification.id);
        // A failed/unfinished FCM presentation proves this document is a live
        // foreground arrival rather than old backlog. Preserve the normal
        // baseline rule for every other document.
        if (_pushClaims.containsKey(notification.id) ||
            _retryFromFirestoreIds.contains(notification.id)) {
          _considerForBanner(notification);
        }
      }
      return;
    }
    for (final notification in notifications) {
      final isNew = _knownIds.add(notification.id);
      if (!isNew &&
          !_pendingNotifications.containsKey(notification.id) &&
          !_retryFromFirestoreIds.contains(notification.id)) {
        continue;
      }
      _considerForBanner(notification);
    }
  }

  void _considerForBanner(AppNotification notification) {
    final id = notification.id;
    if (notification.isRead || notification.bellSuppressed) {
      _pendingNotifications.remove(id);
      _retryFromFirestoreIds.remove(id);
      return;
    }
    if (_banneredIds.contains(id)) {
      _pendingNotifications.remove(id);
      _retryFromFirestoreIds.remove(id);
      return;
    }
    if (_pushClaims.containsKey(id)) {
      _pendingNotifications[id] = notification;
      return;
    }
    _tryShowBanner(notification);
  }

  void _tryShowBanner(AppNotification notification) {
    final id = notification.id;
    var presented = false;
    try {
      presented = showBanner(notification);
    } catch (error) {
      debugPrint(
        'ForegroundNotificationStreamSource: banner presentation failed '
        '(${error.runtimeType}).',
      );
    }
    if (presented) {
      _banneredIds.add(id);
      _pendingNotifications.remove(id);
      _retryFromFirestoreIds.remove(id);
      return;
    }
    _pendingNotifications[id] = notification;
    _retryFromFirestoreIds.add(id);
  }

  /// Reserves an id for FCM without marking it as shown. The returned token
  /// commits only after a native or in-app surface accepted the presentation;
  /// failure releases the reservation and immediately hands any deferred
  /// Firestore document back to the stream path.
  ForegroundNotificationClaimDecision claimPushBanner(String? notificationId) {
    if (notificationId == null || notificationId.isEmpty) {
      return const ForegroundNotificationClaimDecision.allowUntracked();
    }
    if (_banneredIds.contains(notificationId) ||
        _pushClaims.containsKey(notificationId)) {
      return const ForegroundNotificationClaimDecision.skip();
    }
    final generation = ++_nextClaimGeneration;
    _pushClaims[notificationId] = generation;
    return ForegroundNotificationClaimDecision.claimed(
      ForegroundNotificationClaim(
        (presented) => _completePushBanner(
          notificationId,
          generation: generation,
          presented: presented,
        ),
      ),
    );
  }

  void _completePushBanner(
    String notificationId, {
    required int generation,
    required bool presented,
  }) {
    // An old platform Future may finish after sign-out/sign-in or after a new
    // delivery claimed the same id. A generation token cannot settle that
    // newer account/delivery's reservation.
    if (_pushClaims[notificationId] != generation) return;
    _pushClaims.remove(notificationId);
    if (presented) {
      _banneredIds.add(notificationId);
      _pendingNotifications.remove(notificationId);
      _retryFromFirestoreIds.remove(notificationId);
      return;
    }
    _retryFromFirestoreIds.add(notificationId);
    final pending =
        _pendingNotifications[notificationId] ??
        _latestNotifications[notificationId];
    if (pending != null) _considerForBanner(pending);
  }

  /// Retries only notifications whose prior presentation returned false. The
  /// app calls this after the first frame when ScaffoldMessenger becomes ready.
  void retryPendingBanners() {
    final pending = _pendingNotifications.values.toList(growable: false);
    for (final notification in pending) {
      _considerForBanner(notification);
    }
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _feedSubscription?.cancel();
    _authSubscription = null;
    _feedSubscription = null;
  }
}

class YoVoiceApp extends StatefulWidget {
  const YoVoiceApp({this.preferencesController, super.key});

  final AppPreferencesController? preferencesController;

  @override
  State<YoVoiceApp> createState() => _YoVoiceAppState();
}

class _YoVoiceAppState extends State<YoVoiceApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  ForegroundNotificationStreamSource? _streamNotifications;
  late final AuthEpochRouteResetter _authRouteResetter;
  StreamSubscription<User?>? _authRouteSubscription;
  bool _foregroundRetryScheduled = false;

  @override
  void initState() {
    super.initState();
    _authRouteResetter = AuthEpochRouteResetter(
      navigatorKey: notificationNavigatorKey,
      routeFactory: _authBoundaryRoute,
      onPrincipalExit: _disconnectVoiceForAuthEpoch,
    );
    _authRouteSubscription = FirebaseAuth.instance.authStateChanges().listen(
      (user) => _authRouteResetter.handlePrincipal(user?.uid),
      onError: _authRouteResetter.handleError,
    );
    PushNotificationService.instance.onNotificationTap =
        (type, targetId, actorId, notificationId) {
          return NotificationRouter.route(
            type: type,
            targetId: targetId,
            actorId: actorId,
            notificationId: notificationId,
          );
        };
    // Foreground banners are stream-driven: any freshly arrived unread
    // notification document banners, whether or not FCM is configured or
    // permitted on this device. The FCM foreground hook below stays as a
    // second entry point (it can beat Firestore's snapshot), deduped per
    // notification id through the same source.
    final streamNotifications = ForegroundNotificationStreamSource(
      authStates: FirebaseAuth.instance.authStateChanges(),
      watchNotifications: () => NotificationService().watchNotifications(),
      showBanner: (notification) {
        return _showForegroundBanner(
          title: notification.title,
          body: null,
          type: notification.type,
          targetId: notification.targetId,
          actorId: notification.actorId,
          notificationId: notification.id,
        );
      },
    )..start();
    _streamNotifications = streamNotifications;
    PushNotificationService.instance.claimForegroundNotification =
        streamNotifications.claimPushBanner;
    PushNotificationService.instance.onInAppForegroundNotification =
        (title, body, type, targetId, actorId, notificationId) {
          return _showForegroundBanner(
            title: title,
            body: body,
            type: type,
            targetId: targetId,
            actorId: actorId,
            notificationId: notificationId,
          );
        };
  }

  @override
  void dispose() {
    PushNotificationService.instance.claimForegroundNotification = null;
    PushNotificationService.instance.onInAppForegroundNotification = null;
    unawaited(_authRouteSubscription?.cancel());
    unawaited(_streamNotifications?.dispose());
    super.dispose();
  }

  Widget _authBoundary({
    bool initiallySignedOut = false,
    String? initialAuthError,
  }) {
    return DirectCallCoordinator(
      child: PresenceLifecycle(
        child: AuthGate(
          initiallySignedOut: initiallySignedOut,
          initialAuthError: initialAuthError,
        ),
      ),
    );
  }

  Route<void> _authBoundaryRoute(AuthRouteResetTarget target) {
    // ScaffoldMessenger lives above AuthGate, so banners from the previous
    // account would otherwise survive the route reset and appear on Login or
    // on the next account.
    final messenger = _messengerKey.currentState;
    if (messenger != null) clearSessionSnackBars(messenger);

    return PageRouteBuilder<void>(
      settings: const RouteSettings(name: '/auth-session'),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) =>
          switch (target.reason) {
            AuthRouteResetReason.signedOut => _authBoundary(
              initiallySignedOut: true,
            ),
            AuthRouteResetReason.principalChanged => _authBoundary(),
            AuthRouteResetReason.authError => _authBoundary(
              initialAuthError: target.error.toString(),
            ),
          },
    );
  }

  void _disconnectVoiceForAuthEpoch() {
    final voice = VoiceCallService.instance;
    if (voice.roomId == null && voice.status == VoiceCallStatus.disconnected) {
      return;
    }
    unawaited(
      voice.disconnect(playSound: false).catchError((Object error) {
        debugPrint(
          'YoVoiceApp: local voice disposal failed during auth epoch change '
          '(${error.runtimeType}).',
        );
      }),
    );
  }

  bool _showForegroundBanner({
    required String title,
    required String? body,
    required NotificationType type,
    required String? targetId,
    required String? actorId,
    String? notificationId,
  }) {
    // Treat a deliberately suppressed event as consumed so the Firestore
    // source does not replay a stale message banner after the chat closes.
    // Background/terminated delivery never passes through this app surface.
    if (shouldSuppressForegroundNotification(
      type: type,
      targetId: targetId,
      activeConversations: ActiveConversationRegistry.instance,
    )) {
      return true;
    }
    final messenger = _messengerKey.currentState;
    if (messenger == null) {
      _scheduleForegroundBannerRetry();
      return false;
    }
    final navigatorContext = notificationNavigatorKey.currentContext;
    // Voice-room control docks grow with accessibility text scaling.
    // Keep foreground notifications above them instead of covering the
    // microphone, people, chat or leave actions.
    final bottomClearance = foregroundNotificationBottomClearance(
      navigatorContext == null
          ? TextScaler.noScaling
          : MediaQuery.textScalerOf(navigatorContext),
    );
    try {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          buildForegroundNotificationBanner(
            title: title,
            body: body,
            type: type,
            targetId: targetId,
            actorId: actorId,
            notificationId: notificationId,
            bottomClearance: bottomClearance,
            palette: navigatorContext?.appPalette,
          ),
        );
    } catch (error) {
      debugPrint(
        'YoVoiceApp: foreground banner was not accepted '
        '(${error.runtimeType}).',
      );
      _scheduleForegroundBannerRetry();
      return false;
    }
    // Play only after the visible, deep-linkable surface was accepted. This
    // keeps the completion signal equivalent to one audible + visible event.
    unawaited(UiSoundService.instance.play(UiSound.notification));
    return true;
  }

  void _scheduleForegroundBannerRetry() {
    if (_foregroundRetryScheduled) return;
    _foregroundRetryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _foregroundRetryScheduled = false;
      if (!mounted) return;
      _streamNotifications?.retryPendingBanners();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller =
        widget.preferencesController ?? AppPreferencesController.instance;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => AppPreferencesScope(
        controller: controller,
        child: MaterialApp(
          navigatorKey: notificationNavigatorKey,
          navigatorObservers: [appRouteObserver],
          scaffoldMessengerKey: _messengerKey,
          debugShowCheckedModeBanner: false,
          title: 'YO Voice',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: controller.value.theme.themeMode,
          locale: controller.value.language.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            final theme = Theme.of(context);
            final palette = context.appPalette;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: AppTheme.systemOverlayStyle(theme.brightness, palette),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: _authBoundary(),
        ),
      ),
    );
  }
}
