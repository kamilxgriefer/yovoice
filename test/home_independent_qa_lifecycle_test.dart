import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_roster_cache.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';

/// INDEPENDENT QA — listener ownership, the retained shell, and the account
/// boundary.
///
/// Three questions the brief makes load-bearing and that a screenshot can
/// never answer: does Home open MORE listeners than it declares, does leaving
/// and coming back (a tab switch, or returning from a room) re-open them, and
/// does a different account ever see the previous account's world.

/// Counts subscriptions AND cancellations, so "the old account's listeners
/// were closed" is observable rather than assumed.
class _LedgerRooms extends RoomService {
  _LedgerRooms({
    required super.firestore,
    required super.auth,
    required this.log,
    this.tag = '',
    this.live = const <VoiceRoom>[],
  });

  final List<String> log;
  final String tag;
  final List<VoiceRoom> live;

  int liveCalls = 0;
  int ownedCalls = 0;
  int loungeCalls = 0;
  final Set<String> loungeIds = <String>{};
  final List<String> rosterRoomIds = <String>[];
  int openRosters = 0;

  Stream<T> _tracked<T>(String label, T value) {
    late StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        log.add('$tag$label:listen');
        controller.add(value);
      },
      onCancel: () => log.add('$tag$label:cancel'),
    );
    return controller.stream;
  }

  @override
  Stream<List<VoiceRoom>> watchLivePublicRooms() {
    liveCalls++;
    return _tracked('live', live);
  }

  @override
  Stream<List<VoiceRoom>> watchOwnedRooms() {
    ownedCalls++;
    return _tracked('owned', const <VoiceRoom>[]);
  }

  @override
  Stream<VoiceRoom?> watchClubLounge(String clubId) {
    loungeCalls++;
    loungeIds.add(clubId);
    return _tracked<VoiceRoom?>('lounge($clubId)', null);
  }

  @override
  Stream<List<RoomParticipant>> watchParticipants(String roomId) {
    rosterRoomIds.add(roomId);
    openRosters++;
    late StreamController<List<RoomParticipant>> controller;
    controller = StreamController<List<RoomParticipant>>(
      onListen: () {
        log.add('${tag}roster($roomId):listen');
        controller.add(const <RoomParticipant>[]);
      },
      onCancel: () {
        openRosters--;
        log.add('${tag}roster($roomId):cancel');
      },
    );
    return controller.stream;
  }
}

class _LedgerFriends extends FriendService {
  _LedgerFriends({
    required super.firestore,
    required super.auth,
    required this.log,
  });
  final List<String> log;
  int calls = 0;

  @override
  Stream<List<FriendUser>> watchFriends() {
    calls++;
    late StreamController<List<FriendUser>> controller;
    controller = StreamController<List<FriendUser>>(
      onListen: () {
        log.add('friends:listen');
        controller.add(const <FriendUser>[]);
      },
      onCancel: () => log.add('friends:cancel'),
    );
    return controller.stream;
  }
}

class _LedgerClubs extends ClubService {
  _LedgerClubs({
    required super.firestore,
    required super.auth,
    required super.storage,
    required this.log,
    this.tag = '',
    this.clubs = const <Club>[],
  });
  final List<String> log;
  final String tag;
  final List<Club> clubs;
  int calls = 0;

  @override
  Stream<List<Club>> watchMyClubs() {
    calls++;
    late StreamController<List<Club>> controller;
    controller = StreamController<List<Club>>(
      onListen: () {
        log.add('${tag}clubs:listen');
        controller.add(clubs);
      },
      onCancel: () => log.add('${tag}clubs:cancel'),
    );
    return controller.stream;
  }
}

class _CountingFeed extends HomeFeedService {
  _CountingFeed({required super.firestore, required super.auth});
  int calls = 0;
  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) {
    calls++;
    return Stream<List<VoiceMoment>>.value(const <VoiceMoment>[]);
  }
}

class _CountingFollow extends FollowService {
  _CountingFollow({required super.firestore, required super.auth});
  int calls = 0;
  @override
  Stream<List<FollowUser>> watchFollowing(String userId) {
    calls++;
    return const Stream<List<FollowUser>>.empty();
  }
}

class _CountingMessages extends MessageService {
  _CountingMessages({required super.firestore, required super.auth});
  int calls = 0;
  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) {
    calls++;
    return const Stream<List<Conversation>>.empty();
  }
}

class _CountingViews extends MomentViewsService {
  _CountingViews({required super.firestore, required super.auth});
  int calls = 0;
  @override
  Stream<Set<String>> watchViewedMomentIds() {
    calls++;
    return const Stream<Set<String>>.empty();
  }
}

class _NoCapabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

