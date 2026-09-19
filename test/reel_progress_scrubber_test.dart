import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_progress_row.dart';

import 'reel_stage_test_support.dart';

/// Drag-to-seek on the Yeel timeline (ADR-210): the band over the hairline.
void main() {
  const bandKey = ValueKey<String>('reel-progress-scrub');
  const total = Duration(seconds: 20);

  group('the band', () {
    late _FakeTarget target;
    late ValueNotifier<Duration> position;
    late int underTaps;

    Future<void> pumpBand(
      WidgetTester tester, {
      TextDirection direction = TextDirection.ltr,
      bool disableAnimations = false,
      bool inPager = false,
    }) async {
      underTaps = 0;
      final trackKey = GlobalKey();
      Widget stage = SizedBox(
        width: 400,
        height: 200,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey<String>('under'),
                behavior: HitTestBehavior.opaque,
                onTap: () => underTaps += 1,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: KeyedSubtree(
                key: trackKey,
                child: ListenableBuilder(
                  listenable: target,
                  builder: (context, _) => ReelProgressBar(
                    position: position,
                    total: total,
                    announce: !target.canSeek,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 40,
              child: ReelProgressScrubber(
                key: bandKey,
                target: target,
                position: position,
                total: total,
                trackKey: trackKey,
              ),
            ),
          ],
        ),
      );
      if (inPager) {
        stage = PageView(
          scrollDirection: Axis.vertical,
          children: <Widget>[
            Center(child: stage),
            const Center(child: Text('next page')),
          ],
        );
      } else {
        stage = Center(child: stage);
      }
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: Directionality(
            textDirection: direction,
            child: Scaffold(body: stage),
          ),
        ),
      );
    }

    setUp(() {
      target = _FakeTarget();
      position = ValueNotifier<Duration>(Duration.zero);
      target.position = position;
    });

    tearDown(() {
      position.dispose();
      target.dispose();
    });

    testWidgets('a horizontal drag begins, follows the finger and ends', (
      tester,
    ) async {
      await pumpBand(tester);
      final band = tester.getRect(find.byKey(bandKey));
      final gesture = await tester.startGesture(
        Offset(band.left + 100, band.center.dy),
      );
      await gesture.moveBy(const Offset(40, 0));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(target.calls, <String>['begin']);
      await gesture.up();
      await tester.pump();

      expect(target.calls, <String>['begin', 'end']);
      // DragStartBehavior.down: the first preview is where the finger landed.
      expect(target.targets.first, const Duration(seconds: 5));
      expect(target.targets.last, const Duration(seconds: 10));
      expect(underTaps, 0);
    });

    testWidgets('right-to-left mirrors the fraction', (tester) async {
      await pumpBand(tester, direction: TextDirection.rtl);
      final band = tester.getRect(find.byKey(bandKey));
      await tester.dragFrom(
        Offset(band.left + 100, band.center.dy),
        const Offset(100, 0),
      );
      await tester.pump();
      expect(target.targets.first, const Duration(seconds: 15));
      expect(target.targets.last, const Duration(seconds: 10));
    });

    testWidgets('a vertical swipe from the band still turns the page', (
      tester,
    ) async {
      await pumpBand(tester, inPager: true);
      final band = tester.getRect(find.byKey(bandKey));
      await tester.dragFrom(
        Offset(band.left + 200, band.center.dy),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(target.calls, isEmpty);
      expect(target.targets, isEmpty);
      expect(tester.getCenter(find.text('next page')).dy, lessThan(600));
    });

    testWidgets('a touch tap falls through; a mouse click seeks', (
      tester,
    ) async {
      await pumpBand(tester);
      final band = tester.getRect(find.byKey(bandKey));
      final point = Offset(band.left + 300, band.center.dy);

      await tester.tapAt(point);
      await tester.pump(kDoubleTapTimeout);
      expect(underTaps, 1);
      expect(target.steps, isEmpty);
      expect(target.calls, isEmpty);

      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.pump(kDoubleTapTimeout);
      expect(target.steps, <Duration>[const Duration(seconds: 15)]);
      expect(underTaps, 1, reason: 'the click belongs to the timeline');
    });

    testWidgets('one adjustable slider node; none while it cannot seek', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      position.value = const Duration(seconds: 6);
      await pumpBand(tester);

      final finder = find.bySemanticsLabel('Playback position');
      expect(finder, findsOneWidget);
      final node = tester.getSemantics(finder);
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isSlider, isTrue);
      expect(data.value, '0:06 of 0:20');
      expect(data.increasedValue, '0:11 of 0:20');
      expect(data.decreasedValue, '0:01 of 0:20');
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      expect(data.hasAction(SemanticsAction.decrease), isTrue);

      node.owner!.performAction(node.id, SemanticsAction.increase);
      node.owner!.performAction(node.id, SemanticsAction.decrease);
      expect(target.steps, <Duration>[
        const Duration(seconds: 5),
        const Duration(seconds: -5),
      ]);

      target.setSeekable(false);
      await tester.pump();
      final still = find.bySemanticsLabel('Playback position');
      expect(still, findsOneWidget, reason: 'the bar keeps the fact');
      final readOnly = tester.getSemantics(still).getSemanticsData();
      expect(readOnly.flagsCollection.isSlider, isFalse);
      expect(readOnly.hasAction(SemanticsAction.increase), isFalse);
      semantics.dispose();
    });

    testWidgets('arrow keys step five seconds, mirrored in RTL', (
      tester,
    ) async {
      await pumpBand(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('reel-progress-scrub-focus')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(target.steps, <Duration>[
        const Duration(seconds: 5),
        const Duration(seconds: -5),
      ]);

      target.steps.clear();
      await pumpBand(tester, direction: TextDirection.rtl);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(target.steps, <Duration>[const Duration(seconds: -5)]);
    });

    testWidgets('the track grows, a thumb and the time appear', (tester) async {
      await pumpBand(tester);
      expect(
        find.byKey(const ValueKey<String>('reel-progress-scrub-thumb')),
        findsNothing,
      );
      final band = tester.getRect(find.byKey(bandKey));
      final gesture = await tester.startGesture(
        Offset(band.left + 100, band.center.dy),
      );
      await gesture.moveBy(const Offset(60, 0));
      await tester.pumpAndSettle();

      final track = tester.getRect(
        find.byKey(const ValueKey<String>('reel-progress-scrub-track')),
      );
      expect(track.height, ReelProgressScrubber.scrubTrackHeight);
      expect(track.width, 400);
      expect(
        find.byKey(const ValueKey<String>('reel-progress-scrub-thumb')),
        findsOneWidget,
      );
      expect(find.text('0:08 / 0:20'), findsOneWidget);
      final label = tester.getRect(find.text('0:08 / 0:20'));
      expect(label.bottom, lessThanOrEqualTo(track.top));
      // The visible hairline itself never moved or grew.
      expect(tester.getSize(find.byKey(reelProgressBarKey)).height, 2);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('reel-progress-scrub-thumb')),
        findsNothing,
      );
    });

    testWidgets('under Reduce Motion the scrub state is instant', (
      tester,
    ) async {
      await pumpBand(tester, disableAnimations: true);
      final band = tester.getRect(find.byKey(bandKey));
      final gesture = await tester.startGesture(
        Offset(band.left + 100, band.center.dy),
      );
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(
        find.byKey(const ValueKey<String>('reel-progress-scrub-thumb')),
        findsOneWidget,
      );
      await gesture.up();
      await tester.pump();
    });
  });

  testWidgets('the hairline draws its played part at full height', (
    tester,
  ) async {
    // Regression: the fill was a childless box under the Stack's loose
    // height, laid out 0 px tall, so the bar never showed any progress.
    final position = ValueNotifier<Duration>(const Duration(seconds: 9));
    addTearDown(position.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ReelProgressBar(
              position: position,
              total: const Duration(seconds: 18),
            ),
          ),
        ),
      ),
    );
    final fills = find.descendant(
      of: find.byKey(reelProgressBarKey),
      matching: find.byType(ColoredBox),
    );
    final sizes = fills
        .evaluate()
        .map((element) => (element.renderObject! as RenderBox).size)
        .toList();
    expect(sizes, hasLength(2));
    expect(sizes.last.width, 200);
    expect(sizes.last.height, ReelProgressBar.trackHeight);
  });

  group('on the Yeel stage', () {
    setUpAll(loadStageFonts);

    Finder inCard(Finder finder) =>
        find.descendant(of: find.byType(ReelCard), matching: finder).first;

    Future<void> dragAcross(WidgetTester tester, {double to = .5}) async {
      final band = tester.getRect(inCard(find.byKey(bandKey)));
      final bar = tester.getRect(inCard(find.byKey(reelProgressBarKey)));
      final gesture = await tester.startGesture(
        Offset(bar.left + bar.width * .1, band.bottom - 4),
      );
      await gesture.moveTo(Offset(bar.left + bar.width * to, band.bottom - 4));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    for (final size in <Size>[const Size(390, 844), const Size(1440, 900)]) {
      testWidgets('${size.width.toInt()} px: a drag seeks and play resumes', (
        tester,
      ) async {
        final players = FakeReelPlayers();
        await pumpReelStage(
          tester,
          players: players,
          size: size,
          immersive: size.width < 600,
        );
        final video = players.of('reel_1');
        expect(video.playing, isTrue);
        final bar = tester.getRect(inCard(find.byKey(reelProgressBarKey)));

        await dragAcross(tester, to: .5);

        expect(video.seekPositions.last.inMilliseconds, closeTo(9000, 200));
        expect(video.playing, isTrue);
        expect(tester.getRect(inCard(find.byKey(reelProgressBarKey))), bar);
        expect(bar.height, ReelProgressBar.trackHeight);
      });
    }

    testWidgets('a tap on the band over the media still pauses', (
      tester,
    ) async {
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(390, 844),
        immersive: true,
      );
      final video = players.of('reel_1');
      expect(video.playing, isTrue);
      final band = tester.getRect(inCard(find.byKey(bandKey)));
      final rail = tester.getRect(
        inCard(find.byKey(const ValueKey<String>('reel-action-rail'))),
      );
      final identity = tester.getRect(
        inCard(find.byKey(const ValueKey<String>('reel-identity-block'))),
      );
      // A point of the band that no control covers: between the identity
      // block and the rail, or under both.
      final x = identity.right < rail.left
          ? (identity.right + rail.left) / 2
          : band.center.dx;
      final y = band.bottom - 3;
      await tester.tapAt(Offset(x, y));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(video.playing, isFalse);
    });

    testWidgets('a mouse click on a control over the band fires it; only the '
        'strip under every control seeks', (tester) async {
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(390, 844),
        immersive: true,
      );
      final video = players.of('reel_1');
      final band = tester.getRect(inCard(find.byKey(bandKey)));
      final more = tester.getRect(
        inCard(find.byKey(const ValueKey('reel-more-action'))),
      );
      final bar = tester.getRect(inCard(find.byKey(reelProgressBarKey)));
      expect(band.height, greaterThanOrEqualTo(44));
      // The control really does sit inside the band.
      expect(more.bottom, greaterThan(band.top));
      final seeksBefore = video.seekPositions.length;

      await tester.tapAt(
        Offset(more.center.dx, more.bottom - 4),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(video.seekPositions.length, seeksBefore);
      expect(find.text('Report Yeel'), findsOneWidget);
      Navigator.of(tester.element(find.text('Report Yeel'))).pop();
      await tester.pumpAndSettle();

      // Under every control, a click still moves the timeline.
      await tester.tapAt(
        Offset(bar.left + bar.width * .25, band.bottom - 3),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(video.seekPositions.length, seeksBefore + 1);
    });

    testWidgets('the spoken slider keeps to the strip under the controls', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(390, 844),
        immersive: true,
      );
      final band = tester.getRect(inCard(find.byKey(bandKey)));
      final more = tester.getRect(
        inCard(find.byKey(const ValueKey('reel-more-action'))),
      );
      final slider = tester.getRect(
        find.bySemanticsLabel(RegExp('Playback position')).first,
      );
      expect(slider.bottom, band.bottom);
      expect(slider.top, greaterThanOrEqualTo(more.bottom));
      semantics.dispose();
    });

    testWidgets('the chrome fades under the finger, not under Reduce Motion', (
      tester,
    ) async {
      final players = FakeReelPlayers();
      await pumpReelStage(
        tester,
        players: players,
        size: const Size(390, 844),
        immersive: true,
      );
      double chromeOpacity() => tester
          .widget<AnimatedOpacity>(
            find
                .descendant(
                  of: inCard(
                    find.byKey(const ValueKey<String>('reel-action-rail')),
                  ),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          )
          .opacity;

      final band = tester.getRect(inCard(find.byKey(bandKey)));
      final gesture = await tester.startGesture(
        Offset(band.left + 60, band.bottom - 4),
      );
      await gesture.moveBy(const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(chromeOpacity(), 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(chromeOpacity(), 1);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpAndSettle();
      final held = await tester.startGesture(
        Offset(band.left + 60, band.bottom - 4),
      );
      await held.moveBy(const Offset(80, 0));
      await tester.pump();
      expect(chromeOpacity(), 1);
      await held.up();
      await tester.pumpAndSettle();
    });
  });
}

class _FakeTarget extends ChangeNotifier implements ReelScrubTarget {
  bool _seekable = true;
  bool _scrubbing = false;
  late ValueNotifier<Duration> position;
  final List<String> calls = <String>[];
  final List<Duration> targets = <Duration>[];
  final List<Duration> steps = <Duration>[];

  void setSeekable(bool value) {
    _seekable = value;
    notifyListeners();
  }

  @override
  bool get canSeek => _seekable;

  @override
  bool get isScrubbing => _scrubbing;

  @override
  Future<void> beginScrub() async {
    calls.add('begin');
    _scrubbing = true;
    notifyListeners();
  }

  @override
  void scrubTo(Duration offset) {
    targets.add(offset);
    position.value = offset;
  }

  @override
  Future<void> endScrub() async {
    calls.add('end');
    _scrubbing = false;
    notifyListeners();
  }

  @override
  Future<void> seekBy(Duration delta) async => steps.add(delta);
}
