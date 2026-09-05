import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';

void main() {
  for (final isWeb in [false, true]) {
    test('no current session cannot present (web: $isWeb)', () async {
      final accepted = await presentForegroundNotificationSurface(
        isWeb: isWeb,
        isCall: false,
        isCurrent: () => false,
        presentInApp: () => fail('No session may receive this payload'),
        presentNative: () async => fail('No native alert after sign-out'),
      );
      expect(accepted, isFalse);
    });
  }

  for (final changesUid in [true, false]) {
    test('auth transition blocks stale retry (new UID: $changesUid)', () async {
      var currentUid = 'first-user';
      final identity = PushIdentityEpochGuard();
      final expectedEpoch = identity.epoch;
      var appAttempts = 0;
      final accepted = await presentForegroundNotificationSurface(
        isWeb: false,
        isCall: true,
        isCurrent: () =>
            currentUid == 'first-user' && identity.epoch == expectedEpoch,
        presentInApp: () {
          appAttempts++;
          return true;
        },
        presentNative: () async {
          if (changesUid) {
            currentUid = 'second-user';
          } else {
            identity.beginTransition();
          }
          throw StateError('platform failed after session changed');
        },
      );
      expect(accepted, isFalse);
      expect(appAttempts, 0);
    });
  }

  test('native social activity prefers one in-app presentation', () async {
    final calls = <String>[];
    final accepted = await presentForegroundNotificationSurface(
      isWeb: false,
      isCall: false,
      presentInApp: () {
        calls.add('app');
        return true;
      },
      presentNative: () async => calls.add('native'),
    );
    expect(accepted, isTrue);
    expect(calls, ['app']);
  });

  test('unready app host preserves native fallback', () async {
    final calls = <String>[];
    final accepted = await presentForegroundNotificationSurface(
      isWeb: false,
      isCall: false,
      presentInApp: () {
        calls.add('app');
        return false;
      },
      presentNative: () async => calls.add('native'),
    );
    expect(accepted, isTrue);
    expect(calls, ['app', 'native']);
  });

  test('throwing app host still permits native fallback', () async {
    var nativeCalls = 0;
    expect(
      await presentForegroundNotificationSurface(
        isWeb: false,
        isCall: false,
        presentInApp: () => throw StateError('unmounted'),
        presentNative: () async => nativeCalls++,
      ),
      isTrue,
    );
    expect(nativeCalls, 1);
  });

  test('calls stay native-first without a second app alert', () async {
    final calls = <String>[];
    final accepted = await presentForegroundNotificationSurface(
      isWeb: false,
      isCall: true,
      presentInApp: () {
        calls.add('app');
        return true;
      },
      presentNative: () async => calls.add('native'),
    );
    expect(accepted, isTrue);
    expect(calls, ['native']);
  });

  test('failed native call alert keeps the existing in-app fallback', () async {
    final calls = <String>[];
    final accepted = await presentForegroundNotificationSurface(
      isWeb: false,
      isCall: true,
      presentInApp: () {
        calls.add('app');
        return true;
      },
      presentNative: () async {
        calls.add('native');
        throw StateError('platform unavailable');
      },
    );
    expect(accepted, isTrue);
    expect(calls, ['native', 'app']);
  });

  for (final isCall in [false, true]) {
    test('web uses only in-app surface (call: $isCall)', () async {
      var nativeCalls = 0;
      final accepted = await presentForegroundNotificationSurface(
        isWeb: true,
        isCall: isCall,
        presentInApp: () => true,
        presentNative: () async => nativeCalls++,
      );
      expect(accepted, isTrue);
      expect(nativeCalls, 0);
    });
  }

  test('unready web host releases rather than consuming delivery', () async {
    final outcomes = <bool>[];
    final accepted = await presentForegroundNotificationDecision(
      decision: ForegroundNotificationClaimDecision.claimed(
        ForegroundNotificationClaim(outcomes.add),
      ),
      present: () => presentForegroundNotificationSurface(
        isWeb: true,
        isCall: false,
        presentInApp: () => false,
        presentNative: () async => fail('web must never use native fallback'),
      ),
    );
    expect(accepted, isFalse);
    expect(outcomes, [false]);
  });

  test('both failed surfaces release the reserved event', () async {
    final outcomes = <bool>[];
    var attempts = 0;
    final accepted = await presentForegroundNotificationDecision(
      decision: ForegroundNotificationClaimDecision.claimed(
        ForegroundNotificationClaim(outcomes.add),
      ),
      present: () => presentForegroundNotificationSurface(
        isWeb: false,
        isCall: false,
        presentInApp: () {
          attempts++;
          return false;
        },
        presentNative: () async => throw StateError('platform unavailable'),
      ),
    );
    expect(accepted, isFalse);
    expect(outcomes, [false]);
    expect(attempts, 2);
  });

  test('host can recover during failed native presentation', () async {
    var ready = false;
    final accepted = await presentForegroundNotificationSurface(
      isWeb: false,
      isCall: false,
      presentInApp: () => ready,
      presentNative: () async {
        ready = true;
        throw StateError('platform unavailable');
      },
    );
    expect(accepted, isTrue);
  });

  test('arbiter veto calls neither surface', () async {
    var calls = 0;
    final accepted = await presentForegroundNotificationDecision(
      decision: const ForegroundNotificationClaimDecision.skip(),
      present: () => presentForegroundNotificationSurface(
        isWeb: false,
        isCall: false,
        presentInApp: () {
          calls++;
          return true;
        },
        presentNative: () async => calls++,
      ),
    );
    expect(accepted, isFalse);
    expect(calls, 0);
  });
}
