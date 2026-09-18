import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/shared/widgets/buttons/yo_button.dart';

/// RC-14 / gate blocker G-3.
///
/// The publish footer reports its stage by passing a live label to [YoButton]
/// while `isLoading` is true. Until this round the loading branch replaced the
/// entire button child with a bare [CircularProgressIndicator], so the label —
/// "Publishing 42%", "Preparing…", "Finishing…" — reached VoiceOver only and a
/// sighted user saw a wordless spinner. Every assertion below is on *rendered*
/// text, not on the widget's `label` property, because the property was already
/// correct while the screen showed nothing.
void main() {
  testWidgets('a loading button renders its label next to the spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Locale('en'),
        const YoButton(
          label: 'Finishing…',
          onPressed: null,
          isLoading: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.text('Finishing…'),
      findsOneWidget,
      reason: 'a busy control must still say what it is busy with',
    );
  });

  testWidgets('the loading label is drawn in Polish too', (tester) async {
    await tester.pumpWidget(
      _host(
        const Locale('pl'),
        const YoButton(
          label: 'Kończenie…',
          onPressed: null,
          isLoading: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Kończenie…'), findsOneWidget);
  });

  testWidgets('an idle button keeps its icon and label', (tester) async {
    await tester.pumpWidget(
      _host(
        const Locale('en'),
        YoButton(
          label: 'Publish Yeel',
          onPressed: () {},
          icon: const Icon(Icons.publish_rounded),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.publish_rounded), findsOneWidget);
    expect(find.text('Publish Yeel'), findsOneWidget);
  });

  testWidgets('the loading label survives 320px at 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        const Locale('pl'),
        const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: YoButton(
            // The longest publish-stage phrase in either locale.
            label: 'Publikowanie 100%',
            onPressed: null,
            isLoading: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Publikowanie 100%'), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'the label wraps or ellipsizes; it never overflows the button',
    );
  });
}

Widget _host(Locale locale, Widget child) => MaterialApp(
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: Center(child: child)),
);
