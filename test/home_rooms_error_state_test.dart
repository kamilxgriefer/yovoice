import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

/// "Rooms for you" on both live Home compositions, when the room query
/// FAILS rather than returning nothing.
///
/// Both screens read `snapshot.data ?? const <VoiceRoom>[]` with no
/// `hasError` branch and then printed "No rooms to show yet — start one and
/// your community will see it here." That is the same collapse that hid the
/// Discover clubs rail, with an extra harm: it hands the reader an action
/// ("start one") in the one situation where the app does not know whether
/// there are rooms at all.
class _FailingRoomService extends RoomService {
  _FailingRoomService({super.firestore, super.auth});

  @override
  Stream<List<VoiceRoom>> watchLivePublicRooms() =>
      Stream<List<VoiceRoom>>.error(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Missing or insufficient permissions.',
        ),
      );
}

void main() {
  const uid = 'me-uid';

  late FakeFirebaseFirestore db;

  MockFirebaseAuth auth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: 'me@yovoice.app', displayName: 'Kamil'),
  );

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

  void useSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  MobileHome mobileHome({required RoomService rooms}) {
    final firebaseAuth = auth();
    return MobileHome(
      onOpenRoom: (_) {},
      onOpenDiscover: () {},
      onOpenFriends: () {},
      onOpenNotifications: () {},
      onOpenProfile: () {},
      onCreateMoment: () {},
      onCreateRoom: () {},
      onOpenMoment: (_) {},
      onOpenComments: (_) {},
      onOpenConversation: (_) {},
      onSeeAllChats: () {},
      roomService: rooms,
      friendService: FriendService(firestore: db, auth: firebaseAuth),
      profileService: ProfileService(firestore: db, auth: firebaseAuth),
      feedService: HomeFeedService(firestore: db, auth: firebaseAuth),
      messageService: MessageService(firestore: db, auth: firebaseAuth),
      currentUserId: uid,
    );
  }

  DesktopHome desktopHome({required RoomService rooms}) {
    final firebaseAuth = auth();
    return DesktopHome(
      currentUserId: uid,
      onOpenRoom: (_) {},
      onSeeAllRooms: () {},
      onViewAllFriends: () {},
      onStartRoom: () {},
      onOpenMoment: (_) {},
      onCreateMoment: () {},
      onSeeAllMoments: () {},
      onOpenConversation: (_) {},
      onOpenClub: (_) {},
      onSeeAllChats: () {},
      onOpenClubs: () {},
      roomService: rooms,
      friendService: FriendService(firestore: db, auth: firebaseAuth),
      followService: FollowService(firestore: db, auth: firebaseAuth),
      profileService: ProfileService(firestore: db, auth: firebaseAuth),
      feedService: HomeFeedService(firestore: db, auth: firebaseAuth),
      messageService: MessageService(firestore: db, auth: firebaseAuth),
      firebaseAuth: firebaseAuth,
    );
  }

  testWidgets('mobile: a failed room query says so, and never invites the '
      'reader to fix it by starting a room', (tester) async {
    useSize(tester, const Size(390, 2600));

    await tester.pumpWidget(
      host(
        mobileHome(
          rooms: _FailingRoomService(firestore: db, auth: auth()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.textContaining('could not be loaded'), findsOneWidget);
    expect(find.textContaining('No rooms to show yet'), findsNothing);
  });

  testWidgets('mobile: an empty room list still reads as empty', (
    tester,
  ) async {
    useSize(tester, const Size(390, 2600));

    await tester.pumpWidget(
      host(mobileHome(rooms: RoomService(firestore: db, auth: auth()))),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.textContaining('No rooms to show yet'), findsOneWidget);
    expect(find.textContaining('could not be loaded'), findsNothing);
  });

  testWidgets('desktop: a failed room query says so', (tester) async {
    useSize(tester, const Size(1440, 2600));

    await tester.pumpWidget(
      host(
        desktopHome(
          rooms: _FailingRoomService(firestore: db, auth: auth()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.textContaining('could not be loaded'), findsOneWidget);
    expect(find.textContaining('No rooms to show yet'), findsNothing);
  });

  testWidgets('desktop: an empty room list still reads as empty', (
    tester,
  ) async {
    useSize(tester, const Size(1440, 2600));

    await tester.pumpWidget(
      host(desktopHome(rooms: RoomService(firestore: db, auth: auth()))),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.textContaining('No rooms to show yet'), findsOneWidget);
    expect(find.textContaining('could not be loaded'), findsNothing);
  });
}
