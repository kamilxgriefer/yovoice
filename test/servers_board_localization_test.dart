import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_servers_board.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/presentation/screens/servers_screen.dart';
import 'package:yovoice/features/servers/presentation/server_localized_copy.dart';
import 'package:yovoice/features/servers/presentation/servers_board_copy.dart';
import 'package:yovoice/features/servers/presentation/widgets/servers_board.dart';

import 'server_test_support.dart';

/// The Servers board's copy in all 41 translated locales (ADR-239).
///
/// `app_translation_catalog.dart` merges this module with
/// `serversBoardTranslations[locale]!`, so a missing locale is a null-check
/// crash on the first catalog read in every locale, not an English fallback.
/// A dropped placeholder is a crash in that locale and an English value is a
/// silent fallback; both are pinned here per key. The last group renders the
/// board in every selectable locale on a phone and proves the short labels
/// fit their boxes.
final _placeholderPattern = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');

List<String> _placeholders(String value) =>
    _placeholderPattern.allMatches(value).map((m) => m.group(0)!).toList()
      ..sort();

/// `serversBoard.*` context keys carry no placeholders of their own.
String _placeholderSource(String key) =>
    key.startsWith('serversBoard.') ? '' : key;

/// Values that are legitimately the same as their English source: loanwords
/// ("Community" in German, Italian, Dutch and Swedish; "Servers" in Dutch)
/// and "person", which is also Swedish, Danish and Norwegian.
const _naturallyUnchangedPairs = <String>{
  'de|Community',
  'it|Community',
  'nl|Community',
  'sv|Community',
  'nl|Servers',
  'sv|{count} person',
  'da|{count} person',
  'nb|{count} person',
};

/// What each context key says in English, for the fallback check.
const _contextEnglish = <String, String>{
  'serversBoard.view': 'View',
  'serversBoard.live': 'live',
  'serversBoard.showAll': 'Show all',
  'serversBoard.showFewer': 'Show fewer',
  'serversBoard.paste': 'Paste',
};

/// "live" is the word itself in these languages.
const _liveLoanword = <String>{'de', 'nl', 'sv', 'da', 'fil'};

const _boardSources = <String>[
  'lib/features/servers/presentation/servers_board_copy.dart',
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
  return <String>[
    for (final match in call.allMatches(source))
      _joinedLiteral(match.group(1)!),
  ];
}

Server _server(
  String id,
  String name,
  ServerType type, {
  int members = 8,
  ServerPrivacy? privacy,
}) => Server(
  id: id,
  name: name,
  description: '',
  ownerId: id.startsWith('pub') ? 'someone' : 'owner',
  type: type,
  privacy:
      privacy ??
      (type == ServerType.family
          ? ServerPrivacy.inviteOnly
          : ServerPrivacy.private),
  memberCount: members,
  schemaVersion: 1,
  activationState: 'active',
  status: 'active',
);

TestServerRepository _repository({bool newcomer = false}) =>
    TestServerRepository()
      ..servers = newcomer
          ? const []
          : [
              _server(
                's',
                'Nocne Granie',
                ServerType.community,
                members: 128,
                privacy: ServerPrivacy.public,
              ),
              _server('p', 'Paczka z liceum', ServerType.friends, members: 12),
              _server('r', 'Rodzina Nowaków', ServerType.family, members: 6),
              _server('f', 'Studio Fala', ServerType.podcast, members: 42),
              _server('c', 'Biuro', ServerType.company, members: 1),
              _server('k', 'Klub książki', ServerType.community, members: 184),
              _server('z', 'Szósty', ServerType.friends, members: 3),
            ]
      ..publicServers = [
        _server(
          'pub-f',
          'Fotografia po godzinach',
          ServerType.community,
          members: 312,
          privacy: ServerPrivacy.public,
        ),
        _server(
          'pub-n',
          'Nocna audycja',
          ServerType.podcast,
          members: 26,
          privacy: ServerPrivacy.public,
        ),
      ]
      ..channels = [
        ServerChannel(
          id: 'stage',
          serverId: 's',
          name: 'Scena',
          kind: ServerChannelKind.stage,
          roomId: 'room',
          schemaVersion: 1,
          liveness: ServerChannelLiveness(
            isLive: true,
            startedAt: DateTime(2026, 10, 3, 21, 4),
          ),
        ),
      ];

