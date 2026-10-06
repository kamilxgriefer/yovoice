import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_first_steps.dart';
import 'package:yovoice/features/home/data/first_steps.dart';
import 'package:yovoice/features/home/presentation/first_steps_copy.dart';

/// "Zacznij tutaj" copy (firstSteps A) in all 41 translated locales.
///
/// `app_translation_catalog.dart` merges this module with
/// `firstStepsTranslations[locale]!`, so a missing locale is a null-check
/// crash on the first catalog read in every locale, not an English fallback.
/// A dropped placeholder is caught by `AppLocalizations.template` (it then
/// shows English), and an English value is a silent fallback; both are pinned
/// here per key.
final _placeholderPattern = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');

List<String> _placeholders(String value) =>
    _placeholderPattern.allMatches(value).map((m) => m.group(0)!).toList()
      ..sort();

/// The key a value's placeholders are compared with: a `firstSteps.*` context
/// key has none.
String _placeholderSource(String key) =>
    key.startsWith('firstSteps.') ? '' : key;

/// The files that render first-steps copy only through the catalog.
const _sources = <String>[
  'lib/features/home/presentation/first_steps_copy.dart',
  'lib/features/home/presentation/widgets/shared/home_first_steps_card.dart',
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
    '\\.(?:text|template|contextualText)\\(\\s*$literals,',
    multiLine: true,
  );
  return <String>[
    for (final match in call.allMatches(source))
      _joinedLiteral(match.group(1)!),
  ];
}

