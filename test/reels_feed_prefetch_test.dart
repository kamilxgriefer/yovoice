// Prefetch rules for the Reels feed.
//
// The point of prefetching is to move a round trip earlier, not to add one.
// These tests pin the "does not fetch what it will not use" side of that:
// nothing speculative is issued when a usable grant is already in hand, a
// second page does not warm a card nobody is looking at, and a speculative
// failure never surfaces as an error.

import 'dart:async';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';

MockFirebaseAuth _auth() => MockFirebaseAuth(
  mockUser: MockUser(uid: 'viewer-1', isEmailVerified: true),
  signedIn: true,
);

int _millisFromNow(Duration offset) =>
    DateTime.now().toUtc().add(offset).millisecondsSinceEpoch;

Map<String, Object?> _feedItem(String id, {bool grant = false}) {
  const millis = 1725000000000;
  return <String, Object?>{
    'id': id,
    'authorId': 'creator_$id',
    'authorName': 'Creator $id',
    'media': <String, Object?>{
      'kind': 'video',
      'contentType': 'video/mp4',
      'size': 4096,
      'generation': '7',
      'durationMs': 10000,
    },
    'backingAudio': null,
    'composition': const ReelComposition(
      trimStartMs: 0,
      trimEndMs: 10000,
    ).toWire(),
    'publishedAtMillis': millis,
    'sortKey': '${millis}_$id',
    'availability': <String, Object?>{
      'schemaVersion': 1,
      'availabilityHours': 'permanent',
      'expiresAtMillis': null,
    },
    if (grant)
      'mediaGrant': <String, Object?>{
        'url': 'https://storage.googleapis.com/yovoice/$id.mp4',
        'expiresAtMillis': _millisFromNow(const Duration(minutes: 3)),
        'generation': '7',
      },
  };
}

Map<Object?, Object?> _feed(List<Map<String, Object?>> items, {String? next}) =>
    <Object?, Object?>{'schemaVersion': 2, 'items': items, 'nextCursor': next};

Map<Object?, Object?> _mintedGrant(String reelId) => <Object?, Object?>{
  'schemaVersion': 2,
  'url': 'https://storage.googleapis.com/yovoice/$reelId-minted.mp4',
  'expiresAtMillis': _millisFromNow(const Duration(minutes: 5)),
  'generation': '7',
  'availabilityHours': 'permanent',
  'contentExpiresAtMillis': null,
};

