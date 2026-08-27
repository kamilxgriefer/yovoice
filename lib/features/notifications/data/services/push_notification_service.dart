import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

/// Runs in a separate isolate with no access to app state. The OS already
/// renders the notification for messages that carry a `notification`
/// payload, so there is nothing to do here — this only exists because
/// [FirebaseMessaging.onBackgroundMessage] requires a registered top-level
/// handler before background messages are delivered at all.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// A single-use reservation for one foreground notification presentation.
///
/// FCM and the Firestore notification stream are independent deliveries of the
/// same event. Reserving first keeps them from presenting concurrently, while
/// completing only after a banner/system notification was accepted lets the
/// losing path retry when presentation was unavailable.
class ForegroundNotificationClaim {
  ForegroundNotificationClaim(this._onComplete);

  final void Function(bool presented) _onComplete;
  bool _completed = false;

  void complete({required bool presented}) {
    if (_completed) return;
    _completed = true;
    _onComplete(presented);
  }
}

/// Explicitly distinguishes an untracked legacy payload from a vetoed
/// duplicate. A nullable claim alone cannot represent both without either
/// dropping id-less pushes or allowing already-presented ids through again.
class ForegroundNotificationClaimDecision {
  const ForegroundNotificationClaimDecision.allowUntracked()
    : shouldPresent = true,
      claim = null;

  const ForegroundNotificationClaimDecision.skip()
    : shouldPresent = false,
      claim = null;

  ForegroundNotificationClaimDecision.claimed(
    ForegroundNotificationClaim claimed,
  ) : shouldPresent = true,
      claim = claimed;

  final bool shouldPresent;
  final ForegroundNotificationClaim? claim;
}

/// Applies the explicit arbitration decision and settles any claim from the
/// actual presentation result, including the exceptional path. Kept as a
/// small testable seam because platform local-notification plugins are not
/// available in VM tests.
@visibleForTesting
Future<bool> presentForegroundNotificationDecision({
  required ForegroundNotificationClaimDecision decision,
  required Future<bool> Function() present,
}) async {
  if (!decision.shouldPresent) return false;
  var presented = false;
  try {
    presented = await present();
    return presented;
  } finally {
    decision.claim?.complete(presented: presented);
  }
}

/// Owns the FCM lifecycle end-to-end: permission request, token
/// register/refresh/unregister, foreground local-notification display, and
/// routing a tap back into the app. Every entry point is wrapped so a
/// missing platform config (no APNs key yet, no web VAPID key, an emulator
/// without Google Play services) degrades to "push doesn't work" rather
/// than crashing app startup — see main.dart's App Check guard for the same
/// pattern applied here.
class PushNotificationService {
  /// Android notification-channel sound settings are immutable after the
  /// channel is first created. v3 is the Velvet Prism sound migration; a new
  /// id is required for existing installs to receive the new master.
  static const String androidChannelId = 'yovoice_activity_v3';
  static const String androidCallChannelId = 'yovoice_calls_v1';
  static const String androidSoundResource = 'yovoice_notification';
  static const String iosSoundFile = 'yovoice_notification.wav';

  static const String _rotationPendingPreference =
      'push_token_rotation_pending_v1';
  static const Duration _signOutCleanupTimeout = Duration(seconds: 4);

  /// Web push needs a VAPID public key, and there is no safe default for
  /// it: without one `getToken()` on web either throws or yields a token
  /// the browser will never deliver to. It is supplied at build time and
  /// is deliberately absent from the repository.
  ///
  ///   flutter build web --release \
  ///     --dart-define=YOVOICE_WEB_PUSH_VAPID_KEY=`<public key>`
  ///
  /// The key is the "Web Push certificates" key pair's PUBLIC key, from
  /// Firebase Console → Project settings → Cloud Messaging. It is a
  /// public value (it ships in the client either way), but it is a
  /// per-project configuration value, so it lives in the build command
  /// and not in source. Nothing else about web push is gated on it.
  static const String webVapidKey = String.fromEnvironment(
    'YOVOICE_WEB_PUSH_VAPID_KEY',
  );

  /// True when this build can actually register for web push. On every
  /// other platform token registration has no such prerequisite.
  static bool get webPushConfigured => !kIsWeb || webVapidKey.isNotEmpty;

