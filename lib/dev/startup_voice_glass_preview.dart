// Developer-only preview. Does not initialize Firebase, request permissions,
// write preferences, or impose an artificial delay in the production app.
// flutter run -t lib/dev/startup_voice_glass_preview.dart --dart-define=STARTUP_LANGUAGE=pl
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:yovoice/core/localization/app_language.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/localization/translations/translations_startup.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/presentation/widgets/startup_loading_screen.dart';

void main() {
  final languageKey =
      Uri.base.queryParameters['lang'] ??
      const String.fromEnvironment('STARTUP_LANGUAGE', defaultValue: 'pl');
  final locale = selectableAppLanguages
      .firstWhere(
        (language) => language.localeKey == languageKey,
        orElse: () => AppLanguagePreference.polish,
      )
      .locale!;
  runApp(
    StartupVoiceGlassPreview(
      locale: locale,
      headlineIndex:
          int.tryParse(Uri.base.queryParameters['headline'] ?? '') ??
          const int.fromEnvironment('STARTUP_HEADLINE'),
      reducedMotion: const bool.fromEnvironment('STARTUP_REDUCED_MOTION'),
      highContrast: const bool.fromEnvironment('STARTUP_HIGH_CONTRAST'),
      textScale: const bool.fromEnvironment('STARTUP_LARGE_TEXT') ? 2 : null,
    ),
  );
}

class StartupVoiceGlassPreview extends StatelessWidget {
  const StartupVoiceGlassPreview({
    this.locale = const Locale('pl'),
    this.headlineIndex = 0,
    this.reducedMotion = false,
    this.highContrast = false,
    this.textScale,
    this.safePadding,
    this.repaintKey,
    super.key,
  });

  final Locale locale;
  final int headlineIndex;
  final bool reducedMotion;
  final bool highContrast;
  final double? textScale;
  final EdgeInsets? safePadding;
  final Key? repaintKey;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'YO Voice startup preview',
    theme: AppTheme.darkTheme,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localeListResolutionCallback: resolveAppLocale,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) {
      final media = MediaQuery.of(context);
      return RepaintBoundary(
        key: repaintKey,
        child: MediaQuery(
          data: media.copyWith(
            disableAnimations: reducedMotion || media.disableAnimations,
            accessibleNavigation: reducedMotion || media.accessibleNavigation,
            highContrast: highContrast || media.highContrast,
            textScaler: textScale == null
                ? media.textScaler
                : TextScaler.linear(textScale!),
            padding: safePadding ?? media.padding,
          ),
          child: child!,
        ),
      );
    },
    home: StartupLoadingScreen(
      headlineKey:
          startupHeadlineTranslationKeys[headlineIndex.clamp(
            0,
            startupHeadlineTranslationKeys.length - 1,
          )],
    ),
  );
}
