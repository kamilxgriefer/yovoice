import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_notification_engagement.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_mentions.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';
import 'package:yovoice/features/notifications/presentation/notification_router.dart';
import 'package:yovoice/features/notifications/presentation/screens/notification_preferences_screen.dart';

final _placeholderPattern = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');

List<String> _placeholders(String value) =>
    (_placeholderPattern.allMatches(value).map((m) => m.group(0)!).toList()
      ..sort());

void main() {
  group('comment, mention, event and role notifications', () {
    test('every new type has a destination, and none of them is "none"', () {
      const engagement = <NotificationType>[
        NotificationType.momentComment,
        NotificationType.reelComment,
        NotificationType.commentMention,
        NotificationType.serverEventReminder,
        NotificationType.serverRole,
      ];
      expect(
        NotificationRouter.destinationFor(NotificationType.momentComment),
        NotificationDestination.momentComments,
      );
      expect(
        NotificationRouter.destinationFor(NotificationType.reelComment),
        NotificationDestination.reelComments,
      );
      expect(
        NotificationRouter.destinationFor(NotificationType.commentMention),
        NotificationDestination.commentThread,
      );
      expect(
        NotificationRouter.destinationFor(NotificationType.serverEventReminder),
        NotificationDestination.serverEvent,
      );
      expect(
        NotificationRouter.destinationFor(NotificationType.serverRole),
        NotificationDestination.club,
      );
      for (final type in engagement) {
        expect(
          NotificationRouter.destinationFor(type),
          isNot(NotificationDestination.none),
          reason: '${type.name} must be tappable',
        );
      }
      // Every enum value still resolves — the switch stays exhaustive.
      for (final type in NotificationType.values) {
        expect(NotificationRouter.destinationFor(type), isNotNull);
      }
    });

    test('a server row parses its new optional fields', () {
      final firestore = FakeFirebaseFirestore();
      return firestore
          .collection('users')
          .doc('reader')
          .collection('notifications')
          .doc('momentComment_c1')
          .set(<String, Object?>{
            'type': 'momentComment',
            'actorId': 'ada',
            'actorName': 'Ada',
            'actorPhotoUrl': null,
            'targetId': 'moment-1',
            'targetSubId': 'c1',
            'sourcePath': 'voiceMoments/moment-1/comments/c1',
            'targetLabel': null,
            'isRead': false,
            'bellSuppressed': false,
          })
          .then((_) async {
            final doc = await firestore
                .collection('users')
                .doc('reader')
                .collection('notifications')
                .doc('momentComment_c1')
                .get();
            final notification = AppNotification.fromFirestore(doc);
            expect(notification.type, NotificationType.momentComment);
            expect(notification.targetSubId, 'c1');
            expect(
              notification.sourcePath,
              'voiceMoments/moment-1/comments/c1',
            );
            expect(notification.title, 'Ada commented on your Moment');
          });
    });

    test('a row from an older writer still parses with no new fields', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('users')
          .doc('reader')
          .collection('notifications')
          .doc('friendRequest_ada')
          .set(<String, Object?>{
            'type': 'friendRequest',
            'actorId': 'ada',
            'actorName': 'Ada',
            'targetId': 'ada',
            'isRead': false,
          });
      final doc = await firestore
          .collection('users')
          .doc('reader')
          .collection('notifications')
          .doc('friendRequest_ada')
          .get();
      final notification = AppNotification.fromFirestore(doc);
      expect(notification.targetSubId, isNull);
      expect(notification.sourcePath, isNull);
      expect(notification.title, 'Ada sent you a friend request');
    });

    test('titles fall back gracefully when the label is missing', () {
      AppNotification row(NotificationType type, {String? label}) =>
          AppNotification(
            id: 'row',
            type: type,
            actorId: 'ada',
            actorName: 'Ada',
            actorPhotoUrl: null,
            targetId: 'target',
            targetLabel: label,
            isRead: false,
            createdAt: null,
          );
      expect(
        row(NotificationType.serverEventReminder).title,
        'An event is starting soon',
      );
      expect(
        row(NotificationType.serverEventReminder, label: 'Sunday call').title,
        'Starting soon: Sunday call',
      );
      expect(
        row(NotificationType.serverRole).title,
        'Ada promoted you in a server',
      );
      expect(
        row(NotificationType.serverRole, label: 'Family').title,
        'Ada promoted you in Family',
      );
      expect(
        row(NotificationType.commentMention).title,
        'Ada mentioned you in a comment',
      );
    });

    test('each new type rings with a deliberate sound profile', () {
      expect(
        notificationSoundProfileFor(NotificationType.momentComment),
        NotificationSoundProfile.social,
      );
      expect(
        notificationSoundProfileFor(NotificationType.reelComment),
        NotificationSoundProfile.social,
      );
      expect(
        notificationSoundProfileFor(NotificationType.serverRole),
        NotificationSoundProfile.social,
      );
      expect(
        notificationSoundProfileFor(NotificationType.commentMention),
        NotificationSoundProfile.message,
      );
      expect(
        notificationSoundProfileFor(NotificationType.serverEventReminder),
        NotificationSoundProfile.alert,
      );
    });

    test('the composer resolves the ids a comment mentions, capped at five', () {
      final directory = MentionDirectory(<MentionCandidate>[
        MentionCandidate(userId: 'u1', displayName: 'Ada Lovelace'),
        MentionCandidate(userId: 'u2', displayName: 'Nadia'),
      ]);
      expect(
        mentionedUserIds('hi @Ada Lovelace and @Nadia', directory),
        <String>['u1', 'u2'],
      );
      // A repeated mention is one recipient, and an unresolved name is not a
      // mention at all.
      expect(
        mentionedUserIds('@Nadia @Nadia @Nobody', directory),
        <String>['u2'],
      );
      expect(mentionedUserIds('no mentions here', directory), isEmpty);
      expect(
        mentionedUserIds('@Ada Lovelace @Nadia', directory, limit: 1),
        <String>['u1'],
      );
    });

    testWidgets('the preferences screen shows the new group and writes every '
        'type its switch covers', (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final firestore = FakeFirebaseFirestore();
      const uid = 'engagement-preferences-owner';
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: uid),
      );
      await firestore.collection('users').doc(uid).set({
        'uid': uid,
        'notificationPreferences': <String, bool>{},
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: NotificationPreferencesScreen(
            isRootTab: true,
            notificationService: NotificationService(
              firestore: firestore,
              auth: auth,
            ),
            creatorAudienceVisibleStream: Stream.value(false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Moments & Yeels'), findsOneWidget);
      expect(find.text('Comments and mentions'), findsOneWidget);
      expect(find.text('Server events'), findsOneWidget);
      expect(find.text('Your server role'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Comments and mentions'),
        200,
      );
      final row = find.ancestor(
        of: find.text('Comments and mentions'),
        matching: find.byType(Row),
      );
      await tester.tap(
        find.descendant(of: row.first, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();

      final stored =
          (await firestore.collection('users').doc(uid).get())
                  .data()?['notificationPreferences']
              as Map<String, dynamic>;
      // One visible switch, three server types: turning comments off must not
      // leave mentions inside comments still pushing.
      expect(stored['momentComment'], isFalse);
      expect(stored['reelComment'], isFalse);
      expect(stored['commentMention'], isFalse);
    });

    test('every new phrase is translated into every selectable locale', () {
      final translatedLocaleKeys = selectableAppLanguages
          .where(
            (language) =>
                language != AppLanguagePreference.english &&
                language != AppLanguagePreference.polish,
          )
          .map((language) => language.localeKey)
          .toSet();
      expect(
        notificationEngagementTranslations.keys.toSet(),
        translatedLocaleKeys,
      );
      expect(
        appTranslationKeys,
        containsAll(notificationEngagementTranslationKeys),
      );
      for (final localeKey in translatedLocaleKeys) {
        final entries = notificationEngagementTranslations[localeKey]!;
        expect(
          entries.keys.toSet(),
          notificationEngagementTranslationKeys.toSet(),
          reason: localeKey,
        );
        for (final key in notificationEngagementTranslationKeys) {
          final value = translatedPhrase(localeKey, key);
          expect(value, isNotNull, reason: '$localeKey: $key');
          expect(value!.trim(), isNotEmpty, reason: '$localeKey: $key');
          expect(
            _placeholders(value),
            _placeholders(key),
            reason: '$localeKey: $key',
          );
        }
      }
      // The Polish copy is written inline beside the English source, the way
      // every other notification title is.
      const polish = AppLocalizations(Locale('pl'));
      expect(
        polish.template(
          '{actor} commented on your Moment',
          '{actor} komentuje Twój Moment',
          values: {'actor': 'Ada'},
        ),
        'Ada komentuje Twój Moment',
      );
      const german = AppLocalizations(Locale('de'));
      expect(
        german.template(
          '{actor} mentioned you in a comment',
          '{actor} oznacza Cię w komentarzu',
          values: {'actor': 'Ada'},
        ),
        'Ada hat dich in einem Kommentar erwähnt',
      );
    });
  });
}
