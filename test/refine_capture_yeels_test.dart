// Refine-look batch 6 — capture and Yeels (spec §3 R2 / R6 / R14, §5 W4,
// §8.4). What these tests pin:
//
// * W4, the record button listens: the idle bead is the R6-lifted brand bead
//   with gloss; recording cross-fades a solid live bead in, and its halo is
//   the bead's own shadow, growing with the REAL input level and settling in
//   silence; Reduce Motion fixes the halo, high contrast drops it; a medium
//   haptic on start and a light one on stop.
// * The recorder's immersive block finish (panels) and its flow steps, and
//   the review preview's unplayed track staying visible on that finish.
// * The immersive "+" as the 48 px R6 disc — on the canvas and over media,
//   where it takes the Dark palette in both themes — and the create sheet's
//   R2 tiles with the 44 px icon circle.
// * The §8.4 Yeels plates (black @ .55, a white @ .14 hairline without a
//   ring — `AppFinish` tokens, the .55 shared with the chip plate) and the
//   Yeel progress bar: a white played run with the brand tip, 3:1 or more
//   against the unplayed track (§8.4 as amended by the batch-6 review).
// * The batch-6 review of the recorder: the halo's reach, the review step's
//   R14 preview bead, R5 "Opublikuj", the R8 availability selection and the
//   preview slider's colours at 3:1 or more on the raised panel.

import 'dart:math' as math;

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' show Amplitude;

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_progress_row.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/cards/yo_card.dart';
import 'package:yovoice/shared/widgets/interactions/yo_press_feedback.dart';
import 'package:yovoice/shared/widgets/navigation/yo_moments_icon.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_feed_chrome.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart';

import 'voice_moment_test_doubles.dart';

Widget _host(
  Widget child, {
  ThemeData? theme,
  bool disableAnimations = false,
  bool highContrast = false,
}) => MaterialApp(
  theme: theme ?? AppTheme.darkTheme,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  navigatorObservers: <NavigatorObserver>[appRouteObserver],
  builder: (context, inner) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: disableAnimations,
      highContrast: highContrast,
    ),
    child: inner!,
  ),
  home: child,
);

void _useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// dBFS for a normalised level (the inverse of
/// [VoiceMomentRecorder.normalizeAmplitude] over its -45 dB floor).
Amplitude _sample(double level) =>
    Amplitude(current: -45 + 45 * level, max: 0);

double _luminance(Color color) => color.computeLuminance();

/// WCAG contrast of two opaque colours.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
}

/// The recorder panel's two fill stops (`_panelFill`: the raised surface
/// into the surface, both @ .92) laid over the backdrop.
final List<Color> _panelStops = <Color>[
  for (final stop in <Color>[
    AppImmersiveColors.surfaceRaised,
    AppImmersiveColors.surface,
  ])
    Color.alphaBlend(
      stop.withValues(alpha: .92),
      AppImmersiveColors.background,
    ),
];

