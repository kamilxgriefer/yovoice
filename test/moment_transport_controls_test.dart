// The expanded player's transport: ±15 s, the accessible slider, the one
// dominant disc — and no speed chip, because nothing drives playback rate.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_transport_controls.dart';

void main() {
  Future<List<Duration>> pumpTransport(
    WidgetTester tester, {
    Duration position = const Duration(seconds: 20),
    Duration total = const Duration(seconds: 45),
    bool canSeek = true,
    bool busy = false,
    bool isPlaying = false,
    bool compact = false,
    VoidCallback? onTogglePlay,
    Size size = const Size(700, 900),
  }) async {
    final seeks = <Duration>[];
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              child: MomentTransportControls(
                position: position,
                total: total,
                isPlaying: isPlaying,
                busy: busy,
                canSeek: canSeek,
                compact: compact,
                onTogglePlay: onTogglePlay ?? () {},
                onSeek: seeks.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return seeks;
  }

  testWidgets('the skips move exactly fifteen seconds', (tester) async {
    final seeks = await pumpTransport(tester);

    await tester.tap(find.byKey(const ValueKey('moment-detail-skip-forward')));
    await tester.tap(find.byKey(const ValueKey('moment-detail-skip-back')));

    expect(kMomentSkipStep, const Duration(seconds: 15));
    expect(seeks, <Duration>[
      const Duration(seconds: 35),
      const Duration(seconds: 5),
    ]);
  });

  testWidgets('both ends are clamped before the player is ever asked', (
    tester,
  ) async {
    final atStart = await pumpTransport(tester, position: Duration.zero);
    await tester.tap(find.byKey(const ValueKey('moment-detail-skip-back')));
    expect(atStart, <Duration>[Duration.zero]);

    final atEnd = await pumpTransport(
      tester,
      position: const Duration(seconds: 40),
    );
    await tester.tap(find.byKey(const ValueKey('moment-detail-skip-forward')));
    expect(
      atEnd,
      <Duration>[const Duration(seconds: 45)],
      reason: 'seeking past the end lands ON the end and lets completion fire',
    );
  });

  testWidgets('nothing is loaded yet: the skips and the slider are visibly '
      'disabled, not hidden', (tester) async {
    final seeks = await pumpTransport(tester, canSeek: false);

    final back = tester.widget<IconButton>(
      find.byKey(const ValueKey('moment-detail-skip-back')),
    );
    final forward = tester.widget<IconButton>(
      find.byKey(const ValueKey('moment-detail-skip-forward')),
    );
    expect(back.onPressed, isNull);
    expect(forward.onPressed, isNull);
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('moment-detail-position')),
    );
    expect(slider.onChanged, isNull);

    await tester.tap(
      find.byKey(const ValueKey('moment-detail-skip-forward')),
      warnIfMissed: false,
    );
    expect(seeks, isEmpty);
  });

  testWidgets('the slider carries a real position value and 5-second steps', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final seeks = await pumpTransport(tester);

    final node = tester.getSemantics(
      find.byKey(const ValueKey('moment-detail-position')),
    );
    expect(node.label, 'Playback position');
    expect(node.value, '0:20 of 0:45');
    expect(node.increasedValue, '0:25 of 0:45');
    expect(node.decreasedValue, '0:15 of 0:45');

    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);

    // The same clamped seek the visible controls use.
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('moment-detail-position')),
    );
    slider.onChanged!(25000);
    await tester.pump();
    expect(seeks, <Duration>[const Duration(seconds: 25)]);
    handle.dispose();
  });

  testWidgets('the times are the same value the slider holds', (tester) async {
    await pumpTransport(tester);

    expect(find.byKey(const ValueKey('moment-detail-elapsed')), findsOneWidget);
    expect(find.text('0:20'), findsOneWidget);
    expect(find.text('0:45'), findsOneWidget);
  });

  testWidgets('one dominant disc: 72 from 600 up, 64 below it', (tester) async {
    await pumpTransport(tester);
    expect(
      tester.getSize(find.byKey(const ValueKey('moment-detail-play'))).height,
      AppSizing.audioControl,
    );

    await pumpTransport(tester, compact: true, size: const Size(390, 844));
    expect(
      tester.getSize(find.byKey(const ValueKey('moment-detail-play'))).height,
      AppSizing.audioControlCompact,
    );
  });

  testWidgets('play and pause are one toggled control', (tester) async {
    final handle = tester.ensureSemantics();
    var toggles = 0;
    await pumpTransport(tester, onTogglePlay: () => toggles++);

    expect(find.bySemanticsLabel('Play'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('moment-detail-play')));
    expect(toggles, 1);

    await pumpTransport(tester, isPlaying: true);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    handle.dispose();
  });

  testWidgets('while a grant is resolving the disc spins and refuses taps', (
    tester,
  ) async {
    var toggles = 0;
    await pumpTransport(tester, busy: true, onTogglePlay: () => toggles++);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('moment-detail-play')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('moment-detail-play')),
      warnIfMissed: false,
    );
    expect(toggles, 0);
  });

  testWidgets('no playback-speed chip is drawn and no slot is reserved for '
      'one', (tester) async {
    await pumpTransport(tester);

    expect(find.text('1×'), findsNothing);
    expect(find.text('1x'), findsNothing);
    // Exactly three controls in the transport row.
    expect(find.byType(IconButton), findsNWidgets(2));
    expect(find.byKey(const ValueKey('moment-detail-play')), findsOneWidget);
  });
}
