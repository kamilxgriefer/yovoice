import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('push identity recognizes an account switch', () {
    expect(
      shouldRebindPushIdentity(
        registeredUserId: 'account-a',
        currentUserId: 'account-a',
      ),
      isFalse,
      reason: 'the same account must not duplicate device listeners or writes',
    );
    expect(
      shouldRebindPushIdentity(
        registeredUserId: null,
        currentUserId: 'account-b',
      ),
      isTrue,
      reason:
          'cold start or sign-out has unknown ownership, so binding rotates',
    );
    expect(
      shouldRebindPushIdentity(
        registeredUserId: 'account-a',
        currentUserId: 'account-b',
      ),
      isTrue,
    );
    expect(
      shouldRebindPushIdentity(
        registeredUserId: 'account-a',
        currentUserId: null,
      ),
      isFalse,
      reason: 'there is no owner to bind while signed out',
    );
  });

  test(
    'account switch cannot reuse a token until invalidation succeeds',
    () async {
      final guard = PushTokenPrivacyGuard()..requireRotation();
      var attempts = 0;

      final failed = await guard.rotate(() async {
        attempts += 1;
        throw Exception('offline');
      });
      expect(failed, isFalse);
      expect(guard.rotationRequired, isTrue);

      final succeeded = await guard.rotate(() async {
        attempts += 1;
      });
      expect(succeeded, isTrue);
      expect(guard.rotationRequired, isFalse);
      expect(attempts, 2);
    },
  );

  test('a platform token refresh satisfies pending rotation', () {
    final guard = PushTokenPrivacyGuard()..requireRotation();
    guard.markTokenRefreshed();
    expect(guard.rotationRequired, isFalse);
  });

  test('refresh cannot register during sign-out or under a stale epoch', () {
    final epochs = PushIdentityEpochGuard();
    final accountAEpoch = epochs.beginTransition();
    expect(epochs.canRegister(accountAEpoch), isFalse);
    expect(epochs.completeTransition(accountAEpoch), isTrue);
    expect(epochs.canRegister(accountAEpoch), isTrue);

    final signOutEpoch = epochs.beginTransition();
    expect(epochs.transitionInProgress, isTrue);
    expect(
      epochs.canRegister(signOutEpoch),
      isFalse,
      reason: 'a refresh queued during sign-out must be ignored',
    );
    expect(epochs.canRegister(accountAEpoch), isFalse);

    final accountBEpoch = epochs.beginTransition();
    expect(epochs.completeTransition(signOutEpoch), isFalse);
    expect(epochs.completeTransition(accountBEpoch), isTrue);
    expect(epochs.canRegister(accountBEpoch), isTrue);
    expect(
      epochs.canRegister(accountAEpoch),
      isFalse,
      reason: 'a delayed Account A write cannot land under Account B',
    );
  });

  test('pending rotation survives a process-local guard restart', () async {
    expect(await markPushTokenRotationPending(), isTrue);
    expect(await isPushTokenRotationPending(), isTrue);

    final restartedGuard = PushTokenPrivacyGuard();
    if (await isPushTokenRotationPending()) {
      restartedGuard.requireRotation();
    }
    expect(restartedGuard.rotationRequired, isTrue);

    expect(await restartedGuard.rotate(() async {}), isTrue);
    expect(await clearPushTokenRotationPending(), isTrue);
    expect(await isPushTokenRotationPending(), isFalse);
  });

  test(
    'persistence failure cannot leave the active process fail-open',
    () async {
      final guard = PushTokenPrivacyGuard();

      final persisted = await requirePushTokenRotation(
        guard: guard,
        persistPending: () async => throw Exception('preferences unavailable'),
      );

      expect(persisted, isFalse);
      expect(guard.rotationRequired, isTrue);
    },
  );

  test('a rejected persistence write is treated as not durable', () async {
    final guard = PushTokenPrivacyGuard();

    final persisted = await requirePushTokenRotation(
      guard: guard,
      persistPending: () async => false,
    );

    expect(persisted, isFalse);
    expect(guard.rotationRequired, isTrue);
  });

  test(
    'sign-out cleanup primitives bound never-completing operations',
    () async {
      final pendingVoid = Completer<void>();
      final pendingBool = Completer<bool>();

      expect(
        await completePushCleanupWithin(
          pendingVoid.future,
          timeout: const Duration(milliseconds: 10),
        ),
        isFalse,
      );
      expect(
        await resolvePushCleanupWithin(
          pendingBool.future,
          timeout: const Duration(milliseconds: 10),
        ),
        isNull,
      );
    },
  );

  test(
    'owner-row cleanup repeats after a delayed registration drains',
    () async {
      final registration = Completer<void>();
      var rowExists = false;
      var deleteCalls = 0;
      final delayedRegistration = registration.future.then((_) {
        rowExists = true;
      });

      final cleanup = retirePushOwnerRowWithin(
        registrationTail: delayedRegistration,
        deleteOwnerRow: () async {
          deleteCalls += 1;
          rowExists = false;
        },
        timeout: const Duration(seconds: 1),
      );

      await Future<void>.delayed(Duration.zero);
      expect(
        deleteCalls,
        1,
        reason: 'retirement starts without waiting offline',
      );
      registration.complete();
      final result = await cleanup;

      expect(result.registrationDrained, isTrue);
      expect(result.ownerRowRemoved, isTrue);
      expect(
        deleteCalls,
        2,
        reason: 'the post-drain delete wins the final race',
      );
      expect(rowExists, isFalse);
    },
  );
}
