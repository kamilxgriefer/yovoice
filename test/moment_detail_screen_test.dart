// The Voice Moment detail page: sections, ownership, availability, the
// graceful gone-state, deletion, and the honest "Top reactions" row.
//
// Everything here runs against a seeded fake Firestore through the SAME
// MomentService production uses, so the live-document stream, the likers
// query and the comment thread are exercised end to end.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

const _viewer = 'me';

VoiceMoment _moment(
  String id, {
  String author = 'nadia',
  String authorName = 'Nadia Rutkowska',
  String caption = 'The one thing nobody tells you.',
  int likes = 0,
  int comments = 0,
  Duration age = const Duration(hours: 2),

  /// Null = PERMANENT under the amended availability contract.
  Duration? lifetime = const Duration(hours: 24),
}) {
  final createdAt = DateTime.now().subtract(age);
  return VoiceMoment(
    id: id,
    authorId: author,
    authorName: authorName,
    authorPhotoUrl: null,
    caption: caption,
    audioUrl: 'https://cdn.example/$id.m4a',
    durationSeconds: 27,
    likeCount: likes,
    commentCount: comments,
    isPublished: true,
    createdAt: createdAt,
    expiresAt: lifetime == null ? null : createdAt.add(lifetime),
    schemaVersion: 2,
    status: 'published',
    isDeleted: false,
  );
}

Map<String, dynamic> _doc(VoiceMoment moment) => <String, dynamic>{
  'authorId': moment.authorId,
  'authorName': moment.authorName,
  'authorPhotoUrl': null,
  'caption': moment.caption,
  'audioUrl': moment.audioUrl,
  'durationSeconds': moment.durationSeconds,
  'likeCount': moment.likeCount,
  'commentCount': moment.commentCount,
  'isPublished': moment.isPublished,
  'createdAt': Timestamp.fromDate(moment.createdAt!),
  if (moment.expiresAt != null)
    'expiresAt': Timestamp.fromDate(moment.expiresAt!),
  'schemaVersion': 2,
  'status': 'published',
  'isDeleted': false,
};

class _SilentPlayer implements audio.AudioPlayer {
  @override
  Stream<Duration> get onPositionChanged => const Stream<Duration>.empty();

  @override
  Stream<Duration> get onDurationChanged => const Stream<Duration>.empty();

  @override
  Stream<void> get onPlayerComplete => const Stream<void>.empty();

