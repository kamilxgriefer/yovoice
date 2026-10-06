import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_server_page.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_event.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_session_controller.dart';
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
  // Channel-list group headings (capitals): the language's own word is the
  // English one, or the loanword it uses.
  'de|ORGANISATION',
  'de|START',
  'de|PODCAST',
  'de|COMMUNITY',
  'de|TEAM',
  'es|PODCAST',
  'pt|PODCAST',
  'pt_BR|PODCAST',
  'fr|ORGANISATION',
  'fr|PODCAST',
  'it|PODCAST',
  'it|TEAM',
  'nl|START',
  'nl|PODCAST',
  'nl|COMMUNITY',
  'nl|TEAM',
  'ro|TEXT',
  'ro|START',
  'ro|PODCAST',
  'tr|PODCAST',
  'el|PODCAST',
  'hu|PODCAST',
  'cs|START',
  'cs|PODCAST',
  'sk|PODCAST',
  'hr|PODCAST',
  'sv|TEXT',
  'sv|ORGANISATION',
  'sv|START',
  'sv|PODCAST',
  'sv|TEAM',
  'da|START',
  'da|PODCAST',
  'da|TEAM',
  'nb|START',
  'nb|PODCAST',
  'nb|TEAM',
  'fi|PODCAST',
  'id|PODCAST',
  'vi|PODCAST',
};

/// Languages without capital letters: a group heading there is the word
/// itself.
const _caselessLocales = <String>{
  'zh_CN',
  'zh_TW',
  'ja',
  'ko',
  'ar',
  'th',
  'he',
  'fa',
  'hi',
  'bn',
  'ur',
};

