import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/navigation/embedded_back_scope.dart';

/// A view inside a route that owns one level of Back (the Yeels "Twoje
/// Yeels" pool) must take exactly one Back, and must never share it with the
/// host that holds the same route for its own history (the mobile shell).
void main() {
  testWidgets('a claimed scope takes a system Back instead of the route', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    var backs = 0;
    var claimed = true;
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const Text('home')),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => StatefulBuilder(
          builder: (context, setState) => EmbeddedBackScope(
            claimed: claimed,
            onBack: () => setState(() {
              backs += 1;
              claimed = false;
            }),
            child: const Text('sub-view'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(backs, 1);
    expect(find.text('sub-view'), findsOneWidget, reason: 'route kept');

    // Released: the next Back is the route's again.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(backs, 1);
    expect(find.text('sub-view'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('one Back never both leaves the sub-view and moves the host '
      'history that holds the same route', (tester) async {
    var subViewBacks = 0;
    var historyBacks = 0;
    var claimed = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          // The mobile shell's shape: a PopScope holding the root route for
          // its tab history, offering each Back to the scopes first.
          builder: (shellContext) => PopScope<Object?>(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop || EmbeddedBackScope.dispatch(shellContext)) return;
              historyBacks += 1;
            },
            child: StatefulBuilder(
              builder: (context, setState) => EmbeddedBackScope(
                claimed: claimed,
                onBack: () => setState(() {
                  subViewBacks += 1;
                  claimed = false;
                }),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );

    // Both pop entries hear this Back; only the sub-view acts, and only once.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(subViewBacks, 1);
    expect(historyBacks, 0);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(subViewBacks, 1);
    expect(historyBacks, 1);
  });

  testWidgets('dispatch reaches only a claimed scope on the same route', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    var backs = 0;
    late BuildContext homeContext;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) {
            homeContext = context;
            return EmbeddedBackScope(
              claimed: true,
              onBack: () => backs += 1,
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );

    // The edge-swipe path: a direct offer, answered once.
    expect(EmbeddedBackScope.dispatch(homeContext), isTrue);
    expect(backs, 1);

    late BuildContext pushedContext;
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) {
          pushedContext = context;
          return const SizedBox.expand();
        },
      ),
    );
    await tester.pumpAndSettle();
    // A scope on a covered route claims nothing for the route above it.
    expect(EmbeddedBackScope.dispatch(pushedContext), isFalse);
    expect(backs, 1);
  });

  testWidgets('an unclaimed scope changes nothing', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    var backs = 0;
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const Text('home')),
    );
    late BuildContext pushedContext;
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) {
          pushedContext = context;
          return EmbeddedBackScope(
            claimed: false,
            onBack: () => backs += 1,
            child: const Text('page'),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(EmbeddedBackScope.dispatch(pushedContext), isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(backs, 0);
    expect(find.text('home'), findsOneWidget);
  });
}
