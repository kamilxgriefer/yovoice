import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_theme.dart';
// StoryWaveform is reached through moment_story_viewer.dart on purpose: the
// re-export is the contract that keeps every existing `show StoryWaveform`
// import and the type-pinned tests resolving.
import 'package:yovoice/features/moments/presentation/widgets/moment_story_viewer.dart'
    show StoryWaveform;
import 'package:yovoice/shared/widgets/waveform/yo_waveform.dart'
    hide StoryWaveform;

/// The one bar waveform (Slim redesign, phase 0): every decorative waveform
/// and every progress-driven Moment waveform is `YoWaveform`, so the honesty
/// rule (no amplitude = static, no ticker, no randomness), the exact box
/// contract and the StoryWaveform alias are pinned here once.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    TextDirection direction = TextDirection.ltr,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        home: Directionality(
          textDirection: direction,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('sizes exactly to height and fills the parent width', (
    tester,
  ) async {
    await pump(
      tester,
      const SizedBox(
        width: 240,
        child: YoWaveform(color: AppColors.primary, height: 32),
      ),
    );
    expect(tester.getSize(find.byType(YoWaveform)), const Size(240, 32));
    expect(find.byType(CustomPaint), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an explicit width is honoured even inside a tight parent', (
    tester,
  ) async {
    await pump(
      tester,
      const SizedBox(
        width: 300,
        height: 14,
        child: YoWaveform(
          color: AppColors.primary,
          width: 30,
          height: 14,
          barWidth: 3,
          barGap: 3,
          silhouette: [6 / 14, 11 / 14, 1, 9 / 14, 5 / 14],
        ),
      ),
    );
    // The painter box stays 30 x 14 (five bars at pitch 6), centred; the
    // parent's 300 px never turns into fifty bars.
    expect(tester.getSize(find.byType(CustomPaint)), const Size(30, 14));
    final box = tester.getRect(find.byType(CustomPaint));
    final host = tester.getRect(find.byType(YoWaveform));
    expect(box.center.dx, closeTo(host.center.dx, .01));
  });

  testWidgets('a waveform without amplitude is static: no frame scheduled, '
      'no semantics, no key of its own', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      YoWaveform(
        color: AppColors.primary,
        height: 24,
        silhouette: YoWaveform.ramp(13),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.byType(ExcludeSemantics), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(YoWaveform)).getSemanticsData().label,
      isEmpty,
    );
    expect(tester.widget<YoWaveform>(find.byType(YoWaveform)).key, isNull);
    handle.dispose();
  });

  testWidgets('a marker key passes through to the widget', (tester) async {
    await pump(
      tester,
      const YoWaveform(
        key: ValueKey('server-podcast-waveform'),
        color: AppColors.primary,
        width: 30,
        height: 14,
        barWidth: 3,
      ),
    );
    expect(find.byKey(const ValueKey('server-podcast-waveform')), findsOneWidget);
  });

  testWidgets('RTL and progress at 0, .4 and 1 render without exception', (
    tester,
  ) async {
    for (final direction in TextDirection.values) {
      for (final progress in const [0.0, .4, 1.0, 1.5, -.2]) {
        await pump(
          tester,
          SizedBox(
            width: 200,
            child: YoWaveform(
              color: AppColors.primary.withValues(alpha: .32),
              progress: progress,
              playedGradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.secondary],
              ),
              height: 32,
              barWidth: 3,
              barGap: 3,
              barRadius: 1.5,
            ),
          ),
          direction: direction,
        );
        expect(tester.takeException(), isNull, reason: '$direction $progress');
      }
    }
  });

  test('the Start ramp is the deterministic (10 + i*13 % 24) / 34 pattern', () {
    final ramp = YoWaveform.ramp(24);
    expect(ramp, hasLength(24));
    expect(ramp.first, 10 / 34);
    expect(ramp[1], 23 / 34);
    expect(ramp[2], 12 / 34);
    expect(ramp.every((value) => value > 0 && value <= 1), isTrue);
    expect(YoWaveform.bars, hasLength(30));
    expect(YoWaveform.bars.every((value) => value > 0 && value <= 1), isTrue);
  });

  testWidgets('StoryWaveform is the primitive with the Moment player defaults', (
    tester,
  ) async {
    await pump(
      tester,
      SizedBox(width: 240, child: StoryWaveform(progress: .4)),
      theme: AppTheme.lightTheme,
    );
    final wave = tester.widget<StoryWaveform>(find.byType(StoryWaveform));
    expect(wave, isA<YoWaveform>());
    expect(find.byType(YoWaveform), findsOneWidget);
    expect(wave.progress, .4);
    expect(wave.height, 44);
    expect(wave.barWidth, isNull);
    expect(wave.barGap, 3);
    expect(wave.barRadius, 2);
    expect(wave.playedColor, AppColors.secondary);
    expect(wave.color, StoryWaveform.unplayedColor());
    expect(StoryWaveform.unplayedColor(), AppColors.primary.withValues(alpha: .32));
    expect(StoryWaveform.bars, same(YoWaveform.bars));
    expect(tester.getSize(find.byType(StoryWaveform)), const Size(240, 44));
  });
}
