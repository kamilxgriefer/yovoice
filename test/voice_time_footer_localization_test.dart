import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_voice_time_footer.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_time_labels.dart';

// Explicit expected outputs, not obtained from the production catalog/helper.
const _expected = <String, Map<String, Object>>{
  "en": {
    "now": "now",
    "minuteAge": <String>["now", "1m ago", "2m ago", "5m ago"],
    "hourAge": <String>["now", "1h ago", "2h ago", "5h ago"],
    "dayAge": <String>["now", "1d ago", "2d ago", "5d ago"],
    "minuteExpiry": <String>[
      "Expires soon",
      "Expires in 1m",
      "Expires in 2m",
      "Expires in 5m",
    ],
    "hourExpiry": <String>[
      "Expires soon",
      "Expires in 1h",
      "Expires in 2h",
      "Expires in 5h",
    ],
    "dayExpiry": <String>[
      "Expires soon",
      "Expires in 24h",
      "Expires in 2d",
      "Expires in 5d",
    ],
    "dayTemplate": <String>[
      "Expires in 0d",
      "Expires in 1d",
      "Expires in 2d",
      "Expires in 5d",
    ],
    "age59": "59m ago",
    "age23": "23h ago",
    "expiry47": "Expires in 47h",
    "permanent": "Stays until deleted",
  },
  "pl": {
    "now": "teraz",
    "minuteAge": <String>["teraz", "1 min temu", "2 min temu", "5 min temu"],
    "hourAge": <String>[
      "teraz",
      "1 godz. temu",
      "2 godz. temu",
      "5 godz. temu",
    ],
    "dayAge": <String>["teraz", "1 dzień temu", "2 dni temu", "5 dni temu"],
    "minuteExpiry": <String>[
      "Wkrótce wygaśnie",
      "Wygasa za 1 min",
      "Wygasa za 2 min",
      "Wygasa za 5 min",
    ],
    "hourExpiry": <String>[
      "Wkrótce wygaśnie",
      "Wygasa za 1 godz.",
      "Wygasa za 2 godz.",
      "Wygasa za 5 godz.",
    ],
    "dayExpiry": <String>[
      "Wkrótce wygaśnie",
      "Wygasa za 24 godz.",
      "Wygasa za 2 dni",
      "Wygasa za 5 dni",
    ],
    "dayTemplate": <String>[
      "Wygasa za 0 dni",
      "Wygasa za 1 dzień",
      "Wygasa za 2 dni",
      "Wygasa za 5 dni",
    ],
    "age59": "59 min temu",
    "age23": "23 godz. temu",
    "expiry47": "Wygasa za 47 godz.",
    "permanent": "Dostępny do usunięcia",
  },
  "de": {
    "now": "jetzt",
    "minuteAge": <String>["jetzt", "vor 1 Min.", "vor 2 Min.", "vor 5 Min."],
    "hourAge": <String>["jetzt", "vor 1 Std.", "vor 2 Std.", "vor 5 Std."],
    "dayAge": <String>["jetzt", "vor 1 T.", "vor 2 T.", "vor 5 T."],
    "minuteExpiry": <String>[
      "Läuft bald ab",
      "Läuft in 1 Min. ab",
      "Läuft in 2 Min. ab",
      "Läuft in 5 Min. ab",
    ],
    "hourExpiry": <String>[
      "Läuft bald ab",
      "Läuft in 1 Std. ab",
      "Läuft in 2 Std. ab",
      "Läuft in 5 Std. ab",
    ],
    "dayExpiry": <String>[
      "Läuft bald ab",
      "Läuft in 24 Std. ab",
      "Läuft in 2 T. ab",
      "Läuft in 5 T. ab",
    ],
    "dayTemplate": <String>[
      "Läuft in 0 T. ab",
      "Läuft in 1 T. ab",
      "Läuft in 2 T. ab",
      "Läuft in 5 T. ab",
    ],
    "age59": "vor 59 Min.",
    "age23": "vor 23 Std.",
    "expiry47": "Läuft in 47 Std. ab",
    "permanent": "Bleibt bis zum Löschen",
  },
  "nl": {
    "now": "nu",
    "minuteAge": <String>[
      "nu",
      "1 min geleden",
      "2 min geleden",
      "5 min geleden",
    ],
    "hourAge": <String>[
      "nu",
      "1 uur geleden",
      "2 uur geleden",
      "5 uur geleden",
    ],
    "dayAge": <String>["nu", "1 d geleden", "2 d geleden", "5 d geleden"],
    "minuteExpiry": <String>[
      "Verloopt binnenkort",
      "Verloopt over 1 min",
      "Verloopt over 2 min",
      "Verloopt over 5 min",
    ],
    "hourExpiry": <String>[
      "Verloopt binnenkort",
      "Verloopt over 1 u",
      "Verloopt over 2 u",
      "Verloopt over 5 u",
    ],
    "dayExpiry": <String>[
      "Verloopt binnenkort",
      "Verloopt over 24 u",
      "Verloopt over 2 d",
      "Verloopt over 5 d",
    ],
    "dayTemplate": <String>[
      "Verloopt over 0 d",
      "Verloopt over 1 d",
      "Verloopt over 2 d",
      "Verloopt over 5 d",
    ],
    "age59": "59 min geleden",
    "age23": "23 uur geleden",
    "expiry47": "Verloopt over 47 u",
    "permanent": "Blijft tot verwijdering",
  },
  "ar": {
    "now": "الآن",
    "minuteAge": <String>["الآن", "منذ 1 د", "منذ 2 د", "منذ 5 د"],
    "hourAge": <String>["الآن", "منذ 1 س", "منذ 2 س", "منذ 5 س"],
    "dayAge": <String>["الآن", "منذ 1 ي", "منذ 2 ي", "منذ 5 ي"],
    "minuteExpiry": <String>[
      "تنتهي قريبًا",
      "تنتهي خلال 1 د",
      "تنتهي خلال 2 د",
      "تنتهي خلال 5 د",
    ],
    "hourExpiry": <String>[
      "تنتهي قريبًا",
      "تنتهي خلال 1 س",
      "تنتهي خلال 2 س",
      "تنتهي خلال 5 س",
    ],
    "dayExpiry": <String>[
      "تنتهي قريبًا",
      "تنتهي خلال 24 س",
      "تنتهي خلال 2 ي",
      "تنتهي خلال 5 ي",
    ],
    "dayTemplate": <String>[
      "تنتهي خلال 0 ي",
      "تنتهي خلال 1 ي",
      "تنتهي خلال 2 ي",
      "تنتهي خلال 5 ي",
    ],
    "age59": "منذ 59 د",
    "age23": "منذ 23 س",
    "expiry47": "تنتهي خلال 47 س",
    "permanent": "تبقى حتى حذفها",
  },
};
const _counts = [0, 1, 2, 5];

