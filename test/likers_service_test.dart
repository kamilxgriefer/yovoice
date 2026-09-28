import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/likers/data/models/likers_target.dart';
import 'package:yovoice/features/likers/data/services/likers_service.dart';

import 'support/likers_fixtures.dart';

void main() {
  group('LikersService target mapping (never a limit)', () {
    final cases = <(LikersTarget, String, Map<String, Object?>)>[
      (
        const VoiceMomentLikersTarget('m1'),
        'listVoiceMomentLikersV1',
        {'momentId': 'm1'},
      ),
      (
        const VoiceMomentCommentLikersTarget('m1', 'c1'),
        'listVoiceMomentLikersV1',
        {'momentId': 'm1', 'commentId': 'c1'},
      ),
      (const ReelLikersTarget('r1'), 'listReelLikersV1', {'reelId': 'r1'}),
      (
        const ReelCommentLikersTarget('r1', 'c1'),
        'listReelLikersV1',
        {'reelId': 'r1', 'commentId': 'c1'},
      ),
      (
        const ServerMessageReactorsTarget('s1', 'ch1', 'msg1'),
        'listServerChannelMessageReactorsV1',
        {'serverId': 's1', 'channelId': 'ch1', 'messageId': 'msg1'},
      ),
      (
        const ServerMessageReactorsTarget('s1', 'ch1', 'msg1', emoji: '❤️'),
        'listServerChannelMessageReactorsV1',
        {
          'serverId': 's1',
          'channelId': 'ch1',
          'messageId': 'msg1',
          'emoji': '❤️',
        },
      ),
    ];

    for (final (target, callable, payload) in cases) {
      test('$callable ${payload.keys.join(',')}', () async {
        final script = ScriptedLikers([pageWire(const []), pageWire(const [])]);
        await script.service.load(target);
        await script.service.load(target, cursor: kTestCursor);
        expect(script.calls.map((call) => call.name), [callable, callable]);
        expect(script.calls.first.payload, payload);
        expect(script.calls.last.payload, {...payload, 'cursor': kTestCursor});
        for (final call in script.calls) {
          expect(call.payload.containsKey('limit'), isFalse);
        }
      });
    }

    test('withEmoji switches the filter and clears it', () {
      const base = ServerMessageReactorsTarget('s', 'c', 'm');
      expect(base.withEmoji('👍').emoji, '👍');
      expect(base.withEmoji('👍').withEmoji(null), base);
    });
  });

  group('LikersService error mapping (spec §3.0 envelope)', () {
    Future<LikersFailure> failureOf(Object error, {String? cursor}) async {
      final script = ScriptedLikers([error]);
      try {
        await script.service.load(
          const VoiceMomentLikersTarget('m1'),
          cursor: cursor,
        );
      } on LikersException catch (exception) {
        return exception.failure;
      }
      fail('Expected a LikersException');
    }

    test('likersNotEnabled -> notEnabled', () async {
      expect(
        await failureOf(
          functionsError('failed-precondition', reason: 'likersNotEnabled'),
        ),
        LikersFailure.notEnabled,
      );
    });

    test('likersAccessRequired -> accessRequired', () async {
      expect(
        await failureOf(
          functionsError('failed-precondition', reason: 'likersAccessRequired'),
        ),
        LikersFailure.accessRequired,
      );
    });

    test('permission-denied and not-found -> unavailable', () async {
      expect(
        await failureOf(functionsError('permission-denied')),
        LikersFailure.unavailable,
      );
      expect(
        await failureOf(functionsError('not-found')),
        LikersFailure.unavailable,
      );
    });

    test('resource-exhausted -> rateLimited', () async {
      expect(
        await failureOf(functionsError('resource-exhausted')),
        LikersFailure.rateLimited,
      );
    });

    test(
      'invalid-argument -> invalidCursor only when a cursor was sent',
      () async {
        expect(
          await failureOf(
            functionsError('invalid-argument'),
            cursor: kTestCursor,
          ),
          LikersFailure.invalidCursor,
        );
        expect(
          await failureOf(functionsError('invalid-argument')),
          LikersFailure.network,
        );
      },
    );

    test(
      'other failures, a reasonless precondition and junk -> network',
      () async {
        expect(
          await failureOf(functionsError('failed-precondition')),
          LikersFailure.network,
        );
        expect(
          await failureOf(functionsError('unavailable')),
          LikersFailure.network,
        );
        expect(await failureOf(StateError('boom')), LikersFailure.network);
      },
    );

    test('a malformed response -> network', () async {
      final script = ScriptedLikers([
        {'schemaVersion': 1},
      ]);
      await expectLater(
        script.service.load(const ReelLikersTarget('r1')),
        throwsA(
          isA<LikersException>().having(
            (e) => e.failure,
            'failure',
            LikersFailure.network,
          ),
        ),
      );
    });
  });
}
