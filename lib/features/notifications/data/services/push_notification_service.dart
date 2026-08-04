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

  /// Set by the widget layer once a navigator is available. Called with the
  /// notification's type + targetId whenever a push is tapped, whether the
  /// app was foregrounded, backgrounded, or launched cold from it.
  void Function(NotificationType type, String? targetId)? onNotificationTap;

  /// Call once, after the user is signed in — token registration needs a
  /// uid to write `users/{uid}/fcmTokens/{token}` under, and requesting
  /// permission before there's any account to attach it to would just mean
  /// asking twice.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler,
      );
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
      final token =
          _registeredToken ?? await FirebaseMessaging.instance.getToken();
      if (token != null && _auth.currentUser != null) {
        await _notificationService.unregisterFcmToken(token);
      }
    } catch (_) {
      // Best-effort: a stale token left behind just means one fewer device
      // gets push for the old account, never a crash on sign-out.
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
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || _auth.currentUser == null) return;
    _registeredToken = token;
    try {
      await _notificationService.registerFcmToken(
        token,
        platform: _platformName,
      );
    } catch (_) {}
  }

  Future<void> _handleTokenRefresh(String token) async {
    if (_auth.currentUser == null) return;
    _registeredToken = token;
    try {
      await _notificationService.registerFcmToken(
        token,
        platform: _platformName,
      );
    } catch (_) {}
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
        onNotificationTap?.call(type, targetId);
      },
    );
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    if (kIsWeb) return;
    final notification = message.notification;
    if (notification == null) return;
    try {
      await _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'yovoice_default',
            'YO Voice notifications',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload:
            '${message.data['type'] ?? ''}|${message.data['targetId'] ?? ''}',
      );
    } catch (_) {}
  }

  void _routeFromMessage(RemoteMessage message) {
    final type = NotificationType.fromName(message.data['type'] as String?);
    final targetId = message.data['targetId'] as String?;
    onNotificationTap?.call(type, targetId);
  }
}
