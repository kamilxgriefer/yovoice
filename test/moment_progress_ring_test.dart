// The listening-progress ring: the arc is a position, not a presence.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_progress_ring.dart';

void main() {
  group('arc math', () {
    test('starts at twelve o\'clock and sweeps clockwise', () {
      expect(MomentProgressRing.startAngle, -math.pi / 2);
      expect(MomentProgressRing.sweepFor(0), 0);
      expect(MomentProgressRing.sweepFor(0.25), closeTo(math.pi / 2, 1e-9));
      expect(MomentProgressRing.sweepFor(0.4), closeTo(0.8 * math.pi, 1e-9));
      expect(MomentProgressRing.sweepFor(1), closeTo(2 * math.pi, 1e-9));
    });

    test('a late tick past the end is clamped, never thrown', () {
      expect(MomentProgressRing.sweepFor(1.4), closeTo(2 * math.pi, 1e-9));
      expect(MomentProgressRing.sweepFor(-0.2), 0);
    });

    test('the outer diameter is the avatar plus gap and stroke', () {
      const ring = MomentProgressRing(progress: 0, child: SizedBox());
      expect(ring.avatarDiameter, 120);
      expect(ring.diameter, 140);
      const compact = MomentProgressRing(
        progress: 0,
        avatarDiameter: MomentProgressRing.compactAvatar,
        child: SizedBox(),
      );
      expect(compact.diameter, 116);
    });
  });

  Future<void> pumpProgress(
    WidgetTester tester, {
    double progress = 0.4,
    TextDirection direction = TextDirection.ltr,
    bool reduceMotion = false,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Center(
                child: MomentListeningProgress(
                  progress: progress,
                  avatar: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // A second pumpWidget in the same test crossfades the theme; settle it
    // so the palette under assertion is the ACTIVE one.
    await tester.pumpAndSettle();
  }

  testWidgets('the percentage and the ring are ONE announcement', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpProgress(tester);

    expect(find.text('40%'), findsOneWidget);
    final node = tester.getSemantics(
      find.ancestor(
        of: find.byType(MomentProgressRing),
        matching: find.byType(Semantics).last,
      ),
    );
    expect(node.label, 'Listening progress');
    expect(node.value, '40%');
    // The printed number must not be announced a second time.
    expect(find.bySemanticsLabel('40%'), findsNothing);
    handle.dispose();
  });

  testWidgets('a clock is not mirrored: RTL keeps the same geometry', (
    tester,
  ) async {
    await pumpProgress(tester, direction: TextDirection.ltr);
    final ltr = tester.getSize(find.byType(MomentProgressRing));
    final ltrPainter = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(MomentProgressRing),
            matching: find.byType(CustomPaint),
          ),
        )
        .first
        .painter;

    await pumpProgress(tester, direction: TextDirection.rtl);
    final rtl = tester.getSize(find.byType(MomentProgressRing));
    final rtlPainter = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(MomentProgressRing),
            matching: find.byType(CustomPaint),
          ),
        )
        .first
        .painter;

    expect(rtl, ltr);
    // Same painter configuration in both directions: the painter takes no
    // text direction at all, so the arc cannot be mirrored.
    expect(rtlPainter.runtimeType, ltrPainter.runtimeType);
    expect(
      rtlPainter!.shouldRepaint(ltrPainter!),
      isFalse,
      reason: 'nothing about the ring changes with reading direction',
    );
  });

  testWidgets('Reduce Motion drops the glow but keeps the arc', (tester) async {
    await pumpProgress(tester, reduceMotion: false);
    final lively = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(MomentProgressRing),
            matching: find.byType(CustomPaint),
          ),
        )
        .first
        .painter!;

    await pumpProgress(tester, reduceMotion: true);
    final calm = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(MomentProgressRing),
            matching: find.byType(CustomPaint),
          ),
        )
        .first
        .painter!;

    expect(calm.shouldRepaint(lively), isTrue);
    expect(find.text('40%'), findsOneWidget);
  });

  testWidgets('the percentage takes the audio accent from the ACTIVE '
      'palette, never a remembered hex', (tester) async {
    await pumpProgress(tester);
    expect(
      tester.widget<Text>(find.text('40%')).style?.color,
      AppPalette.dark.audioAccent,
    );

    await pumpProgress(tester, theme: AppTheme.lightTheme);
    expect(
      tester.widget<Text>(find.text('40%')).style?.color,
      AppPalette.light.audioAccent,
    );
  });
}
