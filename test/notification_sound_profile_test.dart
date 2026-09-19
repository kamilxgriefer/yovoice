import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/audio/ui_sound.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';

void main() {
  test('every notification type owns an explicit Prism Halo profile', () {
    const expected = <NotificationType, NotificationSoundProfile>{
      NotificationType.directMessage: NotificationSoundProfile.message,
      NotificationType.mention: NotificationSoundProfile.message,
      NotificationType.reply: NotificationSoundProfile.message,
      // ADR-212. An @mention inside a comment is addressed at one person, so
      // it rings like a message; a comment on your own Moment or Yeel is
      // social; an event reminder is the alert the member asked for.
      NotificationType.commentMention: NotificationSoundProfile.message,
      NotificationType.momentComment: NotificationSoundProfile.social,
      NotificationType.reelComment: NotificationSoundProfile.social,
      NotificationType.serverRole: NotificationSoundProfile.social,
      NotificationType.serverEventReminder: NotificationSoundProfile.alert,
      NotificationType.friendRequest: NotificationSoundProfile.social,
      NotificationType.friendAccepted: NotificationSoundProfile.social,
      NotificationType.follow: NotificationSoundProfile.social,
      NotificationType.clubInvite: NotificationSoundProfile.social,
      NotificationType.clubInviteAccepted: NotificationSoundProfile.social,
      NotificationType.roomInvite: NotificationSoundProfile.social,
      NotificationType.broadcastInvite: NotificationSoundProfile.social,
      NotificationType.liveStarted: NotificationSoundProfile.social,
      NotificationType.achievementUnlocked:
          NotificationSoundProfile.achievement,
      NotificationType.directCall: NotificationSoundProfile.call,
      NotificationType.missedCall: NotificationSoundProfile.alert,
      NotificationType.moderation: NotificationSoundProfile.alert,
      NotificationType.system: NotificationSoundProfile.alert,
    };

    expect(expected.keys.toSet(), NotificationType.values.toSet());
    for (final entry in expected.entries) {
      expect(
        notificationSoundProfileFor(entry.key),
        entry.value,
        reason: entry.key.name,
      );
    }
  });

  test('native sound profiles use fresh immutable Android channels', () {
    expect(
      NotificationSoundProfile.values
          .map((profile) => profile.androidChannelId)
          .toSet(),
      hasLength(NotificationSoundProfile.values.length),
    );
    expect(
      PushNotificationService.androidChannelId,
      NotificationSoundProfile.message.androidChannelId,
    );
    expect(
      PushNotificationService.androidCallChannelId,
      NotificationSoundProfile.call.androidChannelId,
    );

    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(
      manifest,
      contains(
        'android:value="${NotificationSoundProfile.message.androidChannelId}"',
      ),
    );
  });

  test(
    'foreground banners use the matching cue without double-ringing calls',
    () {
      const expected = <NotificationSoundProfile, UiSound?>{
        NotificationSoundProfile.message: UiSound.notification,
        NotificationSoundProfile.social: UiSound.notificationSocial,
        NotificationSoundProfile.achievement: UiSound.notificationAchievement,
        NotificationSoundProfile.alert: UiSound.notificationAlert,
        NotificationSoundProfile.call: null,
      };

      for (final entry in expected.entries) {
        expect(
          entry.key.foregroundUiSound,
          entry.value,
          reason: entry.key.name,
        );
      }
    },
  );

  test('Android and iOS package each exact semantic sound master', () {
    const masters = <NotificationSoundProfile, String>{
      NotificationSoundProfile.message: 'notification.wav',
      NotificationSoundProfile.social: 'notification_social.wav',
      NotificationSoundProfile.achievement: 'notification_achievement.wav',
      NotificationSoundProfile.alert: 'notification_alert.wav',
      NotificationSoundProfile.call: 'call_incoming_loop.wav',
    };
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    for (final entry in masters.entries) {
      final profile = entry.key;
      final master = File(
        'assets/audio/ui/v5/${entry.value}',
      ).readAsBytesSync();
      expect(
        File(
          'android/app/src/main/res/raw/${profile.androidSoundResource}.wav',
        ).readAsBytesSync(),
        master,
        reason: '${profile.name} Android copy',
      );
      expect(
        File('ios/Runner/${profile.iosSoundFile}').readAsBytesSync(),
        master,
        reason: '${profile.name} iOS copy',
      );
      expect(
        project,
        contains('path = ${profile.iosSoundFile};'),
        reason: '${profile.name} must have an Xcode file reference',
      );
      expect(
        project,
        contains('${profile.iosSoundFile} in Resources'),
        reason: '${profile.name} must be bundled in the Runner resources',
      );
    }
  });
}
