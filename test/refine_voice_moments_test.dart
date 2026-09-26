// Refine-look batch 5 — the voice bead and Głos (spec §3 R12 / R13 / R14,
// §5 W3, §8.4). What these tests pin:
//
// * W3: in the feed exactly one card glows — the one whose clip is playing —
//   pausing drops it to rest, playing another card moves the light, and the
//   playhead never rebuilds a card body.
// * The detail player card lights only while its recording sounds; the reply
//   is the page's one gradient CTA.
// * The R12 expiry pill: neutral until the last hour, a ring only where the
//   window is known, words that wrap at 200 %.
// * The R8 chips, the 40 px hairline refresh, the R6 / R5 create actions,
//   the R17 empty / error discs.
// * The shared primitives this batch adds: YoVoiceBlock (lit / high
//   contrast), YoGradientDiscButton (hover and keyboard focus reach the
//   disc), VoiceCore's tokens.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_pill.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_transport_controls.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/features/moments/presentation/widgets/yo_moments_chrome.dart';
import 'package:yovoice/shared/widgets/badges/yo_progress_ring.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc_button.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_feed_chrome.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart'
    show overlayTextShadows;
import 'package:yovoice/shared/widgets/voice/voice_core.dart';
import 'package:yovoice/shared/widgets/voice/yo_voice_finish.dart';
import 'package:yovoice/shared/widgets/waveform/yo_waveform.dart';

import 'moment_listen_test_support.dart';
import 'moments_overview_test_support.dart';
import 'voice_moment_test_doubles.dart';

