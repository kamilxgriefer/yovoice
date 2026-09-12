import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/core/presence/user_availability.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';

import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home_sections.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_overview_sections.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_friend_tile.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_here_now_hero.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_room_board.dart';
import 'package:yovoice/shared/widgets/profile/availability_picker.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';

import 'semantics_probe.dart';
import 'voice_moment_test_doubles.dart';
import 'home_watermark_visual_capture.dart';

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
  setUpAll(loadHomeWatermarkFonts);

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
    bool isLive = true,
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
      'isLive': isLive,
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
    VoidCallback? onSeeAllMoments,
    StaffCapabilityService? capabilityService,
    PresenceService? presenceService,
    FollowService? followService,
    HomeFeedService? feedService,
    ValueListenable<bool>? isVisible,
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
      onSeeAllMoments: onSeeAllMoments,
      roomService: RoomService(firestore: db, auth: firebaseAuth),
      friendService: FriendService(firestore: db, auth: firebaseAuth),
      followService:
          followService ?? FollowService(firestore: db, auth: firebaseAuth),
      profileService: ProfileService(firestore: db, auth: firebaseAuth),
      feedService:
          feedService ??
          HomeFeedService(
            firestore: db,
            auth: firebaseAuth,
            voiceMomentReadService: VoiceMomentReadService(
              feedInvoker: fakeVoiceMomentFeedInvoker(firestore: db),
            ),
          ),
      messageService: MessageService(firestore: db, auth: firebaseAuth),
      capabilityService: capabilityService,
      presenceService: presenceService,
      currentUserId: uid,
      isVisible: isVisible,
    );
  }

  void usePhone(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  for (final (name, theme) in [
    ('dark', AppTheme.darkTheme),
    ('pearl', AppTheme.lightTheme),
  ]) {
    for (final size in [
      const Size(320, 720),
      const Size(390, 844),
      const Size(768, 1024),
    ]) {
      testWidgets('production Home watermark mobile $name ${size.width}', (
        tester,
      ) async {
        usePhone(tester, size);
        final capture = GlobalKey();
        var profileOpens = 0;
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(size.width == 320 ? 2 : 1),
                  disableAnimations: true,
                ),
                child: Scaffold(
                  body: buildHome(onProfile: () => profileOpens++),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => precacheImage(
            AssetImage(YoPageSection.home.asset),
            capture.currentContext!,
          ),
        );
        await tester.pumpAndSettle();
        final mark = find.descendant(
          of: find.byType(MobileHome),
          matching: find.byKey(const ValueKey('yo-atmosphere-home')),
        );
        expect(mark, findsOneWidget);
        final canvas = tester.widget<YoPageBackground>(
          find.descendant(
            of: find.byType(MobileHome),
            matching: find.byType(YoPageBackground),
          ),
        );
        expect(
          canvas.decoration,
          const BoxDecoration(),
          reason: 'shell owns underlying paint',
        );
        expect(tester.getSize(find.byType(YoPageBackground)), size);
        await captureHomeWatermarkFrame(
          tester,
          capture,
          'yo-watermark-mobile-home-$name-${size.width.toInt()}',
        );
        final before = tester.getRect(mark);
        await tester.drag(find.byType(ListView).first, const Offset(0, -240));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(mark),
          before,
          reason: 'logo must not scroll with Home content',
        );
        expect(
          profileOpens,
          0,
          reason: 'decoration never triggers a profile action',
        );
        expect(tester.takeException(), isNull);
      });
    }
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
    // Hosted by this account but not live: it belongs to "Your active
    // rooms" only, so the section renders without a second board banner.
    await seedRoom(
      id: 'mine',
      name: 'My hosted room',
      description: 'Owned, not live',
      participants: 2,
      hostId: uid,
      isLive: false,
    );

    await tester.pumpWidget(host(buildHome()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // Compact header: one greeting carrying the account's own first name.
    // The wave is decoration — drawn, never announced (see the semantics
    // test below, which still refuses to let a control claim the greeting).
    expect(find.textContaining('Hi, Kamil'), findsOneWidget);
    expect(find.text('👋'), findsOneWidget);
    // The friends rail leads, with the signed-in account as its first tile.
    expect(find.text('Your people'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-people-me')), findsOneWidget);
    // The four questions Home answers, in order, and nothing else.
    expect(find.text('YO Moments from your circle'), findsNothing);
    // Only the people tile says "You" now: the Moments rail's own tile
    // left Home, and the trailing Record tile took over creation.
    expect(find.text('You'), findsOneWidget);
    // With nothing followed to hear, a heading promising followed Moments
    // is a promise Home cannot keep: the section header is gated on real
    // content and the Record affordance becomes a labelled action instead.
    expect(find.text('From people you follow'), findsNothing);
    expect(find.byKey(const ValueKey('home-record-moment')), findsOneWidget);
    expect(find.text('Record a Voice Moment'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-your-moment')), findsNothing);
    expect(find.text('Here and now'), findsOneWidget);
    expect(find.text('Your active rooms'), findsOneWidget);
    expect(find.text('Your recent chats'), findsOneWidget);

    double y(String label) => tester.getTopLeft(find.text(label)).dy;
    expect(y('You'), lessThan(y('Here and now')));
    expect(y('Here and now'), lessThan(y('Got a minute?')));
    expect(y('Got a minute?'), lessThan(y('Your recent chats')));
    expect(y('Your recent chats'), lessThan(y('Your active rooms')));
    expect(find.byKey(const ValueKey('home-featured-room')), findsOneWidget);

    // The room appears ONCE, and its name is the hero's eyebrow — the
    // headline never inflects a user-typed name.
    expect(find.textContaining('Evening Talks'), findsOneWidget);
    // The summary is the REAL roster, read from the room's participants.
    expect(find.text('Speaker is talking'), findsOneWidget);
    // The one primary action, and it opens the pre-join screen.
    expect(find.byKey(const ValueKey('home-hero-join')), findsOneWidget);
    expect(find.text('Join the conversation'), findsOneWidget);

    // Retired compositions are gone.
    for (final removed in [
      'LIVE NOW',
      'FEATURED',
      'Your circle',
      'Recommended now',
      'Live around you',
      'Global Chat',
      'Global conversations',
      'Top creators you follow',
      'Voice Trending',
      // The followed-Moments rail and the room directory both left Home.
      'Live for you',
      'Rooms for you',
    ]) {
      expect(find.text(removed), findsNothing, reason: '$removed returned');
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
    var createRoom = 0;

    await tester.pumpWidget(
      host(
        buildHome(
          onOpenRoom: (room) => opened = room,
          onDiscover: () => discover++,
          onFindCreators: () => creators++,
          onFriends: () => friends++,
          onCreateMoment: () => moment++,
          onCreateRoom: () => createRoom++,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    // ONE primary action on the page: the hero's join pill.
    await tester.tap(find.byKey(const ValueKey('home-hero-join')));
    await tester.pump();
    expect(opened?.name, 'Evening Talks');

    // No filler card and no duplicate actions. Recording is the "Masz
    // chwilę?" row card — the followed rail and its own story tile left Home.
    expect(find.text('Find creators'), findsNothing);
    expect(find.text('Record a Moment'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-record-moment')));
    await tester.pump();
    expect(moment, 1);
    expect(creators, 0);
    expect(discover, 0);

    await tester.tap(find.byKey(const ValueKey('home-quick-friends')));
    await tester.tap(find.byKey(const ValueKey('home-quick-create-room')));
    await tester.pump();
    expect(friends, 1);
    expect(createRoom, 1);
    expect(moment, 1, reason: 'Create room must never record a Moment');
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

    expect(
      find.textContaining('A good conversation starts here.'),
      findsOneWidget,
    );
    // The recommended list hides rather than showing filler rows.
    expect(find.text('Recommended now'), findsNothing);
    // An account hosting nothing gets no permanently empty owned-rooms
    // card, and no second Create Room button duplicating the pill row.
    expect(find.text('Your active rooms'), findsNothing);
    expect(find.text('You have no rooms yet.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning to retained Home refreshes the one-shot v2 feed', (
    tester,
  ) async {
    usePhone(tester, const Size(390, 844));
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);
    var requests = 0;
    final firebaseAuth = auth();
    final feedService = HomeFeedService(
      firestore: db,
      auth: firebaseAuth,
      voiceMomentReadService: VoiceMomentReadService(
        feedInvoker: (request) async {
          requests += 1;
          return <Object?, Object?>{
            'schemaVersion': 2,
            'moments': const <Object?>[],
            'scannedCount': 0,
            'hasMore': false,
            'nextCursor': null,
          };
        },
      ),
    );

    await tester.pumpWidget(
      host(buildHome(feedService: feedService, isVisible: visible)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(requests, 1);

    visible.value = false;
    await tester.pump();
    expect(requests, 1);

    visible.value = true;
    await tester.pump(const Duration(milliseconds: 100));
    expect(requests, 2);
  });

  testWidgets('the friends rail marks a FRIEND with a new Voice Moment, and '
      'never a followed author or a document without media', (tester) async {
    usePhone(tester, const Size(390, 1400));
    await seedFriend('friend-voice', 'Friend voice');
    await seedMoment(
      id: 'friend-older',
      authorId: 'friend-voice',
      authorName: 'Friend voice',
      age: const Duration(minutes: 10),
    );
    await seedMoment(
      id: 'friend-newer',
      authorId: 'friend-voice',
      authorName: 'Friend voice',
    );
    await seedFriend('friend-silent', 'Friend silent');
    await seedMoment(
      id: 'friend-silent-document',
      authorId: 'friend-silent',
      authorName: 'Friend silent',
      withMedia: false,
    );
    await seedFollowing('followed', 'Followed voice');
    await seedMoment(
      id: 'followed-moment',
      authorId: 'followed',
      authorName: 'Followed voice',
    );

    List<VoiceMoment>? openedChain;
    await tester.pumpWidget(
      host(buildHome(onOpenChain: (moments) => openedChain = moments)),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // The followed rail and its own story tile left Home; creation survives
    // as the "Got a minute?" card.
    expect(find.byType(MobileMomentsStrip), findsNothing);
    expect(find.byKey(const ValueKey('home-your-moment')), findsNothing);
    expect(find.byKey(const ValueKey('home-record-moment')), findsOneWidget);

    // A followed author is NOT a friend: the following feed page is where
    // the Moment came from, but only friendship may put a mark on a face.
    expect(find.text('Followed voice'), findsNothing);
    // A friend whose only document carries no media gets presence, not a
    // Voice label — "no ring" is never a claim that nothing exists.
    final silent = tester.widget<HomeFriendTile>(
      find.byKey(const ValueKey('home-person-friend-silent')),
    );
    expect(silent.voice, isNull);
    // The friend with playable media gets the mark and the real duration.
    expect(find.text('Voice 0:08'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-person-friend-voice')));
    await tester.pump();
    expect(openedChain?.map((moment) => moment.id), [
      'friend-older',
      'friend-newer',
    ]);
    expect(openedChain, isNotNull);
    expect(openedChain!.every((moment) => moment.audioUrl == null), isTrue);
    expect(
      openedChain!.every((moment) => moment.mediaGeneration == null),
      isTrue,
    );
    expect(openedChain!.every((moment) => moment.hasAuthorizedMedia), isTrue);
  });

  testWidgets('initial following stream failure fails closed to the Record '
      'tile', (tester) async {
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
    expect(find.byKey(const ValueKey('home-record-moment')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-your-moment')), findsNothing);
  });

  testWidgets('an own active Moment adds no third own avatar to Home, and '
      'the Record tile is the creation target', (tester) async {
    usePhone(tester, const Size(390, 1000));
    await seedMoment(id: 'mine-active', authorId: uid, authorName: 'Kamil');
    var records = 0;
    List<VoiceMoment>? played;
    await tester.pumpWidget(
      host(
        buildHome(
          onCreateMoment: () => records++,
          onOpenChain: (chain) => played = chain,
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    // Own-chain playback lives on the Your Moments tab's story strip now —
    // Home carries the header avatar and the "You" tile, and a third own
    // avatar 300 px lower was the clutter this change removed.
    expect(find.byKey(const ValueKey('home-your-moment')), findsNothing);
    expect(played, isNull);
    final record = find.byKey(const ValueKey('home-record-moment'));
    expect(tester.getSize(record).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(record).height, greaterThanOrEqualTo(44));
    await tester.tap(record);
    await tester.pump();
    expect(records, 1);
  });

  testWidgets('the friends rail fits 320px at 200 percent text', (
    tester,
  ) async {
    usePhone(tester, const Size(320, 640));
    await seedFriend('friend-long', 'Aleksandra Bardzo Długie Nazwisko');
    await seedMoment(
      id: 'friend-long-moment',
      authorId: 'friend-long',
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

    final own = find.byKey(const ValueKey('home-people-me'));
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
    // The friend is in the rail at the top of Home, with the real duration
    // of their newest unheard Voice Moment.
    expect(
      find.byKey(const ValueKey('home-person-friend-long')),
      findsOneWidget,
    );
    expect(find.text('Voice 0:08'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Aleksandra Bardzo Długie Nazwisko'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  group('availability on Home', () {
    testWidgets('the own tile opens the picker and writes the choice', (
      tester,
    ) async {
      usePhone(tester, const Size(390, 1200));
      final presence = PresenceService(firestore: db, auth: auth());
      await tester.pumpWidget(host(buildHome(presenceService: presence)));
      await tester.pump(const Duration(milliseconds: 200));

      final me = find.byKey(const ValueKey('home-people-me'));
      expect(me, findsOneWidget);
      // The ring starts at the account's stored state: no availability
      // field yet parses as "available", not as a guess.
      HomeFriendTile tile() => tester.widget<HomeFriendTile>(me);
      expect(tile().status, PeopleStatus.online);
      expect(tile().statusLabel, 'Available');

      await tester.tap(me);
      await tester.pumpAndSettle();
      expect(find.text('Your availability'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('availability-option-busy')));
      await tester.pumpAndSettle();

      expect(
        (await db.collection('users').doc(uid).get()).data()!['availability'],
        'busy',
      );
      // The ring and the label follow the profile stream, not local state.
      await tester.pump(const Duration(milliseconds: 200));
      expect(tile().status, PeopleStatus.busy);
      expect(tile().statusLabel, 'Do not disturb');
      expect(find.text('Do not disturb'), findsWidgets);
    });

    testWidgets('the header carries no chip: the picker lives on the own '
        'tile, with the same 44 px target and the same write', (tester) async {
      usePhone(tester, const Size(390, 1200));
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'displayName': 'Kamil',
        'email': 'me@yovoice.app',
        'availability': UserAvailability.away.wire,
      });
      final presence = PresenceService(firestore: db, auth: auth());
      await tester.pumpWidget(host(buildHome(presenceService: presence)));
      await tester.pump(const Duration(milliseconds: 200));

      // The accepted reference draws bell + avatar only; the chip's action
      // is NOT lost — it moved to the first tile of the friends rail, which
      // is reachable without scrolling at every width.
      expect(find.byType(AvailabilityChip), findsNothing);
      final me = find.byKey(const ValueKey('home-people-me'));
      expect(me, findsOneWidget);
      expect(tester.getSize(me).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(me).height, greaterThanOrEqualTo(44));
      // Under the greeting, at the top of the page.
      expect(
        tester.getTopLeft(me).dy,
        greaterThan(tester.getTopLeft(find.textContaining('Hi, Kamil')).dy),
      );
      // It reads the chosen state as text.
      expect(
        find.descendant(of: me, matching: find.text('Be right back')),
        findsOneWidget,
      );

      await tester.tap(me);
      await tester.pumpAndSettle();
      expect(find.text('Your availability'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('availability-option-invisible')),
      );
      await tester.pumpAndSettle();
      expect(
        (await db.collection('users').doc(uid).get()).data()!['availability'],
        'invisible',
      );
    });

    testWidgets('the availability action is its own semantics node: the '
        'greeting is never swallowed into a button', (tester) async {
      usePhone(tester, const Size(390, 1200));
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'displayName': 'Kamil',
        'email': 'me@yovoice.app',
        'availability': UserAvailability.busy.wire,
      });
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(buildHome()));
      await tester.pump(const Duration(milliseconds: 200));

      const phrase = 'You. Availability: Do not disturb. Change';
      final buttons = compiledButtonLabels(tester);
      expect(
        buttons.where((label) => label == phrase).length,
        1,
        reason: 'the own tile announces exactly the composed phrase, alone',
      );
      // The regression this pins: the greeting Column's Text siblings used
      // to merge into a neighbouring control's node, turning the whole
      // greeting into one 358x112 button.
      for (final label in buttons) {
        expect(
          label,
          isNot(contains('Hi, Kamil')),
          reason: 'no control may claim the greeting as its name: "$label"',
        );
      }
      expect(
        announcedLabelOf(tester, find.byKey(const ValueKey('home-people-me'))),
        phrase,
      );
      // And the greeting is still announced — as static content, without
      // the decorative wave.
      expect(find.bySemanticsLabel(RegExp('Hi, Kamil')), findsOneWidget);
      semantics.dispose();
    });
  });

  testWidgets('Your active rooms survives 200% text without clipping', (
    tester,
  ) async {
    // WCAG 1.4.4: the owned-room card must reflow, not be cut off. The row
    // used to pin itself to artwork + a flat 96 px.
    await seedRoom(
      id: 'mine',
      name: 'Evening Talks',
      description: 'Real talk',
      hostId: uid,
    );
    for (final width in [320.0, 390.0, 430.0, 768.0]) {
      usePhone(tester, Size(width, 2600));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 2600),
              textScaler: const TextScaler.linear(2),
            ),
            child: Scaffold(body: buildHome()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      // At 200 % the hero above grows (the headline wraps rather than being
      // cut), so this section can start below the lazy list's build window.
      // Reaching it by scrolling is the assertion: it exists and reflows.
      final section = find.text('Your active rooms');
      if (section.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          section,
          400,
          scrollable: find.byType(Scrollable).first,
        );
      }
      expect(
        section,
        findsOneWidget,
        reason: 'the section must actually render at $width',
      );
      expect(tester.takeException(), isNull, reason: 'at $width @200% text');
    }
  });

  testWidgets('the room directory is not on Home: six live rooms produce one '
      'hero and no second board', (tester) async {
    usePhone(tester, const Size(390, 4000));
    for (var index = 0; index < 6; index++) {
      await seedRoom(
        id: 'r$index',
        name: 'Room $index',
        description: 'Room number $index',
        participants: 3 + index,
      );
    }

    await tester.pumpWidget(host(buildHome()));
    await tester.pump(const Duration(milliseconds: 250));

    // Discovery belongs to the Odkrywaj destination; Home never becomes a
    // second directory with a listener per banner. The other live rooms are
    // still read — they are the hero's candidate list.
    expect(find.text('Rooms for you'), findsNothing);
    expect(find.byType(HomeRoomBanner), findsNothing);
    expect(find.byKey(const ValueKey('home-featured-room')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-hero-join')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a host keeps "Your active rooms" when several live rooms '
      'lengthen the sections above it', (tester) async {
    // The owned-rooms block sits after a variable-length section. Unkeyed,
    // its list child shifted index the moment the board grew, which
    // rebuilt it from scratch, re-subscribed to an already-emitted
    // broadcast stream, and left the host's own rooms silently missing.
    usePhone(tester, const Size(390, 3000));
    await seedRoom(id: 'r1', name: 'Evening Talks', description: 'Real talk');
    await seedRoom(id: 'r2', name: 'Night Shift', description: 'Late talk');
    await seedRoom(
      id: 'mine',
      name: 'Morning Coffee',
      description: 'Owned and live',
      hostId: uid,
    );

    await tester.pumpWidget(host(buildHome()));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Your active rooms'), findsOneWidget);
    expect(find.text('Could not load rooms'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a medium width is not a stretched phone: wider gutters and '
      'the wide hero composition', (tester) async {
    // The mobile shell also serves tablets and a resized desktop window.
    // At 768 the body is not otherwise framed, so it takes UI.md's medium
    // gutter (24) and the featured room gets its non-compact banner —
    // deliberate, and the ONLY two things that change with width here.
    await seedRoom(id: 'r1', name: 'Evening Talks', description: 'Real talk');

    for (final (width, gutter, compact) in [
      (390.0, 16.0, true),
      (768.0, 24.0, false),
    ]) {
      usePhone(tester, Size(width, 1400));
      await tester.pumpWidget(host(buildHome()));
      await tester.pump(const Duration(milliseconds: 250));

      // The gutter lives on the page children now, not on the ListView:
      // the two rails are full-bleed so their tiles can scroll under the
      // frame edge. Measure what the reader sees — the left ink of a
      // gutter-wrapped section — rather than a padding value.
      final list = tester.widget<ListView>(find.byType(ListView).first);
      expect((list.padding! as EdgeInsets).left, 0);
      expect((list.padding! as EdgeInsets).right, 0);
      expect(
        tester.getTopLeft(find.text('Here and now')).dx,
        gutter,
        reason: 'left gutter at $width',
      );
      expect(
        tester.getTopRight(find.byType(HomeQuickActions)).dx,
        width - gutter,
        reason: 'right gutter at $width',
      );

      final featured = tester.widget<HomeHereNowHero>(
        find.byKey(const ValueKey('home-featured-room')),
      );
      expect(featured.compact, compact, reason: 'featured hero at $width');
      expect(tester.takeException(), isNull);
    }
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
