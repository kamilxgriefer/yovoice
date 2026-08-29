import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';

void main() {
  test(
    'permission barrier settles after permission, before later push work',
    () async {
      final localInitialization = Completer<void>();
      final permission = Completer<String>();
      var permissionRequested = false;
      var settled = 0;

      final phase = runInitialNotificationPermissionPhase(
        initializeLocalNotifications: () => localInitialization.future,
        requestPermission: () {
          permissionRequested = true;
          return permission.future;
        },
        onSettled: () => settled += 1,
        timeout: const Duration(seconds: 1),
      );

      await Future<void>.delayed(Duration.zero);
      expect(permissionRequested, isFalse);
      expect(settled, 0);

      localInitialization.complete();
      await Future<void>.delayed(Duration.zero);
      expect(permissionRequested, isTrue);
      expect(settled, 0);

      permission.complete('authorized');
      expect(await phase, 'authorized');
      expect(settled, 1);
    },
  );

  test(
    'local notification initialization failure releases the barrier',
    () async {
      var permissionRequested = false;
      var settled = 0;

      await expectLater(
        runInitialNotificationPermissionPhase<void>(
          initializeLocalNotifications: () =>
              Future<void>.error(StateError('local init failed')),
          requestPermission: () async {
            permissionRequested = true;
          },
          onSettled: () => settled += 1,
          timeout: const Duration(seconds: 1),
        ),
        throwsStateError,
      );

      expect(permissionRequested, isFalse);
      expect(settled, 1);
    },
  );

  test('permission request failure also releases the barrier once', () async {
    var settled = 0;

    await expectLater(
      runInitialNotificationPermissionPhase<void>(
        initializeLocalNotifications: () async {},
        requestPermission: () =>
            Future<void>.error(StateError('permission failed')),
        onSettled: () => settled += 1,
        timeout: const Duration(seconds: 1),
      ),
      throwsStateError,
    );

    expect(settled, 1);
  });

  test(
    'hung local initialization times out without a late permission request',
    () async {
      final localInitialization = Completer<void>();
      var permissionRequests = 0;
      var settled = 0;

      await expectLater(
        runInitialNotificationPermissionPhase<void>(
          initializeLocalNotifications: () => localInitialization.future,
          requestPermission: () async => permissionRequests += 1,
          onSettled: () => settled += 1,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(permissionRequests, 0);
      expect(settled, 1);
      localInitialization.complete();
      await pumpEventQueue();
      expect(permissionRequests, 0);
      expect(settled, 1);
    },
  );

  test('hung permission request is issued once and settles once', () async {
    final permission = Completer<void>();
    var permissionRequests = 0;
    var settled = 0;

    await expectLater(
      runInitialNotificationPermissionPhase<void>(
        initializeLocalNotifications: () async {},
        requestPermission: () {
          permissionRequests += 1;
          return permission.future;
        },
        onSettled: () => settled += 1,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );

    expect(permissionRequests, 1);
    expect(settled, 1);
    permission.complete();
    await pumpEventQueue();
    expect(permissionRequests, 1);
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
