import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/shared/widgets/inputs/yo_keyboard_done_bar.dart';

Widget _host({
  required double keyboardInset,
  Locale locale = const Locale('en'),
  Widget? action,
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
        bottomNavigationBar: YoKeyboardDoneBar(action: action),
      ),
    ),
  );
}

/// The placement that used to render nothing: the bar as the last child of a
/// Column inside `Scaffold.body`, with a REAL view inset rather than an
/// injected MediaQuery. `Scaffold` strips the bottom view inset from the body
/// slot, so the inherited value there is 0 while the keyboard is open.
Widget _bodyPlacementHost() {
  return MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Column(
        children: const [
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: TextField(
                key: ValueKey('field'),
                maxLines: 4,
                keyboardType: TextInputType.multiline,
              ),
            ),
          ),
          YoKeyboardDoneBar(),
        ],
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
    // Focused, but no keyboard inset reported: still nothing to show. This is
    // also the hardware-keyboard case — the platform reports no inset, the
    // screen's own resting chrome is already visible, and the bar stays out.
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
    // A minimum rather than a fixed height, so enlarged text grows the row
    // instead of overflowing it; Done-only stays a compact strip.
    final height = tester
        .getSize(find.byKey(const ValueKey('yo-keyboard-done-bar')))
        .height;
    expect(height, greaterThanOrEqualTo(48));
    expect(height, lessThanOrEqualTo(56));
    await tester.tap(find.byKey(const ValueKey('yo-keyboard-done')));
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.context?.widget,
      isNot(isA<EditableText>()),
    );
    expect(find.byKey(const ValueKey('yo-keyboard-done-bar')), findsNothing);
  });

  testWidgets('the Done target clears the 44 px floor', (tester) async {
    await tester.pumpWidget(_host(keyboardInset: 300));
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pump();
    final done = tester.getSize(find.byKey(const ValueKey('yo-keyboard-done')));
    expect(done.height, greaterThanOrEqualTo(44));
    expect(done.width, greaterThanOrEqualTo(44));
  });

  testWidgets('a docked action rides next to Done and keeps its own target', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        keyboardInset: 300,
        action: FilledButton(
          key: const ValueKey('docked-action'),
          onPressed: () {},
          style: FilledButton.styleFrom(minimumSize: const Size(112, 48)),
          child: const Text('Publish'),
        ),
      ),
    );
    // Nothing is focused yet, so the whole bar — action included — stays out
    // of the tree rather than floating over a closed keyboard.
    expect(find.byKey(const ValueKey('docked-action')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pump();
    expect(find.byKey(const ValueKey('docked-action')), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    final bar = tester.getRect(
      find.byKey(const ValueKey('yo-keyboard-done-bar')),
    );
    final action = tester.getRect(find.byKey(const ValueKey('docked-action')));
    final done = tester.getRect(find.byKey(const ValueKey('yo-keyboard-done')));
    expect(bar.height, greaterThanOrEqualTo(56));
    expect(action.height, greaterThanOrEqualTo(44));
    // Done leads, the action is docked opposite it, and both sit inside the
    // bar rather than overflowing it.
    expect(done.left, lessThan(action.left));
    expect(bar.contains(action.centerLeft), isTrue);
  });

  testWidgets('the bar renders inside a Scaffold body, where Scaffold strips '
      'the keyboard inset', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_bodyPlacementHost());
    expect(find.byKey(const ValueKey('yo-keyboard-done-bar')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    await tester.pump();

    // The body's own MediaQuery reports no inset at all — this is exactly why
    // an inherited-only reading rendered nothing here.
    final bodyContext = tester.element(find.byKey(const ValueKey('field')));
    expect(MediaQuery.viewInsetsOf(bodyContext).bottom, 0);
    expect(find.byKey(const ValueKey('yo-keyboard-done-bar')), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
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
