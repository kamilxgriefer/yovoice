import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_my_link.dart';
import 'package:yovoice/features/profile/presentation/my_link_copy.dart';

/// "Mój link" copy in all 41 translated locales (ADR-238).
///
/// `app_translation_catalog.dart` merges this module with
/// `myLinkTranslations[locale]!`, so a missing locale is a null-check crash on
/// the first catalog read in every locale, not an English fallback. A dropped
/// placeholder is a crash in that locale, and an English value is a silent
/// fallback; both are pinned here per key.
final _placeholderPattern = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');

List<String> _placeholders(String value) =>
    _placeholderPattern.allMatches(value).map((m) => m.group(0)!).toList()
      ..sort();

/// Every file that renders "Mój link" copy only through the catalog.
const _myLinkSources = <String>[
  'lib/features/profile/presentation/my_link_copy.dart',
  'lib/features/moments/presentation/widgets/moment_detail_chrome.dart',
];

/// Keys those files use that another catalog module already translates for
/// all 41 locales (`translations_reel_links.dart`,
/// `translations_feed_surface_release.dart`, the base catalog), and the one
/// product mark that stays as written.
const _translatedElsewhere = <String>{
  'Share',
  'The link could not be copied. Try again.',
  'Sharing is unavailable here. Copy the link instead.',
  'Sharing could not be confirmed. You can copy the link.',
  'Back',
};
const _productMarks = <String>{'Voice Moment'};

/// A phrase a module had before this one, left exactly as it was.
const _legacyUncatalogued = <String>{'Share this Moment'};

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

/// The catalog key of every `text(` and `template(` call in [source].
List<String> _catalogKeys(String source) {
  const literals = r'''((?:(?:'(?:\\.|[^'])*'|"(?:\\.|[^"])*")\s*)+)''';
  final call = RegExp('\\.(?:text|template)\\(\\s*$literals,', multiLine: true);
  return <String>[
    for (final match in call.allMatches(source))
      _joinedLiteral(match.group(1)!),
  ];
}