  PushNotificationService._({
    NotificationService? notificationService,
    FirebaseAuth? auth,
    Future<void> Function()? deleteMessagingToken,
  }) : _notificationService = notificationService ?? NotificationService(),
       _auth = auth ?? FirebaseAuth.instance,
       _deleteMessagingToken =
           deleteMessagingToken ?? FirebaseMessaging.instance.deleteToken;

  static final PushNotificationService instance = PushNotificationService._();

  final NotificationService _notificationService;
  final FirebaseAuth _auth;
  final Future<void> Function() _deleteMessagingToken;
  final PushTokenPrivacyGuard _tokenPrivacyGuard = PushTokenPrivacyGuard();
  final PushIdentityEpochGuard _identityEpochGuard = PushIdentityEpochGuard();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  String? _registeredToken;
  String? _registeredUserId;
  Future<void> _registrationTail = Future<void>.value();
  bool _initialized = false;
  bool _warnedAboutVapid = false;

  /// Set by the widget layer once a navigator is available. Called with the
  /// notification's type, targetId, and actorId whenever a push is tapped,
  /// whether the app was foregrounded, backgrounded, or launched cold from
  /// it.
  void Function(
    NotificationType type,
    String? targetId,
    String? actorId,
    String? notificationId,
  )?
  onNotificationTap;

  /// Arbitrates the FCM foreground path against the independent Firestore
  /// banner stream. A claimed decision is a temporary reservation, not proof
  /// of presentation: FCM must complete it with the actual native/in-app
  /// result. The explicit decision also distinguishes an already-owned event
  /// from a legacy payload without an id, which remains allowed but untracked.
  ForegroundNotificationClaimDecision Function(String? notificationId)?
  claimForegroundNotification;

  /// Web browsers do not automatically present a `notification` payload
  /// while the tab is focused, so they always use this in-app path. Native
  /// normally uses a local system notification; this hook is also its safe
  /// fallback when that platform presentation throws.
  ///
  /// [notificationId] is the Firestore notification document id carried in
  /// the push payload — the app layer dedupes against its stream-driven
  /// banner source with it, so the same notification never banners twice.
  bool Function(
    String title,
    String? body,
    NotificationType type,
    String? targetId,
    String? actorId,
    String? notificationId,
  )?
  onInAppForegroundNotification;

