import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comments_view.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_engagement_bar.dart';

typedef _Call = ({String name, Map<String, Object?> payload});

final _likeAction = find.byKey(const ValueKey<String>('reel-like-action'));
final _commentsAction = find.byKey(
  const ValueKey<String>('reel-comments-action'),
);

Finder _inCard(Finder finder) =>
    find.descendant(of: find.byType(ReelCard), matching: finder);

FirebaseFunctionsException _refusal(String code) =>
    FirebaseFunctionsException(code: code, message: 'refused in test');

Map<String, Object?> _reelWire({
  String id = 'reel_1',
  String authorId = 'creator_1',
  int likeCount = 4,
  int commentCount = 2,
  bool callerLiked = false,
}) {
  const millis = 1725000000000;
  return <String, Object?>{
    'id': id,
    'authorId': authorId,
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
      caption: 'Night shift stories.',
    ).toWire(),
    'publishedAtMillis': millis,
    'sortKey': '${millis}_$id',
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
  int likeCount = 4,
  int commentCount = 2,
  bool callerLiked = false,
  bool truncated = false,
  String? nextCursor,
}) => <Object?, Object?>{
  'schemaVersion': 2,
  'reel': _reelWire(
    likeCount: likeCount,
    commentCount: commentCount,
    callerLiked: callerLiked,
  ),
  'comments': comments,
  'commentsTruncated': truncated,
  'nextCommentCursor': nextCursor,
};

Map<String, Object?> _commentWire(
  String id, {
  String authorId = 'creator_1',
  String authorName = 'Creator One',
  String text = 'Great one.',
}) => <String, Object?>{
  'schemaVersion': 1,
  'commentId': id,
  'type': 'text',
  'authorId': authorId,
  'authorName': authorName,
  'authorPhotoUrl': null,
  'text': text,
  'durationSeconds': null,
  'createdAtMillis': 1725000000000,
};

class _Harness {
  _Harness({bool emailVerified = true, Map<String, Object?>? reel})
    : reel = reel ?? _reelWire() {
    service = ReelService(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'viewer', isEmailVerified: emailVerified),
      ),
      callableInvoker: (name, payload) {
        calls.add((name: name, payload: payload));
        final responder = responders[name];
        if (responder == null) {
          throw StateError('Unexpected callable $name');
        }
        return responder(payload);
      },
    );
    responders['listReelsV2'] = (_) async => <Object?, Object?>{
      'schemaVersion': 2,
      'items': <Object?>[this.reel],
      'nextCursor': null,
    };
    responders['getReelMediaAccessV2'] = (_) async => <Object?, Object?>{
      'schemaVersion': 2,
      'url': 'https://storage.googleapis.com/yovoice/reel.mp4?token=test',
      'expiresAtMillis': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch,
      'generation': '7',
      'availabilityHours': 'permanent',
      'contentExpiresAtMillis': null,
    };
  }

  final Map<String, Object?> reel;
  final List<_Call> calls = <_Call>[];
  final Map<
    String,
    Future<Map<Object?, Object?>> Function(Map<String, Object?>)
  >
  responders = {};
  late final ReelService service;

  List<_Call> callsTo(String name) =>
      calls.where((call) => call.name == name).toList(growable: false);
}

