// Yeel comment hearts (ADR-230, owner variant B): a compact "♡ 3" line
// under the comment's words, the one trailing control kept, the heart
// disabled (present) while that control spins, an optimistic toggle with a
// revert, and the count opening the comment likers flow.

import 'dart:async';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comments_view.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'support/comment_like_fixtures.dart';
import 'support/likers_fixtures.dart';

const _heart = ValueKey('reel-comment-like-c1');
const _count = ValueKey('reel-comment-likers-c1');
const _whoLiked = ValueKey('reel-comment-who-liked-c1');

class _Backend {
  bool acceptsLikes = true;
  final Map<String, Map<Object?, Object?>> likes =
      <String, Map<Object?, Object?>>{
        'c1': likeStateWire(3),
        'c2': likeStateWire(0),
      };
  final List<({String name, Map<String, Object?> payload})> calls =
      <({String name, Map<String, Object?> payload})>[];
  Object? nextLikeAnswer;
  Completer<Map<Object?, Object?>>? deleteAnswer;

  List<Map<String, Object?>> callsTo(String name) => <Map<String, Object?>>[
    for (final call in calls)
      if (call.name == name) call.payload,
  ];

  late final ReelService service = ReelService(
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'viewer', isEmailVerified: true),
    ),
    callableInvoker: (name, payload) async {
      calls.add((name: name, payload: Map<String, Object?>.of(payload)));
      switch (name) {
        case 'getReelViewV2':
          final flagged = payload.containsKey('includeCommentLikes');
          if (flagged && !acceptsLikes) throw callableError('invalid-argument');
          return reelViewWire(
            comments: <Map<String, Object?>>[
              reelCommentWire(
                'c1',
                text: 'Gdzie to było? Muszę tam pojechać w weekend.',
              ),
              reelCommentWire(
                'c2',
                authorId: 'viewer',
                authorName: 'Me',
                text: 'Nad Wisłą.',
              ),
            ],
            commentLikes: flagged ? <Object?, Object?>{...likes} : null,
          );
        case 'setReelCommentLikeV1':
          final answer = nextLikeAnswer;
          nextLikeAnswer = null;
          if (answer is Exception || answer is Error) throw answer as Object;
          final id = payload['commentId'] as String;
          final liked = payload['liked'] as bool;
          final count = (likes[id]!['likeCount'] as int) + (liked ? 1 : -1);
          likes[id] = likeStateWire(count, liked: liked);
          return <Object?, Object?>{
            'reelId': payload['reelId'],
            'commentId': id,
            'liked': liked,
            'changed': true,
            'likeCount': count,
          };
        case 'deleteReelComment':
          return (deleteAnswer ??= Completer<Map<Object?, Object?>>()).future;
      }
      throw StateError('Unexpected callable $name');
    },
  );
}

