import 'dart:ui' show Locale, PlatformDispatcher;

/// Every language that can be selected explicitly in YO Voice.
///
/// The enum names are persisted in SharedPreferences, so existing values must
/// never be renamed. New languages may safely be appended.
enum AppLanguagePreference {
  system,
  english,
  polish,
  german,
  spanish,
  portuguese,
  portugueseBrazil,
  french,
  italian,
  ukrainian,
  russian,
  czech,
  slovak,
  bulgarian,
  dutch,
  romanian,
  turkish,
  greek,
  hungarian,
  croatian,
  serbian,
  swedish,
  danish,
  norwegian,
  finnish,
  lithuanian,
  latvian,
  estonian,
  indonesian,
  vietnamese,
  chineseSimplified,
  chineseTraditional,
  japanese,
  korean,
  arabic,
  hindi,
  bengali,
  urdu,
  thai,
  malay,
  filipino,
  hebrew,
  persian,
  swahili;

  Locale? get locale => switch (this) {
    AppLanguagePreference.system => null,
    AppLanguagePreference.english => const Locale('en'),
    AppLanguagePreference.polish => const Locale('pl'),
    AppLanguagePreference.german => const Locale('de'),
    AppLanguagePreference.spanish => const Locale('es'),
    AppLanguagePreference.portuguese => const Locale('pt', 'PT'),
    AppLanguagePreference.portugueseBrazil => const Locale('pt', 'BR'),
    AppLanguagePreference.french => const Locale('fr'),
    AppLanguagePreference.italian => const Locale('it'),
    AppLanguagePreference.ukrainian => const Locale('uk'),
    AppLanguagePreference.russian => const Locale('ru'),
    AppLanguagePreference.czech => const Locale('cs'),
    AppLanguagePreference.slovak => const Locale('sk'),
    AppLanguagePreference.bulgarian => const Locale('bg'),
    AppLanguagePreference.dutch => const Locale('nl'),
    AppLanguagePreference.romanian => const Locale('ro'),
    AppLanguagePreference.turkish => const Locale('tr'),
    AppLanguagePreference.greek => const Locale('el'),
    AppLanguagePreference.hungarian => const Locale('hu'),
    AppLanguagePreference.croatian => const Locale('hr'),
    AppLanguagePreference.serbian => const Locale('sr'),
    AppLanguagePreference.swedish => const Locale('sv'),
    AppLanguagePreference.danish => const Locale('da'),
    AppLanguagePreference.norwegian => const Locale('nb'),
    AppLanguagePreference.finnish => const Locale('fi'),
    AppLanguagePreference.lithuanian => const Locale('lt'),
    AppLanguagePreference.latvian => const Locale('lv'),
    AppLanguagePreference.estonian => const Locale('et'),
    AppLanguagePreference.indonesian => const Locale('id'),
    AppLanguagePreference.vietnamese => const Locale('vi'),
    AppLanguagePreference.chineseSimplified => const Locale('zh', 'CN'),
    AppLanguagePreference.chineseTraditional => const Locale('zh', 'TW'),
    AppLanguagePreference.japanese => const Locale('ja'),
    AppLanguagePreference.korean => const Locale('ko'),
    AppLanguagePreference.arabic => const Locale('ar'),
    AppLanguagePreference.hindi => const Locale('hi'),
    AppLanguagePreference.bengali => const Locale('bn'),
    AppLanguagePreference.urdu => const Locale('ur'),
    AppLanguagePreference.thai => const Locale('th'),
    AppLanguagePreference.malay => const Locale('ms'),
    AppLanguagePreference.filipino => const Locale('fil'),
    AppLanguagePreference.hebrew => const Locale('he'),
    AppLanguagePreference.persian => const Locale('fa'),
    AppLanguagePreference.swahili => const Locale('sw'),
  };

  String get localeKey => switch (this) {
    AppLanguagePreference.system => 'system',
    AppLanguagePreference.portugueseBrazil => 'pt_BR',
    AppLanguagePreference.chineseSimplified => 'zh_CN',
    AppLanguagePreference.chineseTraditional => 'zh_TW',
    _ => locale!.languageCode,
  };

