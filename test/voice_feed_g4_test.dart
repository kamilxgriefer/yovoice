import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_compact_row.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/features/moments/presentation/widgets/voice_feed_filter_tabs.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/voice/voice_player_row.dart';

import 'moments_overview_test_support.dart';
import 'voice_moment_test_doubles.dart';

/// G4 — the Głos feed as the owner approved it: three trackless text tabs
/// (Recent retired into Discover), refresh by re-tapping the active tab or
/// pulling the list, the compact rows that open into the player (one at a
/// time), the caption fallback omitted, counts drawn bare and spoken as
/// phrases, and the three widths.
void main() {
  late VoidCallback restoreIdentity;

  setUpAll(loadInterFont);
  setUp(() => restoreIdentity = installIdentityStub());
  tearDown(() => restoreIdentity());

  late List<FakePreviewAudioPlayer> players;
  late StaticDiscovery discovery;
  late QuietFeed feed;

  Future<void> pumpFeed(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    List<VoiceMoment>? pool,
    Set<String> viewed = const <String>{},
    MomentsFilter initialFilter = MomentsFilter.discover,
    Locale locale = const Locale('en'),
    double textScale = 1,
    bool highContrast = false,
    bool light = false,
    bool rtl = false,
  }) async {
    useSurface(tester, size);
    players = <FakePreviewAudioPlayer>[];
    final auth = authAs();
    discovery = StaticDiscovery(pool ?? populatedPool());
    feed = QuietFeed(firestore: fakeFirestore(), auth: auth);
    Widget child = Scaffold(
      body: MomentsFeedView(
        auth: auth,
        onRecord: () {},
        onCreate: () {},
        initialFilter: initialFilter,
        discoveryService: discovery,
        feedService: feed,
        viewsService: StaticViews(viewed),
        momentService: StubMomentService(),
        playerFactory: () {
          final player = FakePreviewAudioPlayer(
            duration: const Duration(seconds: 12),
          );
          players.add(player);
          return player;
        },
      ),
    );
    if (highContrast) {
      final plain = child;
      child = Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(highContrast: true),
          child: plain,
        ),
      );
    }
    await tester.pumpWidget(
      overviewHost(
        child,
        size: size,
        locale: locale,
        textScale: textScale,
        light: light,
        rtl: rtl,
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

  Finder row(String id) => find.byKey(ValueKey('moment-row-$id'));
  Finder tab(String name) => find.byKey(ValueKey('moments-filter-$name'));

  // The line's own span (each counter is one placeholder inside it).
  InlineSpan metaSpan(WidgetTester tester, String id) =>
      momentMetaLine(tester, id).textSpan!;

  /// What the feed announces, as the platform would receive it.
  List<String> captureAnnouncements(WidgetTester tester) {
    final spoken = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (message) async {
        if (message is Map && message['type'] == 'announce') {
          final data = message['data'];
          if (data is Map) spoken.add('${data['message']}');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
            SystemChannels.accessibility,
            null,
          ),
    );
    return spoken;
  }

  bool expanded(WidgetTester tester, String id) =>
      find.byKey(ValueKey('moment-row-progress-$id')).evaluate().isNotEmpty;

  double tintAlpha(WidgetTester tester, String id) {
    final box = tester.widget<DecoratedBox>(
      find.byKey(ValueKey('moment-row-lit-$id')),
    );
    final gradient =
        (box.decoration as BoxDecoration).gradient! as LinearGradient;
    return gradient.colors.first.a;
  }

  group('the three text tabs', () {
    testWidgets('Odkrywaj · Obserwowani · Popularne, no Najnowsze; the active '
        'tab is textPrimary w700 15 px over a 2 px underline the width of '
        'its label', (tester) async {
      await pumpFeed(tester, locale: const Locale('pl'));
      final tabs = find.byType(VoiceFeedFilterTab);
      expect(tabs, findsNWidgets(3));
      expect(find.text('Odkrywaj'), findsOneWidget);
      expect(find.text('Obserwowani'), findsOneWidget);
      expect(find.text('Popularne'), findsOneWidget);
      expect(find.text('Najnowsze'), findsNothing);
      expect(find.text('Najbardziej angażujące'), findsNothing);
      expect(tab('recent'), findsNothing);
      // The 40 px refresh circle left row 2.
      expect(
        find.byKey(const ValueKey('moments-discovery-refresh')),
        findsNothing,
      );

      final palette = AppPalette.of(tester.element(tab('discover')));
      Text label(String name) => tester.widget<Text>(
        find.descendant(of: tab(name), matching: find.byType(Text)),
      );
      expect(label('discover').style!.color, palette.textPrimary);
      expect(label('discover').style!.fontWeight, FontWeight.w700);
      expect(label('discover').style!.fontSize, 15);
      expect(label('following').style!.color, palette.textTertiary);
      expect(label('following').style!.fontWeight, FontWeight.w600);

      Finder underline(String name) => find.descendant(
        of: tab(name),
        matching: find.byKey(VoiceFeedFilterTab.underlineKey),
      );
      final line = tester.getRect(underline('discover'));
      final text = tester.getRect(
        find.descendant(of: tab('discover'), matching: find.byType(Text)),
      );
      expect(line.height, 2);
      expect(line.width, closeTo(text.width, 0.5));
      expect(line.top, greaterThan(text.bottom));
      Color lineColor(String name) =>
          (tester.widget<AnimatedContainer>(underline(name)).decoration!
                  as BoxDecoration)
              .color!;
      expect(lineColor('discover'), palette.textPrimary);
      expect(lineColor('following'), Colors.transparent);
      for (final name in const ['discover', 'following', 'mostEngaged']) {
        expect(tester.getSize(tab(name)).height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('each tab is one focusable button with its selected state, '
        'inside the named filter group; the active one says it reloads', (
      tester,
    ) async {
      await pumpFeed(tester);
      final semantics = tester.ensureSemantics();
      try {
        final discover = tester
            .getSemantics(tab('discover'))
            .getSemanticsData();
        expect(discover.label, 'Discover');
        expect(discover.flagsCollection.isButton, isTrue);
        expect(discover.flagsCollection.isSelected, Tristate.isTrue);
        expect(discover.flagsCollection.isFocused, isNot(Tristate.none));
        expect(discover.hasAction(SemanticsAction.tap), isTrue);
        expect(discover.hint, 'Reload Moments');
        final popular = tester
            .getSemantics(tab('mostEngaged'))
            .getSemanticsData();
        expect(popular.label, 'Popular');
        expect(popular.flagsCollection.isSelected, Tristate.isFalse);
        expect(popular.hint, isEmpty);
        expect(find.bySemanticsLabel('Voice Moment filters'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('Popularne keeps the engagement order; a tab switch changes '
        'the list', (tester) async {
      await pumpFeed(tester, size: const Size(390, 2400));
      double top(String id) => tester.getTopLeft(row(id)).dy;
      // Discover: newest first — m4 (40 min) above m5 (1 h) above m1 (2 h).
      expect(top('m4'), lessThan(top('m5')));
      expect(top('m5'), lessThan(top('m1')));
      await tester.tap(tab('mostEngaged'));
      await tester.pump();
      // Most engaged first: m3 (58 likes, 9 comments) leads.
      expect(top('m3'), lessThan(top('m1')));
      expect(top('m1'), lessThan(top('m4')));
    });

    testWidgets('a request for Recent lands on Discover (legacy seams and '
        'saved state)', (tester) async {
      expect(momentsShownFilter(MomentsFilter.recent), MomentsFilter.discover);
      expect(
        momentsShownFilter(MomentsFilter.following),
        MomentsFilter.following,
      );
      expect(momentsVisibleFilters, isNot(contains(MomentsFilter.recent)));
      await pumpFeed(tester, initialFilter: MomentsFilter.recent);
      final semantics = tester.ensureSemantics();
      try {
        expect(
          tester
              .getSemantics(tab('discover'))
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
      } finally {
        semantics.dispose();
      }
      expect(row('m4'), findsOneWidget);
    });

    testWidgets('re-tapping the active tab scrolls the list to the top, shows '
        'the spinner, announces, and reloads ONCE however often it is '
        'tapped; tapping another tab does not reload', (tester) async {
      await pumpFeed(tester, size: const Size(390, 640));
      final announcements = captureAnnouncements(tester);
      expect(discovery.loadCalls, 1);
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('moments-feed-scroll')),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(200);
      await tester.pump();
      expect(position.pixels, 200);

      await tester.tap(tab('discover'));
      await tester.pump();
      expect(position.pixels, 0, reason: 'Reduce Motion: a jump to the top');
      expect(announcements, <String>['Reloading Moments…']);
      // A second tap while the spinner snaps in is the same request.
      await tester.tap(tab('discover'));
      await tester.pump();
      // Visible progress: the pull-to-refresh spinner, which starts the
      // read once it has snapped in.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);
      expect(discovery.loadCalls, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(discovery.loadCalls, 2, reason: 'two taps, one read');
      expect(announcements, hasLength(1));
      expect(row('m4'), findsOneWidget, reason: 'the content stays up');
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(RefreshProgressIndicator), findsNothing);

      await tester.tap(tab('following'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(discovery.loadCalls, 2);
    });

    testWidgets('pulling the list down refreshes it (palette colours)', (
      tester,
    ) async {
      await pumpFeed(tester);
      expect(discovery.loadCalls, 1);
      final indicator = tester.widget<RefreshIndicator>(
        find.descendant(
          of: find.byKey(const ValueKey('moments-feed-refresh')),
          matching: find.byType(RefreshIndicator),
        ),
      );
      final palette = AppPalette.of(tester.element(row('m4')));
      expect(indicator.color, palette.interactiveForeground);
      expect(indicator.backgroundColor, palette.surfaceRaised);
      await tester.fling(row('m4'), const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(discovery.loadCalls, 2);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the active tab is the focus-recovery target and draws a '
        'visible ring when focused', (tester) async {
      await pumpFeed(tester);
      final inkWell = find.descendant(
        of: tab('discover'),
        matching: find.byType(InkWell),
      );
      final node = tester.widget<InkWell>(inkWell).focusNode;
      expect(node, isNotNull, reason: 'the shared recovery node');
      expect(
        tester
            .widget<InkWell>(
              find.descendant(
                of: tab('following'),
                matching: find.byType(InkWell),
              ),
            )
            .focusNode,
        isNull,
      );
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      node!.requestFocus();
      await tester.pump();
      await tester.pump();
      final ring = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: tab('discover'),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is DecoratedBox &&
                    w.position == DecorationPosition.foreground,
              ),
            )
            .first,
      );
      final palette = AppPalette.of(tester.element(tab('discover')));
      expect(
        ((ring.decoration as BoxDecoration).border! as Border).top.color,
        palette.focus,
      );
    });
  });

  group('the compact row, collapsed', () {
    testWidgets('min 76, a 44 avatar with no ring, name 15 w700, the real '
        'age, the unheard dot, one caption line, the meta line and a 44 '
        'outline play button — no card, a hairline under it', (tester) async {
      await pumpFeed(tester, viewed: const {'m5'});
      final palette = AppPalette.of(tester.element(row('m4')));
      // m1: a captioned row; m4: no caption.
      await tester.ensureVisible(row('m1'));
      await tester.pump();
      expect(tester.getSize(row('m1')).height, greaterThanOrEqualTo(76));
      expect(tester.getSize(row('m4')).height, 76);
      // A 44 px face in its 44 px target, and no ring around it.
      final avatar = find.byKey(const ValueKey('moment-row-chain-m1'));
      expect(tester.getSize(avatar).width, greaterThanOrEqualTo(44));
      final face = find.descendant(
        of: avatar,
        matching: find.byType(UserAvatar),
      );
      expect(tester.getSize(face), const Size.square(44));
      expect(
        find.descendant(of: avatar, matching: find.byType(MomentSeenAvatar)),
        findsNothing,
      );
      final name = tester.widget<Text>(
        find.byKey(const ValueKey('moment-row-name-m1')),
      );
      expect(name.style!.fontSize, 15);
      expect(name.style!.fontWeight, FontWeight.w700);
      expect(name.style!.color, palette.textPrimary);
      final age = tester.widget<Text>(
        find.byKey(const ValueKey('moment-row-age-m1')),
      );
      expect(age.data, '2h ago');
      expect(age.style!.fontSize, 12);
      // On the canvas (below 1100) the 12 px ink is textSecondary: the
      // backdrop photo behind it left textTertiary under 4.5:1.
      expect(age.style!.color, palette.textSecondary);
      final caption = tester.widget<Text>(
        find.byKey(const ValueKey('moment-row-caption-m1')),
      );
      expect(caption.maxLines, 1);
      expect(caption.overflow, TextOverflow.ellipsis);
      expect(caption.style!.fontSize, 14);

      // Unheard → the 8 px secondary dot in a 1.5 px canvas ring (its 3:1
      // against any backdrop pixel); heard (m5) → none.
      final dot = find.byKey(const ValueKey('moment-row-unheard-m1'));
      expect(tester.getSize(dot), const Size.square(8));
      final dotFill =
          tester.widget<Container>(dot).decoration! as BoxDecoration;
      expect(dotFill.color, AppColors.secondary);
      expect(dotFill.boxShadow, hasLength(1));
      expect(dotFill.boxShadow!.single.color, palette.background);
      expect(dotFill.boxShadow!.single.spreadRadius, 1.5);
      expect(dotFill.boxShadow!.single.blurRadius, 0);
      expect(find.byKey(const ValueKey('moment-row-unheard-m5')), findsNothing);

      // The play button: a 44 outline disc in borderStrong (in its 48 px
      // target), the textPrimary glyph, no gradient until the row opens.
      final play = find.byKey(const ValueKey('moment-row-play-m1'));
      expect(tester.getSize(play), const Size.square(48));
      expect(
        tester.getSize(
          find.descendant(
            of: play,
            matching: find.byKey(MomentRowTransportButton.outlineKey),
          ),
        ),
        const Size.square(44),
      );
      final outline =
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: play,
                      matching: find.byKey(MomentRowTransportButton.outlineKey),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect((outline.border! as Border).top.color, palette.borderStrong);
      expect(outline.gradient, isNull);
      expect(
        find.descendant(of: play, matching: find.byType(YoGradientDisc)),
        findsNothing,
      );
      final glyph = tester.widget<Icon>(
        find.descendant(of: play, matching: find.byType(Icon)),
      );
      expect(glyph.color, palette.textPrimary);

      // No card, no player and no action line while collapsed.
      expect(find.byKey(const ValueKey('moment-row-like-m1')), findsNothing);
      expect(
        find.byKey(const ValueKey('moment-row-reply-voice-m1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('moment-row-progress-m1')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('moment-row-menu-m1')), findsNothing);
      final edge =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: row('m1'),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect((edge.border! as Border).bottom.color, palette.hairline);
      expect(edge.borderRadius, isNull);
      expect(edge.gradient, isNull);
    });

    testWidgets('the age is never cut: whole on line 1 while the name keeps '
        'its width, otherwise it opens the meta line — collapsed and open', (
      tester,
    ) async {
      await pumpFeed(
        tester,
        size: const Size(320, 1400),
        locale: const Locale('pl'),
        pool: <VoiceMoment>[
          overviewMoment(
            'short',
            author: 'bartek',
            authorName: 'Bartek',
            caption: 'Krótko.',
            likes: 3,
            age: const Duration(minutes: 40),
          ),
          overviewMoment(
            'long',
            author: 'aleksandra',
            authorName: 'Aleksandra Wiśniewska-Kowalczyk',
            caption: 'Długie imię.',
            likes: 2,
            age: const Duration(hours: 1),
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      RenderParagraph paragraphOf(Finder text) => tester.renderObject(
        find.descendant(of: text, matching: find.byType(RichText)),
      );

      // A short name at 320: the age stays on line 1, drawn whole.
      final shortAge = find.byKey(const ValueKey('moment-row-age-short'));
      expect(shortAge, findsOneWidget);
      expect(paragraphOf(shortAge).didExceedMaxLines, isFalse);
      expect(
        tester.getSize(shortAge).width,
        greaterThanOrEqualTo(paragraphOf(shortAge).getMaxIntrinsicWidth(1e6)),
      );
      expect(
        tester.getRect(shortAge).center.dy,
        closeTo(
          tester
              .getRect(find.byKey(const ValueKey('moment-row-name-short')))
              .center
              .dy,
          3,
        ),
      );
      expect(metaSpan(tester, 'short').toPlainText(), startsWith('0:45'));

      // A long name: the age leaves line 1 whole and opens the meta line;
      // the name keeps the line to itself.
      expect(find.byKey(const ValueKey('moment-row-age-long')), findsNothing);
      expect(
        metaSpan(tester, 'long').toPlainText(),
        startsWith('1 godz. temu · 0:45'),
      );

      // Open, it still opens the (availability) line under the name, whole.
      await tapPlay(tester, 'long');
      expect(expanded(tester, 'long'), isTrue);
      expect(find.byKey(const ValueKey('moment-row-age-long')), findsNothing);
      expect(
        metaSpan(tester, 'long').toPlainText(),
        startsWith('1 godz. temu · wygasa za'),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('moment-row-meta-long'))).top,
        greaterThanOrEqualTo(
          tester
                  .getRect(find.byKey(const ValueKey('moment-row-name-long')))
                  .bottom -
              1,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the meta line: duration · ♡ likes · 💬 comments · the '
        'expiry copy mid-sentence; zeros are not printed; spoken as '
        'phrases', (tester) async {
      await pumpFeed(tester, locale: const Locale('pl'));
      // As drawn: each counter unit written back as "￼ <number>".
      String meta(String id) => momentMetaVisible(tester, id);
      // m1: 45 s, 24 likes, 6 comments, 24 h window, 2 h old.
      expect(
        meta('m1'),
        matches(RegExp(r'^0:45 · ￼ 24 · ￼ 6 · wygasa za 21 godz\.$')),
      );
      // m4: 12 s, 3 likes, no comments.
      expect(
        meta('m4'),
        matches(RegExp(r'^0:12 · ￼ 3 · wygasa za 23 godz\.$')),
      );
      // Spoken as phrases, on the row's ONE node, after its name.
      final semantics = tester.ensureSemantics();
      try {
        final m1 = tester.getSemantics(row('m1')).getSemanticsData().label;
        expect(m1, startsWith('Otwórz Voice Moment: '));
        expect(
          m1,
          endsWith('\n0:45, Polubienia: 24, Komentarze: 6, Wygasa za 21 godz.'),
        );
        expect(
          tester.getSemantics(row('m4')).getSemanticsData().label,
          endsWith('\n0:12, Polubienia: 3, Wygasa za 23 godz.'),
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('the last hour turns the expiry amber; the author sees '
        '"Dostępny do usunięcia" on a permanent Moment', (tester) async {
      final now = DateTime.now();
      final urgent = VoiceMoment(
        id: 'u1',
        authorId: 'ola',
        authorName: 'Ola',
        authorPhotoUrl: null,
        caption: 'Za chwilę zniknie',
        audioUrl: 'https://cdn.example/u1.m4a',
        durationSeconds: 20,
        likeCount: 0,
        commentCount: 0,
        isPublished: true,
        createdAt: now.subtract(const Duration(hours: 23, minutes: 30)),
        expiresAt: now.add(const Duration(minutes: 30)),
        schemaVersion: 2,
        status: 'published',
        isDeleted: false,
      );
      final mine = overviewMoment(
        'own',
        author: viewerUid,
        authorName: 'Ja',
        permanent: true,
        age: const Duration(minutes: 5),
      );
      await pumpFeed(
        tester,
        locale: const Locale('pl'),
        pool: <VoiceMoment>[urgent, mine],
      );
      final palette = AppPalette.of(tester.element(row('u1')));
      final span = metaSpan(tester, 'u1') as TextSpan;
      final expiry = span.children!.last as TextSpan;
      expect(expiry.text, matches(RegExp(r'^wygasa za (29|30) min$')));
      expect(expiry.style!.color, palette.warningForeground);
      final own = metaSpan(tester, 'own').toPlainText();
      expect(own, endsWith('dostępny do usunięcia'));
      // No unheard dot on your own Moment.
      expect(
        find.byKey(const ValueKey('moment-row-unheard-own')),
        findsNothing,
      );
    });

    testWidgets('an empty caption and the "Voice Moment" fallback publishing '
        'writes both omit the caption line — the row still names the '
        'format to a screen reader, never "Voice Moment: Voice Moment"', (
      tester,
    ) async {
      final pool = <VoiceMoment>[
        overviewMoment('blank', author: 'a', authorName: 'Ala', caption: ''),
        overviewMoment(
          'fallback',
          author: 'b',
          authorName: 'Basia',
          caption: 'Voice Moment',
          age: const Duration(hours: 3),
        ),
        overviewMoment(
          'real',
          author: 'c',
          authorName: 'Cezary',
          caption: 'Prawdziwy opis',
          age: const Duration(hours: 4),
        ),
      ];
      expect(momentCaptionIsFallback(''), isTrue);
      expect(momentCaptionIsFallback('  Voice Moment '), isTrue);
      expect(momentCaptionIsFallback('Voice Moments'), isFalse);
      await pumpFeed(tester, pool: pool);
      expect(
        find.byKey(const ValueKey('moment-row-caption-blank')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('moment-row-caption-fallback')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: row('fallback'),
          matching: find.text('Voice Moment'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('moment-row-caption-real')),
        findsOneWidget,
      );
      expect(tester.getSize(row('fallback')).height, 76);
      final semantics = tester.ensureSemantics();
      try {
        final fallback = tester
            .getSemantics(row('fallback'))
            .getSemanticsData()
            .label;
        expect(fallback, startsWith('Open Voice Moment by Basia, 3h ago'));
        expect(fallback, isNot(contains('Voice Moment: Voice Moment')));
        expect(
          tester.getSemantics(row('real')).getSemanticsData().label,
          startsWith('Open Voice Moment: Prawdziwy opis, Cezary, 4h ago'),
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('the row is a named button the bridge can press, with like, '
        'reply and more as custom actions', (tester) async {
      await pumpFeed(tester);
      final semantics = tester.ensureSemantics();
      try {
        final node = tester.getSemantics(row('m4'));
        final data = node.getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        // m4 has no caption and has not been heard: "…, new".
        expect(
          data.label,
          startsWith('Open Voice Moment by Bartek, 40m ago, new'),
        );
        expect(data.hasAction(SemanticsAction.customAction), isTrue);
        final labels = <String>[
          for (final id in data.customSemanticsActionIds!)
            CustomSemanticsAction.getAction(id)!.label!,
        ];
        // "See who liked" (ADR-230) joins them because m4 has likes; the
        // meta line's count stays a span of this one label.
        expect(
          labels,
          unorderedEquals(<String>[
            'Like this Moment',
            'Reply with voice',
            'See who liked',
            'More options',
          ]),
        );

        // "Like" through the bridge writes the real like.
        final likeId = data.customSemanticsActionIds!.firstWhere(
          (id) =>
              CustomSemanticsAction.getAction(id)!.label == 'Like this Moment',
        );
        node.owner!.performAction(
          node.id,
          SemanticsAction.customAction,
          likeId,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(feed.likeWrites, ['m4:true']);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('a long press opens the ⋯ menu: View profile, Details and '
        'Report on somebody else\'s Moment', (tester) async {
      await pumpFeed(tester);
      await tester.longPress(row('m4'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('moment-row-profile-m4')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('moment-row-details-m4')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('moment-row-report-m4')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('moment-row-delete-m4')), findsNothing);
    });
  });

  group('the compact row, open', () {
    testWidgets('playing opens the row: the full caption (3 lines), the lit '
        'bead, the waveform with its seek slider and the clock, and the '
        'action line; the row wears the one tint', (tester) async {
      await pumpFeed(tester, size: const Size(390, 1400));
      final palette = AppPalette.of(tester.element(row('m1')));
      expect(tintAlpha(tester, 'm1'), 0);
      await tapPlay(tester, 'm1');
      expect(expanded(tester, 'm1'), isTrue);
      final caption = tester.widget<Text>(
        find.byKey(const ValueKey('moment-row-caption-m1')),
      );
      expect(caption.maxLines, 3);
      expect(caption.style!.color, palette.textPrimary);
      final bead = tester.widget<YoGradientDisc>(
        find.descendant(
          of: find.byKey(const ValueKey('moment-row-play-m1')),
          matching: find.byType(YoGradientDisc),
        ),
      );
      expect(bead.emphasis, YoDiscEmphasis.lit);
      expect(bead.size, 44);
      expect(
        tester.getSize(find.byKey(const ValueKey('moment-row-play-m1'))),
        const Size.square(48),
        reason: 'the 44 bead keeps the 48 px target',
      );
      final wave = tester.widget<VoicePourWaveform>(
        find.byKey(const ValueKey('moment-row-wave-m1')),
      );
      expect(wave.height, 26);
      expect(
        tester.getSize(find.byKey(const ValueKey('moment-row-wave-m1'))).width,
        greaterThan(250),
        reason: 'the waveform runs the row\'s full width beside the clock',
      );
      players.last.emitPosition(const Duration(seconds: 5));
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('moment-row-time-m1')))
            .data,
        '0:05 / 0:12',
      );
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('moment-row-progress-m1')),
      );
      expect(slider.onChanged, isNotNull);
      for (final key in const [
        'moment-row-like-m1',
        'moment-row-comments-m1',
        'moment-row-reply-voice-m1',
        'moment-row-share-m1',
        'moment-row-menu-m1',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      final reply = tester.widget<TextButton>(
        find.byKey(const ValueKey('moment-row-reply-voice-m1')),
      );
      expect(
        reply.style!.foregroundColor!.resolve(<WidgetState>{}),
        palette.interactiveForeground,
      );
      expect(tintAlpha(tester, 'm1'), closeTo(palette.tintAlpha, .001));
      // Open, the meta line keeps only the availability: the length and
      // the counters are the player's and the action line's now, but the
      // expiry never disappears as the row opens.
      expect(metaSpan(tester, 'm1').toPlainText(), 'Expires in 21h');
      expect(
        find.byKey(const ValueKey('moment-row-meta-likes-m1')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('only one row is open at a time; pausing keeps it open but '
        'drops the light', (tester) async {
      await pumpFeed(tester, size: const Size(390, 1400));
      await tapPlay(tester, 'm4');
      expect(expanded(tester, 'm4'), isTrue);
      await tapPlay(tester, 'm5');
      expect(expanded(tester, 'm5'), isTrue);
      expect(expanded(tester, 'm4'), isFalse);
      expect(tintAlpha(tester, 'm4'), 0);
      for (final id in const ['m1', 'm2', 'm3', 'm6']) {
        expect(expanded(tester, id), isFalse, reason: id);
      }

      // Pause: still the current clip (open), no longer lit.
      await tapPlay(tester, 'm5');
      expect(expanded(tester, 'm5'), isTrue);
      expect(tintAlpha(tester, 'm5'), 0);
      final bead = tester.widget<YoGradientDisc>(
        find.descendant(
          of: find.byKey(const ValueKey('moment-row-play-m5')),
          matching: find.byType(YoGradientDisc),
        ),
      );
      expect(bead.emphasis, YoDiscEmphasis.rest);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a popup menu is not a new screen: the open row\'s ⋯ opens '
        'over the playing row, which stays open and lit; Escape hands focus '
        'back to ⋯; nothing reloads; the entries still answer', (tester) async {
      useSurface(tester, const Size(390, 1400));
      final auth = authAs();
      final opened = <String>[];
      final discovery = StaticDiscovery(populatedPool());
      await tester.pumpWidget(
        overviewHost(
          Scaffold(
            body: MomentsFeedView(
              auth: auth,
              onRecord: () {},
              discoveryService: discovery,
              feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
              viewsService: StaticViews(const <String>{}),
              momentService: StubMomentService(),
              playerFactory: () => FakePreviewAudioPlayer(),
              onOpenDetail: (moment) => opened.add(moment.id),
            ),
          ),
          size: const Size(390, 1400),
        ),
      );
      await settleOverview(tester);
      expect(discovery.loadCalls, 1);
      await tapPlay(tester, 'm4');
      expect(tintAlpha(tester, 'm4'), greaterThan(0), reason: 'playing');

      // By keyboard: focus ⋯, open it with Enter.
      final more = find.byKey(const ValueKey('moment-row-menu-m4'));
      final moreFocus = Focus.of(
        tester.element(find.descendant(of: more, matching: find.byType(Icon))),
      );
      moreFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('moment-row-profile-m4')),
        findsOneWidget,
      );
      // The row the menu belongs to is still the open, playing one.
      expect(expanded(tester, 'm4'), isTrue, reason: 'the row stays open');
      expect(tintAlpha(tester, 'm4'), greaterThan(0), reason: 'still lit');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(expanded(tester, 'm4'), isTrue);
      expect(moreFocus.hasPrimaryFocus, isTrue, reason: 'focus back on ⋯');
      expect(discovery.loadCalls, 1, reason: 'a closed menu reloads nothing');

      // And an entry still answers, from the same menu.
      await tester.tap(more);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('moment-row-details-m4')));
      await tester.pumpAndSettle();
      expect(opened, ['m4']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a tap on an inert control of the open row (a like in '
        'flight) is absorbed — it never opens the sheet over the clip', (
      tester,
    ) async {
      await pumpFeed(tester, size: const Size(390, 1400));
      final gate = Completer<void>();
      feed.likeGate = gate;
      await tapPlay(tester, 'm4');
      final like = find.byKey(const ValueKey('moment-row-like-m4'));
      await tester.tap(like);
      await tester.pump();
      expect(tester.widget<TextButton>(like).onPressed, isNull);
      await tester.tap(like, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(expanded(tester, 'm4'), isTrue, reason: 'still playing');
      expect(find.byType(BottomSheet), findsNothing);
      gate.complete();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('keyboard focus stays on the play button as its row opens', (
      tester,
    ) async {
      await pumpFeed(tester);
      final play = find.byKey(const ValueKey('moment-row-play-m4'));
      final focus = Focus.of(
        tester.element(find.descendant(of: play, matching: find.byType(Icon))),
      );
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(expanded(tester, 'm4'), isTrue);
      expect(focus.hasFocus, isTrue, reason: 'the same button, a new face');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the action line draws bare numbers and speaks phrases; the '
        'like is an action with its count and a toggle; the liked heart '
        'wears the secondary role; ⋯ is "More options"', (tester) async {
      await pumpFeed(tester, size: const Size(390, 1400));
      await tapPlay(tester, 'm6');
      final like = find.byKey(const ValueKey('moment-row-like-m6'));
      expect(
        find.descendant(of: like, matching: find.text('2')),
        findsOneWidget,
      );
      final heart = tester.widget<Icon>(
        find.descendant(of: like, matching: find.byType(Icon)),
      );
      expect(heart.icon, Icons.favorite_rounded);
      expect(heart.color, AppColors.secondary);
      final semantics = tester.ensureSemantics();
      try {
        final likeNode = tester.getSemantics(like).getSemanticsData();
        expect(likeNode.label, 'Like, Likes: 2');
        expect(likeNode.flagsCollection.isButton, isTrue);
        expect(likeNode.flagsCollection.isToggled, Tristate.isTrue);
        final comments = tester
            .getSemantics(find.byKey(const ValueKey('moment-row-comments-m6')))
            .getSemanticsData();
        expect(comments.label, 'Comments');
        final more = tester
            .getSemantics(find.byKey(const ValueKey('moment-row-menu-m6')))
            .getSemanticsData();
        expect(more.tooltip, 'More options');
        // Not liked yet: the same action, toggled off.
        await tapPlay(tester, 'm1');
        final plain = tester
            .getSemantics(find.byKey(const ValueKey('moment-row-like-m1')))
            .getSemanticsData();
        expect(plain.label, 'Like, Likes: 24');
        expect(plain.flagsCollection.isToggled, Tristate.isFalse);
      } finally {
        semantics.dispose();
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed play keeps today\'s copy and its retry', (
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
              discoveryService: StaticDiscovery(populatedPool()),
              feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
              viewsService: StaticViews(const <String>{}),
              momentService: StubMomentService(),
              playerFactory: () =>
                  FakePreviewAudioPlayer()..playError = StateError('refused'),
            ),
          ),
          size: const Size(390, 844),
        ),
      );
      await settleOverview(tester);
      await tapPlay(tester, 'm4');
      expect(expanded(tester, 'm4'), isTrue);
      expect(
        find.text('This Moment could not be played. Try again.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('moment-row-play-retry-m4')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('text size, contrast and direction', () {
    for (final width in const <double>[320, 390]) {
      testWidgets('200 % text at $width: collapsed and open rows, the tabs and '
          'the circles lay out without overflow', (tester) async {
        await pumpFeed(
          tester,
          size: Size(width, 2400),
          textScale: 2,
          locale: const Locale('pl'),
        );
        expect(tester.takeException(), isNull);
        // The name keeps line 1; the age opens the meta line.
        final meta = metaSpan(tester, 'm4').toPlainText();
        expect(meta, startsWith('40 min temu · 0:12'));
        // The heart grows with the words beside it exactly once: 11 px
        // scaled to 22, never scaled again by the span (44).
        final heart = find.descendant(
          of: find.byKey(const ValueKey('moment-row-meta-m4')),
          matching: find.byIcon(Icons.favorite_border_rounded),
        );
        expect(heart, findsOneWidget);
        expect(tester.getRect(heart).height, closeTo(22, .5));
        await tapPlay(tester, 'm1');
        expect(expanded(tester, 'm1'), isTrue);
        expect(tester.takeException(), isNull);
        // The reply keeps its words whole on a line of its own.
        final reply = tester.getRect(
          find.byKey(const ValueKey('moment-row-reply-voice-m1')),
        );
        final like = tester.getRect(
          find.byKey(const ValueKey('moment-row-like-m1')),
        );
        expect(reply.top, greaterThanOrEqualTo(like.bottom - 1));
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('a wrapping meta line never parts a glyph from its count '
        '(1440, Pearl, 200 %: the line wraps around "💬 6")', (tester) async {
      await pumpFeed(
        tester,
        size: const Size(1440, 1800),
        textScale: 2,
        light: true,
        locale: const Locale('pl'),
      );
      expect(tester.takeException(), isNull);
      var wrapped = 0;
      var counters = 0;
      for (final id in const ['m1', 'm2', 'm3', 'm5']) {
        // The first RichText is the line itself; the counters' own follow.
        final paragraph = tester.renderObject<RenderParagraph>(
          find
              .descendant(
                of: find.byKey(ValueKey('moment-row-meta-$id')),
                matching: find.byType(RichText),
              )
              .first,
        );
        final lineHeight = paragraph.getFullHeightForCaret(
          const TextPosition(offset: 0),
        );
        if (paragraph.size.height > lineHeight * 1.5) wrapped += 1;
        final plain = metaSpan(tester, id).toPlainText();
        // No number is text of the line that a wrap could strand: each is
        // inside its glyph's unit.
        expect(plain, isNot(matches(RegExp('\uFFFC\\s*\\d'))), reason: id);
        final placeholders = RegExp('\uFFFC').allMatches(plain).toList();
        var index = 0;
        for (final kind in const ['likes', 'comments']) {
          final unit = find.byKey(ValueKey('moment-row-meta-$kind-$id'));
          if (unit.evaluate().isEmpty) continue;
          counters += 1;
          final icon = tester.getRect(
            find.descendant(of: unit, matching: find.byType(Icon)),
          );
          final number = tester.getRect(
            find.descendant(of: unit, matching: find.byType(Text)),
          );
          // The glyph and its number share one line…
          expect((icon.center.dy - number.center.dy).abs(), lessThan(1.5));
          expect(number.left, greaterThan(icon.right));
          // …and the number sits in the line's own box, beside the words
          // (the "·" after the unit): scaled once, on the same baseline.
          expect(number.height, closeTo(lineHeight, 1), reason: '$id $kind');
          final dot = placeholders[index].start + 2;
          final box = paragraph
              .getBoxesForSelection(
                TextSelection(baseOffset: dot, extentOffset: dot + 1),
              )
              .first
              .toRect();
          final dotCentre = paragraph.localToGlobal(box.center);
          expect(
            (dotCentre.dy - number.center.dy).abs(),
            lessThan(1.5),
            reason:
                '$id $kind: "${plain.substring(placeholders[index].start)}"',
          );
          index += 1;
        }
      }
      expect(counters, greaterThan(4));
      // The case is real: at this size the meta lines do wrap.
      expect(wrapped, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('high contrast: no tint on the playing row, borderStrong '
        'dividers, a primary unheard dot', (tester) async {
      await pumpFeed(tester, highContrast: true, size: const Size(390, 1400));
      final context = tester.element(row('m4'));
      final palette = AppPalette.of(context);
      expect(find.byKey(const ValueKey('moment-row-lit-m4')), findsNothing);
      await tapPlay(tester, 'm4');
      expect(expanded(tester, 'm4'), isTrue);
      expect(find.byKey(const ValueKey('moment-row-lit-m4')), findsNothing);
      final edge =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: row('m5'),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect((edge.border! as Border).bottom.color, palette.borderStrong);
      expect(
        (tester
                    .widget<Container>(
                      find.byKey(const ValueKey('moment-row-unheard-m5')),
                    )
                    .decoration!
                as BoxDecoration)
            .color,
        Theme.of(context).colorScheme.primary,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('right to left: the avatar leads from the right and the play '
        'button closes on the left', (tester) async {
      await pumpFeed(tester, rtl: true);
      final avatar = tester.getRect(
        find.byKey(const ValueKey('moment-row-chain-m4')),
      );
      final play = tester.getRect(
        find.byKey(const ValueKey('moment-row-play-m4')),
      );
      expect(avatar.right, closeTo(390 - 16, 0.5));
      // The 44 disc sits centred in its 48 target, 2 px in from the gutter.
      expect(play.left, closeTo(16, 0.5));
      expect(tester.takeException(), isNull);
    });
  });

  group('the three widths', () {
    testWidgets('below 600: the chrome tabs over full-bleed rows with a '
        '16 px gutter', (tester) async {
      await pumpFeed(tester);
      expect(find.byType(VoiceFeedFilterTabs), findsOneWidget);
      expect(
        find.byKey(const ValueKey('yo-moments-local-panel')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('moments-feed-block')), findsNothing);
      final rowRect = tester.getRect(row('m4'));
      expect(rowRect.left, 0);
      expect(rowRect.width, 390);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('moment-row-chain-m4'))).dx,
        16,
      );
    });

    testWidgets('600–1099: one centred column (max 640 + gutters) with the '
        'same rows and the tabs', (tester) async {
      await pumpFeed(tester, size: const Size(768, 1024));
      expect(find.byType(VoiceFeedFilterTabs), findsOneWidget);
      expect(
        find.byKey(const ValueKey('yo-moments-local-panel')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('moments-feed-block')), findsNothing);
      final rowRect = tester.getRect(row('m4'));
      expect(rowRect.width, 640 + 2 * 24);
      expect(rowRect.center.dx, closeTo(384, 0.5));
      expect(tester.getSize(row('m4')).height, 76);
    });

    testWidgets('≥ 1100: the local panel (three filters, Odśwież Momenty, '
        'Utwórz) and the rows inside ONE R2 block', (tester) async {
      await pumpFeed(
        tester,
        size: const Size(1440, 1200),
        locale: const Locale('pl'),
      );
      final panel = find.byKey(const ValueKey('yo-moments-local-panel'));
      expect(panel, findsOneWidget);
      expect(find.byType(VoiceFeedFilterTabs), findsNothing);
      for (final name in const ['discover', 'following', 'mostEngaged']) {
        expect(find.descendant(of: panel, matching: tab(name)), findsOneWidget);
      }
      expect(find.descendant(of: panel, matching: tab('recent')), findsNothing);
      expect(
        find.descendant(of: panel, matching: find.text('Popularne')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('moments-discovery-refresh')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('moments-create-cta')), findsOneWidget);

      final block = tester.widget<DecoratedSliver>(
        find.byKey(const ValueKey('moments-feed-block')),
      );
      final palette = AppPalette.of(tester.element(row('m4')));
      final fill = block.decoration as BoxDecoration;
      expect(fill.borderRadius, const BorderRadius.all(Radius.circular(20)));
      expect(fill.color, palette.surface);
      final edge =
          tester
                  .widget<DecoratedSliver>(
                    find.descendant(
                      of: find.byKey(const ValueKey('moments-feed-block')),
                      matching: find.byType(DecoratedSliver),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(edge.border, AppFinish.blockEdge(palette));
      // Rows are inset 20 inside the block; the last has no divider.
      final rowRect = tester.getRect(row('m4'));
      expect(
        tester
                .getTopLeft(find.byKey(const ValueKey('moment-row-chain-m4')))
                .dx -
            rowRect.left,
        20,
      );
      final lastEdge =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: row('m6'),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(lastEdge.border, isNull);
      // The circles stay on the canvas above the block.
      expect(
        tester
            .getRect(find.byKey(const ValueKey('moments-author-circles')))
            .bottom,
        lessThanOrEqualTo(rowRect.top),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Pearl reads its roles from the palette', (tester) async {
      await pumpFeed(tester, light: true);
      final palette = AppPalette.of(tester.element(row('m4')));
      expect(palette.isDark, isFalse);
      final name = tester.widget<Text>(
        find.byKey(const ValueKey('moment-row-name-m4')),
      );
      expect(name.style!.color, palette.textPrimary);
      final edge =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: row('m4'),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect((edge.border! as Border).bottom.color, palette.hairline);
    });
  });

  test('the retired Recent tab keeps its enum value and code path', () {
    // The value survives for the seams that may still name it.
    expect(MomentsFilter.values, contains(MomentsFilter.recent));
  });
}
