import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/features/reels/data/reel_links.dart';
import 'package:yovoice/features/reels/presentation/navigation/reel_link_coordinator.dart';

void main() {
  test(
    'intent survives login but is consumed only once by the exact principal',
    () async {
      final controller = ReelLinkIntentController(
        initialUri: buildReelLink('one'),
      );
      addTearDown(controller.dispose);
      controller.handlePrincipal(null);
      expect(controller.consumeFor('a'), isNull);
      controller.handlePrincipal('a');
      expect(controller.consumeFor('b'), isNull);
      expect(controller.consumeFor('a'), 'one');
      expect(controller.consumeFor('a'), isNull);
      var complete = false;
      unawaited(controller.initialVisitCompleted.then((_) => complete = true));
      await Future<void>.value();
      expect(complete, isFalse);
      controller.completeVisit();
      await controller.initialVisitCompleted;
      expect(complete, isTrue);
    },
  );

  test(
    'logout, account switch and auth error invalidate unconsumed intent',
    () {
      for (final transition in [
        <String?>['a', null, 'a'],
        <String?>['a', 'b'],
      ]) {
        final controller = ReelLinkIntentController(
          initialUri: buildReelLink('one'),
        );
        for (final uid in transition) {
          controller.handlePrincipal(uid);
        }
        expect(controller.consumeFor(transition.last!), isNull);
        controller.dispose();
      }
      final controller = ReelLinkIntentController(
        initialUri: buildReelLink('one'),
      );
      controller.handlePrincipal(null);
      controller.handleAuthError();
      controller.handlePrincipal('b');
      expect(controller.consumeFor('b'), isNull);
      controller.dispose();
    },
  );

  test('invalid target does not block onboarding', () async {
    final controller = ReelLinkIntentController(
      initialUri: Uri.parse('https://app.yovoice.app/'),
    );
    addTearDown(controller.dispose);
    await controller.initialVisitCompleted;
    controller.handlePrincipal('a');
    expect(controller.consumeFor('a'), isNull);
  });

  testWidgets(
    'login plus profile readiness opens one destination, then returns to shell',
    (tester) async {
      final controller = ReelLinkIntentController(
        initialUri: buildReelLink('target'),
      );
      final ready = ValueNotifier<bool>(false);
      addTearDown(controller.dispose);
      addTearDown(ready.dispose);
      var builds = 0;
      final navigator = GlobalKey<NavigatorState>();
      controller.handlePrincipal(null);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [appRouteObserver],
          home: ValueListenableBuilder<bool>(
            valueListenable: ready,
            builder: (_, value, _) => value
                ? ReelLinkEntryCoordinator(
                    controller: controller,
                    userId: 'viewer',
                    destinationBuilder: (_, id) {
                      builds++;
                      return Scaffold(body: Text('Destination $id'));
                    },
                    child: const Scaffold(body: Text('Shell')),
                  )
                : const Scaffold(body: Text('Login / profile setup')),
          ),
        ),
      );
      controller.handlePrincipal('viewer');
      await tester.pumpAndSettle();
      expect(builds, 0);
      ready.value = true;
      await tester.pumpAndSettle();
      expect(find.text('Destination target'), findsOneWidget);
      expect(builds, 1);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await controller.initialVisitCompleted;
      controller.handlePrincipal('viewer');
      await tester.pumpAndSettle();
      expect(find.text('Shell'), findsOneWidget);
      expect(builds, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('verification route is never covered by pending Reel', (
    tester,
  ) async {
    final controller = ReelLinkIntentController(
      initialUri: buildReelLink('target'),
    );
    final ready = ValueNotifier<bool>(false);
    addTearDown(controller.dispose);
    addTearDown(ready.dispose);
    final navigator = GlobalKey<NavigatorState>();
    controller.handlePrincipal('viewer');
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [appRouteObserver],
        home: ValueListenableBuilder<bool>(
          valueListenable: ready,
          builder: (_, value, _) => value
              ? ReelLinkEntryCoordinator(
                  controller: controller,
                  userId: 'viewer',
                  destinationBuilder: (_, id) =>
                      Scaffold(body: Text('Reel $id')),
                  child: const Scaffold(body: Text('Shell')),
                )
              : const Scaffold(body: Text('Provisioning')),
        ),
      ),
    );
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Verify email')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    ready.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Verify email'), findsOneWidget);
    expect(find.text('Reel target'), findsNothing);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Reel target'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