  String get nativeName => switch (this) {
    AppLanguagePreference.system => 'System',
    AppLanguagePreference.english => 'English',
    AppLanguagePreference.polish => 'Polski',
    AppLanguagePreference.german => 'Deutsch',
    AppLanguagePreference.spanish => 'Español',
    AppLanguagePreference.portuguese => 'Português (Portugal)',
    AppLanguagePreference.portugueseBrazil => 'Português (Brasil)',
    AppLanguagePreference.french => 'Français',
    AppLanguagePreference.italian => 'Italiano',
    AppLanguagePreference.ukrainian => 'Українська',
    AppLanguagePreference.russian => 'Русский',
    AppLanguagePreference.czech => 'Čeština',
    AppLanguagePreference.slovak => 'Slovenčina',
    AppLanguagePreference.bulgarian => 'Български',
    AppLanguagePreference.dutch => 'Nederlands',
    AppLanguagePreference.romanian => 'Română',
    AppLanguagePreference.turkish => 'Türkçe',
    AppLanguagePreference.greek => 'Ελληνικά',
    AppLanguagePreference.hungarian => 'Magyar',
    AppLanguagePreference.croatian => 'Hrvatski',
    AppLanguagePreference.serbian => 'Српски',
    AppLanguagePreference.swedish => 'Svenska',
    AppLanguagePreference.danish => 'Dansk',
    AppLanguagePreference.norwegian => 'Norsk bokmål',
    AppLanguagePreference.finnish => 'Suomi',
    AppLanguagePreference.lithuanian => 'Lietuvių',
    AppLanguagePreference.latvian => 'Latviešu',
    AppLanguagePreference.estonian => 'Eesti',
    AppLanguagePreference.indonesian => 'Bahasa Indonesia',
    AppLanguagePreference.vietnamese => 'Tiếng Việt',
    AppLanguagePreference.chineseSimplified => '简体中文',
    AppLanguagePreference.chineseTraditional => '繁體中文',
    AppLanguagePreference.japanese => '日本語',
    AppLanguagePreference.korean => '한국어',
    AppLanguagePreference.arabic => 'العربية',
    AppLanguagePreference.hindi => 'हिन्दी',
    AppLanguagePreference.bengali => 'বাংলা',
    AppLanguagePreference.urdu => 'اردو',
    AppLanguagePreference.thai => 'ไทย',
    AppLanguagePreference.malay => 'Bahasa Melayu',
    AppLanguagePreference.filipino => 'Filipino',
    AppLanguagePreference.hebrew => 'עברית',
    AppLanguagePreference.persian => 'فارسی',
    AppLanguagePreference.swahili => 'Kiswahili',
  };

  String get englishName => switch (this) {
    AppLanguagePreference.system => 'Device language',
    AppLanguagePreference.english => 'English',
    AppLanguagePreference.polish => 'Polish',
    AppLanguagePreference.german => 'German',
    AppLanguagePreference.spanish => 'Spanish',
    AppLanguagePreference.portuguese => 'Portuguese (Portugal)',
    AppLanguagePreference.portugueseBrazil => 'Portuguese (Brazil)',
    AppLanguagePreference.french => 'French',
    AppLanguagePreference.italian => 'Italian',
    AppLanguagePreference.ukrainian => 'Ukrainian',
    AppLanguagePreference.russian => 'Russian',
    AppLanguagePreference.czech => 'Czech',
    AppLanguagePreference.slovak => 'Slovak',
    AppLanguagePreference.bulgarian => 'Bulgarian',
    AppLanguagePreference.dutch => 'Dutch',
    AppLanguagePreference.romanian => 'Romanian',
    AppLanguagePreference.turkish => 'Turkish',
    AppLanguagePreference.greek => 'Greek',
    AppLanguagePreference.hungarian => 'Hungarian',
    AppLanguagePreference.croatian => 'Croatian',
    AppLanguagePreference.serbian => 'Serbian',
    AppLanguagePreference.swedish => 'Swedish',
    AppLanguagePreference.danish => 'Danish',
    AppLanguagePreference.norwegian => 'Norwegian Bokmål',
    AppLanguagePreference.finnish => 'Finnish',
    AppLanguagePreference.lithuanian => 'Lithuanian',
    AppLanguagePreference.latvian => 'Latvian',
    AppLanguagePreference.estonian => 'Estonian',
    AppLanguagePreference.indonesian => 'Indonesian',
    AppLanguagePreference.vietnamese => 'Vietnamese',
    AppLanguagePreference.chineseSimplified => 'Chinese (Simplified)',
    AppLanguagePreference.chineseTraditional => 'Chinese (Traditional)',
    AppLanguagePreference.japanese => 'Japanese',
    AppLanguagePreference.korean => 'Korean',
    AppLanguagePreference.arabic => 'Arabic',
    AppLanguagePreference.hindi => 'Hindi',
    AppLanguagePreference.bengali => 'Bengali',
    AppLanguagePreference.urdu => 'Urdu',
    AppLanguagePreference.thai => 'Thai',
    AppLanguagePreference.malay => 'Malay',
    AppLanguagePreference.filipino => 'Filipino',
    AppLanguagePreference.hebrew => 'Hebrew',
    AppLanguagePreference.persian => 'Persian',
    AppLanguagePreference.swahili => 'Swahili',
  };

