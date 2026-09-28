import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_vip_likers.dart';
import 'package:yovoice/features/likers/data/models/likers_target.dart';
import 'package:yovoice/features/likers/presentation/likers_copy.dart';
import 'package:yovoice/features/likers/presentation/show_likers.dart';

import 'support/likers_fixtures.dart';

/// "See who liked" copy in all 41 translated locales (spec §5.7, ADR-230).
///
/// `app_translation_catalog.dart` merges this module with
/// `vipLikersTranslations[locale]!`, so a missing locale is a null-check crash
/// on the first catalog read in every locale, not an English fallback. A
/// dropped placeholder is a crash in that locale, and an English value is a
/// silent fallback; both are pinned here per key.
final _placeholderPattern = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');

List<String> _placeholders(String value) =>
    _placeholderPattern.allMatches(value).map((m) => m.group(0)!).toList()
      ..sort();

const _pluralCategories = <String>[
  'zero',
  'one',
  'two',
  'few',
  'many',
  'other',
];

const _countStems = <String>[
  '{count} people liked this Moment',
  '{count} people liked this Yeel',
  '{count} people liked this comment',
  '{count} people reacted to this message',
];

/// The key a value's placeholders are compared with: a plural entry keeps the
/// placeholders of its stem, a `likers.*` context key has none.
String _placeholderSource(String key) {
  if (key.startsWith('likers.')) return '';
  final dot = key.lastIndexOf('.');
  if (dot > 0 && _pluralCategories.contains(key.substring(dot + 1))) {
    return key.substring(0, dot);
  }
  return key;
}

/// Values that are legitimately the same as their English source: a
/// placeholder-only template carries no prose, Italian and Dutch write
/// "Privacy" as English does, and German uses the loanword "Likes".
const _naturallyUnchanged = <String>{'{emoji}: {count}'};
const _naturallyUnchangedPairs = <String>{
  'it|Privacy',
  'nl|Privacy',
  'de|Likes · {count}',
};

