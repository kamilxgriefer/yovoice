// The inline media-grant path: `listReelsV2` may carry a pre-minted signed
// URL per item so the first video frame does not wait on a second callable.
//
// Two properties matter more than the saved round trip and are asserted here:
//   * a grant this build cannot fully validate must degrade to the dedicated
//     `getReelMediaAccessV2` callable, never empty the feed page;
//   * a backend that predates the `mediaGrants` input flag must keep working,
//     because installed clients cannot be deployed in a chosen order.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';

MockFirebaseAuth _auth({String uid = 'viewer-1'}) => MockFirebaseAuth(
  mockUser: MockUser(uid: uid, isEmailVerified: true),
  signedIn: true,
);

int _millisFromNow(Duration offset) =>
    DateTime.now().toUtc().add(offset).millisecondsSinceEpoch;

Map<String, Object?> _grantWire({
  String url = 'https://storage.googleapis.com/yovoice/reel.mp4?sig=a',
  Object? expiresAtMillis,
  Object? generation = '7',
}) => <String, Object?>{
  'url': url,
  'expiresAtMillis':
      expiresAtMillis ?? _millisFromNow(const Duration(minutes: 3)),
  'generation': generation,
};

Map<String, Object?> _feedItem(
  String id, {
  Object? mediaGrant,
  Map<String, Object?>? availability,
}) {
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
    'availability':
        availability ??
        <String, Object?>{
          'schemaVersion': 1,
          'availabilityHours': 'permanent',
          'expiresAtMillis': null,
        },
    'mediaGrant': ?mediaGrant,
  };
}

Map<Object?, Object?> _feed(List<Map<String, Object?>> items) =>
    <Object?, Object?>{'schemaVersion': 2, 'items': items, 'nextCursor': null};

Map<Object?, Object?> _mintedGrant(String reelId) => <Object?, Object?>{
  'schemaVersion': 2,
  'url': 'https://storage.googleapis.com/yovoice/$reelId-minted.mp4',
  'expiresAtMillis': _millisFromNow(const Duration(seconds: 90)),
  'generation': '7',
  'availabilityHours': 'permanent',
  'contentExpiresAtMillis': null,
};

