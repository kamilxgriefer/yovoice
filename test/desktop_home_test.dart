import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

/// Pulse Home (desktop) coverage: every module must render REAL data,
/// the section actions must delegate to the shell's fixed-slot
/// navigation (never a route), and the whole screen must fit the two
/// required desktop sizes without overflow.
void main() {
  const uid = 'me-uid';

  late FakeFirebaseFirestore db;

  MockFirebaseAuth auth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: 'me@yovoice.app', displayName: 'Kamil'),
  );

  Future<void> seedRoom({
    required String id,
    required String name,
    required String description,
    int participants = 12,
  }) async {
    await db.collection('rooms').doc(id).set({
      'hostId': 'host-$id',
      'hostName': 'Host',
      'name': name,
      'description': description,
      'category': 'talk',
      'visibility': 'public',
      'language': 'English',
      'participantCount': participants,
      'memberCount': 0,
      'isLive': true,
      'roomType': 'community',
      'status': 'active',
      'experience': 'community',
      'createdAt': Timestamp.now(),
    });
    await db
        .collection('rooms')
        .doc(id)
        .collection('participants')
        .doc('speaker-$id')
        .set({
          'userId': 'speaker-$id',
          'displayName': 'Speaker $id',
          'role': 'host',
          'isMuted': false,
          'isSpeaker': true,
        });
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'Kamil',
      'email': 'me@yovoice.app',
    });
  });

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  DesktopHome buildHome({
    void Function(VoiceRoom)? onOpenRoom,
    VoidCallback? onSeeAll,
    VoidCallback? onFriends,
    VoidCallback? onStartRoom,
  }) {
    final firebaseAuth = auth();
    return DesktopHome(
      onOpenRoom: onOpenRoom ?? (_) {},
      onSeeAllRooms: onSeeAll ?? () {},
      onViewAllFriends: onFriends ?? () {},
      onStartRoom: onStartRoom ?? () {},
      roomService: RoomService(firestore: db, auth: firebaseAuth),
      friendService: FriendService(firestore: db, auth: firebaseAuth),
      profileService: ProfileService(firestore: db, auth: firebaseAuth),
    );
  }

  void useDesktop(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  setUp(ProfileService.resetCurrentProfileCache);
  tearDown(ProfileService.resetCurrentProfileCache);

  testWidgets('renders the Pulse Home modules from real live-room data', (
    tester,
  ) async {
    useDesktop(tester, const Size(1440, 820));
    await seedRoom(
      id: 'r1',
      name: 'Late night conversations',
      description: 'Real people. Honest talks.',
      participants: 186,
    );
    await seedRoom(
      id: 'r2',
      name: 'Night owls',
      description: 'Late talks for open minds.',
    );

    await tester.pumpWidget(host(buildHome()));
    await tester.pump(const Duration(milliseconds: 120));

    // Compact greeting — no emoji, no giant heading.
    expect(find.textContaining('Kamil'), findsWidgets);
    // Quick-scan row + featured + recommendations, all from real rooms.
    expect(find.text('Live around you'), findsOneWidget);
    expect(find.text('FEATURED LIVE'), findsOneWidget);
    expect(find.text('Late night conversations'), findsWidgets);
    expect(find.text('Real people. Honest talks.'), findsWidgets);
    expect(find.text('Your circle'), findsOneWidget);
    expect(find.text('Join room'), findsOneWidget);
    expect(find.text('186 listening'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('section actions delegate to the shell — Join opens the real '
      'room, See all and View all friends fire their callbacks', (
    tester,
  ) async {
    useDesktop(tester, const Size(1440, 820));
    await seedRoom(
      id: 'r1',
      name: 'Late night conversations',
      description: 'Real people.',
    );

    VoiceRoom? opened;
    var seeAll = 0;
    var friends = 0;
    var startRoom = 0;

    await tester.pumpWidget(
      host(
        buildHome(
          onOpenRoom: (room) => opened = room,
          onSeeAll: () => seeAll++,
          onFriends: () => friends++,
          onStartRoom: () => startRoom++,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    await tester.tap(find.text('Join room'));
    await tester.pump();
    expect(opened?.name, 'Late night conversations');

    await tester.tap(find.text('See all').first);
    await tester.pump();
    expect(seeAll, 1);

    await tester.tap(find.text('View all friends'));
    await tester.pump();
    expect(friends, 1);

    await tester.tap(find.text('Start a room'));
    await tester.pump();
    expect(startRoom, 1);
  });

  testWidgets('no live rooms: honest empty states, never invented rooms', (
    tester,
  ) async {
    useDesktop(tester, const Size(1440, 820));
    await tester.pumpWidget(host(buildHome()));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('No public rooms are live right now.'), findsOneWidget);
    expect(find.text('Nothing is live yet'), findsOneWidget);
    // The "For you" rail hides entirely rather than showing filler.
    expect(find.text('For you'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1440, 820), const Size(1440, 620)]) {
    testWidgets('lays out without overflow at ${size.width.toInt()}x'
        '${size.height.toInt()}', (tester) async {
      useDesktop(tester, size);
      await seedRoom(id: 'r1', name: 'Room one', description: 'One');
      await seedRoom(id: 'r2', name: 'Room two', description: 'Two');
      await seedRoom(id: 'r3', name: 'Room three', description: 'Three');

      await tester.pumpWidget(host(buildHome()));
      await tester.pump(const Duration(milliseconds: 120));

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('narrow desktop centre stacks Featured and Your circle '
      'instead of squeezing them', (tester) async {
    useDesktop(tester, const Size(700, 820));
    await seedRoom(id: 'r1', name: 'Room one', description: 'One');

    await tester.pumpWidget(host(buildHome()));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Your circle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
