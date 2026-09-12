import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_viewer.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';

import 'moments_overview_test_support.dart';
import 'voice_moment_test_doubles.dart';

/// The 06 Voice card: one caption block, the format badge from 600, the
/// 48/32/88 transport row, the action row's wrap rules, hover, the liked
/// heart role, no view counts, and "Odpowiedz głosem" into the recorder.
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

  testWidgets('transport row: 48 disc, 32 waveform under a transparent seek '
      'slider, 88 reserved for the time', (tester) async {
    await pumpCards(tester, size: const Size(768, 1024));
    final play = find.byKey(const ValueKey('moment-row-play-m4'));
    expect(tester.getSize(play), const Size(48, 48));
    final wave = find.descendant(
      of: find.byKey(const ValueKey('moment-row-m4')),
      matching: find.byType(StoryWaveform),
    );
    expect(wave, findsOneWidget);
    expect(tester.getSize(wave).height, 32);
    final waveform = tester.widget<StoryWaveform>(wave);
    expect(waveform.barWidth, 3);
    expect(waveform.barGap, 3);
    expect(waveform.playedGradient, isNotNull);
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('moment-row-progress-m4')),
    );
    expect(slider.max, 12000);
    expect(slider.value, 0);
    expect(slider.onChanged, isNull, reason: 'idle: no seeking');
    final time = find.byKey(const ValueKey('moment-row-time-m4'));
    expect(tester.getSize(time).width, 88);
    expect(tester.widget<Text>(time).data, '0:12');
    // The slider lies over the waveform: same vertical band.
    final sliderRect = tester.getRect(find.byKey(const ValueKey('moment-row-progress-m4')));
    final waveRect = tester.getRect(wave);
    expect(sliderRect.top, lessThanOrEqualTo(waveRect.top));
    expect(sliderRect.bottom, greaterThanOrEqualTo(waveRect.bottom));
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
    Material material() => tester.widget<Material>(
      find.descendant(of: card, matching: find.byType(Material)).first,
    );
    expect(material().color, palette.surface);
    expect(
      (material().shape as RoundedRectangleBorder).side.color,
      palette.border,
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(card));
    await tester.pump();
    expect(
      (material().shape as RoundedRectangleBorder).side.color,
      palette.borderStrong,
    );

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
