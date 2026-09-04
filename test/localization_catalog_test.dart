import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_auth_call_release.dart';
import 'package:yovoice/core/localization/translations/translations_current_release.dart';
import 'package:yovoice/core/localization/translations/translations_direct_call_refusals.dart';
import 'package:yovoice/core/localization/translations/translations_reels.dart';

final _placeholderPattern = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');

List<String> _placeholders(String value) {
  final placeholders = _placeholderPattern
      .allMatches(value)
      .map((match) => match.group(0)!)
      .toList(growable: false);
  return [...placeholders]..sort();
}

String _localeTag(Locale locale) => locale.toLanguageTag();

const _extendedLanguagePreferences = <AppLanguagePreference>[
  AppLanguagePreference.chineseSimplified,
  AppLanguagePreference.chineseTraditional,
  AppLanguagePreference.japanese,
  AppLanguagePreference.korean,
  AppLanguagePreference.arabic,
  AppLanguagePreference.hindi,
  AppLanguagePreference.bengali,
  AppLanguagePreference.urdu,
  AppLanguagePreference.thai,
  AppLanguagePreference.malay,
  AppLanguagePreference.filipino,
  AppLanguagePreference.hebrew,
  AppLanguagePreference.persian,
  AppLanguagePreference.swahili,
];

