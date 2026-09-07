import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/reel_engagement_copy.dart';

/// One recorded callable invocation.
typedef _Call = ({String name, Map<String, Object?> payload});

/// A hexadecimal request id exactly as [ReelPublishSession.newRequestId] mints
/// it. Anything else would be rejected by the backend's own id validator.
final _requestIdPattern = RegExp(r'^[0-9a-f]{32}$');

FirebaseFunctionsException _refusal(String code) =>
    FirebaseFunctionsException(code: code, message: 'refused in test');

ReelService _service({
  required List<_Call> calls,
  required Future<Map<Object?, Object?>> Function(_Call call) respond,
}) {
  return ReelService(
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
    ),
    callableInvoker: (name, payload) {
      final call = (name: name, payload: payload);
      calls.add(call);
      return respond(call);
    },
  );
}

Map<Object?, Object?> _likeResponse({
  String reelId = 'reel_1',
  bool liked = true,
  bool changed = true,
  int likeCount = 1,
}) => <Object?, Object?>{
  'reelId': reelId,
  'liked': liked,
  'changed': changed,
  'likeCount': likeCount,
};

Map<Object?, Object?> _commentResponse({int commentCount = 1}) =>
    <Object?, Object?>{
      'reelId': 'reel_1',
      'commentId': 'comment_1',
      'created': true,
      'commentCount': commentCount,
    };

Map<Object?, Object?> _deletionResponse({int commentCount = 0}) =>
    <Object?, Object?>{
      'reelId': 'reel_1',
      'commentId': 'comment_1',
      'deleted': true,
      'commentCount': commentCount,
    };

Map<String, Object?> _commentWire(
  String id, {
  String authorId = 'viewer',
  String authorName = 'Viewer',
  String text = 'Hello',
  int createdAtMillis = 1725000000000,
}) => <String, Object?>{
  'schemaVersion': 1,
  'commentId': id,
  'type': 'text',
  'authorId': authorId,
  'authorName': authorName,
  'authorPhotoUrl': null,
  'text': text,
  'durationSeconds': null,
  'createdAtMillis': createdAtMillis,
};

Map<String, Object?> _reelWire({
  int likeCount = 3,
  int commentCount = 2,
  bool callerLiked = true,
}) {
  const millis = 1725000000000;
  return <String, Object?>{
    'id': 'reel_1',
    'authorId': 'creator_1',
    'authorName': 'Creator One',
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
    'sortKey': '${millis}_reel_1',
    'availability': <String, Object?>{
      'schemaVersion': 1,
      'availabilityHours': 'permanent',
      'expiresAtMillis': null,
    },
    'likeCount': likeCount,
    'commentCount': commentCount,
    'callerLiked': callerLiked,
  };
}

Map<Object?, Object?> _viewResponse({
  List<Map<String, Object?>> comments = const <Map<String, Object?>>[],
  bool truncated = false,
  String? nextCursor,
}) => <Object?, Object?>{
  'schemaVersion': 2,
  'reel': _reelWire(),
  'comments': comments,
  'commentsTruncated': truncated,
  'nextCommentCursor': nextCursor,
};

