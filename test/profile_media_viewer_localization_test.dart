import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_profile_media_viewer.dart';

/// Guard for the fullscreen profile-media (avatar + banner) viewer catalog.
///
/// `app_translation_catalog.dart` merges this module with
/// `profileMediaViewerTranslations[entry.key]!` — a null-check dereference
/// inside the initializer of the lazily built `appTranslations`. One absent
/// locale therefore does not degrade that locale to English: it throws
/// `Null check operator used on a null value` on the *first* catalog read, in
/// every locale including English, taking the navigation dock and the Chats
/// list down with it. The first test below states that requirement as a set
/// comparison so the failure names the missing locale instead of surfacing as
/// a null-check crash 60 suites wide.
final _placeholderPattern = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');

List<String> _placeholders(String value) => _placeholderPattern
    .allMatches(value)
    .map((match) => match.group(0)!)
    .toList();

Set<String> _translatedLocaleKeys() => selectableAppLanguages
    .where(
      (language) =>
          language != AppLanguagePreference.english &&
          language != AppLanguagePreference.polish,
    )
    .map((language) => language.localeKey)
    .toSet();

void main() {
  group('profile media viewer localization', () {
    test('covers every translated locale the catalog dereferences', () {
      expect(
        profileMediaViewerTranslations.keys.toSet(),
        _translatedLocaleKeys(),
        reason:
            'appTranslations does profileMediaViewerTranslations[locale]! for '
            'each of these locales; a missing one throws for all of them',
      );
    });

    test('every locale carries the complete key set, with no fallback', () {
      final expectedKeys = profileMediaViewerTranslationKeys.toSet();
      expect(
        expectedKeys,
        hasLength(profileMediaViewerTranslationKeys.length),
        reason: 'duplicate key in profileMediaViewerTranslationKeys',
      );
      for (final localeKey in profileMediaViewerTranslations.keys) {
        final entries = profileMediaViewerTranslations[localeKey]!;
        expect(entries.keys.toSet(), expectedKeys, reason: localeKey);
        for (final key in profileMediaViewerTranslationKeys) {
          final value = entries[key]!;
          expect(value.trim(), isNotEmpty, reason: '$localeKey: $key');
          expect(
            _placeholders(value),
            _placeholders(key),
            reason: '$localeKey: placeholder drift on "$key"',
          );
          expect(
            value,
            isNot(key),
            reason: '$localeKey: English fallback shipped for "$key"',
          );
        }
      }
    });

    test('the viewer copy resolves through the merged app catalog', () {
      expect(
        appTranslationKeys,
        containsAll(profileMediaViewerTranslationKeys),
      );
      for (final localeKey in _translatedLocaleKeys()) {
        for (final key in profileMediaViewerTranslationKeys) {
          expect(
            translatedPhrase(localeKey, key),
            profileMediaViewerTranslations[localeKey]![key],
            reason: '$localeKey: $key',
          );
        }
      }
    });
  });
}
