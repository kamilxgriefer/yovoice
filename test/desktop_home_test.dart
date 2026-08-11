import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

/// Pulse Home (desktop) coverage: every module must render REAL data,
/// the section actions must delegate to the shell's fixed-slot
/// navigation (never a route), and the whole screen must fit every
/// supported desktop size without overflow.
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
    String hostId = '',
    String hostName = 'Host',
    Duration age = Duration.zero,
  }) async {
    await db.collection('rooms').doc(id).set({
      'hostId': hostId.isEmpty ? 'host-$id' : hostId,
      'hostName': hostName,
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
      // watchLivePublicRooms orders by createdAt desc, so age decides
      // which room is Featured and which fall through to "For you".
      'createdAt': Timestamp.fromDate(DateTime.now().subtract(age)),
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

  Future<void> seedFriend(String friendId, String name) async {
    await db.collection('users').doc(friendId).set({
      'uid': friendId,
      'displayName': name,
      'email': '$friendId@yovoice.app',
      'isOnline': true,
    });
    await db
        .collection('users')
        .doc(uid)
        .collection('friends')
        .doc(friendId)
        .set({'friendId': friendId, 'createdAt': Timestamp.now()});
  }

  Future<void> seedFollowing(String creatorId, String name) async {
    await db.collection('users').doc(creatorId).set({
      'uid': creatorId,
      'displayName': name,
      'username': name.toLowerCase(),
    });
    await db
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(creatorId)
        .set({
          'uid': creatorId,
          'displayName': name,
          'username': name.toLowerCase(),
          'followedAt': Timestamp.now(),
        });
  }

  Future<void> seedMoment({
    required String id,
    required String authorId,
    required String authorName,
    required String caption,
    Duration age = const Duration(minutes: 30),
    int durationSeconds = 42,
  }) async {
    await db.collection('voiceMoments').doc(id).set({
      'authorId': authorId,
      'authorName': authorName,
      'caption': caption,
      'audioUrl': 'https://example.invalid/$id.m4a',
      'durationSeconds': durationSeconds,
      'likeCount': 0,
      'commentCount': 0,
      'isPublished': true,
      'createdAt': Timestamp.fromDate(DateTime.now().subtract(age)),
    });
  }

  Future<void> seedConversation({
    required String id,
    required String otherId,
    required String otherName,
    required String lastMessage,
    int unread = 0,
  }) async {
    await db.collection('conversations').doc(id).set({
      'participantIds': [uid, otherId],
      'participantNames': {uid: 'Kamil', otherId: otherName},
      'participantEmails': {
        uid: 'me@yovoice.app',
        otherId: '$otherId@yovoice.app',
      },
      'participantPhotoUrls': <String, String>{},
      'unreadCounts': {uid: unread, otherId: 0},
      'lastMessage': lastMessage,
      'lastMessageType': 'text',
      'lastMessageSenderId': otherId,
      'updatedAt': Timestamp.now(),
      'createdAt': Timestamp.now(),
      'archivedBy': <String>[],
      'mutedBy': <String>[],
    });
  }

  Future<void> seedClub({
    required String id,
    required String name,
    String? lastMessage,
  }) async {
    await db.collection('clubs').doc(id).set({
      'name': name,
      'description': 'A club',
      'ownerId': 'owner-$id',
      'ownerName': 'Owner',
      'privacy': 'public',
      'defaultLanguage': 'English',
      'memberCount': 3,
      'onlineCount': 0,
      'defaultChatChannelId': 'general',
      'defaultVoiceChannelId': 'lounge',
      'announcementChannelId': 'announcements',
      'createdAt': Timestamp.now(),
    });
    await db.collection('users').doc(uid).collection('clubs').doc(id).set({
      'clubId': id,
      'joinedAt': Timestamp.now(),
    });
    if (lastMessage != null) {
      await db
          .collection('clubs')
          .doc(id)
          .collection('channels')
          .doc('general')
          .collection('messages')
          .doc('m1')
          .set({
            'senderId': 'someone',
            'senderName': 'Ola',
            'content': lastMessage,
            'sentAt': Timestamp.now(),
            'isDeleted': false,
          });
    }
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
    void Function(VoiceMoment)? onOpenMoment,
    VoidCallback? onCreateMoment,
    VoidCallback? onSeeAllMoments,
    void Function(Conversation)? onOpenConversation,
    void Function(Club)? onOpenClub,
    VoidCallback? onSeeAllChats,
    VoidCallback? onOpenClubs,
  }) {
    final firebaseAuth = auth();
    final notifications = NotificationService(
      firestore: db,
      auth: firebaseAuth,
    );
    return DesktopHome(
      currentUserId: uid,
      onOpenRoom: onOpenRoom ?? (_) {},
      onSeeAllRooms: onSeeAll ?? () {},
      onViewAllFriends: onFriends ?? () {},
      onStartRoom: onStartRoom ?? () {},
      onOpenMoment: onOpenMoment ?? (_) {},
      onCreateMoment: onCreateMoment ?? () {},
      onSeeAllMoments: onSeeAllMoments ?? () {},
      onOpenConversation: onOpenConversation ?? (_) {},
      onOpenClub: onOpenClub ?? (_) {},
      onSeeAllChats: onSeeAllChats ?? () {},
      onOpenClubs: onOpenClubs ?? () {},
      roomService: RoomService(firestore: db, auth: firebaseAuth),
      friendService: FriendService(firestore: db, auth: firebaseAuth),
      profileService: ProfileService(firestore: db, auth: firebaseAuth),
      feedService: HomeFeedService(firestore: db, auth: firebaseAuth),
      messageService: MessageService(
        firestore: db,
        auth: firebaseAuth,
        notificationService: notifications,
      ),
      clubService: ClubService(
        firestore: db,
        auth: firebaseAuth,
        storage: MockFirebaseStorage(),
        notificationService: notifications,
      ),
      clubChatService: ClubChatService(firestore: db, auth: firebaseAuth),
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
      age: const Duration(minutes: 5),
    );

    await tester.pumpWidget(host(buildHome()));
    await tester.pump(const Duration(milliseconds: 120));

    // Compact greeting — no emoji, no giant heading.
    expect(find.textContaining('Kamil'), findsWidgets);
    // Every section of the redesigned surface, in order.
    expect(find.text('Moments from your circle'), findsOneWidget);
    expect(find.text('Live around you'), findsOneWidget);
    expect(find.text('FEATURED LIVE'), findsOneWidget);
    expect(find.text('Late night conversations'), findsWidgets);
    expect(find.text('Real people. Honest talks.'), findsWidgets);
    expect(find.text('Your circle'), findsOneWidget);
    expect(find.text('Join room'), findsOneWidget);
    expect(find.text('186 listening'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the two obsolete actions are gone: no "Start a room" in Your '
      'circle, and Home never renders a sidebar Moment action', (tester) async {
    useDesktop(tester, const Size(1440, 820));
    await seedRoom(id: 'r1', name: 'Room one', description: 'One');

    await tester.pumpWidget(host(buildHome()));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Start a room'), findsNothing);
    expect(find.text('Create your Moment'), findsNothing);
    // Room creation is still reachable from Home's own empty state only
    // when nothing is live; the rail owns it the rest of the time.
    expect(find.text('Your circle'), findsOneWidget);
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

    await tester.pumpWidget(
      host(
        buildHome(
          onOpenRoom: (room) => opened = room,
          onSeeAll: () => seeAll++,
          onFriends: () => friends++,
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

  group('Moments from your circle', () {
    testWidgets('shows one tile per person from real friend/following '
        'Moments, plus the user\'s own Moment slot', (tester) async {
      useDesktop(tester, const Size(1440, 820));
      await seedFriend('friend-1', 'Ola');
      await seedFollowing('creator-1', 'Marek');
      await seedMoment(
        id: 'm1',
        authorId: 'friend-1',
        authorName: 'Ola',
        caption: 'Morning thoughts',
      );
      await seedMoment(
        id: 'm2',
        authorId: 'creator-1',
        authorName: 'Marek',
        caption: 'Studio update',
        age: const Duration(days: 3),
        durationSeconds: 95,
      );
      // A stranger the user neither follows nor is friends with.
      await seedMoment(
        id: 'm3',
        authorId: 'stranger',
        authorName: 'Nobody',
        caption: 'Not in the circle',
      );

      await tester.pumpWidget(host(buildHome()));
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Your Moment'), findsOneWidget);
      expect(find.text('Ola'), findsWidgets);
      expect(find.text('Marek'), findsOneWidget);
      // Nobody outside friends/following/self may appear.
      expect(find.text('Nobody'), findsNothing);
      // Real state only: fresh Moments read "New", older ones show their
      // real duration.
      expect(find.text('New'), findsWidgets);
      expect(find.text('1:35'), findsOneWidget);
    });

    testWidgets('a Moment tile opens the existing viewer and the plus opens '
        'the existing creation flow', (tester) async {
      useDesktop(tester, const Size(1440, 820));
      await seedFriend('friend-1', 'Ola');
      await seedMoment(
        id: 'm1',
        authorId: 'friend-1',
        authorName: 'Ola',
        caption: 'Morning thoughts',
      );

      VoiceMoment? opened;
      var created = 0;
      var seeAllMoments = 0;

      await tester.pumpWidget(
        host(
          buildHome(
            onOpenMoment: (moment) => opened = moment,
            onCreateMoment: () => created++,
            onSeeAllMoments: () => seeAllMoments++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      await tester.tap(find.text('Ola').first);
      await tester.pump();
      expect(opened?.id, 'm1');

      await tester.tap(find.byTooltip('Record a Voice Moment'));
      await tester.pump();
      expect(created, 1);

      await tester.tap(find.text('See all').first);
      await tester.pump();
      expect(seeAllMoments, 1);
    });

    testWidgets('empty circle: a compact state with one Discover action, '
        'never a blank band', (tester) async {
      useDesktop(tester, const Size(1440, 820));
      var discover = 0;

      await tester.pumpWidget(host(buildHome(onSeeAll: () => discover++)));
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Moments from your circle'), findsOneWidget);
      // Creation stays reachable even with nothing to show.
      expect(find.text('Your Moment'), findsOneWidget);
      expect(find.text('Find creators'), findsOneWidget);

      await tester.tap(find.text('Find creators'));
      await tester.pump();
      expect(discover, 1);
    });
  });

  group('For you', () {
    // Tall enough that the section is genuinely on screen: with the
    // Moments strip above it, "For you" sits below the fold on a 820px
    // laptop and the page scrolls to it, which is the intended behaviour.
    testWidgets('compact editorial cards carry host, topic, chips and a Join '
        'affordance — all from real room fields', (tester) async {
      useDesktop(tester, const Size(1440, 1400));
      await seedRoom(id: 'r1', name: 'Featured one', description: 'First');
      await seedRoom(
        id: 'r2',
        name: 'Design critique',
        description: 'Bring your work',
        hostName: 'Marta',
        participants: 24,
        age: const Duration(minutes: 5),
      );

      await tester.pumpWidget(host(buildHome()));
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('For you'), findsOneWidget);
      expect(find.text('Design critique'), findsWidgets);
      expect(find.text('Bring your work'), findsWidgets);
      // Host identity and the real chips, not decoration.
      expect(find.text('Marta'), findsOneWidget);
      expect(find.text('talk'), findsWidgets);
      expect(find.text('English'), findsWidgets);
      expect(find.text('Join'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a card opens the real room through the shell callback', (
      tester,
    ) async {
      useDesktop(tester, const Size(1440, 1400));
      await seedRoom(id: 'r1', name: 'Featured one', description: 'First');
      await seedRoom(
        id: 'r2',
        name: 'Design critique',
        description: 'Bring',
        age: const Duration(minutes: 5),
      );

      VoiceRoom? opened;
      await tester.pumpWidget(
        host(buildHome(onOpenRoom: (room) => opened = room)),
      );
      await tester.pump(const Duration(milliseconds: 150));

      await tester.tap(find.text('Join').first);
      await tester.pump();
      expect(opened?.name, 'Design critique');
    });
  });

  group('Conversations', () {
    testWidgets('All merges real club and direct conversations; each filter '
        'narrows to its own real records', (tester) async {
      useDesktop(tester, const Size(1440, 1700));
      await seedFriend('friend-1', 'Ola');
      await seedConversation(
        id: 'c1',
        otherId: 'friend-1',
        otherName: 'Ola',
        lastMessage: 'See you tonight',
        unread: 3,
      );
      await seedConversation(
        id: 'c2',
        otherId: 'stranger-1',
        otherName: 'Piotr',
        lastMessage: 'Hello there',
      );
      await seedClub(id: 'club-1', name: 'Night Owls', lastMessage: 'Welcome');

      await tester.pumpWidget(host(buildHome()));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      // All: everything real, nothing invented.
      expect(find.text('Ola'), findsWidgets);
      expect(find.text('Piotr'), findsWidgets);
      expect(find.text('Night Owls'), findsOneWidget);
      expect(find.text('3'), findsWidgets, reason: 'real unread count');

      // Clubs: only the club conversation.
      await tester.tap(find.text('Clubs'));
      await tester.pump();
      expect(find.text('Night Owls'), findsOneWidget);
      expect(find.text('Piotr'), findsNothing);

      // Friends: only the conversation whose counterpart is a friend.
      await tester.tap(find.text('Friends'));
      await tester.pump();
      expect(find.text('Ola'), findsWidgets);
      expect(find.text('Piotr'), findsNothing);
      expect(find.text('Night Owls'), findsNothing);

      // Private: the data model's direct conversations, in full.
      await tester.tap(find.text('Private'));
      await tester.pump();
      expect(find.text('Ola'), findsWidgets);
      expect(find.text('Piotr'), findsWidgets);
      expect(find.text('Night Owls'), findsNothing);
    });

    testWidgets('a row opens the existing chat / club surface and See all '
        'chats delegates to the shell', (tester) async {
      useDesktop(tester, const Size(1440, 1700));
      await seedConversation(
        id: 'c1',
        otherId: 'friend-1',
        otherName: 'Ola',
        lastMessage: 'See you tonight',
      );
      await seedClub(id: 'club-1', name: 'Night Owls', lastMessage: 'Welcome');

      Conversation? openedConversation;
      Club? openedClub;
      var seeAllChats = 0;

      await tester.pumpWidget(
        host(
          buildHome(
            onOpenConversation: (conversation) =>
                openedConversation = conversation,
            onOpenClub: (club) => openedClub = club,
            onSeeAllChats: () => seeAllChats++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Ola'));
      await tester.pump();
      expect(openedConversation?.id, 'c1');

      await tester.tap(find.text('Night Owls'));
      await tester.pump();
      expect(openedClub?.id, 'club-1');

      await tester.tap(find.text('See all chats'));
      await tester.pump();
      expect(seeAllChats, 1);
    });

    testWidgets('each empty filter gets its own contextual state and an '
        'existing action', (tester) async {
      useDesktop(tester, const Size(1440, 1700));
      await tester.pumpWidget(host(buildHome()));
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text('No conversations yet — start one with a friend.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Clubs'));
      await tester.pump();
      expect(find.text('You have not joined a club yet.'), findsOneWidget);
      expect(find.text('Browse Clubs'), findsOneWidget);

      await tester.tap(find.text('Private'));
      await tester.pump();
      expect(find.text('No direct messages yet.'), findsOneWidget);
    });
  });

  for (final size in [
    const Size(1440, 820),
    const Size(1440, 620),
    // The narrowest supported desktop: at the 1100px shell breakpoint the
    // centre column is only ~490px wide with the right column beside it.
    const Size(1100 - 264 - 344, 900),
    const Size(1920, 1080),
  ]) {
    testWidgets('lays out without overflow at ${size.width.toInt()}x'
        '${size.height.toInt()}', (tester) async {
      useDesktop(tester, size);
      await seedFriend('friend-1', 'Ola');
      await seedMoment(
        id: 'm1',
        authorId: 'friend-1',
        authorName: 'Ola',
        caption: 'Morning',
      );
      await seedConversation(
        id: 'c1',
        otherId: 'friend-1',
        otherName: 'Ola',
        lastMessage: 'See you tonight',
        unread: 2,
      );
      await seedRoom(id: 'r1', name: 'Room one', description: 'One');
      await seedRoom(id: 'r2', name: 'Room two', description: 'Two');
      await seedRoom(id: 'r3', name: 'Room three', description: 'Three');

      await tester.pumpWidget(host(buildHome()));
      await tester.pump(const Duration(milliseconds: 200));

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
