import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/app_translation_catalog.dart';
import 'package:yovoice/core/localization/translations/translations_gif_composer.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/media/data/models/gif_asset.dart';
import 'package:yovoice/features/media/data/services/gif_catalog_service.dart';
import 'package:yovoice/shared/widgets/inputs/yo_gif_picker.dart';

import 'support/fake_gif_transport.dart';

void main() {
  test('GIF copy explicitly covers every canonical translated locale', () {
    final locales = selectableAppLanguages
        .where(
          (language) =>
              language != AppLanguagePreference.english &&
              language != AppLanguagePreference.polish,
        )
        .map((language) => language.localeKey)
        .toSet();
    expect(AppLocalizations.supportedLocales, hasLength(43));
    expect(gifComposerTranslations.keys.toSet(), locales);
    expect(gifComposerTranslationKeys, hasLength(37));
    expect(gifComposerTranslationKeys.toSet(), hasLength(37));
    expect(appTranslationKeys, containsAll(gifComposerTranslationKeys));
    final placeholder = RegExp(r'\{[a-zA-Z][a-zA-Z0-9_]*\}');
    for (final locale in locales) {
      final row = gifComposerTranslations[locale]!;
      expect(row.keys.toSet(), gifComposerTranslationKeys.toSet());
      for (final key in gifComposerTranslationKeys) {
        final value = row[key]!;
        expect(value.trim(), isNotEmpty, reason: '$locale: $key');
        expect(translatedPhrase(locale, key), value);
        expect(
          placeholder.allMatches(value).map((match) => match.group(0)),
          placeholder.allMatches(key).map((match) => match.group(0)),
          reason: '$locale: $key',
        );
        // GIF and Emoji are shared medium names in several languages. The
        // complete title template may likewise be identical legitimately.
        if (key.length > 10 && key != 'GIF: {title}') {
          expect(value, isNot(key), reason: '$locale: no English fallback');
        }
      }
    }
  });

  test(
    'GIF labels substitute the stored title exactly once in every locale',
    () {
      const title = 'Cat {title} — kot';
      for (final locale in AppLocalizations.supportedLocales) {
        final copy = AppLocalizations(locale);
        expect(
          copy.template(
            'Load GIF: {title}',
            'Wczytaj GIF: {title}',
            values: const {'title': title},
          ),
          contains(title),
        );
        expect(
          copy.template(
            'GIF: {title}',
            'GIF: {title}',
            values: const {'title': title},
          ),
          contains(title),
        );
      }
    },
  );

  testWidgets('translated unavailable copy fits a short panel at 200 percent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final locale in AppLocalizations.supportedLocales) {
      for (final reason in [
        GifUnavailableReason.notConfigured,
        GifUnavailableReason.disabled,
        GifUnavailableReason.unreachable,
      ]) {
        final service = GifCatalogService(
          transport: FakeGifTransport(
            catalogResult: GifCatalog.unavailable(reason),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            theme: AppTheme.darkTheme,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: YoGifPicker(
                  service: service,
                  height: 180,
                  autoLoad: false,
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$locale $reason');
        expect(find.byKey(const ValueKey('gif-unavailable')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        service.dispose();
      }
    }
  });
}
