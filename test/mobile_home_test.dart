import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/messages/data/services/global_chat_service.dart';
import 'package:yovoice/features/messages/presentation/screens/global_chat_screen.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
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
    VoidCallback? onCreateRoom,
  }) {
    final firebaseAuth = auth();
    return MobileHome(
      onOpenRoom: onOpenRoom ?? (_) {},
      onOpenDiscover: onDiscover ?? () {},
      onOpenFriends: onFriends ?? () {},
      onOpenNotifications: () {},
      onOpenProfile: () {},
      onCreateMoment: onCreateMoment ?? () {},
      onCreateRoom: onCreateRoom ?? () {},
      onOpenComments: (_) {},
      roomService: RoomService(firestore: db, auth: firebaseAuth),
      friendService: FriendService(firestore: db, auth: firebaseAuth),
      profileService: ProfileService(firestore: db, auth: firebaseAuth),
      feedService: HomeFeedService(firestore: db, auth: firebaseAuth),
      globalChatService: GlobalChatService(firestore: db, auth: firebaseAuth),
      currentUserId: uid,
    );
  }

  void usePhone(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('renders the briefing modules from real data and drops the '
      'retired hero composition', (tester) async {
    // Tall viewport: mobile Home is a long feed now, and a lazy ListView
    // only builds what fits. Phone-width layout is asserted by the
    // dedicated size tests below.
    usePhone(tester, const Size(390, 2600));
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
    // The four questions Home answers, in order, and nothing else.
    expect(find.text('Moments from your circle'), findsOneWidget);
    expect(find.text('Rooms for you'), findsOneWidget);
    expect(find.text('Your active rooms'), findsOneWidget);
    expect(find.text('Global Chat'), findsOneWidget);

    double y(String label) => tester.getTopLeft(find.text(label)).dy;
    expect(y('Moments from your circle'), lessThan(y('Rooms for you')));
    expect(y('Rooms for you'), lessThan(y('Your active rooms')));
    expect(y('Your active rooms'), lessThan(y('Global Chat')));

    // The room appears ONCE, on one board — not in three sections.
    expect(find.text('Evening Talks'), findsOneWidget);
    // The banner's count chip: the room's own participantCount.
    expect(find.text('8'), findsOneWidget);

    // Retired compositions are gone.
    for (final removed in [
      'LIVE NOW',
      'FEATURED',
      'Your circle',
      'Recommended now',
      'Live around you',
    ]) {
      expect(find.text(removed), findsNothing, reason: '\$removed returned');
    }

    // Mobile carries no Premium or sponsored content.
    expect(find.textContaining('Check plans'), findsNothing);
    expect(find.text('SPONSORED EXAMPLE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actions reuse the existing flows', (tester) async {
    usePhone(tester, const Size(390, 2600));
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

    // One primary action per room, on one board. The phone banner
    // shortens the label to fit beside the chips and the face pile.
    await tester.tap(find.text('Join').first);
    await tester.pump();
    expect(opened?.name, 'Evening Talks');

    // Discover is reached from the Moments empty state's Find creators —
    // the rail is where people discovery lives now.
    await tester.tap(find.text('Find creators'));
    await tester.pump();
    expect(discover, 1);

    await tester.tap(find.text('Record a Moment'));
    await tester.pump();
    expect(moment, 1);

    // Friends is a bottom-navigation destination now, not a Home card.
    expect(friends, 0);
  });

  testWidgets('no live rooms: compact honest empty states', (tester) async {
    usePhone(tester, const Size(390, 844));
    await tester.pumpWidget(host(buildHome()));
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.textContaining('No rooms to show yet'),
      findsOneWidget,
    );
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
  group('Global conversations', () {
    Future<void> seedGlobal({
      required String id,
      required String sender,
      required String content,
      bool isDeleted = false,
      Duration age = const Duration(minutes: 1),
    }) async {
      await db
          .collection('globalChat')
          .doc('main')
          .collection('messages')
          .doc(id)
          .set(<String, dynamic>{
            'senderId': sender,
            'senderName': sender,
            'senderPhotoUrl': null,
            'senderIsCreator': false,
            'senderIsStaff': false,
            'content': isDeleted ? '' : content,
            'sentAt': Timestamp.fromDate(DateTime.now().subtract(age)),
            'isDeleted': isDeleted,
            'deletedBy': isDeleted ? 'mod' : null,
            'deletedAt': null,
          });
    }

    testWidgets('renders real messages and opens the existing Global Chat '
        'screen', (tester) async {
      usePhone(tester, const Size(390, 2600));
      await seedGlobal(id: 'm1', sender: 'Ola', content: 'hello world');
      await seedGlobal(
        id: 'm2',
        sender: 'Jonas',
        content: 'anyone up for a room',
        age: const Duration(minutes: 2),
      );

      await tester.pumpWidget(host(buildHome()));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Global conversations'), findsOneWidget);
      expect(find.text('hello world'), findsOneWidget);
      expect(find.text('anyone up for a room'), findsOneWidget);

      await tester.tap(find.text('Open Global Chat'));
      await tester.pumpAndSettle();

      // The real screen, hosting the canonical panel.
      expect(find.byType(GlobalChatScreen), findsOneWidget);
    });

    testWidgets('a moderated message never appears in the preview', (
      tester,
    ) async {
      usePhone(tester, const Size(390, 2600));
      await seedGlobal(id: 'm1', sender: 'Ola', content: 'still here');
      await seedGlobal(
        id: 'm2',
        sender: 'Spammer',
        content: 'buy followers',
        isDeleted: true,
        age: const Duration(seconds: 30),
      );

      await tester.pumpWidget(host(buildHome()));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('still here'), findsOneWidget);
      expect(find.text('buy followers'), findsNothing);
      expect(find.text('Spammer'), findsNothing);
    });

    testWidgets('an empty channel says so rather than showing nothing', (
      tester,
    ) async {
      usePhone(tester, const Size(390, 2600));
      await tester.pumpWidget(host(buildHome()));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Global conversations'), findsOneWidget);
      expect(
        find.text('No messages yet — say the first thing.'),
        findsOneWidget,
      );
    });

    testWidgets('the section fits a 320pt phone without overflow', (
      tester,
    ) async {
      usePhone(tester, const Size(320, 640));
      await seedGlobal(
        id: 'm1',
        sender: 'SomebodyWithAVeryLongDisplayName',
        content:
            'a long message that would happily run past the edge of a '
            'narrow phone if nothing constrained it',
      );

      await tester.pumpWidget(host(buildHome()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the preview subscription is dropped with the widget', (
      tester,
    ) async {
      usePhone(tester, const Size(390, 2600));
      await seedGlobal(id: 'm1', sender: 'Ola', content: 'hello world');

      await tester.pumpWidget(host(buildHome()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('hello world'), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(milliseconds: 100));

      // A write after teardown must not reach a live listener.
      await seedGlobal(
        id: 'm2',
        sender: 'Late',
        content: 'after disposal',
        age: Duration.zero,
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
    });
  });
}