  String get badge => switch (this) {
    AppLanguagePreference.system => 'A',
    AppLanguagePreference.portugueseBrazil => 'BR',
    AppLanguagePreference.chineseSimplified => '简',
    AppLanguagePreference.chineseTraditional => '繁',
    AppLanguagePreference.filipino => 'FIL',
    _ => locale!.languageCode.toUpperCase(),
  };

  /// Android's per-app language configuration uses BCP-47 region tags.
  String get androidLocaleTag => locale!.toLanguageTag();

  /// Apple uses script-based Chinese localization bundle names.
  String get iosLocalizationTag => switch (this) {
    AppLanguagePreference.chineseSimplified => 'zh-Hans',
    AppLanguagePreference.chineseTraditional => 'zh-Hant',
    _ => locale!.toLanguageTag(),
  };

  Locale get effectiveLocale =>
      locale ??
      resolveAppLocale(
        PlatformDispatcher.instance.locales,
        selectableAppLanguages.map((language) => language.locale!),
      );
}

const selectableAppLanguages = <AppLanguagePreference>[
  AppLanguagePreference.english,
  AppLanguagePreference.polish,
  AppLanguagePreference.german,
  AppLanguagePreference.spanish,
  AppLanguagePreference.portuguese,
  AppLanguagePreference.portugueseBrazil,
  AppLanguagePreference.french,
  AppLanguagePreference.italian,
  AppLanguagePreference.ukrainian,
  AppLanguagePreference.russian,
  AppLanguagePreference.czech,
  AppLanguagePreference.slovak,
  AppLanguagePreference.bulgarian,
  AppLanguagePreference.dutch,
  AppLanguagePreference.romanian,
  AppLanguagePreference.turkish,
  AppLanguagePreference.greek,
  AppLanguagePreference.hungarian,
  AppLanguagePreference.croatian,
  AppLanguagePreference.serbian,
  AppLanguagePreference.swedish,
  AppLanguagePreference.danish,
  AppLanguagePreference.norwegian,
  AppLanguagePreference.finnish,
  AppLanguagePreference.lithuanian,
  AppLanguagePreference.latvian,
  AppLanguagePreference.estonian,
  AppLanguagePreference.indonesian,
  AppLanguagePreference.vietnamese,
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

AppLanguagePreference languagePreferenceForLocale(Locale locale) {
  if (locale.languageCode == 'zh') {
    final script = locale.scriptCode?.toLowerCase();
    final region = locale.countryCode?.toUpperCase();
    if (script == 'hant' || const {'TW', 'HK', 'MO'}.contains(region)) {
      return AppLanguagePreference.chineseTraditional;
    }
    return AppLanguagePreference.chineseSimplified;
  }
  if (locale.languageCode == 'pt') {
    return locale.countryCode?.toUpperCase() == 'BR'
        ? AppLanguagePreference.portugueseBrazil
        : AppLanguagePreference.portuguese;
  }
  return selectableAppLanguages.firstWhere(
    (language) => language.locale!.languageCode == locale.languageCode,
    orElse: () => AppLanguagePreference.english,
  );
}

String localizationKeyForLocale(Locale locale) =>
    languagePreferenceForLocale(locale).localeKey;

/// Resolves the device locale through YO Voice's region/script-aware catalog.
///
/// Flutter's generic resolver cannot infer that `zh-Hant-HK` should use the
/// app's `zh-TW` translation when the selectable entries are region-based.
/// Keeping the rule here also guarantees the same English fallback as the
/// persisted language preference parser.
Locale resolveAppLocale(
  List<Locale>? preferredLocales,
  Iterable<Locale> supportedLocales,
) {
  if (preferredLocales == null || preferredLocales.isEmpty) {
    return AppLanguagePreference.english.locale!;
  }
  final supportedLanguageCodes = supportedLocales
      .map((locale) => locale.languageCode)
      .toSet();
  for (final preferredLocale in preferredLocales) {
    if (!supportedLanguageCodes.contains(preferredLocale.languageCode)) {
      continue;
    }
    return languagePreferenceForLocale(preferredLocale).locale!;
  }
  return AppLanguagePreference.english.locale!;
}
