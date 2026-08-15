import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/presentation/screens/auth_gate.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/presentation/notification_router.dart';

SnackBar buildForegroundNotificationBanner({
  required String title,
  required String? body,
  required NotificationType type,
  required String? targetId,
  required String? actorId,
}) {
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(16, 16, 16, 104),
    duration: const Duration(seconds: 5),
    backgroundColor: const Color(0xFF241132),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFF7330A8)),
    ),
    content: Row(
      children: [
        const Icon(
          Icons.notifications_active_rounded,
          color: Color(0xFFD28AFF),
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
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (body?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 2),
                Text(
                  body!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB8ADBF),
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
      textColor: const Color(0xFFD28AFF),
      onPressed: () => NotificationRouter.route(
        type: type,
        targetId: targetId,
        actorId: actorId,
      ),
    ),
  );
}

class YoVoiceApp extends StatefulWidget {
  const YoVoiceApp({super.key});

  @override
  State<YoVoiceApp> createState() => _YoVoiceAppState();
}

class _YoVoiceAppState extends State<YoVoiceApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    PushNotificationService.instance.onNotificationTap =
        (type, targetId, actorId) {
          NotificationRouter.route(
            type: type,
            targetId: targetId,
            actorId: actorId,
          );
        };
    PushNotificationService.instance.onWebForegroundNotification =
        (title, body, type, targetId, actorId) {
          SystemSound.play(SystemSoundType.alert);
          final messenger = _messengerKey.currentState;
          if (messenger == null) return;
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              buildForegroundNotificationBanner(
                title: title,
                body: body,
                type: type,
                targetId: targetId,
                actorId: actorId,
              ),
            );
        };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: notificationNavigatorKey,
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      title: 'YO Voice',
      theme: AppTheme.darkTheme,
      home: const PresenceLifecycle(child: AuthGate()),
    );
  }
}
