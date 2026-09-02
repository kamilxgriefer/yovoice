// Developer-only interactive preview for the production language selector.
// Run with:
//   flutter run -d web-server -t lib/dev/localization_preview.dart
//
// This entrypoint is never imported by lib/main.dart and is not shipped.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/preferences/app_preferences.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/settings/presentation/screens/app_language_screen.dart';

void main() {
  final controller = AppPreferencesController(
    store: _MemoryPreferencesStore(),
    initialValue: const AppPreferences(
      theme: AppThemePreference.dark,
      language: AppLanguagePreference.system,
    ),
  );
  runApp(
    AppPreferencesScope(
      controller: controller,
      child: _LocalizationPreviewApp(controller: controller),
    ),
  );
}

class _LocalizationPreviewApp extends StatelessWidget {
  const _LocalizationPreviewApp({required this.controller});

  final AppPreferencesController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'YO Voice language preview',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: controller.value.theme.themeMode,
        locale: controller.value.language.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localeListResolutionCallback: resolveAppLocale,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const AppLanguageScreen(),
      ),
    );
  }
}

class _MemoryPreferencesStore implements AppPreferencesStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
