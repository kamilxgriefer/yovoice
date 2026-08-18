import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

/// Runs in a separate isolate with no access to app state. The OS already
/// renders the notification for messages that carry a `notification`
/// payload, so there is nothing to do here — this only exists because
/// [FirebaseMessaging.onBackgroundMessage] requires a registered top-level
/// handler before background messages are delivered at all.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Owns the FCM lifecycle end-to-end: permission request, token
/// register/refresh/unregister, foreground local-notification display, and
/// routing a tap back into the app. Every entry point is wrapped so a
/// missing platform config (no APNs key yet, no web VAPID key, an emulator
/// without Google Play services) degrades to "push doesn't work" rather
/// than crashing app startup — see main.dart's App Check guard for the same
/// pattern applied here.
class PushNotificationService {
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
  }) : _notificationService = notificationService ?? NotificationService(),
       _auth = auth ?? FirebaseAuth.instance;

  static final PushNotificationService instance = PushNotificationService._();

  final NotificationService _notificationService;
  final FirebaseAuth _auth;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  String? _registeredToken;
  bool _initialized = false;
  bool _warnedAboutVapid = false;

  /// Set by the widget layer once a navigator is available. Called with the
  /// notification's type, targetId, and actorId whenever a push is tapped,
  /// whether the app was foregrounded, backgrounded, or launched cold from
  /// it.
  void Function(NotificationType type, String? targetId, String? actorId)?
  onNotificationTap;

  /// Web browsers do not automatically present a `notification` payload
  /// while the tab is focused. The app layer uses this hook for one modest
  /// in-app banner; native foreground messages are presented by the local
  /// notifications plugin with the same system sound as background pushes.
  ///
  /// [notificationId] is the Firestore notification document id carried in
  /// the push payload — the app layer dedupes against its stream-driven
  /// banner source with it, so the same notification never banners twice.
  void Function(
    String title,
    String? body,
    NotificationType type,
    String? targetId,
    String? actorId,
    String? notificationId,
  )?
  onWebForegroundNotification;

  /// Call once, after the user is signed in — token registration needs a
  /// uid to write `users/{uid}/fcmTokens/{token}` under, and requesting
  /// permission before there's any account to attach it to would just mean
  /// asking twice.
  Future<void> initialize() async {
    if (_initialized) return;
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

      await _registerCurrentToken();
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
    try {
      final token = _registeredToken ?? await _currentToken();
      if (token != null && _auth.currentUser != null) {
        await _notificationService.unregisterFcmToken(token);
      }
    } catch (error) {
      // Best-effort by design: sign-out must never fail because a token
      // could not be removed. But a token left behind means the PREVIOUS
      // account keeps receiving push on this device, which is a privacy
      // consequence and not merely a lost convenience — so it is named.
      debugPrint(
        'PushNotificationService: could not unregister this device on sign '
        'out (${error.runtimeType}). The previous account may keep '
        'receiving push here until the token is refreshed or invalidated.',
      );
    }
    _registeredToken = null;
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedAppSubscription?.cancel();
    _initialized = false;
  }

  Future<void> _registerCurrentToken() async {
    final token = await _currentToken();
    if (token == null || _auth.currentUser == null) return;
    _registeredToken = token;
    try {
      await _notificationService.registerFcmToken(
        token,
        platform: _platformName,
      );
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
    if (_auth.currentUser == null) return;
    _registeredToken = token;
    try {
      await _notificationService.registerFcmToken(
        token,
        platform: _platformName,
      );
    } catch (error) {
      debugPrint(
        'PushNotificationService: refreshed FCM token could not be stored '
        '(${error.runtimeType}). This device may stop receiving push until '
        'the next refresh; in-app notifications are unaffected.',
      );
    }
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
        onNotificationTap?.call(type, targetId, actorId);
      },
    );

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'yovoice_activity_v2',
        'YO Voice notifications',
        description: 'Messages, invitations and activity from YO Voice',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('yovoice_notification'),
        enableVibration: true,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    if (kIsWeb) {
      onWebForegroundNotification?.call(
        notification.title ?? 'YO Voice',
        notification.body,
        NotificationType.fromName(message.data['type'] as String?),
        message.data['targetId'] as String?,
        message.data['actorId'] as String?,
        message.data['notificationId'] as String?,
      );
      return;
    }
    try {
      await _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'yovoice_activity_v2',
            'YO Voice notifications',
            channelDescription:
                'Messages, invitations and activity from YO Voice',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('yovoice_notification'),
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'yovoice_notification.wav',
          ),
        ),
        payload:
            '${message.data['type'] ?? ''}|${message.data['targetId'] ?? ''}'
            '|${message.data['actorId'] ?? ''}',
      );
    } catch (error) {
      // Only the foreground re-display failed. The message itself was
      // received and the activity document behind it is already stored.
      debugPrint(
        'PushNotificationService: could not present a foreground '
        'notification (${error.runtimeType}).',
      );
    }
  }

  void _routeFromMessage(RemoteMessage message) {
    final type = NotificationType.fromName(message.data['type'] as String?);
    final targetId = message.data['targetId'] as String?;
    final actorId = message.data['actorId'] as String?;
    onNotificationTap?.call(type, targetId, actorId);
  }
}