Future<void> _pumpBoard(
  WidgetTester tester,
  Locale locale, {
  bool newcomer = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A fresh tree: the board keeps its repository for its lifetime.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: AppTheme.darkTheme,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: ServersScreen(
        isRootTab: true,
        repository: _repository(newcomer: newcomer),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Whether the one-line [Text] showing [label] was cut.
bool _elided(WidgetTester tester, String label) {
  final paragraphs = tester.renderObjectList<RenderParagraph>(
    find.descendant(of: find.text(label), matching: find.byType(RichText)),
  );
  return paragraphs.any((paragraph) => paragraph.didExceedMaxLines);
}

void main() {
  final translatedLocaleKeys = _translatedLocaleKeys();

  group('servers board catalog', () {
    test('covers exactly the 41 translated locales', () {
      expect(AppLocalizations.supportedLocales, hasLength(43));
      expect(translatedLocaleKeys, hasLength(41));
      expect(serversBoardTranslations.keys.toSet(), translatedLocaleKeys);
    });

    test('keys are unique', () {
      expect(
        serversBoardTranslationKeys.toSet(),
        hasLength(serversBoardTranslationKeys.length),
        reason: 'duplicate key in serversBoardTranslationKeys',
      );
    });

    test('every locale is complete, non-empty and keeps placeholders', () {
      final expected = serversBoardTranslationKeys.toSet();
      for (final localeKey in translatedLocaleKeys) {
        final entries = serversBoardTranslations[localeKey]!;
        expect(entries.keys.toSet(), expected, reason: localeKey);
        for (final key in serversBoardTranslationKeys) {
          final value = entries[key]!;
          expect(value.trim(), isNotEmpty, reason: '$localeKey: $key');
          expect(
            _placeholders(value),
            _placeholders(_placeholderSource(key)),
            reason: '$localeKey: placeholder drift on "$key": "$value"',
          );
          if (_naturallyUnchangedPairs.contains('$localeKey|$key')) continue;
          if (key == 'serversBoard.live' && _liveLoanword.contains(localeKey)) {
            continue;
          }
          expect(
            value,
            isNot(_contextEnglish[key] ?? key),
            reason: '$localeKey: English fallback shipped for "$key"',
          );
        }
      }
    });

    test('the merged app catalog serves these entries unchanged', () {
      expect(appTranslationKeys, containsAll(serversBoardTranslationKeys));
      for (final localeKey in translatedLocaleKeys) {
        for (final key in serversBoardTranslationKeys) {
          expect(
            translatedPhrase(localeKey, key),
            serversBoardTranslations[localeKey]![key],
            reason:
                '$localeKey: "$key" is overridden by another catalog module',
          );
        }
      }
    });

    test('every board string in code has a catalog entry', () {
      final missing = <String>[];
      for (final path in _boardSources) {
        final keys = _catalogKeys(File(path).readAsStringSync());
        expect(keys, isNotEmpty, reason: '$path: no copy found');
        for (final key in keys) {
          if (!appTranslationKeys.contains(key)) missing.add('$path: "$key"');
        }
      }
      expect(missing, isEmpty, reason: missing.join('\n'));
    });

    test('the Servers copy the board reuses resolves in every locale', () {
      for (final localeKey in translatedLocaleKeys) {
        final language = selectableAppLanguages.firstWhere(
          (language) => language.localeKey == localeKey,
        );
        final copy = AppLocalizations(language.locale!);
        final entries = serversBoardTranslations[localeKey]!;
        expect(copy.serversTitle, entries['Servers'], reason: localeKey);
        expect(copy.serverManage, entries['Manage server'], reason: localeKey);
        expect(
          copy.serverKindSubtitle(ServerType.community, ServerPrivacy.public),
          entries['Community'],
          reason: localeKey,
        );
        expect(
          copy.serverKindSubtitle(ServerType.community, ServerPrivacy.private),
          entries['Private community'],
          reason: localeKey,
        );
        expect(
          copy.serverKindSubtitle(ServerType.friends, ServerPrivacy.private),
          entries['Private server'],
          reason: localeKey,
        );
        expect(
          copy.serverKindSubtitle(ServerType.podcast, ServerPrivacy.public),
          entries['Podcast server'],
          reason: localeKey,
        );
        expect(
          copy.serverKindSubtitle(ServerType.company, ServerPrivacy.private),
          entries['Company space'],
          reason: localeKey,
        );
        expect(
          copy.serverKindSubtitle(ServerType.family, ServerPrivacy.inviteOnly),
          entries['Invite only'],
          reason: localeKey,
        );
        for (final count in const [1, 2, 5, 128]) {
          final line = copy.serverMembers(count);
          expect(line, contains('$count'), reason: '$localeKey: $line');
          expect(line, isNot(contains('{count}')), reason: localeKey);
          expect(
            line,
            isNot(matches(RegExp(r'\bpeople\b'))),
            reason: '$localeKey fell back to English: $line',
          );
        }
        // The phone workspace header's line is a whole template per locale:
        // the translated count is never dropped into an English sentence
        // ("12 Personen in the server").
        for (final count in const [1, 2, 5, 128]) {
          final line = copy.serverMembersInServer(count);
          expect(
            line,
            entries[count == 1
                    ? '{count} person in the server'
                    : '{count} people in the server']!
                .replaceAll('{count}', '$count'),
            reason: localeKey,
          );
          expect(
            line,
            isNot(contains('in the server')),
            reason: '$localeKey mixes English into the line: $line',
          );
        }
        expect(copy.serversBoardLive, entries['serversBoard.live']);
        expect(copy.serversBoardView, entries['serversBoard.view']);
      }
    });

    test('English and Polish keep the authored forms', () {
      const en = AppLocalizations(Locale('en'));
      const pl = AppLocalizations(Locale('pl'));
      expect(en.serversBoardYours, 'Your servers');
      expect(pl.serversBoardYours, 'Twoje serwery');
      expect(en.serversBoardPublic, 'Public servers');
      expect(pl.serversBoardPublic, 'Serwery publiczne');
      expect(en.serversBoardView, 'View');
      expect(pl.serversBoardView, 'Zobacz');
      expect(en.serversBoardLive, 'live');
      expect(pl.serversBoardLive, 'na żywo');
      expect(pl.serversBoardShowAll, 'Pokaż wszystkie');
      expect(pl.serversBoardJoinLink, 'Dołącz z linku');
      expect(pl.serversBoardCreate, 'Stwórz serwer');
      expect(pl.serversBoardSearch, 'Szukaj serwera');
      expect(en.serverMembersInServer(1), '1 person in the server');
      expect(en.serverMembersInServer(12), '12 people in the server');
      expect(pl.serverMembersInServer(1), '1 osoba w serwerze');
      expect(pl.serverMembersInServer(3), '3 osoby w serwerze');
      expect(pl.serverMembersInServer(12), '12 osób w serwerze');
    });
  });

  group('the board fits a phone in every selectable locale', () {
    for (final language in selectableAppLanguages) {
      final locale = language.locale!;
      testWidgets('${language.localeKey}: rows, cards, sheet and first run', (
        tester,
      ) async {
        await _pumpBoard(tester, locale);
        expect(tester.takeException(), isNull, reason: 'populated');
        final context = tester.element(find.byType(ServersScreen));
        final copy = AppLocalizations.of(context);

        // The lamp sits beside the name and the pill inside a 173 px card:
        // neither short label may be cut.
        expect(find.text(copy.serversBoardLive), findsOneWidget);
        expect(
          _elided(tester, copy.serversBoardLive),
          isFalse,
          reason: 'lamp "${copy.serversBoardLive}"',
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('server-public-pub-n')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(copy.serversBoardView), findsNWidgets(2));
        expect(
          _elided(tester, copy.serversBoardView),
          isFalse,
          reason: 'pill "${copy.serversBoardView}"',
        );
        expect(tester.takeException(), isNull, reason: 'cards');

        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('servers-add')),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const ValueKey('servers-add')));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 80));
        }
        expect(find.text(copy.serversBoardCreate), findsOneWidget);
        expect(find.text(copy.serversBoardJoinLink), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'sheet');
        await tester.tap(find.byKey(const ValueKey('servers-join-link')));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 80));
        }
        expect(find.text(copy.serversJoinLinkLabel), findsOneWidget);
        expect(find.text(copy.serversJoinLinkPaste), findsOneWidget);
        expect(find.text(copy.serversJoinLinkOpen), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'link sheet');

        await _pumpBoard(tester, locale, newcomer: true);
        expect(find.text(copy.serversBoardNewcomerTitle), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'first run');
      });

      testWidgets('${language.localeKey}: 200 % text does not overflow', (
        tester,
      ) async {
        await _pumpBoard(tester, locale, textScale: 2);
        expect(tester.takeException(), isNull, reason: 'populated');
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -1200),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'scrolled');
        await _pumpBoard(tester, locale, newcomer: true, textScale: 2);
        expect(tester.takeException(), isNull, reason: 'first run');
      });
    }
  });

  // Runs last on purpose: a loaded font stays loaded for the rest of this
  // file, and the groups above measure with the test font, which is wider
  // than Inter and therefore the stricter ruler for the short labels.
  group('a row never loses its member count (real Inter metrics)', () {
    setUpAll(() async {
      final inter = FontLoader('Inter')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('assets/fonts/InterVariable.ttf').readAsBytesSync(),
            ),
          ),
        );
      await inter.load();
    });

    // Inter draws Latin, Greek and Cyrillic (with their extended blocks —
    // Vietnamese lives in Latin Extended Additional). Any other script would
    // be measured with the test font's 1 em boxes, which says nothing about
    // the real line, so those locales are left to the capture frames.
    bool drawnByInter(String line) => line.runes.every(
      (rune) =>
          rune < 0x0530 ||
          (rune >= 0x1E00 && rune < 0x2000) ||
          (rune >= 0x2000 && rune < 0x2070),
    );

    for (final language in selectableAppLanguages) {
      final locale = language.locale!;
      testWidgets('${language.localeKey}: kind and count stay whole', (
        tester,
      ) async {
        await _pumpBoard(tester, locale);
        final rows = find.byType(ServerBoardRow);
        expect(rows, findsWidgets);
        // The kind and the count share one line and the count is at its
        // end, so a cut line loses exactly the number ("Только по
        // приглашению · Участн…" at one line).
        final lines = tester
            .renderObjectList<RenderParagraph>(
              find.descendant(of: rows, matching: find.byType(RichText)),
            )
            .where((paragraph) => paragraph.text.toPlainText().contains('·'))
            .toList();
        expect(
          lines,
          hasLength(ServersBoardMetrics.collapsedRows),
          reason: 'one line per visible row',
        );
        if (!lines.every((line) => drawnByInter(line.text.toPlainText()))) {
          return;
        }
        final cut = [
          for (final line in lines)
            if (line.didExceedMaxLines) line.text.toPlainText(),
        ];
        expect(cut, isEmpty, reason: '${language.localeKey}: cut $cut');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('pl and en: every row is the chosen 64 px frame', (
      tester,
    ) async {
      for (final locale in const [Locale('pl'), Locale('en')]) {
        await _pumpBoard(tester, locale);
        final rows = find.byType(ServerBoardRow);
        expect(rows, findsNWidgets(ServersBoardMetrics.collapsedRows));
        for (final element in rows.evaluate()) {
          expect(
            (element.renderObject! as RenderBox).size.height,
            ServersBoardMetrics.rowMinHeight,
            reason:
                '$locale: ${(element.widget as ServerBoardRow).server.name}',
          );
        }
      }
    });
  });
}