void main() {
  final now = DateTime.utc(2026, 9, 11, 14);
  test('Voice time/footer stable keys cover all 41 actual catalogs', () {
    const keys = {
      'Following',
      '{count} live Moment loaded.',
      '{count} live Moments loaded.',
      'That is the only live Moment right now.',
      'That is all {count} live Moments right now.',
      '{count}m ago',
      '{count}h ago',
      '{count}d ago',
      'Expires in {count}d',
      'Expires in {count}h',
      'Expires in {count}m',
      'now',
      'Expires soon',
      'Stays until deleted',
    };
    final placeholders = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');
    expect(appTranslations, hasLength(41));
    final addedKeys = keys.difference({
      '{count}m ago',
      '{count}h ago',
      '{count}d ago',
      'now',
    });
    expect(voiceTimeFooterTranslationKeys, hasLength(10));
    expect(voiceTimeFooterTranslationKeys.toSet(), addedKeys);
    expect(
      voiceTimeFooterTranslations.keys.toSet(),
      appTranslations.keys.toSet(),
    );
    for (final entry in appTranslations.entries) {
      expect(voiceTimeFooterTranslations[entry.key]!.keys.toSet(), addedKeys);
      for (final key in keys) {
        final value = entry.value[key];
        expect(value, isNotNull, reason: '${entry.key}: $key');
        expect(value!.trim(), isNotEmpty);
        expect(value, isNot(key), reason: '${entry.key}: no English fallback');
        expect(
          placeholders.allMatches(value).map((m) => m.group(0)).toList(),
          placeholders.allMatches(key).map((m) => m.group(0)).toList(),
        );
      }
    }
  });

  for (final locale in _expected.keys) {
    final expected = _expected[locale]!;
    final copy = AppLocalizations(Locale(locale));
    test('$locale time labels use actual localized 0 1 2 5 values', () {
      for (var index = 0; index < _counts.length; index++) {
        final count = _counts[index];
        for (final unit in ['minute', 'hour', 'day']) {
          final duration = switch (unit) {
            'minute' => Duration(minutes: count),
            'hour' => Duration(hours: count),
            _ => Duration(days: count),
          };
          expect(
            momentRelativeAge(now.subtract(duration), now: now, copy: copy),
            (expected['${unit}Age'] as List<String>)[index],
            reason: '$locale / $unit age / $count',
          );
          expect(
            momentExpiryLabel(now.add(duration), now: now, copy: copy),
            (expected['${unit}Expiry'] as List<String>)[index],
            reason: '$locale / $unit expiry / $count',
          );
        }
        expect(
          copy.template(
            'Expires in {count}d',
            count == 1 ? 'Wygasa za {count} dzień' : 'Wygasa za {count} dni',
            values: {'count': count},
          ),
          (expected['dayTemplate'] as List<String>)[index],
        );
      }
    });

    test('$locale time labels preserve null, future and expiry boundaries', () {
      expect(momentRelativeAge(null, now: now, copy: copy), '');
      expect(
        momentRelativeAge(
          now.add(const Duration(days: 2)),
          now: now,
          copy: copy,
        ),
        expected['now'],
      );
      expect(
        momentRelativeAge(
          now.subtract(const Duration(seconds: 59)),
          now: now,
          copy: copy,
        ),
        expected['now'],
      );
      expect(
        momentRelativeAge(
          now.subtract(const Duration(minutes: 59)),
          now: now,
          copy: copy,
        ),
        expected['age59'],
      );
      expect(
        momentRelativeAge(
          now.subtract(const Duration(minutes: 60)),
          now: now,
          copy: copy,
        ),
        (expected['hourAge'] as List<String>)[1],
      );
      expect(
        momentRelativeAge(
          now.subtract(const Duration(hours: 23, minutes: 59)),
          now: now,
          copy: copy,
        ),
        expected['age23'],
      );
      expect(
        momentRelativeAge(
          now.subtract(const Duration(hours: 24)),
          now: now,
          copy: copy,
        ),
        (expected['dayAge'] as List<String>)[1],
      );
      expect(momentExpiryLabel(null, now: now, copy: copy), isNull);
      expect(
        momentAvailabilityLabel(null, now: now, copy: copy),
        expected['permanent'],
      );
      for (final expired in [
        const Duration(microseconds: 1),
        const Duration(days: 1),
      ]) {
        expect(
          momentExpiryLabel(now.subtract(expired), now: now, copy: copy),
          isNull,
        );
        expect(
          momentAvailabilityLabel(now.subtract(expired), now: now, copy: copy),
          isNull,
        );
      }
      for (final soon in [Duration.zero, const Duration(seconds: 59)]) {
        expect(
          momentExpiryLabel(now.add(soon), now: now, copy: copy),
          (expected['minuteExpiry'] as List<String>)[0],
        );
      }
      expect(
        momentExpiryLabel(
          now.add(const Duration(minutes: 1)),
          now: now,
          copy: copy,
        ),
        (expected['minuteExpiry'] as List<String>)[1],
      );
      expect(
        momentExpiryLabel(
          now.add(const Duration(hours: 1)),
          now: now,
          copy: copy,
        ),
        (expected['hourExpiry'] as List<String>)[1],
      );
      for (final lastHours in [
        const Duration(hours: 47),
        const Duration(hours: 48) - const Duration(microseconds: 1),
      ]) {
        expect(
          momentExpiryLabel(now.add(lastHours), now: now, copy: copy),
          expected['expiry47'],
        );
      }
      for (final firstDays in [
        const Duration(hours: 48),
        const Duration(hours: 49),
      ]) {
        expect(
          momentExpiryLabel(now.add(firstDays), now: now, copy: copy),
          (expected['dayExpiry'] as List<String>)[2],
        );
        expect(
          momentAvailabilityLabel(now.add(firstDays), now: now, copy: copy),
          (expected['dayExpiry'] as List<String>)[2],
        );
      }
    });
  }

  test('null localization keeps the exact English time API contract', () {
    expect(momentRelativeAge(null, now: now), '');
    expect(
      momentRelativeAge(now.add(const Duration(days: 1)), now: now),
      'now',
    );
    expect(
      momentRelativeAge(now.subtract(const Duration(minutes: 5)), now: now),
      '5m ago',
    );
    expect(
      momentRelativeAge(now.subtract(const Duration(hours: 2)), now: now),
      '2h ago',
    );
    expect(
      momentRelativeAge(now.subtract(const Duration(days: 1)), now: now),
      '1d ago',
    );
    expect(momentExpiryLabel(null, now: now), isNull);
    expect(momentAvailabilityLabel(null, now: now), 'Stays until deleted');
    expect(
      momentExpiryLabel(
        now.subtract(const Duration(microseconds: 1)),
        now: now,
      ),
      isNull,
    );
    expect(momentExpiryLabel(now, now: now), 'Expires soon');
    expect(
      momentExpiryLabel(now.add(const Duration(minutes: 5)), now: now),
      'Expires in 5m',
    );
    expect(
      momentExpiryLabel(now.add(const Duration(hours: 47)), now: now),
      'Expires in 47h',
    );
    expect(
      momentExpiryLabel(now.add(const Duration(hours: 48)), now: now),
      'Expires in 2d',
    );
  });
}
