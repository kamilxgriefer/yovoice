import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/shared/widgets/inputs/yo_keyboard_done_bar.dart';

Widget _host({
  required double keyboardInset,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        viewInsets: EdgeInsets.only(bottom: keyboardInset),
      ),
      child: Scaffold(
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: TextField(
            key: ValueKey('field'),
            maxLines: 4,
            keyboardType: TextInputType.multiline,
          ),
        ),
        bottomNavigationBar: const YoKeyboardDoneBar(),
      ),
    ),
  );
}

void main() {
  testWidgets('bar is absent at rest and while the keyboard is closed', (
    tester,
  ) async {
    await tester.pumpWidget(_host(keyboardInset: 0));
    expect(find.byKey(const ValueKey('yo-keyboard-done-bar')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pump();
    // Focused, but no keyboard inset reported: still nothing to show.
    expect(find.byKey(const ValueKey('yo-keyboard-done-bar')), findsNothing);
  });

  testWidgets('Done appears with a focused field and an open keyboard, and '
      'unfocuses on tap', (tester) async {
    await tester.pumpWidget(_host(keyboardInset: 300));
    expect(find.byKey(const ValueKey('yo-keyboard-done-bar')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pump();
    expect(find.byKey(const ValueKey('yo-keyboard-done-bar')), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('yo-keyboard-done-bar'))).height,
      48,
    );
    await tester.tap(find.byKey(const ValueKey('yo-keyboard-done')));
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.context?.widget,
      isNot(isA<EditableText>()),
    );
    expect(find.byKey(const ValueKey('yo-keyboard-done-bar')), findsNothing);
  });

  testWidgets('Polish copy', (tester) async {
    await tester.pumpWidget(
      _host(keyboardInset: 300, locale: const Locale('pl')),
    );
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pump();
    expect(find.text('Gotowe'), findsOneWidget);
  });
}
