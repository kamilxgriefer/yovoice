// Voice Moment comment hearts (ADR-230, owner variant B "Odpowiedz · ♡ 3"):
// no heart while the deployment has not proven comment likes (unknown or
// unsupported; never a "Coming soon" heart); heart + count when it has; an
// optimistic toggle with a revert SnackBar; the count opens "See who liked"
// (list for VIP, U1 upsell otherwise); VIP viewers also read "Who liked";
// the pop is decorative and snapped under Reduce Motion.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'support/comment_like_fixtures.dart';
import 'support/likers_fixtures.dart';

const _heart = ValueKey('moment-comment-like-c1');
const _count = ValueKey('moment-comment-likers-c1');
const _whoLiked = ValueKey('moment-comment-who-liked-c1');

class _SilentPlayer implements audio.AudioPlayer {
  @override
  Stream<Duration> get onPositionChanged => const Stream<Duration>.empty();

  @override
  Stream<Duration> get onDurationChanged => const Stream<Duration>.empty();

  @override
  Stream<void> get onPlayerComplete => const Stream<void>.empty();

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A scripted Voice backend: the view (flag-aware) and the toggle.
class _Backend {
  _Backend({this.acceptsFlag = true, Map<String, Map<Object?, Object?>>? likes})
    : likes =
          likes ??
          <String, Map<Object?, Object?>>{
            'c1': likeStateWire(3),
            'c2': likeStateWire(0),
          };

  bool acceptsFlag;
  Map<String, Map<Object?, Object?>> likes;
  final List<Map<String, Object?>> viewRequests = <Map<String, Object?>>[];
  final List<Map<String, Object?>> likeRequests = <Map<String, Object?>>[];

  /// Next toggle answer: null answers like the server, an exception throws,
  /// a completer waits.
  Object? nextLikeAnswer;

  late final DateTime _created = DateTime.now().subtract(
    const Duration(hours: 1),
  );

  Future<Map<Object?, Object?>> view(Map<String, Object?> request) async {
    viewRequests.add(Map<String, Object?>.of(request));
    final flagged = request.containsKey('includeCommentLikes');
    if (flagged && !acceptsFlag) throw callableError('invalid-argument');
    return voiceViewWire(
      moment: voiceMomentWire(createdAt: _created),
      comments: <Map<Object?, Object?>>[
        voiceCommentWire('c1', createdAt: _created),
        voiceCommentWire(
          'c2',
          authorId: 'michal',
          authorName: 'Michał Kowalczyk',
          text: 'Brzmi jak mój tramwaj o 7:10.',
          createdAt: _created,
          offsetMillis: 1000,
        ),
      ],
      commentLikes: flagged ? <Object?, Object?>{...likes} : null,
    );
  }

  Future<Object?> like(Map<String, Object?> request) async {
    likeRequests.add(Map<String, Object?>.of(request));
    final answer = nextLikeAnswer;
    nextLikeAnswer = null;
    if (answer is Completer<Object?>) return answer.future;
    if (answer is Exception || answer is Error) throw answer as Object;
    final id = request['commentId'] as String;
    final liked = request['liked'] as bool;
    final before = likes[id]!['likeCount'] as int;
    final count = liked ? before + 1 : before - 1;
    likes[id] = likeStateWire(count, liked: liked);
    return <Object?, Object?>{
      'momentId': request['momentId'],
      'commentId': id,
      'liked': liked,
      'changed': true,
      'likeCount': count,
    };
  }

  MomentService service() => MomentService(
    firestore: FakeFirebaseFirestore(),
    auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
    storage: MockFirebaseStorage(),
    readService: VoiceMomentReadService(viewInvoker: view),
    commentLikeInvoker: like,
  );

