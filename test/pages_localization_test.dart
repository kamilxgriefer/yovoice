// Premium Pages copy in all 43 locales (spec premium-pages §5, §6.3 "the
// 43-locale sweep"): English and Polish are authored at the call sites, the
// other 41 locales resolve through `translations_pages.dart` (and, for the
// likers count line of a Page post, `translations_vip_likers.dart`).
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_pages.dart';
import 'package:yovoice/features/pages/presentation/page_post_copy.dart';
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

/// Catalog keys in [source]: the first literal of every `text(`,
/// `template(` and `contextualText(` call, and each plural stem's six
/// category keys.
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

List<String> _pagesSources() {
  final files =
      Directory('lib/features/pages')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => file.path)
          .toList()
        ..sort();
  return [...files, 'lib/shared/widgets/identity/vip_meaning_sheet.dart'];
}

/// The key a value's placeholders are compared with.
String _placeholderSource(String key) {
  if (key.startsWith('pages.') || key.startsWith('identity.')) return '';
  final dot = key.lastIndexOf('.');
  if (dot > 0 && _pluralCategories.contains(key.substring(dot + 1))) {
    return key.substring(0, dot);
  }
  return key;
}

void main() {
  final locales = _translatedLocaleKeys();

  test('covers exactly the 41 translated locales with unique keys', () {
    expect(locales, hasLength(41));
    expect(pagesTranslations.keys.toSet(), locales);
    expect(
      pagesTranslationKeys.toSet(),
      hasLength(pagesTranslationKeys.length),
      reason: 'duplicate key in pagesTranslationKeys',
    );
    expect(appTranslationKeys, containsAll(pagesTranslationKeys));
  });

  test('every locale is complete, non-empty and keeps placeholders', () {
    final expected = pagesTranslationKeys.toSet();
    for (final locale in locales) {
      final entries = pagesTranslations[locale]!;
      expect(entries.keys.toSet(), expected, reason: locale);
      for (final key in pagesTranslationKeys) {
        final value = entries[key]!;
        expect(value.trim(), isNotEmpty, reason: '$locale: $key');
        expect(
          _placeholders(value),
          _placeholders(_placeholderSource(key)),
          reason: '$locale: placeholder drift on "$key": "$value"',
        );
        // A sentence left in English is a missed translation; short labels
        // ("Sport", "E-mail", "Post") and placeholder-only templates such
        // as "{name}, {kind}, {age}" can legitimately match.
        final source = _placeholderSource(key);
        final prose = source.replaceAll(_placeholderPattern, '').trim();
        if (RegExp(r'[A-Za-z]{2,}').hasMatch(prose) &&
            source.split(' ').length >= 3) {
          expect(
            value,
            isNot(source),
            reason: '$locale: English fallback shipped for "$key"',
          );
        }
      }
    }
  });

  test('every Pages string in code resolves in all 41 locales', () {
    final missing = <String>[];
    for (final path in _pagesSources()) {
      for (final key in _catalogKeys(File(path).readAsStringSync())) {
        for (final locale in locales) {
          if (translatedPhrase(locale, key) == null) {
            missing.add('$locale: $path "$key"');
          }
        }
      }
    }
    for (final key in const [
      '{actor} commented on your Page post',
      '{count} people liked this post.one',
      '{count} people liked this post.other',
    ]) {
      for (final locale in locales) {
        if (translatedPhrase(locale, key) == null) {
          missing.add('$locale: "$key"');
        }
      }
    }
    expect(missing, isEmpty, reason: missing.take(40).join('\n'));
  });

  test('the merged catalog serves the Pages entries unchanged', () {
    for (final locale in locales) {
      for (final key in pagesTranslationKeys) {
        expect(
          translatedPhrase(locale, key),
          pagesTranslations[locale]![key],
          reason: '$locale: "$key" is overridden by another module',
        );
      }
    }
  });

  group('counts use each language\'s plural forms', () {
    PagesCopy copy(String tag) {
      final parts = tag.split('_');
      return PagesCopy(
        AppLocalizations(
          parts.length == 2 ? Locale(parts[0], parts[1]) : Locale(parts[0]),
        ),
      );
    }

    test('English and Polish keep the reviewed forms', () {
      expect(copy('en').likes(1), '1 like');
      expect(copy('en').likes(48), '48 likes');
      expect(copy('en').followers(1200), '1.2K followers');
      expect(copy('pl').likes(1), '1 polubienie');
      expect(copy('pl').likes(22), '22 polubienia');
      expect(copy('pl').likes(25), '25 polubień');
      expect(copy('pl').comments(3), '3 komentarze');
      expect(copy('pl').comments(12), '12 komentarzy');
      expect(copy('pl').morePhotos(3), 'Jeszcze 3 zdjęcia');
      expect(copy('pl').followers(1), '1 obserwujący');
      expect(
        PagePostCopy(const AppLocalizations(Locale('pl'))).postsLeftToday(2),
        'Dziś możesz opublikować jeszcze 2 posty.',
      );
    });

    test('Slavic and Arabic counts pick the right category', () {
      expect(copy('ru').comments(1), '1 комментарий');
      expect(copy('ru').comments(3), '3 комментария');
      expect(copy('ru').comments(5), '5 комментариев');
      expect(copy('ru').comments(21), '21 комментарий');
      expect(copy('uk').comments(22), '22 коментарі');
      expect(copy('cs').likes(3), '3 lajky');
      expect(copy('ar').comments(2), '2 تعليقان');
      expect(copy('ar').comments(11), '11 تعليقًا');
      expect(copy('de').followers(1), '1 Follower');
      expect(copy('fr').comments(0), '0 commentaire');
    });

    test('no locale shows an English count word', () {
      final english = RegExp(r'\b(likes?|comments?|followers?)\b');
      for (final locale in locales) {
        final pages = copy(locale);
        for (final n in const [0, 1, 2, 3, 5, 11, 21, 101]) {
          expect(
            pages.comments(n),
            isNot(matches(english)),
            reason: '$locale comments($n)',
          );
          expect(pages.comments(n), contains('$n'), reason: locale);
          expect(pages.likes(n), contains('$n'), reason: locale);
        }
      }
    });
  });
}
