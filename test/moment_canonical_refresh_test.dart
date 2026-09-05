import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';

const _viewerId = 'refresh_viewer';

void main() {
  group('MomentDetailScreen canonical refresh', () {
    testWidgets('rebuilds do not call the canonical view again', (
      tester,
    ) async {
      final service = _ControlledMomentService();
      late StateSetter rebuildHost;
      await _pumpDetail(
        tester,
        service,
        onHostState: (setter) {
          rebuildHost = setter;
        },
      );
      expect(service.requests, hasLength(1));

      service.requests.single.complete(_view(caption: 'Canonical detail'));
      await tester.pump();
      expect(find.text('Canonical detail'), findsOneWidget);

      for (var index = 0; index < 4; index += 1) {
        rebuildHost(() {});
        await tester.pump();
      }

      expect(service.requests, hasLength(1));
    });

    testWidgets('resume and route return each trigger exactly one refresh', (
      tester,
    ) async {
      final service = _ControlledMomentService();
      await _pumpDetail(tester, service);
      service.requests[0].complete(_view(caption: 'Initial'));
      await tester.pump();

      _resumeApp(tester);
      await tester.pump();
      expect(service.requests, hasLength(2));
      service.requests[1].complete(_view(caption: 'After resume'));
      await tester.pump();

      await _pushAndReturn(tester, const ValueKey('moment-detail-screen'));
      expect(service.requests, hasLength(3));
      service.requests[2].complete(_view(caption: 'After route return'));
      await tester.pump();
      await tester.pump();

      expect(find.text('After route return'), findsOneWidget);
      expect(service.requests, hasLength(3));
    });

    testWidgets('a superseded response cannot overwrite the latest view', (
      tester,
    ) async {
      final service = _ControlledMomentService();
      await _pumpDetail(tester, service);

      _resumeApp(tester);
      await tester.pump();
      expect(service.requests, hasLength(2));

      service.requests[1].complete(_view(caption: 'Fresh projection'));
      await tester.pump();
      expect(find.text('Fresh projection'), findsOneWidget);

      service.requests[0].complete(_view(caption: 'Stale projection'));
      await tester.pump();
      expect(find.text('Fresh projection'), findsOneWidget);
      expect(find.text('Stale projection'), findsNothing);
    });

    for (final code in const <String>[
      'permission-denied',
      'not-found',
      'gone',
    ]) {
      testWidgets('$code clears every stale detail projection', (tester) async {
        final service = _ControlledMomentService();
        await _pumpDetail(tester, service);
        service.requests[0].complete(
          _view(
            caption: 'Private stale caption',
            comment: 'Private stale comment',
          ),
        );
        await tester.pump();
        expect(find.text('Private stale caption'), findsOneWidget);
        expect(find.text('Private stale comment'), findsOneWidget);

        _resumeApp(tester);
        await tester.pump();
        service.requests[1].completeError(
          FirebaseFunctionsException(code: code, message: 'Unavailable'),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.byKey(const ValueKey('moment-detail-gone')),
          findsOneWidget,
        );
        expect(find.text('Private stale caption'), findsNothing);
        expect(find.text('Private stale comment'), findsNothing);
      });
    }
  });

  group('MomentCommentsScreen canonical refresh', () {
    testWidgets('rebuilds do not call the canonical comments view again', (
      tester,
    ) async {
      final service = _ControlledMomentService();
      late StateSetter rebuildHost;
      await _pumpComments(
        tester,
        service,
        onHostState: (setter) {
          rebuildHost = setter;
        },
      );
      expect(service.requests, hasLength(1));

      service.requests.single.complete(_view(comment: 'Canonical comment'));
      await tester.pump();
      expect(find.text('Canonical comment'), findsOneWidget);

      for (var index = 0; index < 4; index += 1) {
        rebuildHost(() {});
        await tester.pump();
      }

      expect(service.requests, hasLength(1));
    });

    testWidgets('resume and route return each trigger exactly one refresh', (
      tester,
    ) async {
      final service = _ControlledMomentService();
      await _pumpComments(tester, service);
      service.requests[0].complete(_view(comment: 'Initial comment'));
      await tester.pump();

      _resumeApp(tester);
      await tester.pump();
      expect(service.requests, hasLength(2));
      service.requests[1].complete(_view(comment: 'After resume'));
      await tester.pump();

      await _pushAndReturn(tester, const ValueKey('moment-comments-screen'));
      expect(service.requests, hasLength(3));
      service.requests[2].complete(_view(comment: 'After route return'));
      await tester.pump();
      await tester.pump();

      expect(find.text('After route return'), findsOneWidget);
      expect(service.requests, hasLength(3));
    });

    testWidgets('a superseded response cannot overwrite fresh comments', (
      tester,
    ) async {
      final service = _ControlledMomentService();
      await _pumpComments(tester, service);

      _resumeApp(tester);
      await tester.pump();
      expect(service.requests, hasLength(2));

      service.requests[1].complete(_view(comment: 'Fresh comment'));
      await tester.pump();
      expect(find.text('Fresh comment'), findsOneWidget);

      service.requests[0].complete(_view(comment: 'Stale comment'));
      await tester.pump();
      expect(find.text('Fresh comment'), findsOneWidget);
      expect(find.text('Stale comment'), findsNothing);
    });

    for (final code in const <String>[
      'permission-denied',
      'not-found',
      'gone',
    ]) {
      testWidgets('$code clears the comments screen cache', (tester) async {
        final service = _ControlledMomentService();
        await _pumpComments(tester, service);
        service.requests[0].complete(_view(comment: 'Private stale comment'));
        await tester.pump();
        expect(find.text('Private stale comment'), findsOneWidget);

        _resumeApp(tester);
        await tester.pump();
        service.requests[1].completeError(
          FirebaseFunctionsException(code: code, message: 'Unavailable'),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.byKey(const ValueKey('moment-comments-gone')),
          findsOneWidget,
        );
        expect(find.text('Private stale comment'), findsNothing);
      });
    }
  });
}

