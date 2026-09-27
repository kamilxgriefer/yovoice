import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' show Amplitude;

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';

import 'voice_moment_test_doubles.dart';

/// Refine-look W4, "the record button listens" (spec §5), and the
/// recorder's immersive block finish.
///
/// The halo is the record bead's own shadow, driven by the SAME normalised
/// sample the level meter draws, smoothed (attack .6 / release .25) and
/// eased over 140 ms through a notifier only the halo listens to. Silence is
/// a still halo, the web keeps it still, Reduce Motion fixes it, and high
/// contrast removes it.
void main() {
  const medium = Size(768, 1024);

  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget host(
    Widget child, {
    bool disableAnimations = false,
    bool highContrast = false,
    ThemeData? theme,
  }) => MaterialApp(
    theme: theme ?? AppTheme.darkTheme,
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: disableAnimations,
        highContrast: highContrast,
      ),
      child: inner!,
    ),
    home: child,
  );

  ({
    FakeRecorderBackend backend,
    FakeAudioCapture capture,
    FakeStopwatch clock,
    Widget screen,
  })
  build() {
    final backend = FakeRecorderBackend();
    final capture = FakeAudioCapture()..result = FakeRecordedAudio();
    final clock = FakeStopwatch();
    return (
      backend: backend,
      capture: capture,
      clock: clock,
      screen: RecordVoiceMomentScreen(
        recorder: VoiceMomentRecorder(
          backend: backend,
          capture: capture,
          clock: clock,
        ),
        momentService: StubMomentService(),
        previewPlayerFactory: FakePreviewAudioPlayer.new,
      ),
    );
  }

  Future<void> startRecording(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();
    await tester.pump();
    expect(find.text('Recording — tap to stop.'), findsOneWidget);
  }

  final halo = find.byKey(const ValueKey('voice-record-halo'));

  BoxShadow haloShadow(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(halo);
    final shadows = (box.decoration as BoxDecoration).boxShadow!;
    expect(shadows, hasLength(1));
    return shadows.single;
  }

  void expectHaloAt(WidgetTester tester, double level) {
    final shadow = haloShadow(tester);
    expect(shadow.color.a, closeTo(.30 + .35 * level, 1e-3));
    expect(shadow.color.r, closeTo(AppColors.live.r, 1e-3));
    expect(shadow.blurRadius, closeTo(28 + 24 * level, 1e-3));
    expect(shadow.spreadRadius, closeTo(2 + 4 * level, 1e-3));
  }

  group('the halo level', () {
    test('rises with attack .6 and settles with release .25', () {
      expect(voiceMomentHaloAttack, .6);
      expect(voiceMomentHaloRelease, .25);
      final rise = voiceMomentHaloLevel(0, .8, isWeb: false);
      expect(rise, closeTo(.48, 1e-9));
      final fall = voiceMomentHaloLevel(rise, .2, isWeb: false);
      expect(fall, closeTo(.48 + (.2 - .48) * .25, 1e-9));
    });

    test('silence settles to a still 0 instead of creeping forever', () {
      var level = 1.0;
      var steps = 0;
      while (level > 0 && steps < 100) {
        level = voiceMomentHaloLevel(level, 0, isWeb: false);
        steps++;
      }
      expect(level, 0);
      expect(steps, lessThan(20), reason: 'about two seconds at 8 Hz');
      expect(voiceMomentHaloLevel(0, 0, isWeb: false), 0);
    });

    test('the web keeps a still halo whatever the meter reads', () {
      expect(voiceMomentHaloLevel(0, 1, isWeb: true), 0);
      expect(voiceMomentHaloLevel(.7, .9, isWeb: true), 0);
    });

    test('a broken sample is read as silence, never as light', () {
      expect(voiceMomentHaloLevel(0, double.nan, isWeb: false), 0);
      expect(voiceMomentHaloLevel(0, double.infinity, isWeb: false), 0);
      expect(voiceMomentHaloLevel(0, 4, isWeb: false), closeTo(.6, 1e-9));
    });
  });

  group('the record bead', () {
    testWidgets('idle is the R14 bead at 96 with the R6 lift and a 38 mic', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      final region = find.ancestor(
        of: find.byIcon(Icons.mic_rounded),
        matching: find.byType(AccessibleTapRegion),
      );
      expect(region, findsOneWidget);
      // The bead keeps its 96 px layout slot (and hit target); the region is
      // 5 px wider on every side, centred on the bead, so its focus ring
      // sits 3 px outside the bead (R14) instead of on the gradient's edge.
      final bead = find.byKey(const ValueKey('voice-record-bead'));
      expect(tester.getSize(bead), const Size(96, 96));
      expect(tester.getSize(region), const Size(106, 106));
      expect(tester.getCenter(region), tester.getCenter(bead));
      final slot = find
          .ancestor(of: region, matching: find.byType(SizedBox))
          .first;
      expect(tester.getSize(slot), const Size(96, 96));
      expect(tester.getCenter(slot), tester.getCenter(bead));

      final discs = tester
          .widgetList<YoGradientDisc>(
            find.descendant(of: region, matching: find.byType(YoGradientDisc)),
          )
          .toList();
      final brand = discs.firstWhere((d) => d.tone == YoDiscTone.brand);
      expect(brand.size, 96);
      expect(brand.gloss, isTrue);
      expect(brand.emphasis, YoDiscEmphasis.lift);

      final mic = tester.widget<Icon>(find.byIcon(Icons.mic_rounded));
      expect(mic.size, 38);
      expect(mic.color, Colors.white);
      expect(halo, findsNothing, reason: 'no light before a voice');
    });

    testWidgets('recording is the live bead; its halo follows the meter', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await startRecording(tester);
      await tester.pump(const Duration(milliseconds: 250));

      final stop = tester.widget<Icon>(find.byIcon(Icons.stop_rounded));
      expect(stop.color, AppColors.onLive);
      expect(stop.size, 38);
      final live = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byWidgetPredicate(
            (w) => w is YoGradientDisc && w.tone == YoDiscTone.live,
          ),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(live.opacity, 1);
      expect(live.duration, const Duration(milliseconds: 220));

      // Silence: a still halo at its base.
      expect(halo, findsOneWidget);
      expectHaloAt(tester, 0);

      // -9 dBFS normalises to .8; one attack step lifts the halo to .48.
      harness.backend.amplitudes.add(Amplitude(current: -9, max: 0));
      await tester.pump();
      final clockBefore = tester.widget<Text>(find.text('0:00 / 1:00'));
      await tester.pump(const Duration(milliseconds: 60));
      final mid = haloShadow(tester).color.a;
      expect(mid, greaterThan(.30));
      expect(mid, lessThan(.30 + .35 * .48));
      expect(
        identical(tester.widget<Text>(find.text('0:00 / 1:00')), clockBefore),
        isTrue,
        reason: 'the halo eases on its own; the screen is not rebuilt',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expectHaloAt(tester, .48);

      // A quieter sample releases slowly (release .25), not at once.
      harness.backend.amplitudes.add(Amplitude(current: -45, max: 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expectHaloAt(tester, .48 * .75);
    });

    testWidgets('a lost level stream puts the halo out', (tester) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await startRecording(tester);

      harness.backend.amplitudes.add(Amplitude(current: 0, max: 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expectHaloAt(tester, .6);

      harness.backend.amplitudes.addError(StateError('analyser detached'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expectHaloAt(tester, 0);
    });

    testWidgets('Reduce Motion holds one fixed halo and snaps the glyph', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen, disableAnimations: true));
      await tester.pumpAndSettle();
      await startRecording(tester);

      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

      harness.backend.amplitudes.add(Amplitude(current: 0, max: 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final shadow = haloShadow(tester);
      expect(shadow.color.a, closeTo(.42, 1e-3));
      expect(shadow.blurRadius, 28);
    });

    testWidgets('high contrast keeps the solid disc and drops every glow', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen, highContrast: true));
      await tester.pumpAndSettle();
      await startRecording(tester);
      harness.backend.amplitudes.add(Amplitude(current: 0, max: 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(halo, findsNothing);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    });

    for (final (themeName, theme) in [
      ('Dark', AppTheme.darkTheme),
      ('Pearl', AppTheme.lightTheme),
    ]) {
      testWidgets('keyboard focus rings the bead 3 px outside it, and the '
          'ring reads ($themeName)', (tester) async {
        useSurface(tester, medium);
        final strategy = FocusManager.instance.highlightStrategy;
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
        final harness = build();
        await tester.pumpWidget(host(harness.screen, theme: theme));
        await tester.pumpAndSettle();

        final bead = find.byKey(const ValueKey('voice-record-bead'));
        final beadRect = tester.getRect(bead);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.ancestor(of: bead, matching: find.byType(RepaintBoundary)).first,
        );
        final origin = boundary.localToGlobal(Offset.zero);
        Future<ByteData> shot() async => (await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            return await image.toByteData();
          } finally {
            image.dispose();
          }
        }))!;
        Color pixel(ByteData bytes, Offset global) {
          final x = (global.dx - origin.dx).floor();
          final y = (global.dy - origin.dy).floor();
          final i = (y * boundary.size.width.round() + x) * 4;
          return Color.fromARGB(
            bytes.getUint8(i + 3),
            bytes.getUint8(i),
            bytes.getUint8(i + 1),
            bytes.getUint8(i + 2),
          );
        }

        double contrast(Color a, Color b) {
          final la = a.computeLuminance();
          final lb = b.computeLuminance();
          return la > lb ? (la + .05) / (lb + .05) : (lb + .05) / (la + .05);
        }

        final c = beadRect.center;
        final r = beadRect.width / 2;
        // [ring] 4 px outside the bead: the middle of the 2 px ring (3–5 px
        // out). [edge] 1 px inside it: the bead's own rim.
        List<Offset> around(double d) => [
          Offset(c.dx - d, c.dy),
          Offset(c.dx + d - 1, c.dy),
          Offset(c.dx, c.dy - d),
          Offset(c.dx, c.dy + d - 1),
        ];
        final ring = around(r + 4);
        final edge = around(r - 1);
        final rest = await shot();

        Focus.of(tester.element(find.byIcon(Icons.mic_rounded))).requestFocus();
        // The region's ring fades in over 120 ms from the frame after the
        // focus change; a single long pump would only start it.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        final focused = await shot();
        expect(tester.getRect(bead), beadRect, reason: 'focus moves nothing');

        // The capture screen is immersive-dark in both app themes: its ring
        // is the palette in force around the bead.
        final palette = tester.element(bead).appPalette;
        for (final at in ring) {
          final was = pixel(rest, at);
          final now = pixel(focused, at);
          expect(
            contrast(now, palette.focus),
            lessThan(1.15),
            reason: '$at is the focus ring, got $now',
          );
          expect(
            contrast(now, was),
            greaterThanOrEqualTo(3),
            reason: '$at: ring $now against rest $was',
          );
        }
        // The ring is not drawn over the gradient's own edge any more.
        for (final at in edge) {
          expect(
            contrast(pixel(focused, at), palette.focus),
            greaterThan(1.15),
            reason: '$at: the bead\'s rim stays the bead',
          );
        }
      });
    }

    testWidgets('requesting shows the bead at 35 % with a white spinner', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      // A microphone prompt that never answers holds the requesting phase.
      harness.capture.microphoneGate = Completer<MicrophoneAccess>();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Waiting for microphone access…'), findsOneWidget);
      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(spinner.color, Colors.white);
      final brand = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byWidgetPredicate(
            (w) => w is YoGradientDisc && w.tone == YoDiscTone.brand,
          ),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(brand.opacity, .35);
      expect(halo, findsNothing);

      // Leave the way a person would: cancel the stalled prompt.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      harness.capture.microphoneGate!.complete(
        const MicrophoneAccess.granted(),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });
  });

  group('haptics', () {
    List<String> captureHaptics(WidgetTester tester) {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            calls.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      return calls;
    }

    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      testWidgets('${platform.name}: medium on start, light on stop', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          useSurface(tester, medium);
          final haptics = captureHaptics(tester);
          final harness = build();
          await tester.pumpWidget(host(harness.screen));
          await tester.pumpAndSettle();
          await startRecording(tester);
          expect(haptics, <String>['HapticFeedbackType.mediumImpact']);

          harness.clock.value = const Duration(seconds: 3);
          await tester.pump(const Duration(milliseconds: 250));
          await tester.tap(find.byIcon(Icons.stop_rounded));
          await tester.pump();
          await tester.pump();
          expect(haptics, <String>[
            'HapticFeedbackType.mediumImpact',
            'HapticFeedbackType.lightImpact',
          ]);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('desktop records without haptics', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        useSurface(tester, const Size(1440, 900));
        final haptics = captureHaptics(tester);
        final harness = build();
        await tester.pumpWidget(host(harness.screen));
        await tester.pumpAndSettle();
        await startRecording(tester);
        harness.clock.value = const Duration(seconds: 3);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byIcon(Icons.stop_rounded));
        await tester.pump();
        await tester.pump();
        expect(haptics, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('the immersive block finish', () {
    BoxDecoration decorationOf(WidgetTester tester, Key key) =>
        tester.widget<Container>(find.byKey(key)).decoration! as BoxDecoration;

    testWidgets('panels are top-lit under a white hairline, in both themes', (
      tester,
    ) async {
      for (final theme in <ThemeData>[
        AppTheme.darkTheme,
        AppTheme.lightTheme,
      ]) {
        useSurface(tester, medium);
        final harness = build();
        await tester.pumpWidget(host(harness.screen, theme: theme));
        await tester.pumpAndSettle();

        final stage = decorationOf(
          tester,
          const ValueKey('voice-moment-capture-stage'),
        );
        final gradient = stage.gradient! as LinearGradient;
        expect(gradient.begin, Alignment.topCenter);
        expect(gradient.end, Alignment.bottomCenter);
        expect(gradient.colors, <Color>[
          AppImmersiveColors.surfaceRaised.withValues(alpha: .92),
          AppImmersiveColors.surface.withValues(alpha: .92),
        ]);
        expect(stage.borderRadius, BorderRadius.circular(28));
        final edge = (stage.border! as Border).top;
        expect(edge.color, AppColors.white.withValues(alpha: .10));
        expect(edge.width, 1);
        expect(stage.boxShadow, isNull, reason: 'the bead is the light');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('high contrast panels are flat with borderStrong', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen, highContrast: true));
      await tester.pumpAndSettle();

      final stage = decorationOf(
        tester,
        const ValueKey('voice-moment-capture-stage'),
      );
      expect(stage.gradient, isNull);
      expect(stage.color, AppImmersiveColors.surface);
      expect((stage.border! as Border).top.color, AppPalette.dark.borderStrong);
    });

    testWidgets('the active step is a primary wash with a gradient number', (
      tester,
    ) async {
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();

      final steps = find.descendant(
        of: find.byKey(const ValueKey('voice-moment-flow-progress')),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).borderRadius ==
                  BorderRadius.circular(16),
        ),
      );
      final decorations = tester
          .widgetList<Container>(steps)
          .map((c) => c.decoration! as BoxDecoration)
          .toList();
      expect(decorations, hasLength(2));
      final active = decorations.first;
      expect(active.color, AppColors.primary.withValues(alpha: .14));
      expect(
        (active.border! as Border).top,
        BorderSide(color: AppColors.primary.withValues(alpha: .55), width: 1.5),
      );
      final inactive = decorations.last;
      expect(inactive.color, AppColors.white.withValues(alpha: .03));
      expect(
        (inactive.border! as Border).top.color,
        AppColors.white.withValues(alpha: .06),
      );

      final numberDisc = find.descendant(
        of: find.byKey(const ValueKey('voice-moment-flow-progress')),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).gradient == AppGradients.primary,
        ),
      );
      expect(numberDisc, findsOneWidget);
    });

    testWidgets('the review slider keeps a visible inactive track', (
      tester,
    ) async {
      // The lit panel swallowed the theme's dark inactive track, so the
      // preview slider draws it in the screen's control ink (≥ 3:1 on the
      // panel).
      useSurface(tester, medium);
      final harness = build();
      await tester.pumpWidget(host(harness.screen));
      await tester.pumpAndSettle();
      await startRecording(tester);
      harness.clock.value = const Duration(seconds: 4);
      await tester.pump(const Duration(milliseconds: 200));
      final stop = find.byIcon(Icons.stop_rounded);
      await tester.ensureVisible(stop);
      await tester.pump();
      await tester.tap(stop);
      await tester.pump();
      await tester.pump();

      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('voice-preview-seek')),
      );
      expect(slider.inactiveColor, AppImmersiveColors.textTertiary);
      await tester.pumpWidget(const SizedBox());
    });

    for (final highContrast in <bool>[false, true]) {
      testWidgets('the unavailable card\'s Back is a neutral tonal action '
          '(high contrast: $highContrast)', (tester) async {
        useSurface(tester, medium);
        final capture = FakeAudioCapture()
          ..support = const CaptureSupport.unsupported(
            reason: 'This browser cannot record MP4/AAC audio.',
            action: 'Open YO Voice in Chrome, Edge or Safari to record.',
          );
        await tester.pumpWidget(
          host(
            RecordVoiceMomentScreen(
              recorder: VoiceMomentRecorder(
                backend: FakeRecorderBackend(),
                capture: capture,
                clock: FakeStopwatch(),
              ),
              momentService: StubMomentService(),
              previewPlayerFactory: FakePreviewAudioPlayer.new,
            ),
            highContrast: highContrast,
          ),
        );
        await tester.pumpAndSettle();

        final button = tester.widget<OutlinedButton>(
          find.ancestor(
            of: find.text('Go back'),
            matching: find.byType(OutlinedButton),
          ),
        );
        final style = button.style!;
        final side = style.side!.resolve(<WidgetState>{})!;
        final fill = style.backgroundColor?.resolve(<WidgetState>{});
        if (highContrast) {
          expect(side.color, AppPalette.dark.borderStrong);
          expect(fill, isNull);
        } else {
          expect(side.color, AppPalette.dark.hairlineControl);
          expect(fill, AppPalette.dark.glass);
        }
        expect(side.color, isNot(AppImmersiveColors.border));
      });
    }
  });
}
