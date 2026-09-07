import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comments_view.dart';

typedef _Call = ({String name, Map<String, Object?> payload});

const _viewer = 'viewer';

FirebaseFunctionsException _refusal(String code) =>
    FirebaseFunctionsException(code: code, message: 'refused in test');

Map<String, Object?> _reelWire({int commentCount = 0}) {
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
    'likeCount': 0,
    'commentCount': commentCount,
    'callerLiked': false,
  };
}

Reel _reel({int commentCount = 0}) =>
    Reel.fromV2Wire(_reelWire(commentCount: commentCount));

Map<String, Object?> _commentWire(
  String id, {
  String authorId = 'creator_1',
  String authorName = 'Creator One',
  String text = 'Great one.',
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

Map<Object?, Object?> _view(
  List<Map<String, Object?>> comments, {
  String? nextCursor,
  int? commentCount,
}) => <Object?, Object?>{
  'schemaVersion': 2,
  'reel': _reelWire(commentCount: commentCount ?? comments.length),
  'comments': comments,
  'commentsTruncated': nextCursor != null,
  'nextCommentCursor': nextCursor,
};

class _Harness {
  _Harness({bool emailVerified = true}) {
    service = ReelService(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _viewer, isEmailVerified: emailVerified),
      ),
      callableInvoker: (name, payload) {
        calls.add((name: name, payload: payload));
        final responder = responders[name];
        if (responder == null) throw StateError('Unexpected callable $name');
        return responder(payload);
      },
    );
  }

  final List<_Call> calls = <_Call>[];
  final Map<
    String,
    Future<Map<Object?, Object?>> Function(Map<String, Object?>)
  >
  responders = {};
  final List<Reel> updates = <Reel>[];
  late final ReelService service;

  List<_Call> callsTo(String name) =>
      calls.where((call) => call.name == name).toList(growable: false);
}

