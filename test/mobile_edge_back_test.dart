import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/navigation/mobile_destination_history.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/navigation/yo_edge_back_gesture.dart';

void main() {
  test('root history goes back through visits and Home clears it', () {
    final history = MobileDestinationHistory();
    expect(history.back(), isNull);
    history.select(3);
    history.select(1);
    history.select(1);
    expect(history.back(), 3);
    expect(history.back(), 0);
    expect(history.canGoBack, isFalse);
    history.select(5);
    history.select(0);
    expect(history.canGoBack, isFalse);
  });

  test('history is bounded and viewport reset uses visible roots only', () {
    final history = MobileDestinationHistory();
    for (var i = 0; i < 100; i++) {
      history.select(i.isEven ? 3 : 1);
    }
    var steps = 0;
    while (history.back() != null) {
      steps++;
    }
    expect(steps, 23);
    expect(history.current, 0);
    history.resetTo(2);
    expect(history.back(), 0);
    history.resetTo(10);
    expect(history.canGoBack, isFalse);
    history.select(99);
    expect(history.current, 0);
  });

  Future<void> pumpGesture(
    WidgetTester tester, {
    required VoidCallback onBack,
    bool rtl = false,
    bool enabled = true,
    Object navigationIdentity = 1,
    Widget? child,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: YoEdgeBackGesture(
              enabled: enabled,
              navigationIdentity: navigationIdentity,
              onBack: onBack,
              child: child ?? const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }

  for (final rtl in [false, true]) {
    testWidgets('leading-edge back commits once on release, RTL=$rtl', (
      tester,
    ) async {
      var backs = 0;
      await pumpGesture(tester, onBack: () => backs++, rtl: rtl);
      final gesture = await tester.startGesture(Offset(rtl ? 384 : 6, 300));
      await gesture.moveBy(Offset(rtl ? -30 : 30, 0));
      await gesture.moveBy(Offset(rtl ? -130 : 130, 0));
      await tester.pump();
      expect(backs, 0);
      expect(find.byKey(const ValueKey('edge-back-indicator')), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect(backs, 1);
      expect(find.byKey(const ValueKey('edge-back-indicator')), findsNothing);
    });
  }

  testWidgets(
    'cancel, short, wrong-edge, wrong-direction and mouse do not go back',
    (tester) async {
      var backs = 0;
      await pumpGesture(tester, onBack: () => backs++);
      final canceled = await tester.startGesture(const Offset(6, 300));
      await canceled.moveBy(const Offset(160, 0));
      await canceled.cancel();
      await tester.pump();
      await tester.dragFrom(const Offset(6, 300), const Offset(25, 0));
      await tester.dragFrom(const Offset(384, 300), const Offset(-160, 0));
      await tester.dragFrom(const Offset(6, 300), const Offset(-160, 0));
      await tester.dragFrom(
        const Offset(6, 300),
        const Offset(160, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(backs, 0);
    },
  );

  testWidgets('center horizontal media gestures remain owned by child', (
    tester,
  ) async {
    var backs = 0;
    var mediaDrags = 0;
    await pumpGesture(
      tester,
      onBack: () => backs++,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (_) => mediaDrags++,
        child: const SizedBox.expand(),
      ),
    );
    await tester.dragFrom(const Offset(150, 300), const Offset(180, 0));
    await tester.pump();
    expect(backs, 0);
    expect(mediaDrags, 1);
  });

  testWidgets('vertical scrolling still works from leading edge', (
    tester,
  ) async {
    var backs = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await pumpGesture(
      tester,
      onBack: () => backs++,
      child: ListView(
        controller: scroll,
        children: const [SizedBox(height: 2400)],
      ),
    );
    await tester.dragFrom(const Offset(6, 500), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(50));
    expect(backs, 0);
  });

  for (final rtl in [false, true]) {
    testWidgets(
      'true leading-edge horizontal drag wins over child media, RTL=$rtl',
      (tester) async {
        var backs = 0;
        var mediaDrags = 0;
        await pumpGesture(
          tester,
          rtl: rtl,
          onBack: () => backs++,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (_) => mediaDrags++,
            child: const SizedBox.expand(),
          ),
        );
        await tester.dragFrom(
          Offset(rtl ? 384 : 6, 300),
          Offset(rtl ? -180 : 180, 0),
        );
        await tester.pump();
        expect(backs, 1);
        expect(mediaDrags, 0);
      },
    );
  }

  testWidgets('leading-edge tap still reaches the underlying child', (
    tester,
  ) async {
    var taps = 0;
    await pumpGesture(
      tester,
      onBack: () => fail('A tap is not Back'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => taps++,
        child: const SizedBox.expand(),
      ),
    );
    await tester.tapAt(const Offset(6, 300));
    expect(taps, 1);
    expect(find.byKey(const ValueKey('edge-back-indicator')), findsNothing);
  });

  testWidgets('disabled root does not consume an edge media gesture', (
    tester,
  ) async {
    var mediaDrags = 0;
    await pumpGesture(
      tester,
      enabled: false,
      onBack: () => fail('disabled'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (_) => mediaDrags++,
        child: const SizedBox.expand(),
      ),
    );
    await tester.dragFrom(const Offset(6, 300), const Offset(180, 0));
    expect(mediaDrags, 1);
  });

  testWidgets('ordinary pushed iOS page retains native interactive Back', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS),
        home: const Scaffold(body: Text('root')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('detail')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(2, 200), const Offset(650, 0));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(find.text('root'), findsOneWidget);
  });

  testWidgets(
    'same-identity rebuild retains drag, changed identity cancels it',
    (tester) async {
      var backs = 0;
      await pumpGesture(tester, onBack: () => backs++);
      final retained = await tester.startGesture(const Offset(6, 300));
      await retained.moveBy(const Offset(30, 0));
      await retained.moveBy(const Offset(130, 0));
      await tester.pump();
      await pumpGesture(tester, onBack: () => backs++);
      await retained.up();
      expect(backs, 1);

      final canceled = await tester.startGesture(const Offset(6, 300));
      await canceled.moveBy(const Offset(30, 0));
      await canceled.moveBy(const Offset(130, 0));
      await tester.pump();
      await pumpGesture(tester, onBack: () => backs++, navigationIdentity: 2);
      expect(find.byKey(const ValueKey('edge-back-indicator')), findsNothing);
      await canceled.up();
      expect(backs, 1);
      await tester.dragFrom(const Offset(6, 300), const Offset(160, 0));
      expect(backs, 2);
    },
  );

  testWidgets('disabling during a drag cancels without a late back', (
    tester,
  ) async {
    var backs = 0;
    await pumpGesture(tester, onBack: () => backs++);
    final gesture = await tester.startGesture(const Offset(6, 300));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(130, 0));
    await tester.pump();
    await pumpGesture(tester, onBack: () => backs++, enabled: false);
    await gesture.up();
    expect(backs, 0);
    expect(find.byKey(const ValueKey('edge-back-indicator')), findsNothing);
    await pumpGesture(tester, onBack: () => backs++);
    await tester.dragFrom(const Offset(6, 300), const Offset(160, 0));
    expect(backs, 1);
  });

  testWidgets('a second pointer cannot create a duplicate back commit', (
    tester,
  ) async {
    var backs = 0;
    await pumpGesture(tester, onBack: () => backs++);
    final first = await tester.startGesture(const Offset(6, 300), pointer: 1);
    final second = await tester.startGesture(const Offset(6, 400), pointer: 2);
    await first.moveBy(const Offset(30, 0));
    await first.moveBy(const Offset(130, 0));
    await second.moveBy(const Offset(160, 0));
    await first.up();
    await second.up();
    expect(backs, 1);
    await tester.dragFrom(const Offset(6, 300), const Offset(160, 0));
    expect(backs, 2);
  });

  testWidgets('unmounting during a drag leaves no late callback or exception', (
    tester,
  ) async {
    var backs = 0;
    await pumpGesture(tester, onBack: () => backs++);
    final gesture = await tester.startGesture(const Offset(6, 300));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(130, 0));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await gesture.up();
    await tester.pump();
    expect(backs, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a separate bottom dock retains its leading-edge drag', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var backs = 0;
    var dockDrags = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: YoEdgeBackGesture(
            enabled: true,
            navigationIdentity: 1,
            onBack: () => backs++,
            child: const SizedBox.expand(),
          ),
          bottomNavigationBar: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (_) => dockDrags++,
            child: const SizedBox(height: 100),
          ),
        ),
      ),
    );
    await tester.dragFrom(const Offset(6, 800), const Offset(160, 0));
    expect(dockDrags, 1);
    expect(backs, 0);
  });

  testWidgets('system Back composes root history and a pushed route', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final root = GlobalKey<_RootHistoryFixtureState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: _RootHistoryFixture(key: root),
      ),
    );
    await tester.tap(find.text('Go Rooms'));
    await tester.pump();
    await tester.tap(find.text('Go Chats'));
    await tester.pump();
    expect(root.currentState!.history.current, 1);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('pushed detail')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('pushed detail'), findsNothing);
    expect(root.currentState!.history.current, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(root.currentState!.history.current, 3);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(root.currentState!.history.current, 0);
    expect(root.currentState!.history.canGoBack, isFalse);
    await tester.tap(find.text('Go Chats'));
    await tester.pump();
    await tester.tap(find.text('Go Home'));
    await tester.pump();
    expect(root.currentState!.history.canGoBack, isFalse);
  });

  for (final rtl in [false, true]) {
    testWidgets(
      'indicator stays inside landscape leading safe inset, RTL=$rtl',
      (tester) async {
        tester.view.physicalSize = const Size(768, 390);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: EdgeInsets.only(
                  left: rtl ? 0 : 47,
                  right: rtl ? 47 : 0,
                ),
                viewPadding: EdgeInsets.only(
                  left: rtl ? 0 : 47,
                  right: rtl ? 47 : 0,
                ),
              ),
              child: Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: child!,
              ),
            ),
            home: Scaffold(
              body: YoEdgeBackGesture(
                enabled: true,
                navigationIdentity: 1,
                onBack: () {},
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
        final gesture = await tester.startGesture(Offset(rtl ? 762 : 6, 150));
        await gesture.moveBy(Offset(rtl ? -30 : 30, 0));
        await gesture.moveBy(Offset(rtl ? -100 : 100, 0));
        await tester.pump();
        final indicator = tester.getRect(
          find.byKey(const ValueKey('edge-back-indicator')),
        );
        if (rtl) {
          expect(indicator.right, lessThanOrEqualTo(768 - 47));
        } else {
          expect(indicator.left, greaterThanOrEqualTo(47));
        }
        await gesture.cancel();
        await tester.pump();
      },
    );
  }

  testWidgets('route appearing during edge drag prevents a root history pop', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    var backs = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: YoEdgeBackGesture(
            enabled: true,
            navigationIdentity: 1,
            onBack: () => backs++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(6, 300));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(130, 0));
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('arriving route')),
      ),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(backs, 0);
    expect(find.text('arriving route'), findsOneWidget);
  });

  for (final veto in [false, true]) {
    testWidgets(
      'native pushed iOS back cancel/veto preserves root, veto=$veto',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final navigator = GlobalKey<NavigatorState>();
        var rootBacks = 0;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS),
            home: Scaffold(
              body: YoEdgeBackGesture(
                enabled: true,
                navigationIdentity: 1,
                onBack: () => rootBacks++,
                child: const Text('retained root'),
              ),
            ),
          ),
        );
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => PopScope<void>(
              canPop: !veto,
              child: const Scaffold(body: Text('native detail')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final gesture = await tester.startGesture(const Offset(2, 300));
        await gesture.moveBy(Offset(veto ? 340 : 70, 0));
        await tester.pump(const Duration(milliseconds: 600));
        if (veto) {
          await gesture.up();
        } else {
          await gesture.cancel();
        }
        await tester.pumpAndSettle();
        expect(find.text('native detail'), findsOneWidget);
        expect(rootBacks, 0);
        if (veto) {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.text('native detail'), findsOneWidget);
          expect(rootBacks, 0);
        }
      },
    );
  }
}

/// Composition fixture, not the Firebase-backed MainShell: exercise the real
/// history and edge component under the same root PopScope contract.
class _RootHistoryFixture extends StatefulWidget {
  const _RootHistoryFixture({super.key});

  @override
  State<_RootHistoryFixture> createState() => _RootHistoryFixtureState();
}

class _RootHistoryFixtureState extends State<_RootHistoryFixture> {
  final history = MobileDestinationHistory();

  void back() => setState(() => history.back());

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !history.canGoBack,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) back();
    },
    child: Scaffold(
      body: YoEdgeBackGesture(
        enabled: history.canGoBack,
        navigationIdentity: history.current,
        onBack: back,
        child: Column(
          children: [
            for (final destination in [(0, 'Home'), (3, 'Rooms'), (1, 'Chats')])
              TextButton(
                onPressed: () => setState(() => history.select(destination.$1)),
                child: Text('Go ${destination.$2}'),
              ),
            Text('Current root ${history.current}'),
          ],
        ),
      ),
    ),
  );
}
