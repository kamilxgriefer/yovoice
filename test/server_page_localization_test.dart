import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_server_page.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/server_localized_copy.dart';
import 'package:yovoice/features/servers/presentation/server_page_copy.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_home_page.dart';

import 'server_page_support.dart';
import 'server_test_support.dart';

/// The server page's copy in all 41 translated locales (ADR-240).
///
/// `app_translation_catalog.dart` merges this module with
/// `serverPageTranslations[locale]!`, so a missing locale is a null-check
/// crash on the first catalog read in every locale, not an English fallback.
/// A dropped placeholder is a crash in that locale, and an English value is a
/// silent fallback; both are pinned here per key.
final _placeholderPattern = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');

List<String> _placeholders(String value) =>
    _placeholderPattern.allMatches(value).map((m) => m.group(0)!).toList()
      ..sort();

/// A `serverPage.*` context key carries no placeholders of its own.
String _placeholderSource(String key) =>
    key.startsWith('serverPage.') ? '' : key;

/// Values that are legitimately the same as their English source: loanwords
/// the language itself uses (`Chat`, `Community`, `LIVE`, `Events`) and
/// words that are spelled alike (`Public`, `Calendar`, `Servers`).
const _naturallyUnchangedPairs = <String>{
  'de|Community',
  'de|Chat',
  'de|Events',
  'de|LIVE',
  'es|Chat',
  'pt|Chat',
  'pt_BR|Chat',
  'fr|Public',
  'fr|Chat',
  'it|Chat',
  'nl|Servers',
  'nl|Community',
  'nl|Chat',
  'nl|LIVE',
  'ro|Public',
  'ro|Chat',
  'ro|Calendar',
  'cs|Chat',
  'sk|Chat',
  'hr|Chat',
  'sv|LIVE',
  'da|Chat',
  'da|LIVE',
  'nb|Chat',
};

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
    '\\b(?:text|template|contextualText)\\(\\s*$literals,',
    multiLine: true,
  );
  return [
    for (final match in call.allMatches(source))
      _joinedLiteral(match.group(1)!),
  ];
}

AppLocalizations _copy(String localeKey) {
  final parts = localeKey.split('_');
  return AppLocalizations(
    parts.length == 2 ? Locale(parts[0], parts[1]) : Locale(parts[0]),
  );
}

