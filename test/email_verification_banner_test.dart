import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/auth/presentation/widgets/email_verification_banner.dart';

Widget _host({
  required Locale locale,
  required VoidCallback onTap,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.darkTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: Scaffold(body: EmailVerificationBanner(onTap: onTap)),
  );
}

void main() {
  testWidgets('unverified email reminder is a persistent English tap target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      _host(locale: const Locale('en'), onTap: () => taps += 1),
    );

    expect(find.text("Your email isn't verified yet."), findsOneWidget);
    expect(find.text('Verify now'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Your email is not verified. Verify now.'),
      findsOneWidget,
    );
    final semanticsData = tester
        .getSemantics(
          find.bySemanticsLabel('Your email is not verified. Verify now.'),
        )
        .getSemanticsData();
    expect(
      semanticsData.hasAction(SemanticsAction.tap),
      isTrue,
      reason:
          'The announced verification button must be screen-reader tappable.',
    );

    await tester.tap(find.byKey(const ValueKey('email-verification-banner')));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('unverified email reminder has natural Polish copy', (
    tester,
  ) async {
    await tester.pumpWidget(_host(locale: const Locale('pl'), onTap: () {}));

    expect(
      find.text('Twój adres e-mail nie został jeszcze zweryfikowany.'),
      findsOneWidget,
    );
    expect(find.text('Zweryfikuj teraz'), findsOneWidget);
    expect(find.text('Verify now'), findsNothing);
  });

  testWidgets('Polish reminder stays readable at 320px and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        locale: const Locale('pl'),
        onTap: () {},
        textScaler: const TextScaler.linear(2),
      ),
    );

    final message = find.text(
      'Twój adres e-mail nie został jeszcze zweryfikowany.',
    );
    final action = find.text('Zweryfikuj teraz');
    expect(message, findsOneWidget);
    expect(action, findsOneWidget);
    expect(
      tester.getRect(action).top,
      greaterThan(tester.getRect(message).top),
    );
    expect(tester.takeException(), isNull);
  });
}
