import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      'a fresh install follows the device language by default (ADR-136)',
      () async {
        final controller = AppPreferencesController(store: _MemoryStore());

        await controller.load();

        expect(controller.isLoaded, isTrue);
        expect(controller.value.language, AppLanguagePreference.system);
      },
    );

    test(
      'loads persisted values and falls back safely for invalid values',
      () async {
        final store = _MemoryStore({
          'appearance.theme.v1': 'light',
          'appearance.language.v1': 'polish',
          'audio.sound_effects.enabled.v1': 'false',
        });
        final controller = AppPreferencesController(store: store);

        await controller.load();

        expect(controller.isLoaded, isTrue);
        expect(controller.value.theme, AppThemePreference.light);
        expect(controller.value.language, AppLanguagePreference.polish);
        expect(controller.value.soundEffectsEnabled, isFalse);

        final invalidController = AppPreferencesController(
          store: _MemoryStore({
            'appearance.theme.v1': 'sepia',
            'appearance.language.v1': 'klingon',
            'audio.sound_effects.enabled.v1': 'not-a-bool',
          }),
        );
        await invalidController.load();
        expect(invalidController.value.theme, AppThemePreference.dark);
        expect(invalidController.value.language, AppLanguagePreference.english);
        expect(invalidController.value.soundEffectsEnabled, isTrue);
      },
    );

    test('persists theme, language and sound independently', () async {
      final store = _MemoryStore();
      final controller = AppPreferencesController(store: store);

      await controller.setTheme(AppThemePreference.light);
      await controller.setTheme(AppThemePreference.dark);
      await controller.setLanguage(AppLanguagePreference.polish);
      await controller.setSoundEffectsEnabled(false);

      expect(store.values['appearance.theme.v1'], 'dark');
      expect(store.values['appearance.language.v1'], 'polish');
      expect(store.values['audio.sound_effects.enabled.v1'], 'false');
      expect(controller.value.theme, AppThemePreference.dark);
      expect(controller.value.language, AppLanguagePreference.polish);
      expect(controller.value.soundEffectsEnabled, isFalse);
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
      await expectLater(
        controller.setSoundEffectsEnabled(false),
        throwsA(isA<StateError>()),
      );

      expect(controller.value, isA<AppPreferences>());
      expect(controller.value.theme, AppThemePreference.dark);
      expect(controller.value.language, AppLanguagePreference.system);
      expect(controller.value.soundEffectsEnabled, isTrue);
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
      expect(find.textContaining('Light · Beta'), findsNothing);
      expect(find.textContaining('Pearl surfaces'), findsOneWidget);
      expect(store.values['appearance.theme.v1'], 'light');
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.light,
      );
    });

    testWidgets('Polish is production-ready and has no beta label', (
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
      await tester.fling(find.byType(ListView), const Offset(0, -5000), 1200);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Nawigacja, logowanie, rejestracja'),
        findsOneWidget,
      );
      expect(find.textContaining('Beta'), findsNothing);
    });

    testWidgets('search and a non-Polish locale switch work end to end', (
      tester,
    ) async {
      final store = _MemoryStore();
      final controller = AppPreferencesController(store: store);
      await tester.pumpWidget(
        _PreferencesTestApp(
          controller: controller,
          home: const AppLanguageScreen(),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('language-search')),
        'Deutsch',
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('language-de')),
          matching: find.text('Deutsch'),
        ),
        findsOneWidget,
      );
      expect(find.text('Español'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('language-de')));
      await tester.pumpAndSettle();

      expect(controller.value.language, AppLanguagePreference.german);
      expect(store.values['appearance.language.v1'], 'german');
      expect(find.text('App-Sprache'), findsOneWidget);
      expect(find.textContaining('Beta'), findsNothing);
    });

    testWidgets('language cards are keyboard reachable and activatable', (
      tester,
    ) async {
      final controller = AppPreferencesController(store: _MemoryStore());
      await tester.pumpWidget(
        _PreferencesTestApp(
          controller: controller,
          home: const AppLanguageScreen(),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('language-search')));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      final englishCard = find.byKey(const ValueKey('language-en'));
      final englishInkWell = tester.widget<InkWell>(
        find.descendant(of: englishCard, matching: find.byType(InkWell)),
      );
      expect(
        englishInkWell.focusNode?.hasFocus,
        isTrue,
        reason: 'Tab must move from search into the first language card.',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.value.language, AppLanguagePreference.english);
    });

    testWidgets(
      'preference choices expose one named state and lock during persistence',
      (tester) async {
        final store = _DelayedStore();
        final controller = AppPreferencesController(store: store);
        final semantics = tester.ensureSemantics();
        bool isAppearanceChoice(Widget widget) =>
            widget is Semantics &&
            (widget.properties.label?.contains('Follows your device') == true ||
                widget.properties.label?.contains('original cosmic') == true ||
                widget.properties.label?.contains('Pearl surfaces') == true);
        await tester.pumpWidget(
          _PreferencesTestApp(
            controller: controller,
            home: const AppearanceSettingsScreen(),
          ),
        );

        await tester.tap(find.textContaining('Light').last);
        await tester.pump();

        final choices = tester.widgetList<Semantics>(
          find.byWidgetPredicate(isAppearanceChoice),
        );
        expect(choices, hasLength(3));
        expect(
          choices.every((choice) => choice.properties.enabled == false),
          isTrue,
        );
        expect(
          choices.where((choice) => choice.properties.value == 'Saving'),
          hasLength(1),
        );

        store.completeWrite();
        await tester.pumpAndSettle();
        final settledChoices = tester.widgetList<Semantics>(
          find.byWidgetPredicate(isAppearanceChoice),
        );
        expect(
          settledChoices.any((choice) => choice.properties.enabled == true),
          isTrue,
        );
        semantics.dispose();
      },
    );

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

class _DelayedStore implements AppPreferencesStore {
  final Completer<void> _write = Completer<void>();

  void completeWrite() {
    if (!_write.isCompleted) _write.complete();
  }

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) => _write.future;
}
