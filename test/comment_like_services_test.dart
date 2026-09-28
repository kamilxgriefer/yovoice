// Comment-like services (ADR-230, spec §3.4-§3.6, §5.6): the probed
// `includeCommentLikes` view flag and the retry-stable toggles, for Voice
// Moments (MomentService) and Yeels (ReelService).

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/likers/data/models/comment_like.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';

import 'support/comment_like_fixtures.dart';

typedef _Call = ({String name, Map<String, Object?> payload});

void main() {
  group('MomentService', () {
    late List<Map<String, Object?>> viewRequests;
    late List<Map<String, Object?>> likeRequests;

    MomentService build({
      required Future<Map<Object?, Object?>> Function(Map<String, Object?>)
      view,
      Future<Object?> Function(Map<String, Object?>)? like,
    }) {
      viewRequests = <Map<String, Object?>>[];
      likeRequests = <Map<String, Object?>>[];
      return MomentService(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
        storage: MockFirebaseStorage(),
        readService: VoiceMomentReadService(
          viewInvoker: (request) {
            viewRequests.add(Map<String, Object?>.of(request));
            return view(request);
          },
        ),
        commentLikeInvoker: (request) {
          likeRequests.add(Map<String, Object?>.of(request));
          return like == null
              ? Future<Object?>.error(StateError('unexpected'))
              : like(request);
        },
      );
    }

    test('an unflagged read is byte-identical and learns nothing', () async {
      final service = build(view: (_) async => voiceViewWire());
      final view = await service.loadMomentView('m1');
      expect(viewRequests.single.containsKey('includeCommentLikes'), isFalse);
      expect(view.commentLikes, isNull);
      expect(service.commentLikeSupport.value, CommentLikeSupport.unknown);
    });

    test('a flagged read that is answered latches supported', () async {
      final service = build(
        view: (request) async => voiceViewWire(
          commentLikes: request['includeCommentLikes'] == true
              ? <Object?, Object?>{'c1': likeStateWire(2, liked: true)}
              : null,
        ),
      );
      final view = await service.loadMomentView(
        'm1',
        includeCommentLikes: true,
      );
      expect(viewRequests.single['includeCommentLikes'], isTrue);
      expect(
        view.commentLikes!['c1'],
        const CommentLikeState(likeCount: 2, callerLiked: true),
      );
      expect(service.commentLikeSupport.value, CommentLikeSupport.supported);
    });

    test('a refusal is verified by an unflagged replay, then never asked '
        'again', () async {
      final service = build(
        view: (request) async {
          if (request.containsKey('includeCommentLikes')) {
            throw callableError('invalid-argument');
          }
          return voiceViewWire();
        },
      );
      final view = await service.loadMomentView(
        'm1',
        includeCommentLikes: true,
      );
      expect(view.commentLikes, isNull);
      expect(viewRequests, hasLength(2));
      expect(viewRequests.last.containsKey('includeCommentLikes'), isFalse);
      expect(service.commentLikeSupport.value, CommentLikeSupport.unsupported);

      await service.loadMomentView('m1', includeCommentLikes: true);
      expect(viewRequests, hasLength(3));
      expect(viewRequests.last.containsKey('includeCommentLikes'), isFalse);
    });

    test('a refusal for the request itself teaches nothing', () async {
      final service = build(
        view: (_) async => throw callableError('invalid-argument'),
      );
      await expectLater(
        service.loadMomentView('m1', includeCommentLikes: true),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      expect(viewRequests, hasLength(2));
      expect(service.commentLikeSupport.value, CommentLikeSupport.unknown);
    });

    test(
      'once supported, invalid-argument is reported, not replayed',
      () async {
        var refuse = false;
        final service = build(
          view: (request) async {
            if (refuse) throw callableError('invalid-argument');
            return voiceViewWire(
              commentLikes: <Object?, Object?>{'c1': likeStateWire(0)},
            );
          },
        );
        await service.loadMomentView('m1', includeCommentLikes: true);
        refuse = true;
        await expectLater(
          service.loadMomentView('m1', includeCommentLikes: true),
          throwsA(isA<FirebaseFunctionsException>()),
        );
        expect(viewRequests, hasLength(2));
        expect(service.commentLikeSupport.value, CommentLikeSupport.supported);
      },
    );

    test(
      'setCommentLike sends the exact request and parses the answer',
      () async {
        final service = build(
          view: (_) async => voiceViewWire(),
          like: (request) async => <Object?, Object?>{
            'momentId': 'm1',
            'commentId': 'c1',
            'liked': true,
            'changed': true,
            'likeCount': 5,
          },
        );
        final result = await service.setCommentLike('m1', 'c1', liked: true);
        expect(result.likeCount, 5);
        expect(result.liked, isTrue);
        final request = likeRequests.single;
        expect(request.keys.toSet(), <String>{
          'momentId',
          'commentId',
          'liked',
          'requestId',
        });
        expect(request['momentId'], 'm1');
        expect(request['commentId'], 'c1');
        expect(request['liked'], isTrue);
        expect(request['requestId'], isA<String>());
        expect(
          service.debugCommentLikeRequestId('m1', 'c1', liked: true),
          isNull,
        );
      },
    );

    test('a failed toggle keeps its request id for the retry; success '
        'releases both directions', () async {
      var fail = true;
      final service = build(
        view: (_) async => voiceViewWire(),
        like: (request) async {
          if (fail) throw callableError('unavailable');
          return <Object?, Object?>{
            'momentId': 'm1',
            'commentId': 'c1',
            'liked': true,
            'changed': false,
            'likeCount': 1,
          };
        },
      );
      await expectLater(
        service.setCommentLike('m1', 'c1', liked: true),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      final kept = service.debugCommentLikeRequestId('m1', 'c1', liked: true);
      expect(kept, isNotNull);
      fail = false;
      await service.setCommentLike('m1', 'c1', liked: true);
      expect(likeRequests.map((request) => request['requestId']), <Object?>[
        kept,
        kept,
      ]);
      expect(
        service.debugCommentLikeRequestId('m1', 'c1', liked: true),
        isNull,
      );
    });

    test('both directions lost: the next like gets a fresh id, never the '
        'first like\'s replay', () async {
      var fail = true;
      final service = build(
        view: (_) async => voiceViewWire(),
        like: (request) async {
          if (fail) throw callableError('unavailable');
          return <Object?, Object?>{
            'momentId': 'm1',
            'commentId': 'c1',
            'liked': request['liked'],
            'changed': true,
            'likeCount': 1,
          };
        },
      );
      await expectLater(
        service.setCommentLike('m1', 'c1', liked: true),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      final firstLike = likeRequests.last['requestId'];
      await expectLater(
        service.setCommentLike('m1', 'c1', liked: false),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      // Sending the unlike dropped the like's held id.
      expect(
        service.debugCommentLikeRequestId('m1', 'c1', liked: true),
        isNull,
      );
      fail = false;
      await service.setCommentLike('m1', 'c1', liked: true);
      expect(likeRequests.last['requestId'], isNot(firstLike));
      expect(
        likeRequests.last['requestId'],
        isNot(likeRequests[1]['requestId']),
      );
    });

    test('a poisoned request id or a malformed answer is released', () async {
      var answer = 0;
      final service = build(
        view: (_) async => voiceViewWire(),
        like: (request) async {
          answer++;
          if (answer == 1) throw callableError('already-exists');
          return <Object?, Object?>{'momentId': 'm1'};
        },
      );
      await expectLater(
        service.setCommentLike('m1', 'c1', liked: false),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      expect(
        service.debugCommentLikeRequestId('m1', 'c1', liked: false),
        isNull,
      );
      await expectLater(
        service.setCommentLike('m1', 'c1', liked: false),
        throwsFormatException,
      );
      expect(
        service.debugCommentLikeRequestId('m1', 'c1', liked: false),
        isNull,
      );
      expect(
        likeRequests.first['requestId'],
        isNot(likeRequests.last['requestId']),
      );
    });
  });

  group('ReelService', () {
    late List<_Call> calls;

    ReelService build(
      Future<Map<Object?, Object?>> Function(
        String name,
        Map<String, Object?> payload,
      )
      respond,
    ) {
      calls = <_Call>[];
      return ReelService(
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
        ),
        callableInvoker: (name, payload) {
          calls.add((name: name, payload: Map<String, Object?>.of(payload)));
          return respond(name, payload);
        },
      );
    }

    List<Map<String, Object?>> views() => <Map<String, Object?>>[
      for (final call in calls)
        if (call.name == 'getReelViewV2') call.payload,
    ];

    test('an unflagged thread read never sends includeCommentLikes', () async {
      final service = build((_, _) async => reelViewWire());
      final view = await service.loadView('reel_1');
      expect(views().single.containsKey('includeCommentLikes'), isFalse);
      expect(views().single['commentTypes'], <String>['text', 'voice']);
      expect(view.commentLikes, isNull);
      expect(service.commentLikeSupport.value, CommentLikeSupport.unknown);
    });

    test('both flags answered: hearts and voice latch supported', () async {
      final service = build(
        (_, payload) async => reelViewWire(
          commentLikes: payload['includeCommentLikes'] == true
              ? <Object?, Object?>{'c1': likeStateWire(3)}
              : null,
        ),
      );
      final view = await service.loadView('reel_1', includeCommentLikes: true);
      expect(views().single['includeCommentLikes'], isTrue);
      expect(views().single['commentTypes'], <String>['text', 'voice']);
      expect(view.commentLikes!['c1']!.likeCount, 3);
      expect(service.commentLikeSupport.value, CommentLikeSupport.supported);
      expect(service.voiceCommentsSupported, isTrue);
    });

    test('probe order: both flags, then commentTypes only, and the like '
        'flag is recorded unsupported', () async {
      final service = build((_, payload) async {
        if (payload.containsKey('includeCommentLikes')) {
          throw callableError('invalid-argument');
        }
        return reelViewWire();
      });
      final view = await service.loadView('reel_1', includeCommentLikes: true);
      expect(view.commentLikes, isNull);
      expect(views(), hasLength(2));
      expect(views().last.containsKey('includeCommentLikes'), isFalse);
      expect(views().last['commentTypes'], <String>['text', 'voice']);
      expect(service.commentLikeSupport.value, CommentLikeSupport.unsupported);
      expect(service.voiceCommentsSupported, isTrue);

      await service.loadView('reel_1', includeCommentLikes: true);
      expect(views(), hasLength(3));
      expect(views().last.containsKey('includeCommentLikes'), isFalse);
    });

    test('probe order: an old backend refusing both falls back to the '
        'unflagged replay', () async {
      final service = build((_, payload) async {
        if (payload.containsKey('includeCommentLikes') ||
            payload.containsKey('commentTypes')) {
          throw callableError('invalid-argument');
        }
        return reelViewWire();
      });
      await service.loadView('reel_1', includeCommentLikes: true);
      expect(views(), hasLength(3));
      expect(views()[0].containsKey('includeCommentLikes'), isTrue);
      expect(views()[1].containsKey('includeCommentLikes'), isFalse);
      expect(views()[1].containsKey('commentTypes'), isTrue);
      expect(views()[2].containsKey('commentTypes'), isFalse);
      expect(service.commentLikeSupport.value, CommentLikeSupport.unsupported);
      expect(service.voiceCommentsSupported, isFalse);
    });

    test('a refusal no replay fixes is the original error and teaches '
        'nothing', () async {
      final service = build(
        (_, _) async => throw callableError('invalid-argument'),
      );
      await expectLater(
        service.loadView('reel_1', includeCommentLikes: true),
        throwsA(isA<ReelEngagementException>()),
      );
      expect(views(), hasLength(3));
      expect(service.commentLikeSupport.value, CommentLikeSupport.unknown);
      expect(
        service.voiceCommentSupport.value,
        ReelVoiceCommentSupport.unknown,
      );
    });

    test(
      'setCommentLike: exact request, retry-stable id, parsed answer',
      () async {
        var fail = true;
        final service = build((name, payload) async {
          expect(name, 'setReelCommentLikeV1');
          if (fail) throw callableError('unavailable');
          return <Object?, Object?>{
            'reelId': 'reel_1',
            'commentId': 'c1',
            'liked': true,
            'changed': true,
            'likeCount': 8,
          };
        });
        await expectLater(
          service.setCommentLike('reel_1', 'c1', liked: true),
          throwsA(isA<ReelEngagementException>()),
        );
        fail = false;
        final result = await service.setCommentLike(
          'reel_1',
          'c1',
          liked: true,
        );
        expect(result.likeCount, 8);
        expect(calls, hasLength(2));
        expect(calls.first.payload.keys.toSet(), <String>{
          'reelId',
          'commentId',
          'liked',
          'requestId',
        });
        expect(
          calls.first.payload['requestId'],
          calls.last.payload['requestId'],
        );
        expect(
          service.debugCommentLikeRequestId('reel_1', 'c1', liked: true),
          isNull,
        );
      },
    );

    test('setCommentLike: sending one direction drops the other\'s held '
        'id', () async {
      var fail = true;
      final service = build((name, payload) async {
        if (fail) throw callableError('unavailable');
        return <Object?, Object?>{
          'reelId': 'reel_1',
          'commentId': 'c1',
          'liked': payload['liked'],
          'changed': true,
          'likeCount': 1,
        };
      });
      await expectLater(
        service.setCommentLike('reel_1', 'c1', liked: true),
        throwsA(isA<ReelEngagementException>()),
      );
      final firstLike = calls.last.payload['requestId'];
      await expectLater(
        service.setCommentLike('reel_1', 'c1', liked: false),
        throwsA(isA<ReelEngagementException>()),
      );
      expect(
        service.debugCommentLikeRequestId('reel_1', 'c1', liked: true),
        isNull,
      );
      fail = false;
      await service.setCommentLike('reel_1', 'c1', liked: true);
      expect(calls.last.payload['requestId'], isNot(firstLike));
    });

    test('setCommentLike: a poisoned id is released', () async {
      final service = build(
        (_, _) async => throw callableError('invalid-argument'),
      );
      await expectLater(
        service.setCommentLike('reel_1', 'c1', liked: false),
        throwsA(isA<ReelEngagementException>()),
      );
      expect(
        service.debugCommentLikeRequestId('reel_1', 'c1', liked: false),
        isNull,
      );
    });
  });
}
