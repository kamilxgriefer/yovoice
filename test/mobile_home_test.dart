import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

/// Mobile Home ("Voice Briefing") coverage: real data in every module,
/// the retired hero composition gone, honest empty states, and clean
/// layout at narrow and large phone sizes.
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
    int participants = 8,
  }) async {
    await db.collection('rooms').doc(id).set({
      'hostId': 'host-$id',
      'hostName': 'Host',
      'name': name,
      'description': description,
      'category': 'community',
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
          'displayName': 'Speaker',
          'role': 'host',
          'isMuted': false,
          'isSpeaker': true,
        });
  }

  setUp(() async {
    ProfileService.resetCurrentProfileCache();
    db = FakeFirebaseFirestore();
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'Kamil',
      'email': 'me@yovoice.app',
    });
  });
  tearDown(ProfileService.resetCurrentProfileCache);

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  MobileHome buildHome({
    void Function(VoiceRoom)? onOpenRoom,
    VoidCallback? onDiscover,
    VoidCallback? onFriends,
    VoidCallback? onCreateMoment,
  }) {
    final firebaseAuth = auth();
    return MobileHome(
      onOpenRoom: onOpenRoom ?? (_) {},
      onOpenDiscover: onDiscover ?? () {},
      onOpenFriends: onFriends ?? () {},
      onOpenNotifications: () {},
      onOpenProfile: () {},
      onCreateMoment: onCreateMoment ?? () {},
      onOpenComments: (_) {},
      roomService: RoomService(firestore: db, auth: firebaseAuth),
      friendService: FriendService(firestore: db, auth: firebaseAuth),
      profileService: ProfileService(firestore: db, auth: firebaseAuth),
    );
  }

  void usePhone(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('renders the briefing modules from real data and drops the '
      'retired hero composition', (tester) async {
    usePhone(tester, const Size(390, 844));
    await seedRoom(
      id: 'r1',
      name: 'Evening Talks',
      description: 'Real conversations, real people',
      participants: 8,
    );

    await tester.pumpWidget(host(buildHome()));
    await tester.pump(const Duration(milliseconds: 150));

    // Compact header: greeting + real name, and no emoji.
    expect(find.text('Kamil'), findsOneWidget);
    expect(find.textContaining('👋'), findsNothing);
    // Briefing strip counts come from the live-room stream.
    expect(find.textContaining('room live'), findsOneWidget);
    // Featured room, from the same real data.
    expect(find.text('FEATURED'), findsOneWidget);
    expect(find.text('Evening Talks'), findsWidgets);
    expect(find.text('8 listening'), findsOneWidget);
    // The retired "LIVE NOW" hero heading is gone from mobile Home.
    expect(find.text('LIVE NOW'), findsNothing);
    expect(find.text('Your circle'), findsOneWidget);
    expect(find.text('Your Moment'), findsOneWidget);
    expect(find.text('Recommended now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actions reuse the existing flows', (tester) async {
    usePhone(tester, const Size(390, 844));
    await seedRoom(id: 'r1', name: 'Evening Talks', description: 'Real talk');

    VoiceRoom? opened;
    var discover = 0;
    var friends = 0;
    var moment = 0;

    await tester.pumpWidget(
      host(
        buildHome(
          onOpenRoom: (room) => opened = room,
          onDiscover: () => discover++,
          onFriends: () => friends++,
          onCreateMoment: () => moment++,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    await tester.tap(find.text('Join').first);
    await tester.pump();
    expect(opened?.name, 'Evening Talks');

    await tester.tap(find.text('See all').last);
    await tester.pump();
    expect(discover, 1);

    await tester.tap(find.text('See all').first);
    await tester.pump();
    expect(friends, 1);

    await tester.tap(find.text('Your Moment'));
    await tester.pump();
    expect(moment, 1);
  });

  testWidgets('no live rooms: compact honest empty states', (tester) async {
    usePhone(tester, const Size(390, 844));
    await tester.pumpWidget(host(buildHome()));
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Nothing is live right now'), findsOneWidget);
    // The recommended list hides rather than showing filler rows.
    expect(find.text('Recommended now'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(430, 932),
  ]) {
    testWidgets(
      'lays out cleanly at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        usePhone(tester, size);
        await seedRoom(id: 'r1', name: 'Evening Talks', description: 'Talk');
        await seedRoom(id: 'r2', name: 'new test', description: 'Open talk');
        await seedRoom(id: 'r3', name: 'super test', description: 'Chill');

        await tester.pumpWidget(host(buildHome()));
        await tester.pump(const Duration(milliseconds: 150));

        expect(tester.takeException(), isNull);
      },
    );
  }
}
