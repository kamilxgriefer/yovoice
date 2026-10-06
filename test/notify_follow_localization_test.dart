import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_notify_follow.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/notifications/presentation/notification_copy.dart';
import 'package:yovoice/features/notifications/presentation/screens/notification_preferences_screen.dart';

/// Notification copy in all 41 translated locales (ADR-237).
///
/// `app_translation_catalog.dart` merges this module with
/// `notifyFollowTranslations[locale]!`, so a missing locale is a null-check
/// crash on the first catalog read in every locale, not an English fallback.
/// A dropped placeholder is a crash in that locale, and an English value is a
/// silent fallback; both are pinned here per key.
final _placeholderPattern = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');

List<String> _placeholders(String value) =>
    _placeholderPattern.allMatches(value).map((m) => m.group(0)!).toList()
      ..sort();

/// The key a value's placeholders are compared with: a `notifyFollow.*`
/// context key has none.
String _placeholderSource(String key) =>
    key.startsWith('notifyFollow.') ? '' : key;

Set<String> _translatedLocaleKeys() => selectableAppLanguages
    .where(
      (language) =>
          language != AppLanguagePreference.english &&
          language != AppLanguagePreference.polish,
    )
    .map((language) => language.localeKey)
    .toSet();

String _joinedLiteral(String expression) {
  final literal = RegExp(r'''(?:'((?:\\.|[^'])*)'|"((?:\\.|[^"])*)")''');
  return literal.allMatches(expression).map((match) {
    final encoded = match.group(1) ?? match.group(2)!;
    return encoded
        .replaceAll(r"\'", "'")
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', r'\');
  }).join();
}

/// The catalog key of every `text(`, `template(` and `contextualText(` call
/// in [source].
List<String> _catalogKeys(String source) {
  const literals = r'''((?:(?:'(?:\\.|[^'])*'|"(?:\\.|[^"])*")\s*)+)''';
  final call = RegExp(
    '\\.(?:text|template|contextualText)\\(\\s*$literals,',
    multiLine: true,
  );
  return <String>[
    for (final match in call.allMatches(source))
      _joinedLiteral(match.group(1)!),
  ];
}

AppNotification _row(
  NotificationType type, {
  String actor = 'Pracownia Glina',
  String? label,
  String? targetId,
  String? preview,
}) => AppNotification(
  id: 'row',
  type: type,
  actorId: 'actor',
  actorName: actor,
  actorPhotoUrl: null,
  targetId: targetId,
  targetLabel: label,
  isRead: false,
  createdAt: DateTime(2026, 10, 3, 12),
  postPreview: preview,
);