MockFirebaseAuth _auth() =>
    MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _viewerId));

VoiceMoment _moment({String caption = 'Seed projection'}) {
  final createdAt = DateTime.utc(2026, 8, 30, 12);
  return VoiceMoment(
    id: 'refresh_moment',
    authorId: '',
    authorName: 'Moment author',
    authorPhotoUrl: null,
    caption: caption,
    audioUrl: null,
    durationSeconds: 12,
    likeCount: 0,
    commentCount: 1,
    isPublished: true,
    createdAt: createdAt,
    expiresAt: DateTime.utc(2036),
    schemaVersion: 2,
    status: 'published',
    hasAuthorizedMedia: true,
  );
}

VoiceMomentViewV2 _view({
  String caption = 'Canonical projection',
  String comment = 'Canonical comment',
}) => VoiceMomentViewV2(
  moment: _moment(caption: caption),
  comments: <MomentComment>[
    MomentComment(
      id: 'refresh_comment',
      type: 'text',
      authorId: '',
      authorName: 'Comment author',
      authorPhotoUrl: null,
      text: comment,
      durationSeconds: 0,
      createdAt: DateTime.utc(2026, 8, 30, 12, 1),
    ),
  ],
  commentsTruncated: false,
  nextCommentCursor: null,
  topReactions: const <MomentReactor>[],
);

Future<void> _pumpDetail(
  WidgetTester tester,
  _ControlledMomentService service, {
  ValueChanged<StateSetter>? onHostState,
}) async {
  final auth = _auth();
  final db = FakeFirebaseFirestore();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      navigatorObservers: <NavigatorObserver>[appRouteObserver],
      home: StatefulBuilder(
        builder: (context, setState) {
          onHostState?.call(setState);
          return MomentDetailScreen(
            key: const ValueKey('refresh-detail-host'),
            moment: _moment(),
            momentService: service,
            feedService: HomeFeedService(firestore: db, auth: auth),
            auth: auth,
          );
        },
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpComments(
  WidgetTester tester,
  _ControlledMomentService service, {
  ValueChanged<StateSetter>? onHostState,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      navigatorObservers: <NavigatorObserver>[appRouteObserver],
      home: StatefulBuilder(
        builder: (context, setState) {
          onHostState?.call(setState);
          return MomentCommentsScreen(
            key: const ValueKey('refresh-comments-host'),
            moment: _moment(),
            momentService: service,
            auth: _auth(),
          );
        },
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pushAndReturn(
  WidgetTester tester,
  ValueKey<String> screenKey,
) async {
  final navigator = Navigator.of(tester.element(find.byKey(screenKey)));
  final route = MaterialPageRoute<void>(
    builder: (_) => const Scaffold(body: Text('Temporary child route')),
  );
  unawaited(navigator.push<void>(route));
  await tester.pumpAndSettle();
  navigator.pop();
  await tester.pumpAndSettle();
}

void _resumeApp(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

final class _ControlledMomentService extends MomentService {
  _ControlledMomentService()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: _auth(),
        storage: MockFirebaseStorage(),
      );

  final List<Completer<VoiceMomentViewV2>> requests =
      <Completer<VoiceMomentViewV2>>[];

  @override
  Future<VoiceMomentViewV2> loadMomentView(
    String momentId, {
    String? commentCursor,
    int commentLimit = 7,
    int reactionLimit = 3,
  }) {
    final request = Completer<VoiceMomentViewV2>();
    requests.add(request);
    return request.future;
  }
}
