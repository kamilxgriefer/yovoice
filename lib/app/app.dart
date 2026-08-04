import 'package:flutter/material.dart';

import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/presentation/screens/auth_gate.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';
import 'package:yovoice/features/notifications/presentation/notification_router.dart';

class YoVoiceApp extends StatefulWidget {
  const YoVoiceApp({super.key});

  @override
  State<YoVoiceApp> createState() => _YoVoiceAppState();
}

class _YoVoiceAppState extends State<YoVoiceApp> {
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
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: notificationNavigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'YO Voice',
      theme: AppTheme.darkTheme,
      home: const PresenceLifecycle(child: AuthGate()),
    );
  }
}
