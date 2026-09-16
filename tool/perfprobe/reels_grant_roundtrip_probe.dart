// MEASUREMENT PROBE (not a regression test): counts the callable round trips
// the Reels data layer issues for one tab open plus four swipes, and times how
// long the first card's media URL takes to become known.
//
//   flutter test tool/perfprobe/reels_grant_roundtrip_probe.dart
//
// Three scenarios, all against a fake transport:
//   1. "current backend"  — listReelsV2 accepts only {cursor, limit}; an
//      unknown input key is `invalid-argument`, exactly as
//      functions/integrity/guards.js requireExactInput behaves today. No
//      leading-media warm (the pre-change client shape).
//   2. "current backend + warm" — same server, client warms the first item.
//   3. "inline-grant backend" — accepts the optional `mediaGrants` flag and
//      returns `mediaGrant` on the first two items.
//
// COUNTS are exact. WALL CLOCK is counts multiplied by an injected, uniform
// round-trip model (_rtt below) plus a modelled card-mount delay; it is not a
// measurement of production latency and is labelled as such in the output.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';

/// Injected uniform round-trip time for every callable.
const Duration _rtt = Duration(milliseconds: 120);

/// Modelled delay between the feed page arriving and the first card mounting
/// and asking for its URL. This is the window the leading-media warm covers.
const Duration _cardMountDelay = Duration(milliseconds: 30);

const int _cardsViewed = 5; // first card + four swipes

void main() {
  test('round trips: tab open + 4 swipes', () async {
    final report = <String>[];
    for (final scenario in <_Scenario>[
      _Scenario('current backend       ', inlineCapable: false, warm: false),
      _Scenario('current backend + warm', inlineCapable: false, warm: true),
      _Scenario('inline-grant backend  ', inlineCapable: true, warm: true),
    ]) {
      ReelService.clearAllMediaAccessCaches();
      // ignore: invalid_use_of_visible_for_testing_member
      ReelService.debugResetInlineGrantSupport();
      final calls = <String>[];
      final service = ReelService(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
        ),
        callableInvoker: (name, payload) async => _respond(
          name,
          payload,
          calls,
          inlineCapable: scenario.inlineCapable,
        ),
      );

      final clock = Stopwatch()..start();
      final page = await service.fetchFeed(warmLeadingMedia: scenario.warm);
      final listDoneMs = clock.elapsedMilliseconds;

      // What the card does: mount, then ask for its URL.
      await Future<void>.delayed(_cardMountDelay);
      final readyAtMount = service.cachedMediaUri(page.items.first.id) != null;
      await service.resolveMediaUri(page.items.first.id);
      final firstUriMs = clock.elapsedMilliseconds;

      // Four swipes.
      for (var i = 1; i < _cardsViewed && i < page.items.length; i++) {
        await service.resolveMediaUri(page.items[i].id);
      }

      // A second page load, to show what the flag costs in steady state: the
      // unsupported-flag probe is once per process, not once per page.
      final beforeSecondPage = calls.length;
      await service.fetchFeed(warmLeadingMedia: scenario.warm);
      final secondPageCalls = calls.length - beforeSecondPage;

      final list = calls.where((c) => c.startsWith('listReelsV2')).length;
      final grants = calls
          .where((c) => c.startsWith('getReelMediaAccessV2'))
          .length;
      report
        ..add(
          '${scenario.name}  listReelsV2=$list  getReelMediaAccessV2=$grants  '
          'total=${calls.length}',
        )
        ..add(
          '    feed page at ${listDoneMs}ms; first card URL at ${firstUriMs}ms '
          '(modelled); URL already in hand when the card mounted: '
          '${readyAtMount ? 'YES' : 'no'}; '
          'a later page costs $secondPageCalls call(s)',
        )
        ..add('    ${calls.join('\n    ')}');
    }
    // ignore: avoid_print
    print(
      '\n===== REELS GRANT ROUND TRIPS ($_cardsViewed cards viewed, '
      'modelled RTT ${_rtt.inMilliseconds}ms) =====\n'
      '${report.join('\n')}\n=====\n',
    );
  });
}

class _Scenario {
  const _Scenario(this.name, {required this.inlineCapable, required this.warm});
  final String name;
  final bool inlineCapable;
  final bool warm;
}

Future<Map<Object?, Object?>> _respond(
  String name,
  Map<String, Object?> payload,
  List<String> calls, {
  required bool inlineCapable,
}) async {
  final wantsGrants = payload.containsKey('mediaGrants');
  calls.add(
    '$name${wantsGrants ? '(mediaGrants)' : ''}'
    '${name == 'getReelMediaAccessV2' ? '(${payload['reelId']})' : ''}',
  );
  await Future<void>.delayed(_rtt);
  if (name == 'listReelsV2') {
    if (wantsGrants && !inlineCapable) {
      // requireExactInput(request.data, ["cursor", "limit"], ["limit"]).
      throw FirebaseFunctionsException(
        code: 'invalid-argument',
        message: 'Unsupported field: mediaGrants.',
      );
    }
    return <Object?, Object?>{
      'schemaVersion': 2,
      'items': <Object?>[
        for (var i = 0; i < 10; i++)
          _reelWire(i, grant: wantsGrants && inlineCapable && i < 2),
      ],
      'nextCursor': null,
    };
  }
  if (name == 'getReelMediaAccessV2') {
    return <Object?, Object?>{
      'schemaVersion': 2,
      'url': 'https://storage.googleapis.com/yovoice/${payload['reelId']}.mp4',
      'expiresAtMillis': DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 90))
          .millisecondsSinceEpoch,
      'generation': '7',
      'availabilityHours': 'permanent',
      'contentExpiresAtMillis': null,
    };
  }
  throw StateError('Unexpected callable $name');
}

Map<String, Object?> _reelWire(int index, {required bool grant}) {
  final millis = 1725000000000 - index;
  return <String, Object?>{
    'id': 'reel_feed_$index',
    'authorId': 'creator_$index',
    'authorName': 'Creator $index',
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
    'sortKey': '${millis}_reel_feed_$index',
    'availability': <String, Object?>{
      'schemaVersion': 1,
      'availabilityHours': 'permanent',
      'expiresAtMillis': null,
    },
    if (grant)
      'mediaGrant': <String, Object?>{
        'url': 'https://storage.googleapis.com/yovoice/reel_feed_$index.mp4',
        'expiresAtMillis': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 3))
            .millisecondsSinceEpoch,
        'generation': '7',
      },
  };
}