void main() {
  final translatedLocaleKeys = _translatedLocaleKeys();

  group('notify follow catalog', () {
    test('covers exactly the 41 translated locales', () {
      expect(AppLocalizations.supportedLocales, hasLength(43));
      expect(translatedLocaleKeys, hasLength(41));
      expect(notifyFollowTranslations.keys.toSet(), translatedLocaleKeys);
    });

    test('keys are unique and registered in the app catalog', () {
      expect(
        notifyFollowTranslationKeys.toSet(),
        hasLength(notifyFollowTranslationKeys.length),
        reason: 'duplicate key in notifyFollowTranslationKeys',
      );
      for (final key in notifyFollowTranslationKeys) {
        expect(appTranslationKeys, contains(key));
      }
    });

    test('every locale translates every key and keeps its placeholders', () {
      for (final localeKey in translatedLocaleKeys) {
        final translations = notifyFollowTranslations[localeKey]!;
        expect(
          translations.keys.toSet(),
          notifyFollowTranslationKeys.toSet(),
          reason: '$localeKey must contain exactly the module keys',
        );
        for (final key in notifyFollowTranslationKeys) {
          final value = translations[key]!;
          expect(value.trim(), isNotEmpty, reason: '$localeKey "$key"');
          expect(value, value.trim(), reason: '$localeKey "$key"');
          expect(
            _placeholders(value),
            _placeholders(_placeholderSource(key)),
            reason: '$localeKey changed placeholders for "$key": "$value"',
          );
          // No silent English. No value in this module is naturally the
          // same as its English source.
          expect(
            value,
            isNot(key),
            reason: '$localeKey "$key" is still English',
          );
          // The merged catalog serves exactly this value.
          expect(translatedPhrase(localeKey, key), value);
        }
      }
    });

    test('brand words stay as written in every locale', () {
      for (final localeKey in translatedLocaleKeys) {
        final translations = notifyFollowTranslations[localeKey]!;
        for (final key in notifyFollowTranslationKeys) {
          if (key.contains('YO Voice')) {
            expect(
              translations[key],
              contains('YO Voice'),
              reason: '$localeKey "$key"',
            );
          }
        }
        expect(
          translations['LIVE from people you follow'],
          contains('LIVE'),
          reason: localeKey,
        );
      }
    });

    test('the copy helper only uses catalogued keys', () {
      final source = File(
        'lib/features/notifications/presentation/notification_copy.dart',
      ).readAsStringSync();
      final keys = _catalogKeys(source);
      expect(keys.length, greaterThan(40));
      for (final key in keys) {
        expect(
          appTranslationKeys,
          contains(key),
          reason: 'notification_copy.dart uses an uncatalogued key "$key"',
        );
      }
      // The notification centre itself: its subtitle, heading, actions,
      // empty and error states and screen-reader labels used to be English
      // beside the translated rows.
      final bell = File(
        'lib/features/notifications/presentation/screens/'
        'notifications_screen.dart',
      ).readAsStringSync();
      final bellKeys = _catalogKeys(bell);
      expect(bellKeys.length, greaterThan(20));
      for (final key in bellKeys) {
        expect(
          appTranslationKeys,
          contains(key),
          reason: 'notifications_screen.dart uses an uncatalogued key "$key"',
        );
      }
      for (final key in const [
        'notifyBell.activity',
        'Mark all read',
        'You are all caught up',
        'Friend requests, messages and activity',
        'Delete notification',
      ]) {
        expect(bellKeys, contains(key));
        expect(notifyFollowTranslationKeys, contains(key));
      }
      // The settings rows added for the Following group.
      final preferences = File(
        'lib/features/notifications/presentation/screens/'
        'notification_preferences_screen.dart',
      ).readAsStringSync();
      for (final key in const [
        'notifyFollow.groupFollowing',
        'LIVE from people you follow',
        'New posts from Pages you follow',
        'At most one notification a day from each Page',
      ]) {
        expect(_catalogKeys(preferences), contains(key));
        expect(appTranslationKeys, contains(key));
      }
    });
  });

  group('titles in every language', () {
    // Types whose title is a sentence the app composes (a `system`, a
    // labelled `moderation` and the two Page notices carry server text).
    const composed = <NotificationType>[
      NotificationType.friendRequest,
      NotificationType.friendAccepted,
      NotificationType.follow,
      NotificationType.clubInvite,
      NotificationType.clubInviteAccepted,
      NotificationType.roomInvite,
      NotificationType.broadcastInvite,
      NotificationType.liveStarted,
      NotificationType.directMessage,
      NotificationType.directCall,
      NotificationType.missedCall,
      NotificationType.mention,
      NotificationType.reply,
      NotificationType.momentComment,
      NotificationType.reelComment,
      NotificationType.commentMention,
      NotificationType.serverEventReminder,
      NotificationType.serverRole,
      NotificationType.pagePostComment,
      NotificationType.pagePostPublished,
      NotificationType.achievementUnlocked,
      NotificationType.moderation,
    ];

    test('no bell title falls back to English in any of the 42 languages', () {
      const english = NotificationCopy(AppLocalizations(Locale('en')));
      for (final language in selectableAppLanguages) {
        if (language == AppLanguagePreference.english) continue;
        final copy = NotificationCopy(AppLocalizations(language.locale!));
        for (final type in composed) {
          for (final label in <String?>[null, 'Nocne Granie']) {
            // A moderator's own words are shown as written.
            if (type == NotificationType.moderation && label != null) continue;
            final title = copy.titleFor(type: type, actor: 'Ola', label: label);
            final source = english.titleFor(
              type: type,
              actor: 'Ola',
              label: label,
            );
            final reason = '${type.name} in ${language.localeKey}';
            expect(title.trim(), isNotEmpty, reason: reason);
            expect(title, isNot(contains('{')), reason: reason);
            expect(title, isNot(source), reason: '$reason is English');
            if (label != null && source.contains(label)) {
              expect(title, contains(label), reason: reason);
            }
          }
        }
      }
    });

    test('English and Polish read as written', () {
      const en = NotificationCopy(AppLocalizations(Locale('en')));
      const pl = NotificationCopy(AppLocalizations(Locale('pl')));
      final post = _row(
        NotificationType.pagePostPublished,
        label: 'New post from a Page you follow: Pracownia Glina',
        preview: 'Nowe kubki już w pracowni',
      );
      expect(en.title(post), 'Pracownia Glina published a post');
      // Present tense, like every other row: the past is gendered in Polish
      // and a Page's name is its owner's name.
      expect(pl.title(post), 'Pracownia Glina dodaje post');
      expect(pl.body(post), 'Nowe kubki już w pracowni');
      expect(pl.body(_row(NotificationType.pagePostPublished)), isNull);
      expect(
        pl.body(_row(NotificationType.pagePostPublished, preview: '   ')),
        isNull,
      );
      // A comment's words never reach a row: only a Page post has a body.
      expect(
        pl.body(_row(NotificationType.pagePostComment, preview: 'secret')),
        isNull,
      );

      // An unlocked achievement is named in the reader's language from the
      // catalogue id, not by the English title the row stores.
      final award = _row(
        NotificationType.achievementUnlocked,
        actor: 'YO Voice',
        label: 'First Word',
        targetId: 'messages_1',
      );
      expect(pl.title(award), 'Odblokowano osiągnięcie: Pierwsze słowo');
      expect(en.title(award), startsWith('Achievement unlocked: '));
      // An id this build does not know keeps the server's label.
      expect(
        pl.title(
          _row(
            NotificationType.achievementUnlocked,
            label: 'Future Award',
            targetId: 'future_9',
          ),
        ),
        'Odblokowano osiągnięcie: Future Award',
      );
      expect(
        pl.title(_row(NotificationType.achievementUnlocked)),
        'Odblokowano osiągnięcie',
      );
      // A row without a name still names somebody.
      expect(
        pl.title(_row(NotificationType.follow, actor: '  ')),
        'Użytkownik YO Voice zaczyna Cię obserwować',
      );
      // Server-authored text is shown as written.
      expect(
        pl.title(_row(NotificationType.system, label: 'Planned maintenance')),
        'Planned maintenance',
      );
      expect(pl.title(_row(NotificationType.system)), 'YO Voice');
    });
  });

  group('the Following group fits in every language', () {
    for (final language in selectableAppLanguages) {
      testWidgets('${language.localeKey}: 320 px at 200 % text', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final firestore = FakeFirebaseFirestore();
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'fit-owner'),
        );
        await firestore.collection('users').doc('fit-owner').set({
          'uid': 'fit-owner',
          'notificationPreferences': <String, bool>{},
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            locale: language.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
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

        final copy = AppLocalizations(language.locale!);
        expect(
          find.text(
            copy.contextualText(
              'notifyFollow.groupFollowing',
              'Following',
              'Obserwowane',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            copy.text('LIVE from people you follow', 'LIVE obserwowanych'),
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            copy.text(
              'New posts from Pages you follow',
              'Nowe posty obserwowanych stron',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            copy.text(
              'At most one notification a day from each Page',
              'Najwyżej jedno powiadomienie dziennie od jednej strony',
            ),
          ),
          findsOneWidget,
        );
        // A RenderFlex overflow is reported as a FlutterError.
        expect(tester.takeException(), isNull);
      });
    }
  });
}