/// Every file that renders "See who liked" copy only through the catalog.
const _likersSources = <String>[
  'lib/features/likers/presentation/likers_copy.dart',
  'lib/features/likers/presentation/show_likers.dart',
  'lib/features/likers/presentation/likers_launcher.dart',
  'lib/features/likers/presentation/comment_likes_controller.dart',
  'lib/features/likers/presentation/widgets/comment_like_controls.dart',
  'lib/features/likers/presentation/widgets/likers_entry_button.dart',
  'lib/features/likers/presentation/widgets/likers_list_view.dart',
  'lib/features/likers/presentation/widgets/likers_upsell_sheet.dart',
  'lib/shared/widgets/identity/yo_vip_rosette.dart',
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
/// and every `stem:` of a `pluralTemplate(` call in [source].
List<String> _catalogKeys(String source) {
  const literals = r'''((?:(?:'(?:\\.|[^'])*'|"(?:\\.|[^"])*")\s*)+)''';
  final call = RegExp(
    '\\.(?:text|template|contextualText)\\(\\s*$literals,',
    multiLine: true,
  );
  final stem = RegExp('\\bstem:\\s*$literals,', multiLine: true);
  return <String>[
    for (final match in call.allMatches(source))
      _joinedLiteral(match.group(1)!),
    for (final match in stem.allMatches(source))
      _joinedLiteral(match.group(1)!),
  ];
}

void main() {
  final translatedLocaleKeys = _translatedLocaleKeys();

  group('vip likers catalog', () {
    test('covers exactly the 41 translated locales', () {
      expect(AppLocalizations.supportedLocales, hasLength(43));
      expect(translatedLocaleKeys, hasLength(41));
      expect(vipLikersTranslations.keys.toSet(), translatedLocaleKeys);
    });

    test('keys are unique and every count stem has all six categories', () {
      expect(
        vipLikersTranslationKeys.toSet(),
        hasLength(vipLikersTranslationKeys.length),
        reason: 'duplicate key in vipLikersTranslationKeys',
      );
      for (final stem in _countStems) {
        for (final category in _pluralCategories) {
          expect(vipLikersTranslationKeys, contains('$stem.$category'));
        }
      }
    });

    test('every locale is complete, non-empty and keeps placeholders', () {
      final expected = vipLikersTranslationKeys.toSet();
      for (final localeKey in translatedLocaleKeys) {
        final entries = vipLikersTranslations[localeKey]!;
        expect(entries.keys.toSet(), expected, reason: localeKey);
        for (final key in vipLikersTranslationKeys) {
          final value = entries[key]!;
          expect(value.trim(), isNotEmpty, reason: '$localeKey: $key');
          expect(
            _placeholders(value),
            _placeholders(_placeholderSource(key)),
            reason: '$localeKey: placeholder drift on "$key": "$value"',
          );
          if (_naturallyUnchanged.contains(key) ||
              _naturallyUnchangedPairs.contains('$localeKey|$key')) {
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
      expect(appTranslationKeys, containsAll(vipLikersTranslationKeys));
      for (final localeKey in translatedLocaleKeys) {
        for (final key in vipLikersTranslationKeys) {
          expect(
            translatedPhrase(localeKey, key),
            vipLikersTranslations[localeKey]![key],
            reason:
                '$localeKey: "$key" is overridden by another catalog module',
          );
        }
      }
    });

    test('every likers string in code has a catalog entry', () {
      final missing = <String>[];
      for (final path in _likersSources) {
        for (final key in _catalogKeys(File(path).readAsStringSync())) {
          if (!appTranslationKeys.contains(key) && !_countStems.contains(key)) {
            missing.add('$path: "$key"');
          }
        }
      }
      expect(missing, isEmpty, reason: missing.join('\n'));
      expect(
        _catalogKeys(
          File(_likersSources.first).readAsStringSync(),
        ).where(_countStems.contains).toSet(),
        _countStems.toSet(),
        reason: 'LikersCopy must use exactly the catalogued count stems',
      );
    });

    test('the Premium and Settings strings in code are the catalog keys', () {
      const expected = <String, List<String>>{
        'lib/features/premium/presentation/premium_localized_copy.dart': [
          'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost',
          'See who liked',
          'See who liked Voice Moments, Yeels, comments and Server messages',
        ],
        'lib/features/premium/presentation/widgets/premium_feature_gate.dart': [
          'See who liked',
          'With Premium you can see the people who liked a Voice Moment, a Yeel or a comment, or reacted to a Server message. Like counts stay visible to everyone.',
          'See who liked is included with Premium',
        ],
        'lib/features/settings/presentation/screens/settings_screen.dart': [
          'Privacy',
          'Hide my likes',
          "You won't appear in YO Voice's lists of who liked or reacted. Counts don't change. Server members still receive your reactions in channels you share.",
          "Couldn't update this setting. Try again.",
        ],
      };
      for (final entry in expected.entries) {
        final keys = _catalogKeys(File(entry.key).readAsStringSync());
        for (final key in entry.value) {
          expect(keys, contains(key), reason: '${entry.key} no longer uses');
          expect(vipLikersTranslationKeys, contains(key));
        }
      }
    });
  });

  group('count line plurals', () {
    const counts = <int>[0, 1, 2, 3, 5, 11, 21, 22, 25, 101, 102];
    const targets = <LikersTarget>[
      VoiceMomentLikersTarget('m1'),
      ReelLikersTarget('r1'),
      VoiceMomentCommentLikersTarget('m1', 'c1'),
      ServerMessageReactorsTarget('s1', 'ch1', 'x1'),
    ];
    // "person" is also Swedish, Danish and Norwegian, so it is not a signal.
    final english = RegExp(r'\b(people|liked|reacted)\b');

    test('English and Polish keep the reviewed forms', () {
      const en = LikersCopy(AppLocalizations(Locale('en')));
      const pl = LikersCopy(AppLocalizations(Locale('pl')));
      const moment = VoiceMomentLikersTarget('m1');
      expect(en.countLine(moment, 1), '1 person liked this Moment');
      expect(en.countLine(moment, 24), '24 people liked this Moment');
      expect(pl.countLine(moment, 1), '1 osoba polubiła ten Moment');
      expect(pl.countLine(moment, 24), '24 osoby polubiły ten Moment');
      expect(pl.countLine(moment, 12), '12 osób polubiło ten Moment');
      expect(pl.countLine(moment, 25), '25 osób polubiło ten Moment');
      expect(
        pl.countLine(targets.last, 3),
        '3 osoby zareagowały na tę wiadomość',
      );
    });

    test('every locale names the count and never falls back to English', () {
      for (final localeKey in translatedLocaleKeys) {
        final language = selectableAppLanguages.firstWhere(
          (language) => language.localeKey == localeKey,
        );
        final copy = LikersCopy(AppLocalizations(language.locale!));
        for (final target in targets) {
          for (final count in counts) {
            final line = copy.countLine(target, count);
            expect(line, contains('$count'), reason: '$localeKey: $line');
            expect(line, isNot(contains('{count}')), reason: localeKey);
            expect(
              line,
              isNot(matches(english)),
              reason: '$localeKey fell back to English: $line',
            );
          }
        }
      }
    });

    test('languages with several plural forms decline them', () {
      const threeForms = <String, List<int>>{
        'ru': [1, 2, 5],
        'uk': [1, 2, 5],
        'cs': [1, 2, 5],
        'sk': [1, 2, 5],
        'hr': [1, 2, 5],
        'sr': [1, 2, 5],
        'lt': [1, 2, 10],
        'lv': [1, 2, 10],
        'ro': [1, 2, 20],
      };
      for (final entry in threeForms.entries) {
        final language = selectableAppLanguages.firstWhere(
          (language) => language.localeKey == entry.key,
        );
        final copy = LikersCopy(AppLocalizations(language.locale!));
        for (final target in targets) {
          expect(
            entry.value
                .map((count) => copy.countLine(target, count))
                .map((line) => line.replaceAll(RegExp(r'\d+'), '#'))
                .toSet(),
            hasLength(3),
            reason: '${entry.key} must decline three forms for $target',
          );
        }
      }
      const arabic = LikersCopy(AppLocalizations(Locale('ar')));
      expect(
        <int>[1, 2, 3, 11]
            .map((count) => arabic.countLine(targets.first, count))
            .map((line) => line.replaceAll(RegExp(r'\d+'), '#'))
            .toSet(),
        hasLength(4),
      );
    });
  });

  group('resolved copy', () {
    test('context keys and templates localize outside English', () {
      const de = LikersCopy(AppLocalizations(Locale('de')));
      expect(de.title(const VoiceMomentLikersTarget('m1')), 'Likes');
      expect(
        de.title(const ServerMessageReactorsTarget('s1', 'ch1', 'x1')),
        'Reaktionen',
      );
      expect(de.tabAll, 'Alle');
      expect(de.you, 'Du');
      expect(de.likesCount(24), 'Likes · 24');
      expect(de.reactedRow('Ana', '🔥'), 'Ana, hat mit 🔥 reagiert');
      expect(de.upsellTitle, 'Likes ansehen — eine Premium-Funktion');
      expect(
        de.countLine(const VoiceMomentLikersTarget('m1'), 1),
        'Dieser Moment gefällt 1 Person',
      );

      const fr = LikersCopy(AppLocalizations(Locale('fr')));
      expect(fr.tabLabel('👍', 3), '👍 : 3');
      expect(
        fr.likedByOpen('Ana, Bo', 4),
        'Aimé par Ana, Bo et 4 autres personnes. Voir qui a aimé.',
      );
    });
  });

  group('long translations lay out', () {
    // The longest and the right-to-left translations, on the narrowest phone
    // at 200 % text: a Flutter overflow is an exception the tester catches.
    const locales = <Locale>[
      Locale('ru'),
      Locale('fi'),
      Locale('el'),
      Locale('de'),
      Locale('ar'),
    ];
    const server = ServerMessageReactorsTarget('s1', 'ch1', 'x1');

    void narrow(WidgetTester tester) {
      tester.view.physicalSize = const Size(640, 1400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> openWith(
      WidgetTester tester,
      Locale locale,
      Future<void> Function(BuildContext context) open,
    ) async {
      await tester.pumpWidget(
        likersHost(
          Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  key: const ValueKey('open'),
                  onPressed: () => open(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          locale: locale,
          textScale: 2,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
    }

    for (final locale in locales) {
      testWidgets('list with reaction tabs in ${locale.languageCode}', (
        tester,
      ) async {
        narrow(tester);
        final script = ScriptedLikers([
          pageWire([
            likerWire('julia', 'Julia Nowak-Wiśniewska', reaction: '👍'),
            likerWire('marta', 'Marta', reaction: '❤️'),
          ]),
        ]);
        await openWith(
          tester,
          locale,
          (context) => showLikers(
            context,
            server,
            totalCount: 26,
            reactionCounts: const <String, int>{'👍': 14, '❤️': 12},
            access: FakeLikersAccess(true),
            service: script.service,
            viewerId: 'me',
            identityRepository: identityRepository(vip: {'marta'}),
          ),
        );
        expect(find.byKey(kLikersListSurface), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      for (final canBuy in const <bool>[false, true]) {
        testWidgets('upsell (${canBuy ? 'purchase' : 'not for sale'}) in '
            '${locale.languageCode}', (tester) async {
          narrow(tester);
          await openWith(
            tester,
            locale,
            (context) => showLikersUpsell(
              context,
              const VoiceMomentLikersTarget('m1'),
              totalCount: 24,
              canBuyPremium: () async => canBuy,
            ),
          );
          expect(find.byKey(kLikersUpsellSurface), findsOneWidget);
          final copy = LikersCopy(AppLocalizations(locale));
          expect(find.text(copy.upsellTitle), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
