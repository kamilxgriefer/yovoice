// "See who liked" on Voice Moment detail (ADR-230, owner variant A): a
// "See who liked ›" text control beside the Top reactions avatars, whose
// spoken label keeps the free names; a "Likes · N ›" fallback when likes
// exist but no liker could be projected; VIP → list, others → U1 upsell. The
// like chip (count fused with the heart) is unchanged.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'support/likers_fixtures.dart';
import 'voice_moment_test_doubles.dart';

const _entry = ValueKey('moment-detail-likers');

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

class _RecordingFeed extends HomeFeedService {
  _RecordingFeed(FakeFirebaseFirestore db)
    : super(
        firestore: db,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      );

  final List<(String, bool)> writes = <(String, bool)>[];

  @override
  Future<void> setLike(String momentId, {required bool liked}) async {
    writes.add((momentId, liked));
  }
}

VoiceMoment _moment(int likes) {
  final createdAt = DateTime.now().subtract(const Duration(hours: 2));
  return VoiceMoment(
    id: 'm1',
    authorId: 'nadia',
    authorName: 'Nadia Rutkowska',
    authorPhotoUrl: null,
    caption: 'The one thing nobody tells you.',
    audioUrl: 'https://cdn.example/m1.m4a',
    durationSeconds: 27,
    likeCount: likes,
    commentCount: 0,
    isPublished: true,
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(hours: 24)),
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
  'isPublished': true,
  'createdAt': Timestamp.fromDate(moment.createdAt!),
  'expiresAt': Timestamp.fromDate(moment.expiresAt!),
  'schemaVersion': 2,
  'status': 'published',
  'isDeleted': false,
};

void main() {
  late PublicIdentityRepository originalIdentity;

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = identityRepository();
  });

  tearDown(() => PublicIdentityRepository.instance = originalIdentity);

  MockFirebaseAuth auth() =>
      MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me'));

  /// Seeds [likes] likes, of which [projected] have a resolvable liker.
  Future<FakeFirebaseFirestore> seed(int likes, {int projected = 0}) async {
    final db = FakeFirebaseFirestore();
    await db.collection('voiceMoments').doc('m1').set(_doc(_moment(likes)));
    const names = ['Ola', 'Marek', 'Zosia'];
    for (var i = 0; i < projected; i++) {
      await db
          .collection('voiceMoments')
          .doc('m1')
          .collection('likes')
          .doc('u$i')
          .set({
            'userId': 'u$i',
            'createdAt': Timestamp.fromDate(
              DateTime.now().subtract(Duration(minutes: i + 1)),
            ),
          });
      await db.collection('publicProfiles').doc('u$i').set({
        'displayName': names[i],
      });
    }
    return db;
  }

  Future<ScriptedLikers> pumpDetail(
    WidgetTester tester, {
    required FakeFirebaseFirestore db,
    HomeFeedService? feed,
    required int likes,
    required bool vip,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final script = ScriptedLikers([
      pageWire([likerWire('julia', 'Julia Nowak')]),
    ]);
    final moments = MomentService(
      firestore: db,
      auth: auth(),
      storage: MockFirebaseStorage(),
      readService: VoiceMomentReadService(
        viewInvoker: fakeVoiceMomentViewInvoker(firestore: db),
      ),
    );
    await tester.pumpWidget(
      likersHost(
        textScale: textScale,
        const Scaffold(body: Center(child: Text('FEED'))),
      ),
    );
    final context = tester.element(find.text('FEED'));
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MomentDetailScreen(
            moment: _moment(likes),
            momentService: moments,
            feedService: feed ?? HomeFeedService(firestore: db, auth: auth()),
            auth: auth(),
            playerFactory: _SilentPlayer.new,
            likersLauncher: testLikersLauncher(allowed: vip, script: script),
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    return script;
  }

  Future<void> openEntry(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(_entry));
    await tester.pump();
    await tester.tap(find.byKey(_entry));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('"See who liked ›" sits beside the avatars; its label keeps '
      'the names; a VIP gets the list', (tester) async {
    final db = await seed(7, projected: 2);
    final script = await pumpDetail(tester, db: db, likes: 7, vip: true);

    expect(find.text('Top reactions'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget);
    expect(find.text('See who liked'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);
    expect(
      find.bySemanticsLabel('Liked by Ola, Marek and 5 others. See who liked.'),
      findsOneWidget,
    );
    final avatars = tester.getRect(
      find.byKey(const ValueKey('moment-detail-reactions')),
    );
    final entry = tester.getRect(find.byKey(_entry));
    // Beside the faces while it fits, on its own line when it does not (the
    // harness font is wider than any real one); never on top of them.
    expect(entry.overlaps(avatars), isFalse);
    expect(entry.top, greaterThanOrEqualTo(avatars.top - 10));
    expect(entry.height, greaterThanOrEqualTo(40));

    await openEntry(tester);
    expect(find.byKey(kLikersListSurface), findsOneWidget);
    expect(find.text('Julia Nowak'), findsOneWidget);
    expect(script.calls.single.name, 'listVoiceMomentLikersV1');
    expect(script.calls.single.payload, <String, Object?>{'momentId': 'm1'});
  });

  testWidgets('a non-VIP gets the U1 upsell', (tester) async {
    final db = await seed(7, projected: 2);
    final script = await pumpDetail(tester, db: db, likes: 7, vip: false);
    await openEntry(tester);
    expect(find.byKey(kLikersUpsellSurface), findsOneWidget);
    expect(find.text('7 people liked this Moment'), findsOneWidget);
    expect(script.calls, isEmpty);
  });

  testWidgets('no projectable likers: "Likes · N" still reaches the flow', (
    tester,
  ) async {
    final db = await seed(4);
    await pumpDetail(tester, db: db, likes: 4, vip: false);
    expect(find.text('Top reactions'), findsNothing);
    expect(find.text('Likes · 4'), findsOneWidget);
    expect(find.bySemanticsLabel('See who liked. Likes: 4'), findsOneWidget);
    await openEntry(tester);
    expect(find.byKey(kLikersUpsellSurface), findsOneWidget);
  });

  testWidgets('no likes: no entry at all', (tester) async {
    final db = await seed(0);
    await pumpDetail(tester, db: db, likes: 0, vip: true);
    expect(find.byKey(_entry), findsNothing);
    expect(find.text('Top reactions'), findsNothing);
  });

  testWidgets('the like chip still toggles the like, not the list', (
    tester,
  ) async {
    final db = await seed(7, projected: 2);
    final feed = _RecordingFeed(db);
    final script = await pumpDetail(
      tester,
      db: db,
      feed: feed,
      likes: 7,
      vip: true,
    );
    final like = find.byKey(const ValueKey('moment-detail-like'));
    await tester.ensureVisible(like);
    await tester.pump();
    await tester.tap(like);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(feed.writes, <(String, bool)>[('m1', true)]);
    expect(script.calls, isEmpty);
    expect(find.byKey(kLikersListSurface), findsNothing);
  });

  for (final size in const [Size(320, 700), Size(820, 1000), Size(1280, 900)]) {
    testWidgets('lays out at ${size.width.toInt()} px and 200 % text', (
      tester,
    ) async {
      final db = await seed(412, projected: 3);
      await pumpDetail(
        tester,
        db: db,
        likes: 412,
        vip: true,
        size: size,
        textScale: 2,
      );
      expect(find.byKey(_entry), findsOneWidget);
      expect(find.text('+409'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