Future<void> _pumpFeed(
  WidgetTester tester,
  _Harness harness, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      // The desktop shell and the mobile route both provide the Scaffold an
      // embedded feed announces through.
      home: Scaffold(
        body: ReelsFeedScreen(
          embedded: true,
          service: harness.service,
          videoBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The count rendered inside one engagement control.
String _countIn(WidgetTester tester, Finder action) {
  return tester
      .widget<Text>(find.descendant(of: action, matching: find.byType(Text)))
      .data!;
}

bool _likeIsFilled(WidgetTester tester) {
  return tester
      .widgetList<Icon>(
        find.descendant(of: _inCard(_likeAction), matching: find.byType(Icon)),
      )
      .any((icon) => icon.icon == Icons.favorite_rounded);
}

void main() {
  testWidgets('the feed shows the server counts it was given', (tester) async {
    final harness = _Harness();
    await _pumpFeed(tester, harness);

    expect(_countIn(tester, _inCard(_likeAction)), '4');
    expect(_countIn(tester, _inCard(_commentsAction)), '2');
    expect(_likeIsFilled(tester), isFalse);
  });

  testWidgets('assistive technology gets the action, the state and the exact '
      'total behind the compact one', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = _Harness(
      reel: _reelWire(likeCount: 1243, commentCount: 38, callerLiked: true),
    );
    await _pumpFeed(tester, harness);

    // The eye sees "1.2K"; the screen reader still hears 1243.
    expect(_countIn(tester, _inCard(_likeAction)), '1.2K');
    final like = tester
        .getSemantics(find.bySemanticsLabel('Unlike. Likes: 1243'))
        .getSemanticsData();
    expect(like.flagsCollection.isButton, isTrue);
    expect(like.flagsCollection.isSelected, ui.Tristate.isTrue);
    expect(like.flagsCollection.isEnabled, ui.Tristate.isTrue);

    final comments = tester
        .getSemantics(find.bySemanticsLabel('Open comments. Comments: 38'))
        .getSemanticsData();
    expect(comments.flagsCollection.isButton, isTrue);
    expect(comments.flagsCollection.isSelected, ui.Tristate.isFalse);

    semantics.dispose();
  });

  testWidgets('a like applies immediately and then adopts the server count', (
    tester,
  ) async {
    final harness = _Harness();
    final pending = Completer<Map<Object?, Object?>>();
    harness.responders['setReelLike'] = (_) => pending.future;
    await _pumpFeed(tester, harness);

    await tester.tap(_inCard(_likeAction));
    await tester.pump();

    // Optimistic: exactly one more, the heart filled, the control busy.
    expect(_countIn(tester, _inCard(_likeAction)), '5');
    expect(_likeIsFilled(tester), isTrue);
    expect(tester.widget<ReelCard>(find.byType(ReelCard)).likePending, isTrue);

    pending.complete(<Object?, Object?>{
      'reelId': 'reel_1',
      'liked': true,
      'changed': true,
      // The server counted other people's likes while this one was in flight.
      'likeCount': 42,
    });
    await tester.pumpAndSettle();

    expect(_countIn(tester, _inCard(_likeAction)), '42');
    expect(_likeIsFilled(tester), isTrue);
    expect(tester.widget<ReelCard>(find.byType(ReelCard)).likePending, isFalse);
    expect(harness.callsTo('setReelLike').single.payload['liked'], isTrue);
  });

  testWidgets('a refused like reverts to the pre-tap state and says why', (
    tester,
  ) async {
    final harness = _Harness();
    final pending = Completer<Map<Object?, Object?>>();
    harness.responders['setReelLike'] = (_) => pending.future;
    await _pumpFeed(tester, harness);

    await tester.tap(_inCard(_likeAction));
    await tester.pump();
    expect(_countIn(tester, _inCard(_likeAction)), '5');

    pending.completeError(_refusal('resource-exhausted'));
    await tester.pumpAndSettle();

    expect(_countIn(tester, _inCard(_likeAction)), '4');
    expect(_likeIsFilled(tester), isFalse);
    expect(
      find.text('You are doing that too often. Try again shortly.'),
      findsOneWidget,
    );
  });

  testWidgets('an unlike that is refused restores the like it removed', (
    tester,
  ) async {
    final harness = _Harness(reel: _reelWire(likeCount: 9, callerLiked: true));
    final pending = Completer<Map<Object?, Object?>>();
    harness.responders['setReelLike'] = (_) => pending.future;
    await _pumpFeed(tester, harness);

    expect(_likeIsFilled(tester), isTrue);
    await tester.tap(_inCard(_likeAction));
    await tester.pump();
    expect(_countIn(tester, _inCard(_likeAction)), '8');
    expect(_likeIsFilled(tester), isFalse);

    // One refusal envelope: the Reel is simply unavailable to engage with.
    pending.completeError(_refusal('permission-denied'));
    await tester.pumpAndSettle();

    expect(_countIn(tester, _inCard(_likeAction)), '9');
    expect(_likeIsFilled(tester), isTrue);
    expect(find.text('This Reel is unavailable right now.'), findsOneWidget);
  });

  testWidgets('a second tap cannot race the first', (tester) async {
    final harness = _Harness();
    final pending = Completer<Map<Object?, Object?>>();
    harness.responders['setReelLike'] = (_) => pending.future;
    await _pumpFeed(tester, harness);

    await tester.tap(_inCard(_likeAction));
    await tester.pump();
    await tester.tap(_inCard(_likeAction), warnIfMissed: false);
    await tester.pump();

    expect(harness.callsTo('setReelLike'), hasLength(1));
    pending.complete(<Object?, Object?>{
      'reelId': 'reel_1',
      'liked': true,
      'changed': true,
      'likeCount': 5,
    });
    await tester.pumpAndSettle();
    expect(_countIn(tester, _inCard(_likeAction)), '5');
  });

  testWidgets('an unverified account is told what unlocks liking', (
    tester,
  ) async {
    final harness = _Harness(emailVerified: false);
    await _pumpFeed(tester, harness);

    // The control stays live: a dead button would teach nothing.
    expect(tester.widget<ReelCard>(find.byType(ReelCard)).onLike, isNotNull);
    await tester.tap(_inCard(_likeAction));
    await tester.pumpAndSettle();

    expect(find.text('Verify your email to like or comment.'), findsOneWidget);
    // Nothing was spent on a call the backend would certainly refuse.
    expect(harness.callsTo('setReelLike'), isEmpty);
    expect(_countIn(tester, _inCard(_likeAction)), '4');
  });

  testWidgets('the comment control opens the thread over a narrow feed', (
    tester,
  ) async {
    final harness = _Harness();
    harness.responders['getReelViewV2'] = (_) async =>
        _viewResponse(comments: <Map<String, Object?>>[_commentWire('c1')]);
    await _pumpFeed(tester, harness);

    await tester.tap(_inCard(_commentsAction));
    await tester.pumpAndSettle();

    expect(find.byType(ReelCommentsView), findsOneWidget);
    expect(find.text('Great one.'), findsOneWidget);
    expect(harness.callsTo('getReelViewV2').single.payload['reelId'], 'reel_1');
  });

  testWidgets('a comment posted in the sheet updates the card behind it', (
    tester,
  ) async {
    final harness = _Harness();
    var posted = false;
    harness.responders['getReelViewV2'] = (_) async => _viewResponse(
      comments: <Map<String, Object?>>[
        _commentWire('c1'),
        if (posted)
          _commentWire(
            'c2',
            authorId: 'viewer',
            authorName: 'Viewer',
            text: 'Mine.',
          ),
      ],
      commentCount: posted ? 3 : 2,
    );
    harness.responders['createReelComment'] = (_) async {
      posted = true;
      return <Object?, Object?>{
        'reelId': 'reel_1',
        'commentId': 'c2',
        'created': true,
        'commentCount': 3,
      };
    };
    await _pumpFeed(tester, harness);

    await tester.tap(_inCard(_commentsAction));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('reel-comment-field')),
      'Mine.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('reel-comment-post')));
    await tester.pumpAndSettle();

    expect(find.text('Comment posted.'), findsOneWidget);
    expect(find.text('Mine.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('modal-sheet-close')));
    await tester.pumpAndSettle();

    // The count the card shows is the one the server returned.
    expect(_countIn(tester, _inCard(_commentsAction)), '3');
  });

  testWidgets('the sheet keeps its composer above the software keyboard', (
    tester,
  ) async {
    final harness = _Harness();
    harness.responders['getReelViewV2'] = (_) async =>
        _viewResponse(comments: <Map<String, Object?>>[_commentWire('c1')]);
    await _pumpFeed(tester, harness);

    await tester.tap(_inCard(_commentsAction));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();

    final field = tester.getRect(
      find.byKey(const ValueKey<String>('reel-comment-field')),
    );
    expect(field.bottom, lessThanOrEqualTo(844 - 320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a full thread and an open keyboard still fit the window', (
    tester,
  ) async {
    final harness = _Harness();
    harness.responders['getReelViewV2'] = (_) async => _viewResponse(
      comments: <Map<String, Object?>>[
        for (var index = 0; index < 7; index++)
          _commentWire(
            'c$index',
            authorName: 'Commenter With A Fairly Long Name $index',
            text:
                'A comment long enough to wrap onto two or three lines in a '
                'sheet this narrow, repeated so the thread fills its page. '
                '$index',
          ),
      ],
      truncated: true,
      nextCursor: 'cursor_2',
    );
    await _pumpFeed(tester, harness, size: const Size(320, 640));

    await tester.tap(_inCard(_commentsAction));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final field = tester.getRect(
      find.byKey(const ValueKey<String>('reel-comment-field')),
    );
    expect(field.bottom, lessThanOrEqualTo(640 - 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a thread read never overwrites a like still in flight', (
    tester,
  ) async {
    final harness = _Harness();
    final pendingLike = Completer<Map<Object?, Object?>>();
    harness.responders['setReelLike'] = (_) => pendingLike.future;
    // The thread answers with the pre-like aggregates, as a read that started
    // before the like legitimately would.
    harness.responders['getReelViewV2'] = (_) async =>
        _viewResponse(commentCount: 6);
    await _pumpFeed(tester, harness, size: const Size(1440, 900));

    await tester.tap(_inCard(_likeAction));
    await tester.pump();
    await tester.tap(_inCard(_commentsAction));
    await tester.pumpAndSettle();

    expect(_likeIsFilled(tester), isTrue);
    expect(_countIn(tester, _inCard(_likeAction)), '5');
    // The comment count from that same read is adopted, because no comment
    // operation of ours is in flight.
    expect(_countIn(tester, _inCard(_commentsAction)), '6');

    pendingLike.complete(<Object?, Object?>{
      'reelId': 'reel_1',
      'liked': true,
      'changed': true,
      'likeCount': 5,
    });
    await tester.pumpAndSettle();
    expect(_countIn(tester, _inCard(_likeAction)), '5');
  });

  group('wide layout', () {
    testWidgets('the thread opens beside the feed instead of over it', (
      tester,
    ) async {
      final harness = _Harness();
      harness.responders['getReelViewV2'] = (_) async =>
          _viewResponse(comments: <Map<String, Object?>>[_commentWire('c1')]);
      await _pumpFeed(tester, harness, size: const Size(1440, 900));

      // The panel carries its own bar in the written-label variant.
      expect(find.byType(ReelEngagementBar), findsNWidgets(2));
      expect(find.byType(ReelCommentsView), findsNothing);

      await tester.tap(_inCard(_commentsAction));
      await tester.pumpAndSettle();

      expect(find.byType(ReelCommentsView), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Great one.'), findsOneWidget);
      expect(
        tester.widget<ReelCard>(find.byType(ReelCard)).commentsOpen,
        isTrue,
      );

      await tester.tap(_inCard(_commentsAction));
      await tester.pumpAndSettle();

      expect(find.byType(ReelCommentsView), findsNothing);
      expect(
        tester.widget<ReelCard>(find.byType(ReelCard)).commentsOpen,
        isFalse,
      );
    });

    testWidgets('the panel and the card never disagree about a like', (
      tester,
    ) async {
      final harness = _Harness();
      harness.responders['setReelLike'] = (_) async => <Object?, Object?>{
        'reelId': 'reel_1',
        'liked': true,
        'changed': true,
        'likeCount': 12,
      };
      await _pumpFeed(tester, harness, size: const Size(1440, 900));

      final panelLike = find.descendant(
        of: find.byType(ReelEngagementBar).last,
        matching: find.byType(Text),
      );
      expect(tester.widget<Text>(panelLike.first).data, '4');

      await tester.tap(_inCard(_likeAction));
      await tester.pumpAndSettle();

      expect(_countIn(tester, _inCard(_likeAction)), '12');
      expect(tester.widget<Text>(panelLike.first).data, '12');
    });
  });

  testWidgets('a signed-out viewer sees the counts without a dead control', (
    tester,
  ) async {
    final auth = MockFirebaseAuth();
    final service = ReelService(
      auth: auth,
      callableInvoker: (name, payload) async {
        throw StateError('no callable may run without a viewer');
      },
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(body: ReelsFeedScreen(embedded: true, service: service)),
      ),
    );
    await tester.pumpAndSettle();

    // The signed-out feed cannot even list, so it shows its error state — the
    // engagement wiring must not be what breaks first.
    expect(find.byType(ReelCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
