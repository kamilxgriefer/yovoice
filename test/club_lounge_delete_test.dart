import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_image_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/room_settings_screen.dart';

/// Club lounges (including Family Rooms) are deleted by deleting their CLUB
/// through the owner-only `deleteClubSelf` callable — `deleteRoomSelf`
/// refuses `club_lounge_*` rooms outright, so the old wiring produced a
/// dialog whose Delete button could only ever show a server refusal.
///
/// These tests pin the routing on both delete surfaces (the Home board menu
/// and Room settings):
///  * lounge + club owner   → honest club copy, `deleteClubSelf`, and the
///    room delete path is never touched;
///  * lounge + non-owner    → no delete control at all, even when the
///    lounge's possibly-stale `hostId` still matches the caller;
///  * ordinary room         → byte-for-byte the flow it always had.
void main() {
  const ownerUid = 'me';
  const clubId = 'family';

  VoiceRoom room({
    String id = 'room-1',
    String name = 'Evening Talks',
    String hostId = ownerUid,
    String? storedClubId,
  }) {
    return VoiceRoom(
      id: id,
      hostId: hostId,
      hostName: 'Host',
      hostPhotoUrl: null,
      name: name,
      description: 'A place to talk.',
      category: 'talk',
      visibility: storedClubId == null ? 'public' : 'private',
      language: 'English',
      maxParticipants: null,
      participantCount: 1,
      memberCount: 1,
      isLive: false,
      roomType: RoomType.community,
      status: RoomStatus.active,
      imageUrl: null,
      approvalRequired: false,
      slowModeSeconds: 0,
      autoMuteNewUsers: false,
      membersCanStartVoice: true,
      createdAt: null,
      updatedAt: null,
      clubId: storedClubId,
      storedClubId: storedClubId,
    );
  }

  VoiceRoom lounge() => room(
    id: 'club_lounge_$clubId',
    name: 'family Lounge',
    storedClubId: clubId,
  );

  MockFirebaseAuth auth({String uid = ownerUid}) => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: '$uid@yovoice.app', displayName: uid),
  );

  Future<FakeFirebaseFirestore> seededDb({
    String clubOwnerId = ownerUid,
  }) async {
    final db = FakeFirebaseFirestore();
    await db.collection('clubs').doc(clubId).set({
      'name': 'family',
      'description': 'The family club.',
      'ownerId': clubOwnerId,
      'ownerName': 'Owner',
      'privacy': 'inviteOnly',
      'type': 'family',
      'status': 'active',
      'defaultLanguage': 'English',
      'memberCount': 2,
      'onlineCount': 1,
      'defaultChatChannelId': 'chat',
      'defaultVoiceChannelId': 'voice',
      'announcementChannelId': 'announce',
    });
    return db;
  }

  ClubService clubService(
    FakeFirebaseFirestore db, {
    _RecordingFunctions? functions,
    String uid = ownerUid,
  }) {
    return ClubService(
      firestore: db,
      auth: auth(uid: uid),
      storage: MockFirebaseStorage(),
      functions: functions,
    );
  }

  Widget host(Widget child) => MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(body: child),
  );

  void useSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('ClubService.deleteClub', () {
    test('calls deleteClubSelf with the club id and accepts the contract '
        'success shape', () async {
      final functions = _RecordingFunctions();
      final service = clubService(await seededDb(), functions: functions);

      await service.deleteClub(clubId);

      expect(functions.calls, hasLength(1));
      expect(functions.calls.single.name, 'deleteClubSelf');
      expect(functions.calls.single.payload, {'clubId': clubId});
    });

    test('refuses an empty club id locally, before any callable', () async {
      final functions = _RecordingFunctions();
      final service = clubService(await seededDb(), functions: functions);

      await expectLater(service.deleteClub('   '), throwsArgumentError);
      expect(functions.calls, isEmpty);
    });

    test('refuses to claim success when the result is not the contract '
        'shape', () async {
      final functions = _RecordingFunctions(result: {'clubId': clubId});
      final service = clubService(await seededDb(), functions: functions);

      await expectLater(service.deleteClub(clubId), throwsStateError);
    });

    test('surfaces failed-precondition (deletion already in progress) as '
        'the refusal it is, never as silent success', () async {
      final functions = _RecordingFunctions(
        failure: FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'This Club is already being deleted.',
        ),
      );
      final service = clubService(await seededDb(), functions: functions);

      await expectLater(
        service.deleteClub(clubId),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (error) => error.code,
            'code',
            'failed-precondition',
          ),
        ),
      );
    });

    test('surfaces permission-denied for a caller who is not the club '
        'owner', () async {
      final functions = _RecordingFunctions(
        failure: FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'Only the Club owner can delete it.',
        ),
      );
      final service = clubService(await seededDb(), functions: functions);

      await expectLater(
        service.deleteClub(clubId),
        throwsA(isA<FirebaseFunctionsException>()),
      );
    });
  });

  group('ClubService.watchClub under deletion', () {
    test('errors when the club document disappears mid-watch, which is what '
        'routes ClubOverviewScreen to its existing error state', () async {
      final db = await seededDb();
      final service = clubService(db);
      final events = <Object>[];
      final errors = <Object>[];
      final subscription = service
          .watchClub(clubId)
          .listen(events.add, onError: errors.add);
      await pumpEventQueue();
      expect(events, hasLength(1));

      await db.collection('clubs').doc(clubId).delete();
      await pumpEventQueue();

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      await subscription.cancel();
    });
  });

  group('Home board: club lounge', () {
    testWidgets('the club owner gets the club delete — honest copy, '
        'deleteClubSelf, and deleteRoomSelf is unreachable', (tester) async {
      useSize(tester, const Size(390, 844));
      final functions = _RecordingFunctions();
      final service = clubService(await seededDb(), functions: functions);
      var roomDeleteCalls = 0;

      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: HomeRoomBanner(
              room: lounge(),
              onJoin: (_) {},
              compact: true,
              currentUserId: ownerUid,
              clubService: service,
              onManageOwnedRoom: () {},
              onDeleteOwnedRoom: () async => roomDeleteCalls++,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('Manage your room'));
      await tester.pumpAndSettle();
      expect(find.text('Delete club…'), findsOneWidget);
      expect(find.text('Delete room…'), findsNothing);

      await tester.tap(find.text('Delete club…'));
      await tester.pumpAndSettle();
      expect(find.text('Delete the Club "family"?'), findsOneWidget);
      expect(
        find.textContaining(
          'its lounge, chat, channels, members and invites',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('This cannot be undone'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(functions.calls, hasLength(1));
      expect(functions.calls.single.name, 'deleteClubSelf');
      expect(functions.calls.single.payload, {'clubId': clubId});
      expect(roomDeleteCalls, 0, reason: 'deleteRoomSelf must never run');
      expect(find.text('Delete the Club "family"?'), findsNothing);
    });

    testWidgets('a non-owner gets NO delete control, even when the '
        'lounge\'s stale hostId still matches them', (tester) async {
      useSize(tester, const Size(390, 844));
      final functions = _RecordingFunctions();
      final service = clubService(
        await seededDb(clubOwnerId: 'someone-else'),
        functions: functions,
      );

      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: HomeRoomBanner(
              room: lounge(),
              onJoin: (_) {},
              compact: true,
              currentUserId: ownerUid,
              clubService: service,
              onManageOwnedRoom: () {},
              onDeleteOwnedRoom: () async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('Manage your room'));
      await tester.pumpAndSettle();
      expect(find.text('Room settings'), findsOneWidget);
      expect(find.text('Delete club…'), findsNothing);
      expect(find.text('Delete room…'), findsNothing);
      expect(functions.calls, isEmpty);
    });

    testWidgets('a lounge whose club cannot be read fails closed: no '
        'delete control at all', (tester) async {
      useSize(tester, const Size(390, 844));
      // No clubService injected and no Firebase app: the menu must degrade
      // to settings-only rather than fall back to the room delete.
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: HomeRoomBanner(
              room: lounge(),
              onJoin: (_) {},
              compact: true,
              currentUserId: ownerUid,
              onManageOwnedRoom: () {},
              onDeleteOwnedRoom: () async {},
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Manage your room'));
      await tester.pumpAndSettle();
      expect(find.text('Room settings'), findsOneWidget);
      expect(find.text('Delete club…'), findsNothing);
      expect(find.text('Delete room…'), findsNothing);
    });

    testWidgets('a server refusal is shown in the dialog instead of '
        'pretending the Club was deleted', (tester) async {
      useSize(tester, const Size(390, 844));
      final functions = _RecordingFunctions(
        failure: FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'This Club is already being deleted.',
        ),
      );
      final service = clubService(await seededDb(), functions: functions);

      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: HomeRoomBanner(
              room: lounge(),
              onJoin: (_) {},
              compact: true,
              currentUserId: ownerUid,
              clubService: service,
              onManageOwnedRoom: () {},
              onDeleteOwnedRoom: () async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('Manage your room'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete club…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Dialog stays open with the server's own words.
      expect(find.text('Delete the Club "family"?'), findsOneWidget);
      expect(
        find.textContaining('already being deleted'),
        findsOneWidget,
      );
    });
  });

  group('Home board: state recycling', () {
    testWidgets('REGRESSION: swapping the tile to another lounge retargets '
        'the menu — Delete club… must never erase the previous tile\'s club',
        (tester) async {
      // Home\'s lists reorder on every join/leave, and Flutter reuses the
      // element at a position. Before the fix the menu state bound its club
      // stream in initState alone, so after a reorder "Delete club…" showed
      // one club\'s name and deleted ANOTHER — found in review, pinned here.
      useSize(tester, const Size(390, 844));
      final db = await seededDb();
      await db.collection('clubs').doc('test').set({
        'name': 'test',
        'description': 'The test club.',
        'ownerId': ownerUid,
        'ownerName': 'Owner',
        'privacy': 'inviteOnly',
        'type': 'community',
        'status': 'active',
        'defaultLanguage': 'English',
        'memberCount': 1,
        'onlineCount': 0,
        'defaultChatChannelId': 'chat',
        'defaultVoiceChannelId': 'voice',
        'announcementChannelId': 'announce',
      });
      final functions = _RecordingFunctions();
      final service = clubService(db, functions: functions);

      Widget bannerFor(VoiceRoom r) => host(
        SingleChildScrollView(
          child: HomeRoomBanner(
            room: r,
            onJoin: (_) {},
            compact: true,
            currentUserId: ownerUid,
            clubService: service,
            onManageOwnedRoom: () {},
            onDeleteOwnedRoom: () async {},
          ),
        ),
      );

      await tester.pumpWidget(bannerFor(lounge()));
      await tester.pump();
      await tester.pump();

      // The SAME tree position now carries the OTHER lounge — exactly what a
      // list reorder does to a recycled element.
      await tester.pumpWidget(
        bannerFor(
          room(
            id: 'club_lounge_test',
            name: 'test Lounge',
            storedClubId: 'test',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('Manage your room'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete club…'));
      await tester.pumpAndSettle();

      expect(find.text('Delete the Club "test"?'), findsOneWidget);
      expect(
        find.text('Delete the Club "family"?'),
        findsNothing,
        reason: 'the recycled state must not keep the previous club',
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(functions.calls.single.payload, {'clubId': 'test'});
    });
  });

  group('Home board: ordinary room (pinned)', () {
    testWidgets('the room delete flow is byte-for-byte what it was',
        (tester) async {
      useSize(tester, const Size(390, 844));
      var deleted = 0;

      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: HomeRoomBanner(
              room: room(),
              onJoin: (_) {},
              compact: true,
              currentUserId: ownerUid,
              onManageOwnedRoom: () {},
              onDeleteOwnedRoom: () async => deleted++,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Manage your room'));
      await tester.pumpAndSettle();
      expect(find.text('Delete room…'), findsOneWidget);
      expect(find.text('Delete club…'), findsNothing);

      await tester.tap(find.text('Delete room…'));
      await tester.pumpAndSettle();
      expect(find.text('Delete "Evening Talks"?'), findsOneWidget);
      expect(
        find.text(
          'Messages, members and room settings will be permanently '
          'removed. This cannot be undone.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleted, 1);
    });
  });

  group('Room settings', () {
    Future<void> scrollToBottom(WidgetTester tester) async {
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      for (var attempt = 0; attempt < 3; attempt += 1) {
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pump();
      }
    }

    Widget settings(
      VoiceRoom target, {
      required FakeFirebaseFirestore db,
      _RecordingFunctions? functions,
      ClubService? clubs,
    }) {
      final firebaseAuth = auth();
      return MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: RoomSettingsScreen(
          room: target,
          roomService: RoomService(
            firestore: db,
            auth: firebaseAuth,
            functions: functions,
          ),
          roomImageService: RoomImageService(
            storage: MockFirebaseStorage(),
            auth: firebaseAuth,
          ),
          clubService: clubs,
        ),
      );
    }

    testWidgets('lounge + club owner: the delete control is the CLUB '
        'delete and calls deleteClubSelf', (tester) async {
      useSize(tester, const Size(390, 844));
      final db = await seededDb();
      final functions = _RecordingFunctions();
      final clubs = clubService(db, functions: functions);

      await tester.pumpWidget(
        settings(lounge(), db: db, functions: functions, clubs: clubs),
      );
      await tester.pump();
      await tester.pump();
      await scrollToBottom(tester);

      expect(find.text('Delete club'), findsOneWidget);
      expect(find.text('Delete room'), findsNothing);

      await tester.tap(find.text('Delete club'));
      await tester.pumpAndSettle();
      expect(find.text('Delete the Club "family"?'), findsOneWidget);
      expect(
        find.text(
          'This deletes the whole Club — its lounge, chat, channels, '
          'members and invites. This cannot be undone.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(functions.calls, hasLength(1));
      expect(functions.calls.single.name, 'deleteClubSelf');
      expect(functions.calls.single.payload, {'clubId': clubId});
    });

    testWidgets('lounge + non-owner: no delete control of either kind',
        (tester) async {
      useSize(tester, const Size(390, 844));
      final db = await seededDb(clubOwnerId: 'someone-else');
      final functions = _RecordingFunctions();
      final clubs = clubService(db, functions: functions);

      await tester.pumpWidget(
        settings(lounge(), db: db, functions: functions, clubs: clubs),
      );
      await tester.pump();
      await tester.pump();
      await scrollToBottom(tester);

      expect(find.text('Delete club'), findsNothing);
      expect(find.text('Delete room'), findsNothing);
      expect(functions.calls, isEmpty);
    });

    testWidgets('ordinary room: the delete tile and flow are unchanged and '
        'still call deleteRoomSelf', (tester) async {
      useSize(tester, const Size(390, 844));
      final db = await seededDb();
      final functions = _RecordingFunctions();

      await tester.pumpWidget(settings(room(), db: db, functions: functions));
      await tester.pump();
      await scrollToBottom(tester);

      expect(find.text('Delete room'), findsOneWidget);
      expect(find.text('Delete club'), findsNothing);

      await tester.tap(find.text('Delete room'));
      await tester.pumpAndSettle();
      expect(find.text('Delete "Evening Talks"?'), findsOneWidget);
      expect(
        find.text(
          'Messages, members and room settings will be permanently '
          'removed. This cannot be undone.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(functions.calls, hasLength(1));
      expect(functions.calls.single.name, 'deleteRoomSelf');
      expect(functions.calls.single.payload, {'roomId': 'room-1'});
    });
  });
}

class _Call {
  const _Call(this.name, this.payload);
  final String name;
  final Map<String, dynamic> payload;
}

/// The same recording shape content_report_test.dart uses: a fake
/// FirebaseFunctions that records every callable invocation and answers
/// with the configured result, or throws the configured failure.
class _RecordingFunctions implements FirebaseFunctions {
  _RecordingFunctions({this.failure, Map<String, Object?>? result})
    : result = result ?? const {'success': true, 'clubId': 'family'};

  final Object? failure;
  final Map<String, Object?> result;
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
    final failure = owner.failure;
    if (failure != null) throw failure;
    return _FakeResult<T>(Map<Object?, Object?>.from(owner.result) as T);
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