void main() {
  late PublicIdentityRepository originalIdentity;

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = identityRepository();
  });

  tearDown(() => PublicIdentityRepository.instance = originalIdentity);

  Future<ScriptedLikers> pump(
    WidgetTester tester,
    _Backend backend, {
    bool vip = false,
    double width = 390,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak')]),
    ]);
    await tester.pumpWidget(
      likersHost(
        textScale: textScale,
        Scaffold(
          body: SafeArea(
            child: ReelCommentsView(
              reel: Reel.fromV2Wire(reelWire()),
              service: backend.service,
              onReelUpdated: (_) {},
              likersLauncher: testLikersLauncher(allowed: vip, script: script),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return script;
  }

  testWidgets('no hearts while the deployment refuses comment likes', (
    tester,
  ) async {
    final backend = _Backend()..acceptsLikes = false;
    await pump(tester, backend);
    expect(
      find.text('Gdzie to było? Muszę tam pojechać w weekend.'),
      findsOneWidget,
    );
    expect(find.byKey(_heart), findsNothing);
    expect(find.byKey(_count), findsNothing);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    final views = backend.callsTo('getReelViewV2');
    expect(views, hasLength(2));
    expect(views.first['includeCommentLikes'], isTrue);
    expect(views.last.containsKey('includeCommentLikes'), isFalse);
    expect(views.last['commentTypes'], <String>['text', 'voice']);
  });

  for (final width in <double>[320, 390]) {
    for (final scale in <double>[1, 2]) {
      testWidgets('a compact heart line under the words at $width px, '
          '${(scale * 100).round()} % text; one trailing control', (
        tester,
      ) async {
        await pump(
          tester,
          _Backend(),
          vip: true,
          width: width,
          textScale: scale,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final text = tester.getRect(
          find.text('Gdzie to było? Muszę tam pojechać w weekend.'),
        );
        final heart = tester.getRect(find.byKey(_heart));
        final count = tester.getRect(find.byKey(_count));
        expect(heart.top, greaterThanOrEqualTo(text.bottom - 1));
        expect(count.left, greaterThanOrEqualTo(heart.right - 0.5));
        expect(heart.shortestSide, greaterThanOrEqualTo(44));
        expect(count.shortestSide, greaterThanOrEqualTo(44));
        expect(find.byKey(_whoLiked), findsOneWidget);
        // The glyph lines up with the words above it.
        final glyph = tester.getRect(
          find.descendant(
            of: find.byKey(_heart),
            matching: find.byIcon(Icons.favorite_border_rounded),
          ),
        );
        expect((glyph.left - text.left).abs(), lessThan(1.5));
        // Still ONE trailing control per row.
        expect(
          find.byKey(const ValueKey('reel-comment-report-c1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('reel-comment-delete-c2')),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('the heart toggles optimistically; a failure reverts and says '
      'so', (tester) async {
    final backend = _Backend();
    await pump(tester, backend);
    await tester.tap(find.byKey(_heart));
    await tester.pump();
    await tester.pump();
    expect(
      find.descendant(of: find.byKey(_count), matching: find.text('4')),
      findsOneWidget,
    );
    final sent = backend.callsTo('setReelCommentLikeV1').single;
    expect(sent['reelId'], 'reel_1');
    expect(sent['commentId'], 'c1');
    expect(sent['liked'], isTrue);

    backend.nextLikeAnswer = callableError('unavailable');
    await tester.tap(find.byKey(_heart));
    await tester.pump();
    await tester.pump();
    expect(
      find.descendant(of: find.byKey(_count), matching: find.text('4')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Unlike comment. Likes: 4'), findsOneWidget);
    expect(find.text('Couldn\'t update your like. Try again.'), findsOneWidget);
  });

  for (final width in <double>[320, 390]) {
    testWidgets('at $width px the whole 44 px heart target takes taps, its '
        'start edge included', (tester) async {
      final backend = _Backend();
      await pump(tester, backend, width: width);
      final heart = tester.getRect(find.byKey(_heart));
      expect(heart.width, greaterThanOrEqualTo(44));
      await tester.tapAt(Offset(heart.left + 4, heart.center.dy));
      await tester.pump();
      await tester.pump();
      final sent = backend.callsTo('setReelCommentLikeV1');
      expect(sent, hasLength(1));
      expect(sent.single['liked'], isTrue);
      // The glyph still lines up with the words above it.
      final text = tester.getRect(
        find.text('Gdzie to było? Muszę tam pojechać w weekend.'),
      );
      final glyph = tester.getRect(
        find.descendant(
          of: find.byKey(_heart),
          matching: find.byIcon(Icons.favorite_rounded),
        ),
      );
      expect((glyph.left - text.left).abs(), lessThan(1.5));
    });
  }

  testWidgets('while the row is busy the heart is disabled, not removed', (
    tester,
  ) async {
    final backend = _Backend();
    await pump(tester, backend);
    await tester.tap(find.byKey(const ValueKey('reel-comment-delete-c2')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('reel-comment-delete-confirm')),
    );
    await tester.pump();
    await tester.pump();
    const busyHeart = ValueKey('reel-comment-like-c2');
    expect(find.byKey(busyHeart), findsOneWidget);
    expect(tester.widget<InkResponse>(find.byKey(busyHeart)).onTap, isNull);
    await tester.tap(find.byKey(busyHeart), warnIfMissed: false);
    await tester.pump();
    expect(backend.callsTo('setReelCommentLikeV1'), isEmpty);
    backend.deleteAnswer!.complete(<Object?, Object?>{
      'reelId': 'reel_1',
      'commentId': 'c2',
      'deleted': true,
      'commentCount': 1,
    });
    await tester.pumpAndSettle();
  });

  testWidgets('the count opens the comment likers list for a VIP', (
    tester,
  ) async {
    final script = await pump(tester, _Backend(), vip: true);
    await tester.tap(find.byKey(_count));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
    expect(find.byKey(kLikersListSurface), findsOneWidget);
    expect(script.calls.single.name, 'listReelLikersV1');
    expect(script.calls.single.payload, <String, Object?>{
      'reelId': 'reel_1',
      'commentId': 'c1',
    });
  });

  testWidgets('a non-VIP gets the upsell and no "Who liked"', (tester) async {
    final script = await pump(tester, _Backend());
    expect(find.byKey(_whoLiked), findsNothing);
    await tester.tap(find.byKey(_count));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
    expect(find.byKey(kLikersUpsellSurface), findsOneWidget);
    expect(script.calls, isEmpty);
  });
}
