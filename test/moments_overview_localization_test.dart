import 'package:flutter/material.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_moments_overview.dart';

final _placeholderPattern = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');

List<String> _placeholders(String value) =>
    (_placeholderPattern.allMatches(value).map((m) => m.group(0)!).toList()
      ..sort());

/// Every new user-facing string of the YO Moments overview has an explicit
/// entry in all 41 translated locales (43 selectable minus English and
/// Polish, which live in the call sites), the catalog knows the keys, and
/// no locale ships English fallback copy.
void main() {
  final translatedLocaleKeys = selectableAppLanguages
      .where(
        (language) =>
            language != AppLanguagePreference.english &&
            language != AppLanguagePreference.polish,
      )
      .map((language) => language.localeKey)
      .toSet();

  test('the overview catalog covers all 43 selectable locale variants', () {
    expect(AppLocalizations.supportedLocales, hasLength(43));
    expect(translatedLocaleKeys, hasLength(41));
    expect(momentsOverviewTranslations.keys.toSet(), translatedLocaleKeys);
    expect(momentsOverviewTranslationKeys.toSet(), hasLength(16));
    expect(appTranslationKeys, containsAll(momentsOverviewTranslationKeys));
    for (final localeKey in translatedLocaleKeys) {
      final entries = momentsOverviewTranslations[localeKey]!;
      expect(
        entries.keys.toSet(),
        momentsOverviewTranslationKeys.toSet(),
        reason: localeKey,
      );
      for (final key in momentsOverviewTranslationKeys) {
        final value = entries[key]!;
        expect(value.trim(), isNotEmpty, reason: '$localeKey: $key');
        expect(_placeholders(value), _placeholders(key), reason: '$localeKey: $key');
        expect(translatedPhrase(localeKey, key), value, reason: '$localeKey: $key');
        if (!key.startsWith('yoMoments.') && key.length > 10) {
          expect(value, isNot(key), reason: '$localeKey: no English fallback');
        }
      }
    }
  });

  test('contextual keys resolve to the reviewed EN/PL copy and never leak the '
      'unrelated meaning of the same English word', () {
    const english = AppLocalizations(Locale('en'));
    const polish = AppLocalizations(Locale('pl'));
    expect(english.contextualText('yoMoments.create', 'Create', 'Utwórz'), 'Create');
    expect(polish.contextualText('yoMoments.create', 'Create', 'Utwórz'), 'Utwórz');
    expect(
      polish.contextualText('yoMoments.followingState', 'Following', 'Obserwujesz'),
      'Obserwujesz',
    );
    expect(polish.text('Following', 'Obserwowani'), 'Obserwowani');
    const german = AppLocalizations(Locale('de'));
    expect(
      german.contextualText('yoMoments.followingState', 'Following', 'Obserwujesz'),
      'Du folgst',
    );
    expect(german.text('Reply with voice', 'Odpowiedz głosem'), 'Mit Stimme antworten');
    expect(
      german.template(
        'Follow {name}',
        'Obserwuj: {name}',
        values: const <String, Object>{'name': 'Ola'},
      ),
      'Ola folgen',
    );
  });
}