void main() {
  group('W4 — the halo recipe', () {
    test('the level eases up fast (.6) and falls away slowly (.25)', () {
      expect(voiceRecordHaloLevel(0, .8), closeTo(.48, 1e-9));
      expect(voiceRecordHaloLevel(.48, 0), closeTo(.36, 1e-9));
      expect(voiceRecordHaloLevel(.2, .2), closeTo(.2, 1e-9));
      expect(voiceRecordHaloLevel(0, 4), closeTo(.6, 1e-9));
      expect(voiceRecordHaloLevel(.5, double.nan), closeTo(.375, 1e-9));
    });

    test('silence is a still, quiet halo; a full voice swells it', () {
      final quiet = voiceRecordHalo(0).single;
      expect(quiet.color, AppColors.live.withValues(alpha: .30));
      expect(quiet.blurRadius, 28);
      expect(quiet.spreadRadius, 2);
      final loud = voiceRecordHalo(1).single;
      expect(loud.color.a, closeTo(.65, 1e-6));
      expect(loud.color.withValues(alpha: 1), AppColors.live);
      // The batch-6 review (a deliberate change of W4's first geometry,
      // blur 28 + 24 L / spread 2 + 4 L, whose red reached 41-45 px past the
      // disc against the spec's ~26 px): the swell is mostly light, its
      // reach grows only a little.
      expect(loud.blurRadius, 32);
      expect(loud.spreadRadius, 3);
      expect(voiceRecordHalo(3).single.blurRadius, 32);
    });

    test('Reduce Motion is the fixed .42 / blur 28 halo', () {
      final fixed = voiceRecordHalo(.9, reduceMotion: true).single;
      expect(fixed.color, AppColors.live.withValues(alpha: .42));
      expect(fixed.blurRadius, 28);
      expect(fixed.spreadRadius, 3);
    });
  });

  group('W4 — the record bead', () {
    ({FakeRecorderBackend backend, Widget screen}) build() {
      final backend = FakeRecorderBackend();
      return (
        backend: backend,
        screen: RecordVoiceMomentScreen(
          recorder: VoiceMomentRecorder(
            backend: backend,
            capture: FakeAudioCapture()..result = FakeRecordedAudio(),
            clock: FakeStopwatch(),
          ),
          momentService: StubMomentService(),
        ),
      );
    }

    final bead = find.byKey(const ValueKey<String>('voice-record-bead'));
    final halo = find.byKey(const ValueKey<String>('voice-record-halo'));

    List<YoGradientDisc> discs(WidgetTester tester) => tester
        .widgetList<YoGradientDisc>(
          find.descendant(of: bead, matching: find.byType(YoGradientDisc)),
        )
        .toList();

    double liveOpacity(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(
          find.byKey(const ValueKey<String>('voice-record-live')),
        )
        .opacity;

    BoxShadow haloShadow(WidgetTester tester) =>
        (tester.widget<DecoratedBox>(halo).decoration as BoxDecoration)
            .boxShadow!
            .single;

    Future<void> startRecording(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('idle is the lifted brand bead with gloss and a white mic', (
      tester,
    ) async {
      _useSurface(tester, const Size(390, 844));
      await tester.pumpWidget(_host(build().screen));
      await tester.pumpAndSettle();

      expect(tester.getSize(bead), const Size(96, 96));
      final brand = discs(tester).first;
      expect(brand.size, 96);
      expect(brand.tone, YoDiscTone.brand);
      expect(brand.emphasis, YoDiscEmphasis.lift);
      expect(brand.gloss, isTrue);
      final live = discs(tester).last;
      expect(live.tone, YoDiscTone.live);
      expect(live.gloss, isTrue);
      expect(liveOpacity(tester), 0);

      final mic = tester.widget<Icon>(find.byIcon(Icons.mic_rounded));
      expect(mic.color, AppColors.white);
      expect(mic.size, 38);
      // R14's press: .94 under a finger.
      final press = tester.widget<YoPressFeedback>(
        find.ancestor(of: bead, matching: find.byType(YoPressFeedback)),
      );
      expect(press.scale, YoPressFeedback.disc);
      expect(press.enabled, isTrue);
      // The record region keeps its label; the bead adds no node.
      expect(find.bySemanticsLabel('Start recording'), findsOneWidget);
    });

    testWidgets('recording fades the live bead in and its halo follows the '
        'real input level', (tester) async {
      _useSurface(tester, const Size(390, 844));
      final harness = build();
      await tester.pumpWidget(_host(harness.screen));
      await tester.pumpAndSettle();
      await startRecording(tester);

      expect(liveOpacity(tester), 1);
      final stop = tester.widget<Icon>(find.byIcon(Icons.stop_rounded));
      expect(stop.color, AppColors.onLive);
      expect(stop.size, 38);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      expect(find.bySemanticsLabel('Stop recording'), findsOneWidget);
      // Nothing measured yet: the silent halo.
      expect(haloShadow(tester).blurRadius, 28);

      harness.backend.amplitudes.add(_sample(.8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final swell = haloShadow(tester);
      final expected = voiceRecordHalo(.48).single;
      expect(swell.blurRadius, closeTo(expected.blurRadius, .01));
      expect(swell.spreadRadius, closeTo(expected.spreadRadius, .01));
      expect(swell.color.a, closeTo(expected.color.a, .01));

      // Silence: the halo settles back (release .25), it never jumps.
      harness.backend.amplitudes.add(_sample(0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final settling = haloShadow(tester).blurRadius;
      expect(settling, lessThan(swell.blurRadius));
      expect(
        settling,
        closeTo(voiceRecordHalo(.36).single.blurRadius, .01),
      );
    });

    testWidgets('a lost level stream settles the halo to silence', (
      tester,
    ) async {
      _useSurface(tester, const Size(390, 844));
      final harness = build();
      await tester.pumpWidget(_host(harness.screen));
      await tester.pumpAndSettle();
      await startRecording(tester);
      harness.backend.amplitudes.add(_sample(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(haloShadow(tester).blurRadius, greaterThan(28));

      harness.backend.amplitudes.addError(StateError('analyser detached'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(haloShadow(tester).blurRadius, 28);
    });

    testWidgets('Reduce Motion: the halo is fixed and the glyph swaps at '
        'once', (tester) async {
      _useSurface(tester, const Size(390, 844));
      final harness = build();
      await tester.pumpWidget(
        _host(harness.screen, disableAnimations: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump();
      // No transition frame: the stop glyph alone, the live bead fully in.
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      expect(liveOpacity(tester), 1);

      harness.backend.amplitudes.add(_sample(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final fixed = haloShadow(tester);
      final rm = voiceRecordHalo(0, reduceMotion: true).single;
      expect(fixed.color, rm.color);
      expect(fixed.blurRadius, rm.blurRadius);
      expect(fixed.spreadRadius, rm.spreadRadius);
    });

    testWidgets('high contrast: no halo while recording', (tester) async {
      _useSurface(tester, const Size(390, 844));
      final harness = build();
      await tester.pumpWidget(_host(harness.screen, highContrast: true));
      await tester.pumpAndSettle();
      await startRecording(tester);
      harness.backend.amplitudes.add(_sample(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      expect(halo, findsNothing);
    });

    testWidgets('a medium haptic when the take starts, a light one when it '
        'stops', (tester) async {
      _useSurface(tester, const Size(390, 844));
      final haptics = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
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
      await tester.pumpWidget(_host(build().screen));
      await tester.pumpAndSettle();
      await startRecording(tester);
      expect(haptics, <Object?>['HapticFeedbackType.mediumImpact']);

      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pump();
      await tester.pump();
      expect(haptics, <Object?>[
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.lightImpact',
      ]);
    });

    testWidgets('the panels wear the immersive block finish; high contrast '
        'restores a flat surface and borderStrong', (tester) async {
      _useSurface(tester, const Size(390, 844));
      await tester.pumpWidget(_host(build().screen));
      await tester.pumpAndSettle();

      BoxDecoration stage() =>
          tester
                  .widget<Container>(
                    find.byKey(const ValueKey('voice-moment-capture-stage')),
                  )
                  .decoration!
              as BoxDecoration;

      final lit = stage();
      expect(lit.gradient!.colors, <Color>[
        AppImmersiveColors.surfaceRaised.withValues(alpha: .92),
        AppImmersiveColors.surface.withValues(alpha: .92),
      ]);
      expect(
        (lit.border! as Border).top.color,
        AppColors.white.withValues(alpha: .10),
      );
      expect(lit.borderRadius, BorderRadius.circular(28));

      await tester.pumpWidget(_host(build().screen, highContrast: true));
      await tester.pumpAndSettle();
      final flat = stage();
      expect(flat.gradient, isNull);
      expect(flat.color, AppImmersiveColors.surface);
      expect((flat.border! as Border).top.color, AppPalette.dark.borderStrong);
    });

    testWidgets('the active flow step is a primary wash with the gradient '
        'number disc; the other is a white glaze', (tester) async {
      _useSurface(tester, const Size(390, 844));
      await tester.pumpWidget(_host(build().screen));
      await tester.pumpAndSettle();

      final boxes = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byKey(const ValueKey('voice-moment-flow-progress')),
              matching: find.byType(Container),
            ),
          )
          .map((container) => container.decoration! as BoxDecoration)
          .toList();
      // Step tile, its number disc; then the second step's pair.
      expect(boxes, hasLength(4));
      final (activeTile, activeDisc, restTile, restDisc) = (
        boxes[0],
        boxes[1],
        boxes[2],
        boxes[3],
      );
      expect(activeTile.color, AppColors.primary.withValues(alpha: .14));
      final activeEdge = (activeTile.border! as Border).top;
      expect(activeEdge.color, AppColors.primary.withValues(alpha: .55));
      expect(activeEdge.width, 1.5);
      expect(activeDisc.gradient, AppGradients.primary);
      expect(restTile.color, AppColors.white.withValues(alpha: .03));
      expect(
        (restTile.border! as Border).top.color,
        AppColors.white.withValues(alpha: .06),
      );
      expect(restDisc.color, AppImmersiveColors.background);
    });

    testWidgets('the review preview keeps its unplayed track on the raised '
        'panel; high contrast restores borderStrong', (tester) async {
      _useSurface(tester, const Size(390, 844));
      for (final highContrast in const <bool>[false, true]) {
        final clock = FakeStopwatch();
        await tester.pumpWidget(
          _host(
            RecordVoiceMomentScreen(
              key: UniqueKey(),
              recorder: VoiceMomentRecorder(
                backend: FakeRecorderBackend(),
                capture: FakeAudioCapture()..result = FakeRecordedAudio(),
                clock: clock,
              ),
              momentService: StubMomentService(),
              previewPlayerFactory: () =>
                  FakePreviewAudioPlayer(duration: const Duration(seconds: 5)),
            ),
            highContrast: highContrast,
          ),
        );
        await tester.pumpAndSettle();
        await startRecording(tester);
        clock.value = const Duration(seconds: 5);
        await tester.pump(const Duration(milliseconds: 200));
        final stop = find.byIcon(Icons.stop_rounded);
        await tester.ensureVisible(stop);
        await tester.pump();
        await tester.tap(stop);
        await tester.pump();
        await tester.pump();

        // The theme's primary thumb (2.98:1) and inactive track (1.97:1)
        // fell under 3:1 on the panel's raised finish: every part of the
        // slider must hold 3:1 on both panel stops (WCAG 1.4.11).
        final seek = tester.widget<Slider>(
          find.byKey(const ValueKey('voice-preview-seek')),
        );
        for (final (part, color) in <(String, Color?)>[
          ('thumb', seek.thumbColor),
          ('played', seek.activeColor),
          ('remaining', seek.inactiveColor),
        ]) {
          expect(color, isNotNull, reason: part);
          for (final stop in _panelStops) {
            expect(
              _contrast(color!, stop),
              greaterThanOrEqualTo(3),
              reason: '$part on ${stop.toARGB32().toRadixString(16)}'
                  '${highContrast ? ' (high contrast)' : ''}',
            );
          }
        }
      }
    });

    testWidgets('the review step: the preview is the R14 bead, "Opublikuj" '
        'the one R5 action and the selected availability the tonal '
        'selection of spec §13', (tester) async {
      _useSurface(tester, const Size(390, 844));
      final clock = FakeStopwatch();
      final player = FakePreviewAudioPlayer(
        duration: const Duration(seconds: 5),
      );
      await tester.pumpWidget(
        _host(
          RecordVoiceMomentScreen(
            recorder: VoiceMomentRecorder(
              backend: FakeRecorderBackend(),
              capture: FakeAudioCapture()..result = FakeRecordedAudio(),
              clock: clock,
            ),
            momentService: StubMomentService(),
            previewPlayerFactory: () => player,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await startRecording(tester);
      clock.value = const Duration(seconds: 5);
      await tester.pump(const Duration(milliseconds: 200));
      final stop = find.byIcon(Icons.stop_rounded);
      await tester.ensureVisible(stop);
      await tester.pump();
      await tester.tap(stop);
      await tester.pumpAndSettle();

      final toggle = find.byKey(const ValueKey('voice-preview-toggle'));
      YoGradientDisc bead() => tester.widget<YoGradientDisc>(
        find.descendant(of: toggle, matching: find.byType(YoGradientDisc)),
      );
      expect(tester.getSize(toggle), const Size(52, 52));
      expect(bead().size, 52);
      expect(bead().tone, YoDiscTone.brand);
      expect(bead().gloss, isTrue);
      expect(bead().emphasis, YoDiscEmphasis.rest);
      expect(bead().icon, Icons.play_arrow_rounded);
      // The stock flat-violet squircle is gone.
      expect(
        tester.widget<IconButton>(toggle).style?.backgroundColor?.resolve(
          const <WidgetState>{},
        ),
        Colors.transparent,
      );

      // Lit only while the take plays.
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(bead().emphasis, YoDiscEmphasis.lit);
      expect(bead().icon, Icons.pause_rounded);

      // "Opublikuj": the R5 gradient action with the screen's one lift.
      final publish = find.ancestor(
        of: find.text('Publish'),
        matching: find.byType(YoGradientFilledButton),
      );
      expect(publish, findsOneWidget);
      expect(
        tester.widget<YoGradientFilledButton>(publish).emphasis,
        YoActionEmphasis.lifted,
      );

      // The selected availability: the tonal selection of spec §13 (B6) —
      // a white @.12 fill, a 1.5 px interactive edge that holds 3:1 on the
      // panel, a white label and a check as the non-colour cue. Not the
      // chip-scale ink inversion (that slab outweighed "Opublikuj").
      final timed = find.byKey(const ValueKey('availability-timed'));
      final fill = tester
          .widget<Material>(
            find.descendant(of: timed, matching: find.byType(Material)).first,
          )
          .color;
      expect(fill, AppImmersiveColors.textPrimary.withValues(alpha: .12));
      final label = tester.widget<Text>(
        find.descendant(of: timed, matching: find.byType(Text)),
      );
      expect(label.style?.color, AppImmersiveColors.textPrimary);
      expect(
        find.descendant(
          of: timed,
          matching: find.byKey(const ValueKey('availability-selected-check')),
        ),
        findsOneWidget,
      );
      for (final stop in _panelStops) {
        expect(
          _contrast(AppPalette.dark.interactiveForeground, stop),
          greaterThanOrEqualTo(3),
        );
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('the immersive "+" and the create sheet', () {
    Future<void> pumpHeader(
      WidgetTester tester, {
      required bool onCanvas,
      required ThemeData theme,
      required VoidCallback onCreate,
    }) async {
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => buildImmersiveMomentsHeader(
                  context,
                  showBack: false,
                  selectedFormat: YoMomentsFormat.reels,
                  onFormatSelected: (_) {},
                  onCreate: onCreate,
                  onCanvas: onCanvas,
                ).trailing!,
              ),
            ),
          ),
          theme: theme,
        ),
      );
      await tester.pump();
    }

    for (final onCanvas in <bool>[true, false]) {
      testWidgets('${onCanvas ? 'on the canvas' : 'over media'} it is the '
          '48 px R6 disc with the brand lift', (tester) async {
        var creates = 0;
        await pumpHeader(
          tester,
          onCanvas: onCanvas,
          theme: AppTheme.lightTheme,
          onCreate: () => creates += 1,
        );
        final create = find.byKey(const ValueKey('moments-create-cta'));
        expect(tester.getSize(create), const Size(48, 48));
        final disc = find.descendant(
          of: create,
          matching: find.byType(YoGradientDisc),
        );
        final widget = tester.widget<YoGradientDisc>(disc);
        expect(widget.size, 48);
        expect(widget.tone, YoDiscTone.brand);
        expect(widget.emphasis, YoDiscEmphasis.lift);
        expect(widget.icon, Icons.add_rounded);
        expect(
          tester
              .widget<YoPressFeedback>(
                find.descendant(
                  of: create,
                  matching: find.byType(YoPressFeedback),
                  matchRoot: true,
                ),
              )
              .scale,
          YoPressFeedback.disc,
        );
        // Over footage the disc is immersive in both themes; on the Pearl
        // canvas it is Pearl's.
        expect(
          AppPalette.of(tester.element(disc)).background,
          onCanvas ? AppPalette.light.background : AppPalette.dark.background,
        );
        expect(find.bySemanticsLabel('CREATE'), findsOneWidget);
        await tester.tap(create);
        expect(creates, 1);
      });
    }

    testWidgets('the sheet tiles are R2 blocks with a 44 px icon circle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          MomentsScreen(
            isRootTab: true,
            initialFormat: YoMomentsFormat.reels,
            reelService: ReelService(
              auth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: 'viewer'),
              ),
              callableInvoker: (name, payload) async => <Object?, Object?>{
                'schemaVersion': 2,
                'items': const <Object?>[],
                'nextCursor': null,
              },
            ),
            onCreateReel: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('moments-create-cta')));
      await tester.pumpAndSettle();

      final primary = AppTheme.darkTheme.colorScheme.primary;
      for (final key in <String>[
        'create-voice-moment-choice',
        'create-reel-choice',
      ]) {
        final tile = find.byKey(ValueKey<String>(key));
        final card = tester.widget<YoCard>(
          find.descendant(of: tile, matching: find.byType(YoCard)),
        );
        expect(card.radius, AppRadius.block, reason: key);
        final circle = find
            .descendant(
              of: tile,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration! as BoxDecoration).shape ==
                        BoxShape.circle,
              ),
            )
            .first;
        expect(tester.getSize(circle), const Size(44, 44), reason: key);
        expect(
          (tester.widget<Container>(circle).decoration! as BoxDecoration)
              .color,
          primary.withValues(alpha: .14),
          reason: key,
        );
      }
      // One ink and one construction in both circles (the batch-6 review):
      // an outline frame with a filled play, in `interactiveForeground`.
      final ink = AppPalette.dark.interactiveForeground;
      final mark = tester.widget<YoMomentsIcon>(
        find.descendant(
          of: find.byKey(const ValueKey('create-voice-moment-choice')),
          matching: find.byType(YoMomentsIcon),
        ),
      );
      expect(mark.state, YoMomentsIconState.inactive);
      expect(mark.color, ink);
      final glyph = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('create-reel-choice')),
          matching: find.byType(Icon),
        ).first,
      );
      expect(glyph.icon, Icons.smart_display_outlined);
      expect(glyph.color, ink);
      expect(tester.takeException(), isNull);
    });
  });

  group('the Yeels header by stage (the batch-6 review)', () {
    ReelService emptyReels() => ReelService(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'v')),
      callableInvoker: (name, payload) async => <Object?, Object?>{
        'schemaVersion': 2,
        'items': const <Object?>[],
        'nextCursor': null,
      },
    );

    Future<void> pumpYeels(WidgetTester tester, Size size) async {
      _useSurface(tester, size);
      await tester.pumpWidget(
        _host(
          MomentsScreen(
            isRootTab: true,
            initialFormat: YoMomentsFormat.reels,
            reelService: emptyReels(),
            onCreateReel: () async {},
          ),
          theme: AppTheme.lightTheme,
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final (width, onCanvas) in const <(double, bool)>[
      (390, false),
      (768, true),
    ]) {
      testWidgets('at ${width.toInt()} px the chrome is '
          '${onCanvas ? 'on the page canvas' : 'over the stage'}', (
        tester,
      ) async {
        await pumpYeels(tester, Size(width, 1024));
        final chrome = tester.widget<ImmersiveFeedChrome>(
          find.byType(ImmersiveFeedChrome),
        );
        expect(chrome.onCanvas, onCanvas);
        final refresh = find.byKey(const ValueKey('reels-refresh'));
        expect(refresh, findsOneWidget);
        // The canvas refresh is Głos's 40 px hairline circle, never the
        // over-media plate on the paper.
        expect(
          find.descendant(of: refresh, matching: find.byType(OverlayPlate)),
          onCanvas ? findsNothing : findsOneWidget,
        );
        final disc = find.descendant(
          of: find.byKey(const ValueKey('moments-create-cta')),
          matching: find.byType(YoGradientDisc),
        );
        // The "+" takes the page's own (Pearl) palette on the canvas.
        expect(
          AppPalette.of(tester.element(disc)).background,
          onCanvas ? AppPalette.light.background : AppPalette.dark.background,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('from 1100 px the resting "+" keeps 8 px above the stage', (
      tester,
    ) async {
      await pumpYeels(tester, const Size(1440, 900));
      final create = tester.getRect(
        find.byKey(const ValueKey('moments-create-cta')),
      );
      final stage = tester.getRect(
        find.byKey(const ValueKey('yo-moments-retained-content')),
      );
      expect(stage.top - create.bottom, greaterThanOrEqualTo(8));
      expect(tester.takeException(), isNull);
    });
  });

  group('§8.4 Yeels plates', () {
    Future<BoxDecoration> plate(
      WidgetTester tester, {
      bool hovered = false,
      Color? ring,
      Color? fill,
      bool highContrast = false,
    }) async {
      await tester.pumpWidget(
        _host(
          Center(
            child: OverlayPlate(
              icon: Icons.favorite_rounded,
              color: Colors.white,
              hovered: hovered,
              ring: ring,
              fill: fill,
            ),
          ),
          highContrast: highContrast,
        ),
      );
      await tester.pumpAndSettle();
      return tester
              .widget<AnimatedContainer>(find.byType(AnimatedContainer))
              .decoration!
          as BoxDecoration;
    }

    testWidgets('an icon plate is black @ .55 with a white @ .14 hairline', (
      tester,
    ) async {
      final rest = await plate(tester);
      expect(rest.color, AppFinish.overlayControlPlate);
      expect(rest.color, const Color(0x8C000000));
      final edge = (rest.border! as Border).top;
      expect(edge.color, AppFinish.overlayControlPlateHairline);
      expect(edge.color, const Color(0x24FFFFFF));
      expect(edge.width, 1);
      expect(
        (await plate(tester, hovered: true)).color,
        AppFinish.overlayControlPlateHover,
      );
      expect(AppFinish.overlayControlPlateHover, const Color(0xB3000000));
    });

    test('the .55 icon plate and the .55 chip plate are one token, each '
        'holding its white ink at 4.5:1 over a pure-white frame', () {
      expect(AppFinish.overlayControlPlate, AppFinish.overlayChipColor);
      for (final plate in <Color>[
        AppFinish.overlayControlPlate,
        AppFinish.overlayChipColor,
        overlayPlateColor,
      ]) {
        final onWhite = Color.alphaBlend(plate, AppColors.white);
        expect(
          _contrast(AppColors.white, onWhite),
          greaterThanOrEqualTo(4.5),
          reason: plate.toARGB32().toRadixString(16),
        );
      }
    });

    testWidgets('a ring replaces the hairline; a canvas fill has none', (
      tester,
    ) async {
      final ringed = await plate(tester, ring: Colors.white);
      expect((ringed.border! as Border).top.color, Colors.white);
      expect((ringed.border! as Border).top.width, 2);
      final canvas = await plate(tester, fill: Colors.transparent);
      expect(canvas.border, isNull);
    });

    testWidgets('high contrast keeps the deeper word plate, no hairline', (
      tester,
    ) async {
      final hc = await plate(tester, highContrast: true);
      expect(hc.color, overlayPlateColor);
      expect(hc.border, isNull);
    });

    test('the word plate keeps its value', () {
      expect(overlayPlateColor, const Color(0xB8000000));
      expect(overlayPlateHoverColor, const Color(0xD6000000));
    });
  });

  group('§8.4 Yeel progress (amended by the batch-6 review)', () {
    Future<void> pumpBar(
      WidgetTester tester, {
      required bool pearl,
      bool highContrast = false,
    }) async {
      final position = ValueNotifier<Duration>(const Duration(seconds: 9));
      addTearDown(position.dispose);
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: SizedBox(
              width: 400,
              child: ReelProgressBar(
                position: position,
                total: const Duration(seconds: 18),
              ),
            ),
          ),
          theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
          highContrast: highContrast,
        ),
      );
    }

    for (final pearl in <bool>[false, true]) {
      testWidgets('the played run is white over the footage with the brand '
          'tip at the playhead (${pearl ? 'Pearl' : 'Dark'})', (tester) async {
        await pumpBar(tester, pearl: pearl);
        final run = find.byKey(ReelProgressBar.playedKey);
        final played = tester.widget<DecoratedBox>(run);
        expect((played.decoration as BoxDecoration).color, AppColors.white);
        expect((played.decoration as BoxDecoration).gradient, isNull);
        expect(tester.getSize(run), const Size(200, 2));

        final cap = find.byKey(ReelProgressBar.playedCapKey);
        expect(tester.getSize(cap), const Size(ReelProgressBar.capLength, 2));
        // The tip closes the run, at the playhead.
        expect(tester.getRect(cap).right, tester.getRect(run).right);
        final tip = tester.widget<DecoratedBox>(
          find.descendant(of: cap, matching: find.byType(DecoratedBox)),
        );
        expect(
          (tip.decoration as BoxDecoration).color,
          ReelProgressBar.sweepAt(.5),
        );
      });
    }

    testWidgets('high contrast: one solid white run, no brand tip', (
      tester,
    ) async {
      await pumpBar(tester, pearl: true, highContrast: true);
      final played = tester.widget<DecoratedBox>(
        find.byKey(ReelProgressBar.playedKey),
      );
      expect((played.decoration as BoxDecoration).color, AppColors.white);
      expect(find.byKey(ReelProgressBar.playedCapKey), findsNothing);
    });

    test('played and unplayed differ by 3:1 or more, not by hue alone', () {
      // The phone stage's bottom scrim stop (black @ .72) over the two
      // extreme frames, under the unplayed white @ .32 track.
      for (final footage in <Color>[AppColors.white, AppColors.black]) {
        final scrim = Color.alphaBlend(const Color(0xB8000000), footage);
        final unplayed = Color.alphaBlend(
          AppColors.white.withValues(alpha: .32),
          scrim,
        );
        final ink = ReelProgressBar.playedInk(
          AppPalette.dark,
          onMedia: true,
        );
        expect(ink, ReelProgressBar.playedInk(AppPalette.light, onMedia: true));
        expect(_contrast(ink, unplayed), greaterThanOrEqualTo(3));
        // The raw logo pair failed exactly this (1.05-1.40:1 measured).
        expect(
          _contrast(ReelProgressBar.sweepAt(0), unplayed),
          lessThan(3),
          reason: 'the brand tip is decoration; the white run carries it',
        );
      }
    });

    test('the brand tip runs from the logo violet to its magenta', () {
      expect(ReelProgressBar.sweepAt(0), AppColors.primary);
      expect(ReelProgressBar.sweepAt(1), AppColors.secondary);
      expect(ReelProgressBar.sweepAt(2), AppColors.secondary);
    });
  });
}
