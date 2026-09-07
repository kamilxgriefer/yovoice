import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_auth_call_release.dart';
import 'package:yovoice/core/localization/translations/translations_current_release.dart';
import 'package:yovoice/core/localization/translations/translations_direct_call_refusals.dart';
import 'package:yovoice/core/localization/translations/translations_home.dart';
import 'package:yovoice/core/localization/translations/translations_mobile_navigation.dart';
import 'package:yovoice/core/localization/translations/translations_moments_creation.dart';
import 'package:yovoice/core/localization/translations/translations_reels.dart';
import 'package:yovoice/core/localization/translations/translations_yo_moments.dart';

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
    test('Moment creation copy covers all 43 selectable locale variants', () {
      final translatedLocaleKeys = selectableAppLanguages
          .where(
            (language) =>
                language != AppLanguagePreference.english &&
                language != AppLanguagePreference.polish,
          )
          .map((language) => language.localeKey)
          .toSet();
      expect(AppLocalizations.supportedLocales, hasLength(43));
      expect(momentsCreationTranslations.keys.toSet(), translatedLocaleKeys);
      expect(momentsCreationTranslationKeys.toSet(), hasLength(156));
      expect(momentsCreationTranslationKeys, hasLength(156));
      expect(appTranslationKeys, containsAll(momentsCreationTranslationKeys));
      for (final localeKey in translatedLocaleKeys) {
        final entries = momentsCreationTranslations[localeKey]!;
        expect(entries.keys.toSet(), momentsCreationTranslationKeys.toSet());
        for (final key in momentsCreationTranslationKeys) {
          final value = entries[key]!;
          expect(value.trim(), isNotEmpty, reason: '$localeKey: $key');
          expect(_placeholders(value), _placeholders(key));
          expect(translatedPhrase(localeKey, key), value);
          if (key.length > 10) {
            expect(value, isNot(key), reason: '$localeKey: no fallback');
          }
        }
      }
    });

    test(
      'Moment creation keys do not override existing release terminology',
      () {
        final existingFeatureKeys = <String>{
          ...currentReleaseTranslationKeys,
          ...currentReleaseCompactTranslationKeys,
          ...currentReleaseChatMediaTranslationKeys,
          ...authCallReleaseTranslationKeys,
          ...directCallRefusalTranslationKeys,
          ...reelsTranslationKeys,
          ...yoMomentsTranslationKeys,
          ...mobileNavigationTranslationKeys,
          ...homeTranslationKeys,
        };
        expect(
          momentsCreationTranslationKeys.toSet().intersection(
            existingFeatureKeys,
          ),
          isEmpty,
        );
      },
    );

    test('creation stages preserve the reviewed English and Polish copy', () {
      const copyPairs = <String, String>{
        "This draft belongs to a previous session. Discard it and create a new Reel.":
            "Ten szkic pochodzi z poprzedniej sesji. Odrzuć go i utwórz nowego Reela.",
        'Record': 'Nagraj',
        'Review': 'Sprawdź',
        'Your recording': 'Twoje nagranie',
        'Media': 'Multimedia',
        'Edit': 'Edytuj',
        'Crop': 'Kadr',
        'Audio': 'Dźwięk',
        'Text and links': 'Tekst i linki',
        'Reset crop': 'Resetuj kadr',
        'Pinch to zoom, drag to position.':
            'Uszczypnij, aby powiększyć, i przeciągnij, aby ustawić kadr.',
        'Zoom in to reposition the frame.':
            'Powiększ, aby zmienić położenie kadru.',
        'Preview Reel': 'Podgląd Reela',
        'Retry preview': 'Ponów podgląd',
        'Play preview': 'Odtwórz podgląd',
        'Pause preview': 'Wstrzymaj podgląd',
        'Photos up to 10 MB. Videos: 1 second – 5 minutes, up to 100 MB.':
            'Zdjęcia do 10 MB. Filmy: od 1 sekundy do 5 minut, do 100 MB.',
        'Use your own MP3, M4A or WAV: 1 second – 5 minutes, up to 15 MB.':
            'Dodaj własny plik MP3, M4A lub WAV: od 1 sekundy do 5 minut, do 15 MB.',
        'Preparing audio': 'Przygotowywanie dźwięku',
        'Your Reels': 'Twoje Reels',
        'No Reels of your own yet': 'Nie masz jeszcze własnych Reels',
        'More Reels are available to check.': 'Możesz sprawdzić kolejne Reels.',
        'Load more': 'Wczytaj więcej',
        'Replace media?': 'Zmienić multimedia?',
        'Your caption, audio and overlays stay. Crop and video trim will reset.':
            'Opis, dźwięk i nakładki zostaną zachowane. Kadr i przycięcie filmu zostaną zresetowane.',
        'Discard this draft?': 'Odrzucić ten szkic?',
        'Your unpublished changes will be lost.':
            'Nieopublikowane zmiany zostaną utracone.',
        'Audio credit (optional)': 'Autor dźwięku (opcjonalnie)',
        'Sign in again before publishing.':
            'Zaloguj się ponownie przed publikacją.',
        'Check your email verification and account permissions before publishing.':
            'Przed publikacją sprawdź weryfikację adresu e-mail i uprawnienia konta.',
        'You have reached the publishing limit. Try again later.':
            'Osiągnięto limit publikacji. Spróbuj ponownie później.',
        'Check your media and audio rights, then try again.':
            'Sprawdź multimedia i prawa do dźwięku, a następnie spróbuj ponownie.',
        'Check your connection and retry. Your draft is kept.':
            'Sprawdź połączenie i ponów próbę. Twój szkic został zachowany.',
        'Confirm that you may use the backing audio.':
            'Potwierdź, że masz prawo użyć podkładu dźwiękowego.',
        'The Reel could not be prepared. Try again.':
            'Nie udało się przygotować Reela. Spróbuj ponownie.',
        "Choose Reel media": "Wybierz multimedia Reela",
        "Enter a label and a public HTTPS link.":
            "Wpisz nazwę i publiczny link HTTPS.",
        "Text size": "Rozmiar tekstu",
        "Crop zoom": "Powiększenie kadru",
        "Horizontal crop position": "Pozioma pozycja kadru",
        "Vertical crop position": "Pionowa pozycja kadru",
        "Video trim range": "Zakres przycięcia filmu",
        "Original video audio": "Dźwięk z filmu",
        "Original video audio volume": "Głośność dźwięku z filmu",
        "24 hours": "24 godziny",
        "7 days": "7 dni",
        "30 days": "30 dni",
        "Until deleted": "Do usunięcia",
        "{hours} hours": "{hours} godz.",
        "Availability is locked for this retry.":
            "Dostępność jest zablokowana dla tej ponownej próby.",
        "Choose how long this Reel remains available.":
            "Wybierz, jak długo ten Reel ma być dostępny.",
        "Available for": "Dostępny przez",
        "Custom": "Własny czas",
        "Custom · {hours}h": "Własny · {hours} godz.",
        "Choose 24–720 whole hours or 1–30 whole days.":
            "Wybierz 24–720 pełnych godzin lub 1–30 pełnych dni.",
        "Custom availability": "Własny czas",
        "Duration": "Czas",
        "Unit": "Jednostka",
        "Hours": "Godziny",
        "Days": "Dni",
        "Apply": "Zastosuj",
        "Backing audio volume": "Głośność podkładu",
        "Audio start": "Początek podkładu",
        "Backing audio start position": "Początek podkładu dźwiękowego",
        "Refresh": "Odśwież",
        "Enter a whole number.": "Wpisz liczbę całkowitą.",
        "Choose between 24 and 720 hours.": "Wybierz od 24 do 720 godzin.",
        "Choose between 1 and 30 days.": "Wybierz od 1 do 30 dni.",
        "Choose a valid duration.": "Wybierz prawidłowy czas dostępności.",
        "Preview could not be played on this device. You can try again, record a new take, or publish this one.":
            "Nie udało się odtworzyć podglądu na tym urządzeniu. Spróbuj ponownie, nagraj nową wersję albo opublikuj tę.",
        "Recording could not be started.":
            "Nie udało się rozpocząć nagrywania.",
        "Try again.": "Spróbuj ponownie.",
        "Ten seconds left.": "Pozostało dziesięć sekund.",
        "No sound is reaching the microphone. Check that the right microphone is selected and not muted.":
            "Mikrofon nie odbiera dźwięku. Sprawdź, czy wybrano właściwy mikrofon i czy nie jest wyciszony.",
        "Microphone level is unavailable, so YO Voice cannot tell you whether sound is being picked up. Recording continues.":
            "Poziom mikrofonu jest niedostępny, więc YO Voice nie może sprawdzić, czy dźwięk jest odbierany. Nagrywanie trwa dalej.",
        "Recording could not be finished.":
            "Nie udało się zakończyć nagrywania.",
        "Record again.": "Nagraj ponownie.",
        "That was too short to publish — a Voice Moment needs at least one second.":
            "Nagranie jest za krótkie — Voice Moment musi trwać co najmniej sekundę.",
        "Hold on a little longer this time.":
            "Tym razem nagrywaj odrobinę dłużej.",
        "Microphone request cancelled.":
            "Anulowano prośbę o dostęp do mikrofonu.",
        "Record Voice Moment": "Nagraj Voice Moment",
        "Listen before publishing": "Posłuchaj przed publikacją",
        "Share your voice": "Podziel się swoim głosem",
        "Record a voice reply up to 60 seconds long.":
            "Nagraj odpowiedź głosową trwającą do 60 sekund.",
        "Between 1 and 60 seconds.": "Od 1 do 60 sekund.",
        "Recording": "Nagrywanie",
        "Input level": "Poziom wejścia",
        "Remaining": "Pozostało",
        "Checking whether this device can record…":
            "Sprawdzamy, czy to urządzenie może nagrywać…",
        "Recording is not available here": "Nagrywanie nie jest tutaj dostępne",
        "Go back": "Wróć",
        "Somewhere quiet records best.":
            "Najlepszą jakość uzyskasz w cichym miejscu.",
        "Published straight to your feed.":
            "Publikacja trafi bezpośrednio do Twojego kanału.",
        "Before you start": "Zanim zaczniesz",
        "Recording length": "Długość nagrania",
        "Pause recording preview": "Wstrzymaj podgląd nagrania",
        "Play recording preview": "Odtwórz podgląd nagrania",
        "Recording preview position": "Pozycja podglądu nagrania",
        "No sound detected — check your microphone.":
            "Nie wykryto dźwięku — sprawdź mikrofon.",
        "Stop recording": "Zatrzymaj nagrywanie",
        "Start recording": "Rozpocznij nagrywanie",
        "Waiting for microphone access…": "Czekamy na dostęp do mikrofonu…",
        "Recording — tap to stop.": "Nagrywanie — dotknij, aby zatrzymać.",
        "Preview your take, then publish — or record again.":
            "Odsłuchaj nagranie, a potem opublikuj je lub nagraj ponownie.",
        "Publishing your Voice Moment…": "Publikujemy Twój Voice Moment…",
        "Tap the microphone to start.": "Dotknij mikrofonu, aby rozpocząć.",
        "Add a caption…": "Dodaj opis…",
        "Choose how long this Moment stays visible in the feed.":
            "Wybierz, jak długo ten Moment ma być widoczny w kanale.",
        "This Moment will stay visible in the feed until you delete it.":
            "Ten Moment pozostanie widoczny w kanale, dopóki go nie usuniesz.",
        "Timed": "Na określony czas",
        "Caption is locked for this retry.":
            "Opis jest zablokowany podczas tej ponownej próby.",
        "Caption and availability are locked for this retry.":
            "Opis i czas dostępności są zablokowane podczas tej ponownej próby.",
        "Record again": "Nagraj ponownie",
        "Publishing…": "Publikowanie…",
        "Publish": "Opublikuj",
        "Microphone level": "Poziom mikrofonu",
        "Microphone level, not recording":
            "Poziom mikrofonu, nagrywanie wyłączone",
        "Voice Moment posted.": "Voice Moment opublikowany.",
        "Caption limit reached: {limit} characters.":
            "Osiągnięto limit opisu: {limit} znaków.",
        "Reply to {author}": "Odpowiedz: {author}",
        "{elapsed} of {limit} seconds": "{elapsed} z {limit} sekund",
        "{count} of {limit} characters": "{count} z {limit} znaków",
        "Visibility: {hours} h": "Widoczność: {hours} godz.",
        "Availability: {label}": "Dostępność: {label}",
        "Microphone access for YO Voice is blocked in this browser.":
            "Dostęp YO Voice do mikrofonu jest zablokowany w tej przeglądarce.",
        "Allow the microphone in your browser's site settings for YO Voice, then reload this page.":
            "Zezwól na używanie mikrofonu w ustawieniach witryny YO Voice w przeglądarce, a następnie odśwież stronę.",
        "YO Voice does not have permission to use your microphone.":
            "YO Voice nie ma uprawnień do używania mikrofonu.",
        "Allow the microphone for YO Voice in your device settings.":
            "Zezwól aplikacji YO Voice na używanie mikrofonu w ustawieniach urządzenia.",
        "The microphone request was dismissed, so recording could not start.":
            "Prośba o dostęp do mikrofonu została zamknięta, więc nagrywanie nie mogło się rozpocząć.",
        "Start recording again, then choose Allow.":
            "Rozpocznij nagrywanie ponownie, a następnie wybierz Zezwól.",
        "No microphone was found on this device.":
            "Nie znaleziono mikrofonu na tym urządzeniu.",
        "Connect a microphone, then start recording again.":
            "Podłącz mikrofon, a następnie rozpocznij nagrywanie ponownie.",
        "Your microphone could not be opened — another app is probably using it.":
            "Nie można uruchomić mikrofonu — prawdopodobnie korzysta z niego inna aplikacja.",
        "Close the other app, then start recording again.":
            "Zamknij inną aplikację, a następnie rozpocznij nagrywanie ponownie.",
        "Your browser did not answer the microphone request.":
            "Przeglądarka nie odpowiedziała na prośbę o dostęp do mikrofonu.",
        "YO Voice could not open your microphone.":
            "YO Voice nie może uruchomić mikrofonu.",
        "That recording could not be used. Record again and speak for at least a second.":
            "Nie można użyć tego nagrania. Nagraj ponownie i mów przez co najmniej sekundę.",
        "That recording is larger than the 12 MB limit for a Voice Moment.":
            "To nagranie przekracza limit 12 MB dla Voice Momentu.",
        "Record a shorter Voice Moment.": "Nagraj krótszy Voice Moment.",
        "This recording format cannot be published.":
            "Tego formatu nagrania nie można opublikować.",
        "Open YO Voice in Chrome, Edge or Safari to record.":
            "Otwórz YO Voice w Chrome, Edge lub Safari, aby nagrywać.",
        "Microphone access needs a secure (https) connection.":
            "Dostęp do mikrofonu wymaga bezpiecznego połączenia (https).",
        "Open YO Voice over https and try again.":
            "Otwórz YO Voice przez https i spróbuj ponownie.",
        "This browser cannot record MP4/AAC audio.":
            "Ta przeglądarka nie może nagrywać dźwięku MP4/AAC.",
        "Voice recording is not available on this device.":
            "Nagrywanie głosu nie jest dostępne na tym urządzeniu.",
        "YO Voice could not reach an audio recorder on this device.":
            "YO Voice nie może skorzystać z nagrywania dźwięku na tym urządzeniu.",
        "You have reached the limit of active Moments. A slot frees up when one expires or you delete one.":
            "Osiągnięto limit aktywnych Momentów. Miejsce zwolni się, gdy jeden z nich wygaśnie lub go usuniesz.",
        "Your recording is kept — publish it once a slot frees up.":
            "Nagranie zostało zachowane — opublikuj je, gdy zwolni się miejsce.",
        "You must be signed in to publish a Voice Moment.":
            "Musisz się zalogować, aby opublikować Voice Moment.",
        "Your Voice Moment could not be published.":
            "Nie udało się opublikować Voice Momentu.",
        "Your recording is still here — try publishing again.":
            "Nagranie zostało zachowane — spróbuj opublikować je ponownie.",
        "Publishing took too long and was stopped safely.":
            "Publikacja trwała zbyt długo i została bezpiecznie zatrzymana.",
        "Silent": "Cisza",
        "Quiet": "Cicho",
        "Good level": "Dobry poziom",
        "Input level unavailable": "Poziom wejścia niedostępny",
      };
      expect(copyPairs.keys.toSet(), momentsCreationTranslationKeys.toSet());
      for (final locale in AppLocalizations.supportedLocales) {
        final copy = AppLocalizations(locale);
        for (final pair in copyPairs.entries) {
          final actual = copy.text(pair.key, pair.value);
          expect(actual, switch (locale.languageCode) {
            'en' => pair.key,
            'pl' => pair.value,
            _ => momentsCreationTranslations[copy.localeKey]![pair.key],
          });
          final names = _placeholders(
            pair.key,
          ).map((token) => token.substring(1, token.length - 1)).toSet();
          if (names.isNotEmpty) {
            // Runtime names/counters are inserted once and never translated
            // or interpreted as another catalog template.
            const content = r'Żółć أسماء {untouched} $value';
            final rendered = copy.template(
              pair.key,
              pair.value,
              values: {for (final name in names) name: content},
            );
            expect(rendered, contains(content));
            for (final name in names) {
              expect(rendered, isNot(contains('{$name}')));
            }
          }
        }
      }
    });

    test('Home copy covers every translated locale explicitly', () {
      final translatedLocaleKeys = selectableAppLanguages
          .where(
            (language) =>
                language != AppLanguagePreference.english &&
                language != AppLanguagePreference.polish,
          )
          .map((language) => language.localeKey)
          .toSet();
      expect(homeTranslations.keys.toSet(), translatedLocaleKeys);
      expect(appTranslationKeys, containsAll(homeTranslationKeys));
      for (final localeKey in translatedLocaleKeys) {
        expect(
          homeTranslations[localeKey]!.keys.toSet(),
          homeTranslationKeys.toSet(),
          reason: localeKey,
        );
        for (final key in homeTranslationKeys) {
          final value = translatedPhrase(localeKey, key);
          expect(value, isNotNull, reason: '$localeKey: $key');
          expect(value!.trim(), isNotEmpty, reason: '$localeKey: $key');
          expect(_placeholders(value), _placeholders(key));
        }
      }
    });

    test('Home labels resolve in all 43 locales with reviewed EN/PL copy', () {
      List<String> labels(AppLocalizations copy) => [
        copy.homeLiveForYou,
        copy.homeYourCircle,
        copy.homeCreateRoom,
        copy.homeStartConversation,
        copy.homeGrowYourCircle,
        copy.homeYou,
      ];

      final english = labels(const AppLocalizations(Locale('en')));
      expect(english, [
        'Live for you',
        'Your circle',
        'Create room',
        'Invite and talk',
        'Grow your circle',
        'You',
      ]);
      expect(labels(const AppLocalizations(Locale('pl'))), [
        'Na żywo dla Ciebie',
        'Twój krąg',
        'Stwórz pokój',
        'Zaproś i rozmawiaj',
        'Powiększ swój krąg',
        'Ty',
      ]);
      expect(AppLocalizations.supportedLocales, hasLength(43));
      for (final locale in AppLocalizations.supportedLocales) {
        final values = labels(AppLocalizations(locale));
        for (var index = 0; index < values.length; index++) {
          expect(values[index].trim(), isNotEmpty);
          if (locale.languageCode != 'en') {
            expect(
              values[index],
              isNot(english[index]),
              reason:
                  '${locale.toLanguageTag()}: ${homeTranslationKeys[index]}',
            );
          }
        }
      }
    });

    test(
      'mobile navigation copy covers every translated locale explicitly',
      () {
        final translatedLocaleKeys = selectableAppLanguages
            .where(
              (language) =>
                  language != AppLanguagePreference.english &&
                  language != AppLanguagePreference.polish,
            )
            .map((language) => language.localeKey)
            .toSet();
        expect(mobileNavigationTranslations.keys.toSet(), translatedLocaleKeys);
        expect(
          appTranslationKeys,
          containsAll(mobileNavigationTranslationKeys),
        );
        for (final localeKey in translatedLocaleKeys) {
          expect(
            mobileNavigationTranslations[localeKey]!.keys.toSet(),
            mobileNavigationTranslationKeys.toSet(),
          );
          for (final key in mobileNavigationTranslationKeys) {
            final value = translatedPhrase(localeKey, key);
            expect(value, isNotNull, reason: '$localeKey: $key');
            expect(value!.trim(), isNotEmpty, reason: '$localeKey: $key');
            expect(
              value,
              isNot(key),
              reason: '$localeKey: no English fallback',
            );
          }
        }
      },
    );

    test('mobile Rooms label never falls back to English in other locales', () {
      expect(const AppLocalizations(Locale('en')).navigationRooms, 'Rooms');
      expect(const AppLocalizations(Locale('pl')).navigationRooms, 'Pokoje');
      expect(const AppLocalizations(Locale('ar')).navigationRooms, 'الغرف');
      for (final locale in AppLocalizations.supportedLocales) {
        final label = AppLocalizations(locale).navigationRooms;
        expect(label.trim(), isNotEmpty, reason: locale.toLanguageTag());
        if (locale.languageCode != 'en') {
          expect(label, isNot('Rooms'), reason: locale.toLanguageTag());
        }
      }
    });

    test(
      'mobile tab label is localized without changing the product brand',
      () {
        expect(
          const AppLocalizations(Locale('en')).navigationYourMoments,
          'Your Moments',
        );
        expect(
          const AppLocalizations(Locale('pl')).navigationYourMoments,
          'Twoje Momenty',
        );
        for (final locale in AppLocalizations.supportedLocales) {
          final copy = AppLocalizations(locale);
          expect(copy.navigationYourMoments.trim(), isNotEmpty);
          expect(copy.moments, 'YO Moments');
          if (locale.languageCode != 'en') {
            expect(
              copy.navigationYourMoments,
              isNot('Your Moments'),
              reason: locale.toLanguageTag(),
            );
          }
        }
      },
    );

    test('mobile create guidance names the translated destination', () {
      const source =
          'Create a Voice Room here. Open Your Moments to record a Voice Moment.';
      const polish =
          'Tutaj utworzysz pokój głosowy. Otwórz Twoje Momenty, aby nagrać Voice Moment.';
      for (final locale in AppLocalizations.supportedLocales) {
        final copy = AppLocalizations(locale);
        final body = copy.text(source, polish);
        expect(
          body,
          contains(copy.navigationYourMoments),
          reason: '${locale.toLanguageTag()} must match the visible tab label.',
        );
        expect(body, contains('Voice Moment'));
        if (locale.languageCode != 'en') {
          expect(body, isNot(source), reason: locale.toLanguageTag());
        }
        if (locale.languageCode != 'en' && locale.languageCode != 'pl') {
          expect(
            translatedPhrase(
              copy.localeKey,
              'Create a Voice Moment or start a Voice Room here.',
            ),
            isNotNull,
            reason: 'Existing desktop creation guidance remains available.',
          );
        }
      }
    });

    test('YO Moments copy is explicit in every translated locale', () {
      final translatedLocaleKeys = selectableAppLanguages
          .where(
            (language) =>
                language != AppLanguagePreference.english &&
                language != AppLanguagePreference.polish,
          )
          .map((language) => language.localeKey)
          .toSet();

      expect(yoMomentsTranslations.keys.toSet(), translatedLocaleKeys);
      expect(yoMomentsTranslationKeys, const <String>[
        'yoMoments.voiceFormat',
        'yoMoments.fromCircle',
      ]);
      for (final localeKey in translatedLocaleKeys) {
        for (final key in yoMomentsTranslationKeys) {
          final value = translatedPhrase(localeKey, key);
          expect(
            value,
            isNotNull,
            reason: '$localeKey must explicitly translate $key.',
          );
          expect(value!.trim(), isNotEmpty);
        }
      }
    });

    test('circle heading is localized across all 43 selectable locales', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final copy = AppLocalizations(locale);
        final value = copy.yoMomentsFromYourCircle;
        expect(value.trim(), isNotEmpty, reason: locale.toLanguageTag());
        if (locale.languageCode != 'en') {
          expect(
            value,
            isNot('YO Moments from your circle'),
            reason: '${locale.toLanguageTag()} must not use English fallback.',
          );
        }
      }
    });

    test('YO Moments brand name is invariant in all 43 locales', () {
      for (final locale in AppLocalizations.supportedLocales) {
        expect(AppLocalizations(locale).moments, 'YO Moments');
      }
    });

    test('Voice format translation cannot leak into unrelated Voice copy', () {
      const german = AppLocalizations(Locale('de'));
      expect(
        german.contextualText('yoMoments.voiceFormat', 'Voice', 'Głos'),
        'Stimme',
      );
      expect(german.text('Voice', 'Głos'), 'Voice');
      expect(
        const AppLocalizations(
          Locale('en'),
        ).contextualText('yoMoments.voiceFormat', 'Voice', 'Głos'),
        'Voice',
      );
      expect(
        const AppLocalizations(
          Locale('pl'),
        ).contextualText('yoMoments.voiceFormat', 'Voice', 'Głos'),
        'Głos',
      );
    });

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
        ...momentsCreationTranslationKeys,
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
        // Established Malay and Filipino media-editor loanwords, not fallback.
        'ms|Media',
        'ms|Audio',
        'ms|Unit',
        'fil|Media',
        'fil|Audio',
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