  @override
  Future<void> play(
    audio.Source source, {
    double? volume,
    double? balance,
    audio.AudioContext? ctx,
    Duration? position,
    audio.PlayerMode? mode,
  }) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late PublicIdentityRepository originalIdentity;

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _viewer)),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  MockFirebaseAuth auth() =>
      MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _viewer));

  ({FakeFirebaseFirestore db, MomentService moments, HomeFeedService feed})
  services() {
    final db = FakeFirebaseFirestore();
    return (
      db: db,
      // _CallableDeleteService: MomentService.deleteMoment now routes
      // through the deployed `deleteMoment` callable (the client-side
      // sweep broke on foreign likes/comments); the double performs the
      // callable's server-side outcome against the fake db.
      moments: _CallableDeleteService(
        firestore: db,
        auth: auth(),
        storage: MockFirebaseStorage(),
        db: db,
      ),
      feed: HomeFeedService(firestore: db, auth: auth()),
    );
  }

  Future<void> pumpDetail(
    WidgetTester tester, {
    required VoiceMoment moment,
    required MomentService moments,
    required HomeFeedService feed,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: const Scaffold(body: Center(child: Text('FEED'))),
      ),
    );
    final context = tester.element(find.text('FEED'));
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MomentDetailScreen(
            moment: moment,
            momentService: moments,
            feedService: feed,
            auth: auth(),
            playerFactory: _SilentPlayer.new,
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  group('sections', () {
    testWidgets('author, caption heading, player, engagement and comments '
        'all render from real data', (tester) async {
      final s = services();
      final moment = _moment('m1', likes: 3, comments: 1);
      await s.db.collection('voiceMoments').doc('m1').set(_doc(moment));
      await s.db
          .collection('voiceMoments')
          .doc('m1')
          .collection('comments')
          .add(<String, dynamic>{
            'type': 'text',
            'authorId': 'tomas',
            'authorName': 'Tomás Oliveira',
            'text': 'The night bus is where the truth lives.',
            'createdAt': Timestamp.fromDate(
              DateTime.now().subtract(const Duration(minutes: 30)),
            ),
          });

      await pumpDetail(
        tester,
        moment: moment,
        moments: s.moments,
        feed: s.feed,
      );

      expect(find.text('Nadia Rutkowska'), findsOneWidget);
      // The caption IS the heading: Moments carry no separate title.
      expect(find.text('The one thing nobody tells you.'), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-detail-play')), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-detail-like')), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // the real like count
      expect(find.byKey(const ValueKey('moment-detail-share')), findsOneWidget);
      // Someone else's Moment: Report offered, Delete absent.
      expect(
        find.byKey(const ValueKey('moment-detail-report-m1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('moment-detail-delete-m1')),
        findsNothing,
      );
      expect(find.text('Comments (1)'), findsOneWidget);
      expect(
        find.text('The night bus is where the truth lives.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('moment-detail-comment-field')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('back returns to where the page was opened from', (
      tester,
    ) async {
      final s = services();
      final moment = _moment('m1');
      await s.db.collection('voiceMoments').doc('m1').set(_doc(moment));

      await pumpDetail(
        tester,
        moment: moment,
        moments: s.moments,
        feed: s.feed,
      );
      expect(find.byKey(const ValueKey('moment-detail-back')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('moment-detail-back')));
      await tester.pumpAndSettle();
      expect(find.text('FEED'), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-detail-back')), findsNothing);
    });

    testWidgets('sending a comment posts through the real service and '
        'appears in the thread', (tester) async {
      final s = services();
      final moment = _moment('m1');
      await s.db.collection('voiceMoments').doc('m1').set(_doc(moment));

      await pumpDetail(
        tester,
        moment: moment,
        moments: s.moments,
        feed: s.feed,
      );

      await tester.enterText(
        find.byKey(const ValueKey('moment-detail-comment-field')),
        'Real comment',
      );
      await tester.tap(
        find.byKey(const ValueKey('moment-detail-comment-send')),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(find.text('Real comment'), findsOneWidget);
      final stored = await s.db
          .collection('voiceMoments')
          .doc('m1')
          .collection('comments')
          .get();
      expect(stored.docs.single.data()['text'], 'Real comment');
      expect(stored.docs.single.data()['schemaVersion'], 2);
      expect(
        (await s.db.collection('voiceMoments').doc('m1').get())
            .data()?['commentCount'],
        1,
      );
    });
  });

  group('availability', () {
    testWidgets('the author of a timed Moment sees the real countdown', (
      tester,
    ) async {
      final s = services();
      final moment = _moment('m1', author: _viewer, authorName: 'Kamil');
      await s.db.collection('voiceMoments').doc('m1').set(_doc(moment));

      await pumpDetail(
        tester,
        moment: moment,
        moments: s.moments,
        feed: s.feed,
      );

      expect(
        find.byKey(const ValueKey('moment-detail-availability')),
        findsOneWidget,
      );
      expect(find.textContaining('Expires in'), findsOneWidget);
    });

    testWidgets('the author of a PERMANENT Moment sees "Stays until '
        'deleted" and no countdown', (tester) async {
      final s = services();
      final moment = _moment(
        'm1',
        author: _viewer,
        authorName: 'Kamil',
        lifetime: null,
      );
      await s.db.collection('voiceMoments').doc('m1').set(_doc(moment));

      await pumpDetail(
        tester,
        moment: moment,
        moments: s.moments,
        feed: s.feed,
      );

      expect(find.text('Stays until deleted'), findsOneWidget);
      expect(find.textContaining('Expires in'), findsNothing);
    });

    testWidgets('a non-author sees NO availability line on a permanent '
        'Moment — nothing is expiring', (tester) async {
      final s = services();
      final moment = _moment('m1', lifetime: null);
      await s.db.collection('voiceMoments').doc('m1').set(_doc(moment));

      await pumpDetail(
        tester,
        moment: moment,
        moments: s.moments,
        feed: s.feed,
      );

      expect(find.text('Nadia Rutkowska'), findsOneWidget);
      expect(find.text('Stays until deleted'), findsNothing);
      expect(find.textContaining('Expires in'), findsNothing);
    });
  });

  group('gone states', () {
    testWidgets('an EXPIRED Moment renders the graceful gone-state, not a '
        'stale page', (tester) async {
      final s = services();
      final moment = _moment(
        'm1',
        age: const Duration(hours: 30),
        lifetime: const Duration(hours: 24),
      );
      await s.db.collection('voiceMoments').doc('m1').set(_doc(moment));

      await pumpDetail(
        tester,
        moment: moment,
        moments: s.moments,
        feed: s.feed,
      );

      expect(find.byKey(const ValueKey('moment-detail-gone')), findsOneWidget);
      expect(find.text('This Moment is no longer available'), findsOneWidget);
      expect(find.byKey(const ValueKey('moment-detail-play')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('moment-detail-gone-back')));
      await tester.pumpAndSettle();
      expect(find.text('FEED'), findsOneWidget);
    });

    testWidgets('a MISSING document renders the graceful gone-state', (
      tester,
    ) async {
      final s = services();
      // Deliberately NOT seeded: the page was opened from a stale
      // reference and the document does not exist.
      final moment = _moment('vanished');

      await pumpDetail(
        tester,
        moment: moment,
        moments: s.moments,
        feed: s.feed,
      );

      expect(find.byKey(const ValueKey('moment-detail-gone')), findsOneWidget);
    });
  });

  group('deletion', () {
    testWidgets('the author deletes: destructive confirmation with the '
        'exact copy, the document goes, the page pops', (tester) async {
      final s = services();
      final moment = _moment(
        'm1',
        author: _viewer,
        authorName: 'Kamil',
        lifetime: null,
      );
      await s.db.collection('voiceMoments').doc('m1').set(_doc(moment));

      await pumpDetail(
        tester,
        moment: moment,
        moments: s.moments,
        feed: s.feed,
      );

      await tester.tap(find.byKey(const ValueKey('moment-detail-delete-m1')));
      await tester.pumpAndSettle();

      // The exact destructive copy.
      expect(find.text('Delete this moment?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('moment-detail-delete-confirm')),
      );
      await tester.pumpAndSettle();

      final snapshot = await s.db.collection('voiceMoments').doc('m1').get();
      expect(snapshot.exists, isFalse);
      expect(find.text('FEED'), findsOneWidget);
      expect(find.text('Voice Moment deleted.'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation deletes nothing', (tester) async {
      final s = services();
      final moment = _moment('m1', author: _viewer, authorName: 'Kamil');
      await s.db.collection('voiceMoments').doc('m1').set(_doc(moment));

      await pumpDetail(
        tester,
        moment: moment,
        moments: s.moments,
        feed: s.feed,
      );

      await tester.tap(find.byKey(const ValueKey('moment-detail-delete-m1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('moment-detail-delete-cancel')),
      );
      await tester.pumpAndSettle();

      final snapshot = await s.db.collection('voiceMoments').doc('m1').get();
      expect(snapshot.exists, isTrue);
      // The page did not pop: its own chrome is still on screen.
      expect(find.byKey(const ValueKey('moment-detail-back')), findsOneWidget);
    });
  });

  group('top reactions', () {
    testWidgets('renders the real likers resolved through publicProfiles, '
        'plus the honest +N remainder', (tester) async {
      final s = services();
      final moment = _moment('m1', likes: 7);
      await s.db.collection('voiceMoments').doc('m1').set(_doc(moment));
      final likes = s.db
          .collection('voiceMoments')
          .doc('m1')
          .collection('likes');
      await likes.doc('u1').set({
        'userId': 'u1',
        'createdAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      });
      await likes.doc('u2').set({
        'userId': 'u2',
        'createdAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 9)),
        ),
      });
      await s.db.collection('publicProfiles').doc('u1').set({
        'displayName': 'Ola',
      });
      await s.db.collection('publicProfiles').doc('u2').set({
        'displayName': 'Marek',
      });

      await pumpDetail(
        tester,
        moment: moment,
        moments: s.moments,
        feed: s.feed,
      );

      expect(find.text('Top reactions'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('moment-detail-reactions')),
        findsOneWidget,
      );
      // 7 real likes, 2 resolvable identities: the remainder is honest.
      expect(find.text('+5'), findsOneWidget);
    });

    testWidgets('no likes, no section — nothing is invented', (tester) async {
      final s = services();
      final moment = _moment('m1', likes: 0);
      await s.db.collection('voiceMoments').doc('m1').set(_doc(moment));

      await pumpDetail(
        tester,
        moment: moment,
        moments: s.moments,
        feed: s.feed,
      );

      expect(find.text('Top reactions'), findsNothing);
    });
  });
}

class _CallableDeleteService extends MomentService {
  _CallableDeleteService({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required FirebaseStorage storage,
    required FakeFirebaseFirestore db,
  }) : db = db,
       super(
         firestore: firestore,
         auth: auth,
         storage: storage,
         functions: _MomentDetailFunctions(db),
       );

  final FakeFirebaseFirestore db;

  @override
  Future<void> deleteMoment(VoiceMoment moment) async {
    if (moment.authorId != 'me') {
      throw StateError('You can only delete your own Voice Moments.');
    }
    await db.collection('voiceMoments').doc(moment.id).delete();
  }
}

/// The widget still exercises the production [MomentService]. This double is
/// only the callable transport: it models the Admin-SDK side effect after the
/// client calls `createMomentComment`, so the test cannot pass through a
/// client-direct Firestore fallback that production Rules now reject.
class _MomentDetailFunctions implements FirebaseFunctions {
  _MomentDetailFunctions(this.db);

  final FakeFirebaseFirestore db;
  int _nextComment = 0;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _MomentDetailCallable((parameters) => _call(name, parameters));

  Future<Object?> _call(String name, Object? parameters) async {
    if (name != 'createMomentComment') {
      throw FirebaseFunctionsException(
        code: 'not-found',
        message: 'Unexpected callable $name.',
      );
    }
    final data = Map<String, dynamic>.from(parameters as Map);
    final momentId = data['momentId'] as String;
    final text = data['text'] as String;
    _nextComment += 1;
    final commentId = _nextComment.toRadixString(16).padLeft(20, '0');
    final momentRef = db.collection('voiceMoments').doc(momentId);
    final commentRef = momentRef.collection('comments').doc(commentId);
    final now = Timestamp.now();

    await db.runTransaction((transaction) async {
      final moment = await transaction.get(momentRef);
      final current = (moment.data()?['commentCount'] as num?)?.toInt() ?? 0;
      transaction.set(commentRef, <String, dynamic>{
        'schemaVersion': 2,
        'type': 'text',
        'authorId': _viewer,
        'authorName': 'YO Voice viewer',
        'authorPhotoUrl': null,
        'text': text,
        'audioUrl': null,
        'storagePath': null,
        'durationSeconds': null,
        'mediaGeneration': null,
        'mediaSize': null,
        'mediaContentType': null,
        'createdAt': now,
      });
      transaction.update(momentRef, <String, dynamic>{
        'commentCount': current + 1,
        'updatedAt': now,
      });
    });
    return <String, Object?>{'commentId': commentId};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MomentDetailCallable implements HttpsCallable {
  _MomentDetailCallable(this.handler);

  final Future<Object?> Function(Object? parameters) handler;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async =>
      _MomentDetailCallableResult<T>(await handler(parameters) as T);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MomentDetailCallableResult<T> implements HttpsCallableResult<T> {
  _MomentDetailCallableResult(this.data);

  @override
  final T data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
