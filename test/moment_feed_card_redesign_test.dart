import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/features/moments/presentation/widgets/yo_moments_chrome.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/waveform/yo_waveform.dart';

import 'moments_overview_test_support.dart';
import 'voice_moment_test_doubles.dart';

/// The Głos row (G4, which replaced the 06 Voice card): the caption as one
/// line collapsed and three open, no format badge at any width (the switch
/// names the format), the 44 bead / 26 waveform / clock-beside-the-wave
/// transport, the action line's wrap rule, hover, the liked heart role, no
/// view counts, and "Odpowiedz głosem" into the recorder.
void main() {
  late VoidCallback restoreIdentity;

  setUpAll(loadInterFont);
  setUp(() => restoreIdentity = installIdentityStub());
  tearDown(() => restoreIdentity());

  Future<StaticDiscovery> pumpCards(
    WidgetTester tester, {
    required Size size,
    List<VoiceMoment>? pool,
    double textScale = 1,
    GlobalKey<NavigatorState>? navigatorKey,
    StubMomentService? momentService,
  }) async {
    useSurface(tester, size);
    final auth = authAs();
    final discovery = StaticDiscovery(pool ?? populatedPool());
    await tester.pumpWidget(
      overviewHost(
        Scaffold(
          body: MomentsFeedView(
            auth: auth,
            onRecord: () {},
            discoveryService: discovery,
            feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
            viewsService: StaticViews(const <String>{}),
            momentService: momentService ?? StubMomentService(),
            playerFactory: SilentPlayer.new,
          ),
        ),
        textScale: textScale,
        size: size,
        navigatorKey: navigatorKey,
      ),
    );
    await settleOverview(tester);
    return discovery;
  }

  Future<void> reveal(WidgetTester tester, String id) async {
    final row = find.byKey(ValueKey('moment-row-$id'));
    if (row.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        row,
        240,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('moments-feed-scroll')),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            )
            .first,
      );
    }
    await tester.ensureVisible(row);
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, String id) async {
    await reveal(tester, id);
    await tester.tap(find.byKey(ValueKey('moment-row-play-$id')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
  }

  testWidgets('the caption is one line collapsed and three open, and an '
      'empty caption is not replaced by the format name', (tester) async {
    await pumpCards(tester, size: const Size(390, 844));
    final empty = find.byKey(const ValueKey('moment-row-m4'));
    expect(
      find.descendant(of: empty, matching: find.text('Voice Moment')),
      findsNothing,
    );
    await reveal(tester, 'm3');
    final caption = find.byKey(const ValueKey('moment-row-caption-m3'));
    expect(tester.widget<Text>(caption).maxLines, 1);
    expect(tester.widget<Text>(caption).overflow, TextOverflow.ellipsis);
    await open(tester, 'm3');
    expect(tester.widget<Text>(caption).maxLines, 3);
    expect(tester.widget<Text>(caption).overflow, TextOverflow.ellipsis);
    // No second "title" line is ever invented: one caption text.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('moment-row-m3')),
        matching: find.byKey(const ValueKey('moment-row-caption-m3')),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no VOICE MOMENT badge on a row at any width: the switch above '
      'already names the format', (tester) async {
    for (final size in const [
      Size(390, 900),
      Size(768, 900),
      Size(1440, 900),
    ]) {
      await pumpCards(tester, size: size);
      expect(find.byType(YoMomentsFormatBadge), findsNothing, reason: '$size');
      expect(find.byKey(const ValueKey('moment-row-badge-m4')), findsNothing);
    }
  });

  // G4 / R13: the open row keeps the R14 bead (44 here, the board's size) and
  // the R13 bars (3 px, 2 px gaps, the palette's unplayed ink, the played
  // sweep across the whole run) at 26 high; the clock sits BESIDE the wave,
  // end-aligned, so the wave never competes with it for the row's width.
  testWidgets('transport: a 44 bead, a 26 waveform under a transparent seek '
      'slider, the clock at its end', (tester) async {
    await pumpCards(tester, size: const Size(768, 1024));
    await open(tester, 'm4');
    final play = find.byKey(const ValueKey('moment-row-play-m4'));
    expect(tester.getSize(play), const Size(48, 48), reason: 'the target');
    expect(
      tester.getSize(
        find.descendant(of: play, matching: find.byType(YoGradientDisc)),
      ),
      const Size(44, 44),
      reason: 'the bead',
    );
    final card = find.byKey(const ValueKey('moment-row-m4'));
    final palette = AppPalette.of(tester.element(card));
    final wave = find.descendant(of: card, matching: find.byType(YoWaveform));
    expect(wave, findsOneWidget);
    expect(tester.getSize(wave).height, 26);
    final waveform = tester.widget<YoWaveform>(wave);
    expect(waveform.barWidth, 3);
    expect(waveform.barGap, 2);
    expect(waveform.playedGradient, isNotNull);
    expect(waveform.color, palette.waveUnplayed);
    expect(waveform.continuousProgress, isTrue);
    expect(waveform.gradientSpan, YoWaveformGradientSpan.full);
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('moment-row-progress-m4')),
    );
    expect(slider.max, 12000);
    expect(slider.value, 0);
    final time = find.byKey(const ValueKey('moment-row-time-m4'));
    expect(tester.widget<Text>(time).data, '0:00 / 0:12');
    // The slider lies over the waveform: same vertical band.
    final sliderRect = tester.getRect(
      find.byKey(const ValueKey('moment-row-progress-m4')),
    );
    final waveRect = tester.getRect(wave);
    expect(sliderRect.top, lessThanOrEqualTo(waveRect.top));
    expect(sliderRect.bottom, greaterThanOrEqualTo(waveRect.bottom));
    // The clock sits beside the wave, on its line, at the row's end.
    final timeRect = tester.getRect(time);
    expect(timeRect.left, greaterThan(sliderRect.right));
    expect(timeRect.center.dy, closeTo(waveRect.center.dy, 2));
    expect(timeRect.right, closeTo(tester.getRect(card).right - 24, 1));

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('below the width the reply needs it takes its own line; wider, '
      'the whole action line is one row', (tester) async {
    await pumpCards(tester, size: const Size(320, 800));
    await open(tester, 'm4');
    final reply = tester.getRect(
      find.byKey(const ValueKey('moment-row-reply-voice-m4')),
    );
    final like = tester.getRect(
      find.byKey(const ValueKey('moment-row-like-m4')),
    );
    final share = tester.getRect(
      find.byKey(const ValueKey('moment-row-share-m4')),
    );
    expect(reply.top, greaterThanOrEqualTo(like.bottom - 1));
    expect(share.top, closeTo(like.top, 1), reason: 'share keeps the line');
    expect(
      tester.getSize(find.byKey(const ValueKey('moment-row-share-m4'))).width,
      48,
    );
    expect(find.text('Share'), findsNothing, reason: 'share is an icon');
    await tester.pumpWidget(const SizedBox());

    await pumpCards(tester, size: const Size(1440, 900));
    await open(tester, 'm4');
    final wideReply = tester.getRect(
      find.byKey(const ValueKey('moment-row-reply-voice-m4')),
    );
    final wideLike = tester.getRect(
      find.byKey(const ValueKey('moment-row-like-m4')),
    );
    final wideShare = tester.getRect(
      find.byKey(const ValueKey('moment-row-share-m4')),
    );
    final wideMore = tester.getRect(
      find.byKey(const ValueKey('moment-row-menu-m4')),
    );
    expect(wideReply.top, closeTo(wideLike.top, 1), reason: 'one row');
    expect(wideShare.top, closeTo(wideLike.top, 1));
    expect(wideMore.left, greaterThan(wideShare.left));
    expect(wideReply.left, greaterThan(wideLike.left));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hover lays the row wash; the liked heart wears the secondary '
      'role; no view counts exist', (tester) async {
    await pumpCards(tester, size: const Size(1440, 900));
    final body = find.byKey(const ValueKey('moment-row-body-m4'));
    final palette = AppPalette.of(tester.element(body));
    final overlay = tester.widget<InkWell>(body).overlayColor!;
    expect(overlay.resolve(<WidgetState>{}), Colors.transparent);
    expect(
      overlay.resolve(<WidgetState>{WidgetState.hovered}),
      palette.textPrimary.withValues(alpha: .04),
    );
    expect(
      overlay.resolve(<WidgetState>{WidgetState.pressed}),
      palette.interactiveForeground.withValues(alpha: .10),
    );
    // What is PAINTED under the pointer, not only what would resolve: the
    // row's ink layer draws the hover wash once the pointer is over it.
    final hover = palette.textPrimary.withValues(alpha: .04);
    final ink = Material.of(tester.element(body)) as RenderObject;
    expect(ink, isNot(paints..rect(color: hover)), reason: 'no wash at rest');
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    // The row's own surface (its text), not a control inside it.
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('moment-row-name-m4'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(ink, paints..rect(color: hover), reason: 'the wash, painted');
    expect(tester.takeException(), isNull);
    await gesture.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(ink, isNot(paints..rect(color: hover)), reason: 'and gone again');

    await open(tester, 'm6');
    final likeIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('moment-row-like-m6')),
        matching: find.byType(Icon),
      ),
    );
    expect(likeIcon.icon, Icons.favorite_rounded);
    expect(likeIcon.color, AppColors.secondary);
    expect(
      find.textContaining(RegExp(r'\d+ (views|listens|odsłuch)')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('"Odpowiedz głosem" opens the recorder in reply mode and a '
      'published reply refreshes the feed', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final service = StubMomentService();
    final discovery = await pumpCards(
      tester,
      size: const Size(390, 844),
      navigatorKey: navigatorKey,
      momentService: service,
    );
    expect(discovery.loadCalls, 1);
    await open(tester, 'm4');
    await tester.tap(find.byKey(const ValueKey('moment-row-reply-voice-m4')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final recorder = find.byType(RecordVoiceMomentScreen);
    expect(recorder, findsOneWidget);
    final screen = tester.widget<RecordVoiceMomentScreen>(recorder);
    expect(screen.replyToMomentId, 'm4');
    expect(screen.replyToAuthorName, 'Bartek');
    expect(identical(screen.momentService, service), isTrue);

    navigatorKey.currentState!.pop(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Voice reply published.'), findsOneWidget);
    expect(discovery.loadCalls, 2, reason: 'a published reply refreshes');
    expect(find.byType(RecordVoiceMomentScreen), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });
}