Future<void> _pumpThread(
  WidgetTester tester,
  _Harness harness, {
  Reel? reel,
  Size size = const Size(390, 844),
  double textScale = 1,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: SafeArea(
            child: ReelCommentsView(
              reel: reel ?? _reel(),
              service: harness.service,
              onReelUpdated: harness.updates.add,
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  testWidgets('a thread that is still loading says so', (tester) async {
    final harness = _Harness();
    final pending = Completer<Map<Object?, Object?>>();
    harness.responders['getReelViewV2'] = (_) => pending.future;

    await _pumpThread(tester, harness, settle: false);

    expect(find.text('Loading comments'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reel-comment-thread')),
      findsNothing,
    );

    pending.complete(_view(const <Map<String, Object?>>[]));
    await tester.pumpAndSettle();
    expect(find.text('Loading comments'), findsNothing);
  });

  testWidgets('an empty thread invites the first comment', (tester) async {
    final harness = _Harness();
    harness.responders['getReelViewV2'] = (_) async =>
        _view(const <Map<String, Object?>>[]);

    await _pumpThread(tester, harness);

    expect(
      find.byKey(const ValueKey<String>('reel-comments-empty')),
      findsOneWidget,
    );
    expect(find.text('No comments yet'), findsOneWidget);
    expect(find.text('Be the first to comment.'), findsOneWidget);
    // The composer stays available on an empty thread.
    expect(
      find.byKey(const ValueKey<String>('reel-comment-field')),
      findsOneWidget,
    );
  });

  testWidgets('a failed read is explained and retried in place', (
    tester,
  ) async {
    final harness = _Harness();
    var attempts = 0;
    harness.responders['getReelViewV2'] = (_) async {
      if (attempts++ == 0) throw _refusal('unavailable');
      return _view(<Map<String, Object?>>[_commentWire('c1')]);
    };

    await _pumpThread(tester, harness);

    expect(
      find.byKey(const ValueKey<String>('reel-comments-error')),
      findsOneWidget,
    );
    expect(find.text('Check your connection and try again.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Great one.'), findsOneWidget);
    expect(harness.callsTo('getReelViewV2'), hasLength(2));
  });

  testWidgets('a rate-limited read names the limit, not the status code', (
    tester,
  ) async {
    final harness = _Harness();
    harness.responders['getReelViewV2'] = (_) async =>
        throw _refusal('resource-exhausted');

    await _pumpThread(tester, harness);

    expect(
      find.text('You are doing that too often. Try again shortly.'),
      findsOneWidget,
    );
  });

  testWidgets('the thread pages forward with the server cursor', (
    tester,
  ) async {
    final harness = _Harness();
    harness.responders['getReelViewV2'] = (payload) async {
      final cursor = payload['commentCursor'];
      if (cursor == null) {
        return _view(
          <Map<String, Object?>>[
            _commentWire('c1', text: 'Oldest'),
            _commentWire('c2', text: 'Middle'),
          ],
          nextCursor: 'cursor_2',
          commentCount: 3,
        );
      }
      expect(cursor, 'cursor_2');
      return _view(<Map<String, Object?>>[
        _commentWire('c3', text: 'Newest'),
      ], commentCount: 3);
    };

    await _pumpThread(tester, harness);

    expect(find.text('Oldest'), findsOneWidget);
    expect(find.text('Newest'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('reel-comments-load-more')),
    );
    await tester.pumpAndSettle();

    // Oldest first, appended in order, with the affordance gone at the end.
    expect(find.text('Oldest'), findsOneWidget);
    expect(find.text('Middle'), findsOneWidget);
    expect(find.text('Newest'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reel-comments-load-more')),
      findsNothing,
    );
    expect(harness.callsTo('getReelViewV2'), hasLength(2));
  });

  testWidgets('a posted comment is re-read from the server, never invented', (
    tester,
  ) async {
    final harness = _Harness();
    var posted = false;
    harness.responders['getReelViewV2'] = (_) async =>
        _view(<Map<String, Object?>>[
          _commentWire('c1'),
          if (posted)
            _commentWire(
              'c2',
              authorId: _viewer,
              authorName: 'Viewer Name From Server',
              text: 'Mine.',
              createdAtMillis: 1725000009000,
            ),
        ], commentCount: posted ? 2 : 1);
    harness.responders['createReelComment'] = (_) async {
      posted = true;
      return <Object?, Object?>{
        'reelId': 'reel_1',
        'commentId': 'c2',
        'created': true,
        'commentCount': 2,
      };
    };

    await _pumpThread(tester, harness);
    await tester.enterText(
      find.byKey(const ValueKey<String>('reel-comment-field')),
      '  Mine.  ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('reel-comment-post')));
    await tester.pumpAndSettle();

    expect(
      harness.callsTo('createReelComment').single.payload['text'],
      'Mine.',
    );
    expect(find.text('Comment posted.'), findsOneWidget);
    expect(find.text('Mine.'), findsOneWidget);
    // The display name is the server's, not one the client guessed.
    expect(find.text('Viewer Name From Server'), findsOneWidget);
    expect(harness.updates.last.commentCount, 2);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('reel-comment-field')),
          )
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets(
    'a lost post replays the same requestId instead of double-posting',
    (tester) async {
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _view(const <Map<String, Object?>>[]);
      var attempts = 0;
      harness.responders['createReelComment'] = (_) async {
        if (attempts++ == 0) throw _refusal('unavailable');
        return <Object?, Object?>{
          'reelId': 'reel_1',
          'commentId': 'c1',
          'created': true,
          'commentCount': 1,
        };
      };

      await _pumpThread(tester, harness);
      await tester.enterText(
        find.byKey(const ValueKey<String>('reel-comment-field')),
        'Once only.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('reel-comment-post')));
      await tester.pumpAndSettle();

      expect(find.text('Check your connection and try again.'), findsOneWidget);
      // The words are still there to retry with.
      expect(find.text('Once only.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('reel-comment-post')));
      await tester.pumpAndSettle();

      final posts = harness.callsTo('createReelComment');
      expect(posts, hasLength(2));
      expect(posts[1].payload['requestId'], posts[0].payload['requestId']);
      expect(find.text('Comment posted.'), findsOneWidget);
    },
  );

  testWidgets('a rate-limited post keeps the draft and explains the wait', (
    tester,
  ) async {
    final harness = _Harness();
    harness.responders['getReelViewV2'] = (_) async =>
        _view(const <Map<String, Object?>>[]);
    harness.responders['createReelComment'] = (_) async =>
        throw _refusal('resource-exhausted');

    await _pumpThread(tester, harness);
    await tester.enterText(
      find.byKey(const ValueKey<String>('reel-comment-field')),
      'Too fast.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('reel-comment-post')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('reel-comment-composer-note')),
      findsOneWidget,
    );
    expect(
      find.text('You are doing that too often. Try again shortly.'),
      findsOneWidget,
    );
    expect(find.text('Too fast.'), findsOneWidget);
  });

  group('deleting your own comment', () {
    Future<_Harness> pumpMixedThread(WidgetTester tester) async {
      final harness = _Harness();
      var deleted = false;
      harness.responders['getReelViewV2'] = (_) async =>
          _view(<Map<String, Object?>>[
            _commentWire('c1', text: 'Theirs.'),
            if (!deleted)
              _commentWire(
                'c2',
                authorId: _viewer,
                authorName: 'Viewer',
                text: 'Mine.',
              ),
          ], commentCount: deleted ? 1 : 2);
      harness.responders['deleteReelComment'] = (_) async {
        deleted = true;
        return <Object?, Object?>{
          'reelId': 'reel_1',
          'commentId': 'c2',
          'deleted': true,
          'commentCount': 1,
        };
      };
      await _pumpThread(tester, harness, reel: _reel(commentCount: 2));
      return harness;
    }

    testWidgets('only your own comment offers deletion, and nothing offers a '
        'report path that does not exist', (tester) async {
      await pumpMixedThread(tester);

      expect(
        find.byKey(const ValueKey<String>('reel-comment-delete-c2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('reel-comment-delete-c1')),
        findsNothing,
      );
      expect(find.byTooltip('Report comment'), findsNothing);
      expect(find.byIcon(Icons.flag_outlined), findsNothing);
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    });

    testWidgets('cancelling the confirmation keeps the comment', (
      tester,
    ) async {
      final harness = await pumpMixedThread(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-delete-c2')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete comment?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Mine.'), findsOneWidget);
      expect(harness.callsTo('deleteReelComment'), isEmpty);
    });

    testWidgets('confirming removes it and adopts the returned count', (
      tester,
    ) async {
      final harness = await pumpMixedThread(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-delete-c2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-delete-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mine.'), findsNothing);
      expect(find.text('Theirs.'), findsOneWidget);
      expect(find.text('Comment deleted.'), findsOneWidget);
      expect(
        harness.callsTo('deleteReelComment').single.payload['commentId'],
        'c2',
      );
      expect(harness.updates.last.commentCount, 1);
    });

    testWidgets('a refused deletion leaves the comment and says why', (
      tester,
    ) async {
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _view(<Map<String, Object?>>[
            _commentWire(
              'c2',
              authorId: _viewer,
              authorName: 'Viewer',
              text: 'Mine.',
            ),
          ]);
      harness.responders['deleteReelComment'] = (_) async =>
          throw _refusal('resource-exhausted');
      await _pumpThread(tester, harness, reel: _reel(commentCount: 1));

      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-delete-c2')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('reel-comment-delete-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mine.'), findsOneWidget);
      expect(
        find.text('You are doing that too often. Try again shortly.'),
        findsOneWidget,
      );
    });
  });

  group('a host that fixes the height', () {
    Future<Rect> pumpInPanel(
      WidgetTester tester,
      _Harness harness, {
      double height = 700,
    }) async {
      tester.view.physicalSize = const Size(380, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 380,
                height: height,
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: ReelCommentsView(
                        reel: _reel(),
                        service: harness.service,
                        onReelUpdated: harness.updates.add,
                        gutter: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getRect(
        find.byKey(const ValueKey<String>('reel-comment-composer')),
      );
    }

    testWidgets('pins the composer to the bottom of an empty thread', (
      tester,
    ) async {
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _view(const <Map<String, Object?>>[]);

      final composer = await pumpInPanel(tester, harness);

      // The wide context panel gives this view a fixed column; the thread
      // takes it and the composer stays on the bottom edge instead of
      // floating under two lines of empty state.
      expect(composer.bottom, 700);
      expect(find.text('No comments yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a window too shallow for its placeholder states', (
      tester,
    ) async {
      final harness = _Harness();
      final pending = Completer<Map<Object?, Object?>>();
      harness.responders['getReelViewV2'] = (_) => pending.future;

      tester.view.physicalSize = const Size(380, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 380,
                height: 190,
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: ReelCommentsView(
                        reel: _reel(),
                        service: harness.service,
                        onReelUpdated: harness.updates.add,
                        gutter: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Loading comments'), findsOneWidget);
      expect(tester.takeException(), isNull);

      pending.complete(_view(const <Map<String, Object?>>[]));
      await tester.pumpAndSettle();
      expect(find.text('No comments yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pins the composer to the bottom of a full thread', (
      tester,
    ) async {
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _view(<Map<String, Object?>>[
            for (var index = 0; index < 7; index++)
              _commentWire(
                'c$index',
                authorName: 'Commenter $index',
                text:
                    'A comment long enough to wrap onto a second line here. '
                    '$index',
              ),
          ], nextCursor: 'cursor_2');

      final composer = await pumpInPanel(tester, harness);

      expect(composer.bottom, 700);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('an unverified account is told what unlocks commenting', (
    tester,
  ) async {
    final harness = _Harness(emailVerified: false);
    harness.responders['getReelViewV2'] = (_) async =>
        _view(<Map<String, Object?>>[_commentWire('c1')]);

    await _pumpThread(tester, harness);

    // Reading is not gated; posting is.
    expect(find.text('Great one.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reel-comment-verify-notice')),
      findsOneWidget,
    );
    expect(find.text('Verify your email to like or comment.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reel-comment-field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('reel-comment-post')),
      findsNothing,
    );
    expect(harness.callsTo('createReelComment'), isEmpty);
  });

  testWidgets('long names and full-length comments still lay out', (
    tester,
  ) async {
    final harness = _Harness();
    harness.responders['getReelViewV2'] = (_) async =>
        _view(<Map<String, Object?>>[
          _commentWire(
            'c1',
            authorId: _viewer,
            authorName: 'Aleksandra Wiśniewska-Kowalczyk Rutkowska Jaguszewska',
            text: 'Zażółć gęślą jaźń. ' * 52,
          ),
        ]);

    // The narrowest supported width, at the largest text scale the project
    // verifies elsewhere.
    await _pumpThread(
      tester,
      harness,
      size: const Size(320, 568),
      textScale: 2,
    );

    expect(
      find.byKey(const ValueKey<String>('reel-comment-thread')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching to another Reel reloads the thread from scratch', (
    tester,
  ) async {
    final harness = _Harness();
    harness.responders['getReelViewV2'] = (payload) async {
      expect(payload['commentCursor'], isNull);
      return _view(<Map<String, Object?>>[_commentWire('c1')]);
    };
    final reel = ValueNotifier<Reel>(_reel());
    addTearDown(reel.dispose);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ValueListenableBuilder<Reel>(
            valueListenable: reel,
            builder: (context, value, _) => ReelCommentsView(
              reel: value,
              service: harness.service,
              onReelUpdated: harness.updates.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.callsTo('getReelViewV2'), hasLength(1));

    reel.value = Reel.fromV2Wire(<String, Object?>{
      ..._reelWire(),
      'id': 'reel_2',
      'sortKey': '1725000000000_reel_2',
    });
    await tester.pumpAndSettle();

    expect(harness.callsTo('getReelViewV2'), hasLength(2));
    expect(harness.callsTo('getReelViewV2').last.payload['reelId'], 'reel_2');
  });
}
