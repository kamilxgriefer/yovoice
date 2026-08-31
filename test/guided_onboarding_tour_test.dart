import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/onboarding/data/guided_onboarding_progress.dart';
import 'package:yovoice/features/onboarding/presentation/guided_onboarding_tour.dart';

void main() {
  testWidgets('five steps support Next, Back and a completed outcome', (
    tester,
  ) async {
    final anchors = _tourAnchors();
    await _pumpHarness(tester, anchors: anchors);
    await _openTour(tester);

    expect(find.text('Welcome to YO Voice'), findsOneWidget);
    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(_tourHighlights(), findsNothing);

    await _tapControl(tester, const ValueKey('guided-tour-next'));
    _expectHighlightMatches(tester, anchors, GuidedOnboardingTarget.create);

    await _tapControl(tester, const ValueKey('guided-tour-next'));
    _expectHighlightMatches(tester, anchors, GuidedOnboardingTarget.moments);

    await _tapControl(tester, const ValueKey('guided-tour-back'));
    expect(find.text('Use your voice'), findsOneWidget);
    _expectHighlightMatches(tester, anchors, GuidedOnboardingTarget.create);

    for (final target in const [
      GuidedOnboardingTarget.moments,
      GuidedOnboardingTarget.chats,
      GuidedOnboardingTarget.more,
    ]) {
      await _tapControl(tester, const ValueKey('guided-tour-next'));
      _expectHighlightMatches(tester, anchors, target);
    }

    expect(find.text('More, one tap away'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.byKey(const ValueKey('guided-tour-skip')), findsNothing);

    await _tapControl(tester, const ValueKey('guided-tour-next'));

    expect(find.text('Outcome: completed'), findsOneWidget);
    expect(find.byKey(const ValueKey('guided-tour-card')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Skip records skipped and the spotlight never passes taps through',
    (tester) async {
      final anchors = _tourAnchors();
      await _pumpHarness(tester, anchors: anchors);
      await _openTour(tester);
      await _tapControl(tester, const ValueKey('guided-tour-next'));

      final targetRect = tester.getRect(
        find.byKey(anchors[GuidedOnboardingTarget.create]!),
      );
      await tester.tapAt(targetRect.center);
      await tester.pump();

      expect(find.text('Underlying taps: 0'), findsOneWidget);

      await _tapControl(tester, const ValueKey('guided-tour-skip'));
      expect(find.text('Outcome: skipped'), findsOneWidget);
    },
  );

  testWidgets('arrow keys navigate and Escape skips', (tester) async {
    final anchors = _tourAnchors();
    await _pumpHarness(tester, anchors: anchors);
    await _openTour(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Use your voice'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Hear what\'s new'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('Use your voice'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Outcome: skipped'), findsOneWidget);
  });

  testWidgets('focused Next survives step changes for repeated Enter', (
    tester,
  ) async {
    final anchors = _tourAnchors();
    await _pumpHarness(tester, anchors: anchors);
    await _openTour(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Use your voice'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Hear what\'s new'), findsOneWidget);
  });

  testWidgets('Dark and Pearl use their semantic raised card surface', (
    tester,
  ) async {
    for (final (theme, palette) in [
      (AppTheme.darkTheme, AppPalette.dark),
      (AppTheme.lightTheme, AppPalette.light),
    ]) {
      final anchors = _tourAnchors();
      await _pumpHarness(tester, anchors: anchors, theme: theme);
      await _openTour(tester);

      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byKey(const ValueKey('guided-tour-card')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, palette.surfaceRaised);
      await _tapControl(tester, const ValueKey('guided-tour-next'));
      final highlight = find.byKey(
        const ValueKey('guided-tour-highlight-create'),
      );
      final highlightDecoration =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: highlight,
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(
        highlightDecoration.border,
        Border.all(color: palette.textPrimary, width: 3),
      );
      expect(
        highlightDecoration.boxShadow!.single.color,
        palette.interactiveForeground.withValues(alpha: .38),
      );
      expect(tester.takeException(), isNull);

      await _tapControl(tester, const ValueKey('guided-tour-skip'));
    }
  });

  testWidgets(
    'Polish reduced-motion tour fits 320x568 at 200% through every step',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final anchors = _tourAnchors();
      await _pumpHarness(
        tester,
        anchors: anchors,
        theme: AppTheme.lightTheme,
        locale: const Locale('pl'),
        textScale: 2,
        reduceMotion: true,
      );
      await _openTour(tester);

      expect(find.text('Witaj w YO Voice'), findsOneWidget);
      expect(find.text('Pomiń'), findsOneWidget);
      expect(find.text('Dalej'), findsOneWidget);
      expect(
        tester
            .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
            .every((widget) => widget.duration == Duration.zero),
        isTrue,
      );
      expect(tester.takeException(), isNull);

      for (var step = 2; step <= 5; step++) {
        await _tapControl(tester, const ValueKey('guided-tour-next'));
        expect(find.text('Krok $step z 5'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      expect(find.text('Więcej — jedno dotknięcie'), findsOneWidget);
      expect(find.text('Gotowe'), findsOneWidget);
      await _tapControl(tester, const ValueKey('guided-tour-next'));
      expect(find.text('Outcome: completed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Map<GuidedOnboardingTarget, GlobalKey> _tourAnchors() => {
  for (final target in GuidedOnboardingTarget.values)
    target: GlobalKey(debugLabel: 'tour-${target.name}'),
};

Finder _tourHighlights() => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith(
        'guided-tour-highlight-',
      ),
);

void _expectHighlightMatches(
  WidgetTester tester,
  Map<GuidedOnboardingTarget, GlobalKey> anchors,
  GuidedOnboardingTarget target,
) {
  final highlight = find.byKey(
    ValueKey('guided-tour-highlight-${target.name}'),
  );
  expect(highlight, findsOneWidget);
  expect(_tourHighlights(), findsOneWidget);

  final targetRect = tester.getRect(find.byKey(anchors[target]!));
  final highlightRect = tester.getRect(highlight);
  expect(highlightRect.left, closeTo(targetRect.left - 8, 0.01));
  expect(highlightRect.top, closeTo(targetRect.top - 8, 0.01));
  expect(highlightRect.right, closeTo(targetRect.right + 8, 0.01));
  expect(highlightRect.bottom, closeTo(targetRect.bottom + 8, 0.01));
}

Future<void> _openTour(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-guided-tour')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('guided-tour-card')), findsOneWidget);
}

Future<void> _tapControl(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required Map<GuidedOnboardingTarget, GlobalKey> anchors,
  ThemeData? theme,
  Locale locale = const Locale('en'),
  double textScale = 1,
  bool reduceMotion = false,
  bool desktop = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: _TourHarness(anchors: anchors, desktop: desktop),
    ),
  );
  await tester.pump();
}

class _TourHarness extends StatefulWidget {
  const _TourHarness({required this.anchors, required this.desktop});

  final Map<GuidedOnboardingTarget, GlobalKey> anchors;
  final bool desktop;

  @override
  State<_TourHarness> createState() => _TourHarnessState();
}

class _TourHarnessState extends State<_TourHarness> {
  GuidedOnboardingOutcome? _outcome;
  int _underlyingTaps = 0;

  void _openTour() {
    unawaited(
      showGuidedOnboardingTour(
        context,
        anchors: widget.anchors,
        desktop: widget.desktop,
      ).then((outcome) {
        if (!mounted) return;
        setState(() => _outcome = outcome);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            children: [
              Positioned(
                left: 12,
                top: 12,
                child: FilledButton(
                  key: const ValueKey('open-guided-tour'),
                  onPressed: _openTour,
                  child: const Text('Open tour'),
                ),
              ),
              Positioned(
                left: 12,
                top: 76,
                child: Text('Outcome: ${_outcome?.name ?? 'pending'}'),
              ),
              Positioned(
                left: 12,
                top: 104,
                child: Text('Underlying taps: $_underlyingTaps'),
              ),
              if (widget.desktop) ...[
                _anchor(
                  target: GuidedOnboardingTarget.create,
                  left: 28,
                  top: 160,
                  size: const Size(214, 64),
                ),
                _anchor(
                  target: GuidedOnboardingTarget.moments,
                  left: 28,
                  top: 242,
                  size: const Size(214, 54),
                ),
                _anchor(
                  target: GuidedOnboardingTarget.chats,
                  left: 28,
                  top: 310,
                  size: const Size(214, 54),
                ),
                _anchor(
                  target: GuidedOnboardingTarget.more,
                  left: 28,
                  top: 378,
                  size: const Size(214, 54),
                ),
              ] else ...[
                _anchor(
                  target: GuidedOnboardingTarget.chats,
                  left: 16,
                  bottom: 16,
                ),
                _anchor(
                  target: GuidedOnboardingTarget.create,
                  left: width / 2 - 28,
                  bottom: 16,
                  size: const Size.square(56),
                ),
                _anchor(
                  target: GuidedOnboardingTarget.moments,
                  left: width - 120,
                  bottom: 16,
                ),
                _anchor(
                  target: GuidedOnboardingTarget.more,
                  left: width - 64,
                  bottom: 16,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _anchor({
    required GuidedOnboardingTarget target,
    required double left,
    double? top,
    double? bottom,
    Size size = const Size.square(48),
  }) {
    return Positioned(
      left: left,
      top: top,
      bottom: bottom,
      width: size.width,
      height: size.height,
      child: KeyedSubtree(
        key: widget.anchors[target],
        child: GestureDetector(
          key: ValueKey('underlying-${target.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _underlyingTaps += 1),
          child: ColoredBox(
            color: Theme.of(context).colorScheme.primaryContainer,
          ),
        ),
      ),
    );
  }
}
