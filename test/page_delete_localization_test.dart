// Page deletion copy (ADR-236) in all 43 locales: English and Polish are
// authored at the call sites (`page_delete_copy.dart`, two lines of
// `page_profile_copy.dart`), the other 41 locales resolve through
// `translations_page_delete.dart`. A missing locale is a null-check crash on
// the first catalog read, a dropped placeholder is a crash in that locale,
// and an English value is a silent fallback; all three are pinned per key.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_page_delete.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/page_delete_copy.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';

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

const _stem = '{count} posts';

Set<String> _translatedLocaleKeys() => selectableAppLanguages
    .where(
      (language) =>
          language != AppLanguagePreference.english &&
          language != AppLanguagePreference.polish,
    )
    .map((language) => language.localeKey)
    .toSet();

/// The key a value's placeholders are compared with.
String _placeholderSource(String key) {
  if (key.startsWith('pages.')) return '';
  final dot = key.lastIndexOf('.');
  if (dot > 0 && _pluralCategories.contains(key.substring(dot + 1))) {
    return key.substring(0, dot);
  }
  return key;
}

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
/// and the six category keys of every plural `stem:` in [source].
Set<String> _catalogKeys(String source) {
  const literals = r'''((?:(?:'(?:\\.|[^'])*'|"(?:\\.|[^"])*")\s*)+)''';
  final call = RegExp(
    '\\.(?:text|template|contextualText)\\(\\s*$literals,',
    multiLine: true,
  );
  final stem = RegExp('\\bstem:\\s*$literals,', multiLine: true);
  return <String>{
    for (final match in call.allMatches(source))
      _joinedLiteral(match.group(1)!),
    for (final match in stem.allMatches(source))
      for (final category in _pluralCategories)
        '${_joinedLiteral(match.group(1)!)}.$category',
  };
}

PagesCopy _copy(String tag) {
  final parts = tag.split('_');
  return PagesCopy(
    AppLocalizations(
      parts.length == 2 ? Locale(parts[0], parts[1]) : Locale(parts[0]),
    ),
  );
}