void main() {
  group('localization catalog integrity', () {
    test('canonical keys are stable templates, never interpolated values', () {
      for (final key in appTranslationKeys) {
        expect(
          key,
          isNot(contains(r'$')),
          reason:
              'Canonical lookup keys must use placeholders such as {name}; '
              'runtime interpolation would make the key impossible to find.',
        );
      }
    });

    test(
      'selectable preferences and supported locales are unique and aligned',
      () {
        expect(
          selectableAppLanguages.toSet(),
          hasLength(selectableAppLanguages.length),
        );
        expect(
          selectableAppLanguages,
          isNot(contains(AppLanguagePreference.system)),
        );

        final preferenceTags = selectableAppLanguages
            .map((language) => _localeTag(language.locale!))
            .toList(growable: false);
        final supportedTags = AppLocalizations.supportedLocales
            .map(_localeTag)
            .toList(growable: false);

        expect(preferenceTags.toSet(), hasLength(preferenceTags.length));
        expect(supportedTags, preferenceTags);
      },
    );

    test('every translated locale has one complete, non-empty catalog', () {
      final requiredLocaleKeys = selectableAppLanguages
          .where(
            (language) =>
                language != AppLanguagePreference.english &&
                language != AppLanguagePreference.polish,
          )
          .map((language) => language.localeKey)
          .toSet();

      expect(appTranslations.keys.toSet(), requiredLocaleKeys);

      for (final localeKey in requiredLocaleKeys) {
        final translations = appTranslations[localeKey];
        expect(translations, isNotNull, reason: 'Missing $localeKey catalog.');
        expect(
          translations!.keys.toSet(),
          appTranslationKeys,
          reason:
              '$localeKey must contain exactly the canonical source keys. '
              'Missing: ${<String>{...appTranslationKeys}.difference(translations.keys.toSet())}; '
              'extra: ${translations.keys.toSet().difference(<String>{...appTranslationKeys})}.',
        );
        for (final entry in translations.entries) {
          expect(
            entry.value.trim(),
            isNotEmpty,
            reason: '$localeKey has an empty translation for "${entry.key}".',
          );
          expect(
            _placeholders(entry.value),
            _placeholders(entry.key),
            reason:
                '$localeKey changed placeholders for "${entry.key}": '
                '"${entry.value}".',
          );
        }
      }
    });

    test('current release copy has an explicit entry in every locale', () {
      final requiredLocaleKeys = selectableAppLanguages
          .where(
            (language) =>
                language != AppLanguagePreference.english &&
                language != AppLanguagePreference.polish,
          )
          .map((language) => language.localeKey);
      final releaseKeys = <String>{
        ...currentReleaseTranslationKeys,
        ...currentReleaseCompactTranslationKeys,
        ...currentReleaseChatMediaTranslationKeys,
        ...authCallReleaseTranslationKeys,
        ...directCallRefusalTranslationKeys,
        ...reelsTranslationKeys,
      };

      expect(appTranslationKeys, containsAll(releaseKeys));
      for (final localeKey in requiredLocaleKeys) {
        for (final key in releaseKeys) {
          final localized = translatedPhrase(localeKey, key);
          expect(
            localized,
            isNotNull,
            reason:
                '$localeKey must not fall back to English for current-release '
                'copy "$key".',
          );
          expect(
            localized!.trim(),
            isNotEmpty,
            reason: '$localeKey has empty current-release copy for "$key".',
          );
          expect(
            _placeholders(localized),
            _placeholders(key),
            reason:
                '$localeKey changed a current-release placeholder in "$key".',
          );
        }
      }
    });

    test(
      'connection interruption copy is localized in every translated locale',
      () {
        const key = 'Connection interrupted';

        expect(directCallRefusalTranslationKeys, contains(key));
        for (final entry in directCallRefusalTranslations.entries) {
          expect(
            entry.value.keys,
            contains(key),
            reason: '${entry.key} must localize the direct-call interruption.',
          );
          expect(
            entry.value[key]!.trim(),
            isNotEmpty,
            reason: '${entry.key} has empty direct-call interruption copy.',
          );
          expect(
            entry.value[key],
            isNot(key),
            reason: '${entry.key} must not fall back to English.',
          );
        }
      },
    );

    test('extended locale catalogs do not ship English fallback copy', () {
      const extendedLocaleKeys = <String>{
        'zh_CN',
        'zh_TW',
        'ja',
        'ko',
        'ar',
        'hi',
        'bn',
        'ur',
        'th',
        'ms',
        'fil',
        'he',
        'fa',
        'sw',
      };
      const naturallyUnchangedValues = <String>{
        '{destination}, {unread}',
        // Reels is a stable product destination name, like Premium and VIBE.
        'Reels',
        // Video is an established loanword in several supported languages.
        'Video',
      };
      const naturallyUnchangedPairs = <String>{
        // CLDR display names that are genuinely identical to English.
        'ms|Hindi',
        'ms|Urdu',
        'ms|Thai',
        'ms|Swahili',
        'fil|Japanese',
        'fil|Korean',
        'fil|Arabic',
        'fil|Hindi',
        'fil|Urdu',
        'fil|Thai',
        'fil|Malay',
        'fil|Filipino',
        'fil|Hebrew',
        'fil|Persian',
        'fil|Swahili',
      };
      final unexpectedEnglishCopy = <String>[];

      for (final localeKey in extendedLocaleKeys) {
        for (final entry in appTranslations[localeKey]!.entries) {
          final localePhrase = '$localeKey|${entry.key}';
          if (naturallyUnchangedValues.contains(entry.key) ||
              naturallyUnchangedPairs.contains(localePhrase)) {
            continue;
          }
          if (entry.value == entry.key) unexpectedEnglishCopy.add(localePhrase);
        }
      }
      expect(
        unexpectedEnglishCopy,
        isEmpty,
        reason: 'Extended catalogs still contain English source copy.',
      );
    });

    test('extended language names are localized for the active locale', () {
      const representativeNames = <(Locale, AppLanguagePreference, String)>[
        (Locale('de'), AppLanguagePreference.japanese, 'Japanisch'),
        (Locale('es'), AppLanguagePreference.japanese, 'japonés'),
        (Locale('uk'), AppLanguagePreference.japanese, 'японська'),
        (Locale('ar'), AppLanguagePreference.japanese, 'اليابانية'),
        (Locale('ja'), AppLanguagePreference.korean, '韓国語'),
      ];
      for (final (locale, language, expectedName) in representativeNames) {
        expect(
          AppLocalizations(locale).languageName(language),
          expectedName,
          reason:
              '${locale.toLanguageTag()} must localize '
              '${language.englishName}.',
        );
      }

      // A handful of language names are genuinely spelled identically in a
      // different locale. These explicit pairs keep the guard strict without
      // treating correct CLDR data as a regression.
      const genuineCrossLocaleMatches = <String>{
        'de|Filipino',
        'fa|Urdu',
        'id|Filipino',
        'ur|Persian',
      };
      final translatedLanguages = selectableAppLanguages.where(
        (language) =>
            language != AppLanguagePreference.english &&
            language != AppLanguagePreference.polish,
      );

      for (final activeLanguage in translatedLanguages) {
        final copy = AppLocalizations(activeLanguage.locale!);
        for (final displayedLanguage in _extendedLanguagePreferences) {
          final localizedName = copy.languageName(displayedLanguage);
          final matchesNativeTitle =
              localizedName == displayedLanguage.nativeName;
          if (!matchesNativeTitle) continue;

          final isOwnLanguage =
              activeLanguage.localeKey == displayedLanguage.localeKey;
          final allowedCrossLocaleMatch = genuineCrossLocaleMatches.contains(
            '${activeLanguage.localeKey}|${displayedLanguage.englishName}',
          );
          expect(
            isOwnLanguage || allowedCrossLocaleMatch,
            isTrue,
            reason:
                '${activeLanguage.localeKey} blindly reuses the native title '
                'for ${displayedLanguage.englishName} instead of a localized '
                'language name.',
          );
        }
      }
    });
  });

  group('locale resolution and fallback', () {
    test(
      'resolves language, region and unsupported locale deterministically',
      () {
        expect(
          languagePreferenceForLocale(const Locale('de', 'DE')),
          AppLanguagePreference.german,
        );
        expect(
          languagePreferenceForLocale(const Locale('pt', 'BR')),
          AppLanguagePreference.portugueseBrazil,
        );
        expect(
          languagePreferenceForLocale(const Locale('pt', 'AO')),
          AppLanguagePreference.portuguese,
        );
        expect(
          languagePreferenceForLocale(
            const Locale.fromSubtags(
              languageCode: 'zh',
              scriptCode: 'Hans',
              countryCode: 'SG',
            ),
          ),
          AppLanguagePreference.chineseSimplified,
        );
        expect(
          languagePreferenceForLocale(
            const Locale.fromSubtags(
              languageCode: 'zh',
              scriptCode: 'Hant',
              countryCode: 'HK',
            ),
          ),
          AppLanguagePreference.chineseTraditional,
        );
        expect(
          languagePreferenceForLocale(const Locale('zh', 'MO')),
          AppLanguagePreference.chineseTraditional,
        );
        expect(
          languagePreferenceForLocale(const Locale('zh', 'SG')),
          AppLanguagePreference.chineseSimplified,
        );
        expect(
          languagePreferenceForLocale(const Locale('xx', 'YY')),
          AppLanguagePreference.english,
        );
        expect(localizationKeyForLocale(const Locale('pt', 'BR')), 'pt_BR');
        expect(localizationKeyForLocale(const Locale('zh', 'CN')), 'zh_CN');
        expect(localizationKeyForLocale(const Locale('zh', 'TW')), 'zh_TW');
        expect(localizationKeyForLocale(const Locale('xx', 'YY')), 'en');
        expect(
          resolveAppLocale(const <Locale>[
            Locale.fromSubtags(
              languageCode: 'zh',
              scriptCode: 'Hant',
              countryCode: 'HK',
            ),
          ], AppLocalizations.supportedLocales),
          const Locale('zh', 'TW'),
        );
        expect(
          resolveAppLocale(const <Locale>[
            Locale('xx', 'YY'),
            Locale('de', 'DE'),
          ], AppLocalizations.supportedLocales),
          const Locale('de'),
        );
      },
    );

    test('unsupported phrases and locales fall back to English', () {
      expect(translatedPhrase('id', 'Not a catalog phrase'), isNull);
      expect(const AppLocalizations(Locale('xx')).settings, 'Settings');
      expect(const AppLocalizations(Locale('id')).settings, 'Pengaturan');
      expect(const AppLocalizations(Locale('vi')).settings, 'Cài đặt');
      expect(const AppLocalizations(Locale('ja')).settings, '設定');
      expect(const AppLocalizations(Locale('ar')).settings, 'الإعدادات');

      const delegate = AppLocalizationsDelegate();
      expect(delegate.isSupported(const Locale('de', 'DE')), isTrue);
      expect(delegate.isSupported(const Locale('xx', 'YY')), isFalse);
    });

    testWidgets('MaterialApp resolves RTL for every supported RTL locale', (
      tester,
    ) async {
      for (final language in <AppLanguagePreference>[
        AppLanguagePreference.arabic,
        AppLanguagePreference.urdu,
        AppLanguagePreference.hebrew,
        AppLanguagePreference.persian,
      ]) {
        late TextDirection direction;
        await tester.pumpWidget(
          MaterialApp(
            locale: language.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Builder(
              builder: (context) {
                direction = Directionality.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pump();
        expect(
          direction,
          TextDirection.rtl,
          reason: '${language.localeKey} must render right-to-left.',
        );
      }

      late TextDirection ltrDirection;
      await tester.pumpWidget(
        MaterialApp(
          locale: AppLanguagePreference.hindi.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) {
              ltrDirection = Directionality.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();
      expect(ltrDirection, TextDirection.ltr);
    });

    testWidgets('MaterialApp can load every selectable locale', (tester) async {
      for (final language in selectableAppLanguages) {
        late Locale resolvedLocale;
        await tester.pumpWidget(
          MaterialApp(
            locale: language.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Builder(
              builder: (context) {
                resolvedLocale = Localizations.localeOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason: '${language.localeKey} must load through Flutter delegates.',
        );
        expect(
          resolvedLocale.toLanguageTag(),
          language.locale!.toLanguageTag(),
          reason: '${language.localeKey} must not resolve to another locale.',
        );
      }
    });
  });

  group('stable runtime templates', () {
    const english = AppLocalizations(Locale('en'));
    const polish = AppLocalizations(Locale('pl'));
    const german = AppLocalizations(Locale('de'));

    test('localizes the stable catalog key before substituting values', () {
      expect(
        english.template(
          'Open chat with {name}',
          'Otwórz czat z użytkownikiem {name}',
          values: const {'name': 'Maja'},
        ),
        'Open chat with Maja',
      );
      expect(
        polish.template(
          'Open chat with {name}',
          'Otwórz czat z użytkownikiem {name}',
          values: const {'name': 'Maja'},
        ),
        'Otwórz czat z użytkownikiem Maja',
      );
      expect(
        german.template(
          'Open chat with {name}',
          'Otwórz czat z użytkownikiem {name}',
          values: const {'name': 'Maja'},
        ),
        'Chat mit Maja öffnen',
      );
    });

    test('substitution is single-pass for untrusted runtime content', () {
      expect(
        english.template(
          'Open chat with {name}',
          'Otwórz czat z użytkownikiem {name}',
          values: const {'name': r'{name} costs $5'},
        ),
        r'Open chat with {name} costs $5',
      );
    });

    test('rejects template and value placeholder mismatches', () {
      expect(
        () => english.template(
          'Open chat with {name}',
          'Otwórz czat z użytkownikiem {displayName}',
          values: const {'name': 'Maja'},
        ),
        throwsArgumentError,
      );
      expect(
        () => english.template(
          'Open chat with {name}',
          'Otwórz czat z użytkownikiem {name}',
          values: const {},
        ),
        throwsArgumentError,
      );
      expect(
        () => english.template(
          'Open chat with {name}',
          'Otwórz czat z użytkownikiem {name}',
          values: const {'name': 'Maja', 'unexpected': 'value'},
        ),
        throwsArgumentError,
      );
    });
  });

  group('plural smoke coverage', () {
    test('every locale formats calendar and relative dates safely', () async {
      final sample = DateTime(2026, 9, 1, 12);
      expect(
        () => const AppLocalizations(Locale('en')).calendarDate(sample),
        returnsNormally,
        reason: 'The fallback localization must initialize date data itself.',
      );
      const delegate = AppLocalizationsDelegate();
      for (final language in selectableAppLanguages) {
        final copy = await delegate.load(language.locale!);
        expect(
          () => copy.calendarDate(sample),
          returnsNormally,
          reason: '${language.localeKey} could not format a calendar date.',
        );
        expect(copy.relativeCompactTime(sample, now: sample), isNotEmpty);
      }
    });

    test('English and Polish retain their expected plural forms', () {
      const english = AppLocalizations(Locale('en'));
      const polish = AppLocalizations(Locale('pl'));

      expect(english.unreadConversations(1), '1 unread conversation');
      expect(english.unreadConversations(2), '2 unread conversations');
      expect(polish.unreadConversations(0), '0 nieprzeczytanych rozmów');
      expect(polish.unreadConversations(1), '1 nieprzeczytana rozmowa');
      expect(polish.unreadConversations(2), '2 nieprzeczytane rozmowy');
      expect(polish.unreadConversations(5), '5 nieprzeczytanych rozmów');
      expect(polish.unreadConversations(12), '12 nieprzeczytanych rozmów');
      expect(polish.unreadConversations(22), '22 nieprzeczytane rozmowy');
    });

    test(
      'every catalog resolves counts without placeholders or English leaks',
      () {
        const counts = <int>[0, 1, 2, 5, 11, 21, 22, 25, 101, 102];
        for (final language in selectableAppLanguages.where(
          (language) =>
              language != AppLanguagePreference.english &&
              language != AppLanguagePreference.polish,
        )) {
          final copy = AppLocalizations(language.locale!);
          for (final count in counts) {
            final conversations = copy.unreadConversations(count);
            final messages = copy.unreadMessages(count);
            for (final value in <String>[conversations, messages]) {
              expect(
                value,
                contains('$count'),
                reason: '${language.localeKey} omitted count $count: $value',
              );
              expect(value, isNot(contains('{count}')));
              expect(
                value.toLowerCase(),
                isNot(contains('unread')),
                reason: '${language.localeKey} fell back to English: $value',
              );
            }
          }
        }
      },
    );

    test('representative CLDR plural families select distinct forms', () {
      for (final language in <AppLanguagePreference>[
        AppLanguagePreference.russian,
        AppLanguagePreference.ukrainian,
        AppLanguagePreference.czech,
        AppLanguagePreference.slovak,
      ]) {
        final copy = AppLocalizations(language.locale!);
        expect(
          <String>{
            copy.unreadConversations(1),
            copy.unreadConversations(2),
            copy.unreadConversations(5),
          },
          hasLength(3),
          reason: '${language.localeKey} must exercise three plural forms.',
        );
      }

      const indonesian = AppLocalizations(Locale('id'));
      const vietnamese = AppLocalizations(Locale('vi'));
      expect(indonesian.unreadConversations(1), '1 percakapan belum dibaca');
      expect(indonesian.unreadConversations(5), '5 percakapan belum dibaca');
      expect(vietnamese.unreadMessages(1), '1 tin nhắn chưa đọc');
      expect(vietnamese.unreadMessages(5), '5 tin nhắn chưa đọc');
    });
  });
}
