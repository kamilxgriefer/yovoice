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
import 'package:yovoice/features/home/presentation/widgets/shared/home_overview_sections.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_friend_tile.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_server_overview.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
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
  int calls = 0;

  @override
  Stream<List<FollowUser>> watchFollowing(String userId) {
    calls++;
    return stream;
  }
}

class _StaticServers extends ServerService {
  _StaticServers({
    required super.firestore,
    required super.auth,
    required this.servers,
  });

  final List<Server> servers;

  @override
  Stream<List<Server>> watchMyServers() => Stream.value(servers);
}

void main() {
  const uid = 'me-uid';
  setUpAll(loadHomeWatermarkFonts);

  late FakeFirebaseFirestore db;

  MockFirebaseAuth auth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: 'me@yovoice.app', displayName: 'Kamil'),
  );

  Server server({
    required String id,
    required String name,
    required String description,
    String? ownerId,
  }) => Server(
    id: id,
    name: name,
    description: description,
    ownerId: ownerId ?? uid,
    type: ServerType.community,
    privacy: ServerPrivacy.public,
    defaultLanguage: 'English',
    schemaVersion: 1,
    activationState: 'active',
  );

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
    ValueChanged<Server>? onOpenServer,
    VoidCallback? onOpenServers,
    List<Server> servers = const [],
    PresenceService? presenceService,
    FollowService? followService,
    HomeFeedService? feedService,
    ValueListenable<bool>? isVisible,
    int unreadNotificationCount = 0,
  }) {
    final firebaseAuth = auth();
    return MobileHome(
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
      onOpenServer: onOpenServer,
      onOpenServers: onOpenServers,
      serverRepository: _StaticServers(
        firestore: db,
        auth: firebaseAuth,
        servers: servers,
      ),
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

  testWidgets('renders the server-first briefing in its intentional order', (
    tester,
  ) async {
    usePhone(tester, const Size(390, 2600));
    final primaryServer = server(
      id: 's1',
      name: 'Evening Talks',
      description: 'Real conversations, real people',
    );

    await tester.pumpWidget(host(buildHome(servers: [primaryServer])));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.textContaining('Hi, Kamil'), findsOneWidget);
    expect(find.text('👋'), findsOneWidget);
    expect(find.text('Your people'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-people-me')), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('From people you follow'), findsNothing);
    expect(find.byKey(const ValueKey('home-record-moment')), findsOneWidget);
    expect(find.text('Record a Voice Moment'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-your-moment')), findsNothing);
    expect(find.text('Here and now'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-server-continue-s1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-servers-overview')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-server-row-s1')), findsOneWidget);
    expect(find.text('Your recent chats'), findsOneWidget);

    double y(Finder finder) => tester.getTopLeft(finder).dy;
    expect(
      y(find.byKey(const ValueKey('home-people-me'))),
      lessThan(y(find.text('Here and now'))),
    );
    expect(
      y(find.text('Here and now')),
      lessThan(y(find.byKey(const ValueKey('home-record-moment')))),
    );
    expect(
      y(find.byKey(const ValueKey('home-record-moment'))),
      lessThan(y(find.text('Your recent chats'))),
    );

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
      'Live for you',
      'Rooms for you',
      'Your active rooms',
      'Join the conversation',
    ]) {
      expect(find.text(removed), findsNothing, reason: '$removed returned');
    }
    expect(find.textContaining('Check plans'), findsNothing);
    expect(find.text('SPONSORED EXAMPLE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actions open the exact server and existing destinations', (
    tester,
  ) async {
    usePhone(tester, const Size(390, 2600));
    final primaryServer = server(
      id: 's1',
      name: 'Evening Talks',
      description: 'Real talk',
    );
    Server? opened;
    var discover = 0;
    var creators = 0;
    var friends = 0;
    var moment = 0;
    var openServers = 0;

    await tester.pumpWidget(
      host(
        buildHome(
          servers: [primaryServer],
          onOpenServer: (value) => opened = value,
          onOpenServers: () => openServers++,
          onDiscover: () => discover++,
          onFindCreators: () => creators++,
          onFriends: () => friends++,
          onCreateMoment: () => moment++,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    await tester.tap(find.byKey(const ValueKey('home-server-continue-s1')));
    await tester.pump();
    expect(opened?.id, 's1');
    expect(opened?.name, 'Evening Talks');

    expect(find.text('Find creators'), findsNothing);
    expect(find.text('Record a Moment'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-record-moment')));
    await tester.pump();
    expect(moment, 1);
    expect(creators, 0);
    expect(discover, 0);

    await tester.tap(find.byKey(const ValueKey('home-quick-friends')));
    await tester.tap(find.byKey(const ValueKey('home-quick-create-server')));
    await tester.pump();
    expect(friends, 1);
    expect(openServers, 1);
    expect(moment, 1, reason: 'Create server must never record a Moment');
  });

  testWidgets('server cards do not expose legacy room administration', (
    tester,
  ) async {
    usePhone(tester, const Size(390, 1400));
    final owned = server(
      id: 'mine',
      name: 'My mobile server',
      description: 'Owned here',
    );
    Server? opened;

    await tester.pumpWidget(
      host(
        buildHome(servers: [owned], onOpenServer: (value) => opened = value),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('home-server-continue-mine')), findsOne);
    expect(find.byTooltip('Manage your room'), findsNothing);
    expect(find.byIcon(Icons.shield_rounded), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-server-row-mine')));
    await tester.pump();
    expect(opened?.id, 'mine');
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

  testWidgets('no servers: compact honest empty state and one CTA', (
    tester,
  ) async {
    usePhone(tester, const Size(390, 844));
    await tester.pumpWidget(host(buildHome()));
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.text('A good conversation starts in your server.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-servers-empty')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-empty-create-server')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-servers-overview')), findsNothing);
    expect(find.text('Your active rooms'), findsNothing);
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

  testWidgets('Home never subscribes to the retired following stream', (
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
    expect(followService.calls, 0);
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

  testWidgets('the server card survives 200% text without clipping', (
    tester,
  ) async {
    final item = server(
      id: 'mine',
      name: 'Evening Talks',
      description: 'Real talk',
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
            child: Scaffold(body: buildHome(servers: [item])),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      final card = find.byKey(const ValueKey('home-server-continue-mine'));
      if (card.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          card,
          400,
          scrollable: find.byType(Scrollable).first,
        );
      }
      expect(
        card,
        findsOneWidget,
        reason: 'the server card must actually render at $width',
      );
      expect(tester.takeException(), isNull, reason: 'at $width @200% text');
    }
  });

  testWidgets('six servers produce one continuation card and three rows', (
    tester,
  ) async {
    usePhone(tester, const Size(390, 4000));
    final servers = [
      for (var index = 0; index < 6; index++)
        server(
          id: 's$index',
          name: 'Server $index',
          description: 'Server number $index',
        ),
    ];

    await tester.pumpWidget(host(buildHome(servers: servers)));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Rooms for you'), findsNothing);
    expect(find.byKey(const ValueKey('home-server-continue-s0')), findsOne);
    expect(find.byKey(const ValueKey('home-servers-overview')), findsOne);
    for (var index = 0; index < 3; index++) {
      expect(find.byKey(ValueKey('home-server-row-s$index')), findsOne);
    }
    for (var index = 3; index < 6; index++) {
      expect(find.byKey(ValueKey('home-server-row-s$index')), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('several servers keep the projection stable', (tester) async {
    usePhone(tester, const Size(390, 3000));
    final servers = [
      server(id: 's1', name: 'Evening Talks', description: 'Real talk'),
      server(id: 's2', name: 'Night Shift', description: 'Late talk'),
      server(id: 'mine', name: 'Morning Coffee', description: 'Owned'),
    ];

    await tester.pumpWidget(host(buildHome(servers: servers)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(const ValueKey('home-server-continue-s1')), findsOne);
    expect(find.byKey(const ValueKey('home-server-row-s1')), findsOne);
    expect(find.byKey(const ValueKey('home-server-row-s2')), findsOne);
    expect(find.byKey(const ValueKey('home-server-row-mine')), findsOne);
    expect(find.text('Could not load rooms'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a medium width is not a stretched phone: wider gutters and '
      'the expanded server composition', (tester) async {
    final item = server(
      id: 's1',
      name: 'Evening Talks',
      description: 'Real talk',
    );

    for (final (width, gutter, expanded) in [
      (390.0, 16.0, false),
      (768.0, 24.0, true),
    ]) {
      usePhone(tester, Size(width, 1400));
      await tester.pumpWidget(host(buildHome(servers: [item])));
      await tester.pump(const Duration(milliseconds: 250));

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

      final featured = tester.widget<HomeServerConversationCard>(
        find.ancestor(
          of: find.byKey(const ValueKey('home-server-continue-s1')),
          matching: find.byType(HomeServerConversationCard),
        ),
      );
      expect(featured.expanded, expanded, reason: 'server card at $width');
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
        final servers = [
          server(id: 's1', name: 'Evening Talks', description: 'Talk'),
          server(id: 's2', name: 'new test', description: 'Open talk'),
          server(id: 's3', name: 'super test', description: 'Chill'),
        ];

        await tester.pumpWidget(host(buildHome(servers: servers)));
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