/// The channel list's group headings, as `serverShellChannelGroup` keys them.
const _groupHeadingKeys = <String>[
  'TEXT',
  'VOICE',
  'ORGANISATION',
  'START',
  'CONVERSATIONS',
  'PODCAST',
  'COMMUNITY',
  'HOME',
  'TOGETHER',
  'COMPANY',
  'TEAM',
];

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
      expect(keys, hasLength(11), reason: '$keys');
      expect(serverPageTranslationKeys, containsAll(keys));
    });

    test('every string of the family check-in panel has a catalog entry', () {
      // The family page embeds the panel; its relative times are templates
      // over the catalog's own `{count}m ago` keys, not one key per number.
      final source = File(
        'lib/features/clubs/presentation/widgets/family_check_in_panel.dart',
      ).readAsStringSync();
      final keys = _catalogKeys(source);
      expect(keys, hasLength(16), reason: '$keys');
      expect(appTranslationKeys, containsAll(keys.toSet()));
      expect(source, isNot(contains(r"'${elapsed")));
    });

    test('the states of the server route have a catalog entry', () {
      final keys = _catalogKeys(
        File(
          'lib/features/servers/presentation/screens/'
          'server_workspace_screen.dart',
        ).readAsStringSync(),
      );
      expect(keys, isNotEmpty);
      expect(appTranslationKeys, containsAll(keys.toSet()));
    });

    test('what the family page embeds of the album has a catalog entry', () {
      // The header action, the empty and error states, the saved line, a
      // memory tile and its delete confirmation. The composer sheet and its
      // failure sentences belong to the album's own flow and are not yet
      // catalogued.
      const embedded = [
        'Family memories',
        'A private album where every photo keeps the voice behind it.',
        'Open album',
        'Add memory',
        'No Family Memories yet',
        'Add a photo and record the voice that belongs with it.',
        'The private album could not be loaded.',
        'Your Family Memory is in the album.',
        'Load photo',
        'Delete memory',
        'Delete this memory?',
        'The photo and voice recording will be removed from the family album.',
        'Keep',
        'Delete',
        'Pause',
        'Listen',
        'Try again',
      ];
      final source = _catalogKeys(
        File(
          'lib/features/servers/presentation/widgets/'
          'server_family_memory_album.dart',
        ).readAsStringSync(),
      );
      expect(source, containsAll(embedded));
      expect(appTranslationKeys, containsAll(embedded));
    });

    test('a word that means something else elsewhere has its own key', () {
      // "Dismiss" closes a failure line here (`Zamknij`); the moderation
      // centre uses the same English word for rejecting a report (`Odrzuć`).
      // The Servers word is therefore a context key, and the bare English
      // phrase is not catalogued by this module.
      expect(serverPageTranslationKeys, contains('serverPage.dismiss'));
      expect(serverPageTranslationKeys, isNot(contains('Dismiss')));
      expect(AppLocalizations(const Locale('pl')).serverDismiss, 'Zamknij');
      expect(AppLocalizations(const Locale('en')).serverDismiss, 'Dismiss');
      expect(AppLocalizations(const Locale('de')).serverDismiss, 'Schließen');
    });

    test('a group heading is in capitals the way its language writes them', () {
      for (final localeKey in translatedLocaleKeys) {
        if (_caselessLocales.contains(localeKey)) continue;
        final entries = serverPageTranslations[localeKey]!;
        for (final key in _groupHeadingKeys) {
          final value = entries[key]!;
          expect(
            value,
            serverPageOverline(Locale(localeKey.split('_').first), value),
            reason: '$localeKey: "$key" -> "$value" is not all capitals',
          );
        }
      }
      // Turkish keeps the dot, Greek drops the tonos.
      expect(serverPageTranslations['tr']!['TEXT'], 'METİN');
      expect(serverPageTranslations['tr']!['TOGETHER'], 'BİRLİKTE');
      expect(serverPageTranslations['el']!['START'], 'ΕΝΑΡΞΗ');
    });

    test('the older Servers copy on and beside the page resolves in every '
        'locale', () {
      final english = AppLocalizations(const Locale('en'));
      for (final localeKey in translatedLocaleKeys) {
        final copy = _copy(localeKey);
        final pairs = <String, (String, String)>{
          // The session card and the lounge joined in place.
          'serverHeldBody': (copy.serverHeldBody, english.serverHeldBody),
          'serverJoinFailed': (copy.serverJoinFailed, english.serverJoinFailed),
          'serverConnectionLost': (
            copy.serverConnectionLost,
            english.serverConnectionLost,
          ),
          'serverOtherVoiceActive': (
            copy.serverOtherVoiceActive,
            english.serverOtherVoiceActive,
          ),
          'serverDismiss': (copy.serverDismiss, english.serverDismiss),
          'serverGoLive': (copy.serverGoLive, english.serverGoLive),
          'serverReconnecting': (
            copy.serverReconnecting,
            english.serverReconnecting,
          ),
          for (final reason in ServerSessionReauthorization.values)
            'serverReconnectingFor($reason)': (
              copy.serverReconnectingFor(reason),
              english.serverReconnectingFor(reason),
            ),
          'serverHeadphonesOn': (
            copy.serverHeadphonesOn,
            english.serverHeadphonesOn,
          ),
          'serverHeadphonesOff': (
            copy.serverHeadphonesOff,
            english.serverHeadphonesOff,
          ),
          'serverLeaveConversation': (
            copy.serverLeaveConversation,
            english.serverLeaveConversation,
          ),
          'serverListenOnly': (copy.serverListenOnly, english.serverListenOnly),
          'serverSpeaking': (copy.serverSpeaking, english.serverSpeaking),
          // The family's board.
          'serverFamilyHeroTitle': (
            copy.serverFamilyHeroTitle,
            english.serverFamilyHeroTitle,
          ),
          'serverFamilyHeroBody': (
            copy.serverFamilyHeroBody,
            english.serverFamilyHeroBody,
          ),
          'serverFamilyPlans': (
            copy.serverFamilyPlans,
            english.serverFamilyPlans,
          ),
          'serverFamilyPlansBody': (
            copy.serverFamilyPlansBody,
            english.serverFamilyPlansBody,
          ),
          'serverFamilyMemories': (
            copy.serverFamilyMemories,
            english.serverFamilyMemories,
          ),
          'serverFamilyMemoriesBody': (
            copy.serverFamilyMemoriesBody,
            english.serverFamilyMemoriesBody,
          ),
          'serverFamilyMemoriesPlay': (
            copy.serverFamilyMemoriesPlay,
            english.serverFamilyMemoriesPlay,
          ),
          'serverFamilyShopping': (
            copy.serverFamilyShopping,
            english.serverFamilyShopping,
          ),
          'serverFamilyShoppingBody': (
            copy.serverFamilyShoppingBody,
            english.serverFamilyShoppingBody,
          ),
          'serverOpenCalendar': (
            copy.serverOpenCalendar,
            english.serverOpenCalendar,
          ),
          'serverOpenSharedList': (
            copy.serverOpenSharedList,
            english.serverOpenSharedList,
          ),
          // Failure lines, the invitation card.
          'serverActionDenied': (
            copy.serverActionDenied,
            english.serverActionDenied,
          ),
          'serverActionUnavailable': (
            copy.serverActionUnavailable,
            english.serverActionUnavailable,
          ),
          'serverInviteRefused': (
            copy.serverInviteRefused,
            english.serverInviteRefused,
          ),
          'serverInviteIntroTitle': (
            copy.serverInviteIntroTitle,
            english.serverInviteIntroTitle,
          ),
          'serverInviteIntroBody': (
            copy.serverInviteIntroBody,
            english.serverInviteIntroBody,
          ),
          'serverInviteHeldBody': (
            copy.serverInviteHeldBody,
            english.serverInviteHeldBody,
          ),
          // The channel list: the column beside the page and the sheet
          // behind `Wszystkie kanały`.
          'serverFamilyHome': (copy.serverFamilyHome, english.serverFamilyHome),
          'serverSearchChannels': (
            copy.serverSearchChannels,
            english.serverSearchChannels,
          ),
          'serverSearchClear': (
            copy.serverSearchClear,
            english.serverSearchClear,
          ),
          'serverSearchNoChannels': (
            copy.serverSearchNoChannels,
            english.serverSearchNoChannels,
          ),
          'serverHandWaitingLabel': (
            copy.serverHandWaitingLabel(3),
            english.serverHandWaitingLabel(3),
          ),
          'serverMembers': (
            copy.serverMembers(128),
            english.serverMembers(128),
          ),
          'serverMembersInServer': (
            copy.serverMembersInServer(128),
            english.serverMembersInServer(128),
          ),
          for (final type in ServerType.values)
            for (final kind in ServerChannelKind.values)
              'serverShellChannelGroup($type, $kind)': (
                copy.serverShellChannelGroup(type, kind),
                english.serverShellChannelGroup(type, kind),
              ),
          for (final kind in ServerChannelKind.values)
            'serverChannelSpokenKind($kind)': (
              copy.serverChannelSpokenKind(kind, restricted: true),
              english.serverChannelSpokenKind(kind, restricted: true),
            ),
          'serverChannelRestricted': (
            copy.serverChannelRestricted,
            english.serverChannelRestricted,
          ),
          // The answer line of the next event.
          'serverEventMaybe': (copy.serverEventMaybe, english.serverEventMaybe),
          'serverEventDeclined': (
            copy.serverEventDeclined,
            english.serverEventDeclined,
          ),
          'serverPageYourAnswer': (
            copy.serverPageYourAnswer('·'),
            english.serverPageYourAnswer('·'),
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
        // Counts keep their number, and the counted phrase is the language's
        // own plural form (the shared member count), never "128 people".
        expect(copy.serverMembers(128), contains('128'), reason: localeKey);
        expect(copy.serverMembers(128), copy.peopleCount(128));
        expect(
          copy.serverMembersInServer(128),
          contains(copy.peopleCount(128)),
          reason: localeKey,
        );
        expect(
          copy.serverHandWaitingLabel(3),
          contains('3'),
          reason: localeKey,
        );
        expect(
          copy.serverPageYourAnswer('·'),
          contains('·'),
          reason: localeKey,
        );
      }
      // English and Polish read exactly as before.
      final polish = AppLocalizations(const Locale('pl'));
      expect(english.serverMembers(1), '1 person');
      expect(english.serverMembers(12), '12 people');
      expect(english.serverMembersInServer(12), '12 people in the server');
      expect(polish.serverMembersInServer(12), '12 osób w serwerze');
      expect(polish.serverMembersInServer(3), '3 osoby w serwerze');
      expect(english.serverHandWaitingLabel(2), '2 waiting to speak');
      expect(polish.serverHandWaitingLabel(2), 'Czekające prośby o głos: 2');
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

  group('nothing the page draws is left in English', () {
    // Every Text of a state, rendered in English and in another language:
    // a string that is the same in both and carries a Latin letter is either
    // fixture data (a name, a title) or a phrase without a catalog entry.
    Future<Set<String>> texts(
      WidgetTester tester,
      Widget Function() build,
      Locale locale,
      Size size,
    ) async {
      await pumpServers(tester, build(), locale: locale, size: size);
      expect(tester.takeException(), isNull, reason: '$locale');
      return {
        for (final text in tester.widgetList<Text>(find.byType(Text)))
          if (text.data != null) text.data!,
      };
    }

    Set<String> data(TestServerRepository repository) => {
      for (final server in repository.servers) ...[
        server.name,
        server.description,
        server.initial,
      ],
      for (final channel in repository.channels) channel.name,
      for (final event in repository.events) event.title,
    };

    final latin = RegExp('[A-Za-z]');
    final states =
        <String, (TestServerRepository Function(), Size, bool justCreated)>{
          'community owner, next event': (
            () => pageRepository(
              ServerType.community,
              events: [
                pageEvent(
                  ServerType.community,
                  id: 'e1',
                  title: 'Wieczór pytań',
                  startsAt: pageDay(1, 20),
                ),
              ],
            ),
            const Size(390, 1800),
            false,
          ),
          'community member live, tablet with the channel column': (
            () => pageRepository(
              ServerType.community,
              role: ServerMemberRole.member,
              live: pageLive,
            ),
            const Size(768, 1400),
            false,
          ),
          'friends': (
            () => pageRepository(ServerType.friends),
            const Size(390, 1800),
            false,
          ),
          'family with its Dom board and check-ins': (
            () => pageRepository(ServerType.family),
            const Size(390, 2600),
            false,
          ),
          'family, tablet with the channel column': (
            () => pageRepository(ServerType.family),
            const Size(768, 2000),
            false,
          ),
          'podcast with a next episode': (
            () =>
                pageRepository(
                    ServerType.podcast,
                    role: ServerMemberRole.member,
                    events: [
                      pageEvent(
                        ServerType.podcast,
                        id: 'p1',
                        title: 'Rozmowa o nocnych pociągach',
                        // Tomorrow, so the answer line is on screen at any hour.
                        startsAt: pageDay(1, 23),
                      ),
                    ],
                  )
                  ..eventResponses['p1'] = const ServerEventAttendance(
                    response: ServerEventResponse.maybe,
                    reminderRequested: true,
                  ),
            const Size(390, 1800),
            false,
          ),
          'company, tablet with the channel column': (
            () => pageRepository(ServerType.company),
            const Size(768, 1400),
            false,
          ),
          'a server that was just created': (
            () => pageRepository(ServerType.friends),
            const Size(390, 1800),
            true,
          ),
          'a held server': (
            () => pageRepository(ServerType.friends, held: true),
            const Size(390, 1800),
            false,
          ),
          'before joining a public server': (
            () => pageRepository(ServerType.community)..myRole = null,
            const Size(390, 844),
            false,
          ),
          'a server nobody may open': (
            () => pageRepository(ServerType.friends)..myRole = null,
            const Size(390, 844),
            false,
          ),
        };
    for (final entry in states.entries) {
      testWidgets(entry.key, (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final (repository, size, justCreated) = entry.value;
        Widget build() => pageWorkspace(repository(), justCreated: justCreated);
        final english = await texts(tester, build, const Locale('en'), size);
        expect(english, isNotEmpty);
        for (final locale in const [Locale('ja'), Locale('tr')]) {
          final localized = await texts(tester, build, locale, size);
          final fixture = data(repository());
          final leftovers = localized
              .intersection(english)
              .where(
                (text) =>
                    latin.hasMatch(text) &&
                    !fixture.contains(text) &&
                    // `Budujemy bazę · Scena LIVE` style lines join data.
                    !fixture.any(
                      (value) => value.length > 1 && text.contains(value),
                    ) &&
                    !_naturallyUnchangedPairs.contains(
                      '${locale.languageCode}|$text',
                    ),
              )
              .toList();
          expect(leftovers, isEmpty, reason: '$locale: ${entry.key}');
        }
      });
    }
  });

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