  /// Call once, after the user is signed in — token registration needs a
  /// uid to write `users/{uid}/fcmTokens/{token}` under, and requesting
  /// permission before there's any account to attach it to would just mean
  /// asking twice.
  Future<void> initialize() async {
    if (_initialized) {
      // Listeners and OS permission are device-scoped and must not be added
      // twice, but token ownership is account-scoped. After A signs out and
      // B signs in, bind a freshly rotated token to B instead of treating the
      // already-initialised device as finished forever.
      if (shouldRebindPushIdentity(
        registeredUserId: _registeredUserId,
        currentUserId: _auth.currentUser?.uid,
      )) {
        if (!await _bindCurrentIdentity()) {
          debugPrint(
            'PushNotificationService: account switch token rotation is '
            'still pending; the previous token will not be registered to '
            'the new account.',
          );
          return;
        }
      }
      return;
    }
    _initialized = true;

    // An unconfigured web build cannot register a token, so asking the
    // browser for notification permission would spend the user's single
    // prompt on a capability that cannot work — and browsers do not give
    // it back. Nothing else in the notification system depends on this.
    if (kIsWeb && webVapidKey.isEmpty) {
      debugPrint(
        'PushNotificationService: skipping web push setup — no VAPID key '
        'in this build. Background/system push will not work; the in-app '
        'activity feed, badge and foreground banners come from Firestore '
        'and keep working.',
      );
      return;
    }

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await _initLocalNotifications();

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      await _bindCurrentIdentity();
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen(
        _handleTokenRefresh,
        onError: (_) {},
      );

      _foregroundSubscription = FirebaseMessaging.onMessage.listen(
        _showLocalNotification,
        onError: (_) {},
      );
      _openedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _routeFromMessage,
        onError: (_) {},
      );

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) _routeFromMessage(initialMessage);
    } catch (error, stackTrace) {
      debugPrint(
        'PushNotificationService.initialize failed (push will be '
        'unavailable this session): $error\n$stackTrace',
      );
    }
  }

  /// Call on sign-out, BEFORE the auth session actually clears — deleting
  /// `fcmTokens/{token}` requires `isOwner(userId)`, which needs a live
  /// session. Stops a shared/reused device from keeping the previous
  /// account's push subscription active.
  Future<void> unregisterCurrentDevice() async {
    final userId = _auth.currentUser?.uid;
    _identityEpochGuard.beginTransition();
    final token = _registeredToken;
    _registeredToken = null;
    _registeredUserId = null;

    // Start every privacy boundary immediately and settle them concurrently.
    // In particular, a Firestore write that never resolves while offline must
    // not postpone the durable marker or platform-token invalidation. The
    // synchronous epoch transition above prevents new refresh writes, while a
    // queued pre-transition operation either finishes before the owner-row
    // delete or observes the stale epoch and becomes a no-op.
    final rotationPersistedFuture = resolvePushCleanupWithin(
      requirePushTokenRotation(guard: _tokenPrivacyGuard),
      timeout: _signOutCleanupTimeout,
    );
    final ownerCleanupFuture = token != null && userId != null
        ? retirePushOwnerRowWithin(
            registrationTail: _registrationTail,
            deleteOwnerRow: () => _notificationService.unregisterFcmToken(
              token,
              expectedUserId: userId,
            ),
            timeout: _signOutCleanupTimeout,
          )
        : completePushCleanupWithin(
            _registrationTail,
            timeout: _signOutCleanupTimeout,
          ).then(
            (drained) => (registrationDrained: drained, ownerRowRemoved: true),
          );
    final rotatedFuture = resolvePushCleanupWithin(
      _tokenPrivacyGuard.rotate(_deleteMessagingToken),
      timeout: _signOutCleanupTimeout,
    );

    final rotationPersisted = await rotationPersistedFuture;
    final ownerCleanup = await ownerCleanupFuture;
    final rotated = await rotatedFuture;

    if (!ownerCleanup.registrationDrained) {
      debugPrint(
        'PushNotificationService: a pre-sign-out token write did not settle '
        'within the cleanup window. Its identity epoch is revoked and the '
        'owner-row cleanup was issued independently.',
      );
    }
    if (!ownerCleanup.ownerRowRemoved) {
      debugPrint(
        'PushNotificationService: could not remove this device token from the '
        'previous account within the cleanup window. That account may keep '
        'receiving push here until the token is refreshed or invalidated.',
      );
    }
    if (rotated == true && rotationPersisted == true) {
      final cleared = await completePushCleanupWithin(
        clearPushTokenRotationPending(),
        timeout: _signOutCleanupTimeout,
      );
      if (!cleared) {
        debugPrint(
          'PushNotificationService: token rotation succeeded but its durable '
          'pending marker could not be cleared. The next binding will rotate '
          'again rather than reusing an uncertain token.',
        );
      }
    }
    if (rotated != true) {
      debugPrint(
        'PushNotificationService: could not invalidate the platform token on '
        'sign out within the cleanup window. Registration for the next account '
        'is blocked until token rotation succeeds.',
      );
      if (rotationPersisted != true) {
        debugPrint(
          'PushNotificationService: the durable rotation marker could not be '
          'stored either. This process remains fail-closed, but after a full '
          'restart token ownership cannot be proven until the platform '
          'invalidates or refreshes the token.',
        );
      }
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedAppSubscription?.cancel();
    _initialized = false;
  }

  Future<bool> _bindCurrentIdentity() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return false;
    final epoch = _identityEpochGuard.beginTransition();
    final drainedFuture = completePushCleanupWithin(
      _registrationTail,
      timeout: _signOutCleanupTimeout,
    );
    final persistedFuture = resolvePushCleanupWithin(
      requirePushTokenRotation(guard: _tokenPrivacyGuard),
      timeout: _signOutCleanupTimeout,
    );
    final drained = await drainedFuture;
    final persisted = await persistedFuture;
    if (!drained || persisted != true) {
      debugPrint(
        'PushNotificationService: previous token work or its durable rotation '
        'marker did not settle within the binding window. Registration remains '
        'fail-closed unless platform invalidation succeeds.',
      );
    }
    if (!await _ensureTokenRotationCompleted()) return false;
    if (_auth.currentUser?.uid != userId) return false;
    if (!_identityEpochGuard.completeTransition(epoch)) return false;
    await _registerCurrentToken(expectedUserId: userId, epoch: epoch);
    return _registeredUserId == userId;
  }

  Future<void> _registerCurrentToken({
    required String expectedUserId,
    required int epoch,
  }) {
    return _enqueueRegistration(() async {
      if (_tokenPrivacyGuard.rotationRequired ||
          !_identityEpochGuard.canRegister(epoch) ||
          _auth.currentUser?.uid != expectedUserId) {
        return;
      }
      final token = await _currentToken();
      if (token == null ||
          !_identityEpochGuard.canRegister(epoch) ||
          _auth.currentUser?.uid != expectedUserId) {
        return;
      }
      // Store before the network write. If sign-out begins while the write is
      // in flight, unregister waits this queue and can then delete this exact
      // token instead of racing past a null field.
      _registeredToken = token;
      try {
        await _notificationService.registerFcmToken(
          token,
          platform: _platformName,
          expectedUserId: expectedUserId,
        );
        if (_identityEpochGuard.canRegister(epoch) &&
            _auth.currentUser?.uid == expectedUserId) {
          _registeredUserId = expectedUserId;
        }
      } catch (error) {
        // A token that fails to persist means this device silently gets no
        // push. That is worth saying out loud — the in-app activity feed
        // is unaffected either way, so this is never fatal.
        debugPrint(
          'PushNotificationService: could not store the FCM token for this '
          'device (${error.runtimeType}). Push will not reach it; in-app '
          'notifications are unaffected.',
        );
      }
    });
  }

  /// The device token, or null when this platform cannot produce one.
  ///
  /// On web `getToken()` REQUIRES the VAPID key. Calling it without one
  /// is not a degraded path, it is a broken one: it throws, or hands
  /// back something undeliverable. So an unconfigured web build does not
  /// call it at all, says why once, and leaves the rest of the
  /// notification system alone.
  Future<String?> _currentToken() async {
    if (kIsWeb && webVapidKey.isEmpty) {
      if (!_warnedAboutVapid) {
        _warnedAboutVapid = true;
        debugPrint(
          'PushNotificationService: web push is not configured — build '
          'with --dart-define=YOVOICE_WEB_PUSH_VAPID_KEY=<public key> to '
          'enable it. No token will be registered; the in-app activity '
          'feed and badge are unaffected.',
        );
      }
      return null;
    }
    try {
      return kIsWeb
          ? await FirebaseMessaging.instance.getToken(vapidKey: webVapidKey)
          : await FirebaseMessaging.instance.getToken();
    } catch (error) {
      debugPrint(
        'PushNotificationService: getToken failed (${error.runtimeType}). '
        'This device will not receive push; in-app notifications are '
        'unaffected.',
      );
      return null;
    }
  }

  Future<void> _handleTokenRefresh(String token) async {
    final userId = _auth.currentUser?.uid;
    final epoch = _identityEpochGuard.epoch;
    if (userId == null || !_identityEpochGuard.canRegister(epoch)) return;
    await _enqueueRegistration(() async {
      if (!_identityEpochGuard.canRegister(epoch) ||
          _auth.currentUser?.uid != userId) {
        return;
      }
      // A platform-issued refresh means the previous registration token is no
      // longer the token being bound. A sign-out transition is synchronous and
      // drains this queue before persisting its marker, so this clear can never
      // erase a newer account-transition requirement.
      _tokenPrivacyGuard.markTokenRefreshed();
      await clearPushTokenRotationPending().catchError((_) => false);
      if (!_identityEpochGuard.canRegister(epoch) ||
          _auth.currentUser?.uid != userId) {
        return;
      }
      _registeredToken = token;
      try {
        await _notificationService.registerFcmToken(
          token,
          platform: _platformName,
          expectedUserId: userId,
        );
        if (_identityEpochGuard.canRegister(epoch) &&
            _auth.currentUser?.uid == userId) {
          _registeredUserId = userId;
        }
      } catch (error) {
        debugPrint(
          'PushNotificationService: refreshed FCM token could not be stored '
          '(${error.runtimeType}). This device may stop receiving push until '
          'the next refresh; in-app notifications are unaffected.',
        );
      }
    });
  }

  Future<void> _enqueueRegistration(Future<void> Function() operation) {
    final scheduled = _registrationTail.then((_) => operation());
    _registrationTail = scheduled.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return scheduled;
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'other';
  }

  Future<void> _initLocalNotifications() async {
    if (kIsWeb) return;
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        final parts = payload.split('|');
        final type = NotificationType.fromName(
          parts.isNotEmpty ? parts[0] : null,
        );
        final targetId = parts.length > 1 && parts[1].isNotEmpty
            ? parts[1]
            : null;
        final actorId = parts.length > 2 && parts[2].isNotEmpty
            ? parts[2]
            : null;
        final notificationId = parts.length > 3 && parts[3].isNotEmpty
            ? parts[3]
            : null;
        onNotificationTap?.call(type, targetId, actorId, notificationId);
      },
    );

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        androidChannelId,
        'YO Voice notifications',
        description: 'Messages, invitations and activity from YO Voice',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(androidSoundResource),
        enableVibration: true,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
      const callChannel = AndroidNotificationChannel(
        androidCallChannelId,
        'YO Voice calls',
        description: 'Incoming private voice calls',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(androidSoundResource),
        enableVibration: true,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(callChannel);
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final type = NotificationType.fromName(message.data['type'] as String?);
    final isCall = type == NotificationType.directCall;
    final notificationId = message.data['notificationId'] as String?;
    final claimOwner = claimForegroundNotification;
    var decision = const ForegroundNotificationClaimDecision.allowUntracked();
    if (claimOwner != null) {
      try {
        decision = claimOwner(notificationId);
      } catch (error) {
        // The Firestore stream remains the source-of-truth fallback. If its
        // arbiter cannot reserve this delivery, do not risk a duplicate native
        // sound/banner here.
        debugPrint(
          'PushNotificationService: could not reserve foreground '
          'notification (${error.runtimeType}).',
        );
        return;
      }
    }

    await presentForegroundNotificationDecision(
      decision: decision,
      present: () async {
        if (kIsWeb) {
          return _tryShowInAppForegroundNotification(
            message,
            notificationId: notificationId,
          );
        }
        try {
          await _localNotifications.show(
            id: notification.hashCode,
            title: notification.title,
            body: notification.body,
            notificationDetails: NotificationDetails(
              android: AndroidNotificationDetails(
                isCall ? androidCallChannelId : androidChannelId,
                isCall ? 'YO Voice calls' : 'YO Voice notifications',
                channelDescription: isCall
                    ? 'Incoming private voice calls'
                    : 'Messages, invitations and activity from YO Voice',
                importance: isCall ? Importance.max : Importance.high,
                priority: isCall ? Priority.max : Priority.high,
                playSound: true,
                sound: const RawResourceAndroidNotificationSound(
                  androidSoundResource,
                ),
                enableVibration: true,
                category: isCall
                    ? AndroidNotificationCategory.call
                    : AndroidNotificationCategory.social,
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
                sound: iosSoundFile,
              ),
            ),
            payload:
                '${message.data['type'] ?? ''}|'
                '${message.data['targetId'] ?? ''}|'
                '${message.data['actorId'] ?? ''}|'
                '${message.data['notificationId'] ?? ''}',
          );
          return true;
        } catch (error) {
          // The native path did not accept a presentation. Try the in-app
          // surface, and release the reservation to Firestore if that surface
          // is not mounted either.
          debugPrint(
            'PushNotificationService: could not present a foreground '
            'notification (${error.runtimeType}).',
          );
          return _tryShowInAppForegroundNotification(
            message,
            notificationId: notificationId,
          );
        }
      },
    );
  }

  bool _tryShowInAppForegroundNotification(
    RemoteMessage message, {
    required String? notificationId,
  }) {
    final notification = message.notification;
    if (notification == null) return false;
    try {
      return onInAppForegroundNotification?.call(
            notification.title ?? 'YO Voice',
            notification.body,
            NotificationType.fromName(message.data['type'] as String?),
            message.data['targetId'] as String?,
            message.data['actorId'] as String?,
            notificationId,
          ) ??
          false;
    } catch (error) {
      debugPrint(
        'PushNotificationService: in-app foreground presentation failed '
        '(${error.runtimeType}).',
      );
      return false;
    }
  }

  void _routeFromMessage(RemoteMessage message) {
    final type = NotificationType.fromName(message.data['type'] as String?);
    final targetId = message.data['targetId'] as String?;
    final actorId = message.data['actorId'] as String?;
    final notificationId = message.data['notificationId'] as String?;
    onNotificationTap?.call(type, targetId, actorId, notificationId);
  }

  Future<bool> _ensureTokenRotationCompleted() async {
    final persistedRotationPending = await resolvePushCleanupWithin(
      isPushTokenRotationPending(),
      timeout: _signOutCleanupTimeout,
    );
    if (persistedRotationPending == null) {
      // If durable state cannot be read, token ownership is unknown. Rotate
      // before any registration instead of treating the read failure as a
      // clean account switch.
      _tokenPrivacyGuard.requireRotation();
    }
    if (persistedRotationPending == true) _tokenPrivacyGuard.requireRotation();
    if (!_tokenPrivacyGuard.rotationRequired) return true;
    final rotated = await resolvePushCleanupWithin(
      _tokenPrivacyGuard.rotate(_deleteMessagingToken),
      timeout: _signOutCleanupTimeout,
    );
    if (rotated == true) {
      await completePushCleanupWithin(
        clearPushTokenRotationPending(),
        timeout: _signOutCleanupTimeout,
      );
    }
    return rotated == true;
  }
}

