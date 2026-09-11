// What happens when a signed URL runs out mid-session.
//
// A Reel may be five minutes long; the signature that plays it is minted for
// a fixed window. The client therefore has to (a) stop handing out a grant
// before a player would fail on it, (b) be able to re-mint one on demand
// without losing the URL it already has if that fails, and (c) not accumulate
// signed URLs for the life of the process.

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/data/services/reel_service.dart';

MockFirebaseAuth _auth() => MockFirebaseAuth(
  mockUser: MockUser(uid: 'viewer-1', isEmailVerified: true),
  signedIn: true,
);

int _millisFromNow(Duration offset) =>
    DateTime.now().toUtc().add(offset).millisecondsSinceEpoch;

Map<Object?, Object?> _grant(String url, Duration ttl) => <Object?, Object?>{
  'schemaVersion': 2,
  'url': 'https://storage.googleapis.com/yovoice/$url',
  'expiresAtMillis': _millisFromNow(ttl),
  'generation': '7',
  'availabilityHours': 'permanent',
  'contentExpiresAtMillis': null,
};

void main() {
  setUp(() {
    ReelService.clearAllMediaAccessCaches();
    ReelService.debugResetInlineGrantSupport();
  });

  test('the refresh margin scales with the grant it protects', () {
    // Short signatures keep exactly the flat margin this client always had.
    expect(
      ReelService.debugGrantSafetyWindow(const Duration(seconds: 90)),
      ReelService.minGrantSafetyWindow,
    );
    // A five-minute Reel's grant gets a proportional margin.
    expect(
      ReelService.debugGrantSafetyWindow(const Duration(seconds: 300)),
      const Duration(seconds: 30),
    );
    // And it is capped, so a long grant is not thrown away early.
    expect(
      ReelService.debugGrantSafetyWindow(const Duration(minutes: 30)),
      ReelService.maxGrantSafetyWindow,
    );
    // A grant that arrives already dead still reports the floor rather than
    // a negative window.
    expect(
      ReelService.debugGrantSafetyWindow(Duration.zero),
      ReelService.minGrantSafetyWindow,
    );
  });

  test('a grant inside its margin is re-minted rather than replayed', () async {
    var calls = 0;
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        calls += 1;
        expect(name, 'getReelMediaAccessV2');
        return _grant('short-$calls.mp4', const Duration(seconds: 10));
      },
    );

    final first = await service.resolveMediaUri('reel_a');
    expect(first.path, endsWith('short-1.mp4'));
    // 10 s of life is inside the 15 s floor, so it is never handed out again.
    expect(service.cachedMediaUri('reel_a'), isNull);
    final second = await service.resolveMediaUri('reel_a');
    expect(second.path, endsWith('short-2.mp4'));
    expect(calls, 2);
  });

  test('a grant outside its margin is reused', () async {
    var calls = 0;
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        calls += 1;
        return _grant('long-$calls.mp4', const Duration(minutes: 5));
      },
    );

    final first = await service.resolveMediaUri('reel_a');
    expect(service.cachedMediaUri('reel_a'), first);
    expect(await service.resolveMediaUri('reel_a'), first);
    expect(calls, 1);
  });

  test('forceRefresh mints a new grant and adopts it', () async {
    var calls = 0;
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        calls += 1;
        return _grant('refresh-$calls.mp4', const Duration(minutes: 5));
      },
    );

    final first = await service.resolveMediaUri('reel_a');
    final refreshed = await service.resolveMediaUri(
      'reel_a',
      forceRefresh: true,
    );
    expect(calls, 2);
    expect(refreshed, isNot(first));
    expect(refreshed.path, endsWith('refresh-2.mp4'));
    // The recovery URL is what the next reader gets, without another call.
    expect(service.cachedMediaUri('reel_a'), refreshed);
    expect(calls, 2);
  });

  test('a failed refresh leaves the working URL in place', () async {
    var calls = 0;
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        calls += 1;
        if (calls > 1) throw StateError('the mint failed');
        return _grant('kept.mp4', const Duration(minutes: 5));
      },
    );

    final first = await service.resolveMediaUri('reel_a');
    await expectLater(
      service.resolveMediaUri('reel_a', forceRefresh: true),
      throwsStateError,
    );
    // Losing a refresh must not also lose the URL the player is using.
    expect(service.cachedMediaUri('reel_a'), first);
  });

  test('a concurrent forced refresh joins the mint already running', () async {
    var calls = 0;
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        calls += 1;
        await Future<void>.delayed(Duration.zero);
        return _grant('joined-$calls.mp4', const Duration(minutes: 5));
      },
    );

    final results = await Future.wait(<Future<Uri>>[
      service.resolveMediaUri('reel_a'),
      service.resolveMediaUri('reel_a', forceRefresh: true),
    ]);
    expect(calls, 1);
    expect(results.first, results.last);
  });

  test(
    'the signed-URL cache is bounded and evicts the shortest-lived',
    () async {
      final service = ReelService(
        auth: _auth(),
        callableInvoker: (name, payload) async {
          final id = payload['reelId']! as String;
          final index = int.parse(id.split('_').last);
          // Later ids get longer lives, so eviction order is observable.
          return _grant('$id.mp4', Duration(minutes: 5 + index));
        },
      );

      const total = ReelService.maxCachedMediaGrants + 6;
      for (var i = 0; i < total; i++) {
        await service.resolveMediaUri('reel_$i');
      }

      expect(
        ReelService.debugCachedGrantCount,
        ReelService.maxCachedMediaGrants,
        reason: 'a long session must not hoard signed URLs',
      );
      expect(service.cachedMediaUri('reel_0'), isNull);
      expect(service.cachedMediaUri('reel_5'), isNull);
      expect(service.cachedMediaUri('reel_6'), isNotNull);
      expect(service.cachedMediaUri('reel_${total - 1}'), isNotNull);
    },
  );

  test('expired entries are dropped when the cache is written', () async {
    var ttl = const Duration(seconds: 1);
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async =>
          _grant('${payload['reelId']}.mp4', ttl),
    );

    // A grant that expires almost immediately still answers its own caller —
    // the URL is valid right now — but must not survive in the cache.
    await service.resolveMediaUri('reel_stale');
    expect(ReelService.debugCachedGrantCount, 1);

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    ttl = const Duration(minutes: 5);
    await service.resolveMediaUri('reel_fresh');

    expect(ReelService.debugCachedGrantCount, 1);
    expect(service.cachedMediaUri('reel_stale'), isNull);
    expect(service.cachedMediaUri('reel_fresh'), isNotNull);
  });

  test('a malformed reel id never throws out of the synchronous read', () {
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async => throw StateError('unreachable'),
    );
    expect(service.cachedMediaUri('reel/escape'), isNull);
    expect(service.cachedMediaUri(''), isNull);
  });
}
