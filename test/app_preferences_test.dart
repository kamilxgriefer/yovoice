import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/settings/presentation/screens/app_language_screen.dart';
import 'package:yovoice/features/settings/presentation/screens/appearance_settings_screen.dart';

void main() {
  group('AppPreferencesController', () {
    test(
      'loads persisted values and falls back safely for invalid values',
      () async {
        final store = _MemoryStore({
          'appearance.theme.v1': 'light',
          'appearance.language.v1': 'polish',
        });
        final controller = AppPreferencesController(store: store);

        await controller.load();

        expect(controller.isLoaded, isTrue);
        expect(controller.value.theme, AppThemePreference.light);
        expect(controller.value.language, AppLanguagePreference.polish);

        final invalidController = AppPreferencesController(
          store: _MemoryStore({
            'appearance.theme.v1': 'sepia',
            'appearance.language.v1': 'klingon',
          }),
        );
        await invalidController.load();
        expect(invalidController.value.theme, AppThemePreference.dark);
        expect(invalidController.value.language, AppLanguagePreference.english);
      },
    );

    test('persists theme and language independently', () async {
      final store = _MemoryStore();
      final controller = AppPreferencesController(store: store);

      await controller.setTheme(AppThemePreference.light);
      await controller.setTheme(AppThemePreference.dark);
      await controller.setLanguage(AppLanguagePreference.polish);

      expect(store.values['appearance.theme.v1'], 'dark');
      expect(store.values['appearance.language.v1'], 'polish');
      expect(controller.value.theme, AppThemePreference.dark);
      expect(controller.value.language, AppLanguagePreference.polish);
    });

    test('rolls back optimistic state when persistence fails', () async {
      final controller = AppPreferencesController(store: _FailingStore());

      await expectLater(
        controller.setTheme(AppThemePreference.light),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        controller.setLanguage(AppLanguagePreference.polish),
        throwsA(isA<StateError>()),
      );

      expect(controller.value, isA<AppPreferences>());
      expect(controller.value.theme, AppThemePreference.dark);
      expect(controller.value.language, AppLanguagePreference.english);
    });
  });

  group('appearance and language settings', () {
    testWidgets('theme selection updates the global theme and persists', (
      tester,
    ) async {
      final store = _MemoryStore();
      final controller = AppPreferencesController(store: store);
      await tester.pumpWidget(
        _PreferencesTestApp(
          controller: controller,
          home: const AppearanceSettingsScreen(),
        ),
      );

      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark,
      );
      await tester.tap(find.textContaining('Light').last);
      await tester.pumpAndSettle();

      expect(controller.value.theme, AppThemePreference.light);
      expect(store.values['appearance.theme.v1'], 'light');
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.light,
      );
    });

    testWidgets('Polish changes locale and explains the bounded preview', (
      tester,
    ) async {
      final controller = AppPreferencesController(store: _MemoryStore());
      await tester.pumpWidget(
        _PreferencesTestApp(
          controller: controller,
          home: const AppLanguageScreen(),
        ),
      );

      await tester.tap(find.textContaining('Polski').last);
      await tester.pumpAndSettle();

      expect(controller.value.language, AppLanguagePreference.polish);
      expect(find.text('Język aplikacji'), findsOneWidget);
      expect(
        find.textContaining('Część ekranów produktu nadal'),
        findsOneWidget,
      );
    });

    for (final width in <double>[320, 768, 1440]) {
      testWidgets(
        'preference screens render at ${width.toInt()}px and 2x text',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = AppPreferencesController(store: _MemoryStore());

          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: const TextScaler.linear(2),
              ),
              child: _PreferencesTestApp(
                controller: controller,
                home: const AppearanceSettingsScreen(),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: const TextScaler.linear(2),
              ),
              child: _PreferencesTestApp(
                controller: controller,
                home: const AppLanguageScreen(),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}

class _PreferencesTestApp extends StatelessWidget {
  const _PreferencesTestApp({required this.controller, required this.home});

  final AppPreferencesController controller;
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => AppPreferencesScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: controller.value.theme.themeMode,
          locale: controller.value.language.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: home,
        ),
      ),
    );
  }
}

class _MemoryStore implements AppPreferencesStore {
  _MemoryStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _FailingStore implements AppPreferencesStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) {
    throw StateError('storage unavailable');
  }
}
