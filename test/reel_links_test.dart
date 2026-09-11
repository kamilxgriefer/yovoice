import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_reel_links.dart';
import 'package:yovoice/features/reels/data/reel_links.dart';

void main() {
  test('canonical link is the Flutter host with exactly one opaque ID', () {
    for (final id in ['A', 'reel_One-7', 'a' * 128]) {
      final link = buildReelLink(id);
      expect(link.toString(), 'https://app.yovoice.app/?reel=$id');
      expect(link.queryParametersAll, {
        'reel': [id],
      });
      expect(link.hasFragment, isFalse);
      expect(parseReelLink(link), id);
    }
  });

  test('invalid ids cannot become share URLs', () {
    for (final id in [
      '',
      'a' * 129,
      '../private',
      'a/b',
      'a?token=x',
      'a#secret',
      ' a',
      'a ',
      'a\n',
      'a\u0000',
      'żółć',
      'https://media.test/x',
    ]) {
      expect(isSafeReelLinkId(id), isFalse, reason: id);
      expect(() => buildReelLink(id), throwsArgumentError);
    }
  });

  test('untrusted URLs are not a generic redirect or capability transport', () {
    for (final value in [
      'https://yovoice.app/?reel=a',
      'https://www.app.yovoice.app/?reel=a',
      'https://app.yovoice.app.attacker.test/?reel=a',
      'https://app.yovoice.app@attacker.test/?reel=a',
      'https://user@app.yovoice.app/?reel=a',
      'http://app.yovoice.app/?reel=a',
      'file:///app.yovoice.app/?reel=a',
      'https://app.yovoice.app:8443/?reel=a',
      'https://app.yovoice.app/reels/a',
      'https://app.yovoice.app/?reel=a#token=x',
      'https://app.yovoice.app/?reel=a#',
      'https://app.yovoice.app/?reel=a&reel=b',
      'https://app.yovoice.app/?reel=a&reel=a',
      'https://app.yovoice.app/?reel=a&room=b',
      'https://app.yovoice.app/?reel=a&token=secret',
      'https://app.yovoice.app/?reel=a&redirect=https%3A%2F%2Fattacker.test',
      'https://app.yovoice.app/?reel=a&media=https%3A%2F%2Fstorage.test',
      'https://app.yovoice.app/?reel=',
      'https://app.yovoice.app/?reel=%2Fprivate',
      'https://app.yovoice.app/?reel=a%0A',
      'https://app.yovoice.app/?reel=%FF',
      'https://app.yovoice.app/?reel=${'x' * 129}',
      '/?reel=a',
    ]) {
      expect(parseReelLink(Uri.parse(value)), isNull, reason: value);
    }
  });

  test('all 43 locales have the same reviewed share and destination keys', () {
    final locales = selectableAppLanguages
        .where(
          (language) =>
              language != AppLanguagePreference.english &&
              language != AppLanguagePreference.polish,
        )
        .map((language) => language.localeKey)
        .toSet();
    expect(locales, hasLength(41));
    expect(reelLinksTranslations.keys.toSet(), locales);
    expect(appTranslationKeys, containsAll(reelLinksTranslationKeys));
    for (final locale in locales) {
      final values = reelLinksTranslations[locale]!;
      expect(values.keys.toSet(), reelLinksTranslationKeys.toSet());
      for (final key in reelLinksTranslationKeys) {
        expect(values[key]!.trim(), isNotEmpty);
        expect(values[key], isNot(key), reason: '$locale: $key');
        expect(translatedPhrase(locale, key), values[key]);
      }
    }
  });

  test(
    'source route is captured once above auth and native association is not claimed',
    () {
      final app = File('lib/app/app.dart').readAsStringSync();
      final gate = File(
        'lib/features/auth/presentation/screens/auth_gate.dart',
      ).readAsStringSync();
      expect(
        'ReelLinkIntentController(initialUri: Uri.base)'.allMatches(app),
        hasLength(1),
      );
      expect(app, contains('_reelLinkIntent.handlePrincipal(user?.uid)'));
      expect(app, contains('_reelLinkIntent.handleAuthError()'));
      expect(gate, contains('ReelLinkEntryCoordinator('));
      expect(gate, contains('intent.initialVisitCompleted'));
      final android = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final ios = File('ios/Runner/Runner.entitlements').readAsStringSync();
      expect(android, isNot(contains('android.intent.action.VIEW')));
      expect(ios, isNot(contains('com.apple.developer.associated-domains')));
      expect(
        File('firebase.json').readAsStringSync(),
        contains('"destination": "/index.html"'),
      );
    },
  );
}
