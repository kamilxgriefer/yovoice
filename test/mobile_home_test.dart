import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
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

  Future<void> seedConversation({
    required String id,
    required String otherName,
    required String lastMessage,
    required Duration age,
    int unread = 0,
  }) async {
    final otherId = 'friend-$id';
    await db.collection('conversations').doc(id).set({
      'participantIds': [uid, otherId],
      'participantNames': {uid: 'Kamil', otherId: otherName},
      'participantEmails': {uid: 'me@yovoice.app', otherId: '$id@yovoice.app'},
      'participantPhotoUrls': <String, String>{},
      'unreadCounts': {uid: unread, otherId: 0},
      'lastMessage': lastMessage,
      'lastMessageType': 'text',
      'lastMessageSenderId': otherId,
      'updatedAt': Timestamp.fromDate(DateTime.now().subtract(age)),
      'createdAt': Timestamp.now(),
      'archivedBy': <String>[],
      'mutedBy': <String>[],
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
    VoidCallback? onProfile,
    ValueChanged<Conversation>? onOpenConversation,
  }) {
    final firebaseAuth = auth();
    return MobileHome(
      onOpenRoom: onOpenRoom ?? (_) {},
      onOpenDiscover: onDiscover ?? () {},
      onOpenFriends: onFriends ?? () {},
      onOpenNotifications: () {},
      onOpenProfile: onProfile ?? () {},
      onCreateMoment: onCreateMoment ?? () {},
      onCreateRoom: onCreateRoom ?? () {},
      onOpenComments: (_) {},
      onOpenConversation: onOpenConversation ?? (_) {},
      onSeeAllChats: () {},
      roomService: RoomService(firestore: db, auth: firebaseAuth),
      friendService: FriendService(firestore: db, auth: firebaseAuth),
      profileService: ProfileService(firestore: db, auth: firebaseAuth),
      feedService: HomeFeedService(firestore: db, auth: firebaseAuth),
      messageService: MessageService(firestore: db, auth: firebaseAuth),
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
    expect(find.text('Your recent chats'), findsOneWidget);

    double y(String label) => tester.getTopLeft(find.text(label)).dy;
    expect(y('Moments from your circle'), lessThan(y('Rooms for you')));
    expect(y('Rooms for you'), lessThan(y('Your active rooms')));
    expect(y('Your active rooms'), lessThan(y('Your recent chats')));

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
      'Global Chat',
      'Global conversations',
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

  testWidgets('header profile is a named 44px keyboard action', (tester) async {
    usePhone(tester, const Size(390, 844));
    var opens = 0;

    await tester.pumpWidget(host(buildHome(onProfile: () => opens += 1)));
    await tester.pump(const Duration(milliseconds: 150));

    final profile = find.bySemanticsLabel('Open your profile');
    expect(profile, findsOneWidget);
    expect(tester.getSize(profile).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(profile).width, greaterThanOrEqualTo(44));
    Focus.of(
      tester.element(find.descendant(of: profile, matching: find.text('K'))),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opens, 1);
  });

  testWidgets('no live rooms: compact honest empty states', (tester) async {
    usePhone(tester, const Size(390, 844));
    await tester.pumpWidget(host(buildHome()));
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.textContaining('No rooms to show yet'), findsOneWidget);
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
  group('Your recent chats', () {
    testWidgets('shows only the three newest conversations and opens one', (
      tester,
    ) async {
      usePhone(tester, const Size(390, 2600));
      for (var index = 0; index < 4; index++) {
        await seedConversation(
          id: 'c$index',
          otherName: 'Friend $index',
          lastMessage: 'Message $index',
          age: Duration(minutes: index),
          unread: index,
        );
      }
      Conversation? opened;
      await tester.pumpWidget(
        host(buildHome(onOpenConversation: (value) => opened = value)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Friend 0'), findsOneWidget);
      expect(find.text('Friend 1'), findsOneWidget);
      expect(find.text('Friend 2'), findsOneWidget);
      expect(find.text('Friend 3'), findsNothing);
      await tester.tap(find.text('Friend 0'));
      expect(opened?.id, 'c0');
    });

    testWidgets('an empty list offers the real friends destination', (
      tester,
    ) async {
      usePhone(tester, const Size(390, 2600));
      await tester.pumpWidget(host(buildHome()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.text('Your latest chats with friends will appear here.'),
        findsOneWidget,
      );
      expect(find.text('Find friends'), findsOneWidget);
    });
  });
}
