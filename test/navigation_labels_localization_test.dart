// Home "Tu i teraz" — Foundation. The five primary navigation labels
// (Start · Serwery · Czaty · Momenty · Więcej / Home · Servers · Chats ·
// Moments · More), the new `navigation.servers` catalog key in every
// translated locale, and the two Polish counters Home's copy will use.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/translations_mobile_navigation.dart';

void main() {
  group('five navigation labels', () {
    test('Polish and English, with the product heading untouched', () {
      const pl = AppLocalizations(Locale('pl'));
      const en = AppLocalizations(Locale('en'));
      expect(
        [
          pl.home,
          pl.navigationServers,
          pl.chats,
          pl.navigationYourMoments,
          pl.more,
        ],
        ['Start', 'Serwery', 'Czaty', 'Momenty', 'Więcej'],
      );
      expect(
        [
          en.home,
          en.navigationServers,
          en.chats,
          en.navigationYourMoments,
          en.more,
        ],
        ['Home', 'Servers', 'Chats', 'Moments', 'More'],
      );
      // O11: the destination heading inside Momenty stays the product name.
      expect(pl.moments, 'YO Moments');
      expect(en.moments, 'YO Moments');
      // The retained Rooms label (Odkrywaj's root) is unchanged.
      expect(pl.navigationRooms, 'Pokoje');
      expect(en.navigationRooms, 'Rooms');
    });

    test('navigation.servers is catalogued for every locale the file lists, '
        'never as the key itself', () {
      expect(mobileNavigationTranslationKeys, contains('navigation.servers'));
      expect(mobileNavigationTranslations, isNotEmpty);
      for (final entry in mobileNavigationTranslations.entries) {
        final value = entry.value['navigation.servers'];
        expect(value, isNotNull, reason: entry.key);
        expect(value!.trim(), isNotEmpty, reason: entry.key);
        expect(value, isNot('navigation.servers'), reason: entry.key);
      }
    });

    test('every supported locale resolves the Servers label to a word', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final label = AppLocalizations(locale).navigationServers;
        expect(label.trim(), isNotEmpty, reason: locale.toLanguageTag());
        expect(
          label,
          isNot('navigation.servers'),
          reason: locale.toLanguageTag(),
        );
      }
      expect(const AppLocalizations(Locale('de')).navigationServers, 'Server');
      expect(const AppLocalizations(Locale('uk')).navigationServers, 'Сервери');
      expect(const AppLocalizations(Locale('ar')).navigationServers, 'الخوادم');
    });
  });

  group('compact tab labels in the translated locales (O11 verified)', () {
    // The dock is five equal cells; a single word that fits one line at
    // 360 px is the contract. Values derive from each catalog's existing
    // "Your Moments" noun with the possessive dropped.
    const compactMoments = <String, String>{
      'de': 'Momente',
      'es': 'Momentos',
      'pt': 'Momentos',
      'pt_BR': 'Momentos',
      'fr': 'Moments',
      'it': 'Momenti',
      'uk': 'Моменти',
      'ru': 'Моменты',
      'cs': 'Momenty',
      'sk': 'Momenty',
      'bg': 'Моменти',
      'nl': 'Momenten',
      'ro': 'Momente',
      'tr': 'Anlar',
      'el': 'Στιγμές',
      'hu': 'Pillanatok',
      'hr': 'Trenuci',
      'sr': 'Тренуци',
      'sv': 'Ögonblick',
      'da': 'Øjeblikke',
      'nb': 'Øyeblikk',
      'fi': 'Hetket',
      'lt': 'Akimirkos',
      'lv': 'Mirkļi',
      'et': 'Hetked',
      'id': 'Momen',
      'vi': 'Khoảnh khắc',
      'zh_CN': '时刻',
      'zh_TW': '時刻',
      'ja': 'モーメント',
      'ko': '모먼트',
      'ar': 'اللحظات',
      'hi': 'पल',
      'bn': 'মুহূর্ত',
      'ur': 'لمحات',
      'th': 'ช่วงเวลา',
      'ms': 'Detik',
      'fil': 'Mga sandali',
      'he': 'רגעים',
      'fa': 'لحظه‌ها',
      'sw': 'Matukio',
    };

    test(
      'navigation.yourMoments is the compact noun, never the possessive',
      () {
        expect(
          mobileNavigationTranslations.keys.toSet(),
          compactMoments.keys.toSet(),
        );
        for (final entry in mobileNavigationTranslations.entries) {
          expect(
            entry.value['navigation.yourMoments'],
            compactMoments[entry.key],
            reason: entry.key,
          );
        }
      },
    );

    test('every primary label stays within the dock label budget', () {
      // 12 characters is the longest label that lays out on one line in a
      // 72 px cell at 11 px/w700; longer words break mid-word or flip the
      // whole dock into its expanded label row.
      for (final locale in AppLocalizations.supportedLocales) {
        final copy = AppLocalizations(locale);
        for (final label in <String>[
          copy.home,
          copy.navigationServers,
          copy.chats,
          copy.navigationYourMoments,
          copy.more,
        ]) {
          expect(label.trim(), isNotEmpty, reason: locale.toLanguageTag());
          expect(
            label.length,
            lessThanOrEqualTo(12),
            reason:
                '${locale.toLanguageTag()}: "$label" exceeds the dock label budget.',
          );
        }
      }
    });
  });

  group('Polish counters', () {
    const table = [1, 2, 4, 5, 12, 14, 22, 25, 101, 112];

    test('peopleCount declines osoba / osoby / osób', () {
      const pl = AppLocalizations(Locale('pl'));
      expect(table.map(pl.peopleCount), [
        '1 osoba',
        '2 osoby',
        '4 osoby',
        '5 osób',
        '12 osób',
        '14 osób',
        '22 osoby',
        '25 osób',
        '101 osób',
        '112 osób',
      ]);
      const en = AppLocalizations(Locale('en'));
      expect(table.map(en.peopleCount), [
        '1 member',
        '2 members',
        '4 members',
        '5 members',
        '12 members',
        '14 members',
        '22 members',
        '25 members',
        '101 members',
        '112 members',
      ]);
    });

    test('secondsCount declines sekunda / sekundy / sekund', () {
      const pl = AppLocalizations(Locale('pl'));
      expect(table.map(pl.secondsCount), [
        '1 sekunda',
        '2 sekundy',
        '4 sekundy',
        '5 sekund',
        '12 sekund',
        '14 sekund',
        '22 sekundy',
        '25 sekund',
        '101 sekund',
        '112 sekund',
      ]);
      const en = AppLocalizations(Locale('en'));
      expect(table.map(en.secondsCount), [
        '1 second',
        '2 seconds',
        '4 seconds',
        '5 seconds',
        '12 seconds',
        '14 seconds',
        '22 seconds',
        '25 seconds',
        '101 seconds',
        '112 seconds',
      ]);
    });
  });
}
