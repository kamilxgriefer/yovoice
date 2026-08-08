import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/screens/main_shell.dart';

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
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
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
    expect(find.text('Friends'), findsOneWidget);
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

    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();

    expect(selected, 2, reason: 'Friends tab index must reach the shell');
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
}
