import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/offline_voice_moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

/// `voiceMoment` and `voiceMomentComment` are the other two targets the
/// deployed `createContentReport` accepts, and nothing in the app reached
/// them either. Moments is a primary destination with a global feed of
/// strangers' audio, which makes an unreachable report path a bigger hole
/// here than anywhere else.
///
/// Three kinds of surface, because Moments has three places a person
/// meets someone else's content: the full Moment card (the sheet the
/// Following rows open), the feed itself (rows, the story viewer, and on
/// desktop the detail panel), and a comment thread.
///
/// HISTORY: the middle group used to pump the Discover avatar board
/// (`MomentDiscoveryView`). The stories redesign replaced that surface
/// with the feed + story viewer, so those tests were re-targeted — the
/// claims they carried (Report beside Like and Comment, hidden on your
/// own Moment, still on screen at a 2x text scale) all survive against
/// the new surfaces below.
void main() {
  const viewerUid = 'viewer-uid';
  const authorUid = 'author-uid';

  late PublicIdentityRepository originalIdentityRepository;

  setUp(() {
    originalIdentityRepository = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: viewerUid),
      ),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentityRepository;
  });

  // Live inside its 24-hour window: the feed (correctly) refuses to
  // render an expired or expiry-less Moment at all.
  VoiceMoment moment({String id = 'v1', String author = authorUid}) =>
      VoiceMoment(
        id: id,
        authorId: author,
        authorName: 'Author',
        authorPhotoUrl: null,
        caption: 'caption',
        audioUrl: 'https://cdn.example/a.m4a',
        durationSeconds: 12,
        likeCount: 0,
        commentCount: 0,
        isPublished: true,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        expiresAt: DateTime.now().add(const Duration(hours: 22)),
        schemaVersion: 2,
        status: 'published',
        isDeleted: false,
      );

  void useSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('the Following feed card', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      required bool canReport,
      required _RecordingFunctions functions,
      Size size = const Size(390, 844),
    }) async {
      useSize(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MomentCard(
                moment: moment(),
                canReport: canReport,
                isOwn: !canReport,
                offlineService: _StubOfflineService(),
                contentReportService: ContentReportService(
                  functions: functions,
                ),
                onComments: () {},
              ),
            ),
          ),
        ),
      );
      // pumpAndSettle, not pump: the card kicks off an async
      // offline-download lookup on mount, and leaving it in flight fails
      // the binding's pending-timer check.
      await tester.pumpAndSettle();
    }

    testWidgets('reports the Moment through the deployed callable', (
      tester,
    ) async {
      final functions = _RecordingFunctions();
      await pumpCard(tester, canReport: true, functions: functions);

      await tester.tap(find.byKey(const ValueKey('report-moment-v1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-reason-hate')));
      await tester.pumpAndSettle();

      expect(functions.calls.single.name, 'createContentReport');
      expect(functions.calls.single.payload, <String, Object?>{
        'targetType': 'voiceMoment',
        'momentId': 'v1',
        'reason': 'hate',
        'requestId': ContentReportService.requestIdFor(
          const ReportedContent.voiceMoment(momentId: 'v1'),
        ),
      });
    });

    testWidgets('your own Moment has no report control', (tester) async {
      final functions = _RecordingFunctions();
      await pumpCard(tester, canReport: false, functions: functions);

      expect(find.byKey(const ValueKey('report-moment-v1')), findsNothing);
    });

    for (final size in <String, Size>{
      'mobile': Size(360, 780),
      'tablet': Size(834, 1112),
      'desktop': Size(1440, 900),
    }.entries) {
      testWidgets('the card action row survives ${size.key}', (tester) async {
        final functions = _RecordingFunctions();
        await pumpCard(
          tester,
          canReport: true,
          functions: functions,
          size: size.value,
        );

        // Like, comment, report and download all coexist in one row; a
        // narrow phone is where a fourth control would have overflowed.
        expect(find.byKey(const ValueKey('report-moment-v1')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the Moments feed and the story viewer', () {
    Future<void> pumpFeed(
      WidgetTester tester, {
      required _RecordingFunctions functions,
      String author = authorUid,
      Size size = const Size(390, 844),
      double textScale = 1.0,
    }) async {
      useSize(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: MomentsScreen(
              auth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: viewerUid),
              ),
              feedService: _QuietFeed(
                firestore: FakeFirebaseFirestore(),
                auth: MockFirebaseAuth(
                  signedIn: true,
                  mockUser: MockUser(uid: viewerUid),
                ),
              ),
              discoveryService: _StaticDiscovery([moment(author: author)]),
              contentReportService: ContentReportService(functions: functions),
              playerFactory: _SilentPlayer.new,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('a feed row\'s menu offers Report and files it through the '
        'deployed callable', (tester) async {
      final functions = _RecordingFunctions();
      await pumpFeed(tester, functions: functions);

      await tester.tap(find.byKey(const ValueKey('moment-row-menu-v1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-reason-hate')));
      await tester.pumpAndSettle();

      expect(functions.calls.single.name, 'createContentReport');
      expect(functions.calls.single.payload, <String, Object?>{
        'targetType': 'voiceMoment',
        'momentId': 'v1',
        'reason': 'hate',
        'requestId': ContentReportService.requestIdFor(
          const ReportedContent.voiceMoment(momentId: 'v1'),
        ),
      });
    });

    testWidgets('your own Moment\'s row offers Delete, never Report', (
      tester,
    ) async {
      // ADAPTED with the availability amendment: the own-row overflow
      // menu now exists (it carries Details and the author's Delete —
      // the only exit a permanent Moment has), but Report stays for
      // OTHERS' Moments only.
      final functions = _RecordingFunctions();
      await pumpFeed(tester, functions: functions, author: viewerUid);

      expect(find.byKey(const ValueKey('moment-row-v1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('moment-row-menu-v1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('moment-row-delete-v1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('moment-row-report-v1')), findsNothing);
      expect(find.text('Report'), findsNothing);
    });

    testWidgets('the story viewer offers Report beside Like and Comment, '
        'and files it', (tester) async {
      final functions = _RecordingFunctions();
      await pumpFeed(tester, functions: functions);

      await tester.tap(find.byKey(ValueKey('moments-chain-$authorUid')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The three controls share the action row: engagement and safety
      // side by side, never one at the cost of the other.
      expect(find.byKey(const ValueKey('story-like')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-comments')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-report-v1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('story-report-v1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-reason-violence')));
      await tester.pumpAndSettle();

      expect(functions.calls.single.payload['targetType'], 'voiceMoment');
      expect(functions.calls.single.payload['momentId'], 'v1');
      expect(functions.calls.single.payload['reason'], 'violence');
    });

    testWidgets('your own chain in the story viewer has no report control', (
      tester,
    ) async {
      final functions = _RecordingFunctions();
      await pumpFeed(tester, functions: functions, author: viewerUid);

      await tester.tap(find.byKey(ValueKey('moments-chain-$viewerUid')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('story-play-toggle')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-report-v1')), findsNothing);
    });

    testWidgets('the report control stays on screen at a 2x text scale', (
      tester,
    ) async {
      // The old avatar board drained a KNOWN 179-px overflow here; the
      // stories surfaces must not regress to tolerating one. The claim
      // is positional: the count chips squeezing at 2x must never push
      // the safety control past the viewport edge.
      final functions = _RecordingFunctions();
      await pumpFeed(
        tester,
        functions: functions,
        size: const Size(360, 780),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(ValueKey('moments-chain-$authorUid')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.takeException(),
        isNull,
        reason: 'the story viewer must not overflow at a 2x text scale',
      );

      final control = find.byKey(const ValueKey('story-report-v1'));
      expect(control, findsOneWidget);
      final rect = tester.getRect(control);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
    });

    testWidgets('the desktop detail panel offers Report beside Like and '
        'Share, and files it', (tester) async {
      final functions = _RecordingFunctions();
      await pumpFeed(
        tester,
        functions: functions,
        size: const Size(1440, 900),
      );

      expect(find.byKey(const ValueKey('detail-like')), findsOneWidget);
      expect(find.byKey(const ValueKey('detail-share')), findsOneWidget);
      expect(find.byKey(const ValueKey('detail-report-v1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('detail-report-v1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-reason-harassment')));
      await tester.pumpAndSettle();

      expect(functions.calls.single.payload['targetType'], 'voiceMoment');
      expect(functions.calls.single.payload['momentId'], 'v1');
      expect(functions.calls.single.payload['reason'], 'harassment');
    });
  });

  group('a comment thread', () {
    Future<FakeFirebaseFirestore> seedComments() async {
      final db = FakeFirebaseFirestore();
      final comments = db
          .collection('voiceMoments')
          .doc('v1')
          .collection('comments');
      await comments.doc('c-theirs').set(<String, dynamic>{
        'authorId': authorUid,
        'authorName': 'Author',
        'text': 'their comment',
        'type': 'text',
        'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
      });
      await comments.doc('c-mine').set(<String, dynamic>{
        'authorId': viewerUid,
        'authorName': 'Me',
        'text': 'my comment',
        'type': 'text',
        'createdAt': Timestamp.fromDate(DateTime(2026, 8, 2)),
      });
      return db;
    }

    Future<void> pumpThread(
      WidgetTester tester,
      FakeFirebaseFirestore db,
      _RecordingFunctions functions, {
      Size size = const Size(390, 844),
    }) async {
      useSize(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: MomentCommentsScreen(
            moment: moment(),
            firestore: db,
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: viewerUid),
            ),
            contentReportService: ContentReportService(functions: functions),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('reports a comment with its own id, not the Moment', (
      tester,
    ) async {
      final functions = _RecordingFunctions();
      await pumpThread(tester, await seedComments(), functions);

      // Only the other person's comment carries the control.
      expect(find.byKey(const ValueKey('report-comment-c-theirs')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('report-comment-c-mine')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('report-comment-c-theirs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-reason-harassment')));
      await tester.pumpAndSettle();

      expect(functions.calls.single.payload, <String, Object?>{
        'targetType': 'voiceMomentComment',
        'momentId': 'v1',
        'commentId': 'c-theirs',
        'reason': 'harassment',
        'requestId': ContentReportService.requestIdFor(
          const ReportedContent.voiceMomentComment(
            momentId: 'v1',
            commentId: 'c-theirs',
          ),
        ),
      });
    });

    testWidgets('the empty thread still renders', (tester) async {
      final functions = _RecordingFunctions();
      await pumpThread(tester, FakeFirebaseFirestore(), functions);

      expect(find.text('Be the first to comment.'), findsOneWidget);
      expect(find.byIcon(Icons.flag_outlined), findsNothing);
    });

    testWidgets('a long comment keeps the report control on the card', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await db
          .collection('voiceMoments')
          .doc('v1')
          .collection('comments')
          .doc('c-long')
          .set(<String, dynamic>{
            'authorId': authorUid,
            'authorName': 'A name that is itself quite long indeed',
            'text': 'wall of text ' * 40,
            'type': 'text',
            'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
          });

      final functions = _RecordingFunctions();
      await pumpThread(tester, db, functions);

      expect(
        find.byKey(const ValueKey('report-comment-c-long')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    for (final size in <String, Size>{
      'tablet': Size(834, 1112),
      'desktop': Size(1440, 900),
    }.entries) {
      testWidgets('the thread report control renders on ${size.key}', (
        tester,
      ) async {
        final functions = _RecordingFunctions();
        await pumpThread(
          tester,
          await seedComments(),
          functions,
          size: size.value,
        );

        expect(
          find.byKey(const ValueKey('report-comment-c-theirs')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}

class _StubOfflineService implements OfflineVoiceMomentService {
  @override
  Future<bool> isDownloaded(String momentId) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticDiscovery implements MomentDiscoveryService {
  _StaticDiscovery(this.moments);

  final List<VoiceMoment> moments;

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async => MomentDiscoveryFeed(
    moments: moments,
    fetchedCount: moments.length,
    drops: const <String, MomentDropReason>{},
    seed: seed ?? 0,
    poolExhausted: false,
  );

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => const Stream<Map<String, MomentEngagement>>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietFeed extends HomeFeedService {
  _QuietFeed({super.firestore, super.auth});

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.value(const []);

  @override
  Stream<bool> watchLiked(String momentId) => Stream<bool>.value(false);

  @override
  Future<void> toggleLike(String momentId) async {}
}

/// An [audio.AudioPlayer] that never touches a platform channel — the
/// story viewer auto-plays on open, and a real player reports its
/// missing channel asynchronously, after the frame under test.
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

class _Call {
  _Call(this.name, this.payload);
  final String name;
  final Map<String, dynamic> payload;
}

class _RecordingFunctions implements FirebaseFunctions {
  final calls = <_Call>[];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _RecordingCallable(this, name);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingCallable implements HttpsCallable {
  _RecordingCallable(this.owner, this.name);
  final _RecordingFunctions owner;
  final String name;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async {
    owner.calls.add(_Call(name, Map<String, dynamic>.from(parameters! as Map)));
    return _FakeResult<T>({'reportId': 'r1', 'created': true} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResult<T> implements HttpsCallableResult<T> {
  _FakeResult(this.data);
  @override
  final T data;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
