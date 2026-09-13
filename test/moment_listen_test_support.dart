// Shared harness for the expanded Voice Moment (board 07): a seeded fake
// Firestore read through the SAME MomentService production uses, a
// controllable audio player, and one pump helper.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_queue_list.dart';

import 'voice_moment_test_doubles.dart';

const listenViewerUid = 'me';

VoiceMoment listenMoment(
  String id, {
  String author = 'nadia',
  String authorName = 'Nadia Rutkowska',
  String caption = 'Before the city wakes up',
  int likes = 0,
  int comments = 0,
  int durationSeconds = 45,
  Duration age = const Duration(hours: 2),

  /// Null = PERMANENT under the availability contract.
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
    durationSeconds: durationSeconds,
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

Map<String, dynamic> listenMomentDoc(VoiceMoment moment) => <String, dynamic>{
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

/// Seeds one comment on [momentId]. A voice reply carries a duration; a
/// text reply never does (the projection refuses the mix).
Future<void> seedListenComment(
  FakeFirebaseFirestore db, {
  required String momentId,
  required String id,
  String authorId = 'ola',
  String authorName = 'Ola',
  String text = 'I needed that morning too.',
  bool voice = false,
  int durationSeconds = 12,
  int minutesAgo = 30,
}) => db
    .collection('voiceMoments')
    .doc(momentId)
    .collection('comments')
    .doc(id)
    .set(<String, dynamic>{
      'type': voice ? 'voice' : 'text',
      'authorId': authorId,
      'authorName': authorName,
      'text': voice ? '' : text,
      'durationSeconds': voice ? durationSeconds : null,
      'createdAt': Timestamp.fromDate(
        DateTime.now().subtract(Duration(minutes: minutesAgo)),
      ),
    });

class ListenHarness {
  ListenHarness({
    required this.db,
    required this.moments,
    required this.feed,
    required this.players,
    required this.navigatorKey,
    required this.queue,
  });

  final FakeFirebaseFirestore db;
  final MomentService moments;
  final HomeFeedService feed;
  final List<FakePreviewAudioPlayer> players;
  final GlobalKey<NavigatorState> navigatorKey;
  final MomentNeighbourQueue queue;

  FakePreviewAudioPlayer get player => players.single;
}

MockFirebaseAuth listenAuth({String uid = listenViewerUid}) =>
    MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid));

/// Pumps [MomentDetailScreen] as the pushed route it really is, over a
/// stand-in feed, so Back has somewhere to go.
Future<ListenHarness> pumpListenDetail(
  WidgetTester tester, {
  required VoiceMoment moment,
  Size size = const Size(390, 844),
  String viewerUid = listenViewerUid,
  List<VoiceMoment>? neighbours,
  MomentNeighbourQueue? queue,
  Duration playerDuration = const Duration(seconds: 45),
  bool seedMoment = true,
  Future<void> Function(FakeFirebaseFirestore db)? seed,
  ThemeData? theme,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final db = FakeFirebaseFirestore();
  if (seedMoment) {
    await db
        .collection('voiceMoments')
        .doc(moment.id)
        .set(listenMomentDoc(moment));
  }
  if (seed != null) await seed(db);
  final auth = listenAuth(uid: viewerUid);
  final moments = MomentService(
    firestore: db,
    auth: auth,
    storage: MockFirebaseStorage(),
    readService: VoiceMomentReadService(
      viewInvoker: fakeVoiceMomentViewInvoker(
        firestore: db,
        viewerUid: viewerUid,
      ),
    ),
    mediaAccessInvoker: fakeMomentMediaAccessInvoker(),
  );
  final feed = HomeFeedService(firestore: db, auth: auth);
  final players = <FakePreviewAudioPlayer>[];
  final navigatorKey = GlobalKey<NavigatorState>();
  final neighbourQueue = queue ?? MomentNeighbourQueue();

  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: theme ?? AppTheme.darkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const Scaffold(body: Center(child: Text('FEED'))),
    ),
  );
  unawaited(
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MomentDetailScreen(
          moment: moment,
          momentService: moments,
          feedService: feed,
          auth: auth,
          neighbours: neighbours,
          neighbourQueue: neighbourQueue,
          playerFactory: () {
            final player = FakePreviewAudioPlayer(duration: playerDuration);
            players.add(player);
            return player;
          },
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }

  return ListenHarness(
    db: db,
    moments: moments,
    feed: feed,
    players: players,
    navigatorKey: navigatorKey,
    queue: neighbourQueue,
  );
}

/// Starts the one main player and drives it to [position].
Future<void> playTo(
  WidgetTester tester,
  ListenHarness harness,
  Duration position,
) async {
  await tester.tap(find.byKey(const ValueKey('moment-detail-play')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  harness.player.emitPosition(position);
  await tester.pump();
}
