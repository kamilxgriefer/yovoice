// The guided tour and a spotlight target that left the screen.
//
// On phones the tour's "create" step points at Start's own create pill and
// places its card above that pill. Start can grow above the pill while the
// tour is open (build 42 adds the "Zacznij tutaj" card under the greeting;
// the shell holds that card until the tour is over, and this is the safety
// net under it). A card placed from an off-screen rect would land off the
// screen with its Next and Skip — on a phone without a Back button there
// would be no way out. The step must be shown centred instead.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/onboarding/data/guided_onboarding_progress.dart';
import 'package:yovoice/features/onboarding/presentation/guided_onboarding_tour.dart';

const _screen = Size(390, 844);

class _Harness extends StatefulWidget {
  const _Harness({required this.anchors});

  final Map<GuidedOnboardingTarget, GlobalKey> anchors;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  /// Where Start's create pill sits; moved by the test as Start grows.
  double createTop = 600;
  GuidedOnboardingOutcome? outcome;

  void moveCreate(double top) => setState(() => createTop = top);

  void open() {
    unawaited(
      showGuidedOnboardingTour(
        context,
        anchors: widget.anchors,
        desktop: false,
      ).then((value) {
        if (mounted) setState(() => outcome = value);
      }),
    );
  }

  Widget _anchor(GuidedOnboardingTarget target, Rect rect) => Positioned(
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height,
    child: SizedBox.expand(key: widget.anchors[target]),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 12,
          top: 12,
          child: FilledButton(
            key: const ValueKey('open'),
            onPressed: open,
            child: const Text('Open tour'),
          ),
        ),
        Positioned(
          left: 12,
          top: 76,
          child: Text('Outcome: ${outcome?.name ?? 'pending'}'),
        ),
        _anchor(
          GuidedOnboardingTarget.create,
          Rect.fromLTWH(16, createTop, 170, 44),
        ),
        _anchor(
          GuidedOnboardingTarget.moments,
          const Rect.fromLTWH(250, 760, 56, 56),
        ),
        _anchor(
          GuidedOnboardingTarget.chats,
          const Rect.fromLTWH(170, 760, 56, 56),
        ),
        _anchor(
          GuidedOnboardingTarget.more,
          const Rect.fromLTWH(320, 760, 56, 56),
        ),
      ],
    ),
  );
}

Future<_HarnessState> _pump(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _screen;
  addTearDown(tester.view.reset);
  final anchors = {
    for (final target in GuidedOnboardingTarget.values)
      target: GlobalKey(debugLabel: 'tour-${target.name}'),
  };
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: const Locale('pl'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: _Harness(anchors: anchors),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('guided-tour-card')), findsOneWidget);
  return tester.state<_HarnessState>(find.byType(_Harness));
}

void _expectCardOnScreen(WidgetTester tester) {
  final card = tester.getRect(find.byKey(const ValueKey('guided-tour-card')));
  final screen = Offset.zero & _screen;
  expect(
    screen.contains(card.topLeft) && screen.contains(card.bottomRight),
    isTrue,
    reason: 'the tour card $card must stay inside $screen',
  );
  for (final control in const ['guided-tour-next', 'guided-tour-skip']) {
    final finder = find.byKey(ValueKey(control));
    if (finder.evaluate().isEmpty) continue;
    expect(
      screen.contains(tester.getCenter(finder)),
      isTrue,
      reason: '$control must be reachable',
    );
  }
}

void main() {
  testWidgets('an on-screen target still places the card above it', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('guided-tour-next')));
    await tester.pumpAndSettle();
    expect(find.text('Krok 2 z 5'), findsOneWidget);
    final card = tester.getRect(find.byKey(const ValueKey('guided-tour-card')));
    expect(card.bottom, lessThanOrEqualTo(600 - 16 + .5));
    expect(
      find.byKey(const ValueKey('guided-tour-highlight-create')),
      findsOneWidget,
    );
    _expectCardOnScreen(tester);
  });

  testWidgets('a target pushed below the screen under the open tour leaves the '
      'card on screen, and the tour can be finished', (tester) async {
    final harness = await _pump(tester);
    _expectCardOnScreen(tester);

    // Start grows above the pill (a card arrives under the greeting).
    harness.moveCreate(1000);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('guided-tour-next')));
    await tester.pumpAndSettle();
    expect(find.text('Krok 2 z 5'), findsOneWidget);
    _expectCardOnScreen(tester);

    for (var step = 3; step <= 5; step++) {
      await tester.tap(find.byKey(const ValueKey('guided-tour-next')));
      await tester.pumpAndSettle();
      expect(find.text('Krok $step z 5'), findsOneWidget);
      _expectCardOnScreen(tester);
    }
    await tester.tap(find.byKey(const ValueKey('guided-tour-next')));
    await tester.pumpAndSettle();
    expect(find.text('Outcome: completed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a target scrolled above the screen leaves the card on screen '
      'and Skip reachable', (tester) async {
    final harness = await _pump(tester);
    harness.moveCreate(-200);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('guided-tour-next')));
    await tester.pumpAndSettle();
    expect(find.text('Krok 2 z 5'), findsOneWidget);
    _expectCardOnScreen(tester);

    await tester.tap(find.byKey(const ValueKey('guided-tour-skip')));
    await tester.pumpAndSettle();
    expect(find.text('Outcome: skipped'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
