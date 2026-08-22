import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_chat_service.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_moments_strip.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
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
    await db.collection('publicProfiles').doc(friendId).set({
      'uid': friendId,
      'displayName': name,
      'username': name.toLowerCase(),
      'photoUrl': null,
      'premiumIdentity': false,
    });
    await db.collection('socialPresence').doc(friendId).set({
      'uid': friendId,
      'isOnline': true,
      'lastSeen': Timestamp.now(),
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
    await db.collection('publicProfiles').doc(creatorId).set({
      'uid': creatorId,
      'displayName': name,
      'username': name.toLowerCase(),
      'photoUrl': null,
      'premiumIdentity': false,
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

    /// Defaults to the shape `finalizeMomentDraft` writes: createdAt +
    /// 24h. Since the expiry contract landed, a Moment without a future
    /// `expiresAt` never renders on Home (see `HomeFeedService`'s
    /// `isActiveAt` filter), so live fixtures must carry one.
    DateTime? expiresAt,
    bool withoutExpiry = false,
  }) async {
    final createdAt = DateTime.now().subtract(age);
    await db.collection('voiceMoments').doc(id).set({
      'authorId': authorId,
      'authorName': authorName,
      'caption': caption,
      'audioUrl': 'https://example.invalid/$id.m4a',
      'durationSeconds': durationSeconds,
      'likeCount': 0,
      'commentCount': 0,
      'isPublished': true,
      'createdAt': Timestamp.fromDate(createdAt),
      if (!withoutExpiry)
        'expiresAt': Timestamp.fromDate(
          expiresAt ?? createdAt.add(const Duration(hours: 24)),
        ),
    });
  }

  Future<void> seedConversation({
    required String id,
    required String otherId,
    required String otherName,
    required String lastMessage,
    int unread = 0,
    Duration age = Duration.zero,
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
      'updatedAt': Timestamp.fromDate(DateTime.now().subtract(age)),
      'createdAt': Timestamp.now(),
      'archivedBy': <String>[],
      'mutedBy': <String>[],
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

  Future<Map<String, dynamic>> invokeFollowMutation(
    Map<String, dynamic> data,
  ) async {
    final targetUserId = data['targetUserId'] as String;
    final following = data['following'] as bool;
    final targetProfile = await db
        .collection('publicProfiles')
        .doc(targetUserId)
        .get();
    final target = targetProfile.data() ?? const <String, dynamic>{};
    final actor = await db.collection('users').doc(uid).get();
    final actorData = actor.data() ?? const <String, dynamic>{};
    final actorFollowing = db
        .collection('users')
        .doc(uid)
        .collection('following')
        .doc(targetUserId);
    final targetFollower = db
        .collection('users')
        .doc(targetUserId)
        .collection('followers')
        .doc(uid);
    final batch = db.batch();
    if (following) {
      final now = Timestamp.now();
      batch.set(actorFollowing, {
        'uid': targetUserId,
        'displayName': target['displayName'] ?? 'YO Voice user',
        'username': target['username'] ?? '',
        'photoUrl': target['photoUrl'],
        'followedAt': now,
      });
      batch.set(targetFollower, {
        'uid': uid,
        'displayName': actorData['displayName'] ?? 'YO Voice user',
        'username': actorData['username'] ?? '',
        'photoUrl': actorData['photoUrl'],
        'followedAt': now,
      });
    } else {
      batch.delete(actorFollowing);
      batch.delete(targetFollower);
    }
    await batch.commit();
    return {'targetUserId': targetUserId, 'following': following};
  }

  DesktopHome buildHome({
    void Function(VoiceRoom)? onOpenRoom,
    VoidCallback? onSeeAll,
    VoidCallback? onFindCreators,
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
      onFindCreators: onFindCreators,
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
      followService: FollowService(
        firestore: db,
        auth: firebaseAuth,
        mutationInvoker: invokeFollowMutation,
      ),
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
      firebaseAuth: firebaseAuth,
    );
  }

  void useDesktop(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  setUp(ProfileService.resetCurrentProfileCache);
  tearDown(ProfileService.resetCurrentProfileCache);

  testWidgets('answers its four questions in order, once each', (tester) async {
    useDesktop(tester, const Size(1440, 2600));
    await seedRoom(id: 'r1', name: 'Evening Talks', description: 'Real talk');
    await tester.pumpWidget(host(buildHome()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    for (final heading in [
      'Rooms for you',
      'Your active rooms',
      'Your recent chats',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }

    double y(String label) => tester.getTopLeft(find.text(label)).dy;
    expect(y('Rooms for you'), lessThan(y('Your active rooms')));
    expect(y('Your active rooms'), lessThan(y('Your recent chats')));

    // The removed compositions must not come back.
    for (final gone in [
      'Live around you',
      'Your circle',
      'For you',
      'Recommended now',
      'Global Chat',
      'Global conversations',
    ]) {
      expect(find.text(gone), findsNothing, reason: '\$gone returned');
    }
  });

  testWidgets('the room board is ONE deduplicated column — a room the '
      'sources both return appears exactly once', (tester) async {
    useDesktop(tester, const Size(1440, 2600));
    await seedRoom(
      id: 'r1',
      name: 'Evening Talks',
      description: 'Real talk',
      age: const Duration(minutes: 1),
    );
    await seedRoom(
      id: 'r2',
      name: 'Night Shift',
      description: 'Late voices',
      age: const Duration(minutes: 9),
    );

    await tester.pumpWidget(host(buildHome()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.byType(HomeRoomBanner), findsNWidgets(2));
    expect(find.text('Evening Talks'), findsOneWidget);
    expect(find.text('Night Shift'), findsOneWidget);

    // Vertically stacked, not a grid: each banner starts below the last.
    final first = tester.getTopLeft(find.text('Evening Talks'));
    final second = tester.getTopLeft(find.text('Night Shift'));
    expect(second.dy, greaterThan(first.dy));
    expect(second.dx, closeTo(first.dx, 1));

    // One primary action per room.
    expect(find.text('Join room'), findsNWidgets(2));
  });

  testWidgets('Join room opens the real room through the shell callback', (
    tester,
  ) async {
    useDesktop(tester, const Size(1440, 2600));
    await seedRoom(id: 'r1', name: 'Evening Talks', description: 'Real talk');
    VoiceRoom? opened;
    await tester.pumpWidget(host(buildHome(onOpenRoom: (r) => opened = r)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    await tester.tap(find.text('Join room').first);
    await tester.pump();
    expect(opened?.name, 'Evening Talks');
  });

  testWidgets('a banner shows the real listener count, and its face pile '
      'opens the real roster on demand', (tester) async {
    useDesktop(tester, const Size(1440, 2600));
    await seedRoom(
      id: 'r1',
      name: 'Evening Talks',
      description: 'Real talk',
      participants: 7,
      hostName: 'Hosty',
    );
    await tester.pumpWidget(host(buildHome()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // The count on the banner is the room's own participantCount.
    expect(find.text('7'), findsOneWidget);

    final facePile = find.byTooltip('See who is in the room');
    expect(facePile, findsOneWidget);

    await tester.tap(facePile);
    // The dialog route has to finish its transition AND the roster
    // stream has to deliver its first snapshot.
    await tester.pumpAndSettle();
    // The roster came from the room's own participant documents.
    expect(find.text('Speaker r1'), findsOneWidget);
  });

  testWidgets('the banner counts big rooms in K, and a room nobody is in '
      'shows no face pile rather than placeholder faces', (tester) async {
    useDesktop(tester, const Size(1440, 2600));
    await seedRoom(
      id: 'busy',
      name: 'Late Night Creators',
      description: 'Deep conversations',
      participants: 2400,
    );
    await tester.pumpWidget(host(buildHome()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.text('2.4K'), findsOneWidget);
    // seedRoom writes one participant document, so the pile is present.
    expect(find.byTooltip('See who is in the room'), findsOneWidget);
  });

  testWidgets('no live rooms: an honest note, never invented rooms', (
    tester,
  ) async {
    useDesktop(tester, const Size(1440, 2600));
    await tester.pumpWidget(host(buildHome()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.textContaining('No rooms to show yet'), findsOneWidget);
    expect(find.text('Join room'), findsNothing);
  });

  testWidgets('Your active rooms lists only rooms this account hosts, and '
      'only the owner sees the settings affordance', (tester) async {
    useDesktop(tester, const Size(1440, 2600));
    await seedRoom(
      id: 'mine',
      name: 'My Room',
      description: 'I host this',
      hostId: uid,
    );
    await seedRoom(
      id: 'theirs',
      name: 'Someone Elses',
      description: 'Not mine',
      hostId: 'other-uid',
    );

    await tester.pumpWidget(host(buildHome()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // The owned room appears twice — board banner and active-rooms tile —
    // and BOTH carry the owner-only manage menu (settings + delete);
    // non-owned rooms never do.
    expect(find.byTooltip('Manage your room'), findsNWidgets(2));
    expect(find.text('Enter'), findsOneWidget);
  });

  test('one listener-count format, so a banner and the owned card under '
      'it can never disagree about the same room', () {
    expect(compactCount(0), '0');
    expect(compactCount(782), '782');
    expect(compactCount(999), '999');
    expect(compactCount(1000), '1K');
    expect(compactCount(1800), '1.8K');
    expect(compactCount(2400), '2.4K');
    // Below 10K keeps one decimal; at and above it drops to whole
    // thousands, so the chip never grows past four characters.
    expect(compactCount(9950), '9.9K');
    expect(compactCount(12400), '12K');
    expect(compactCount(999999), '1000K');
  });

  testWidgets('Your active rooms ends in a Create room tile that starts the '
      'existing room flow', (tester) async {
    useDesktop(tester, const Size(1440, 2600));
    await seedRoom(
      id: 'mine',
      name: 'My Room',
      description: 'I host this',
      hostId: uid,
    );

    var started = 0;
    await tester.pumpWidget(host(buildHome(onStartRoom: () => started++)));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // The tile sits AFTER the room this account owns. The owner-only
    // settings button is the unambiguous marker for that card — the
    // room's name also appears on its banner in the board above.
    expect(find.text('Create room'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Create room')).dx,
      greaterThan(
        tester.getTopLeft(find.byTooltip('Manage your room').last).dx,
      ),
    );

    await tester.tap(find.text('Create room'));
    await tester.pump();
    expect(started, 1);
  });

  testWidgets('an account hosting nothing gets one compact empty state with '
      'the existing Create Room action', (tester) async {
    useDesktop(tester, const Size(1440, 2600));
    await seedRoom(id: 'r1', name: 'Evening Talks', description: 'Real talk');
    await tester.pumpWidget(host(buildHome()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.text('You have no rooms yet.'), findsOneWidget);
    expect(find.text('Create Room'), findsOneWidget);
    expect(find.byTooltip('Manage your room'), findsNothing);
  });

  testWidgets('recent chats shows at most the three newest conversations', (
    tester,
  ) async {
    useDesktop(tester, const Size(1440, 2600));
    for (var index = 0; index < 4; index++) {
      await seedConversation(
        id: 'c$index',
        otherId: 'friend-$index',
        otherName: 'Friend $index',
        lastMessage: 'Message $index',
        age: Duration(minutes: 4 - index),
      );
    }

    await tester.pumpWidget(host(buildHome()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.text('Friend 3'), findsOneWidget);
    expect(find.text('Friend 2'), findsOneWidget);
    expect(find.text('Friend 1'), findsOneWidget);
    expect(find.text('Friend 0'), findsNothing);
  });

  group('Moments from your circle', () {
    testWidgets('keeps typical full names readable at 1100 and 1440', (
      tester,
    ) async {
      await seedFriend('friend-long', 'Aleksandra Kwiatkowska');
      await seedFollowing('friend-long', 'Aleksandra Kwiatkowska');
      await seedMoment(
        id: 'moment-long',
        authorId: 'friend-long',
        authorName: 'Aleksandra Kwiatkowska',
        caption: 'A full-name layout regression',
      );
      await seedFriend('follow-long', 'Katarzyna Wierzbicka');

      useDesktop(tester, const Size(1100, 800));
      await tester.pumpWidget(host(buildHome()));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      void expectFullName(String name) {
        final finder = find.descendant(
          of: find.byType(DesktopMomentsStrip),
          matching: find.text(name),
        );
        expect(finder, findsOneWidget);
        final label = tester.widget<Text>(finder);
        expect(label.maxLines, 2);
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '$name should fit without truncation',
        );
      }

      expectFullName('Aleksandra Kwiatkowska');
      expectFullName('Katarzyna Wierzbicka');
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(1440, 900);
      await tester.pump();

      expectFullName('Aleksandra Kwiatkowska');
      expectFullName('Katarzyna Wierzbicka');
      expect(tester.takeException(), isNull);
    });

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
        // Older than the 24-hour "New" window but explicitly still live:
        // the claim under test is that a non-fresh Moment shows its REAL
        // duration, and the strip trusts the document's expiresAt rather
        // than re-deriving it.
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      // A stranger the user neither follows nor is friends with.
      await seedMoment(
        id: 'm3',
        authorId: 'stranger',
        authorName: 'Nobody',
        caption: 'Not in the circle',
      );
      // In the circle but DEAD: past its 24-hour life. The expiry filter
      // must keep it off Home even before the sweeper marks it.
      await seedFollowing('creator-2', 'Bartek');
      await seedMoment(
        id: 'm4',
        authorId: 'creator-2',
        authorName: 'Bartek',
        caption: 'Expired yesterday',
        age: const Duration(days: 2),
      );
      // In the circle with no expiresAt at all — PERMANENT under the
      // amended availability contract ("keep until deleted"), so it MUST
      // render. This ADAPTS the ADR-101-era pin that read a missing
      // expiresAt as legacy-expired; that direction was deliberately
      // reversed when operator-chosen availability shipped.
      await seedFollowing('creator-3', 'Celina');
      await seedMoment(
        id: 'm5',
        authorId: 'creator-3',
        authorName: 'Celina',
        caption: 'No expiry field',
        withoutExpiry: true,
      );

      await tester.pumpWidget(host(buildHome()));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(find.text('Your Moment'), findsOneWidget);
      expect(find.text('Ola'), findsWidgets);
      expect(find.text('Marek'), findsOneWidget);
      // Nobody outside friends/following/self may appear.
      expect(find.text('Nobody'), findsNothing);
      // A Moment past its expiresAt stays dead and off Home. A Moment
      // with NO expiresAt is permanent and shows — the amended
      // availability contract, not a regression.
      expect(find.text('Bartek'), findsNothing);
      expect(find.text('Celina'), findsOneWidget);
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
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

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

    testWidgets('the rail marks online friends, and offers Follow only for '
        'people this account has not followed yet', (tester) async {
      useDesktop(tester, const Size(1440, 900));
      // Ola is a friend and online; Marek is already followed.
      await seedFriend('friend-1', 'Ola');
      await seedFollowing('creator-1', 'Marek');
      // A friend who is also already followed must NOT be offered again.
      await seedFriend('friend-2', 'Zosia');
      await seedFollowing('friend-2', 'Zosia');

      await tester.pumpWidget(host(buildHome()));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      // Ola is followable; Zosia and Marek are not.
      expect(find.text('Follow'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('Ola'), matching: find.byType(Column)),
        findsWidgets,
      );
      expect(find.text('Zosia'), findsNothing);
    });

    testWidgets('following someone from the rail goes through the real '
        'FollowService and writes both sides of the edge', (tester) async {
      useDesktop(tester, const Size(1440, 900));
      await seedFriend('friend-1', 'Ola');

      await tester.pumpWidget(host(buildHome()));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      await tester.tap(find.text('Follow'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The same two documents the profile screens write.
      final following = await db
          .collection('users')
          .doc(uid)
          .collection('following')
          .doc('friend-1')
          .get();
      final follower = await db
          .collection('users')
          .doc('friend-1')
          .collection('followers')
          .doc(uid)
          .get();
      expect(following.exists, isTrue, reason: 'following edge missing');
      expect(follower.exists, isTrue, reason: 'follower mirror missing');
    });

    testWidgets('empty circle: a compact state with one Discover action, '
        'never a blank band', (tester) async {
      useDesktop(tester, const Size(1440, 820));
      var discover = 0;
      var creators = 0;

      await tester.pumpWidget(
        host(
          buildHome(
            onSeeAll: () => discover++,
            onFindCreators: () => creators++,
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(find.text('People & Moments'), findsOneWidget);
      // Creation stays reachable even with nothing to show.
      expect(find.text('Your Moment'), findsOneWidget);
      expect(find.text('Find creators'), findsOneWidget);

      await tester.tap(find.text('Find creators'));
      await tester.pump();
      expect(creators, 1);
      expect(discover, 0);
    });
  });

  // Every supported desktop size, plus the narrow end of the range.
  for (final size in const [
    Size(1920, 1080),
    Size(1440, 900),
    Size(1366, 768),
    Size(1100, 800),
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
}
