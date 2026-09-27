import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/shared/widgets/waveform/yo_waveform.dart';

import 'moments_overview_test_support.dart';
import 'voice_moment_test_doubles.dart';

/// The 06 Voice card: one caption block, the format badge from 600, the
/// 48 bead / 36 waveform / clock-under-the-wave transport, the action row's
/// wrap rules, hover, the liked heart role, no view counts, and "Odpowiedz
/// głosem" into the recorder.
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
            momentService: momentService,
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

  testWidgets('the caption is one block, three lines at most, and an empty '
      'caption falls back to the format name', (tester) async {
    await pumpCards(tester, size: const Size(390, 844));
    final empty = find.byKey(const ValueKey('moment-row-m4'));
    expect(
      find.descendant(of: empty, matching: find.text('Voice Moment')),
      findsOneWidget,
    );
    await reveal(tester, 'm3');
    final long = find.byKey(const ValueKey('moment-row-m3'));
    final caption = tester.widget<Text>(
      find.descendant(
        of: find.descendant(
          of: long,
          matching: find.byKey(const ValueKey('moment-row-title-m3')),
        ),
        matching: find.byType(Text),
      ),
    );
    expect(caption.maxLines, 3);
    expect(caption.overflow, TextOverflow.ellipsis);
    // No second "title" line is ever invented: the card holds exactly one
    // caption text under its title region.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('moment-row-title-m3')),
        matching: find.byType(Text),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the VOICE MOMENT badge appears from 600 only and reads as the '
      'format name', (tester) async {
    await pumpCards(tester, size: const Size(599, 900));
    expect(find.byKey(const ValueKey('moment-row-badge-m4')), findsNothing);

    await pumpCards(tester, size: const Size(600, 900));
    final badge = find.byKey(const ValueKey('moment-row-badge-m4'));
    expect(badge, findsOneWidget);
    expect(
      find.descendant(of: badge, matching: find.text('VOICE MOMENT')),
      findsOneWidget,
    );
    expect(tester.getSize(badge).height, 28);
    final semantics = tester.ensureSemantics();
    try {
      expect(tester.getSemantics(badge).getSemanticsData().label, 'Voice Moment');
    } finally {
      semantics.dispose();
    }
  });

  // Refine-look §8.4 / R13: the 48 bead keeps its size; the waveform is
  // 36 high with 3 px bars and 2 px gaps in the palette's unplayed ink, the
  // played sweep spread across the whole run; the clock moved UNDER the
  // wave, end-aligned, so the 88 px reserved box is gone.
  testWidgets('transport row: 48 bead, 36 waveform under a transparent seek '
      'slider, the time under the wave at its end', (tester) async {
    await pumpCards(tester, size: const Size(768, 1024));
    final play = find.byKey(const ValueKey('moment-row-play-m4'));
    expect(tester.getSize(play), const Size(48, 48));
    final card = find.byKey(const ValueKey('moment-row-m4'));
    final palette = AppPalette.of(tester.element(card));
    final wave = find.descendant(of: card, matching: find.byType(YoWaveform));
    expect(wave, findsOneWidget);
    expect(tester.getSize(wave).height, 36);
    final waveform = tester.widget<YoWaveform>(wave);
    expect(waveform.barWidth, 3);
    expect(waveform.barGap, 2);
    expect(waveform.playedGradient, isNotNull);
    expect(waveform.color, palette.waveUnplayed);
    expect(waveform.continuousProgress, isTrue);
    expect(waveform.gradientSpan, YoWaveformGradientSpan.full);
    expect(
      waveform.progress,
      isNull,
      reason: 'a clip that is not playing is a still silhouette',
    );
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('moment-row-progress-m4')),
    );
    expect(slider.max, 12000);
    expect(slider.value, 0);
    expect(slider.onChanged, isNull, reason: 'idle: no seeking');
    final time = find.byKey(const ValueKey('moment-row-time-m4'));
    expect(tester.widget<Text>(time).data, '0:12');
    // The slider lies over the waveform: same vertical band.
    final sliderRect = tester.getRect(
      find.byKey(const ValueKey('moment-row-progress-m4')),
    );
    final waveRect = tester.getRect(wave);
    expect(sliderRect.top, lessThanOrEqualTo(waveRect.top));
    expect(sliderRect.bottom, greaterThanOrEqualTo(waveRect.bottom));
    // The clock sits under the wave, flush with its end.
    final timeRect = tester.getRect(time);
    expect(timeRect.top, greaterThanOrEqualTo(waveRect.bottom));
    expect(timeRect.right, closeTo(sliderRect.right, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('below 360 the reply action gets its own full row; wider, it '
      'stays at the trailing end', (tester) async {
    await pumpCards(tester, size: const Size(320, 800));
    final card = tester.getRect(find.byKey(const ValueKey('moment-row-m4')));
    final reply = tester.getRect(
      find.byKey(const ValueKey('moment-row-reply-voice-m4')),
    );
    final share = tester.getRect(find.byKey(const ValueKey('moment-row-share-m4')));
    expect(reply.right, closeTo(card.right - 16, 1));
    expect(reply.top, closeTo(share.top, 4), reason: 'share + reply share a row');
    expect(reply.width, greaterThan(card.width / 2));
    expect(tester.getSize(find.byKey(const ValueKey('moment-row-share-m4'))).width, 48);
    expect(find.text('Share'), findsNothing, reason: 'icon-only share below 400');

    await pumpCards(tester, size: const Size(1440, 900));
    final wideCard = tester.getRect(find.byKey(const ValueKey('moment-row-m4')));
    final wideReply = tester.getRect(
      find.byKey(const ValueKey('moment-row-reply-voice-m4')),
    );
    final like = tester.getRect(find.byKey(const ValueKey('moment-row-like-m4')));
    final wideShare = tester.getRect(find.byKey(const ValueKey('moment-row-share-m4')));
    expect(wideReply.right, closeTo(wideCard.right - 16, 1));
    // In Inter the English row fits: like, comments, share and the reply
    // share one line.
    expect(wideShare.top, closeTo(like.top, 1));
    expect(wideReply.top, closeTo(like.top, 1), reason: 'one row when it fits');
    expect(find.text('Share'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hover strengthens the hairline; the liked heart wears the '
      'secondary role; no view counts exist', (tester) async {
    await pumpCards(tester, size: const Size(1440, 900));
    final card = find.byKey(const ValueKey('moment-row-m4'));
    final palette = AppPalette.of(tester.element(card));
    // Refine-look R2: the card is a block — the palette's top-lit gradient
    // under a 1 px hairline that becomes `hairlineHover` under a pointer
    // (it was a flat `surface` with `border` → `borderStrong`).
    Color edge() =>
        ((tester
                        .widget<DecoratedBox>(
                          find.byKey(const ValueKey('moment-row-edge-m4')),
                        )
                        .decoration
                    as BoxDecoration)
                .border!
            as Border)
            .top
            .color;
    final fills = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: card, matching: find.byType(DecoratedBox)),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.gradient)
        .whereType<LinearGradient>();
    expect(fills, contains(palette.blockGradient));
    expect(edge(), palette.hairline);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(card));
    await tester.pump();
    expect(edge(), palette.hairlineHover);

    await reveal(tester, 'm6');
    final likeIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('moment-row-like-m6')),
        matching: find.byType(Icon),
      ),
    );
    expect(likeIcon.icon, Icons.favorite_rounded);
    expect(likeIcon.color, AppColors.secondary);
    expect(find.textContaining(RegExp(r'\d+ (views|listens|odsłuch)')), findsNothing);
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
