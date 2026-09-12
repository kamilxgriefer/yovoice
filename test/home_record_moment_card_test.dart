import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_record_moment_card.dart';

/// The recording route that survived the followed-Moments rail's move to the
/// Momenty destination. One ink, one target, one destination.
void main() {
  Widget host(
    Widget child, {
    Locale locale = const Locale('pl'),
    double scale = 1,
  }) => MaterialApp(
    locale: locale,
    theme: AppTheme.darkTheme,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );

  testWidgets('one InkWell, one callback, the real Polish copy', (
    tester,
  ) async {
    var records = 0;
    await tester.pumpWidget(
      host(HomeRecordMomentCard(onCreateMoment: () => records++)),
    );
    await tester.pump();

    final card = find.byKey(const ValueKey('home-record-moment'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.byType(InkWell)),
      findsOneWidget,
      reason: 'two nested targets would give the reader two answers',
    );
    expect(find.text('Masz chwilę?'), findsOneWidget);
    expect(find.text('Nagraj Voice Moment'), findsOneWidget);

    await tester.tap(card);
    await tester.pump();
    expect(records, 1);

    final size = tester.getSize(card);
    expect(size.height, greaterThanOrEqualTo(AppSizing.minimumTouchTarget));
    expect(size.width, greaterThanOrEqualTo(AppSizing.minimumTouchTarget));
  });

  testWidgets('a reader hears the card as one action', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(HomeRecordMomentCard(onCreateMoment: () {})));
    await tester.pump();
    final node = tester.getSemantics(
      find.byKey(const ValueKey('home-record-moment')),
    );
    expect(node.label, 'Masz chwilę? Nagraj Voice Moment');
    handle.dispose();
  });

  testWidgets('English keeps the invariant product name', (tester) async {
    await tester.pumpWidget(
      host(
        HomeRecordMomentCard(onCreateMoment: () {}),
        locale: const Locale('en'),
      ),
    );
    await tester.pump();
    expect(find.text('Got a minute?'), findsOneWidget);
    expect(find.text('Record a Voice Moment'), findsOneWidget);
  });

  testWidgets('200 % text grows the card instead of clipping it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(HomeRecordMomentCard(onCreateMoment: () {}), scale: 2),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
