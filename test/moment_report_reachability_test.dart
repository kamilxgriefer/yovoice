import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/offline_voice_moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_discovery_view.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

/// `voiceMoment` and `voiceMomentComment` are the other two targets the
/// deployed `createContentReport` accepts, and nothing in the app reached
/// them either. Moments is now a primary destination with a global
/// discovery feed of strangers' audio, which makes an unreachable report
/// path a bigger hole here than anywhere else.
///
/// Three surfaces, because Moments has three places a person meets
/// someone else's content: the Following feed card, the Discover board's
/// player, and a comment thread.
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
        createdAt: DateTime(2026, 8, 1),
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

  group('the Discover board', () {
    Future<void> pumpStage(
      WidgetTester tester, {
      required _RecordingFunctions functions,
      String author = authorUid,
      Size size = const Size(390, 844),
    }) async {
      useSize(tester, size);
      final db = FakeFirebaseFirestore();
      await db.collection('voiceMoments').doc('v1').set(<String, dynamic>{
        'authorId': author,
        'authorName': 'Author',
        'authorPhotoUrl': null,
        'caption': 'caption',
        'audioUrl': 'https://cdn.example/a.m4a',
        'durationSeconds': 12,
        'likeCount': 0,
        'commentCount': 0,
        'isPublished': true,
        'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
        'schemaVersion': 2,
        'status': 'published',
        'isDeleted': false,
      });
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: viewerUid),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: MomentDiscoveryView(
              discoveryService: MomentDiscoveryService(
                firestore: db,
                auth: auth,
              ),
              auth: auth,
              contentReportService: ContentReportService(functions: functions),
              onOpenComments: (_) {},
              onRecord: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offers Report beside Like and Comment, and files it', (
      tester,
    ) async {
      final functions = _RecordingFunctions();
      await pumpStage(tester, functions: functions);

      expect(find.byKey(const ValueKey('report-discovery-v1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('report-discovery-v1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-reason-violence')));
      await tester.pumpAndSettle();

      expect(functions.calls.single.payload['targetType'], 'voiceMoment');
      expect(functions.calls.single.payload['momentId'], 'v1');
      expect(functions.calls.single.payload['reason'], 'violence');
    });

    testWidgets('your own Moment on the board has no report chip', (
      tester,
    ) async {
      final functions = _RecordingFunctions();
      await pumpStage(tester, functions: functions, author: viewerUid);

      expect(find.byKey(const ValueKey('report-discovery-v1')), findsNothing);
    });

    testWidgets('the report chip stays on screen at a large text scale', (
      tester,
    ) async {
      useSize(tester, const Size(360, 780));
      final db = FakeFirebaseFirestore();
      await db.collection('voiceMoments').doc('v1').set(<String, dynamic>{
        'authorId': authorUid,
        'authorName': 'Author',
        'authorPhotoUrl': null,
        'caption': 'caption',
        'audioUrl': 'https://cdn.example/a.m4a',
        'durationSeconds': 12,
        'likeCount': 0,
        'commentCount': 0,
        'isPublished': true,
        'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
        'schemaVersion': 2,
        'status': 'published',
        'isDeleted': false,
      });
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: viewerUid),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
              size: Size(360, 780),
            ),
            child: Scaffold(
              body: MomentDiscoveryView(
                discoveryService: MomentDiscoveryService(
                  firestore: db,
                  auth: auth,
                ),
                auth: auth,
                contentReportService: ContentReportService(
                  functions: _RecordingFunctions(),
                ),
                onOpenComments: (_) {},
                onRecord: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // This used to drain a KNOWN overflow: the old _PagerControls row
      // ran 179 px past a 360 pt phone at this text scale, with or
      // without the report chip. The pager is gone — the board's order
      // chips and the player's count chips both ellipsize instead — so
      // there is nothing left to tolerate, and this now asserts the
      // stronger thing.
      expect(
        tester.takeException(),
        isNull,
        reason: 'the Discover board must not overflow at a 2x text scale',
      );

      // The assertion is positional rather than "nothing threw": what
      // this test owns is that the third chip did not push the safety
      // control off the edge — Like / Comment / Report wrap onto a
      // second run instead of running past the viewport.
      final chip = find.byKey(const ValueKey('report-discovery-v1'));
      expect(chip, findsOneWidget);
      final rect = tester.getRect(chip);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
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