void main() {
  final translatedLocaleKeys = _translatedLocaleKeys();

  group('first steps catalog', () {
    test('covers exactly the 41 translated locales', () {
      expect(AppLocalizations.supportedLocales, hasLength(43));
      expect(translatedLocaleKeys, hasLength(41));
      expect(firstStepsTranslations.keys.toSet(), translatedLocaleKeys);
    });

    test('keys are unique', () {
      expect(
        firstStepsTranslationKeys.toSet(),
        hasLength(firstStepsTranslationKeys.length),
        reason: 'duplicate key in firstStepsTranslationKeys',
      );
    });

    test('every locale is complete, non-empty and keeps placeholders', () {
      final expected = firstStepsTranslationKeys.toSet();
      for (final localeKey in translatedLocaleKeys) {
        final entries = firstStepsTranslations[localeKey]!;
        expect(entries.keys.toSet(), expected, reason: localeKey);
        for (final key in firstStepsTranslationKeys) {
          final value = entries[key]!;
          expect(value.trim(), isNotEmpty, reason: '$localeKey: $key');
          expect(
            _placeholders(value),
            _placeholders(_placeholderSource(key)),
            reason: '$localeKey: placeholder drift on "$key": "$value"',
          );
          expect(
            value,
            isNot(key),
            reason: '$localeKey: English fallback shipped for "$key"',
          );
          expect(
            value,
            isNot(contains('firstSteps.')),
            reason: '$localeKey: a context key leaked into "$key"',
          );
        }
      }
    });

    test('the merged app catalog serves these entries unchanged', () {
      expect(appTranslationKeys, containsAll(firstStepsTranslationKeys));
      for (final localeKey in translatedLocaleKeys) {
        for (final key in firstStepsTranslationKeys) {
          expect(
            translatedPhrase(localeKey, key),
            firstStepsTranslations[localeKey]![key],
            reason:
                '$localeKey: "$key" is overridden by another catalog module',
          );
        }
      }
    });

    test('every first-steps string in code has a catalog entry', () {
      final used = <String>{};
      final missing = <String>[];
      for (final path in _sources) {
        for (final key in _catalogKeys(File(path).readAsStringSync())) {
          used.add(key);
          if (!appTranslationKeys.contains(key)) missing.add('$path: "$key"');
        }
      }
      expect(missing, isEmpty, reason: missing.join('\n'));
      // And nothing in the module is dead: every key is a string the copy
      // helper really asks for.
      expect(
        firstStepsTranslationKeys.toSet().difference(used),
        isEmpty,
        reason: 'catalogued but not used by FirstStepsCopy',
      );
    });

    test('the three dead ends read their action from FirstStepsCopy', () {
      const users = <String>[
        'lib/features/servers/presentation/widgets/server_invite_sheet.dart',
        'lib/features/notifications/presentation/screens/notifications_screen.dart',
        'lib/features/friends/presentation/screens/friends_screen.dart',
      ];
      for (final path in users) {
        expect(
          File(path).readAsStringSync(),
          contains('FirstStepsCopy('),
          reason: path,
        );
      }
    });
  });

  group('resolved copy', () {
    FirstStepsCopy copyFor(Locale locale) =>
        FirstStepsCopy(AppLocalizations(locale));

    test('English and Polish are the authored strings', () {
      final en = copyFor(const Locale('en'));
      final pl = copyFor(const Locale('pl'));
      expect(en.title, 'Start here');
      expect(pl.title, 'Zacznij tutaj');
      expect(en.progress(1, 5), '1 of 5');
      expect(pl.progress(1, 5), '1 z 5');
      expect(pl.close, 'Zamknij');
      expect(pl.allDone, 'Gotowe. Znasz już YO Voice.');
      expect(pl.label(FirstStep.photo), 'Dodaj zdjęcie profilowe');
      expect(pl.label(FirstStep.friend), 'Dodaj pierwszego znajomego');
      expect(
        pl.label(FirstStep.server),
        'Dołącz do serwera albo stwórz własny',
      );
      expect(pl.label(FirstStep.voice), 'Nagraj pierwszy Głos');
      expect(pl.label(FirstStep.follow), 'Zaobserwuj stronę lub twórcę');
      expect(
        pl.hint(FirstStep.friend),
        'Wyszukaj po nazwie albo wyślij swój link',
      );
      expect(pl.hint(FirstStep.follow), 'Ich nowości zobaczysz w Treściach');
      expect(pl.shareServerLink, 'Udostępnij link do serwera');
      expect(pl.addFriends, 'Dodaj znajomych');
      expect(pl.findPagesToFollow, 'Znajdź strony do obserwowania');
      expect(pl.addFriend, 'Dodaj znajomego');
    });

    test('no selectable locale falls back to English', () {
      final en = copyFor(const Locale('en'));
      List<String> all(FirstStepsCopy copy) => <String>[
        copy.title,
        copy.progress(1, 5),
        copy.close,
        copy.stepDone,
        copy.allDone,
        for (final step in FirstStep.values) ...[
          copy.label(step),
          copy.hint(step),
        ],
        copy.shareServerLink,
        copy.shareServerLinkFailed,
        copy.addFriends,
        copy.findPagesToFollow,
        copy.addFriend,
      ];
      final english = all(en);
      for (final locale in AppLocalizations.supportedLocales) {
        if (locale.languageCode == 'en') continue;
        final localized = all(copyFor(locale));
        for (var i = 0; i < english.length; i++) {
          expect(
            localized[i],
            isNot(english[i]),
            reason: '$locale falls back to English for "${english[i]}"',
          );
          expect(localized[i], isNot(contains('{')), reason: '$locale');
        }
      }
    });

    test('the progress template puts both numbers in every locale', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final text = copyFor(locale).progress(3, 5);
        expect(text, contains('3'), reason: '$locale');
        expect(text, contains('5'), reason: '$locale');
      }
    });

    test('the follow hint names Treści by its tab word in every locale', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final copy = AppLocalizations(locale);
        final tab = copy.contextualText(
          'navigation.content',
          'Content',
          'Treści',
        );
        final hint = FirstStepsCopy(copy).hint(FirstStep.follow);
        // Polish declines the word ("w Treściach"); every other locale uses
        // the tab label as written (Finnish as the stem of a compound).
        if (locale.languageCode == 'pl') {
          expect(hint, contains('Treściach'));
        } else {
          expect(hint, contains(tab), reason: '$locale: "$hint" vs "$tab"');
        }
      }
    });
  });
}