Widget _themed(Widget child, {bool pearl = false, MediaQueryData? media}) =>
    MaterialApp(
      theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: media ?? MediaQuery.of(context),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

void main() {
  group('W3 — exactly one lit clip in the feed', () {
    late VoidCallback restoreIdentity;

    setUpAll(loadInterFont);
    setUp(() => restoreIdentity = installIdentityStub());
    tearDown(() => restoreIdentity());

    Future<List<FakePreviewAudioPlayer>> pumpFeed(WidgetTester tester) async {
      useSurface(tester, const Size(768, 2400));
      final auth = authAs();
      final players = <FakePreviewAudioPlayer>[];
      await tester.pumpWidget(
        overviewHost(
          Scaffold(
            body: MomentsFeedView(
              auth: auth,
              onRecord: () {},
              discoveryService: StaticDiscovery(populatedPool()),
              feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
              viewsService: StaticViews(const <String>{}),
              momentService: StubMomentService(),
              playerFactory: () {
                final player = FakePreviewAudioPlayer(
                  duration: const Duration(seconds: 45),
                );
                players.add(player);
                return player;
              },
            ),
          ),
          size: const Size(768, 2400),
        ),
      );
      await settleOverview(tester);
      return players;
    }

    bool lit(WidgetTester tester, String id) => tester
        .widget<YoVoiceBlock>(find.byKey(ValueKey('moment-row-block-$id')))
        .lit;

    int litCount(WidgetTester tester) => tester
        .widgetList<YoVoiceBlock>(find.byType(YoVoiceBlock))
        .where((block) => block.lit)
        .length;

    YoGradientDisc bead(WidgetTester tester, String id) =>
        tester.widget<YoGradientDisc>(
          find.descendant(
            of: find.byKey(ValueKey('moment-row-play-$id')),
            matching: find.byType(YoGradientDisc),
          ),
        );

    Future<void> tapPlay(WidgetTester tester, String id) async {
      final play = find.byKey(ValueKey('moment-row-play-$id'));
      await tester.ensureVisible(play);
      await tester.tap(play);
      await settleOverview(tester);
    }

    testWidgets('playing card 2 lights only card 2, pausing drops it to rest, '
        'playing card 3 moves the light', (tester) async {
      await pumpFeed(tester);
      expect(litCount(tester), 0, reason: 'nothing plays, nothing glows');
      expect(bead(tester, 'm2').emphasis, YoDiscEmphasis.rest);
      expect(bead(tester, 'm2').resolvedGlyphSize, 24, reason: 'half the bead');

      await tapPlay(tester, 'm2');
      expect(lit(tester, 'm2'), isTrue);
      expect(litCount(tester), 1);
      expect(bead(tester, 'm2').emphasis, YoDiscEmphasis.lit);
      expect(bead(tester, 'm1').emphasis, YoDiscEmphasis.rest);

      await tapPlay(tester, 'm2');
      expect(lit(tester, 'm2'), isFalse, reason: 'paused = at rest');
      expect(litCount(tester), 0);
      expect(bead(tester, 'm2').emphasis, YoDiscEmphasis.rest);

      await tapPlay(tester, 'm3');
      expect(lit(tester, 'm3'), isTrue);
      expect(lit(tester, 'm2'), isFalse);
      expect(litCount(tester), 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('the lit card wears the violet edge and the corner light; the '
        'rest keep the hairline', (tester) async {
      await pumpFeed(tester);
      await tapPlay(tester, 'm1');
      final palette = AppPalette.of(
        tester.element(find.byKey(const ValueKey('moment-row-block-m1'))),
      );
      Border edgeOf(String id) =>
          (tester
                          .widgetList<AnimatedContainer>(
                            find.descendant(
                              of: find.byKey(ValueKey('moment-row-block-$id')),
                              matching: find.byType(AnimatedContainer),
                            ),
                          )
                          .last
                          .decoration
                      as BoxDecoration)
                  .border!
              as Border;
      expect(
        edgeOf('m1'),
        Border.all(color: AppColors.primary.withValues(alpha: .45)),
      );
      expect(edgeOf('m2'), Border.all(color: palette.hairline));
      // The corner light is the block's first AnimatedOpacity.
      double tintOf(String id) => tester
          .widget<AnimatedOpacity>(
            find
                .descendant(
                  of: find.byKey(ValueKey('moment-row-block-$id')),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          )
          .opacity;
      expect(tintOf('m1'), 1);
      expect(tintOf('m2'), 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('position ticks pour the waveform and never rebuild the card '
        'body', (tester) async {
      final players = await pumpFeed(tester);
      await tapPlay(tester, 'm1');
      final title = find.descendant(
        of: find.byKey(const ValueKey('moment-row-title-m1')),
        matching: find.byType(Text),
      );
      final actions = find.byKey(const ValueKey('moment-row-like-m1'));
      final titleBefore = tester.widget<Text>(title);
      final likeBefore = tester.widget(actions);

      players.single.emitPosition(const Duration(seconds: 9));
      await tester.pump();
      players.single.emitPosition(const Duration(milliseconds: 9200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(identical(tester.widget<Text>(title), titleBefore), isTrue);
      expect(identical(tester.widget(actions), likeBefore), isTrue);
      final wave = tester.widget<YoWaveform>(
        find.byKey(const ValueKey('moment-row-waveform-m1')),
      );
      expect(wave.progress, closeTo(9.2 / 45, 1e-6));
      expect(find.text('0:09 / 0:45'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    });
  });

  group('the detail player card', () {
    testWidgets('lights only while the recording sounds; the reply is the '
        'one gradient CTA', (tester) async {
      final harness = await pumpListenDetail(
        tester,
        moment: listenMoment('m1'),
        size: const Size(900, 900),
      );
      bool cardLit() => tester
          .widget<YoVoiceBlock>(
            find.byKey(const ValueKey('moment-detail-player-card')),
          )
          .lit;
      expect(cardLit(), isFalse);

      await playTo(tester, harness, const Duration(seconds: 9));
      expect(cardLit(), isTrue);
      final disc = tester.widget<YoGradientDisc>(
        find.descendant(
          of: find.byKey(const ValueKey('moment-detail-play')),
          matching: find.byType(YoGradientDisc),
        ),
      );
      expect(disc.emphasis, YoDiscEmphasis.lit);
      expect(disc.size, 72);
      // B5 review (V4): the glyph is half the bead, as every bead site drew
      // it before this batch (R14's .42 left the Material glyph timid).
      expect(disc.resolvedGlyphSize, 36);

      await tester.tap(find.byKey(const ValueKey('moment-detail-play')));
      await tester.pump();
      await tester.pump();
      expect(cardLit(), isFalse, reason: 'paused = at rest');

      final reply = find.byKey(const ValueKey('moment-detail-reply-voice'));
      expect(tester.widget(reply), isA<FilledButton>());
      expect(
        find.ancestor(of: reply, matching: find.byType(YoGradientFilledButton)),
        findsOneWidget,
      );
      final wave = tester.widget<YoWaveform>(
        find.byKey(const ValueKey('moment-detail-waveform')),
      );
      expect(wave.continuousProgress, isTrue);
      expect(wave.barWidth, 4);
      expect(wave.barGap, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the gradient reply keeps the FilledButton.icon geometry '
        'it had (16 before the glyph, 24 after the label)', (tester) async {
      // Refine-look capture 2026-09-26 (Inter, 1440): 24 px on both sides
      // pushed the CTA past its 200 px floor and wrapped "Zgłoś" under the
      // chips on the 640 px card. The row itself is proven by the frames;
      // this pins the padding that keeps it on one line.
      await pumpListenDetail(
        tester,
        moment: listenMoment('m1'),
        size: const Size(1440, 900),
      );
      final cta = tester.widget<YoGradientFilledButton>(
        find.ancestor(
          of: find.byKey(const ValueKey('moment-detail-reply-voice')),
          matching: find.byType(YoGradientFilledButton),
        ),
      );
      expect(cta.padding, const EdgeInsetsDirectional.fromSTEB(16, 0, 24, 0));
      expect(tester.takeException(), isNull);
    });

    // B5 review (A11Y-B5-08), deliberate: the step still never scales on
    // its own (it spilled over the arrow at 200 %), but the WHOLE glyph —
    // arrow and step together — now follows the text size up to 1.5×.
    testWidgets('the ⟲15 / ⟳15 glyph scales as one piece, clamped at 1.5×, '
        'at 200 % text', (tester) async {
      await tester.pumpWidget(
        _themed(
          SizedBox(
            width: 390,
            child: MomentTransportControls(
              position: const Duration(seconds: 18),
              total: const Duration(seconds: 45),
              isPlaying: true,
              busy: false,
              canSeek: true,
              compact: true,
              onTogglePlay: () {},
              onSeek: (_) {},
            ),
          ),
          media: const MediaQueryData(textScaler: TextScaler.linear(2)),
        ),
      );
      final steps = find.text('15');
      expect(steps, findsNWidgets(2));
      for (final element in steps.evaluate()) {
        final text = element.widget as Text;
        expect(text.textScaler, TextScaler.noScaling);
        expect(text.style!.fontSize, 9 * 1.5);
        final step = tester.getRect(find.byWidget(text));
        expect(step.height, greaterThan(9));
        final arrow = tester.getRect(
          find
              .ancestor(of: find.byWidget(text), matching: find.byType(Stack))
              .first,
        );
        expect(arrow.size, const Size.square(32 * 1.5));
        // The step sits inside the arrow's open centre, never over it.
        expect(step.width, lessThan(arrow.width * .5));
        expect(step.height, lessThan(arrow.height * .5));
        expect((step.center - arrow.center).distance, lessThan(1));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('at the ordinary text size the skip glyph is unchanged '
        '(32 px arrow, 9 px step)', (tester) async {
      await tester.pumpWidget(
        _themed(
          SizedBox(
            width: 390,
            child: MomentTransportControls(
              position: const Duration(seconds: 18),
              total: const Duration(seconds: 45),
              isPlaying: true,
              busy: false,
              canSeek: true,
              compact: true,
              onTogglePlay: () {},
              onSeek: (_) {},
            ),
          ),
        ),
      );
      for (final element in find.text('15').evaluate()) {
        final text = element.widget as Text;
        expect(text.style!.fontSize, 9);
        expect(
          tester.getSize(
            find
                .ancestor(of: find.byWidget(text), matching: find.byType(Stack))
                .first,
          ),
          const Size.square(32),
        );
      }
    });

    for (final pearl in <bool>[false, true]) {
      testWidgets('the slider is the waveform\'s own played sweep, not a '
          'second colour system (${pearl ? 'Pearl' : 'Dark'})', (tester) async {
        await tester.pumpWidget(
          _themed(
            SizedBox(
              width: 390,
              child: MomentTransportControls(
                position: const Duration(seconds: 18),
                total: const Duration(seconds: 45),
                isPlaying: true,
                busy: false,
                canSeek: true,
                compact: true,
                onTogglePlay: () {},
                onSeek: (_) {},
              ),
            ),
            pearl: pearl,
          ),
        );
        final palette = pearl ? AppPalette.light : AppPalette.dark;
        final scheme =
            (pearl ? AppTheme.lightTheme : AppTheme.darkTheme).colorScheme;
        final sweep = AppGradients.voicePlayed(scheme, palette);
        final theme = SliderTheme.of(
          tester.element(find.byKey(const ValueKey('moment-detail-position'))),
        );
        expect(theme.trackShape, isA<PlayedSweepTrackShape>());
        expect((theme.trackShape! as PlayedSweepTrackShape).sweep, sweep);
        expect(theme.inactiveTrackColor, palette.waveUnplayed);
        final playhead = Color.lerp(
          sweep.colors.first,
          sweep.colors.last,
          18 / 45,
        );
        expect(theme.thumbColor, playhead);
        expect(theme.activeTrackColor, playhead);
        // No cyan on the slider any more: that accent is the listening
        // ring's alone.
        expect(theme.thumbColor, isNot(palette.audioAccent));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the R12 expiry pill', () {
    final now = DateTime(2026, 9, 26, 12);

    testWidgets('neutral with a real-window ring until the last hour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _themed(
          MomentExpiryPill(
            label: 'Wygasa za 18 godz.',
            expiresAt: now.add(const Duration(hours: 18)),
            createdAt: now.subtract(const Duration(hours: 6)),
            now: now,
            labelKey: const ValueKey('label'),
          ),
        ),
      );
      final palette = AppPalette.dark;
      final ring = tester.widget<YoProgressRing>(find.byType(YoProgressRing));
      expect(ring.value, closeTo(18 / 24, 1e-9));
      expect(ring.size, 14);
      // B5 review (V3 / A11Y-B5-09), a deliberate R12 amendment: the arc is
      // the words' neutral ink and the track the always-visible
      // `waveUnplayed` (it was `interactiveForeground` on `border`, a track
      // that measured 1.09:1 on the Dark glass).
      expect(ring.arcColor, palette.textSecondary);
      expect(ring.trackColor, palette.waveUnplayed);
      expect(ring.trackColor, MomentExpiryPill.trackColor(palette));
      final label = tester.widget<Text>(find.byKey(const ValueKey('label')));
      expect(label.style!.color, palette.textSecondary);
      final pill =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(MomentExpiryPill),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(pill.color, palette.glass);
      expect(pill.border, Border.all(color: palette.hairline));
      expect(pill.borderRadius, AppRadius.pill);
    });

    testWidgets('amber only in the last hour', (tester) async {
      await tester.pumpWidget(
        _themed(
          MomentExpiryPill(
            label: 'Wygasa za 42 min',
            expiresAt: now.add(const Duration(minutes: 42)),
            createdAt: now.subtract(const Duration(hours: 23)),
            now: now,
            labelKey: const ValueKey('label'),
          ),
          pearl: true,
        ),
      );
      final palette = AppPalette.light;
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('label'))).style!.color,
        palette.warningForeground,
      );
      expect(
        tester.widget<YoProgressRing>(find.byType(YoProgressRing)).arcColor,
        palette.warningForeground,
      );
      expect(
        MomentExpiryPill.isUrgent(
          now.add(const Duration(minutes: 61)),
          now: now,
        ),
        isFalse,
      );
    });

    testWidgets('no ring is invented for a permanent Moment or an unknown '
        'window', (tester) async {
      for (final (expiresAt, createdAt) in <(DateTime?, DateTime?)>[
        (null, now),
        (now.add(const Duration(hours: 3)), null),
      ]) {
        await tester.pumpWidget(
          _themed(
            MomentExpiryPill(
              label: 'Dostępny do usunięcia',
              expiresAt: expiresAt,
              createdAt: createdAt,
              now: now,
            ),
          ),
        );
        expect(find.byType(YoProgressRing), findsNothing);
        expect(find.text('Dostępny do usunięcia'), findsOneWidget);
      }
    });

    testWidgets(
      'at 200 % the words wrap and the ring stays on the first line',
      (tester) async {
        await tester.pumpWidget(
          _themed(
            SizedBox(
              width: 180,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: MomentExpiryPill(
                  label: 'Wygasa za 23 godz.',
                  expiresAt: now.add(const Duration(hours: 23)),
                  createdAt: now.subtract(const Duration(hours: 1)),
                  now: now,
                  labelKey: const ValueKey('label'),
                ),
              ),
            ),
            media: const MediaQueryData(textScaler: TextScaler.linear(2)),
          ),
        );
        final label = tester.getRect(find.byKey(const ValueKey('label')));
        final ring = tester.getRect(find.byType(YoProgressRing));
        final lineHeight = 12 * 2 * 1.35;
        expect(label.height, greaterThan(lineHeight * 1.5), reason: 'wrapped');
        expect(ring.center.dy, closeTo(label.top + lineHeight / 2, 1));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('once the words wrap, the pill hugs its longest line', (
      tester,
    ) async {
      const width = 180.0;
      await tester.pumpWidget(
        _themed(
          SizedBox(
            width: width,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: MomentExpiryPill(
                label: 'Wygasa za 23 godz.',
                expiresAt: now.add(const Duration(hours: 23)),
                createdAt: now.subtract(const Duration(hours: 1)),
                now: now,
                labelKey: const ValueKey('label'),
              ),
            ),
          ),
          media: const MediaQueryData(textScaler: TextScaler.linear(2)),
        ),
      );
      final label = tester.getRect(find.byKey(const ValueKey('label')));
      // The pill's padding (8 + 11), the ring (14) and its gap (6).
      const room = width - 8 - 14 - 6 - 11;
      expect(label.height, greaterThan(12 * 2 * 1.35 * 1.5), reason: 'wrapped');
      expect(
        label.width,
        lessThan(room - 1),
        reason: 'a wrapped label must not stretch the pill to the column',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('R8 chips', () {
    // In a min-height column, as the chrome hosts it: the row is as tall as
    // its 48 px targets.
    Widget row({required bool onCanvas, bool pearl = false}) => _themed(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ImmersiveFilterRow(
            onCanvas: onCanvas,
            selectedIndex: 0,
            onSelected: (_) {},
            options: const <ImmersiveChromeOption>[
              ImmersiveChromeOption(key: ValueKey('chip-0'), label: 'Odkrywaj'),
              ImmersiveChromeOption(
                key: ValueKey('chip-1'),
                label: 'Obserwowani',
              ),
            ],
          ),
        ],
      ),
      pearl: pearl,
    );

    BoxDecoration inkOf(WidgetTester tester, String key) =>
        tester
                .widget<AnimatedContainer>(
                  find.descendant(
                    of: find.byKey(ValueKey(key)),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration
            as BoxDecoration;

    for (final pearl in <bool>[false, true]) {
      testWidgets('canvas: ink inversion over hairline chips '
          '(${pearl ? 'Pearl' : 'Dark'})', (tester) async {
        await tester.pumpWidget(row(onCanvas: true, pearl: pearl));
        final palette = pearl ? AppPalette.light : AppPalette.dark;
        final selected = inkOf(tester, 'chip-0');
        expect(selected.color, palette.textPrimary);
        expect(selected.border, isNull);
        final idle = inkOf(tester, 'chip-1');
        expect(idle.color, Colors.transparent);
        expect(idle.border, Border.all(color: palette.hairlineControl));
        final on = tester.widget<Text>(find.text('Odkrywaj')).style!;
        expect(on.color, palette.background);
        expect(on.fontWeight, FontWeight.w700);
        final off = tester.widget<Text>(find.text('Obserwowani')).style!;
        expect(off.color, palette.textSecondary);
        expect(off.fontWeight, FontWeight.w600);
        expect(tester.getSize(find.byKey(const ValueKey('chip-1'))).height, 48);
        final ink = find.descendant(
          of: find.byKey(const ValueKey('chip-1')),
          matching: find.byType(AnimatedContainer),
        );
        expect(tester.getSize(ink).height, AppFinish.chipHeight);
      });
    }

    testWidgets('over media: a white chip over translucent black plates', (
      tester,
    ) async {
      await tester.pumpWidget(row(onCanvas: false));
      expect(inkOf(tester, 'chip-0').color, AppColors.white);
      expect(inkOf(tester, 'chip-1').color, AppFinish.overlayChipColor);
      final on = tester.widget<Text>(find.text('Odkrywaj')).style!;
      expect(on.color, AppFinish.chipOverMediaLabel(selected: true));
      expect(on.shadows, isNull);
      final off = tester.widget<Text>(find.text('Obserwowani')).style!;
      expect(off.color, AppColors.white);
      expect(off.fontWeight, FontWeight.w600);
      // B5 review (V6), deliberate: the plate (black @ .55) carries the
      // white label's contrast, so the label keeps only the soft overlay
      // shadow — the hard 8-way stroke stacked on the plate is gone.
      expect(off.shadows, overlayTextShadows);
      expect(
        off.shadows!.every((shadow) => shadow.blurRadius > 0),
        isTrue,
        reason: 'no hard stroke on a plated label',
      );
    });
  });

  group('Głos chrome', () {
    late VoidCallback restoreIdentity;

    setUpAll(loadInterFont);
    setUp(() => restoreIdentity = installIdentityStub());
    tearDown(() => restoreIdentity());

    Future<void> pumpFeed(
      WidgetTester tester, {
      required Size size,
      StaticDiscovery? discovery,
      bool throwing = false,
    }) async {
      useSurface(tester, size);
      final auth = authAs();
      await tester.pumpWidget(
        overviewHost(
          Scaffold(
            body: MomentsFeedView(
              auth: auth,
              onRecord: () {},
              onCreate: () {},
              discoveryService: throwing
                  ? ThrowingDiscovery()
                  : discovery ?? StaticDiscovery(populatedPool()),
              feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
              viewsService: StaticViews(const <String>{}),
              playerFactory: SilentPlayer.new,
            ),
          ),
          size: size,
        ),
      );
      await settleOverview(tester);
    }

    testWidgets('refresh is a 40 px hairline circle in a 48 px target', (
      tester,
    ) async {
      await pumpFeed(tester, size: const Size(390, 844));
      final refresh = find.byKey(const ValueKey('moments-discovery-refresh'));
      expect(tester.getSize(refresh), const Size(48, 48));
      final material = tester.widget<Material>(
        find.descendant(of: refresh, matching: find.byType(Material)).first,
      );
      expect(
        tester.getSize(
          find.descendant(of: refresh, matching: find.byType(Material)).first,
        ),
        const Size(40, 40),
      );
      final palette = AppPalette.dark;
      expect(
        (material.shape! as CircleBorder).side.color,
        palette.hairlineControl,
      );
      expect(tester.widget(refresh), isA<IconButton>());
    });

    testWidgets('desktop "Utwórz" is the lifted gradient action; the panel\'s '
        'selected row is a quiet primary wash with an edge', (tester) async {
      await pumpFeed(tester, size: const Size(1300, 900));
      final create = find.byKey(const ValueKey('moments-create-cta'));
      expect(tester.widget(create), isA<FilledButton>());
      final action = tester.widget<YoGradientFilledButton>(
        find.ancestor(
          of: create,
          matching: find.byType(YoGradientFilledButton),
        ),
      );
      expect(action.emphasis, YoActionEmphasis.lifted);
      expect(tester.getSize(create).height, 48);
      final selected = tester.widget<Material>(
        find
            .descendant(
              of: find.byKey(const ValueKey('moments-filter-discover')),
              matching: find.byType(Material),
            )
            .first,
      );
      final primary = AppTheme.darkTheme.colorScheme.primary;
      expect(selected.color, primary.withValues(alpha: .12));
      expect(
        (selected.shape! as RoundedRectangleBorder).side.color,
        primary.withValues(alpha: .30),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the header "+" is the 48 px R6 disc with the brand lift', (
      tester,
    ) async {
      await tester.pumpWidget(
        _themed(YoMomentsCreateButton(onTap: () {}, compact: true)),
      );
      final create = find.byKey(const ValueKey<String>('moments-create-cta'));
      expect(tester.widget(create), isA<IconButton>());
      expect(tester.getSize(create), const Size(48, 48));
      final disc = tester.widget<YoGradientDisc>(
        find.descendant(of: create, matching: find.byType(YoGradientDisc)),
      );
      expect(disc.size, 48);
      expect(disc.emphasis, YoDiscEmphasis.lift);
      expect(disc.tone, YoDiscTone.brand);
    });

    testWidgets('the empty feed shows the Moments disc and a flat gradient '
        'record action; the error card keeps a solid retry', (tester) async {
      await pumpFeed(
        tester,
        size: const Size(390, 844),
        discovery: StaticDiscovery(const []),
      );
      expect(find.byKey(const ValueKey('moments-state-disc')), findsOneWidget);
      final record = tester.widget<YoGradientFilledButton>(
        find.byType(YoGradientFilledButton),
      );
      expect(record.emphasis, YoActionEmphasis.flat);
      expect(
        tester.getSize(find.byKey(const ValueKey('moments-state-disc'))),
        const Size(64, 64),
      );

      await tester.pumpWidget(const SizedBox());
      await pumpFeed(tester, size: const Size(390, 844), throwing: true);
      expect(
        find.byKey(const ValueKey('moments-discovery-error')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('moments-state-disc')), findsOneWidget);
      expect(find.byType(YoGradientFilledButton), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('shared voice primitives', () {
    testWidgets('YoVoiceBlock: lit edge and corner light, and under high '
        'contrast a flat block with a 1.5 px ink edge and no light', (
      tester,
    ) async {
      Future<BoxDecoration> edge({
        required bool lit,
        bool highContrast = false,
        bool pearl = false,
      }) async {
        await tester.pumpWidget(
          _themed(
            MediaQuery(
              data: MediaQueryData(highContrast: highContrast),
              child: YoVoiceBlock(
                lit: lit,
                child: const SizedBox(width: 200, height: 100),
              ),
            ),
            pearl: pearl,
          ),
        );
        // A theme switch between two pumps animates; let it land.
        await tester.pumpAndSettle();
        return tester
                .widgetList<AnimatedContainer>(
                  find.descendant(
                    of: find.byType(YoVoiceBlock),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .last
                .decoration
            as BoxDecoration;
      }

      expect(
        (await edge(lit: true)).border,
        Border.all(color: AppColors.primary.withValues(alpha: .45)),
      );
      expect(
        (await edge(lit: true, pearl: true)).border,
        Border.all(color: AppColors.primary.withValues(alpha: .35)),
      );
      Finder tint() => find.descendant(
        of: find.byType(YoVoiceBlock),
        matching: find.byType(AnimatedOpacity),
      );
      expect(tint(), findsOneWidget);

      final hc = await edge(lit: true, highContrast: true);
      // B5 review (A11Y-B5-03), a deliberate W3 amendment: the lit edge
      // under high contrast is `textPrimary`, no longer the violet
      // `interactiveForeground` that equals `focus` in both themes.
      expect(
        hc.border,
        Border.all(color: AppPalette.dark.textPrimary, width: 1.5),
      );
      expect(tint(), findsNothing, reason: 'no tint');
      final fill =
          tester
                  .widgetList<AnimatedContainer>(
                    find.descendant(
                      of: find.byType(YoVoiceBlock),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .first
                  .decoration
              as BoxDecoration;
      expect(fill.gradient, isNull);
      expect(fill.color, AppPalette.dark.surface);
    });

    testWidgets('YoGradientDiscButton hands the control\'s real hover and '
        'keyboard focus to the disc', (tester) async {
      await tester.pumpWidget(
        _themed(
          YoGradientDiscButton(
            disc: (hovered, focused) => YoGradientDisc(
              size: 48,
              icon: Icons.play_arrow_rounded,
              hovered: hovered,
              focused: focused,
            ),
            builder: (context, states, disc) => IconButton(
              key: const ValueKey('play'),
              statesController: states,
              onPressed: () {},
              icon: disc,
            ),
          ),
        ),
      );
      YoGradientDisc disc() =>
          tester.widget<YoGradientDisc>(find.byType(YoGradientDisc));
      expect(disc().hovered, isFalse);
      expect(disc().focused, isFalse);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('play'))));
      await tester.pump();
      await tester.pump();
      expect(disc().hovered, isTrue);
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      await tester.pump();
      expect(disc().hovered, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(disc().focused, isTrue);
    });

    testWidgets('VoiceCore paints the logo\'s gradient, no private violets', (
      tester,
    ) async {
      await tester.pumpWidget(_themed(const VoiceCore(size: 80)));
      final discs = tester
          .widgetList<Container>(find.byType(Container))
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => decoration.gradient != null)
          .toList();
      expect(discs.single.gradient, AppGradients.primary);
      expect(
        discs.single.boxShadow!.single.color.withValues(alpha: 1),
        AppColors.secondary,
      );
    });
  });

  // The refine-look B5 review round (2026-09-26): V1-V8 and A11Y-B5-01..09.
  group('B5 review round', () {
    late VoidCallback restoreIdentity;

    setUpAll(loadInterFont);
    setUp(() => restoreIdentity = installIdentityStub());
    tearDown(() => restoreIdentity());

    const longPools = <ImmersiveChromeOption>[
      ImmersiveChromeOption(key: ValueKey('pool-0'), label: 'Odkrywaj'),
      ImmersiveChromeOption(key: ValueKey('pool-1'), label: 'Obserwowani'),
      ImmersiveChromeOption(
        key: ValueKey('pool-2'),
        label: 'Najbardziej angażujące',
      ),
      ImmersiveChromeOption(key: ValueKey('pool-3'), label: 'Twoje Momenty'),
    ];

    Widget strip({
      double width = 240,
      TextDirection direction = TextDirection.ltr,
      List<ImmersiveChromeOption> options = longPools,
    }) => _themed(
      Directionality(
        textDirection: direction,
        child: SizedBox(
          width: width,
          child: ImmersiveFilterRow(
            onCanvas: true,
            selectedIndex: 0,
            onSelected: (_) {},
            options: options,
          ),
        ),
      ),
    );

    ImmersiveFilterRowState stripState(WidgetTester tester) =>
        tester.state<ImmersiveFilterRowState>(find.byType(ImmersiveFilterRow));

    testWidgets('V1: the strip dissolves the edge that still has chips '
        'beyond it, and neither edge at the scroll ends', (tester) async {
      await tester.pumpWidget(strip());
      await tester.pump();
      expect(stripState(tester).fadesStart, isFalse);
      expect(stripState(tester).fadesEnd, isTrue);
      expect(
        find.descendant(
          of: find.byType(ImmersiveFilterRow),
          matching: find.byType(ShaderMask),
        ),
        findsOneWidget,
      );

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-3000, 0),
      );
      await tester.pumpAndSettle();
      expect(stripState(tester).fadesStart, isTrue);
      expect(stripState(tester).fadesEnd, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('V1: mirrored in RTL — the end edge is the left one', (
      tester,
    ) async {
      await tester.pumpWidget(strip(direction: TextDirection.rtl));
      await tester.pump();
      expect(stripState(tester).fadesStart, isFalse);
      expect(stripState(tester).fadesEnd, isTrue);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(3000, 0),
      );
      await tester.pumpAndSettle();
      expect(stripState(tester).fadesStart, isTrue);
      expect(stripState(tester).fadesEnd, isFalse);
    });

    testWidgets('V1: a strip that fits draws no fade at all', (tester) async {
      await tester.pumpWidget(
        strip(width: 700, options: longPools.sublist(0, 2)),
      );
      await tester.pump();
      expect(stripState(tester).fadesStart, isFalse);
      expect(stripState(tester).fadesEnd, isFalse);
    });

    testWidgets('V1: at least 8 px of air between the strip and the refresh '
        'target, on the Głos chips and in the immersive chrome', (
      tester,
    ) async {
      useSurface(tester, const Size(390, 844));
      final auth = authAs();
      await tester.pumpWidget(
        overviewHost(
          Scaffold(
            body: MomentsFeedView(
              auth: auth,
              onRecord: () {},
              onCreate: () {},
              discoveryService: StaticDiscovery(populatedPool()),
              feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
              viewsService: StaticViews(const <String>{}),
              playerFactory: SilentPlayer.new,
            ),
          ),
          size: const Size(390, 844),
        ),
      );
      await settleOverview(tester);
      final chips = tester.getRect(find.byType(ImmersiveFilterRow));
      final refresh = tester.getRect(
        find.byKey(const ValueKey('moments-discovery-refresh')),
      );
      expect(refresh.left - chips.right, greaterThanOrEqualTo(8));

      await tester.pumpWidget(
        _themed(
          SizedBox(
            width: 390,
            child: ImmersiveFeedChrome(
              onCanvas: true,
              gutter: 16,
              filters: longPools,
              selectedFilterIndex: 0,
              onFilterSelected: (_) {},
              filterTrailing: const SizedBox.square(
                key: ValueKey('trailing'),
                dimension: 48,
              ),
            ),
          ),
        ),
      );
      final row = tester.getRect(find.byType(ImmersiveFilterRow));
      final trailing = tester.getRect(find.byKey(const ValueKey('trailing')));
      expect(trailing.left - row.right, greaterThanOrEqualTo(8));
    });

    for (final onCanvas in <bool>[true, false]) {
      for (final pearl in <bool>[false, true]) {
        if (!onCanvas && pearl) continue; // over media is theme-invariant
        testWidgets('A11Y-B5-02: focus on the SELECTED chip is visible '
            '(${onCanvas ? 'canvas' : 'over media'}, '
            '${pearl ? 'Pearl' : 'Dark'})', (tester) async {
          await tester.pumpWidget(
            _themed(
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ImmersiveFilterRow(
                    onCanvas: onCanvas,
                    selectedIndex: 0,
                    onSelected: (_) {},
                    options: longPools.sublist(0, 2),
                  ),
                ],
              ),
              pearl: pearl,
            ),
          );
          final ring = find.byKey(ImmersiveFilterRow.selectedFocusRingKey);
          expect(ring, findsNothing, reason: 'no ring without focus');

          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(ring, findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('pool-0')),
              matching: ring,
            ),
            findsOneWidget,
          );
          final border =
              (tester.widget<DecoratedBox>(ring).decoration as BoxDecoration)
                      .border!
                  as Border;
          expect(border.top.width, 2);
          final fill =
              (tester
                          .widget<AnimatedContainer>(
                            find.descendant(
                              of: find.byKey(const ValueKey('pool-0')),
                              matching: find.byType(AnimatedContainer),
                            ),
                          )
                          .decoration
                      as BoxDecoration)
                  .color!;
          // The ring sits INSIDE the selected fill, so what is behind the
          // chip (black or white footage, the canvas) never decides it.
          expect(_contrast(border.top.color, fill), greaterThanOrEqualTo(3));
          final chip = tester.getRect(
            find.descendant(
              of: find.byKey(const ValueKey('pool-0')),
              matching: find.byType(AnimatedContainer),
            ),
          );
          final ringRect = tester.getRect(ring);
          expect(ringRect.left, greaterThan(chip.left));
          expect(ringRect.right, lessThan(chip.right));

          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(ring, findsNothing, reason: 'focus moved to the next chip');
        });
      }
    }

    test('V6: the over-media plate carries a white label on a pure-white '
        'frame by itself', () {
      final plate = Color.alphaBlend(AppFinish.overlayChipColor, Colors.white);
      expect(_contrast(AppColors.white, plate), greaterThanOrEqualTo(4.5));
    });

    for (final pearl in <bool>[false, true]) {
      testWidgets('A11Y-B5-01: the format badge holds 4.5:1 on glass at the '
          'lit corner tint\'s peak (${pearl ? 'Pearl' : 'Dark'})', (
        tester,
      ) async {
        final palette = pearl ? AppPalette.light : AppPalette.dark;
        final tinted = Color.alphaBlend(
          AppColors.primary.withValues(alpha: palette.tintAlpha),
          palette.blockTop,
        );
        final ground = Color.alphaBlend(AppFinish.glass(palette), tinted);
        expect(
          _contrast(YoMomentsFormatBadge.ink(palette), ground),
          greaterThanOrEqualTo(4.5),
        );
        await tester.pumpWidget(
          _themed(const YoMomentsFormatBadge(), pearl: pearl),
        );
        final label = tester.widget<Text>(
          find.descendant(
            of: find.byType(YoMomentsFormatBadge),
            matching: find.byType(Text),
          ),
        );
        expect(label.style!.color, palette.textSecondary);

        await tester.pumpWidget(
          _themed(
            const YoMomentsFormatBadge(),
            pearl: pearl,
            media: const MediaQueryData(highContrast: true),
          ),
        );
        final pill =
            tester
                    .widget<Container>(
                      find.descendant(
                        of: find.byType(YoMomentsFormatBadge),
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        expect(pill.border, Border.all(color: palette.borderStrong));
        expect(pill.color, palette.surface);
      });
    }

    for (final pearl in <bool>[false, true]) {
      test('V3: the expiry ring\'s track is always drawn and its arc reads '
          'inside it (${pearl ? 'Pearl' : 'Dark'})', () {
        final palette = pearl ? AppPalette.light : AppPalette.dark;
        final pill = Color.alphaBlend(palette.glass, palette.blockTop);
        final track = Color.alphaBlend(
          MomentExpiryPill.trackColor(palette),
          pill,
        );
        expect(_contrast(track, pill), greaterThanOrEqualTo(1.5));
        expect(
          _contrast(palette.textSecondary, track),
          greaterThanOrEqualTo(3),
        );
        // R12's first track, for the record: invisible on the Dark glass.
        if (!pearl) expect(_contrast(palette.border, pill), lessThan(1.2));
      });
    }

    test('A11Y-B5-03: under high contrast a playing card and a focused one '
        'wear different colours', () {
      for (final palette in <AppPalette>[AppPalette.dark, AppPalette.light]) {
        final lit = YoVoiceBlock.edgeFor(
          palette,
          lit: true,
          highContrast: true,
        );
        final focused = YoVoiceBlock.edgeFor(
          palette,
          lit: false,
          focused: true,
          highContrast: true,
        );
        expect(lit.top.color, isNot(focused.top.color));
        expect(_contrast(lit.top.color, focused.top.color), greaterThan(1.5));
      }
    });

    testWidgets('A11Y-B5-07: under accessible navigation the bead and the '
        'block snap instead of fading', (tester) async {
      await tester.pumpWidget(
        _themed(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              YoVoiceBlock(lit: true, child: SizedBox(width: 120, height: 60)),
              YoGradientDisc(
                size: 48,
                icon: Icons.pause_rounded,
                emphasis: YoDiscEmphasis.lit,
              ),
            ],
          ),
          media: const MediaQueryData(accessibleNavigation: true),
        ),
      );
      Finder inside(Type type) => find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is YoVoiceBlock || widget is YoGradientDisc,
        ),
        matching: find.byType(type),
      );
      expect(inside(AnimatedContainer), findsNWidgets(3));
      for (final container in tester.widgetList<AnimatedContainer>(
        inside(AnimatedContainer),
      )) {
        expect(container.duration, Duration.zero);
      }
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).duration,
        Duration.zero,
      );
      expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration.zero,
      );

      // With motion on, the same widgets keep their fades.
      await tester.pumpWidget(
        _themed(
          const YoGradientDisc(
            size: 48,
            icon: Icons.pause_rounded,
            emphasis: YoDiscEmphasis.lit,
          ),
        ),
      );
      expect(
        tester
            .widget<AnimatedContainer>(find.byType(AnimatedContainer))
            .duration,
        YoGradientDisc.litIn,
      );
    });

    test('V4: the bead glyph is half the bead, never under 18', () {
      expect(YoVoiceBead.glyphSize(48), 24);
      expect(YoVoiceBead.glyphSize(44), 22);
      expect(YoVoiceBead.glyphSize(40), 20);
      expect(YoVoiceBead.glyphSize(34), 18);
      expect(YoVoiceBead.glyphSize(72), 36);
    });

    testWidgets('A11Y-B5-05: after a failed play the bead is named for the '
        'refresh glyph it shows', (tester) async {
      useSurface(tester, const Size(768, 2400));
      final auth = authAs();
      await tester.pumpWidget(
        overviewHost(
          Scaffold(
            body: MomentsFeedView(
              auth: auth,
              onRecord: () {},
              discoveryService: StaticDiscovery(populatedPool()),
              feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
              viewsService: StaticViews(const <String>{}),
              momentService: StubMomentService(),
              playerFactory: () =>
                  FakePreviewAudioPlayer(duration: const Duration(seconds: 45))
                    ..playError = StateError('decoder refused'),
            ),
          ),
          size: const Size(768, 2400),
        ),
      );
      await settleOverview(tester);
      final play = find.byKey(const ValueKey('moment-row-play-m1'));
      expect(tester.widget<IconButton>(play).tooltip, 'Play');
      await tester.ensureVisible(play);
      await tester.tap(play);
      await settleOverview(tester);
      expect(
        find.byKey(const ValueKey('moment-row-play-retry-m1')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<YoGradientDisc>(
              find.descendant(of: play, matching: find.byType(YoGradientDisc)),
            )
            .status,
        YoDiscStatus.failed,
      );
      expect(tester.widget<IconButton>(play).tooltip, 'Try again');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('V5: on Yeels the header "+" rests; on Głos it keeps the '
        'lift', (tester) async {
      Future<YoDiscEmphasis> emphasisFor(YoMomentsFormat format) async {
        await tester.pumpWidget(
          _themed(
            YoMomentsHeader(
              selectedFormat: format,
              onFormatSelected: (_) {},
              gutter: 24,
              onCreate: () {},
            ),
          ),
        );
        return tester
            .widget<YoGradientDisc>(
              find.descendant(
                of: find.byKey(const ValueKey('moments-create-cta')),
                matching: find.byType(YoGradientDisc),
              ),
            )
            .emphasis;
      }

      expect(await emphasisFor(YoMomentsFormat.reels), YoDiscEmphasis.rest);
      expect(await emphasisFor(YoMomentsFormat.voice), YoDiscEmphasis.lift);
    });

    for (final pearl in <bool>[false, true]) {
      testWidgets('V7: the R17 disc is opaque, so no scenery shows through '
          '(${pearl ? 'Pearl' : 'Dark'})', (tester) async {
        await tester.pumpWidget(
          _themed(
            const YoMomentsStateDisc(icon: Icons.mic_none_rounded),
            pearl: pearl,
          ),
        );
        final palette = pearl ? AppPalette.light : AppPalette.dark;
        final primary = (pearl ? AppTheme.lightTheme : AppTheme.darkTheme)
            .colorScheme
            .primary;
        final disc =
            tester
                    .widget<Container>(
                      find.descendant(
                        of: find.byType(YoMomentsStateDisc),
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        expect(disc.color!.a, 1);
        expect(disc.color, YoMomentsStateDisc.fill(palette, primary));
        expect(
          tester.getSize(find.byType(YoMomentsStateDisc)),
          const Size.square(64),
        );
      });
    }

    testWidgets('V8: the detail gone state uses the same R17 disc', (
      tester,
    ) async {
      await pumpListenDetail(
        tester,
        moment: listenMoment('gone'),
        seedMoment: false,
      );
      expect(find.byKey(const ValueKey('moment-detail-gone')), findsOneWidget);
      final disc = find.byKey(const ValueKey('moment-detail-gone-disc'));
      expect(disc, findsOneWidget);
      expect(tester.widget(disc), isA<YoMomentsStateDisc>());
      expect(
        find.descendant(
          of: disc,
          matching: find.byIcon(Icons.timer_off_outlined),
        ),
        findsOneWidget,
      );
      expect(tester.getSize(disc), const Size.square(64));
      expect(tester.takeException(), isNull);
    });
  });
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
}