void main() {
  final translatedLocaleKeys = _translatedLocaleKeys();

  group('my link catalog', () {
    test('covers exactly the 41 translated locales', () {
      expect(AppLocalizations.supportedLocales, hasLength(43));
      expect(translatedLocaleKeys, hasLength(41));
      expect(myLinkTranslations.keys.toSet(), translatedLocaleKeys);
    });

    test('keys are unique', () {
      expect(
        myLinkTranslationKeys.toSet(),
        hasLength(myLinkTranslationKeys.length),
        reason: 'duplicate key in myLinkTranslationKeys',
      );
    });

    test('every locale is complete, non-empty and keeps placeholders', () {
      final expected = myLinkTranslationKeys.toSet();
      for (final localeKey in translatedLocaleKeys) {
        final entries = myLinkTranslations[localeKey]!;
        expect(entries.keys.toSet(), expected, reason: localeKey);
        for (final key in myLinkTranslationKeys) {
          final value = entries[key]!;
          expect(value.trim(), isNotEmpty, reason: '$localeKey: $key');
          expect(value, value.trim(), reason: '$localeKey: $key');
          expect(
            _placeholders(value),
            _placeholders(key),
            reason: '$localeKey: placeholder drift on "$key": "$value"',
          );
          expect(
            value,
            isNot(key),
            reason: '$localeKey: English fallback shipped for "$key"',
          );
        }
      }
    });

    test('the merged app catalog serves these entries unchanged', () {
      expect(appTranslationKeys, containsAll(myLinkTranslationKeys));
      for (final localeKey in translatedLocaleKeys) {
        for (final key in myLinkTranslationKeys) {
          expect(
            translatedPhrase(localeKey, key),
            myLinkTranslations[localeKey]![key],
            reason:
                '$localeKey: "$key" is overridden by another catalog module',
          );
        }
      }
    });

    test('every my link string in code has a catalog entry', () {
      final missing = <String>[];
      final used = <String>{};
      for (final path in _myLinkSources) {
        for (final key in _catalogKeys(File(path).readAsStringSync())) {
          used.add(key);
          if (_productMarks.contains(key) ||
              _legacyUncatalogued.contains(key)) {
            continue;
          }
          if (!appTranslationKeys.contains(key)) missing.add('$path: "$key"');
        }
      }
      expect(missing, isEmpty, reason: missing.join('\n'));
      // The module carries no dead entries, and what it borrows from other
      // modules really is translated there.
      for (final key in myLinkTranslationKeys) {
        expect(used, contains(key), reason: 'unused catalog key "$key"');
      }
      for (final key in _translatedElsewhere) {
        expect(appTranslationKeys, contains(key));
        expect(myLinkTranslationKeys, isNot(contains(key)));
        for (final localeKey in translatedLocaleKeys) {
          expect(
            translatedPhrase(localeKey, key),
            isNotNull,
            reason: '$localeKey: "$key"',
          );
        }
      }
    });
  });

  group('resolved copy', () {
    test('English and Polish keep the reviewed forms', () {
      const en = MyLinkCopy(AppLocalizations(Locale('en')));
      const pl = MyLinkCopy(AppLocalizations(Locale('pl')));
      final link = Uri.parse('https://app.yovoice.app/?user=abc');

      expect(en.title, 'My link');
      expect(pl.title, 'Mój link');
      expect(
        pl.body(runsPage: false),
        'Kto go otworzy albo zeskanuje kod, zobaczy Twój profil i będzie '
        'mógł dodać Cię do znajomych.',
      );
      expect(
        pl.body(runsPage: true),
        'Kto go otworzy albo zeskanuje kod, zobaczy Twoją Stronę i będzie '
        'mógł Cię obserwować.',
      );
      expect(
        pl.bodyNotPublic,
        'Twój profil nie jest publiczny, więc ten link nie otworzy go '
        'każdemu. Aby każdy mógł Cię dodać, zmień Widoczność profilu w '
        'Ustawieniach.',
      );
      expect(
        en.bodyNotPublic,
        'Your profile is not public, so this link will not open it for '
        'everyone. To let anyone add you, change Profile visibility in '
        'Settings.',
      );
      expect(pl.copyLink, 'Kopiuj link');
      expect(pl.share, 'Udostępnij');
      expect(pl.shareMyLink, 'Udostępnij mój link');
      expect(pl.copied, 'Link skopiowany.');
      expect(
        pl.shareText(link),
        'Znajdź mnie w YO Voice: https://app.yovoice.app/?user=abc',
      );
      expect(
        en.shareText(link),
        'Find me on YO Voice: https://app.yovoice.app/?user=abc',
      );
      expect(pl.profileUnavailable, 'Ten profil jest niedostępny.');
    });

    test('no locale falls back to English, and the link survives', () {
      final link = Uri.parse('https://app.yovoice.app/?user=abc');
      const en = MyLinkCopy(AppLocalizations(Locale('en')));
      for (final language in selectableAppLanguages) {
        if (language == AppLanguagePreference.english) continue;
        final copy = MyLinkCopy(AppLocalizations(language.locale!));
        final key = language.localeKey;
        expect(copy.title, isNot(en.title), reason: key);
        expect(
          copy.body(runsPage: false),
          isNot(en.body(runsPage: false)),
          reason: key,
        );
        expect(
          copy.body(runsPage: true),
          isNot(en.body(runsPage: true)),
          reason: key,
        );
        expect(copy.bodyNotPublic, isNot(en.bodyNotPublic), reason: key);
        expect(copy.copyLink, isNot(en.copyLink), reason: key);
        expect(copy.share, isNot(en.share), reason: key);
        expect(copy.shareMyLink, isNot(en.shareMyLink), reason: key);
        expect(copy.qrLabel, isNot(en.qrLabel), reason: key);
        expect(copy.copied, isNot(en.copied), reason: key);
        expect(copy.cannotCopy, isNot(en.cannotCopy), reason: key);
        expect(copy.cannotShare, isNot(en.cannotShare), reason: key);
        expect(copy.shareUnconfirmed, isNot(en.shareUnconfirmed), reason: key);
        expect(copy.unavailable, isNot(en.unavailable), reason: key);
        expect(
          copy.profileUnavailable,
          isNot(en.profileUnavailable),
          reason: key,
        );
        expect(
          copy.momentUnavailable,
          isNot(en.momentUnavailable),
          reason: key,
        );
        expect(copy.signInForProfile, isNot(en.signInForProfile), reason: key);
        expect(copy.signInForMoment, isNot(en.signInForMoment), reason: key);

        final shared = copy.shareText(link);
        expect(shared, isNot(en.shareText(link)), reason: key);
        expect(shared, contains('https://app.yovoice.app/?user=abc'));
        expect(shared, contains('YO Voice'), reason: key);
        final moment = copy.momentShareText(authorName: 'Ola', link: link);
        expect(
          moment,
          isNot(en.momentShareText(authorName: 'Ola', link: link)),
          reason: key,
        );
        expect(moment, contains('Ola'), reason: key);
        expect(moment, contains('https://app.yovoice.app/?user=abc'));
      }
    });

    test('user content can never become a second template expression', () {
      const pl = MyLinkCopy(AppLocalizations(Locale('pl')));
      final link = Uri.parse('https://app.yovoice.app/?moment=abc');
      expect(
        pl.momentShareText(authorName: r'{link} $x', link: link),
        r'Posłuchaj {link} $x w YO Voice: '
        'https://app.yovoice.app/?moment=abc',
      );
    });
  });
}
