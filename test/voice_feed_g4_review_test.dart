import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_feed_view.dart';
import 'package:yovoice/features/moments/presentation/widgets/voice_feed_filter_tabs.dart';

import 'moments_overview_test_support.dart';
import 'voice_moment_test_doubles.dart';

/// A Moment service whose media grant can be held open: the play button's
/// loading state, for as long as a test needs it.
class _GatedMoments extends StubMomentService {
  Completer<void>? grant;

  @override
  Future<Uri> resolveMediaUri({
    required String momentId,
    String? commentId,
  }) async {
    final gate = grant;
    if (gate != null) await gate.future;
    return Uri.parse('https://cdn.example/$momentId.m4a');
  }
}

/// The G4 review round: keyboard focus through a loading clip, scroll
/// anchoring when a row opens or closes above what the reader sees, the
/// control strips' long press, the seek's focus ring and one-second steps,
/// the row's one focusable node, canvas contrast, the reloadable empty
/// state, the host's refresh requests, the open row's expiry, and the tab
/// row's edge fade.
void main() {
  late VoidCallback restoreIdentity;

  setUpAll(loadInterFont);
  setUp(() => restoreIdentity = installIdentityStub());
  tearDown(() => restoreIdentity());

  late List<FakePreviewAudioPlayer> players;
  late StaticDiscovery discovery;
  late _GatedMoments moments;

  Future<void> pumpFeed(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    List<VoiceMoment>? pool,
    Set<String> viewed = const <String>{},
    Locale locale = const Locale('en'),
    double textScale = 1,
    Listenable? refreshRequests,
  }) async {
    useSurface(tester, size);
    players = <FakePreviewAudioPlayer>[];
    moments = _GatedMoments();
    final auth = authAs();
    discovery = StaticDiscovery(pool ?? populatedPool());
    await tester.pumpWidget(
      overviewHost(
        Scaffold(
          body: MomentsFeedView(
            auth: auth,
            onRecord: () {},
            discoveryService: discovery,
            feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
            viewsService: StaticViews(viewed),
            momentService: moments,
            refreshRequests: refreshRequests,
            playerFactory: () {
              final player = FakePreviewAudioPlayer(
                duration: const Duration(seconds: 12),
              );
              players.add(player);
              return player;
            },
          ),
        ),
        size: size,
        locale: locale,
        textScale: textScale,
      ),
    );
    await settleOverview(tester);
  }

  Finder row(String id) => find.byKey(ValueKey('moment-row-$id'));
  Finder play(String id) => find.byKey(ValueKey('moment-row-play-$id'));
  bool expanded(String id) =>
      find.byKey(ValueKey('moment-row-progress-$id')).evaluate().isNotEmpty;

  Future<void> tapPlay(WidgetTester tester, String id) async {
    await tester.tap(play(id));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump();
  }

  ScrollPosition feedPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('moments-feed-scroll')),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        ),
      )
      .position;

  FocusNode focusOf(WidgetTester tester, Finder control) => Focus.of(
    tester.element(
      find.descendant(of: control, matching: find.byType(Icon)).first,
    ),
  );

  group('the play button keeps keyboard focus through a loading clip', () {
    testWidgets('focus stays on it while the grant resolves and as it plays; '
        'it says it is loading; the next Tab is the seek', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpFeed(tester, locale: const Locale('pl'));
      moments.grant = Completer<void>();
      final node = focusOf(tester, play('m4'));
      node.requestFocus();
      await tester.pump();
      String spoken() =>
          tester.getSemantics(play('m4')).getSemanticsData().label;
      expect(spoken(), 'Odtwórz, 12 sekund', reason: 'the real length');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(expanded('m4'), isTrue);
      expect(node.hasPrimaryFocus, isTrue, reason: 'busy, still focused');
      expect(spoken(), 'Ładowanie…');
      final busy = tester.widget<IconButton>(play('m4'));
      expect(busy.onPressed, isNotNull, reason: 'never disabled while busy');
      // A press while it loads is ignored, not a second request.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      moments.grant!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(players, hasLength(1));
      expect(players.single.playCalls, 1);
      expect(node.hasPrimaryFocus, isTrue, reason: 'playing, still focused');
      expect(spoken(), 'Pauza');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final seek = find.byKey(const ValueKey('moment-row-progress-m4'));
      final primary = FocusManager.instance.primaryFocus!;
      expect(
        find
            .descendant(
              of: seek,
              matching: find.byWidget(primary.context!.widget),
            )
            .evaluate(),
        isNotEmpty,
        reason: 'the next Tab lands on the seek slider',
      );
      handle.dispose();
    });
  });

  group('the list does not jump when a row opens or closes above the view', () {
    testWidgets('the playing row scrolled away above collapses without '
        'moving the rows in view', (tester) async {
      await pumpFeed(tester, size: const Size(390, 420));
      await tapPlay(tester, 'm4');
      expect(expanded('m4'), isTrue);
      final position = feedPosition(tester);
      final viewportTop = tester
          .getRect(find.byKey(const ValueKey('moments-feed-scroll')))
          .top;
      // Scroll until the open row has left the viewport at the top.
      final target =
          position.pixels + tester.getRect(row('m4')).bottom - viewportTop + 2;
      position.jumpTo(target.clamp(0, position.maxScrollExtent).toDouble());
      await tester.pump();
      final before = tester.getTopLeft(row('m1')).dy;
      await tester.pump();
      await tester.pump();
      expect(expanded('m4'), isFalse, reason: 'out of view: stopped, closed');
      expect(
        tester.getTopLeft(row('m1')).dy,
        closeTo(before, 1),
        reason: 'what the reader sees keeps its place',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('opening a clip below the open row keeps the control just '
        'pressed where it was pressed', (tester) async {
      await pumpFeed(tester, size: const Size(390, 520));
      await tapPlay(tester, 'm4');
      final position = feedPosition(tester);
      // Scroll so the open row sits partly above the viewport: the list
      // has offset to give back.
      position.jumpTo(160);
      await tester.pump();
      expect(expanded('m4'), isTrue);
      final pressed = tester.getCenter(play('m1'));
      await tapPlay(tester, 'm1');
      expect(expanded('m1'), isTrue);
      expect(expanded('m4'), isFalse);
      final after = tester.getCenter(play('m1'));
      expect(after.dy, closeTo(pressed.dy, 1));
      expect(after.dx, closeTo(pressed.dx, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('at the list\'s very top there is no offset to give back: '
        'the pressed control moves by the open row\'s height, no more', (
      tester,
    ) async {
      await pumpFeed(tester, size: const Size(390, 1400));
      await tapPlay(tester, 'm4');
      final openHeight = tester.getSize(row('m4')).height;
      final pressed = tester.getCenter(play('m5')).dy;
      await tapPlay(tester, 'm5');
      final collapsed = tester.getSize(row('m4')).height;
      expect(feedPosition(tester).pixels, 0);
      expect(
        tester.getCenter(play('m5')).dy,
        closeTo(pressed - (openHeight - collapsed), 1),
      );
    });
  });

  group('the open row\'s control strips', () {
    for (final (label, target) in const [
      ('the seek', 'moment-row-progress-m4'),
      ('a like', 'moment-row-like-m4'),
    ]) {
      testWidgets('a long press or a secondary click on $label opens no menu '
          'and keeps playing', (tester) async {
        await pumpFeed(tester);
        await tapPlay(tester, 'm4');
        // Starting the clip stops the player once before it plays.
        final stopsBefore = players.single.stopCalls;
        await tester.longPress(find.byKey(ValueKey(target)));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('moment-row-details-m4')),
          findsNothing,
        );
        expect(expanded('m4'), isTrue);
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.down(tester.getCenter(find.byKey(ValueKey(target))));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('moment-row-details-m4')),
          findsNothing,
        );
        expect(expanded('m4'), isTrue);
        expect(players.single.stopCalls, stopsBefore, reason: 'still playing');
      });
    }

    testWidgets('under a host with no route observer a popup menu still '
        'does not cover the feed: the playing row stays open and lit', (
      tester,
    ) async {
      useSurface(tester, const Size(390, 900));
      final auth = authAs();
      final local = StaticDiscovery(populatedPool());
      await tester.pumpWidget(
        overviewHost(
          Scaffold(
            body: MomentsFeedView(
              auth: auth,
              onRecord: () {},
              discoveryService: local,
              feedService: QuietFeed(firestore: fakeFirestore(), auth: auth),
              viewsService: StaticViews(const <String>{}),
              momentService: StubMomentService(),
              playerFactory: () => FakePreviewAudioPlayer(),
            ),
          ),
          size: const Size(390, 900),
          observeRoutes: false,
        ),
      );
      await settleOverview(tester);
      await tapPlay(tester, 'm4');
      await tester.tap(find.byKey(const ValueKey('moment-row-menu-m4')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('moment-row-details-m4')),
        findsOneWidget,
      );
      expect(expanded('m4'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(expanded('m4'), isTrue);
      expect(local.loadCalls, 1);
    });

    testWidgets('a long press on the collapsed row body still opens the menu '
        'and closing it reloads nothing', (tester) async {
      await pumpFeed(tester);
      expect(discovery.loadCalls, 1);
      await tester.longPress(row('m5'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('moment-row-details-m5')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('moment-row-details-m5')), findsNothing);
      expect(discovery.loadCalls, 1);
    });
  });

  group('the seek slider', () {
    testWidgets('keyboard focus draws a 2 px focus ring around the wave '
        'strip, and an arrow key moves one second', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpFeed(tester, size: const Size(390, 1400));
      await tapPlay(tester, 'm4');
      final palette = AppPalette.of(tester.element(row('m4')));
      final ring = find.descendant(
        of: row('m4'),
        matching: find.byKey(const ValueKey('moment-row-seek-focus')),
      );
      BoxDecoration ringOf() =>
          tester.widget<DecoratedBox>(ring).decoration as BoxDecoration;
      expect((ringOf().border! as Border).top.color, Colors.transparent);

      final seek = find.byKey(const ValueKey('moment-row-progress-m4'));
      tester.widget<Slider>(seek).focusNode!.requestFocus();
      await tester.pump();
      await tester.pump();
      final side = (ringOf().border! as Border).top;
      expect(side.color, palette.focus);
      expect(side.width, 2);
      // Around the whole strip (the slider has no thumb to light).
      expect(tester.getRect(ring), tester.getRect(seek));

      // One step per second of the clip: the spoken value always moves.
      final slider = tester.widget<Slider>(seek);
      expect(slider.divisions, 12);
      final data = tester.getSemantics(seek).getSemanticsData();
      expect(data.value, '0:00 of 0:12');
      expect(data.increasedValue, '0:01 of 0:12');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump();
      expect(players.single.lastSeekPosition, const Duration(seconds: 1));
      handle.dispose();
    });
  });

  group('the row is ONE focusable node, named', () {
    testWidgets('the node keyboard focus lands on is the row button with its '
        'name, tap and its custom actions; no unnamed focusable node sits '
        'in the row', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpFeed(tester, locale: const Locale('pl'));
      Focus.of(
        tester.element(
          find
              .descendant(
                of: find.byKey(const ValueKey('moment-row-body-m1')),
                matching: find.byType(Padding),
              )
              .first,
        ),
      ).requestFocus();
      await tester.pump();
      await tester.pump();

      final node = tester.getSemantics(row('m1'));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isFocused, Tristate.isTrue);
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.label, startsWith('Otwórz Voice Moment'));
      expect(data.label, contains(', nowy'), reason: 'unheard is spoken');
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      // Like, Reply, More options, and — since ADR-230, because m1 has likes —
      // "See who liked" (the meta line's count stays inert).
      expect(data.customSemanticsActionIds, hasLength(4));

      // Every focusable node inside the row carries a name of its own.
      final unnamed = <SemanticsNode>[];
      void visit(SemanticsNode child) {
        final d = child.getSemanticsData();
        if (d.flagsCollection.isFocused != Tristate.none &&
            d.label.trim().isEmpty &&
            d.tooltip.trim().isEmpty) {
          unnamed.add(child);
        }
        if (!child.mergeAllDescendantsIntoThisNode) {
          child.visitChildren((c) {
            visit(c);
            return true;
          });
        }
      }

      node.visitChildren((c) {
        visit(c);
        return true;
      });
      expect(unnamed, isEmpty);
      final avatar = tester
          .getSemantics(find.byKey(const ValueKey('moment-row-chain-m1')))
          .getSemanticsData();
      expect(avatar.flagsCollection.isFocused, isNot(Tristate.none));
      expect(avatar.flagsCollection.isButton, isTrue);
      expect(avatar.label, startsWith('Otwórz relację użytkownika Maja'));
      handle.dispose();
    });

    testWidgets('a heard row says no "new"', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpFeed(tester, viewed: const {'m1'});
      expect(
        tester.getSemantics(row('m1')).getSemanticsData().label,
        isNot(contains(', new')),
      );
      expect(
        tester.getSemantics(row('m4')).getSemanticsData().label,
        contains(', new'),
      );
      handle.dispose();
    });
  });

  group('contrast on the canvas', () {
    testWidgets('below 1100 the 12 px secondary ink is textSecondary; on the '
        'desktop block it stays textTertiary', (tester) async {
      await pumpFeed(tester);
      var palette = AppPalette.of(tester.element(row('m1')));
      TextStyle metaStyle(String id) =>
          momentMetaLine(tester, id).textSpan!.style!;
      expect(metaStyle('m1').color, palette.textSecondary);
      final ageOnCanvas = tester.widget<Text>(
        find.byKey(const ValueKey('moment-row-age-m1')),
      );
      expect(ageOnCanvas.style!.color, palette.textSecondary);
      await tester.pumpWidget(const SizedBox());

      await pumpFeed(tester, size: const Size(1440, 900));
      palette = AppPalette.of(tester.element(row('m1')));
      expect(metaStyle('m1').color, palette.textTertiary);
    });

    testWidgets('the unheard dot grows with the text', (tester) async {
      await pumpFeed(tester, size: const Size(390, 2400), textScale: 2);
      expect(
        tester.getSize(find.byKey(const ValueKey('moment-row-unheard-m4'))),
        const Size.square(16),
      );
    });
  });

  group('the open row keeps its expiry', () {
    testWidgets('the availability line stays, amber in the last hour', (
      tester,
    ) async {
      final urgent = overviewMoment(
        'u1',
        author: 'ula',
        authorName: 'Ula',
        caption: 'Za chwilę zniknie.',
        age: const Duration(hours: 23, minutes: 30),
      );
      await pumpFeed(
        tester,
        pool: <VoiceMoment>[urgent],
        locale: const Locale('pl'),
      );
      await tapPlay(tester, 'u1');
      expect(expanded('u1'), isTrue);
      final palette = AppPalette.of(tester.element(row('u1')));
      final span = momentMetaLine(tester, 'u1').textSpan! as TextSpan;
      final expiry = span.children!.last as TextSpan;
      expect(expiry.text, matches(RegExp(r'^[Ww]ygasa za (29|30) min$')));
      expect(expiry.style!.color, palette.warningForeground);
      // Only the availability: the length and the counts are elsewhere.
      expect(span.toPlainText(), isNot(contains('0:45')));
    });
  });

  group('reloading', () {
    testWidgets('an empty feed can be pulled to reload too', (tester) async {
      await pumpFeed(tester, pool: const <VoiceMoment>[]);
      expect(
        find.byKey(const ValueKey('moments-discovery-empty')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('moments-discovery-empty')),
          matching: find.byType(RefreshIndicator),
        ),
        findsOneWidget,
      );
      expect(discovery.loadCalls, 1);
      await tester.fling(
        find.byKey(const ValueKey('moments-empty-scroll')),
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(discovery.loadCalls, 2);
    });

    testWidgets('the host\'s refresh request takes the list to the top, '
        'shows the spinner and reads once, however often it fires', (
      tester,
    ) async {
      final requests = ChangeNotifier();
      addTearDown(requests.dispose);
      await pumpFeed(
        tester,
        size: const Size(390, 640),
        refreshRequests: requests,
      );
      final position = feedPosition(tester);
      position.jumpTo(200);
      await tester.pump();
      expect(discovery.loadCalls, 1);

      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      requests.notifyListeners();
      await tester.pump();
      expect(position.pixels, 0);
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      requests.notifyListeners();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);
      expect(discovery.loadCalls, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(discovery.loadCalls, 2);
    });
  });

  group('the tab row\'s edge cue', () {
    ({bool start, bool end}) fades(WidgetTester tester) =>
        VoiceFeedFilterTabs.fadesOf(
          tester.element(find.byKey(const ValueKey('voice-filter-tabs'))),
        );

    testWidgets('at 320 × 200 % the row fades where labels continue, and '
        'nowhere when all three fit', (tester) async {
      await pumpFeed(
        tester,
        size: const Size(320, 800),
        textScale: 2,
        locale: const Locale('pl'),
      );
      await tester.pump();
      expect(fades(tester), (start: false, end: true));
      final scroll = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(const ValueKey('voice-filter-tabs-scroll')),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      expect(fades(tester), (start: true, end: false));
      await tester.pumpWidget(const SizedBox());

      await pumpFeed(tester, locale: const Locale('pl'));
      await tester.pump();
      expect(fades(tester), (start: false, end: false));
    });
  });
}
