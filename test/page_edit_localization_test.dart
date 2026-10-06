// "Edytuj stronę" copy in all 43 locales (pageEdit A, ADR-241): English and
// Polish are authored at the call site (`PageEditCopy`), the other 41 locales
// resolve through `translations_page_edit.dart`. A missing locale is a
// null-check crash on the first catalog read, a dropped placeholder is a
// crash in that locale, and an English value is a silent fallback; all three
// are pinned here per key.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_page_edit.dart';
import 'package:yovoice/core/localization/translations/translations_pages.dart';
import 'package:yovoice/core/localization/translations/translations_vip_likers.dart';
import 'package:yovoice/features/pages/presentation/page_edit_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';

final _placeholderPattern = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');

List<String> _placeholders(String value) =>
    _placeholderPattern.allMatches(value).map((m) => m.group(0)!).toList()
      ..sort();

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
Set<String> _catalogKeys(String source) {
  const literals = r'''((?:(?:'(?:\\.|[^'])*'|"(?:\\.|[^"])*")\s*)+)''';
  final call = RegExp(
    '\\.(?:text|template|contextualText)\\(\\s*$literals,',
    multiLine: true,
  );
  return <String>{
    for (final match in call.allMatches(source))
      _joinedLiteral(match.group(1)!),
  };
}

/// The key a value's placeholders are compared with: a `pageEdit.*` context
/// key has none.
String _placeholderSource(String key) => key.startsWith('pageEdit.') ? '' : key;

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

  test('covers exactly the 41 translated locales with unique keys', () {
    expect(AppLocalizations.supportedLocales, hasLength(43));
    expect(locales, hasLength(41));
    expect(pageEditTranslations.keys.toSet(), locales);
    expect(
      pageEditTranslationKeys.toSet(),
      hasLength(pageEditTranslationKeys.length),
      reason: 'duplicate key in pageEditTranslationKeys',
    );
    expect(appTranslationKeys, containsAll(pageEditTranslationKeys));
  });

  test('every locale is complete, non-empty and keeps placeholders', () {
    final expected = pageEditTranslationKeys.toSet();
    for (final locale in locales) {
      final entries = pageEditTranslations[locale]!;
      expect(entries.keys.toSet(), expected, reason: locale);
      for (final key in pageEditTranslationKeys) {
        final value = entries[key]!;
        expect(value.trim(), isNotEmpty, reason: '$locale: $key');
        expect(value, value.trim(), reason: '$locale: $key');
        expect(
          _placeholders(value),
          _placeholders(_placeholderSource(key)),
          reason: '$locale: placeholder drift on "$key": "$value"',
        );
        // A sentence left in English is a missed translation.
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

  test('the module holds exactly the strings PageEditCopy asks for', () {
    final used = _catalogKeys(
      File(
        'lib/features/pages/presentation/page_edit_copy.dart',
      ).readAsStringSync(),
    );
    expect(pageEditTranslationKeys.toSet(), used);
  });

  test('no key is already owned by the Pages or likers modules, and the '
      'merged catalog serves every entry unchanged', () {
    expect(
      pageEditTranslationKeys.toSet().intersection(
        pagesTranslationKeys.toSet(),
      ),
      isEmpty,
    );
    expect(
      pageEditTranslationKeys.toSet().intersection(
        vipLikersTranslationKeys.toSet(),
      ),
      isEmpty,
    );
    for (final locale in locales) {
      for (final key in pageEditTranslationKeys) {
        expect(
          translatedPhrase(locale, key),
          pageEditTranslations[locale]![key],
          reason: '$locale: "$key" is overridden by another module',
        );
      }
    }
  });

  test('English and Polish keep the reviewed wording', () {
    final en = _copy('en');
    final pl = _copy('pl');
    expect(pl.editAppearance, 'Wygląd');
    expect(pl.editName, 'Nazwa');
    expect(
      pl.editNameHelper,
      'Nazwę zmienisz raz na 30 dni. Po zmianie strona przez 7 dni nie '
      'pojawia się w wyszukiwarce.',
    );
    expect(pl.editTypeLocked, 'Typu nie da się jeszcze zmienić');
    expect(pl.unsavedChanges, 'Masz niezapisane zmiany');
    expect(pl.saveChanges, 'Zapisz zmiany');
    expect(
      pl.editPreviewNote,
      'Tak zobaczą stronę inni. Podgląd zmienia się, gdy piszesz.',
    );
    expect(pl.clearContact, 'Wyczyść dane kontaktowe');
    expect(
      pl.editNameLockedUntil('24 paź 2026'),
      'Nazwę zmienisz ponownie 24 paź 2026.',
    );
    expect(en.saveChanges, 'Save changes');
    expect(
      en.editNameLockedUntil('Oct 24, 2026'),
      'You can change the name again on Oct 24, 2026.',
    );
  });

  test('every locale resolves the whole form without English', () {
    for (final locale in locales) {
      final copy = _copy(locale);
      final date = copy.editNameLockedUntil('24.10.2026');
      expect(date, contains('24.10.2026'), reason: locale);
      expect(date, isNot(contains('{')), reason: locale);
      for (final (english, value) in <(String, String)>[
        ('Save changes', copy.saveChanges),
        ('You have unsaved changes', copy.unsavedChanges),
        ('Clear contact details', copy.clearContact),
        ('Editing is off right now', copy.editLockedTitle),
        ('Discard changes?', copy.discardChangesTitle),
      ]) {
        expect(value, isNot(english), reason: '$locale: $english');
        expect(value.trim(), isNotEmpty, reason: locale);
      }
    }
  });

  test('the short labels stay short in every language', () {
    // "Zapisz zmiany" sits in a 168 px desktop button and a phone-wide bar;
    // the section and field labels float on a field's border.
    for (final locale in locales) {
      final copy = _copy(locale);
      expect(copy.saveChanges.length, lessThanOrEqualTo(30), reason: locale);
      expect(copy.editAppearance.length, lessThanOrEqualTo(16), reason: locale);
      expect(copy.editName.length, lessThanOrEqualTo(16), reason: locale);
      expect(copy.clearAction.length, lessThanOrEqualTo(16), reason: locale);
      expect(copy.changeCover.length, lessThanOrEqualTo(32), reason: locale);
      expect(copy.changePhoto.length, lessThanOrEqualTo(32), reason: locale);
    }
  });
}
