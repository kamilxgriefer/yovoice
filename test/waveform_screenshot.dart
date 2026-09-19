// Developer-only VISUAL harness for the one bar waveform (ADR-209).
//
// NOT a test; the name has no `_test` suffix so `flutter test` skips it.
// Run explicitly:
//
//   flutter test test/waveform_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored).
//
// Why this exists: `yo_waveform_test.dart` proves the box contract, the
// stillness and the StoryWaveform alias — never that a bar renders. The
// host harnesses that would show the migrated surfaces either do not mount
// them (Chats bubble, MomentCard sheet, podcast stage) or fail on a fixture
// stream before the frame (desktop `roster-*`, the story viewer), so this
// renders the primitive itself in every configuration a host passes, side
// by side, in Dark and Pearl, LTR and RTL, so a person can look at each
// motif once per theme.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/waveform/yo_waveform.dart';

final _capture = GlobalKey();

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final warmup = await boundary.toImage(pixelRatio: 2);
    warmup.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('test/.screenshots/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

Widget _row(String label, Widget wave, Color ink) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 8),
  child: Row(
    children: [
      SizedBox(
        width: 220,
        child: Text(label, style: TextStyle(color: ink, fontSize: 12)),
      ),
      const SizedBox(width: 12),
      Expanded(child: wave),
    ],
  ),
);

/// Every configuration a migrated host passes today, one row each.
List<Widget> _rows(BuildContext context) {
  final palette = context.appPalette;
  final ink = palette.textSecondary;
  final gradient = palette.audioProgressGradient;
  return [
    _row(
      'Start hero motif (ramp 13, 96x24)',
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: YoWaveform(
          color: AppColors.primary.withValues(alpha: .9),
          width: 96,
          height: 24,
          silhouette: YoWaveform.ramp(13),
          barGap: 96 / 13 * .42,
        ),
      ),
      ink,
    ),
    _row(
      'Legacy Home Moment row (ramp 24, h34, r10)',
      YoWaveform(
        color: palette.interactiveForeground,
        height: 34,
        silhouette: YoWaveform.ramp(24),
        barGap: 3,
        barRadius: 10,
      ),
      ink,
    ),
    _row(
      'MomentCard (30 bars, h26, gap 2.4)',
      YoWaveform(
        height: 26,
        color: AppColors.primary.withValues(alpha: .45),
        barGap: 2.4,
        barRadius: 2,
      ),
      ink,
    ),
    _row(
      'Voice message (24 bars, h32, pill)',
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 126),
        child: YoWaveform(
          height: 32,
          color: palette.textPrimary.withValues(alpha: .82),
          barCount: 24,
          barGap: 2,
          barRadius: 20,
        ),
      ),
      ink,
    ),
    _row(
      'Podcast speaking mark (5 bars, 30x14)',
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: YoWaveform(
          color: palette.textPrimary,
          width: 30,
          height: 14,
          barWidth: 3,
          barGap: 3,
          barRadius: 2,
          silhouette: const [6 / 14, 11 / 14, 1, 9 / 14, 5 / 14],
        ),
      ),
      ink,
    ),
    for (final progress in const [0.0, .4, 1.0])
      _row(
        'Story stage flex, progress $progress',
        StoryWaveform(progress: progress, height: 44),
        ink,
      ),
    for (final progress in const [0.0, .4, 1.0])
      _row(
        'Moment detail tiled 4/4, progress $progress',
        StoryWaveform(
          progress: progress,
          height: 56,
          barWidth: 4,
          barGap: 4,
          barRadius: 2,
          playedGradient: gradient,
        ),
        ink,
      ),
    _row(
      'Feed transport tiled 3/3, progress .4',
      StoryWaveform(
        progress: .4,
        height: 32,
        barWidth: 3,
        barGap: 3,
        barRadius: 1.5,
        playedGradient: gradient,
      ),
      ink,
    ),
    _row(
      'Voice reply mini player 2/3, progress .4',
      StoryWaveform(
        progress: .4,
        height: 20,
        barWidth: 2,
        barGap: 3,
        barRadius: 1,
        playedGradient: gradient,
      ),
      ink,
    ),
  ];
}

void main() {
  for (final themeCase in <({String name, ThemeData theme})>[
    (name: 'dark', theme: AppTheme.darkTheme),
    (name: 'pearl', theme: AppTheme.lightTheme),
  ]) {
    for (final direction in TextDirection.values) {
      final name = 'waveform-${themeCase.name}-${direction.name}-600';
      testWidgets(name, (tester) async {
        tester.view.physicalSize = const Size(600, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: themeCase.theme,
            home: Directionality(
              textDirection: direction,
              child: RepaintBoundary(
                key: _capture,
                child: Builder(
                  builder: (context) => Scaffold(
                    backgroundColor: context.appPalette.background,
                    body: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: _rows(context)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await _shoot(tester, name);
      });
    }
  }
}