Club _club(String id, String name) => Club(
  id: id,
  name: name,
  description: '',
  ownerId: 'owner',
  ownerName: 'Owner',
  avatarUrl: null,
  bannerUrl: null,
  privacy: ClubPrivacy.private,
  defaultLanguage: 'Polish',
  memberCount: 3,
  onlineCount: 0,
  defaultChatChannelId: '',
  defaultVoiceChannelId: '',
  announcementChannelId: '',
  createdAt: null,
  updatedAt: null,
);

VoiceRoom _liveRoom(String id, String name) => VoiceRoom(
  id: id,
  hostId: 'host-$id',
  hostName: 'Host',
  hostPhotoUrl: null,
  name: name,
  description: '',
  category: 'community',
  visibility: 'public',
  language: 'Polish',
  maxParticipants: null,
  participantCount: 2,
  memberCount: 0,
  isLive: true,
  roomType: RoomType.community,
  status: RoomStatus.active,
  imageUrl: null,
  approvalRequired: false,
  slowModeSeconds: 0,
  autoMuteNewUsers: true,
  membersCanStartVoice: false,
  createdAt: null,
  updatedAt: null,
  deletionInProgress: false,
  experience: 'community',
);

void main() {
  late FakeFirebaseFirestore db;

  MockFirebaseAuth authFor(String uid, String name) => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: '$uid@yovoice.app', displayName: name),
  );

  setUp(() async {
    ProfileService.resetCurrentProfileCache();
    db = FakeFirebaseFirestore();
  });
  tearDown(ProfileService.resetCurrentProfileCache);

  Widget app(Widget child) => MaterialApp(
    theme: AppTheme.darkTheme,
    locale: const Locale('pl'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );

  void useWindow(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('leaving Home and coming back re-opens nothing but the one-shot '
      'Moments page — and the rosters stay inside the budget', (tester) async {
    useWindow(tester, const Size(390, 2600));
    const uid = 'life-me';
    final auth = authFor(uid, 'Kamil');
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'Kamil',
      'email': 'me@yovoice.app',
    });
    final log = <String>[];
    final rooms = _LedgerRooms(
      firestore: db,
      auth: auth,
      log: log,
      live: [
        for (var i = 0; i < 9; i++) _liveRoom('r$i', 'Pokój $i'),
      ],
    );
    final clubs = _LedgerClubs(
      firestore: db,
      auth: auth,
      storage: MockFirebaseStorage(),
      log: log,
      clubs: [for (var i = 0; i < 6; i++) _club('c$i', 'Miejsce $i')],
    );
    final friends = _LedgerFriends(firestore: db, auth: auth, log: log);
    final feed = _CountingFeed(firestore: db, auth: auth);
    final follow = _CountingFollow(firestore: db, auth: auth);
    final messages = _CountingMessages(firestore: db, auth: auth);
    final views = _CountingViews(firestore: db, auth: auth);
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);

    Widget home() => app(
      MobileHome(
        key: const ValueKey('life-home'),
        currentUserId: uid,
        isVisible: visible,
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
        clubService: clubs,
        friendService: friends,
        followService: follow,
        profileService: ProfileService(firestore: db, auth: auth),
        feedService: feed,
        messageService: messages,
        momentViewsService: views,
        capabilityService: _NoCapabilities(),
      ),
    );

    await tester.pumpWidget(home());
    await settle(tester);

    expect(rooms.liveCalls, 1);
    expect(rooms.ownedCalls, 1);
    expect(friends.calls, 1);
    expect(clubs.calls, 1);
    expect(follow.calls, 1);
    expect(messages.calls, 1);
    expect(views.calls, 1);
    expect(
      rooms.loungeIds.length,
      lessThanOrEqualTo(4),
      reason: 'six memberships, at most four lounge listeners',
    );
    expect(
      rooms.openRosters,
      lessThanOrEqualTo(4),
      reason: 'nine live rooms, at most four roster listeners',
    );
    final rostersAfterFirstBuild = rooms.openRosters;

    // A tab switch: Home is retained, so the shell only flips visibility.
    final feedReads = feed.calls;
    visible.value = false;
    await settle(tester);
    visible.value = true;
    await settle(tester);

    expect(feed.calls, feedReads + 1, reason: 'the one-shot page refreshes');
    expect(rooms.liveCalls, 1, reason: 'no re-subscribe on return');
    expect(rooms.ownedCalls, 1);
    expect(friends.calls, 1);
    expect(clubs.calls, 1);
    expect(views.calls, 1);
    expect(rooms.openRosters, rostersAfterFirstBuild);
    expect(
      log.where((entry) => entry.endsWith(':cancel')),
      isEmpty,
      reason: 'returning to Home must not tear a single listener down',
    );

    // Twenty rebuilds (what a scroll, a badge tick or a theme change do)
    // must not grow the pool either.
    for (var i = 0; i < 20; i++) {
      await tester.pumpWidget(home());
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(rooms.liveCalls, 1);
    expect(rooms.openRosters, rostersAfterFirstBuild);
    expect(tester.takeException(), isNull);

    // Unmounting Home (signing out, or the shell being replaced) closes
    // every stream it opened.
    await tester.pumpWidget(app(const SizedBox.shrink()));
    await settle(tester);
    expect(rooms.openRosters, 0);
    expect(log, contains('live:cancel'));
    expect(log, contains('clubs:cancel'));
    expect(log, contains('friends:cancel'));
  });

  testWidgets('a room pushed over Home and popped again re-opens nothing', (
    tester,
  ) async {
    // Entering a room does NOT change the selected tab: RoomEntryScreen is
    // pushed over the whole shell, so Home stays mounted underneath and its
    // visibility notifier never flips. Coming back must therefore find the
    // same listeners, not new ones — and must not have torn any down while
    // the room was on top.
    useWindow(tester, const Size(390, 2600));
    const uid = 'return-me';
    final auth = authFor(uid, 'Kamil');
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'Kamil',
      'email': 'me@yovoice.app',
    });
    final log = <String>[];
    final rooms = _LedgerRooms(
      firestore: db,
      auth: auth,
      log: log,
      live: [_liveRoom('r1', 'Wieczorne rozmowy')],
    );
    final clubs = _LedgerClubs(
      firestore: db,
      auth: auth,
      storage: MockFirebaseStorage(),
      log: log,
      clubs: [_club('c1', 'Klub')],
    );
    final friends = _LedgerFriends(firestore: db, auth: auth, log: log);
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);

    await tester.pumpWidget(
      app(
        MobileHome(
          currentUserId: uid,
          isVisible: visible,
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
          clubService: clubs,
          friendService: friends,
          followService: _CountingFollow(firestore: db, auth: auth),
          profileService: ProfileService(firestore: db, auth: auth),
          feedService: _CountingFeed(firestore: db, auth: auth),
          messageService: _CountingMessages(firestore: db, auth: auth),
          momentViewsService: _CountingViews(firestore: db, auth: auth),
          capabilityService: _NoCapabilities(),
        ),
      ),
    );
    await settle(tester);
    final rosters = rooms.openRosters;

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('pre-join')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('pre-join'), findsOneWidget);

    navigator.pop();
    await tester.pumpAndSettle();

    expect(rooms.liveCalls, 1);
    expect(rooms.ownedCalls, 1);
    expect(friends.calls, 1);
    expect(clubs.calls, 1);
    expect(rooms.openRosters, rosters);
    expect(
      log.where((entry) => entry.endsWith(':cancel')),
      isEmpty,
      reason: 'a route on top of Home is not a reason to close its reads',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching account rebuilds Home on the new uid and keeps no '
      'trace of the previous one', (tester) async {
    useWindow(tester, const Size(390, 2600));
    const first = 'acct-a';
    const second = 'acct-b';
    final authA = authFor(first, 'Ala');
    final authB = authFor(second, 'Bartek');
    await db.collection('users').doc(first).set({
      'uid': first,
      'displayName': 'Ala',
      'email': 'ala@yovoice.app',
    });
    await db.collection('users').doc(second).set({
      'uid': second,
      'displayName': 'Bartek',
      'email': 'bartek@yovoice.app',
    });

    final log = <String>[];
    final roomsA = _LedgerRooms(
      firestore: db,
      auth: authA,
      log: log,
      tag: 'A:',
      live: [_liveRoom('ra', 'Pokój Ali')],
    );
    final roomsB = _LedgerRooms(
      firestore: db,
      auth: authB,
      log: log,
      tag: 'B:',
      live: [_liveRoom('rb', 'Pokój Bartka')],
    );
    final clubsA = _LedgerClubs(
      firestore: db,
      auth: authA,
      storage: MockFirebaseStorage(),
      log: log,
      tag: 'A:',
      clubs: [_club('ca', 'Klub Ali')],
    );
    final clubsB = _LedgerClubs(
      firestore: db,
      auth: authB,
      storage: MockFirebaseStorage(),
      log: log,
      tag: 'B:',
      clubs: [_club('cb', 'Klub Bartka')],
    );

    Widget homeFor(
      String uid,
      MockFirebaseAuth auth,
      _LedgerRooms rooms,
      _LedgerClubs clubs,
    ) =>
        // AuthGate keys the authenticated subtree by uid
        // (`ValueKey('auth-user-${user.uid}')`), so this is the production
        // shape of an account switch.
        app(
          KeyedSubtree(
            key: ValueKey('auth-user-$uid'),
            child: MobileHome(
              currentUserId: uid,
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
              clubService: clubs,
              friendService: _LedgerFriends(
                firestore: db,
                auth: auth,
                log: log,
              ),
              followService: _CountingFollow(firestore: db, auth: auth),
              profileService: ProfileService(firestore: db, auth: auth),
              feedService: _CountingFeed(firestore: db, auth: auth),
              messageService: _CountingMessages(firestore: db, auth: auth),
              momentViewsService: _CountingViews(firestore: db, auth: auth),
              capabilityService: _NoCapabilities(),
            ),
          ),
        );

    await tester.pumpWidget(homeFor(first, authA, roomsA, clubsA));
    await settle(tester);
    expect(find.textContaining('Ala'), findsWidgets);
    expect(find.text('Klub Ali'), findsWidgets);

    await tester.pumpWidget(homeFor(second, authB, roomsB, clubsB));
    await settle(tester);

    expect(
      find.text('Klub Ali'),
      findsNothing,
      reason: "the previous account's places must not survive the switch",
    );
    expect(find.text('Pokój Ali'), findsNothing);
    expect(find.textContaining('Bartek'), findsWidgets);
    expect(find.text('Klub Bartka'), findsWidgets);
    expect(
      log,
      containsAll(<String>['A:live:cancel', 'A:clubs:cancel']),
      reason: "the previous account's listeners are closed, not leaked",
    );
    expect(roomsB.liveCalls, 1);
    expect(clubsB.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the desktop opens the same listeners once across a layout flip',
      (tester) async {
    useWindow(tester, const Size(1440, 2200));
    const uid = 'wide-me';
    final auth = authFor(uid, 'Kamil');
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'Kamil',
      'email': 'me@yovoice.app',
    });
    final log = <String>[];
    final rooms = _LedgerRooms(
      firestore: db,
      auth: auth,
      log: log,
      live: [for (var i = 0; i < 7; i++) _liveRoom('w$i', 'Pokój $i')],
    );
    final clubs = _LedgerClubs(
      firestore: db,
      auth: auth,
      storage: MockFirebaseStorage(),
      log: log,
      clubs: [for (var i = 0; i < 5; i++) _club('wc$i', 'Miejsce $i')],
    );
    final friends = _LedgerFriends(firestore: db, auth: auth, log: log);

    Widget home() => app(
      DesktopHome(
        key: const ValueKey('wide-home'),
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
        clubService: clubs,
        friendService: friends,
        followService: _CountingFollow(firestore: db, auth: auth),
        profileService: ProfileService(firestore: db, auth: auth),
        feedService: _CountingFeed(firestore: db, auth: auth),
        messageService: _CountingMessages(firestore: db, auth: auth),
        momentViewsService: _CountingViews(firestore: db, auth: auth),
        capabilityService: _NoCapabilities(),
        firebaseAuth: auth,
      ),
    );

    await tester.pumpWidget(home());
    await settle(tester);
    expect(rooms.liveCalls, 1);
    expect(clubs.calls, 1);
    expect(friends.calls, 1);
    final rosters = rooms.openRosters;
    expect(rosters, lessThanOrEqualTo(4));

    for (final width in [1100.0, 1280.0, 1920.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 2200);
      await tester.pumpWidget(home());
      await settle(tester);
    }

    expect(rooms.liveCalls, 1, reason: 'a reflow is not a resubscribe');
    expect(clubs.calls, 1);
    expect(friends.calls, 1);
    expect(rooms.openRosters, lessThanOrEqualTo(4));
    expect(tester.takeException(), isNull);
  });

  test('the roster pool honours its budget and cancels what falls out', () async {
    final auth = authFor('pool-me', 'Kamil');
    final log = <String>[];
    final rooms = _LedgerRooms(firestore: db, auth: auth, log: log);
    final cache = HomeRosterCache(service: rooms);

    cache.request(['a', 'b', 'c', 'd', 'e', 'f']);
    await Future<void>.delayed(Duration.zero);
    expect(cache.openSubscriptionCount, 4);
    expect(rooms.rosterRoomIds, ['a', 'b', 'c', 'd']);

    // A new priority order drops what fell out and never re-opens what stays.
    cache.request(['c', 'd', 'x', 'y']);
    await Future<void>.delayed(Duration.zero);
    expect(cache.openSubscriptionCount, 4);
    expect(log, contains('roster(a):cancel'));
    expect(log, contains('roster(b):cancel'));
    expect(
      log.where((entry) => entry == 'roster(c):listen'),
      hasLength(1),
      reason: 'a room that stays in the window is not re-subscribed',
    );

    // Duplicates and empty ids never consume a slot.
    cache.request(['c', 'c', '', 'd']);
    await Future<void>.delayed(Duration.zero);
    expect(cache.openSubscriptionCount, 2);

    cache.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(rooms.openRosters, 0);
  });
}