bool shouldRebindPushIdentity({
  required String? registeredUserId,
  required String? currentUserId,
}) => currentUserId != null && currentUserId != registeredUserId;

@visibleForTesting
class PushIdentityEpochGuard {
  int _epoch = 0;
  bool _transitionInProgress = false;

  int get epoch => _epoch;
  bool get transitionInProgress => _transitionInProgress;

  int beginTransition() {
    _transitionInProgress = true;
    return ++_epoch;
  }

  bool completeTransition(int epoch) {
    if (epoch != _epoch) return false;
    _transitionInProgress = false;
    return true;
  }

  bool canRegister(int epoch) => !_transitionInProgress && epoch == _epoch;
}

@visibleForTesting
class PushTokenPrivacyGuard {
  bool _rotationRequired = false;

  bool get rotationRequired => _rotationRequired;

  void requireRotation() {
    _rotationRequired = true;
  }

  Future<bool> rotate(Future<void> Function() deleteToken) async {
    if (!_rotationRequired) return true;
    try {
      await deleteToken();
      _rotationRequired = false;
      return true;
    } on Exception {
      return false;
    }
  }

  void markTokenRefreshed() {
    _rotationRequired = false;
  }
}

@visibleForTesting
Future<bool> isPushTokenRotationPending() async {
  final preferences = await SharedPreferences.getInstance();
  return preferences.getBool(
        PushNotificationService._rotationPendingPreference,
      ) ??
      false;
}

