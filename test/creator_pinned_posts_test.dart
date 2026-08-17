import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_pinned_moment_screen.dart';
import 'package:yovoice/features/creator/presentation/screens/creator_pinned_posts_screen.dart';
import 'package:yovoice/features/creator/presentation/widgets/creator_pinned_moment_card.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';

void main() {
  const creatorId = 'creator-1';
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;

  setUp(() {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: creatorId,
        email: 'creator@yovoice.app',
        isEmailVerified: true,
      ),
    );
  });

  Map<String, dynamic> moment({
    required String id,
    String authorId = creatorId,
    int schemaVersion = 2,
    String status = 'published',
    bool isPublished = true,
    bool isDeleted = false,
    String caption = 'A real Moment for followers',
  }) => {
    'id': id,
    'schemaVersion': schemaVersion,
    'status': status,
    'isDeleted': isDeleted,
    'authorId': authorId,
    'authorName': 'Creator',
    'authorPhotoUrl': null,
    'caption': caption,
    'audioUrl': 'https://example.invalid/$id.m4a',
    'durationSeconds': 18,
    'likeCount': 7,
    'commentCount': 3,
    'isPublished': isPublished,
    'createdAt': Timestamp.fromDate(DateTime(2026, 8, 17)),
  };

  Future<void> seedMoment(String id, {Map<String, dynamic>? data}) =>
      db.collection('voiceMoments').doc(id).set(data ?? moment(id: id));

  Future<void> seedPin(String momentId, {Map<String, dynamic>? data}) => db
      .collection('creatorPinnedPosts')
      .doc(creatorId)
      .set(
        data ??
            {
              'schemaVersion': 1,
              'creatorId': creatorId,
              'momentId': momentId,
              'pinnedAt': Timestamp.fromDate(DateTime(2026, 8, 17)),
              'updatedAt': Timestamp.fromDate(DateTime(2026, 8, 17)),
            },
      );

  CreatorPinnedPostService service({
    PinnedPostMutationInvoker? mutationInvoker,
  }) => CreatorPinnedPostService(
    firestore: db,
    auth: auth,
    mutationInvoker: mutationInvoker ?? (_) async => const {},
  );

  MomentService momentService() =>
      MomentService(firestore: db, auth: auth, storage: MockFirebaseStorage());

  void useSize(WidgetTester tester, Size size, {double textScale = 1}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget host(Widget child, {double textScale = 1}) => MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: child,
    ),
  );

  test('service rejects ids outside the exact backend grammar', () async {
    final api = service();
    for (final invalid in ['bad/id', 'white space', 'ę', '', 'a' * 129]) {
      await expectLater(
        api.setPinnedMoment(invalid),
        throwsA(isA<ArgumentError>()),
      );
    }
  });

  test('service preserves an opaque Creator UID byte-for-byte', () async {
    const opaqueCreatorId = 'opaque użytkownik';
    const pinnedMomentId = 'moment_opaque_creator';
    await db.collection('creatorPinnedPosts').doc(opaqueCreatorId).set({
      'schemaVersion': 1,
      'creatorId': opaqueCreatorId,
      'momentId': pinnedMomentId,
      'pinnedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
      'updatedAt': Timestamp.fromMillisecondsSinceEpoch(1000),
    });

    final pin = await service().watchPinForCreator(opaqueCreatorId).first;

    expect(pin?.creatorId, opaqueCreatorId);
    expect(pin?.momentId, pinnedMomentId);
  });

  test(
    'service sends only the selected Moment identity to the callable seam',
    () async {
      final calls = <String?>[];
      final api = service(
        mutationInvoker: (momentId) async {
          calls.add(momentId);
          return {'pinned': momentId != null};
        },
      );
      await api.setPinnedMoment('moment_1-safe');
      await api.setPinnedMoment(null);
      expect(calls, ['moment_1-safe', null]);
    },
  );

  test(
    'public stream switches its exact Moment listener on a fast re-pin',
    () async {
      await seedMoment('m1');
      await seedMoment(
        'm2',
        data: moment(id: 'm2', caption: 'Replacement Moment'),
      );
      await seedPin('m1');
      final iterator = StreamIterator(
        service()
            .watchPinnedPostForCreator(creatorId)
            .where((value) => value != null),
      );
      addTearDown(iterator.cancel);

      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 2)),
        isTrue,
      );
      expect(iterator.current!.moment.id, 'm1');

      await seedPin('m2');
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 2)),
        isTrue,
      );
      expect(iterator.current!.moment.id, 'm2');
      expect(iterator.current!.moment.caption, 'Replacement Moment');
    },
  );

  testWidgets(
    'public card follows pin and Moment changes and fails closed immediately',
    (tester) async {
      await seedMoment('m1');
      await seedMoment(
        'm2',
        data: moment(id: 'm2', caption: 'Replacement Moment'),
      );
      await seedPin('m1');

      await tester.pumpWidget(
        host(
          Scaffold(
            body: CreatorPinnedMomentCard(
              creatorId: creatorId,
              service: service(),
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('A real Moment for followers'), findsOneWidget);

      await seedPin('m2');
      for (
        var attempt = 0;
        attempt < 20 && find.text('Replacement Moment').evaluate().isEmpty;
        attempt += 1
      ) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.text('Replacement Moment'), findsOneWidget);
      expect(find.text('A real Moment for followers'), findsNothing);

      // An update from the old subscription must not overwrite the fast re-pin.
      await db.collection('voiceMoments').doc('m1').update({
        'caption': 'Stale old update',
      });
      await tester.pump();
      expect(find.text('Replacement Moment'), findsOneWidget);
      expect(find.text('Stale old update'), findsNothing);

      await db.collection('voiceMoments').doc('m2').update({
        'status': 'deleting',
        'isPublished': false,
        'isDeleted': true,
      });
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('PINNED VOICE MOMENT'), findsNothing);
    },
  );

  testWidgets('pinned Moment opens as playable content, not comments alone', (
    tester,
  ) async {
    useSize(tester, const Size(320, 844), textScale: 2);
    final pinnedMoment = VoiceMoment(
      id: 'playable',
      authorId: creatorId,
      authorName: 'Creator',
      authorPhotoUrl: null,
      caption: 'Listen to the pinned story',
      audioUrl: 'https://example.invalid/playable.m4a',
      durationSeconds: 18,
      likeCount: 7,
      commentCount: 3,
      isPublished: true,
      createdAt: DateTime(2026, 8, 17),
      schemaVersion: 2,
      status: 'published',
    );

    await tester.pumpWidget(
      host(CreatorPinnedMomentScreen(moment: pinnedMoment), textScale: 2),
    );
    await tester.pump();

    expect(find.text('Pinned Voice Moment'), findsOneWidget);
    expect(find.text('Listen to the pinned story'), findsOneWidget);
    expect(find.byType(MomentCard), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mode_comment_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('malformed pin and legacy Moment never render publicly', (
    tester,
  ) async {
    await seedMoment(
      'legacy',
      data: moment(id: 'legacy', schemaVersion: 0, status: 'legacy'),
    );
    await seedPin('legacy');
    await tester.pumpWidget(
      host(CreatorPinnedMomentCard(creatorId: creatorId, service: service())),
    );
    await tester.pump();
    expect(find.text('PINNED VOICE MOMENT'), findsNothing);

    await seedPin(
      'legacy',
      data: {
        'schemaVersion': 1,
        'creatorId': 'wrong-creator',
        'momentId': 'legacy',
        'pinnedAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      },
    );
    await tester.pump();
    expect(find.text('PINNED VOICE MOMENT'), findsNothing);

    await seedPin(
      'legacy',
      data: {
        'schemaVersion': 1,
        'creatorId': creatorId,
        'momentId': 'legacy',
        'pinnedAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'unexpectedClientField': true,
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('PINNED VOICE MOMENT'), findsNothing);

    for (final unsafeMomentId in ['bad/path', 'unicode-ę']) {
      await seedPin(
        unsafeMomentId,
        data: {
          'schemaVersion': 1,
          'creatorId': creatorId,
          'momentId': unsafeMomentId,
          'pinnedAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('PINNED VOICE MOMENT'), findsNothing);
    }

    await seedMoment(
      'malformed',
      data: {
        ...moment(id: 'malformed'),
        'caption': 123,
      },
    );
    await seedPin('malformed');
    await tester.pumpAndSettle();
    expect(find.text('PINNED VOICE MOMENT'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'management screen offers only canonical published owned Moments',
    (tester) async {
      useSize(tester, const Size(1440, 900));
      await seedMoment('eligible');
      await seedMoment(
        'legacy',
        data: moment(id: 'legacy', schemaVersion: 0, status: 'legacy'),
      );
      await seedMoment(
        'draft',
        data: moment(id: 'draft', status: 'uploading', isPublished: false),
      );
      await seedMoment(
        'deleted',
        data: moment(
          id: 'deleted',
          status: 'deleting',
          isPublished: false,
          isDeleted: true,
        ),
      );
      await seedMoment(
        'other',
        data: moment(id: 'other', authorId: 'someone-else'),
      );

      await tester.pumpWidget(
        host(
          CreatorPinnedPostsScreen(
            isRootTab: true,
            pinnedPostService: service(),
            momentService: momentService(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('1 available'), findsOneWidget);
      expect(find.text('A real Moment for followers'), findsOneWidget);
      expect(find.text('Pin'), findsOneWidget);
    },
  );

  testWidgets(
    'pin/unpin mutation stays real and reflects the server projection',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await seedMoment('m1');
      final api = service(
        mutationInvoker: (momentId) async {
          if (momentId == null) {
            await db.collection('creatorPinnedPosts').doc(creatorId).delete();
          } else {
            await seedPin(momentId);
          }
          return {'pinned': momentId != null};
        },
      );
      await tester.pumpWidget(
        host(
          CreatorPinnedPostsScreen(
            isRootTab: true,
            pinnedPostService: api,
            momentService: momentService(),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Pin'));
      await tester.pump();
      await tester.pump();
      expect(find.text('PINNED'), findsOneWidget);
      expect(find.text('Unpin'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(r'Pinned Voice Moment: A real Moment for followers'),
        ),
        findsOneWidget,
      );
      final unpinTarget = find.bySemanticsLabel('Remove pinned Voice Moment');
      expect(unpinTarget, findsOneWidget);
      expect(tester.getSize(unpinTarget).height, greaterThanOrEqualTo(48));

      await tester.tap(find.text('Unpin'));
      await tester.pump();
      await tester.pump();
      expect(find.text('PINNED'), findsNothing);
      expect(find.text('Pin'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('management screen is responsive across supported widths', (
    tester,
  ) async {
    await seedMoment('m1');
    addTearDown(tester.view.reset);
    for (final width in [320.0, 390.0, 768.0, 1100.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        host(
          KeyedSubtree(
            key: ValueKey(width),
            child: CreatorPinnedPostsScreen(
              isRootTab: true,
              pinnedPostService: service(),
              momentService: momentService(),
            ),
          ),
          textScale: 2,
        ),
      );
      for (
        var attempt = 0;
        attempt < 20 && find.text('1 available').evaluate().isEmpty;
        attempt += 1
      ) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.text('Pinned post'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Pin'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Pin'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });

  testWidgets('public pinned card is responsive across supported widths', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await seedMoment('m1');
    await seedPin('m1');
    addTearDown(tester.view.reset);
    for (final width in [320.0, 390.0, 768.0, 1100.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 568);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        host(
          Scaffold(
            body: KeyedSubtree(
              key: ValueKey(width),
              child: CreatorPinnedMomentCard(
                creatorId: creatorId,
                service: service(),
                onOpen: (_) {},
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('PINNED VOICE MOMENT'), findsOneWidget);
      final playTarget = find.bySemanticsLabel(
        RegExp(r'Play pinned Voice Moment'),
      );
      expect(playTarget, findsOneWidget);
      expect(tester.getSize(playTarget).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
    semantics.dispose();
  });

  testWidgets('public card can switch between self and foreign profiles', (
    tester,
  ) async {
    const foreignCreator = 'creator-2';
    await seedMoment('self-moment');
    await seedPin('self-moment');
    await db
        .collection('voiceMoments')
        .doc('foreign-moment')
        .set(
          moment(
            id: 'foreign-moment',
            authorId: foreignCreator,
            caption: 'Foreign creator Moment',
          ),
        );
    await db.collection('creatorPinnedPosts').doc(foreignCreator).set({
      'schemaVersion': 1,
      'creatorId': foreignCreator,
      'momentId': 'foreign-moment',
      'pinnedAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });

    await tester.pumpWidget(
      host(CreatorPinnedMomentCard(creatorId: creatorId, service: service())),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('A real Moment for followers'), findsOneWidget);

    await tester.pumpWidget(
      host(
        CreatorPinnedMomentCard(creatorId: foreignCreator, service: service()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Foreign creator Moment'), findsOneWidget);
    expect(find.text('A real Moment for followers'), findsNothing);
  });
}
