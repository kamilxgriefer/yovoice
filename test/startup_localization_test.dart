import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/translations/translations_startup.dart';

const _expectedHeadlineKeys = <String>[
  'Where conversation begins.',
  'Your voice brings us closer.',
  'Good to hear you.',
  'Every connection starts with a hello.',
];

const _expectedKeys = <String>{..._expectedHeadlineKeys, 'Opening YO Voice'};

final _placeholderPattern = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');

List<String> _placeholders(String value) =>
    (_placeholderPattern
        .allMatches(value)
        .map((match) => match.group(0)!)
        .toList()
      ..sort());

void main() {
  test('startup module covers exactly the 43 selectable locale variants', () {
    final selectableLocaleKeys = selectableAppLanguages
        .map((language) => language.localeKey)
        .toSet();

    expect(selectableLocaleKeys, hasLength(43));
    expect(startupTranslations.keys.toSet(), selectableLocaleKeys);
    expect(startupHeadlineTranslationKeys, _expectedHeadlineKeys);
    expect(startupTranslationKeys, hasLength(_expectedKeys.length));
    expect(startupTranslationKeys.toSet(), _expectedKeys);
  });

  test('all 215 startup entries are complete and preserve placeholders', () {
    var entryCount = 0;
    for (final localeEntry in startupTranslations.entries) {
      final localeKey = localeEntry.key;
      final entries = localeEntry.value;
      expect(entries.keys.toSet(), _expectedKeys, reason: localeKey);

      for (final key in _expectedKeys) {
        final value = entries[key]!;
        final context = '$localeKey: $key';
        expect(value, isNotEmpty, reason: context);
        expect(value, value.trim(), reason: context);
        expect(value, isNot(contains('\n')), reason: context);
        expect(value, isNot(contains('\r')), reason: context);
        expect(value, isNot(contains('\uFFFD')), reason: context);
        expect(_placeholders(value), _placeholders(key), reason: context);
        if (localeKey == 'en') {
          expect(value, key, reason: context);
        } else {
          expect(value, isNot(key), reason: '$context: no English fallback');
        }
        entryCount++;
      }

      expect(
        _expectedHeadlineKeys.map((key) => entries[key]).toSet(),
        hasLength(4),
        reason: '$localeKey: each launch variant must remain distinct',
      );
      expect(
        'YO Voice'.allMatches(entries['Opening YO Voice']!),
        hasLength(1),
        reason: '$localeKey: the accessibility label preserves the brand',
      );
    }
    expect(entryCount, 215);
  });

  test(
    'Polish startup copy preserves the approved tone and first headline',
    () {
      expect(startupTranslations['pl'], {
        'Where conversation begins.': 'Tu zaczyna się rozmowa.',
        'Your voice brings us closer.': 'Twój głos nas zbliża.',
        'Good to hear you.': 'Dobrze Cię słyszeć.',
        'Every connection starts with a hello.':
            'Każda znajomość zaczyna się od „cześć”.',
        'Opening YO Voice': 'Otwieranie YO Voice',
      });
    },
  );

  test('Portuguese startup copy follows the app region resolution', () {
    final portugal = localizationKeyForLocale(const Locale('pt', 'PT'));
    final brazil = localizationKeyForLocale(const Locale('pt', 'BR'));
    expect(portugal, 'pt');
    expect(brazil, 'pt_BR');
    expect(
      startupTranslations[portugal]!['Your voice brings us closer.'],
      'A tua voz aproxima-nos.',
    );
    expect(
      startupTranslations[brazil]!['Your voice brings us closer.'],
      'Sua voz nos aproxima.',
    );
  });

  test('Chinese startup copy follows the app script and region resolution', () {
    final simplified = localizationKeyForLocale(
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    );
    final traditional = localizationKeyForLocale(
      const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'HK',
      ),
    );
    expect(simplified, 'zh_CN');
    expect(traditional, 'zh_TW');
    expect(
      startupTranslations[simplified]!['Where conversation begins.'],
      '对话，从这里开始。',
    );
    expect(
      startupTranslations[traditional]!['Where conversation begins.'],
      '對話，從這裡開始。',
    );
  });

  test(
    'RTL headlines retain their own scripts and no forced bidi controls',
    () {
      final rtlScriptPatterns = <String, RegExp>{
        'ar': RegExp(r'[\u0600-\u06FF]'),
        'he': RegExp(r'[\u0590-\u05FF]'),
        'fa': RegExp(r'[\u0600-\u06FF]'),
        'ur': RegExp(r'[\u0600-\u06FF]'),
      };
      final bidiControls = RegExp(r'[\u202A-\u202E\u2066-\u2069]');

      for (final localeEntry in rtlScriptPatterns.entries) {
        final entries = startupTranslations[localeEntry.key]!;
        for (final key in _expectedHeadlineKeys) {
          expect(
            localeEntry.value.hasMatch(entries[key]!),
            isTrue,
            reason: '${localeEntry.key}: $key',
          );
        }
        for (final entry in entries.entries) {
          expect(
            bidiControls.hasMatch(entry.value),
            isFalse,
            reason:
                '${localeEntry.key}: ${entry.key}: direction belongs to the UI',
          );
        }
      }
    },
  );
}
