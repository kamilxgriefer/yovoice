import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';

class _CountingNavigatorObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount += 1;
    super.didPop(route, previousRoute);
  }
}

/// Regression suite for the P0 "bottom navigation randomly disappears"
/// bug: main destinations opened from "More" are hosted in the
/// production [MoreDestinationHost], which re-hosts the shell's own
/// bottom navigation (one source of truth) and pops back to the shell
/// before acting on any bar tap.
void main() {
  Future<void> pumpHost(
    WidgetTester tester, {
    required GlobalKey<NavigatorState> navigatorKey,
    required ValueChanged<int> onDestinationSelected,
    VoidCallback? onVoicePressed,
    VoidCallback? onMorePressed,
    List<NavigatorObserver> navigatorObservers = const [],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: navigatorObservers,
        home: const Scaffold(body: Text('SHELL')),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => MoreDestinationHost(
          body: const Text('DESTINATION'),
          selectedIndex: 0,
          unreadConversationCount: 3,
          onDestinationSelected: onDestinationSelected,
          onVoicePressed: onVoicePressed ?? () {},
          onMorePressed: onMorePressed ?? () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a More destination keeps the persistent bottom navigation', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await pumpHost(
      tester,
      navigatorKey: navigatorKey,
      onDestinationSelected: (_) {},
    );

    expect(find.text('DESTINATION'), findsOneWidget);
    // The full shell bar is present on the pushed destination route.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Chats'), findsOneWidget);
    // Moments replaced Friends in the dock when it was promoted to
    // primary navigation. Friends kept its tab, its state and its rail
    // item, and moved to the first tile of the More sheet.
    expect(find.text('Moments'), findsOneWidget);
    expect(find.text('Friends'), findsNothing);
    expect(find.text('More'), findsOneWidget);
    // Including live shell state — the unread badge is the same widget,
    // not a per-screen reimplementation.
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('bar taps pop back to the shell first, then switch tabs', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    int? selected;
    await pumpHost(
      tester,
      navigatorKey: navigatorKey,
      onDestinationSelected: (index) => selected = index,
    );

    await tester.tap(find.text('Moments'));
    await tester.pumpAndSettle();

    // Derived from the shell's own slot map rather than hard-coded, so
    // this stays true if the slot is ever renumbered.
    final momentsSlot = MainShell.desktopSlots.entries
        .firstWhere((entry) => entry.value == MoreDestination.moments)
        .key;
    expect(
      selected,
      momentsSlot,
      reason: 'the Moments dock slot must reach the shell',
    );
    expect(
      find.text('SHELL'),
      findsOneWidget,
      reason: 'the destination route must be popped before the tab switch',
    );
    expect(find.text('DESTINATION'), findsNothing);
  });

  testWidgets('the voice action and More menu also pop back first', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    var voiceOpened = false;
    await pumpHost(
      tester,
      navigatorKey: navigatorKey,
      onDestinationSelected: (_) {},
      onVoicePressed: () => voiceOpened = true,
    );

    await tester.tap(find.bySemanticsLabel('Use your voice'));
    await tester.pumpAndSettle();

    expect(voiceOpened, isTrue);
    expect(find.text('SHELL'), findsOneWidget);
  });

  testWidgets('a same-frame double tap on More pops and opens exactly once', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _CountingNavigatorObserver();
    var moreOpenCount = 0;
    await pumpHost(
      tester,
      navigatorKey: navigatorKey,
      navigatorObservers: [observer],
      onDestinationSelected: (_) {},
      onMorePressed: () => moreOpenCount += 1,
    );

    final moreTap = tester.widget<InkWell>(
      find
          .ancestor(of: find.text('More'), matching: find.byType(InkWell))
          .first,
    );
    moreTap.onTap!();
    moreTap.onTap!();

    // Popping starts immediately, but the next action waits until the host's
    // reverse transition and overlay have completely left the Navigator.
    await tester.pump();
    expect(observer.popCount, 1);
    expect(moreOpenCount, 0);

    await tester.pumpAndSettle();
    expect(observer.popCount, 1);
    expect(moreOpenCount, 1);
    expect(find.text('SHELL'), findsOneWidget);
    expect(find.text('DESTINATION'), findsNothing);
  });

  test('the More transition guard rejects concurrent presentations', () async {
    final guard = MoreMenuTransitionGuard();
    final presentation = Completer<MoreDestination?>();
    var presentationCount = 0;

    final first = guard.run<MoreDestination>(() {
      presentationCount += 1;
      return presentation.future;
    });
    final duplicate = guard.run<MoreDestination>(() async {
      presentationCount += 1;
      return MoreDestination.settings;
    });

    expect(await duplicate, isNull);
    expect(guard.isActive, isTrue);
    expect(presentationCount, 1);

    presentation.complete(MoreDestination.profile);
    expect(await first, MoreDestination.profile);
    expect(guard.isActive, isFalse);

    expect(
      await guard.run<MoreDestination>(() async => MoreDestination.settings),
      MoreDestination.settings,
    );
  });
}