void main() {
  group('setReelLike', () {
    test(
      'sends exactly the documented payload and adopts the server count',
      () async {
        final calls = <_Call>[];
        final service = _service(
          calls: calls,
          respond: (_) async => _likeResponse(likeCount: 12),
        );

        final result = await service.setLike('reel_1', liked: true);

        expect(calls, hasLength(1));
        expect(calls.single.name, 'setReelLike');
        expect(calls.single.payload.keys.toSet(), <String>{
          'reelId',
          'liked',
          'requestId',
        });
        expect(calls.single.payload['reelId'], 'reel_1');
        expect(calls.single.payload['liked'], isTrue);
        expect(calls.single.payload['requestId'], matches(_requestIdPattern));
        expect(result.liked, isTrue);
        expect(result.changed, isTrue);
        // The count is the server's, never a local increment.
        expect(result.likeCount, 12);
      },
    );

    test(
      'an unchanged server state is a successful no-op, not a failure',
      () async {
        final calls = <_Call>[];
        final service = _service(
          calls: calls,
          respond: (_) async => _likeResponse(changed: false, likeCount: 4),
        );

        final result = await service.setLike('reel_1', liked: true);

        expect(result.changed, isFalse);
        expect(result.likeCount, 4);
      },
    );

    test('a lost acknowledgement replays the identical requestId', () async {
      final calls = <_Call>[];
      var attempts = 0;
      final service = _service(
        calls: calls,
        respond: (_) async {
          if (attempts++ == 0) throw _refusal('unavailable');
          return _likeResponse(likeCount: 9);
        },
      );

      await expectLater(
        service.setLike('reel_1', liked: true),
        throwsA(
          isA<ReelEngagementException>().having(
            (error) => error.reason,
            'reason',
            ReelEngagementFailure.offline,
          ),
        ),
      );
      final retried = await service.setLike('reel_1', liked: true);

      expect(calls, hasLength(2));
      expect(calls[1].payload['requestId'], calls[0].payload['requestId']);
      expect(retried.likeCount, 9);
    });

    test('both directions are released once either one succeeds', () async {
      final calls = <_Call>[];
      var attempts = 0;
      final service = _service(
        calls: calls,
        respond: (call) async {
          // The unlike is lost first, so it holds a retry-stable id; the like
          // that follows must not inherit or resurrect it.
          if (attempts++ == 0) throw _refusal('deadline-exceeded');
          return _likeResponse(liked: call.payload['liked']! as bool);
        },
      );

      await expectLater(
        service.setLike('reel_1', liked: false),
        throwsA(isA<ReelEngagementException>()),
      );
      await service.setLike('reel_1', liked: true);
      await service.setLike('reel_1', liked: false);

      expect(calls, hasLength(3));
      expect(
        calls[2].payload['requestId'],
        isNot(calls[0].payload['requestId']),
      );
      expect(
        calls[2].payload['requestId'],
        isNot(calls[1].payload['requestId']),
      );
    });

    test('a poisoned requestId is discarded rather than replayed', () async {
      for (final poison in const <String>[
        'already-exists',
        'invalid-argument',
      ]) {
        final calls = <_Call>[];
        var attempts = 0;
        final service = _service(
          calls: calls,
          respond: (_) async {
            if (attempts++ == 0) throw _refusal(poison);
            return _likeResponse();
          },
        );

        await expectLater(
          service.setLike('reel_1', liked: true),
          throwsA(isA<ReelEngagementException>()),
        );
        await service.setLike('reel_1', liked: true);

        expect(
          calls[1].payload['requestId'],
          isNot(calls[0].payload['requestId']),
          reason: '$poison must not be replayed with the same id',
        );
      }
    });

    test(
      'a caller-owned requestId is sent verbatim and never cached',
      () async {
        final calls = <_Call>[];
        final service = _service(
          calls: calls,
          respond: (_) async => _likeResponse(),
        );

        await service.setLike(
          'reel_1',
          liked: true,
          requestId: 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
        );

        expect(
          calls.single.payload['requestId'],
          'a1b2c3d4e5f60718293a4b5c6d7e8f90',
        );
      },
    );

    test('every refusal maps to one actionable outcome', () async {
      const expected = <String, ReelEngagementFailure>{
        'unauthenticated': ReelEngagementFailure.signedOut,
        'failed-precondition': ReelEngagementFailure.emailUnverified,
        'resource-exhausted': ReelEngagementFailure.rateLimited,
        // One refusal envelope: a block, a suspension, moderation and expiry
        // are deliberately indistinguishable here.
        'permission-denied': ReelEngagementFailure.unavailable,
        'not-found': ReelEngagementFailure.unavailable,
        'already-exists': ReelEngagementFailure.conflict,
        'invalid-argument': ReelEngagementFailure.invalid,
        'unavailable': ReelEngagementFailure.offline,
        'deadline-exceeded': ReelEngagementFailure.offline,
        'internal': ReelEngagementFailure.unknown,
      };
      for (final entry in expected.entries) {
        final service = _service(
          calls: <_Call>[],
          respond: (_) async => throw _refusal(entry.key),
        );
        await expectLater(
          service.setLike('reel_1', liked: true),
          throwsA(
            isA<ReelEngagementException>().having(
              (error) => error.reason,
              entry.key,
              entry.value,
            ),
          ),
        );
      }
    });

    test('a response about another Reel is refused', () async {
      final service = _service(
        calls: <_Call>[],
        respond: (_) async => _likeResponse(reelId: 'reel_2'),
      );

      await expectLater(
        service.setLike('reel_1', liked: true),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('createReelComment', () {
    test('sends the trimmed body with the caller-owned requestId', () async {
      final calls = <_Call>[];
      final service = _service(
        calls: calls,
        respond: (_) async => _commentResponse(commentCount: 5),
      );

      final result = await service.createComment(
        'reel_1',
        text: '  Beautiful.  ',
        requestId: 'ff00ff00ff00ff00ff00ff00ff00ff00',
      );

      expect(calls.single.name, 'createReelComment');
      expect(calls.single.payload.keys.toSet(), <String>{
        'reelId',
        'text',
        'requestId',
      });
      // Trimmed before hashing, so a retry hashes to the same server identity.
      expect(calls.single.payload['text'], 'Beautiful.');
      expect(
        calls.single.payload['requestId'],
        'ff00ff00ff00ff00ff00ff00ff00ff00',
      );
      expect(result.commentId, 'comment_1');
      expect(result.commentCount, 5);
    });

    test(
      'refuses an empty or oversized body before reaching the network',
      () async {
        final calls = <_Call>[];
        final service = _service(
          calls: calls,
          respond: (_) async => _commentResponse(),
        );

        await expectLater(
          service.createComment('reel_1', text: '   '),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          service.createComment(
            'reel_1',
            text: 'a' * (ReelComment.maxTextLength + 1),
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(calls, isEmpty);
      },
    );

    test('a rate limit is reported as such', () async {
      final service = _service(
        calls: <_Call>[],
        respond: (_) async => throw _refusal('resource-exhausted'),
      );

      await expectLater(
        service.createComment('reel_1', text: 'Hello'),
        throwsA(
          isA<ReelEngagementException>().having(
            (error) => error.reason,
            'reason',
            ReelEngagementFailure.rateLimited,
          ),
        ),
      );
    });

    test('a body the server did not create is refused', () async {
      final service = _service(
        calls: <_Call>[],
        respond: (_) async => <Object?, Object?>{
          ..._commentResponse(),
          'created': false,
        },
      );

      await expectLater(
        service.createComment('reel_1', text: 'Hello'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('deleteReelComment', () {
    test(
      'sends the documented payload and adopts the returned count',
      () async {
        final calls = <_Call>[];
        final service = _service(
          calls: calls,
          respond: (_) async => _deletionResponse(commentCount: 4),
        );

        final result = await service.deleteComment(
          'reel_1',
          commentId: 'comment_1',
        );

        expect(calls.single.name, 'deleteReelComment');
        expect(calls.single.payload.keys.toSet(), <String>{
          'reelId',
          'commentId',
          'requestId',
        });
        expect(calls.single.payload['commentId'], 'comment_1');
        expect(calls.single.payload['requestId'], matches(_requestIdPattern));
        expect(result.commentCount, 4);
      },
    );

    test(
      'a lost deletion replays the same id, and a new one follows success',
      () async {
        final calls = <_Call>[];
        var attempts = 0;
        final service = _service(
          calls: calls,
          respond: (_) async {
            if (attempts++ == 0) throw _refusal('unavailable');
            return _deletionResponse();
          },
        );

        await expectLater(
          service.deleteComment('reel_1', commentId: 'comment_1'),
          throwsA(isA<ReelEngagementException>()),
        );
        await service.deleteComment('reel_1', commentId: 'comment_1');
        await service.deleteComment('reel_1', commentId: 'comment_1');

        expect(calls[1].payload['requestId'], calls[0].payload['requestId']);
        expect(
          calls[2].payload['requestId'],
          isNot(calls[1].payload['requestId']),
        );
      },
    );

    test(
      'the single refusal envelope covers somebody else\'s comment',
      () async {
        final service = _service(
          calls: <_Call>[],
          respond: (_) async => throw _refusal('permission-denied'),
        );

        await expectLater(
          service.deleteComment('reel_1', commentId: 'comment_1'),
          throwsA(
            isA<ReelEngagementException>().having(
              (error) => error.reason,
              'reason',
              ReelEngagementFailure.unavailable,
            ),
          ),
        );
      },
    );
  });

  group('getReelViewV2', () {
    test('sends the reel, the page size and the cursor', () async {
      final calls = <_Call>[];
      final service = _service(
        calls: calls,
        respond: (_) async => _viewResponse(
          comments: <Map<String, Object?>>[
            _commentWire('c1', text: 'Oldest', createdAtMillis: 1725000000000),
            _commentWire('c2', text: 'Newest', createdAtMillis: 1725000009000),
          ],
          truncated: true,
          nextCursor: 'cursor_2',
        ),
      );

      final view = await service.loadView(
        'reel_1',
        commentLimit: 2,
        commentCursor: 'cursor_1',
      );

      expect(calls.single.name, 'getReelViewV2');
      expect(calls.single.payload, <String, Object?>{
        'reelId': 'reel_1',
        'commentLimit': 2,
        'commentCursor': 'cursor_1',
      });
      // Oldest first: the order the thread is rendered in.
      expect(view.comments.map((comment) => comment.text), <String>[
        'Oldest',
        'Newest',
      ]);
      expect(view.commentsTruncated, isTrue);
      expect(view.nextCommentCursor, 'cursor_2');
      expect(view.reel.likeCount, 3);
      expect(view.reel.commentCount, 2);
      expect(view.reel.callerLiked, isTrue);
    });

    test(
      'defaults to the server ceiling and rejects an impossible page',
      () async {
        final calls = <_Call>[];
        final service = _service(
          calls: calls,
          respond: (_) async => _viewResponse(),
        );

        await service.loadView('reel_1');
        expect(calls.single.payload['commentLimit'], ReelView.maxCommentLimit);
        expect(calls.single.payload['commentCursor'], isNull);

        await expectLater(
          service.loadView('reel_1', commentLimit: 0),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          service.loadView(
            'reel_1',
            commentLimit: ReelView.maxCommentLimit + 1,
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(calls, hasLength(1));
      },
    );

    test('a cursor the server called complete cannot page forever', () async {
      final service = _service(
        calls: <_Call>[],
        respond: (_) async => _viewResponse(nextCursor: 'cursor_2'),
      );

      await expectLater(
        service.loadView('reel_1'),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'a view read is rate limited like every other engagement call',
      () async {
        final service = _service(
          calls: <_Call>[],
          respond: (_) async => throw _refusal('resource-exhausted'),
        );

        await expectLater(
          service.loadView('reel_1'),
          throwsA(
            isA<ReelEngagementException>().having(
              (error) => error.reason,
              'reason',
              ReelEngagementFailure.rateLimited,
            ),
          ),
        );
      },
    );
  });

  group('refusal copy', () {
    Future<Map<ReelEngagementFailure, String>> messages(
      WidgetTester tester,
      Locale locale, {
      required ReelEngagementAction action,
    }) async {
      final resolved = <ReelEngagementFailure, String>{};
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<Object?>>[
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) {
              for (final reason in ReelEngagementFailure.values) {
                resolved[reason] = reelEngagementMessage(
                  context,
                  ReelEngagementException(reason),
                  action: action,
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return resolved;
    }

    testWidgets('a rate limit and a verification gate read as themselves', (
      tester,
    ) async {
      final english = await messages(
        tester,
        const Locale('en'),
        action: ReelEngagementAction.like,
      );

      expect(
        english[ReelEngagementFailure.rateLimited],
        'You are doing that too often. Try again shortly.',
      );
      expect(
        english[ReelEngagementFailure.emailUnverified],
        'Verify your email to like or comment.',
      );
      expect(
        english[ReelEngagementFailure.unavailable],
        'This Reel is unavailable right now.',
      );
      expect(
        english[ReelEngagementFailure.offline],
        'Check your connection and try again.',
      );
      expect(
        english[ReelEngagementFailure.unknown],
        'The like could not be saved. Try again.',
      );
      // No message may leak a status code or an exception string.
      for (final message in english.values) {
        expect(message, isNot(contains('resource-exhausted')));
        expect(message, isNot(contains('ReelEngagement')));
        expect(message.trim(), isNotEmpty);
      }
    });

    testWidgets('the same refusals are Polish under a Polish locale', (
      tester,
    ) async {
      final polish = await messages(
        tester,
        const Locale('pl'),
        action: ReelEngagementAction.comment,
      );

      expect(
        polish[ReelEngagementFailure.rateLimited],
        'Robisz to zbyt często. Spróbuj ponownie za chwilę.',
      );
      expect(
        polish[ReelEngagementFailure.emailUnverified],
        'Zweryfikuj adres e-mail, aby polubić lub komentować.',
      );
      expect(
        polish[ReelEngagementFailure.unknown],
        'Nie udało się opublikować komentarza. Spróbuj ponownie.',
      );
    });

    testWidgets('only the residual failure names the operation', (
      tester,
    ) async {
      final like = await messages(
        tester,
        const Locale('en'),
        action: ReelEngagementAction.like,
      );
      final deletion = await messages(
        tester,
        const Locale('en'),
        action: ReelEngagementAction.deleteComment,
      );
      final loading = await messages(
        tester,
        const Locale('en'),
        action: ReelEngagementAction.loadComments,
      );

      expect(
        like[ReelEngagementFailure.rateLimited],
        deletion[ReelEngagementFailure.rateLimited],
      );
      expect(
        deletion[ReelEngagementFailure.unknown],
        'The comment could not be deleted. Try again.',
      );
      expect(
        loading[ReelEngagementFailure.unknown],
        'Comments could not be loaded.',
      );
    });

    testWidgets('an error that is not a refusal still explains itself', (
      tester,
    ) async {
      String? message;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              message = reelEngagementMessage(
                context,
                StateError('The Reel sign-in session changed. Try again.'),
                action: ReelEngagementAction.comment,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(message, 'The comment could not be posted. Try again.');
    });
  });
}