/// Lets the fire-and-forget leading-media warm reach the fake transport before
/// a test counts calls.
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

  test(
    'an inline grant answers the first card with no second callable',
    () async {
      final calls = <String>[];
      final service = ReelService(
        auth: _auth(),
        callableInvoker: (name, payload) async {
          calls.add(name);
          if (name == 'listReelsV2') {
            expect(payload['mediaGrants'], isTrue);
            return _feed(<Map<String, Object?>>[
              _feedItem('reel_a', mediaGrant: _grantWire()),
              _feedItem('reel_b', mediaGrant: _grantWire()),
              _feedItem('reel_c'),
            ]);
          }
          return _mintedGrant(payload['reelId']! as String);
        },
      );

      final page = await service.fetchFeed();
      await _settle();

      expect(page.items, hasLength(3));
      expect(service.cachedMediaUri('reel_a'), isNotNull);
      expect(service.cachedMediaUri('reel_b'), isNotNull);
      expect(service.cachedMediaUri('reel_c'), isNull);
      // The leading item was already covered, so the warm issued nothing.
      expect(calls, <String>['listReelsV2']);

      final uri = await service.resolveMediaUri('reel_a');
      expect(uri.toString(), contains('reel.mp4'));
      expect(calls, <String>['listReelsV2']);
    },
  );

  test('the media grant is bound to the item it arrived with', () async {
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async => name == 'listReelsV2'
          ? _feed(<Map<String, Object?>>[
              _feedItem('reel_a', mediaGrant: _grantWire()),
            ])
          : _mintedGrant(payload['reelId']! as String),
    );
    final page = await service.fetchFeed(warmLeadingMedia: false);
    final grant = page.items.single.mediaGrant;
    expect(grant, isNotNull);
    expect(grant!.generation, page.items.single.media.generation);
    expect(grant.uri.scheme, 'https');
    expect(grant.uri.host, 'storage.googleapis.com');
  });

  group('a grant this build cannot validate degrades instead of failing', () {
    final rejected = <String, Object?>{
      'not an object': 'https://storage.googleapis.com/x.mp4',
      'an unknown key': <String, Object?>{
        ..._grantWire(),
        'downloadToken': 'x',
      },
      'a missing key': <String, Object?>{
        'url': 'https://storage.googleapis.com/yovoice/reel.mp4',
        'generation': '7',
      },
      'a plaintext url': _grantWire(
        url: 'http://storage.googleapis.com/yovoice/reel.mp4',
      ),
      'a foreign host': _grantWire(url: 'https://evil.example.com/reel.mp4'),
      'an embedded credential': _grantWire(
        url: 'https://a:b@storage.googleapis.com/yovoice/reel.mp4',
      ),
      'a non-default port': _grantWire(
        url: 'https://storage.googleapis.com:8443/yovoice/reel.mp4',
      ),
      'a generation the descriptor does not name': _grantWire(generation: '99'),
      'a non-string generation': _grantWire(generation: 7),
      'a non-positive expiry': _grantWire(expiresAtMillis: 0),
      'a non-integer expiry': _grantWire(expiresAtMillis: '1725000000000'),
      'an out-of-range expiry': _grantWire(expiresAtMillis: 8640000000000001),
      'a maximum integer expiry': _grantWire(
        expiresAtMillis: 9223372036854775807,
      ),
    };

    for (final entry in rejected.entries) {
      test('${entry.key} is ignored', () async {
        final calls = <String>[];
        final service = ReelService(
          auth: _auth(),
          callableInvoker: (name, payload) async {
            calls.add(name);
            return name == 'listReelsV2'
                ? _feed(<Map<String, Object?>>[
                    _feedItem('reel_a', mediaGrant: entry.value),
                    _feedItem('reel_b'),
                  ])
                : _mintedGrant(payload['reelId']! as String);
          },
        );

        // The page still renders every item — a bad hint is not data loss.
        final page = await service.fetchFeed(warmLeadingMedia: false);
        expect(page.items.map((reel) => reel.id), <String>['reel_a', 'reel_b']);
        expect(page.items.first.mediaGrant, isNull);
        expect(service.cachedMediaUri('reel_a'), isNull);

        final uri = await service.resolveMediaUri('reel_a');
        expect(uri.toString(), contains('minted'));
        expect(calls, <String>['listReelsV2', 'getReelMediaAccessV2']);
      });
    }
  });

  test('a grant may not outlive the content it points at', () async {
    final contentExpiry = _millisFromNow(const Duration(minutes: 2));
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async => name == 'listReelsV2'
          ? _feed(<Map<String, Object?>>[
              _feedItem(
                'reel_timed',
                availability: <String, Object?>{
                  'schemaVersion': 2,
                  'availabilityHours': 24,
                  'expiresAtMillis': contentExpiry,
                },
                mediaGrant: _grantWire(expiresAtMillis: contentExpiry + 1),
              ),
            ])
          : _mintedGrant(payload['reelId']! as String),
    );

    final page = await service.fetchFeed(warmLeadingMedia: false);
    expect(page.items.single.mediaGrant, isNull);
    expect(service.cachedMediaUri('reel_timed'), isNull);
  });

  test('a grant already inside its refresh margin is not adopted', () async {
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async => name == 'listReelsV2'
          ? _feed(<Map<String, Object?>>[
              _feedItem(
                'reel_a',
                mediaGrant: _grantWire(
                  expiresAtMillis: _millisFromNow(const Duration(seconds: 5)),
                ),
              ),
            ])
          : _mintedGrant(payload['reelId']! as String),
    );

    final page = await service.fetchFeed(warmLeadingMedia: false);
    // Parsed — it is well formed — but too close to expiry to hand out.
    expect(page.items.single.mediaGrant, isNotNull);
    expect(service.cachedMediaUri('reel_a'), isNull);
  });

  test('an inline grant is scoped to the account that received it', () async {
    Future<Map<Object?, Object?>> respond(
      String name,
      Map<String, Object?> payload,
    ) async => name == 'listReelsV2'
        ? _feed(<Map<String, Object?>>[
            _feedItem('reel_a', mediaGrant: _grantWire()),
          ])
        : _mintedGrant(payload['reelId']! as String);

    final first = ReelService(
      auth: _auth(uid: 'viewer-1'),
      callableInvoker: respond,
    );
    await first.fetchFeed(warmLeadingMedia: false);
    expect(first.cachedMediaUri('reel_a'), isNotNull);

    final second = ReelService(
      auth: _auth(uid: 'viewer-2'),
      callableInvoker: respond,
    );
    expect(second.cachedMediaUri('reel_a'), isNull);

    // And the privacy boundary clear drops it exactly like a minted grant.
    ReelService.clearAllMediaAccessCaches();
    expect(first.cachedMediaUri('reel_a'), isNull);
  });

  test(
    'a backend without the mediaGrants flag is retried once and remembered',
    () async {
      final payloads = <Map<String, Object?>>[];
      final service = ReelService(
        auth: _auth(),
        callableInvoker: (name, payload) async {
          payloads.add(payload);
          if (payload.containsKey('mediaGrants')) {
            throw FirebaseFunctionsException(
              code: 'invalid-argument',
              message: 'Unsupported field: mediaGrants.',
            );
          }
          return _feed(<Map<String, Object?>>[_feedItem('reel_a')]);
        },
      );

      final first = await service.fetchFeed(warmLeadingMedia: false);
      expect(first.items, hasLength(1));
      expect(payloads, hasLength(2));
      expect(payloads.first.containsKey('mediaGrants'), isTrue);
      expect(payloads.last.containsKey('mediaGrants'), isFalse);
      expect(ReelService.debugInlineGrantsSupported, isFalse);

      // The probe is once per process, not once per page.
      final second = await service.fetchFeed(warmLeadingMedia: false);
      expect(second.items, hasLength(1));
      expect(payloads, hasLength(3));
      expect(payloads.last.containsKey('mediaGrants'), isFalse);
    },
  );

  test('an invalid-argument that is not the flag is reported', () async {
    var calls = 0;
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        calls += 1;
        throw FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'cursor is invalid.',
        );
      },
    );

    await expectLater(
      service.fetchFeed(warmLeadingMedia: false),
      throwsA(
        isA<FirebaseFunctionsException>().having(
          (error) => error.message,
          'message',
          'cursor is invalid.',
        ),
      ),
    );
    expect(calls, 2, reason: 'one flagged attempt plus one unflagged probe');
    expect(
      ReelService.debugInlineGrantsSupported,
      isTrue,
      reason: 'the flag was never proven to be the problem',
    );
  });

  test(
    'once the flag is proven accepted, a rejected request costs one call',
    () async {
      var calls = 0;
      var poisoned = false;
      final service = ReelService(
        auth: _auth(),
        callableInvoker: (name, payload) async {
          calls += 1;
          if (poisoned) {
            throw FirebaseFunctionsException(
              code: 'invalid-argument',
              message: 'cursor is invalid.',
            );
          }
          return _feed(<Map<String, Object?>>[_feedItem('reel_a')]);
        },
      );

      await service.fetchFeed(warmLeadingMedia: false);
      expect(calls, 1);

      // A cursor the backend refuses must not double every retry for the
      // rest of the session just because the flag was once in question.
      poisoned = true;
      for (var attempt = 0; attempt < 3; attempt++) {
        await expectLater(
          service.fetchFeed(
            cursor: '1725000000000_bad',
            warmLeadingMedia: false,
          ),
          throwsA(isA<FirebaseFunctionsException>()),
        );
      }
      expect(calls, 4);
    },
  );

  test('a transport failure is not retried', () async {
    var calls = 0;
    final service = ReelService(
      auth: _auth(),
      callableInvoker: (name, payload) async {
        calls += 1;
        throw FirebaseFunctionsException(
          code: 'unavailable',
          message: 'offline',
        );
      },
    );

    await expectLater(
      service.fetchFeed(warmLeadingMedia: false),
      throwsA(isA<FirebaseFunctionsException>()),
    );
    expect(calls, 1);
  });
}