Future<void> _settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUp(() {
    ReelService.clearAllMediaAccessCaches();
    ReelService.debugResetInlineGrantSupport();
  });

  test('the first page warms the card the viewer is about to see', () async {
    final calls = <String>[];
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        calls.add(
          name == 'listReelsV2'
              ? 'list(${payload['cursor']})'
              : 'grant(${payload['reelId']})',
        );
        return name == 'listReelsV2'
            ? _feed(<Map<String, Object?>>[
                _feedItem('reel_a'),
                _feedItem('reel_b'),
                _feedItem('reel_c'),
              ])
            : _mintedGrant(payload['reelId']! as String);
      },
    );

    await service.fetchFeed();
    await _settle();

    // Exactly one speculative mint, for the leading card only.
    expect(calls, <String>['list(null)', 'grant(reel_a)']);
    expect(service.cachedMediaUri('reel_a'), isNotNull);
    expect(service.cachedMediaUri('reel_b'), isNull);
  });

  test('the warm is the same round trip, not an extra one', () async {
    var grants = 0;
    final gate = Completer<void>();
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        if (name == 'listReelsV2') {
          return _feed(<Map<String, Object?>>[_feedItem('reel_a')]);
        }
        grants += 1;
        await gate.future;
        return _mintedGrant(payload['reelId']! as String);
      },
    );

    final page = await service.fetchFeed();
    await _settle();
    // The card mounts while the warm is still in flight and joins it.
    final fromCard = service.resolveMediaUri(page.items.first.id);
    gate.complete();
    expect((await fromCard).path, endsWith('reel_a-minted.mp4'));
    expect(grants, 1);
  });

  test('an inlined grant makes the warm issue nothing at all', () async {
    final calls = <String>[];
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        calls.add(name);
        return name == 'listReelsV2'
            ? _feed(<Map<String, Object?>>[
                _feedItem('reel_a', grant: true),
                _feedItem('reel_b'),
              ])
            : _mintedGrant(payload['reelId']! as String);
      },
    );

    await service.fetchFeed();
    await _settle();
    expect(calls, <String>['listReelsV2']);
  });

  test('paging does not warm a card nobody is looking at', () async {
    final calls = <String>[];
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        calls.add(name == 'listReelsV2' ? 'list' : 'grant');
        return name == 'listReelsV2'
            ? _feed(<Map<String, Object?>>[_feedItem('reel_page2')])
            : _mintedGrant(payload['reelId']! as String);
      },
    );

    await service.fetchFeed(cursor: '1725000000000_reel_a');
    await _settle();
    expect(calls, <String>['list']);
  });

  test('an empty page warms nothing', () async {
    final calls = <String>[];
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        calls.add(name);
        return _feed(const <Map<String, Object?>>[]);
      },
    );

    final page = await service.fetchFeed();
    await _settle();
    expect(page.items, isEmpty);
    expect(calls, <String>['listReelsV2']);
  });

  test('warmLeadingMedia: false issues nothing speculative', () async {
    final calls = <String>[];
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        calls.add(name);
        return name == 'listReelsV2'
            ? _feed(<Map<String, Object?>>[_feedItem('reel_a')])
            : _mintedGrant(payload['reelId']! as String);
      },
    );

    await service.fetchFeed(warmLeadingMedia: false);
    await _settle();
    expect(calls, <String>['listReelsV2']);
  });

  test('prefetching a neighbour costs one call and only once', () async {
    var grants = 0;
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        grants += 1;
        return _mintedGrant(payload['reelId']! as String);
      },
    );

    await service.prefetchMediaUri('reel_b');
    expect(grants, 1);
    // Already cached: repeated prefetching a settled neighbour is free.
    await service.prefetchMediaUri('reel_b');
    await service.prefetchMediaUri('reel_b');
    expect(grants, 1);
    // And the card that later shows it does not pay either.
    await service.resolveMediaUri('reel_b');
    expect(grants, 1);
  });

  test('a concurrent prefetch and resolve share one mint', () async {
    var grants = 0;
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        grants += 1;
        await Future<void>.delayed(Duration.zero);
        return _mintedGrant(payload['reelId']! as String);
      },
    );

    final prefetch = service.prefetchMediaUri('reel_b');
    final resolve = service.resolveMediaUri('reel_b');
    await Future.wait(<Future<void>>[prefetch, resolve]);
    expect(grants, 1);
  });

  test('a failed prefetch is silent and leaves nothing cached', () async {
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async =>
          throw StateError('the mint failed'),
    );

    await service.prefetchMediaUri('reel_b');
    expect(service.cachedMediaUri('reel_b'), isNull);
  });

  test('a signed-out prefetch is silent', () async {
    final service = ReelService(
      auth: MockFirebaseAuth(),
      callableInvoker: (name, payload) async => throw StateError('unreachable'),
    );

    await service.prefetchMediaUri('reel_b');
    expect(service.cachedMediaUri('reel_b'), isNull);
  });

  test('backing audio prefetches independently of the video', () async {
    final assets = <String>[];
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        assets.add(payload['asset']! as String);
        return _mintedGrant(payload['reelId']! as String);
      },
    );

    await service.prefetchMediaUri('reel_b');
    await service.prefetchMediaUri('reel_b', asset: ReelAssetKind.backingAudio);
    expect(assets, <String>['media', 'backingAudio']);
    expect(
      service.cachedMediaUri('reel_b', asset: ReelAssetKind.backingAudio),
      isNotNull,
    );
  });
}