void main() {
  final locales = _translatedLocaleKeys();

  // The dates in this copy are formatted per locale; the app loads the
  // symbols with its localization delegate.
  setUpAll(initializeDateFormatting);

  test('covers exactly the 41 translated locales with unique keys', () {
    expect(AppLocalizations.supportedLocales, hasLength(43));
    expect(locales, hasLength(41));
    expect(pageDeleteTranslations.keys.toSet(), locales);
    expect(
      pageDeleteTranslationKeys.toSet(),
      hasLength(pageDeleteTranslationKeys.length),
      reason: 'duplicate key in pageDeleteTranslationKeys',
    );
    for (final category in _pluralCategories) {
      expect(pageDeleteTranslationKeys, contains('$_stem.$category'));
    }
    expect(appTranslationKeys, containsAll(pageDeleteTranslationKeys));
  });

  test('every locale is complete, non-empty and keeps placeholders', () {
    final expected = pageDeleteTranslationKeys.toSet();
    for (final locale in locales) {
      final entries = pageDeleteTranslations[locale]!;
      expect(entries.keys.toSet(), expected, reason: locale);
      for (final key in pageDeleteTranslationKeys) {
        final value = entries[key]!;
        expect(value.trim(), isNotEmpty, reason: '$locale: $key');
        expect(
          _placeholders(value),
          _placeholders(_placeholderSource(key)),
          reason: '$locale: placeholder drift on "$key": "$value"',
        );
        expect(
          value,
          isNot(key),
          reason: '$locale: English fallback shipped for "$key"',
        );
      }
    }
  });

  test('the merged app catalog serves these entries unchanged', () {
    for (final locale in locales) {
      for (final key in pageDeleteTranslationKeys) {
        expect(
          translatedPhrase(locale, key),
          pageDeleteTranslations[locale]![key],
          reason: '$locale: "$key" is overridden by another catalog module',
        );
      }
    }
  });

  test('every deletion string in code is a catalog key, and none is dead', () {
    final used = _catalogKeys(
      File(
        'lib/features/pages/presentation/page_delete_copy.dart',
      ).readAsStringSync(),
    );
    // "Danger zone" is the Servers danger zone's existing key.
    for (final key in used) {
      expect(
        appTranslationKeys.contains(key),
        isTrue,
        reason: 'no translation for "$key"',
      );
      for (final locale in locales) {
        expect(translatedPhrase(locale, key), isNotNull, reason: locale);
      }
    }
    // The two create-flow lines and the cooldown refusal live in
    // page_profile_copy.dart.
    final profileCopy = _catalogKeys(
      File(
        'lib/features/pages/presentation/page_profile_copy.dart',
      ).readAsStringSync(),
    );
    final all = {...used, ...profileCopy};
    for (final key in pageDeleteTranslationKeys) {
      expect(all, contains(key), reason: '"$key" is translated but unused');
    }
  });

  test('the untrue "only deleted with the account" line is gone', () {
    final sources = [
      for (final file in Directory(
        'lib/features/pages',
      ).listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          file.readAsStringSync(),
    ].join('\n');
    expect(sources, isNot(contains('only deleted together with the account')));
    expect(sources, isNot(contains('Usuniesz ją tylko razem z kontem')));
  });

  group('copy', () {
    test('Polish keeps the owner-approved wording of the chosen frames', () {
      final pl = _copy('pl');
      final at = DateTime(2026, 11, 1, 12);
      expect(pl.dangerZone, 'Strefa zagrożenia');
      expect(pl.deleteAllPosts, 'Usuń wszystkie posty');
      expect(pl.deleteAllPostsSubtitle, 'Strona i obserwujący zostają');
      expect(pl.deletePage, 'Usuń stronę');
      expect(
        pl.deletePageSubtitle,
        'Posty, obserwujący i kontakt. Konto zostaje.',
      );
      expect(pl.clearPostsTitle(14), 'Usunąć 14 postów?');
      expect(
        pl.clearPostsBody(128),
        'Znikną też komentarze i polubienia pod nimi. Strona i 128 '
        'obserwujących zostają. Tego nie da się cofnąć.',
      );
      expect(pl.goesPosts(14), '14 postów ze zdjęciami i nagraniami.');
      expect(
        pl.goesFollowers(128),
        '128 obserwujących strony i ich powiadomienia o Twoich LIVE.',
      );
      expect(
        pl.reportedExceptionBody,
        'Zgłoszone treści możemy przechowywać niepublicznie do 90 dni.',
      );
      expect(pl.graceTitle, 'Masz 30 dni na powrót');
      expect(
        pl.graceBody(at),
        'Stronę ukryjemy od razu. Usuniemy ją 1 listopada 2026. Do tego dnia '
        'możesz ją przywrócić. Przywrócenie wymaga aktywnego Premium lub VIP.',
      );
      expect(pl.pendingTitle(at), 'Strona zostanie usunięta 1 listopada 2026');
      expect(pl.statusPendingDeletion, 'Do usunięcia');
      expect(pl.restorePage, 'Przywróć stronę');
      expect(pl.deleteNow, 'Usuń teraz, nie czekaj');
      expect(
        pl.deleteNowSubtitle(at),
        'Bez czekania do 1 listopada. Tego nie da się cofnąć.',
      );
      expect(pl.clearingTitle, 'Trwa usuwanie postów');
      expect(
        pl.clearingBody(128),
        'Znikają w tle, zwykle w kilkanaście minut. Strona i 128 '
        'obserwujących zostają.',
      );
      expect(pl.recreateAfter(at), 'Nową stronę założysz po 1 listopada 2026.');
    });

    test('counted posts decline in Polish, English, Russian and Arabic', () {
      expect(_copy('en').postsCount(1), '1 post');
      expect(_copy('en').postsCount(14), '14 posts');
      expect(_copy('pl').postsCount(1), '1 post');
      expect(_copy('pl').postsCount(3), '3 posty');
      expect(_copy('pl').postsCount(14), '14 postów');
      expect(_copy('pl').postsCount(22), '22 posty');
      expect(_copy('ru').postsCount(1), '1 пост');
      expect(_copy('ru').postsCount(3), '3 поста');
      expect(_copy('ru').postsCount(14), '14 постов');
      expect(_copy('ru').postsCount(21), '21 пост');
      expect(_copy('ar').postsCount(2), '2 منشوران');
      expect(_copy('ar').postsCount(11), '11 منشورًا');
      expect(_copy('de').clearPostsTitle(14), '14 Beiträge löschen?');
    });

    test('no locale shows an English word or a raw placeholder', () {
      // Whole words only, by Unicode letters: Romanian "postări" and
      // Danish "poster" are not the English "post".
      final english = RegExp(
        r'(?<!\p{L})(posts?|followers?|deleted?|restore|the Page)(?!\p{L})',
        unicode: true,
      );
      final at = DateTime(2026, 11, 1, 12);
      for (final locale in locales) {
        final copy = _copy(locale);
        final lines = <String>[
          for (final n in const [0, 1, 2, 5, 14, 21, 101]) ...[
            copy.clearPostsTitle(n),
            copy.goesPosts(n),
          ],
          copy.clearPostsBody(128),
          copy.clearingBody(128),
          copy.goesFollowers(128),
          copy.graceBody(at),
          copy.pendingTitle(at),
          copy.deleteNowSubtitle(at),
          copy.recreateAfter(at),
          copy.typeNameHelper('Pracownia Glina'),
          copy.deletionSoonNotice,
          copy.manageError(PagesFailure.recreateCooldown),
          copy.manageError(PagesFailure.deletionInProgress),
          copy.consentBusiness,
          copy.whatProfile,
        ];
        for (final line in lines) {
          expect(line, isNot(contains('{')), reason: '$locale: $line');
          // Filipino keeps "post", "follower" and "Page" as loanwords.
          if (locale == 'fil' || locale == 'it') continue;
          expect(
            line,
            isNot(matches(english)),
            reason: '$locale fell back to English: $line',
          );
        }
      }
    });
  });
}