void main() {
  final translatedLocaleKeys = _translatedLocaleKeys();

  group('server page catalog', () {
    test('covers exactly the 41 translated locales', () {
      expect(AppLocalizations.supportedLocales, hasLength(43));
      expect(translatedLocaleKeys, hasLength(41));
      expect(serverPageTranslations.keys.toSet(), translatedLocaleKeys);
    });

    test('keys are unique', () {
      expect(
        serverPageTranslationKeys.toSet(),
        hasLength(serverPageTranslationKeys.length),
        reason: 'duplicate key in serverPageTranslationKeys',
      );
    });

    test('every locale is complete, non-empty and keeps placeholders', () {
      final expected = serverPageTranslationKeys.toSet();
      for (final localeKey in translatedLocaleKeys) {
        final entries = serverPageTranslations[localeKey]!;
        expect(entries.keys.toSet(), expected, reason: localeKey);
        for (final key in serverPageTranslationKeys) {
          final value = entries[key]!;
          expect(value.trim(), isNotEmpty, reason: '$localeKey: $key');
          expect(value, value.trim(), reason: '$localeKey: $key');
          expect(
            _placeholders(value),
            _placeholders(_placeholderSource(key)),
            reason: '$localeKey: placeholder drift on "$key": "$value"',
          );
          if (_naturallyUnchangedPairs.contains('$localeKey|$key')) {
            expect(value, key, reason: '$localeKey: stale exemption "$key"');
            continue;
          }
          expect(
            value,
            isNot(key),
            reason: '$localeKey: English fallback shipped for "$key"',
          );
        }
      }
    });

    test('the merged app catalog serves these entries unchanged', () {
      expect(appTranslationKeys, containsAll(serverPageTranslationKeys));
      for (final localeKey in translatedLocaleKeys) {
        for (final key in serverPageTranslationKeys) {
          expect(
            translatedPhrase(localeKey, key),
            serverPageTranslations[localeKey]![key],
            reason:
                '$localeKey: "$key" is overridden by another catalog module',
          );
        }
      }
    });

    test('every string the page adds has a catalog entry', () {
      final keys = _catalogKeys(
        File(
          'lib/features/servers/presentation/server_page_copy.dart',
        ).readAsStringSync(),
      );
      expect(keys, hasLength(10), reason: '$keys');
      expect(serverPageTranslationKeys, containsAll(keys));
    });

    test('the Servers phrases the page shows resolve in every locale', () {
      for (final localeKey in translatedLocaleKeys) {
        final copy = _copy(localeKey);
        final english = AppLocalizations(const Locale('en'));
        // The same getters the page calls, compared with their English: a
        // phrase without a catalog entry would come back unchanged.
        final pairs = <String, (String, String)>{
          'serversTitle': (copy.serversTitle, english.serversTitle),
          'serverInvite': (copy.serverInvite, english.serverInvite),
          // `Share` is catalogued by the feed surface module.
          'serverShare': (copy.serverShare, english.serverShare),
          'serverChannels': (copy.serverChannels, english.serverChannels),
          'serverAddChannel': (copy.serverAddChannel, english.serverAddChannel),
          'serverSettings': (copy.serverSettings, english.serverSettings),
          'serverNoChannels': (copy.serverNoChannels, english.serverNoChannels),
          'serverNoChannelsBody': (
            copy.serverNoChannelsBody,
            english.serverNoChannelsBody,
          ),
          'serverNoUpcomingEvents': (
            copy.serverNoUpcomingEvents,
            english.serverNoUpcomingEvents,
          ),
          'serverWatch': (copy.serverWatch, english.serverWatch),
          'serverListen': (copy.serverListen, english.serverListen),
          'serverJoinConversation': (
            copy.serverJoinConversation,
            english.serverJoinConversation,
          ),
          'serverStartMeeting': (
            copy.serverStartMeeting,
            english.serverStartMeeting,
          ),
          'serverJoinMeeting': (
            copy.serverJoinMeeting,
            english.serverJoinMeeting,
          ),
          'serverStageWaiting': (
            copy.serverStageWaiting,
            english.serverStageWaiting,
          ),
          'serverStageJoinToWatch': (
            copy.serverStageJoinToWatch,
            english.serverStageJoinToWatch,
          ),
          'serverPodcastJoinToListen': (
            copy.serverPodcastJoinToListen,
            english.serverPodcastJoinToListen,
          ),
          'serverInConversation': (
            copy.serverInConversation,
            english.serverInConversation,
          ),
          'serverConnected': (copy.serverConnected, english.serverConnected),
          'serverNextEpisode': (
            copy.serverNextEpisode,
            english.serverNextEpisode,
          ),
          'serverEventReminder': (
            copy.serverEventReminder,
            english.serverEventReminder,
          ),
          'serverEventGoing': (copy.serverEventGoing, english.serverEventGoing),
          'serverQuestionsWaitingLabel': (
            copy.serverQuestionsWaitingLabel,
            english.serverQuestionsWaitingLabel,
          ),
          'serverLiveSince': (
            copy.serverLiveSince('21:04'),
            english.serverLiveSince('21:04'),
          ),
          'serverLiveSinceShort': (
            copy.serverLiveSinceShort('21:04'),
            english.serverLiveSinceShort('21:04'),
          ),
          'serverPageAllChannels': (
            copy.serverPageAllChannels(7),
            english.serverPageAllChannels(7),
          ),
          'serverPublicJoinAction': (
            copy.serverPublicJoinAction,
            english.serverPublicJoinAction,
          ),
          'serverPublicJoining': (
            copy.serverPublicJoining,
            english.serverPublicJoining,
          ),
          'serverPublicJoinTitle': (
            copy.serverPublicJoinTitle,
            english.serverPublicJoinTitle,
          ),
          'serverPublicJoinBody': (
            copy.serverPublicJoinBody,
            english.serverPublicJoinBody,
          ),
          'serverPageTitle': (copy.serverPageTitle, english.serverPageTitle),
          'serverPageNextLive': (
            copy.serverPageNextLive,
            english.serverPageNextLive,
          ),
          'serverPageGoLive': (copy.serverPageGoLive, english.serverPageGoLive),
          for (final kind in const [
            ServerChannelKind.stage,
            ServerChannelKind.meeting,
            ServerChannelKind.voice,
          ])
            'serverQuiet($kind)': (
              copy.serverQuiet(kind),
              english.serverQuiet(kind),
            ),
          for (final type in const [
            ServerType.friends,
            ServerType.podcast,
            ServerType.company,
          ])
            'serverKindSubtitle($type)': (
              copy.serverKindSubtitle(type, ServerPrivacy.private),
              english.serverKindSubtitle(type, ServerPrivacy.private),
            ),
          'serverKindSubtitle(private community)': (
            copy.serverKindSubtitle(
              ServerType.community,
              ServerPrivacy.private,
            ),
            english.serverKindSubtitle(
              ServerType.community,
              ServerPrivacy.private,
            ),
          ),
          'serverPrivacyTitle(inviteOnly)': (
            copy.serverPrivacyTitle(ServerPrivacy.inviteOnly),
            english.serverPrivacyTitle(ServerPrivacy.inviteOnly),
          ),
          'serverPrivacyTitle(private)': (
            copy.serverPrivacyTitle(ServerPrivacy.private),
            english.serverPrivacyTitle(ServerPrivacy.private),
          ),
        };
        for (final entry in pairs.entries) {
          final (localized, source) = entry.value;
          if (_naturallyUnchangedPairs.contains('$localeKey|$source')) {
            continue;
          }
          expect(
            localized,
            isNot(source),
            reason: '$localeKey: ${entry.key} fell back to "$source"',
          );
        }
        // The context keys never show their key.
        for (final value in [
          copy.serverPageVoice,
          copy.serverPagePublic,
          copy.serverPageToday,
          copy.serverPageTomorrow,
          copy.serverPageJoin,
        ]) {
          expect(value, isNot(startsWith('serverPage.')), reason: localeKey);
          expect(value.trim(), isNotEmpty, reason: localeKey);
        }
        expect(copy.serverPageAllChannels(7), contains('7'), reason: localeKey);
        expect(copy.serverLiveSince('21:04'), contains('21:04'));
      }
    });
  });

  test(
    'an overline is capitalised the way its own language writes capitals',
    () {
      // Turkish keeps the dot on its capital İ; Greek capitals drop the tonos.
      expect(
        serverPageOverline(const Locale('tr'), 'Sonraki bölüm'),
        'SONRAKİ BÖLÜM',
      );
      expect(
        serverPageOverline(const Locale('el'), 'Επόμενο επεισόδιο'),
        'ΕΠΟΜΕΝΟ ΕΠΕΙΣΟΔΙΟ',
      );
      expect(
        serverPageOverline(const Locale('pl'), 'Następny LIVE'),
        'NASTĘPNY LIVE',
      );
      expect(
        serverPageOverline(const Locale('de'), 'Nächste Folge'),
        'NÄCHSTE FOLGE',
      );
      // Every catalogued overline survives the trip in its own locale.
      for (final entry in serverPageTranslations.entries) {
        final locale = Locale(entry.key.split('_').first);
        for (final key in const ['Next LIVE', 'Next episode']) {
          final overline = serverPageOverline(locale, entry.value[key]!);
          expect(overline.trim(), isNotEmpty, reason: '${entry.key}: $key');
          expect(
            overline,
            overline.toUpperCase(),
            reason: '${entry.key}: a lower-case letter survived in "$overline"',
          );
        }
      }
    },
  );

  group('the page in another language', () {
    for (final (locale, heading, invite, all) in const [
      (Locale('de'), 'Unterhaltungen', 'Einladen', 'Alle Kanäle (7)'),
      (Locale('ja'), '会話', '招待', 'すべてのチャンネル（7）'),
      (Locale('ar'), 'المحادثات', 'دعوة', 'كل القنوات (7)'),
    ]) {
      testWidgets('renders its own copy in ${locale.languageCode} at 390 and '
          '200 percent text', (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final scale in [1.0, 2.0]) {
          await pumpServers(
            tester,
            pageWorkspace(
              pageRepository(
                ServerType.community,
                role: ServerMemberRole.owner,
                events: [
                  pageEvent(
                    ServerType.community,
                    id: 'e1',
                    title: 'Q&A',
                    startsAt: pageDay(1, 20),
                  ),
                ],
              ),
            ),
            locale: locale,
            textScale: scale,
          );
          expect(tester.takeException(), isNull, reason: '$locale ×$scale');
          expect(find.text(heading), findsOneWidget, reason: '$locale');
          expect(find.text(invite), findsOneWidget, reason: '$locale');
          expect(find.text(all), findsOneWidget, reason: '$locale');
          // Nothing the page itself says is left in English.
          for (final english in const [
            'Conversations',
            'Invite',
            'Share',
            'Go LIVE',
            'Next LIVE',
            'Voice',
            'Going',
            'tomorrow',
          ]) {
            expect(find.text(english), findsNothing, reason: '$locale');
          }
        }
      });
    }
  });
}
