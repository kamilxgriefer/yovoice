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
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';

/// Mobile Home ("Voice Briefing") coverage: real data in every module,
/// the retired hero composition gone, honest empty states, and clean
/// layout at narrow and large phone sizes.
class _StreamFollowService extends FollowService {
  _StreamFollowService({
    required this.stream,
    required super.firestore,
    required super.auth,
  });

  final Stream<List<FollowUser>> stream;

  @override
  Stream<List<FollowUser>> watchFollowing(String userId) => stream;
}

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
    String? hostId,
  }) async {
    await db.collection('rooms').doc(id).set({
      'hostId': hostId ?? 'host-$id',
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

  Future<void> seedFollowing(String userId, String name) async {
    await db.collection('publicProfiles').doc(userId).set({
      'uid': userId,
      'displayName': name,
      'username': name.toLowerCase(),
    });
    await db
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(userId)
        .set({'uid': userId, 'followedAt': Timestamp.now()});
  }

  Future<void> seedFriend(String userId, String name) async {
    await db.collection('publicProfiles').doc(userId).set({
      'uid': userId,
      'displayName': name,
      'username': name.toLowerCase(),
    });
    await db.collection('users').doc(uid).collection('friends').doc(userId).set(
      {'friendId': userId, 'createdAt': Timestamp.now()},
    );
  }

  Future<void> seedMoment({
    required String id,
    required String authorId,
    required String authorName,
    bool withMedia = true,
    Duration age = const Duration(minutes: 5),
  }) async {
    final createdAt = DateTime.now().subtract(age);
    await db.collection('voiceMoments').doc(id).set({
      'authorId': authorId,
      'authorName': authorName,
      if (withMedia) 'mediaGeneration': '1700000000000001',
      if (withMedia) 'mediaContentType': 'audio/mp4',
      if (withMedia) 'mediaSize': 4096,
      'durationSeconds': 8,
      'likeCount': 0,
      'commentCount': 0,
      'isPublished': true,
      'schemaVersion': 2,
      'status': 'published',
      'isDeleted': false,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(createdAt.add(const Duration(hours: 24))),
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
    VoidCallback? onFindCreators,
    VoidCallback? onFriends,
    VoidCallback? onCreateMoment,
    VoidCallback? onCreateRoom,
    VoidCallback? onProfile,
    ValueChanged<VoiceMoment>? onOpenMoment,
    ValueChanged<List<VoiceMoment>>? onOpenChain,
    ValueChanged<Conversation>? onOpenConversation,
    StaffCapabilityService? capabilityService,
    FollowService? followService,
    int unreadNotificationCount = 0,
  }) {
    final firebaseAuth = auth();
    return MobileHome(
      onOpenRoom: onOpenRoom ?? (_) {},
      onOpenDiscover: onDiscover ?? () {},
      onOpenFindCreators: onFindCreators,
      onOpenFriends: onFriends ?? () {},
      onOpenNotifications: () {},
      unreadNotificationCount: unreadNotificationCount,
      onOpenProfile: onProfile ?? () {},
      onCreateMoment: onCreateMoment ?? () {},
      onCreateRoom: onCreateRoom ?? () {},
      onOpenMoment: onOpenMoment ?? (_) {},
      onOpenChain: onOpenChain,
      onOpenComments: (_) {},
      onOpenConversation: onOpenConversation ?? (_) {},
      onSeeAllChats: () {},
      roomService: RoomService(firestore: db, auth: firebaseAuth),
      friendService: FriendService(firestore: db, auth: firebaseAuth),
      followService:
          followService ?? FollowService(firestore: db, auth: firebaseAuth),
      profileService: ProfileService(firestore: db, auth: firebaseAuth),
      feedService: HomeFeedService(firestore: db, auth: firebaseAuth),
      messageService: MessageService(firestore: db, auth: firebaseAuth),
      capabilityService: capabilityService,
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
    var creators = 0;
    var friends = 0;
    var moment = 0;

    await tester.pumpWidget(
      host(
        buildHome(
          onOpenRoom: (room) => opened = room,
          onDiscover: () => discover++,
          onFindCreators: () => creators++,
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

    // A quiet rail contains no filler card or duplicate actions. Recording
    // remains available from the signed-in avatar and its plus badge.
    expect(find.text('Find creators'), findsNothing);
    expect(find.text('Record a Moment'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-your-moment')));
    await tester.pump();
    expect(moment, 1);
    expect(creators, 0);
    expect(discover, 0);

    // Friends is a bottom-navigation destination now, not a Home card.
    expect(friends, 0);
  });

  testWidgets('phone room banners expose owner controls and senior staff '
      'controls without granting them to ordinary visitors', (tester) async {
    usePhone(tester, const Size(390, 1400));
    await seedRoom(
      id: 'mine',
      name: 'My mobile room',
      description: 'Owned here',
      hostId: uid,
    );

    await tester.pumpWidget(host(buildHome()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byTooltip('Manage your room'), findsWidgets);
    expect(find.byIcon(Icons.shield_rounded), findsNothing);

    // Start a fresh screen/session so initState loads the newly injected
    // server capability set rather than retaining the ordinary-account one.
    await tester.pumpWidget(host(const SizedBox.shrink()));
    await tester.pump();
    await tester.pumpWidget(
      host(
        buildHome(
          capabilityService: _StaticCapabilityService(
            const StaffCapabilities(
              staffRole: 'superModerator',
              permanentDeleteSpaces: true,
              endAnyRoom: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.shield_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Delete permanently…'), findsOneWidget);
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

  testWidgets('mobile bell exposes the unread count and a 44px target', (
    tester,
  ) async {
    usePhone(tester, const Size(390, 844));
    await tester.pumpWidget(host(buildHome(unreadNotificationCount: 7)));
    await tester.pump(const Duration(milliseconds: 150));

    final bell = find.bySemanticsLabel('Notifications, 7 unread');
    expect(bell, findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(tester.getSize(bell).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(bell).height, greaterThanOrEqualTo(44));
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

  testWidgets('Moments rail is self plus followed authors with private media', (
    tester,
  ) async {
    usePhone(tester, const Size(390, 1000));
    await seedFriend('friend-only', 'Friend only');
    await seedMoment(
      id: 'friend-moment',
      authorId: 'friend-only',
      authorName: 'Friend only',
    );
    await seedFollowing('followed', 'Followed voice');
    await seedMoment(
      id: 'followed-older',
      authorId: 'followed',
      authorName: 'Followed voice',
      age: const Duration(minutes: 10),
    );
    await seedMoment(
      id: 'followed-newer',
      authorId: 'followed',
      authorName: 'Followed voice',
    );
    await seedFollowing('silent', 'Silent profile');
    await seedMoment(
      id: 'silent-document',
      authorId: 'silent',
      authorName: 'Silent profile',
      withMedia: false,
    );

    List<VoiceMoment>? openedChain;
    await tester.pumpWidget(
      host(buildHome(onOpenChain: (moments) => openedChain = moments)),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.byKey(const ValueKey('home-your-moment')), findsOneWidget);
    expect(find.text('Followed voice'), findsOneWidget);
    expect(find.text('Friend only'), findsNothing);
    expect(find.text('Silent profile'), findsNothing);

    await tester.tap(find.text('Followed voice'));
    await tester.pump();
    expect(openedChain?.map((moment) => moment.id), [
      'followed-older',
      'followed-newer',
    ]);
    expect(openedChain, isNotNull);
    expect(openedChain!.every((moment) => moment.audioUrl == null), isTrue);
    expect(
      openedChain!.every((moment) => moment.mediaGeneration != null),
      isTrue,
    );
  });

  testWidgets('initial following stream failure fails closed to the own tile', (
    tester,
  ) async {
    usePhone(tester, const Size(390, 1000));
    await seedMoment(
      id: 'stream-followed-moment',
      authorId: 'stream-followed',
      authorName: 'Stream followed',
    );
    final firebaseAuth = auth();
    final followService = _StreamFollowService(
      stream: Stream<List<FollowUser>>.error(
        StateError('following unavailable'),
      ),
      firestore: db,
      auth: firebaseAuth,
    );

    await tester.pumpWidget(host(buildHome(followService: followService)));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('Stream followed'), findsNothing);
    expect(find.byKey(const ValueKey('home-your-moment')), findsOneWidget);
  });

  testWidgets('avatar-only Moments rail fits 320px at 200 percent text', (
    tester,
  ) async {
    usePhone(tester, const Size(320, 640));
    await seedFollowing('followed-long', 'Aleksandra Bardzo Długie Nazwisko');
    await seedMoment(
      id: 'followed-long-moment',
      authorId: 'followed-long',
      authorName: 'Aleksandra Bardzo Długie Nazwisko',
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: host(buildHome()),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final own = find.byKey(const ValueKey('home-your-moment'));
    expect(own, findsOneWidget);
    expect(
      MediaQuery.textScalerOf(tester.element(own)).scale(10),
      20,
      reason: 'the regression must exercise 200% text, not the default',
    );
    expect(
      find.textContaining('No Moments from your circle yet'),
      findsNothing,
    );
    expect(find.text('Aleksandra Bardzo Długie Nazwisko'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Play Voice Moment from Aleksandra Bardzo Długie Nazwisko',
      ),
      findsOneWidget,
    );
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

class _StaticCapabilityService extends StaffCapabilityService {
  _StaticCapabilityService(this.value);

  final StaffCapabilities value;

  @override
  Future<StaffCapabilities> load({bool refresh = false}) async => value;
}
