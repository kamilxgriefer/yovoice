import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/audio/ui_sound.dart';
import 'package:yovoice/core/audio/ui_sound_service.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/presentation/screens/auth_gate.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/presentation/notification_router.dart';

double foregroundNotificationBottomClearance(TextScaler textScaler) {
  final textScale = textScaler.scale(1);
  return 104.0 + 72.0 * ((textScale - 1.0).clamp(0.0, 1.0));
}

SnackBar buildForegroundNotificationBanner({
  required String title,
  required String? body,
  required NotificationType type,
  required String? targetId,
  required String? actorId,
  double bottomClearance = 104,
}) {
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.fromLTRB(16, 16, 16, bottomClearance),
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
  const YoVoiceApp({this.preferencesController, super.key});

  final AppPreferencesController? preferencesController;

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
          unawaited(UiSoundService.instance.play(UiSound.notification));
          final messenger = _messengerKey.currentState;
          if (messenger == null) return;
          final navigatorContext = notificationNavigatorKey.currentContext;
          // Voice-room control docks grow with accessibility text scaling.
          // Keep foreground notifications above them instead of covering the
          // microphone, people, chat or leave actions.
          final bottomClearance = foregroundNotificationBottomClearance(
            navigatorContext == null
                ? TextScaler.noScaling
                : MediaQuery.textScalerOf(navigatorContext),
          );
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              buildForegroundNotificationBanner(
                title: title,
                body: body,
                type: type,
                targetId: targetId,
                actorId: actorId,
                bottomClearance: bottomClearance,
              ),
            );
        };
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
          home: const PresenceLifecycle(child: AuthGate()),
        ),
      ),
    );
  }
}
