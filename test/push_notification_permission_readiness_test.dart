import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';

void main() {
  test('startup barrier inspects permission without requesting it', () async {
    final localInitialization = Completer<void>();
    final inspection = Completer<String>();
    var permissionInspected = false;
    var settled = 0;

    final phase = runInitialNotificationInspectionPhase(
      initializeLocalNotifications: () => localInitialization.future,
      inspectPermission: () {
        permissionInspected = true;
        return inspection.future;
      },
      onSettled: () => settled += 1,
      timeout: const Duration(seconds: 1),
    );

    await Future<void>.delayed(Duration.zero);
    expect(permissionInspected, isFalse);
    expect(settled, 0);

    localInitialization.complete();
    await Future<void>.delayed(Duration.zero);
    expect(permissionInspected, isTrue);
    expect(settled, 0);

    inspection.complete('authorized');
    expect(await phase, 'authorized');
    expect(settled, 1);
  });

  test(
    'local notification initialization failure releases the barrier',
    () async {
      var permissionInspected = false;
      var settled = 0;

      await expectLater(
        runInitialNotificationInspectionPhase<void>(
          initializeLocalNotifications: () =>
              Future<void>.error(StateError('local init failed')),
          inspectPermission: () async {
            permissionInspected = true;
          },
          onSettled: () => settled += 1,
          timeout: const Duration(seconds: 1),
        ),
        throwsStateError,
      );

      expect(permissionInspected, isFalse);
      expect(settled, 1);
    },
  );

  test('permission inspection failure releases the barrier once', () async {
    var settled = 0;

    await expectLater(
      runInitialNotificationInspectionPhase<void>(
        initializeLocalNotifications: () async {},
        inspectPermission: () =>
            Future<void>.error(StateError('permission failed')),
        onSettled: () => settled += 1,
        timeout: const Duration(seconds: 1),
      ),
      throwsStateError,
    );

    expect(settled, 1);
  });

  test(
    'hung local initialization times out without a late inspection',
    () async {
      final localInitialization = Completer<void>();
      var permissionInspections = 0;
      var settled = 0;

      await expectLater(
        runInitialNotificationInspectionPhase<void>(
          initializeLocalNotifications: () => localInitialization.future,
          inspectPermission: () async => permissionInspections += 1,
          onSettled: () => settled += 1,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(permissionInspections, 0);
      expect(settled, 1);
      localInitialization.complete();
      await pumpEventQueue();
      expect(permissionInspections, 0);
      expect(settled, 1);
    },
  );

  test('hung permission inspection is issued once and settles once', () async {
    final inspection = Completer<void>();
    var permissionInspections = 0;
    var settled = 0;

    await expectLater(
      runInitialNotificationInspectionPhase<void>(
        initializeLocalNotifications: () async {},
        inspectPermission: () {
          permissionInspections += 1;
          return inspection.future;
        },
        onSettled: () => settled += 1,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );

    expect(permissionInspections, 1);
    expect(settled, 1);
    inspection.complete();
    await pumpEventQueue();
    expect(permissionInspections, 1);
    expect(settled, 1);
  });

  test(
    'initial notification readiness waits for its destination route',
    () async {
      final route = Completer<void>();
      var routingCalls = 0;
      var completed = false;

      final readiness = resolveInitialNotificationNavigation<String>(
        getInitialMessage: () async => 'conversation-1',
        routeMessage: (message) {
          expect(message, 'conversation-1');
          routingCalls += 1;
          return route.future;
        },
        timeout: const Duration(seconds: 1),
      )..then((_) => completed = true);

      await pumpEventQueue();
      expect(routingCalls, 1);
      expect(completed, isFalse);

      route.complete();
      await readiness;
      expect(completed, isTrue);
    },
  );

  test('no initial notification releases readiness without routing', () async {
    var routingCalls = 0;

    await resolveInitialNotificationNavigation<String>(
      getInitialMessage: () async => null,
      routeMessage: (_) async => routingCalls += 1,
      timeout: const Duration(seconds: 1),
    );

    expect(routingCalls, 0);
  });

  test(
    'hung initial notification lookup fails open without a late route',
    () async {
      final lookup = Completer<String?>();
      var routingCalls = 0;

      await resolveInitialNotificationNavigation<String>(
        getInitialMessage: () => lookup.future,
        routeMessage: (_) async => routingCalls += 1,
        timeout: const Duration(milliseconds: 10),
      );

      expect(routingCalls, 0);
      lookup.complete('late-message');
      await pumpEventQueue();
      expect(routingCalls, 0);
    },
  );
}
