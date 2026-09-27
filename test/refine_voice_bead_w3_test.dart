// Refine-look batch 5 — the voice bead and Głos (signature moment W3).
//
// Pins what the spec's acceptance names for W3 — starting card 2 lights
// only card 2, pausing drops it to rest, starting card 3 moves the light,
// and a position tick never rebuilds a card body — plus the pieces the
// batch introduced: the lit block's high-contrast and Reduce Motion forms,
// the poured waveform, the expiry pill, the R8 chips, the author capsule,
// the additive bead on the shared voice row and the create actions.
//
// These are widget tests: they prove structure and state, not pixels. The
// rendered frames live in the batch's capture evidence.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_card.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_pill.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_transport_controls.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_follow_panel.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_queue_list.dart';
import 'package:yovoice/features/moments/presentation/widgets/yo_moments_chrome.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/shared/widgets/badges/yo_progress_ring.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_feed_chrome.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart'
    show OverlayPlate;
import 'package:yovoice/shared/widgets/voice/voice_player_row.dart';
import 'package:yovoice/shared/widgets/waveform/yo_waveform.dart';

import 'moment_listen_test_support.dart';
import 'moments_overview_test_support.dart';
import 'voice_moment_test_doubles.dart';

Widget _themed(
  Widget child, {
  bool light = false,
  bool highContrast = false,
  bool disableAnimations = false,
  double textScale = 1,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  // A theme switch between two pumps must not be caught mid-lerp.
  themeAnimationDuration: Duration.zero,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        highContrast: highContrast,
        disableAnimations: disableAnimations,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

Border _edgeOf(WidgetTester tester, Finder edgeBox) =>
    (tester.widget<DecoratedBox>(edgeBox).decoration as BoxDecoration).border!
        as Border;

void main() {
  group('W3 in the Głos feed', () {
    late VoidCallback restoreIdentity;

    setUp(() => restoreIdentity = installIdentityStub());
    tearDown(() => restoreIdentity());

    late List<FakePreviewAudioPlayer> players;

    Future<void> pumpFeed(WidgetTester tester) async {
      // Tall enough that every card is mounted without scrolling.
      const size = Size(768, 2600);
      useSurface(tester, size);
      players = <FakePreviewAudioPlayer>[];
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
              playerFactory: () {
                final player = FakePreviewAudioPlayer(
                  duration: const Duration(seconds: 40),
                );
                players.add(player);
                return player;
              },
            ),
          ),
          size: size,
        ),
      );
      await settleOverview(tester);
    }

    Future<void> tapPlay(WidgetTester tester, String id) async {
      final play = find.byKey(ValueKey('moment-row-play-$id'));
      await tester.ensureVisible(play);
      await tester.pump();
      await tester.tap(play);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      await tester.pump();
    }

    Color edgeColor(WidgetTester tester, String id) =>
        _edgeOf(tester, find.byKey(ValueKey('moment-row-edge-$id'))).top.color;

    YoDiscEmphasis beadOf(WidgetTester tester, String id) => tester
        .widget<YoGradientDisc>(
          find.descendant(
            of: find.byKey(ValueKey('moment-row-play-$id')),
            matching: find.byType(YoGradientDisc),
          ),
        )
        .emphasis;

    /// The ids whose card is lit right now, among the mounted cards.
    List<String> litCards(WidgetTester tester, AppPalette palette) => [
      for (final id in const ['m4', 'm5', 'm1', 'm2', 'm3', 'm6'])
        if (find.byKey(ValueKey('moment-row-edge-$id')).evaluate().isNotEmpty &&
            edgeColor(tester, id) == VoiceLitBlock.litEdge(palette))
          id,
    ];

    testWidgets('starting card 2 lights only card 2, pausing drops it to '
        'rest, starting card 3 moves the light', (tester) async {
      await pumpFeed(tester);
      final palette = AppPalette.of(
        tester.element(find.byKey(const ValueKey('moment-row-m4'))),
      );
      expect(litCards(tester, palette), isEmpty, reason: 'nothing plays');

      // Newest first: m4, m5 (card 2), m1 (card 3).
      await tapPlay(tester, 'm5');
      expect(players, hasLength(1));
      expect(litCards(tester, palette), ['m5']);
      expect(beadOf(tester, 'm5'), YoDiscEmphasis.lit);
      expect(beadOf(tester, 'm4'), YoDiscEmphasis.rest);
      expect(edgeColor(tester, 'm4'), palette.hairline);

      await tapPlay(tester, 'm5');
      expect(litCards(tester, palette), isEmpty, reason: 'paused = rest');
      expect(beadOf(tester, 'm5'), YoDiscEmphasis.rest);
      expect(edgeColor(tester, 'm5'), palette.hairline);

      await tapPlay(tester, 'm1');
      expect(litCards(tester, palette), ['m1']);
      expect(beadOf(tester, 'm1'), YoDiscEmphasis.lit);
      expect(beadOf(tester, 'm5'), YoDiscEmphasis.rest);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('position ticks never rebuild the card body or its lit '
        'shell; lighting rebuilds the shell only', (tester) async {
      await pumpFeed(tester);
      final card = find.byKey(const ValueKey('moment-row-m5'));
      final title = find.byKey(const ValueKey('moment-row-title-m5'));
      final shell = find.descendant(
        of: card,
        matching: find.byType(VoiceLitBlock),
      );
      final titleAtRest = tester.widget(title);

      await tapPlay(tester, 'm5');
      expect(
        identical(tester.widget(title), titleAtRest),
        isTrue,
        reason: 'lighting the card hands the same content to the lit shell',
      );
      final litShell = tester.widget(shell);
      final litTitle = tester.widget(title);

      for (final seconds in const [2, 4, 6, 8]) {
        players.single.emitPosition(Duration(seconds: seconds));
        await tester.pump();
      }
      expect(identical(tester.widget(title), litTitle), isTrue);
      expect(
        identical(tester.widget(shell), litShell),
        isTrue,
        reason: 'the energy notifier does not change on a position tick',
      );
      // …while the transport did move.
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('moment-row-time-m5')))
            .data,
        '0:08 / 0:40',
      );
      final wave = tester.widget<YoWaveform>(
        find.descendant(of: card, matching: find.byType(YoWaveform)),
      );
      expect(wave.progress, closeTo(8 / 40, 1e-9));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('the corner tint lives only in the lit card', (tester) async {
      await pumpFeed(tester);
      double tint(String id) => tester
          .widget<Opacity>(
            find.descendant(
              of: find.byKey(ValueKey('moment-row-$id')),
              matching: find.byKey(VoiceLitBlock.tintKey),
            ),
          )
          .opacity;

      expect(tint('m5'), 0);
      await tapPlay(tester, 'm5');
      expect(tint('m5'), 1);
      for (final other in const ['m4', 'm1', 'm2']) {
        expect(tint(other), 0, reason: 'one lit card per feed');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    });
  });

  group('W3 on the detail', () {
    testWidgets('the player card and its bead light while the Moment plays '
        'and rest when it pauses', (tester) async {
      final harness = await pumpListenDetail(
        tester,
        moment: listenMoment('m1'),
        size: const Size(390, 844),
      );
      final palette = AppPalette.of(
        tester.element(find.byKey(const ValueKey('moment-detail-play'))),
      );
      Color edge() => _edgeOf(
        tester,
        find.byKey(const ValueKey('moment-detail-player-card-edge')),
      ).top.color;
      YoDiscEmphasis bead() => tester
          .widget<YoGradientDisc>(
            find.descendant(
              of: find.byKey(const ValueKey('moment-detail-play')),
              matching: find.byType(YoGradientDisc),
            ),
          )
          .emphasis;

      expect(edge(), palette.hairline);
      expect(bead(), YoDiscEmphasis.rest);

      await playTo(tester, harness, const Duration(seconds: 9));
      await tester.pump(const Duration(milliseconds: 400));
      expect(edge(), VoiceLitBlock.litEdge(palette));
      expect(bead(), YoDiscEmphasis.lit);

      await tester.tap(find.byKey(const ValueKey('moment-detail-play')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(edge(), palette.hairline);
      expect(bead(), YoDiscEmphasis.rest);
      expect(tester.takeException(), isNull);
    });
  });

  group('the lit block', () {
    testWidgets('lit: primary edge and the corner tint; rest: hairline', (
      tester,
    ) async {
      for (final light in [false, true]) {
        final palette = light ? AppPalette.light : AppPalette.dark;
        for (final lit in [false, true]) {
          await tester.pumpWidget(
            _themed(
              VoiceLitBlock(
                lit: lit,
                edgeKey: const ValueKey('edge'),
                child: const SizedBox(width: 300, height: 160),
              ),
              light: light,
              disableAnimations: true,
            ),
          );
          await tester.pump();
          final edge = _edgeOf(tester, find.byKey(const ValueKey('edge')));
          expect(
            edge.top.color,
            lit ? VoiceLitBlock.litEdge(palette) : palette.hairline,
          );
          expect(edge.top.width, 1);
          expect(
            tester.widget<Opacity>(find.byKey(VoiceLitBlock.tintKey)).opacity,
            lit ? 1 : 0,
          );
        }
      }
      expect(VoiceLitBlock.litEdge(AppPalette.dark).a, closeTo(.45, .01));
      expect(VoiceLitBlock.litEdge(AppPalette.light).a, closeTo(.35, .01));
    });

    testWidgets('high contrast: a 1.5 px interactive edge, no tint and no '
        'gradient', (tester) async {
      await tester.pumpWidget(
        _themed(
          const VoiceLitBlock(
            lit: true,
            edgeKey: ValueKey('edge'),
            child: SizedBox(width: 300, height: 160),
          ),
          highContrast: true,
          disableAnimations: true,
        ),
      );
      await tester.pump();
      final edge = _edgeOf(tester, find.byKey(const ValueKey('edge')));
      expect(edge.top.color, AppPalette.dark.interactiveForeground);
      expect(edge.top.width, 1.5);
      expect(
        find.byKey(VoiceLitBlock.tintKey),
        findsNothing,
        reason: 'no corner tint',
      );
      final gradients = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => decoration.gradient != null);
      expect(gradients, isEmpty);
    });

    testWidgets('light fades in over 180 ms, and switches at once under '
        'Reduce Motion', (tester) async {
      Future<void> pump(bool lit, {required bool reduce}) => tester.pumpWidget(
        _themed(
          VoiceLitBlock(
            lit: lit,
            edgeKey: const ValueKey('edge'),
            child: const SizedBox(width: 300, height: 160),
          ),
          disableAnimations: reduce,
        ),
      );
      Color edge() =>
          _edgeOf(tester, find.byKey(const ValueKey('edge'))).top.color;

      await pump(false, reduce: false);
      await pump(true, reduce: false);
      await tester.pump(const Duration(milliseconds: 60));
      expect(edge(), isNot(VoiceLitBlock.litEdge(AppPalette.dark)));
      expect(edge(), isNot(AppPalette.dark.hairline));
      await tester.pump(const Duration(milliseconds: 200));
      expect(edge(), VoiceLitBlock.litEdge(AppPalette.dark));

      await pump(false, reduce: true);
      await pump(true, reduce: true);
      await tester.pump();
      expect(edge(), VoiceLitBlock.litEdge(AppPalette.dark));
      expect(
        tester.binding.transientCallbackCount,
        0,
        reason: 'no decorative motion under Reduce Motion',
      );
    });
  });

  group('the poured waveform', () {
    Widget pour(double? progress, {Object? snapKey, bool reduce = false}) =>
        _themed(
          SizedBox(
            width: 300,
            child: VoicePourWaveform(
              progress: progress,
              snapKey: snapKey,
              color: AppPalette.dark.waveUnplayed,
              height: 36,
              barWidth: 3,
              barGap: 2,
            ),
          ),
          disableAnimations: reduce,
        );
    double? shown(WidgetTester tester) =>
        tester.widget<YoWaveform>(find.byType(YoWaveform)).progress;

    testWidgets('pours forward between real positions and never past them', (
      tester,
    ) async {
      await tester.pumpWidget(pour(.2));
      expect(shown(tester), .2);
      await tester.pumpWidget(pour(.4));
      await tester.pump(const Duration(milliseconds: 100));
      expect(shown(tester), allOf(greaterThan(.2), lessThan(.4)));
      await tester.pump(const Duration(milliseconds: 150));
      expect(shown(tester), closeTo(.4, 1e-9));
      final wave = tester.widget<YoWaveform>(find.byType(YoWaveform));
      expect(wave.continuousProgress, isTrue);
      expect(wave.gradientSpan, YoWaveformGradientSpan.full);
    });

    testWidgets('a seek, a jump back and Reduce Motion snap', (tester) async {
      await tester.pumpWidget(pour(.2, snapKey: 0));
      await tester.pumpWidget(pour(.7, snapKey: 1));
      expect(shown(tester), .7, reason: 'a seek snaps');
      await tester.pumpWidget(pour(.1, snapKey: 1));
      expect(shown(tester), .1, reason: 'going back snaps');
      await tester.pumpWidget(pour(.1, reduce: true, snapKey: 1));
      await tester.pumpWidget(pour(.5, reduce: true, snapKey: 1));
      expect(shown(tester), .5, reason: 'no tween under Reduce Motion');
      await tester.pumpWidget(pour(null, snapKey: 1));
      expect(shown(tester), isNull, reason: 'no position, a still silhouette');
    });
  });

  group('the expiry pill', () {
    final created = DateTime(2026, 9, 27, 8);
    final expires = created.add(const Duration(hours: 24));

    testWidgets('a neutral ring of the real remaining share, amber only in '
        'the last hour', (tester) async {
      final palette = AppPalette.dark;
      await tester.pumpWidget(
        _themed(
          MomentExpiryPill(
            label: 'Wygasa za 18 godz.',
            labelKey: const ValueKey('label'),
            createdAt: created,
            expiresAt: expires,
            now: created.add(const Duration(hours: 6)),
          ),
        ),
      );
      final ring = tester.widget<YoProgressRing>(find.byType(YoProgressRing));
      expect(ring.value, closeTo(.75, 1e-9));
      expect(ring.arcColor, palette.interactiveForeground);
      expect(ring.trackColor, palette.border);
      expect(ring.size, MomentExpiryPill.ringSize);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('label'))).style!.color,
        palette.textSecondary,
      );

      await tester.pumpWidget(
        _themed(
          MomentExpiryPill(
            label: 'Wygasa za 42 min',
            labelKey: const ValueKey('label'),
            createdAt: created,
            expiresAt: expires,
            now: expires.subtract(const Duration(minutes: 42)),
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('label'))).style!.color,
        palette.warningForeground,
      );
      expect(
        tester.widget<YoProgressRing>(find.byType(YoProgressRing)).arcColor,
        palette.warningForeground,
      );
    });

    testWidgets('no ring without a real countdown', (tester) async {
      for (final pill in [
        const MomentExpiryPill(label: 'Dostępny do usunięcia'),
        MomentExpiryPill(
          label: 'Przesyłanie…',
          createdAt: created,
          expiresAt: expires,
          countdown: false,
        ),
      ]) {
        await tester.pumpWidget(_themed(pill));
        expect(find.byType(YoProgressRing), findsNothing);
        expect(find.text(pill.label), findsOneWidget);
      }
    });

    testWidgets('at 200 % text the label wraps under a top-aligned ring '
        'without overflow', (tester) async {
      await tester.pumpWidget(
        _themed(
          SizedBox(
            width: 150,
            child: Align(
              alignment: Alignment.centerLeft,
              child: MomentExpiryPill(
                label: 'Wygasa za 23 godz.',
                createdAt: created,
                expiresAt: expires,
                now: created.add(const Duration(hours: 1)),
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
      final ring = tester.getRect(find.byType(YoProgressRing));
      final label = tester.getRect(find.text('Wygasa za 23 godz.'));
      expect(label.height, greaterThan(40), reason: 'two lines');
      expect(ring.center.dy, lessThan(label.center.dy));
    });
  });

  group('R8 chips', () {
    Widget chrome({required bool onCanvas, bool light = false}) => _themed(
      SizedBox(
        width: 390,
        child: ImmersiveFeedChrome(
          gutter: 12,
          onCanvas: onCanvas,
          filters: const [
            ImmersiveChromeOption(key: ValueKey('f0'), label: 'Odkrywaj'),
            ImmersiveChromeOption(key: ValueKey('f1'), label: 'Obserwowani'),
          ],
          selectedFilterIndex: 0,
          onFilterSelected: (_) {},
        ),
      ),
      light: light,
    );
    BoxDecoration chipOf(WidgetTester tester, String key) =>
        tester
                .widget<AnimatedContainer>(
                  find.descendant(
                    of: find.byKey(ValueKey(key)),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration!
            as BoxDecoration;
    TextStyle labelOf(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text)).style!;

    testWidgets('on the canvas: ink inversion selected, hairline resting', (
      tester,
    ) async {
      for (final light in [false, true]) {
        final palette = light ? AppPalette.light : AppPalette.dark;
        await tester.pumpWidget(chrome(onCanvas: true, light: light));
        await tester.pump();
        final selected = chipOf(tester, 'f0');
        expect(selected.color, palette.textPrimary);
        expect((selected.border! as Border).top.color, Colors.transparent);
        expect(labelOf(tester, 'Odkrywaj').color, palette.background);
        expect(labelOf(tester, 'Odkrywaj').fontWeight, FontWeight.w700);
        final resting = chipOf(tester, 'f1');
        expect(resting.color, Colors.transparent);
        expect((resting.border! as Border).top.color, palette.hairlineControl);
        expect(labelOf(tester, 'Obserwowani').color, palette.textSecondary);
        expect(labelOf(tester, 'Obserwowani').fontWeight, FontWeight.w600);
        expect(
          tester.getSize(find.byKey(const ValueKey('f1'))).height,
          greaterThanOrEqualTo(48),
        );
      }
    });

    testWidgets('over media: a white chip with canvas ink, a translucent '
        'plate resting', (tester) async {
      await tester.pumpWidget(chrome(onCanvas: false));
      await tester.pump();
      expect(chipOf(tester, 'f0').color, AppColors.white);
      expect(
        labelOf(tester, 'Odkrywaj').color,
        AppFinish.chipOverMediaLabel(selected: true),
      );
      expect(chipOf(tester, 'f1').color, AppFinish.overlayChipColor);
      expect(labelOf(tester, 'Obserwowani').color, AppColors.white);
    });
  });

  group('the author capsule', () {
    testWidgets('a 38 px ring in a hairline pill; the name carries the heard '
        'state', (tester) async {
      for (final seen in [false, true]) {
        await tester.pumpWidget(
          _themed(
            MomentAuthorCapsule(
              name: 'Maja',
              seen: seen,
              semanticLabel: 'Open the story chain by Maja',
              onTap: () {},
            ),
          ),
        );
        final palette = AppPalette.dark;
        expect(
          tester.getSize(find.byKey(MomentAuthorCapsule.borderKey)),
          const Size.square(MomentAuthorCapsule.avatarDiameter),
        );
        final name = tester.widget<Text>(find.text('Maja')).style!;
        expect(name.fontWeight, seen ? FontWeight.w600 : FontWeight.w700);
        expect(name.color, seen ? palette.textSecondary : palette.textPrimary);
        final pill =
            tester
                    .widget<AnimatedContainer>(
                      find.descendant(
                        of: find.byType(MomentAuthorCapsule),
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration!
                as BoxDecoration;
        expect(pill.gradient, palette.blockGradient);
        expect((pill.border! as Border).top.color, palette.hairline);
        expect(pill.boxShadow, isEmpty, reason: 'chip-like: no lift');
      }
    });
  });

  group('the shared voice row', () {
    VoicePlayerRow row(VoicePlayerRowStyle style, {bool playing = false}) =>
        VoicePlayerRow(
          status: playing
              ? VoicePlayerRowStatus.playing
              : VoicePlayerRowStatus.idle,
          durationSeconds: 12,
          semanticsLabel: 'clip',
          onTap: () {},
          style: style,
        );

    testWidgets('the bubble keeps its legacy control unless it opts in', (
      tester,
    ) async {
      await tester.pumpWidget(
        _themed(
          row(
            VoicePlayerRowStyle.inline(
              foreground: Colors.white,
              mutedForeground: Colors.white,
              errorForeground: Colors.white,
            ),
          ),
        ),
      );
      expect(find.byType(YoGradientDisc), findsNothing);

      for (final (tone, playing) in [
        (YoDiscTone.brand, true),
        (YoDiscTone.brand, false),
        (YoDiscTone.onBrand, true),
      ]) {
        await tester.pumpWidget(
          _themed(
            row(
              VoicePlayerRowStyle.inline(
                foreground: Colors.white,
                mutedForeground: Colors.white,
                errorForeground: Colors.white,
                beadTone: tone,
              ),
              playing: playing,
            ),
          ),
        );
        final bead = tester.widget<YoGradientDisc>(find.byType(YoGradientDisc));
        expect(bead.size, 34);
        expect(bead.tone, tone);
        expect(
          bead.emphasis,
          tone == YoDiscTone.brand && playing
              ? YoDiscEmphasis.lit
              : YoDiscEmphasis.rest,
          reason: 'only the brand bead of the clip that plays emits light',
        );
      }
    });

    testWidgets('the thread row is the 40 px bead, lit only while playing', (
      tester,
    ) async {
      for (final playing in [false, true]) {
        await tester.pumpWidget(
          _themed(
            SizedBox(
              width: 320,
              child: row(
                VoicePlayerRowStyle.contained(
                  AppPalette.dark,
                  AppTheme.darkTheme.colorScheme,
                ),
                playing: playing,
              ),
            ),
          ),
        );
        final bead = tester.widget<YoGradientDisc>(find.byType(YoGradientDisc));
        expect(bead.size, 40);
        expect(bead.gloss, isTrue);
        expect(
          bead.emphasis,
          playing ? YoDiscEmphasis.lit : YoDiscEmphasis.rest,
        );
      }
    });
  });

  group('beads and create actions', () {
    VoiceMoment moment() => VoiceMoment(
      id: 'card',
      authorId: 'maja',
      authorName: 'Maja',
      authorPhotoUrl: null,
      caption: 'Poranek',
      audioUrl: 'https://cdn.example/card.m4a',
      durationSeconds: 20,
      likeCount: 0,
      commentCount: 0,
      isPublished: true,
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      expiresAt: DateTime.now().add(const Duration(hours: 23)),
      schemaVersion: 2,
      status: 'published',
      isDeleted: false,
    );

    testWidgets('MomentCard draws a 44 px bead at rest; a host can ask for '
        'more room', (tester) async {
      for (final size in [MomentCard.defaultPlayDiscSize, 52.0]) {
        await tester.pumpWidget(
          _themed(
            SizedBox(
              width: 390,
              child: MomentCard(
                moment: moment(),
                onComments: () {},
                playDiscSize: size,
              ),
            ),
          ),
        );
        await tester.pump();
        final bead = tester.widget<YoGradientDisc>(find.byType(YoGradientDisc));
        expect(bead.size, size);
        expect(bead.emphasis, YoDiscEmphasis.rest);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      }
    });

    testWidgets('"Utwórz" is the lifted gradient action; the compact "+" is '
        'the R6 disc', (tester) async {
      await tester.pumpWidget(
        _themed(
          SizedBox(width: 240, child: YoMomentsCreateButton(onTap: () {})),
        ),
      );
      final create = find.byKey(const ValueKey<String>('moments-create-cta'));
      expect(tester.widget(create), isA<YoGradientFilledButton>());
      expect(
        find.descendant(of: create, matching: find.byType(FilledButton)),
        findsOneWidget,
      );
      expect(tester.getSize(create).height, 48);

      var taps = 0;
      await tester.pumpWidget(
        _themed(YoMomentsCreateButton(onTap: () => taps++, compact: true)),
      );
      final compact = find.byKey(const ValueKey<String>('moments-create-cta'));
      expect(tester.widget(compact), isA<IconButton>());
      final disc = tester.widget<YoGradientDisc>(
        find.descendant(of: compact, matching: find.byType(YoGradientDisc)),
      );
      expect(disc.size, 48);
      expect(disc.emphasis, YoDiscEmphasis.lift);
      await tester.tap(compact);
      expect(taps, 1);
    });
  });

  // -------------------------------------------------------------------------
  // Review fixes (B5 round 2)
  // -------------------------------------------------------------------------

  group('keyboard focus on the feed card', () {
    late VoidCallback restoreIdentity;

    setUp(() => restoreIdentity = installIdentityStub());
    tearDown(() => restoreIdentity());

    testWidgets('Tab reaches a card and the lit block paints the 2 px focus '
        'ring; a focused control inside the card does not ring it', (
      tester,
    ) async {
      const size = Size(768, 2600);
      useSurface(tester, size);
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
              playerFactory: () => FakePreviewAudioPlayer(),
            ),
          ),
          size: size,
        ),
      );
      await settleOverview(tester);
      final palette = AppPalette.dark;
      // Newest first: m4 is the first card.
      final card = find.byKey(const ValueKey('moment-row-m4'));
      final ink = tester.widget<InkWell>(
        find.descendant(
          of: card,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is InkWell &&
                widget.excludeFromSemantics &&
                widget.borderRadius == AppRadius.block,
          ),
        ),
      );
      Border ring() =>
          (tester
                          .widget<DecoratedBox>(
                            find.descendant(
                              of: card,
                              matching: find.byKey(VoiceLitBlock.focusRingKey),
                            ),
                          )
                          .decoration
                      as BoxDecoration)
                  .border!
              as Border;

      expect(ring().top.color, Colors.transparent);
      var presses = 0;
      while (!ink.focusNode!.hasPrimaryFocus && presses < 80) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        presses++;
      }
      expect(
        ink.focusNode!.hasPrimaryFocus,
        isTrue,
        reason: 'the card is a Tab stop',
      );
      expect(ring().top.color, palette.focus);
      expect(ring().top.width, VoiceLitBlock.focusRingWidth);
      // The ring is a foreground: focusing moved nothing.
      final cardRect = tester.getRect(card);

      // The bead inside the card takes focus: the bead draws its own ring
      // and the card's goes, although the card's node still HAS focus.
      final bead = find.byKey(const ValueKey('moment-row-play-m4'));
      Focus.of(
        tester.element(
          find.descendant(of: bead, matching: find.byType(YoGradientDisc)),
        ),
      ).requestFocus();
      await tester.pump();
      await tester.pump();
      expect(ink.focusNode!.hasFocus, isTrue);
      expect(ring().top.color, Colors.transparent);
      expect(
        tester
            .widget<YoGradientDisc>(
              find.descendant(of: bead, matching: find.byType(YoGradientDisc)),
            )
            .focused,
        isTrue,
      );
      expect(tester.getRect(card), cardRect);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('the lit block ring: transparent at rest, focus when focused, '
        'in high contrast too', (tester) async {
      for (final highContrast in [false, true]) {
        for (final focused in [false, true]) {
          await tester.pumpWidget(
            _themed(
              VoiceLitBlock(
                lit: true,
                focused: focused,
                child: const SizedBox(width: 300, height: 160),
              ),
              highContrast: highContrast,
              disableAnimations: true,
            ),
          );
          final border =
              (tester
                              .widget<DecoratedBox>(
                                find.byKey(VoiceLitBlock.focusRingKey),
                              )
                              .decoration
                          as BoxDecoration)
                      .border!
                  as Border;
          expect(
            border.top.color,
            focused ? AppPalette.dark.focus : Colors.transparent,
          );
          expect(border.top.width, 2);
          expect(
            tester.getSize(find.byType(VoiceLitBlock)),
            const Size(300, 160),
          );
        }
      }
    });
  });

  group('a seek always snaps the poured waveform', () {
    late VoidCallback restoreIdentity;

    setUp(() => restoreIdentity = installIdentityStub());
    tearDown(() => restoreIdentity());

    testWidgets('feed: a position tick that lands while the seek is in '
        'flight does not turn the sought position into a pour', (tester) async {
      const size = Size(768, 2600);
      useSurface(tester, size);
      final auth = authAs();
      final players = <_GatedSeekPlayer>[];
      await tester.pumpWidget(
        overviewHost(
          Builder(
            // The pour is decorative motion, which the host switches off.
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: false),
              child: Scaffold(
                body: MomentsFeedView(
                  auth: auth,
                  onRecord: () {},
                  discoveryService: StaticDiscovery(populatedPool()),
                  feedService: QuietFeed(
                    firestore: fakeFirestore(),
                    auth: auth,
                  ),
                  viewsService: StaticViews(const <String>{}),
                  momentService: StubMomentService(),
                  playerFactory: () {
                    final player = _GatedSeekPlayer(
                      duration: const Duration(seconds: 40),
                    );
                    players.add(player);
                    return player;
                  },
                ),
              ),
            ),
          ),
          size: size,
        ),
      );
      await settleOverview(tester);
      double? shown() => tester
          .widget<YoWaveform>(
            find.descendant(
              of: find.byKey(const ValueKey('moment-row-wave-m5')),
              matching: find.byType(YoWaveform),
            ),
          )
          .progress;

      final play = find.byKey(const ValueKey('moment-row-play-m5'));
      await tester.ensureVisible(play);
      await tester.pump();
      await tester.tap(play);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final player = players.single;
      player.emitPosition(const Duration(seconds: 4));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(shown(), closeTo(.1, 1e-9));

      final slider = tester.getRect(
        find.byKey(const ValueKey('moment-row-progress-m5')),
      );
      await tester.tapAt(
        Offset(slider.left + slider.width * .75, slider.center.dy),
      );
      await tester.pump();
      expect(player.gate, isNotNull, reason: 'the seek is in flight');

      // A tick from before the seek lands while it is still in flight and
      // is drawn (a stream event arrives in a microtask, so it takes a
      // second frame)…
      player.emitPosition(const Duration(seconds: 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(shown(), inInclusiveRange(.1, .125));
      // …then the seek completes.
      player.gate!.complete();
      await tester.pump();
      final target = player.lastSeekPosition!.inMilliseconds / 40000;
      expect(target, greaterThan(.5));
      expect(
        shown(),
        closeTo(target, 1e-9),
        reason: 'the sought position snaps at once; it never pours',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    });

    testWidgets('detail: the same race on the ±15 s skip still snaps', (
      tester,
    ) async {
      final moment = listenMoment('m1');
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = FakeFirebaseFirestore();
      await db
          .collection('voiceMoments')
          .doc(moment.id)
          .set(listenMomentDoc(moment));
      final auth = listenAuth();
      final moments = MomentService(
        firestore: db,
        auth: auth,
        storage: MockFirebaseStorage(),
        readService: VoiceMomentReadService(
          viewInvoker: fakeVoiceMomentViewInvoker(
            firestore: db,
            viewerUid: listenViewerUid,
          ),
        ),
        mediaAccessInvoker: fakeMomentMediaAccessInvoker(),
      );
      final players = <_GatedSeekPlayer>[];
      final queue = MomentNeighbourQueue();
      addTearDown(queue.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: MomentDetailScreen(
            moment: moment,
            momentService: moments,
            feedService: HomeFeedService(firestore: db, auth: auth),
            auth: auth,
            neighbourQueue: queue,
            playerFactory: () {
              final player = _GatedSeekPlayer(
                duration: const Duration(seconds: 40),
              );
              players.add(player);
              return player;
            },
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      double? shown() => tester
          .widget<YoWaveform>(
            find.descendant(
              of: find.byKey(const ValueKey('moment-detail-waveform')),
              matching: find.byType(YoWaveform),
            ),
          )
          .progress;

      final play = find.byKey(const ValueKey('moment-detail-play'));
      await tester.ensureVisible(play);
      await tester.pump();
      await tester.tap(play);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final player = players.single;
      player.emitPosition(const Duration(seconds: 4));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(shown(), closeTo(.1, 1e-9));

      final skip = find.byKey(const ValueKey('moment-detail-skip-forward'));
      await tester.ensureVisible(skip);
      await tester.pump();
      await tester.tap(skip);
      await tester.pump();
      expect(player.gate, isNotNull, reason: 'the seek is in flight');
      player.emitPosition(const Duration(seconds: 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(shown(), inInclusiveRange(.1, .125));
      player.gate!.complete();
      await tester.pump();
      expect(player.lastSeekPosition, const Duration(seconds: 19));
      expect(
        shown(),
        closeTo(19 / 40, 1e-9),
        reason: 'the sought position snaps at once; it never pours',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    });
  });

  group('over-media chip focus', () {
    testWidgets('the chosen white chip rings in its own dark ink, a resting '
        'chip in white', (tester) async {
      await tester.pumpWidget(
        _themed(
          SizedBox(
            width: 390,
            child: ImmersiveFeedChrome(
              gutter: 12,
              onCanvas: false,
              filters: const [
                ImmersiveChromeOption(key: ValueKey('f0'), label: 'Odkrywaj'),
                ImmersiveChromeOption(
                  key: ValueKey('f1'),
                  label: 'Obserwowani',
                ),
              ],
              selectedFilterIndex: 0,
              onFilterSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      BoxDecoration chipOf(String key) =>
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: find.byKey(ValueKey(key)),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      void focus(String key) => Focus.of(
        tester.element(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(AnimatedContainer),
          ),
        ),
      ).requestFocus();

      // Focus changes land in a microtask, the ring on the next frame.
      focus('f0');
      await tester.pump();
      await tester.pump();
      final chosen = chipOf('f0');
      final chosenRing = (chosen.border! as Border).top;
      expect(chosen.color, AppColors.white);
      expect(
        chosenRing.color,
        AppFinish.chipOverMediaLabel(selected: true),
        reason: 'a white ring would vanish into the white fill',
      );
      expect(chosenRing.color, isNot(chosen.color));
      expect(chosenRing.width, 2);

      focus('f1');
      await tester.pump();
      await tester.pump();
      expect((chipOf('f1').border! as Border).top.color, AppColors.white);
      expect((chipOf('f0').border! as Border).top.color, Colors.transparent);
    });
  });

  group('R2 ink on the capsule and the record card', () {
    testWidgets(
      'InkSparkle on Android, no ripple anywhere else',
      (tester) async {
        final restoreIdentity = installIdentityStub();
        addTearDown(restoreIdentity);
        final expected = defaultTargetPlatform == TargetPlatform.android
            ? InkSparkle.splashFactory
            : NoSplash.splashFactory;
        expect(momentBlockSplashFactory, expected);

        await tester.pumpWidget(
          _themed(
            MomentAuthorCapsule(
              name: 'Maja',
              seen: false,
              semanticLabel: 'Open the story chain by Maja',
              onTap: () {},
            ),
          ),
        );
        expect(
          tester
              .widget<InkWell>(
                find.descendant(
                  of: find.byType(MomentAuthorCapsule),
                  matching: find.byType(InkWell),
                ),
              )
              .splashFactory,
          expected,
        );

        final auth = authAs();
        await tester.pumpWidget(
          overviewHost(
            Scaffold(
              body: SizedBox(
                width: 320,
                child: MomentsFollowPanel(
                  onRecord: () {},
                  auth: auth,
                  followService: FollowService(
                    firestore: fakeFirestore(),
                    auth: auth,
                  ),
                  friendsStream: Stream.value([friend('ola', name: 'Ola')]),
                  followingStream: Stream.value(const []),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          tester
              .widget<InkWell>(
                find.descendant(
                  of: find.byKey(const ValueKey('moments-follow-panel-record')),
                  matching: find.byType(InkWell),
                ),
              )
              .splashFactory,
          expected,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 20));
      },
      variant: TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }),
    );
  });

  group('the expiry pill keeps time by itself', () {
    final created = DateTime(2026, 9, 27, 8);
    final expires = created.add(const Duration(hours: 24));

    testWidgets('a pill left open across the one-hour mark turns amber '
        'without any other rebuild', (tester) async {
      var now = expires.subtract(const Duration(hours: 1, minutes: 5));
      await tester.pumpWidget(
        _themed(
          MomentExpiryPill(
            label: 'Wygasa za 1 godz.',
            labelKey: const ValueKey('label'),
            createdAt: created,
            expiresAt: expires,
            clock: () => now,
          ),
        ),
      );
      Color ink() => tester
          .widget<Text>(find.byKey(const ValueKey('label')))
          .style!
          .color!;
      expect(ink(), AppPalette.dark.textSecondary);

      now = now.add(const Duration(minutes: 4));
      await tester.pump(const Duration(minutes: 4));
      expect(ink(), AppPalette.dark.textSecondary, reason: 'still > 1 h');

      now = now.add(const Duration(minutes: 1, milliseconds: 1));
      await tester.pump(const Duration(minutes: 1, milliseconds: 1));
      expect(ink(), AppPalette.dark.warningForeground);
      expect(
        tester.widget<YoProgressRing>(find.byType(YoProgressRing)).arcColor,
        AppPalette.dark.warningForeground,
      );
    });

    testWidgets('a mark days away is reached in steps of at most a day', (
      tester,
    ) async {
      final longCreated = DateTime(2026, 9, 20, 8);
      final longExpires = longCreated.add(const Duration(days: 7));
      var now = longExpires.subtract(
        const Duration(days: 2, hours: 1, minutes: 10),
      );
      await tester.pumpWidget(
        _themed(
          MomentExpiryPill(
            label: 'Wygasa za 2 dni',
            labelKey: const ValueKey('label'),
            createdAt: longCreated,
            expiresAt: longExpires,
            clock: () => now,
          ),
        ),
      );
      Color ink() => tester
          .widget<Text>(find.byKey(const ValueKey('label')))
          .style!
          .color!;
      for (var day = 0; day < 2; day++) {
        now = now.add(MomentExpiryPill.longestWait);
        await tester.pump(MomentExpiryPill.longestWait);
        expect(ink(), AppPalette.dark.textSecondary);
      }
      now = now.add(const Duration(minutes: 10, milliseconds: 1));
      await tester.pump(const Duration(minutes: 10, milliseconds: 1));
      expect(ink(), AppPalette.dark.warningForeground);
    });
  });

  group('small bead and layout fixes', () {
    VoiceMoment cardMoment() => VoiceMoment(
      id: 'card',
      authorId: 'maja',
      authorName: 'Maja',
      authorPhotoUrl: null,
      caption: 'Poranek',
      audioUrl: 'https://cdn.example/card.m4a',
      durationSeconds: 20,
      likeCount: 0,
      commentCount: 0,
      isPublished: true,
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      expiresAt: DateTime.now().add(const Duration(hours: 23)),
      schemaVersion: 2,
      status: 'published',
      isDeleted: false,
    );

    testWidgets('the MomentCard bead taps a light haptic when it starts a '
        'clip, and none when it pauses', (tester) async {
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
      await tester.pumpWidget(
        _themed(
          SizedBox(
            width: 390,
            child: MomentCard(
              moment: cardMoment(),
              onComments: () {},
              mediaUriResolver: (_) async =>
                  Uri.parse('https://cdn.example/card.m4a'),
              playerFactory: () =>
                  FakePreviewAudioPlayer(duration: const Duration(seconds: 20)),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(haptics, <Object?>['HapticFeedbackType.lightImpact']);
      expect(
        tester.widget<YoGradientDisc>(find.byType(YoGradientDisc)).emphasis,
        YoDiscEmphasis.lit,
      );
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(haptics, hasLength(1), reason: 'pausing is silent');
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('the "15" in the skip glyphs never scales with the text', (
      tester,
    ) async {
      await tester.pumpWidget(
        _themed(
          SizedBox(
            width: 600,
            child: MomentTransportControls(
              position: const Duration(seconds: 20),
              total: const Duration(seconds: 45),
              isPlaying: false,
              busy: false,
              canSeek: true,
              compact: false,
              onTogglePlay: () {},
              onSeek: (_) {},
            ),
          ),
          textScale: 2,
        ),
      );
      final digits = find.text('15');
      expect(digits, findsNWidgets(2));
      for (final element in digits.evaluate()) {
        expect((element.widget as Text).textScaler, TextScaler.noScaling);
      }
      expect(tester.getSize(digits.first).height, lessThan(16));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Pearl draws the format badge as a bare label, Dark keeps '
        'its glass', (tester) async {
      for (final light in [false, true]) {
        await tester.pumpWidget(
          _themed(const YoMomentsFormatBadge(), light: light),
        );
        final pill =
            tester
                    .widget<Container>(
                      find.descendant(
                        of: find.byType(YoMomentsFormatBadge),
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration!
                as BoxDecoration;
        expect(pill.color, light ? isNull : AppPalette.dark.glass);
        expect(pill.border, isNull);
      }
    });

    testWidgets('the follow pill keeps its label off the curve at 200 %', (
      tester,
    ) async {
      final restoreIdentity = installIdentityStub();
      addTearDown(restoreIdentity);
      for (final scale in [1.0, 2.0]) {
        useSurface(tester, const Size(400, 1200));
        final auth = authAs();
        await tester.pumpWidget(
          overviewHost(
            Scaffold(
              body: SizedBox(
                width: 320,
                child: MomentsFollowPanel(
                  key: ValueKey(scale),
                  onRecord: () {},
                  auth: auth,
                  followService: FollowService(
                    firestore: fakeFirestore(),
                    auth: auth,
                  ),
                  friendsStream: Stream.value([friend('ola', name: 'Ola')]),
                  followingStream: Stream.value(const []),
                ),
              ),
            ),
            textScale: scale,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        final button = find.byKey(const ValueKey('moments-follow-ola'));
        final padding = tester
            .widget<ButtonStyleButton>(button)
            .style!
            .padding!
            .resolve(<WidgetState>{})!
            .resolve(TextDirection.ltr);
        expect(padding.left, closeTo(scale == 1 ? 12 : 19.2, 1e-9));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    });
  });

  group('the Głos refresh circle', () {
    late VoidCallback restoreIdentity;

    setUp(() => restoreIdentity = installIdentityStub());
    tearDown(() => restoreIdentity());

    testWidgets('hover fills the 40 px circle and leaves the 48 px plate '
        'clear: one circle, never two', (tester) async {
      const size = Size(390, 844);
      useSurface(tester, size);
      final auth = authAs();
      await tester.pumpWidget(
        overviewHost(
          Scaffold(
            body: MomentsFeedView(
              auth: auth,
              onRecord: () {},
              immersiveHeader: const ImmersiveFeedHeaderSlots(),
              discoveryService: StaticDiscovery(populatedPool()),
              feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
              viewsService: StaticViews(const <String>{}),
              momentService: StubMomentService(),
              playerFactory: () => FakePreviewAudioPlayer(),
            ),
          ),
          size: size,
        ),
      );
      await settleOverview(tester);
      final palette = AppPalette.dark;
      final circle = find.byKey(
        const ValueKey('moments-discovery-refresh-ring'),
      );
      BoxDecoration ring() =>
          tester.widget<AnimatedContainer>(circle).decoration! as BoxDecoration;
      Color? plate() =>
          (tester
                      .widget<AnimatedContainer>(
                        find.descendant(
                          of: find.descendant(
                            of: find.byKey(
                              const ValueKey('moments-discovery-refresh'),
                            ),
                            matching: find.byType(OverlayPlate),
                          ),
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .color;

      expect(tester.getSize(circle), const Size.square(40));
      expect(ring().color, Colors.transparent);
      expect((ring().border! as Border).top.color, palette.hairlineControl);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(circle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(ring().color, AppFinish.glass(palette, hovered: true));
      expect((ring().border! as Border).top.color, palette.hairlineHover);
      expect(plate(), Colors.transparent, reason: 'no second, 48 px circle');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    });
  });

  group('the share action at a large text size', () {
    late VoidCallback restoreIdentity;

    setUp(() => restoreIdentity = installIdentityStub());
    tearDown(() => restoreIdentity());

    testWidgets('where the reply leaves too little room the share label '
        'gives way to the icon instead of breaking inside the word', (
      tester,
    ) async {
      await loadInterFont();
      const size = Size(560, 3200);
      useSurface(tester, size);
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
              playerFactory: () => FakePreviewAudioPlayer(),
            ),
          ),
          size: size,
          locale: const Locale('pl'),
          textScale: 2,
        ),
      );
      await settleOverview(tester);
      final shares = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'moment-row-share-',
            ),
      );
      expect(shares, findsWidgets);
      var iconOnly = 0;
      for (final element in shares.evaluate()) {
        final key = element.widget.key!;
        final label = find.descendant(
          of: find.byKey(key),
          matching: find.text('Udostępnij'),
        );
        if (label.evaluate().isEmpty) {
          iconOnly++;
          expect(element.widget, isA<IconButton>());
          continue;
        }
        // A labelled share is one line: exactly as tall as the like
        // count beside it, which is the same label style.
        final id = (key as ValueKey<String>).value.substring(
          'moment-row-share-'.length,
        );
        final count = find.descendant(
          of: find.byKey(ValueKey('moment-row-like-$id')),
          matching: find.byType(Text),
        );
        expect(
          tester.getSize(label).height,
          tester.getSize(count).height,
          reason: 'the word never breaks',
        );
      }
      expect(
        iconOnly,
        greaterThan(0),
        reason: 'this width leaves too little room for the word',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    });
  });

  group('the chat voice bubble (for B7)', () {
    Widget bubble({
      required bool outgoing,
      required ValueListenable<double?>? progress,
      bool playing = false,
      bool light = false,
    }) {
      final palette = light ? AppPalette.light : AppPalette.dark;
      final theme = light ? AppTheme.lightTheme : AppTheme.darkTheme;
      return _themed(
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: outgoing
                ? AppGradients.primaryAction(theme.colorScheme)
                : palette.blockGradient,
          ),
          child: VoicePlayerRow(
            status: playing
                ? VoicePlayerRowStatus.playing
                : VoicePlayerRowStatus.idle,
            durationSeconds: 12,
            semanticsLabel: 'voice message',
            onTap: () {},
            progress: progress,
            style: VoicePlayerRowStyle.bubble(
              outgoing: outgoing,
              palette: palette,
              colors: theme.colorScheme,
              foreground: outgoing ? AppColors.white : palette.textPrimary,
              mutedForeground: outgoing
                  ? AppFinish.outgoingMeta
                  : palette.textSecondary,
              errorForeground: outgoing
                  ? AppColors.white
                  : palette.dangerForeground,
            ),
          ),
        ),
        light: light,
      );
    }

    YoWaveform wave(WidgetTester tester) =>
        tester.widget<YoWaveform>(find.byType(YoWaveform));

    testWidgets('incoming: the 34 px brand bead, lit only while it plays, '
        'and the R13 inks', (tester) async {
      for (final light in [false, true]) {
        final palette = light ? AppPalette.light : AppPalette.dark;
        final scheme =
            (light ? AppTheme.lightTheme : AppTheme.darkTheme).colorScheme;
        for (final playing in [false, true]) {
          final position = ValueNotifier<double?>(.4);
          addTearDown(position.dispose);
          await tester.pumpWidget(
            bubble(
              outgoing: false,
              progress: position,
              playing: playing,
              light: light,
            ),
          );
          final bead = tester.widget<YoGradientDisc>(
            find.byType(YoGradientDisc),
          );
          expect(bead.size, 34);
          expect(bead.tone, YoDiscTone.brand);
          expect(bead.gloss, isTrue);
          expect(
            bead.emphasis,
            playing ? YoDiscEmphasis.lit : YoDiscEmphasis.rest,
          );
          expect(wave(tester).color, palette.waveUnplayed);
          expect(
            wave(tester).playedGradient,
            AppGradients.voicePlayed(scheme, palette),
          );
          expect(wave(tester).continuousProgress, isTrue);
          expect(wave(tester).gradientSpan, YoWaveformGradientSpan.full);
          expect(wave(tester).progress, closeTo(.4, 1e-9));
        }
      }
    });

    testWidgets('outgoing: the white @ .22 bead that never lights, white '
        'played over the measured unplayed white', (tester) async {
      final position = ValueNotifier<double?>(.25);
      addTearDown(position.dispose);
      await tester.pumpWidget(
        bubble(outgoing: true, progress: position, playing: true),
      );
      final bead = tester.widget<YoGradientDisc>(find.byType(YoGradientDisc));
      expect(bead.size, 34);
      expect(bead.tone, YoDiscTone.onBrand);
      expect(bead.emphasis, YoDiscEmphasis.rest);
      expect(bead.gloss, isFalse);
      expect(wave(tester).color, AppFinish.outgoingWaveUnplayed);
      expect(wave(tester).playedColor, AppFinish.outgoingWavePlayed);
      expect(wave(tester).playedGradient, isNull);
      expect(wave(tester).progress, closeTo(.25, 1e-9));
    });

    testWidgets('the real position pours forward, snaps back, and a null '
        'position (completion, a new source) is a still silhouette', (
      tester,
    ) async {
      final position = ValueNotifier<double?>(null);
      addTearDown(position.dispose);
      await tester.pumpWidget(
        bubble(outgoing: false, progress: position, playing: true),
      );
      expect(wave(tester).progress, isNull);

      position.value = .2;
      await tester.pump();
      expect(wave(tester).progress, closeTo(.2, 1e-9));
      position.value = .5;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(wave(tester).progress, allOf(greaterThan(.2), lessThan(.5)));
      await tester.pump(const Duration(milliseconds: 150));
      expect(wave(tester).progress, closeTo(.5, 1e-9));

      position.value = .1;
      await tester.pump();
      expect(wave(tester).progress, closeTo(.1, 1e-9), reason: 'back snaps');

      position.value = null;
      await tester.pump();
      expect(wave(tester).progress, isNull);
    });

    testWidgets('a ValueListenable<double> from an older caller still works', (
      tester,
    ) async {
      final position = ValueNotifier<double>(.3);
      addTearDown(position.dispose);
      await tester.pumpWidget(bubble(outgoing: true, progress: position));
      expect(wave(tester).progress, closeTo(.3, 1e-9));
    });
  });
}

/// A player whose seek waits for the test, so a position tick can land
/// while the seek is still in flight — the race the seek generation must
/// survive.
class _GatedSeekPlayer extends FakePreviewAudioPlayer {
  _GatedSeekPlayer({required Duration duration}) : super(duration: duration);

  Completer<void>? gate;

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    lastSeekPosition = position;
    final pending = gate = Completer<void>();
    await pending.future;
  }
}