@visibleForTesting
Future<bool> requirePushTokenRotation({
  required PushTokenPrivacyGuard guard,
  Future<bool> Function()? persistPending,
}) async {
  guard.requireRotation();
  try {
    return await (persistPending ?? markPushTokenRotationPending)();
  } catch (_) {
    return false;
  }
}

@visibleForTesting
Future<bool> markPushTokenRotationPending() async {
  final preferences = await SharedPreferences.getInstance();
  return preferences.setBool(
    PushNotificationService._rotationPendingPreference,
    true,
  );
}

@visibleForTesting
Future<bool> clearPushTokenRotationPending() async {
  final preferences = await SharedPreferences.getInstance();
  return preferences.remove(PushNotificationService._rotationPendingPreference);
}

@visibleForTesting
Future<bool> completePushCleanupWithin(
  Future<void> operation, {
  required Duration timeout,
}) async {
  try {
    await operation.timeout(timeout);
    return true;
  } catch (_) {
    return false;
  }
}

@visibleForTesting
Future<bool?> resolvePushCleanupWithin(
  Future<bool> operation, {
  required Duration timeout,
}) async {
  try {
    return await operation.timeout(timeout);
  } catch (_) {
    return null;
  }
}

@visibleForTesting
Future<({bool registrationDrained, bool ownerRowRemoved})>
retirePushOwnerRowWithin({
  required Future<void> registrationTail,
  required Future<void> Function() deleteOwnerRow,
  required Duration timeout,
}) async {
  // Start with an eager delete so ordinary sign-out is not delayed by SDK
  // bookkeeping. A registration that already passed its epoch checks before
  // sign-out may still finish after that delete, though. Once the bounded
  // drain confirms no such write remains, delete again so retirement is the
  // final server-side operation.
  final eagerDelete = completePushCleanupWithin(
    Future<void>.sync(deleteOwnerRow),
    timeout: timeout,
  );
  final registrationDrained = await completePushCleanupWithin(
    registrationTail,
    timeout: timeout,
  );
  final eagerRemoved = await eagerDelete;
  if (!registrationDrained) {
    return (registrationDrained: false, ownerRowRemoved: eagerRemoved);
  }
  final postDrainRemoved = await completePushCleanupWithin(
    Future<void>.sync(deleteOwnerRow),
    timeout: timeout,
  );
  return (registrationDrained: true, ownerRowRemoved: postDrainRemoved);
}
