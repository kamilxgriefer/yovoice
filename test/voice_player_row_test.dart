import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/voice/voice_player_row.dart';
import 'package:yovoice/shared/widgets/waveform/yo_waveform.dart';

/// The one inline voice-clip row (Slim redesign, phase 0): the chat bubble
/// and the thread reply draw the same play disc, waveform and clock, so the
/// two shapes' contracts are pinned here once — including the differences
/// that are deliberate (the spinner's own colour, the bounded vs. filling
/// waveform, the semantics node shape).
void main() {
  Future<void> pumpRow(
    WidgetTester tester, {
    required VoicePlayerRow row,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        home: Scaffold(
          // Loose, exactly like the hosts: a bubble lets its content
          // shrink-wrap, a thread row is handed the column's width.
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: row,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  VoicePlayerRowStyle inline({Color foreground = Colors.white}) =>
      VoicePlayerRowStyle.inline(
        foreground: foreground,
        mutedForeground: foreground,
        errorForeground: const Color(0xFFFFE0E7),
      );

  group('the clock', () {
    test('is m:ss with no leading zero on the minutes', () {
      expect(formatVoiceClock(0), '0:00');
      expect(formatVoiceClock(7), '0:07');
      expect(formatVoiceClock(47), '0:47');
      expect(formatVoiceClock(60), '1:00');
      expect(formatVoiceClock(605), '10:05');
    });

    test('reads a negative length as silence rather than as "-1:-1"', () {
      expect(formatVoiceClock(-3), '0:00');
    });
  });

  testWidgets('every status draws its own affordance', (tester) async {
    for (final probe in <(VoicePlayerRowStatus, IconData?)>[
      (VoicePlayerRowStatus.idle, Icons.play_arrow_rounded),
      (VoicePlayerRowStatus.paused, Icons.play_arrow_rounded),
      (VoicePlayerRowStatus.playing, Icons.pause_rounded),
      (VoicePlayerRowStatus.failed, Icons.refresh_rounded),
      (VoicePlayerRowStatus.loading, null),
    ]) {
      await pumpRow(
        tester,
        row: VoicePlayerRow(
          status: probe.$1,
          durationSeconds: 12,
          semanticsLabel: 'clip',
          onTap: () {},
          style: inline(),
        ),
      );

      final icon = probe.$2;
      if (icon == null) {
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byType(Icon), findsNothing);
      } else {
        expect(find.byIcon(icon), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      }
      expect(find.text('0:12'), findsOneWidget);
    }
  });

  testWidgets('the retry glyph takes the error ink, the rest the foreground', (
    tester,
  ) async {
    await pumpRow(
      tester,
      row: VoicePlayerRow(
        status: VoicePlayerRowStatus.failed,
        durationSeconds: 3,
        semanticsLabel: 'clip',
        onTap: () {},
        style: inline(),
      ),
    );

    expect(
      tester.widget<Icon>(find.byIcon(Icons.refresh_rounded)).color,
      const Color(0xFFFFE0E7),
    );

    await pumpRow(
      tester,
      row: VoicePlayerRow(
        status: VoicePlayerRowStatus.idle,
        durationSeconds: 3,
        semanticsLabel: 'clip',
        onTap: () {},
        style: inline(foreground: const Color(0xFF123456)),
      ),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.play_arrow_rounded)).color,
      const Color(0xFF123456),
    );
  });

  // Refine-look R14: the thread row's transport became the voice bead, whose
  // busy state is a white spinner on the logo gradient (it was an
  // `audioAccent` spinner on a bordered disc). The bubble keeps its own ink.
  testWidgets('the spinner has its own ink, so a bubble can keep it readable '
      'on the brand gradient while the thread row\'s bead spins white', (
    tester,
  ) async {
    await pumpRow(
      tester,
      row: VoicePlayerRow(
        status: VoicePlayerRowStatus.loading,
        durationSeconds: 3,
        semanticsLabel: 'clip',
        onTap: () {},
        style: inline(foreground: const Color(0xFF123456)),
      ),
    );
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .color,
      const Color(0xFF123456),
    );

    await pumpRow(
      tester,
      row: VoicePlayerRow(
        status: VoicePlayerRowStatus.loading,
        durationSeconds: 3,
        semanticsLabel: 'clip',
        onTap: () {},
        style: VoicePlayerRowStyle.contained(
          AppPalette.dark,
          AppTheme.darkTheme.colorScheme,
        ),
      ),
    );
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .color,
      Colors.white,
    );
    expect(
      find.descendant(
        of: find.byType(YoGradientDisc),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the tap key sits on the whole row, which is a 44 px target', (
    tester,
  ) async {
    var taps = 0;
    await pumpRow(
      tester,
      row: VoicePlayerRow(
        status: VoicePlayerRowStatus.idle,
        durationSeconds: 12,
        semanticsLabel: 'clip',
        onTap: () => taps++,
        tapKey: const ValueKey<String>('voice-row'),
        style: inline(),
      ),
    );

    final row = find.byKey(const ValueKey<String>('voice-row'));
    expect(tester.widget(row), isA<InkWell>());
    expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(row).width, greaterThanOrEqualTo(44));

    await tester.tap(row);
    expect(taps, 1);
  });

  testWidgets('a null onTap disables the row', (tester) async {
    await pumpRow(
      tester,
      row: VoicePlayerRow(
        status: VoicePlayerRowStatus.idle,
        durationSeconds: 12,
        semanticsLabel: 'clip',
        onTap: null,
        tapKey: const ValueKey<String>('voice-row'),
        style: inline(),
      ),
    );
    expect(
      tester
          .widget<InkWell>(find.byKey(const ValueKey<String>('voice-row')))
          .onTap,
      isNull,
    );
  });

  testWidgets('no position source means a still silhouette, never a fill '
      'invented from the duration', (tester) async {
    await pumpRow(
      tester,
      row: VoicePlayerRow(
        status: VoicePlayerRowStatus.playing,
        durationSeconds: 12,
        semanticsLabel: 'clip',
        onTap: () {},
        style: inline(),
      ),
    );

    expect(find.byType(StoryWaveform), findsNothing);
    final bars = tester.widget<YoWaveform>(find.byType(YoWaveform));
    expect(bars.progress, isNull);
    expect(bars.barCount, 24);
    expect(bars.height, 32);
  });

  // Refine-look R13: the thread row now draws the R13 waveform — its own
  // `waveUnplayed` ink, the played sweep across the whole run, poured toward
  // each real position — instead of the Moment player's StoryWaveform pair.
  testWidgets('a real position pours the thread row waveform', (tester) async {
    final progress = ValueNotifier<double>(.25);
    addTearDown(progress.dispose);

    await pumpRow(
      tester,
      row: VoicePlayerRow(
        status: VoicePlayerRowStatus.playing,
        durationSeconds: 12,
        semanticsLabel: 'clip',
        onTap: () {},
        progress: progress,
        style: VoicePlayerRowStyle.contained(
          AppPalette.dark,
          AppTheme.darkTheme.colorScheme,
        ),
      ),
    );

    YoWaveform wave() => tester.widget<YoWaveform>(find.byType(YoWaveform));
    expect(find.byType(StoryWaveform), findsNothing);
    expect(wave().progress, .25, reason: 'the first position is painted');
    expect(wave().color, AppPalette.dark.waveUnplayed);
    expect(wave().continuousProgress, isTrue);
    expect(wave().gradientSpan, YoWaveformGradientSpan.full);

    progress.value = .8;
    await tester.pump();
    await tester.pump(VoicePourWaveform.pourDuration ~/ 2);
    expect(
      wave().progress,
      allOf(greaterThan(.25), lessThan(.8)),
      reason: 'the fill pours toward the new position, never past it',
    );
    await tester.pump(VoicePourWaveform.pourDuration);
    expect(wave().progress, closeTo(.8, 1e-9));
  });

  testWidgets('the inline row shrink-wraps and the contained row fills', (
    tester,
  ) async {
    await pumpRow(
      tester,
      row: VoicePlayerRow(
        status: VoicePlayerRowStatus.idle,
        durationSeconds: 12,
        semanticsLabel: 'clip',
        onTap: () {},
        tapKey: const ValueKey<String>('voice-row'),
        style: inline(),
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('voice-row'))).width,
      lessThan(320),
    );

    await pumpRow(
      tester,
      row: VoicePlayerRow(
        status: VoicePlayerRowStatus.idle,
        durationSeconds: 12,
        semanticsLabel: 'clip',
        onTap: () {},
        tapKey: const ValueKey<String>('voice-row'),
        style: VoicePlayerRowStyle.contained(
          AppPalette.dark,
          AppTheme.darkTheme.colorScheme,
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('voice-row'))).width,
      320,
    );
  });

  testWidgets('the contained row draws its own surface; the inline row leaves '
      'that to the bubble', (tester) async {
    await pumpRow(
      tester,
      row: VoicePlayerRow(
        status: VoicePlayerRowStatus.idle,
        durationSeconds: 12,
        semanticsLabel: 'clip',
        onTap: () {},
        style: VoicePlayerRowStyle.contained(
          AppPalette.dark,
          AppTheme.darkTheme.colorScheme,
        ),
      ),
    );
    final surface = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(VoicePlayerRow),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(surface.color, AppPalette.dark.surfaceMuted);

    await pumpRow(
      tester,
      row: VoicePlayerRow(
        status: VoicePlayerRowStatus.idle,
        durationSeconds: 12,
        semanticsLabel: 'clip',
        onTap: () {},
        style: inline(),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(VoicePlayerRow),
        matching: find.byType(Material),
      ),
      findsNothing,
    );
  });

  testWidgets('an own node carries the label, the toggle and the tap action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await pumpRow(
      tester,
      row: VoicePlayerRow(
        status: VoicePlayerRowStatus.playing,
        durationSeconds: 12,
        semanticsLabel: 'Pause this clip',
        onTap: () => taps++,
        semanticsContainer: true,
        excludeChildSemantics: true,
        toggled: true,
        style: VoicePlayerRowStyle.contained(
          AppPalette.dark,
          AppTheme.darkTheme.colorScheme,
        ),
      ),
    );

    final node = find.bySemanticsLabel('Pause this clip');
    expect(node, findsOneWidget);
    expect(
      tester.getSemantics(node),
      matchesSemantics(
        label: 'Pause this clip',
        isButton: true,
        isToggled: true,
        hasToggledState: true,
        hasTapAction: true,
      ),
    );

    final semantics = tester.getSemantics(node);
    semantics.owner!.performAction(semantics.id, SemanticsAction.tap);
    await tester.pump();
    expect(taps, 1, reason: 'excluded children must not take the action away');
    handle.dispose();
  });

  testWidgets('the bubble shape keeps its children visible to finders', (
    tester,
  ) async {
    await pumpRow(
      tester,
      row: VoicePlayerRow(
        status: VoicePlayerRowStatus.idle,
        durationSeconds: 12,
        semanticsLabel: 'Play this clip',
        onTap: () {},
        style: inline(),
      ),
    );

    // The bubble's node is a plain labelled button over children that keep
    // their own semantics, which is how the chat tests drive it (by icon)
    // and how the long press reaches the context-action wrapper above.
    final node = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(VoicePlayerRow),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(node.properties.label, 'Play this clip');
    expect(node.properties.button, isTrue);
    expect(
      node.properties.toggled,
      isNull,
      reason: 'the bubble row has never carried a toggled flag',
    );
    expect(
      node.excludeSemantics,
      isFalse,
      reason: 'excluding them would hide the icons the chat tests tap',
    );
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
  });

  group('keyboard focus', () {
    /// Every 2 px ring drawn inside the row, read off the decorations.
    List<Color> rings(WidgetTester tester) => tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(VoicePlayerRow),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.border)
        .whereType<Border>()
        .where((border) => border.top.width >= 2)
        .map((border) => border.top.color)
        .toList();

    testWidgets('the thread row draws a 2 px focus ring in the palette focus '
        'ink, and nothing while unfocused', (tester) async {
      for (final (theme, palette) in [
        (AppTheme.darkTheme, AppPalette.dark),
        (AppTheme.lightTheme, AppPalette.light),
      ]) {
        await pumpRow(
          tester,
          theme: theme,
          row: VoicePlayerRow(
            status: VoicePlayerRowStatus.idle,
            durationSeconds: 12,
            semanticsLabel: 'clip',
            onTap: () {},
            style: VoicePlayerRowStyle.contained(palette, theme.colorScheme),
          ),
        );
        expect(rings(tester), isNot(contains(palette.focus)));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(rings(tester), contains(palette.focus));
        // Start the next theme from a fresh tree with nothing focused.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('the bubble row rings in its own ink, which reads on the '
        'brand gradient', (tester) async {
      await pumpRow(
        tester,
        row: VoicePlayerRow(
          status: VoicePlayerRowStatus.idle,
          durationSeconds: 12,
          semanticsLabel: 'clip',
          onTap: () {},
          style: inline(),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(rings(tester), contains(Colors.white));
    });
  });
}