  VoiceMoment moment() => VoiceMoment(
    id: 'm1',
    authorId: 'nadia',
    authorName: 'Nadia Rutkowska',
    authorPhotoUrl: null,
    caption: 'The night bus is where the truth lives.',
    audioUrl: null,
    durationSeconds: 27,
    likeCount: 4,
    commentCount: 2,
    isPublished: true,
    createdAt: _created,
    expiresAt: _created.add(const Duration(hours: 24)),
    schemaVersion: 2,
    status: 'published',
    isDeleted: false,
  );
}

void main() {
  late PublicIdentityRepository originalIdentity;

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = identityRepository();
  });

  tearDown(() => PublicIdentityRepository.instance = originalIdentity);

  Future<ScriptedLikers> pumpScreen(
    WidgetTester tester,
    _Backend backend, {
    bool vip = false,
    double width = 390,
    double textScale = 1,
    bool motion = false,
  }) async {
    tester.view.physicalSize = Size(width, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak')]),
    ]);
    Widget screen = MomentCommentsScreen(
      moment: backend.moment(),
      momentService: backend.service(),
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      mentionFriendsStream: Stream<List<FriendUser>>.value(
        const <FriendUser>[],
      ),
      likersLauncher: testLikersLauncher(allowed: vip, script: script),
    );
    if (motion) {
      final inner = screen;
      screen = Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: false),
          child: inner,
        ),
      );
    }
    await tester.pumpWidget(likersHost(screen, textScale: textScale));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return script;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
  }

  testWidgets('a deployment that refuses the flag: no heart, no count, and '
      'no "Coming soon"', (tester) async {
    final backend = _Backend(acceptsFlag: false);
    await pumpScreen(tester, backend);
    expect(find.text('Słychać cały poranek.'), findsOneWidget);
    expect(find.byKey(const ValueKey('reply-to-comment-c1')), findsOneWidget);
    expect(find.byKey(_heart), findsNothing);
    expect(find.byKey(_count), findsNothing);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    expect(find.textContaining('Coming soon'), findsNothing);
    // Verified once, then read without the flag.
    expect(backend.viewRequests, hasLength(2));
    expect(backend.viewRequests.first['includeCommentLikes'], isTrue);
    expect(
      backend.viewRequests.last.containsKey('includeCommentLikes'),
      isFalse,
    );
  });

  testWidgets('supported: "Reply · ♡ 3" with two separate 44 px targets', (
    tester,
  ) async {
    final backend = _Backend();
    await pumpScreen(tester, backend);
    expect(backend.viewRequests.single['includeCommentLikes'], isTrue);
    expect(find.byKey(_heart), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_count), matching: find.text('3')),
      findsOneWidget,
    );
    // A zero-like comment has its heart but no count target.
    expect(
      find.byKey(const ValueKey('moment-comment-like-c2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('moment-comment-likers-c2')),
      findsNothing,
    );
    // Order in the action line: Reply, then the heart, then the count.
    final reply = tester.getRect(
      find.byKey(const ValueKey('reply-to-comment-c1')),
    );
    final heart = tester.getRect(find.byKey(_heart));
    final count = tester.getRect(find.byKey(_count));
    expect(heart.left, greaterThanOrEqualTo(reply.right));
    expect(count.left, greaterThanOrEqualTo(heart.right - 0.5));
    expect(heart.width, greaterThanOrEqualTo(44));
    expect(heart.height, greaterThanOrEqualTo(44));
    expect(count.width, greaterThanOrEqualTo(44));
    expect(count.height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('Like comment. Likes: 3'), findsOneWidget);
    expect(find.bySemanticsLabel('See who liked. Likes: 3'), findsOneWidget);
    // Not a VIP: no "Who liked".
    expect(find.byKey(_whoLiked), findsNothing);
    expect(find.text('Who liked'), findsNothing);
  });

  testWidgets('a VIP viewer also reads "Who liked" inside the count', (
    tester,
  ) async {
    await pumpScreen(tester, _Backend(), vip: true);
    await tester.pump();
    expect(find.byKey(_whoLiked), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(_count), matching: find.byKey(_whoLiked)),
      findsOneWidget,
    );
    // Only where there are likes to list.
    expect(
      find.byKey(const ValueKey('moment-comment-who-liked-c2')),
      findsNothing,
    );
  });

  testWidgets('the heart toggles optimistically and adopts the server count', (
    tester,
  ) async {
    final backend = _Backend();
    await pumpScreen(tester, backend);
    final pending = Completer<Object?>();
    backend.nextLikeAnswer = pending;
    await tester.tap(find.byKey(_heart));
    await tester.pump();
    expect(
      find.descendant(of: find.byKey(_count), matching: find.text('4')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Unlike comment. Likes: 4'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_heart),
        matching: find.byIcon(Icons.favorite_rounded),
      ),
      findsOneWidget,
    );
    final request = backend.likeRequests.single;
    expect(request['momentId'], 'm1');
    expect(request['commentId'], 'c1');
    expect(request['liked'], isTrue);

    pending.complete(<Object?, Object?>{
      'momentId': 'm1',
      'commentId': 'c1',
      'liked': true,
      'changed': true,
      'likeCount': 11,
    });
    await tester.pump();
    await tester.pump();
    expect(
      find.descendant(of: find.byKey(_count), matching: find.text('11')),
      findsOneWidget,
    );
  });

  testWidgets('a failed toggle reverts and says so', (tester) async {
    final backend = _Backend();
    await pumpScreen(tester, backend);
    backend.nextLikeAnswer = callableError('unavailable');
    await tester.tap(find.byKey(_heart));
    await tester.pump();
    await tester.pump();
    expect(
      find.descendant(of: find.byKey(_count), matching: find.text('3')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Like comment. Likes: 3'), findsOneWidget);
    expect(find.text('Couldn\'t update your like. Try again.'), findsOneWidget);
  });

  testWidgets('the count opens the U1 upsell for a non-VIP', (tester) async {
    final script = await pumpScreen(tester, _Backend());
    await tester.tap(find.byKey(_count));
    await settle(tester);
    expect(find.byKey(kLikersUpsellSurface), findsOneWidget);
    expect(find.text('3 people liked this comment'), findsOneWidget);
    expect(script.calls, isEmpty);
  });

  testWidgets('the count opens the comment likers list for a VIP', (
    tester,
  ) async {
    final script = await pumpScreen(tester, _Backend(), vip: true);
    await tester.tap(find.byKey(_count));
    await settle(tester);
    expect(find.byKey(kLikersListSurface), findsOneWidget);
    expect(find.text('Julia Nowak'), findsOneWidget);
    expect(script.calls.single.name, 'listVoiceMomentLikersV1');
    expect(script.calls.single.payload, <String, Object?>{
      'momentId': 'm1',
      'commentId': 'c1',
    });
  });

  testWidgets('320 px at 200 % text wraps without overflow', (tester) async {
    await pumpScreen(tester, _Backend(), vip: true, width: 320, textScale: 2);
    await tester.pump();
    expect(find.byKey(_heart), findsOneWidget);
    expect(find.byKey(_count), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the like pop runs only when decorative motion is allowed', (
    tester,
  ) async {
    ScaleTransition pop() => tester.widget<ScaleTransition>(
      find.descendant(
        of: find.byKey(_heart),
        matching: find.byType(ScaleTransition),
      ),
    );

    // Reduce Motion (the host's default): snapped.
    await pumpScreen(tester, _Backend());
    await tester.tap(find.byKey(_heart));
    await tester.pump();
    expect(pop().scale.value, 1);

    // Motion allowed: it pops once, then settles (no loop).
    await pumpScreen(tester, _Backend(), motion: true);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('moment-comment-like-c2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final popping = tester.widget<ScaleTransition>(
      find.descendant(
        of: find.byKey(const ValueKey('moment-comment-like-c2')),
        matching: find.byType(ScaleTransition),
      ),
    );
    expect(popping.scale.value, lessThan(1));
    await tester.pumpAndSettle();
    expect(popping.scale.value, 1);
  });

  for (final size in const <Size>[Size(390, 844), Size(1280, 900)]) {
    testWidgets('Moment detail at ${size.width.round()} px: the thread carries '
        'the same hearts', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = _Backend();
      final script = ScriptedLikers([
        pageWire([likerWire('julia', 'Julia Nowak')]),
      ]);
      final db = FakeFirebaseFirestore();
      await db.collection('voiceMoments').doc('m1').set(<String, dynamic>{
        'authorId': 'nadia',
        'createdAt': Timestamp.now(),
      });
      await tester.pumpWidget(
        likersHost(const Scaffold(body: Center(child: Text('FEED')))),
      );
      final context = tester.element(find.text('FEED'));
      unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => MomentDetailScreen(
              moment: backend.moment(),
              momentService: backend.service(),
              feedService: HomeFeedService(
                firestore: db,
                auth: MockFirebaseAuth(
                  signedIn: true,
                  mockUser: MockUser(uid: 'me'),
                ),
              ),
              auth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: 'me'),
              ),
              mentionFriendsStream: Stream<List<FriendUser>>.value(
                const <FriendUser>[],
              ),
              playerFactory: _SilentPlayer.new,
              likersLauncher: testLikersLauncher(allowed: true, script: script),
            ),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(backend.viewRequests.first['includeCommentLikes'], isTrue);
      // The docked "Rozmowa" panel when the width has one, otherwise the
      // single column the thread follows.
      final panel = find.byKey(const ValueKey('moment-detail-thread-scroll'));
      final host = panel.evaluate().isNotEmpty
          ? panel
          : find.byKey(const ValueKey('moment-detail-scroll'));
      await tester.scrollUntilVisible(
        find.byKey(_heart),
        200,
        scrollable: find
            .descendant(of: host, matching: find.byType(Scrollable))
            .first,
      );
      await tester.pump();
      expect(find.byKey(_heart), findsOneWidget);
      expect(find.byKey(_whoLiked), findsOneWidget);

      await tester.tap(find.byKey(_heart));
      await tester.pump();
      await tester.pump();
      expect(backend.likeRequests.single['liked'], isTrue);
      expect(
        find.descendant(of: find.byKey(_count), matching: find.text('4')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(_count));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byKey(kLikersListSurface), findsOneWidget);
      expect(script.calls.single.payload, <String, Object?>{
        'momentId': 'm1',
        'commentId': 'c1',
      });
    });
  }
}
