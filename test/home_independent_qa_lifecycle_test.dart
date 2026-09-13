import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
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
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';

/// Independent lifecycle QA for the server-first Home. Legacy room rosters
/// retain one isolated cache test; Home itself must not subscribe to them.
class _LedgerServers extends ServerService {
  _LedgerServers({
    required super.firestore,
    required super.auth,
    required this.log,
    this.tag = '',
    this.servers = const <Server>[],
  });

  final List<String> log;
  final String tag;
  final List<Server> servers;
  int calls = 0;

  @override
  Stream<List<Server>> watchMyServers() {
    calls++;
    late StreamController<List<Server>> controller;
    controller = StreamController<List<Server>>(
      onListen: () {
        log.add('${tag}servers:listen');
        controller.add(servers);
      },
      onCancel: () => log.add('${tag}servers:cancel'),
    );
    return controller.stream;
  }
}

class _LedgerFriends extends FriendService {
  _LedgerFriends({
    required super.firestore,
    required super.auth,
    required this.log,
    this.tag = '',
  });

  final List<String> log;
  final String tag;
  int calls = 0;

  @override
  Stream<List<FriendUser>> watchFriends() {
    calls++;
    late StreamController<List<FriendUser>> controller;
    controller = StreamController<List<FriendUser>>(
      onListen: () {
        log.add('${tag}friends:listen');
        controller.add(const <FriendUser>[]);
      },
      onCancel: () => log.add('${tag}friends:cancel'),
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

class _RosterRooms extends RoomService {
  _RosterRooms({
    required super.firestore,
    required super.auth,
    required this.log,
  });

  final List<String> log;
  final List<String> rosterRoomIds = <String>[];
  int openRosters = 0;

  @override
  Stream<List<RoomParticipant>> watchParticipants(String roomId) {
    rosterRoomIds.add(roomId);
    openRosters++;
    late StreamController<List<RoomParticipant>> controller;
    controller = StreamController<List<RoomParticipant>>(
      onListen: () {
        log.add('roster($roomId):listen');
        controller.add(const <RoomParticipant>[]);
      },
      onCancel: () {
        openRosters--;
        log.add('roster($roomId):cancel');
      },
    );
    return controller.stream;
  }
}

class _NoCapabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

Server _server(String id, String name, String ownerId) => Server(
  id: id,
  name: name,
  description: 'Rozmowy społeczności',
  ownerId: ownerId,
  type: ServerType.community,
  privacy: ServerPrivacy.public,
  defaultLanguage: 'Polish',
  schemaVersion: 1,
  activationState: 'active',
);

void main() {
  late FakeFirebaseFirestore db;

  MockFirebaseAuth authFor(String uid, String name) => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: '$uid@yovoice.app', displayName: name),
  );

  setUp(() {
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

  Future<void> seedProfile(String uid, String name) => db
      .collection('users')
      .doc(uid)
      .set({'uid': uid, 'displayName': name, 'email': '$uid@yovoice.app'});

  testWidgets(
    'retained Home refreshes only Moments and keeps server listeners stable',
    (tester) async {
      useWindow(tester, const Size(390, 2600));
      const uid = 'life-me';
      final auth = authFor(uid, 'Kamil');
      await seedProfile(uid, 'Kamil');
      final log = <String>[];
      final servers = _LedgerServers(
        firestore: db,
        auth: auth,
        log: log,
        servers: [for (var i = 0; i < 9; i++) _server('s$i', 'Serwer $i', uid)],
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
          serverRepository: servers,
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
      expect(servers.calls, 1);
      expect(friends.calls, 1);
      expect(feed.calls, 1);
      expect(follow.calls, 0, reason: 'Home has no follower surface');
      expect(messages.calls, 1);
      expect(views.calls, 1);

      final feedReads = feed.calls;
      visible.value = false;
      await settle(tester);
      visible.value = true;
      await settle(tester);
      expect(feed.calls, feedReads + 1);
      expect(servers.calls, 1);
      expect(friends.calls, 1);
      expect(messages.calls, 1);
      expect(views.calls, 1);
      expect(log.where((entry) => entry.endsWith(':cancel')), isEmpty);

      for (var i = 0; i < 20; i++) {
        await tester.pumpWidget(home());
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(servers.calls, 1);
      expect(friends.calls, 1);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(app(const SizedBox.shrink()));
      await settle(tester);
      expect(log, contains('servers:cancel'));
      expect(log, contains('friends:cancel'));
    },
  );

  testWidgets('a route pushed over Home does not reopen its server stream', (
    tester,
  ) async {
    useWindow(tester, const Size(390, 2600));
    const uid = 'return-me';
    final auth = authFor(uid, 'Kamil');
    await seedProfile(uid, 'Kamil');
    final log = <String>[];
    final servers = _LedgerServers(
      firestore: db,
      auth: auth,
      log: log,
      servers: [_server('s1', 'Wieczorne rozmowy', uid)],
    );
    final friends = _LedgerFriends(firestore: db, auth: auth, log: log);

    await tester.pumpWidget(
      app(
        MobileHome(
          currentUserId: uid,
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
          serverRepository: servers,
          friendService: friends,
          profileService: ProfileService(firestore: db, auth: auth),
          feedService: _CountingFeed(firestore: db, auth: auth),
          messageService: _CountingMessages(firestore: db, auth: auth),
          momentViewsService: _CountingViews(firestore: db, auth: auth),
          capabilityService: _NoCapabilities(),
        ),
      ),
    );
    await settle(tester);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('workspace')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();

    expect(servers.calls, 1);
    expect(friends.calls, 1);
    expect(log.where((entry) => entry.endsWith(':cancel')), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching account closes the old server world', (tester) async {
    useWindow(tester, const Size(390, 2600));
    const first = 'acct-a';
    const second = 'acct-b';
    final authA = authFor(first, 'Ala');
    final authB = authFor(second, 'Bartek');
    await seedProfile(first, 'Ala');
    await seedProfile(second, 'Bartek');
    final log = <String>[];
    final serversA = _LedgerServers(
      firestore: db,
      auth: authA,
      log: log,
      tag: 'A:',
      servers: [_server('sa', 'Serwer Ali', first)],
    );
    final serversB = _LedgerServers(
      firestore: db,
      auth: authB,
      log: log,
      tag: 'B:',
      servers: [_server('sb', 'Serwer Bartka', second)],
    );

    Widget homeFor(String uid, MockFirebaseAuth auth, _LedgerServers servers) =>
        app(
          KeyedSubtree(
            key: ValueKey('auth-user-$uid'),
            child: MobileHome(
              currentUserId: uid,
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
              serverRepository: servers,
              friendService: _LedgerFriends(
                firestore: db,
                auth: auth,
                log: log,
                tag: '$uid:',
              ),
              profileService: ProfileService(firestore: db, auth: auth),
              feedService: _CountingFeed(firestore: db, auth: auth),
              messageService: _CountingMessages(firestore: db, auth: auth),
              momentViewsService: _CountingViews(firestore: db, auth: auth),
              capabilityService: _NoCapabilities(),
            ),
          ),
        );

    await tester.pumpWidget(homeFor(first, authA, serversA));
    await settle(tester);
    expect(find.text('Serwer Ali'), findsWidgets);

    await tester.pumpWidget(homeFor(second, authB, serversB));
    await settle(tester);
    expect(find.text('Serwer Ali'), findsNothing);
    expect(find.text('Serwer Bartka'), findsWidgets);
    expect(log, contains('A:servers:cancel'));
    expect(serversB.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop reflow does not resubscribe server or friends', (
    tester,
  ) async {
    useWindow(tester, const Size(1440, 2200));
    const uid = 'wide-me';
    final auth = authFor(uid, 'Kamil');
    await seedProfile(uid, 'Kamil');
    final log = <String>[];
    final servers = _LedgerServers(
      firestore: db,
      auth: auth,
      log: log,
      servers: [for (var i = 0; i < 7; i++) _server('s$i', 'Serwer $i', uid)],
    );
    final friends = _LedgerFriends(firestore: db, auth: auth, log: log);

    Widget home() => app(
      DesktopHome(
        key: const ValueKey('wide-home'),
        currentUserId: uid,
        onSeeAllRooms: () {},
        onViewAllFriends: () {},
        onStartRoom: () {},
        onOpenMoment: (_) {},
        onCreateMoment: () {},
        onSeeAllMoments: () {},
        onOpenConversation: (_) {},
        onSeeAllChats: () {},
        onOpenClubs: () {},
        serverRepository: servers,
        friendService: friends,
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
    for (final width in [1100.0, 1280.0, 1920.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 2200);
      await tester.pumpWidget(home());
      await settle(tester);
    }
    expect(servers.calls, 1);
    expect(friends.calls, 1);
    expect(tester.takeException(), isNull);
  });

  test(
    'the legacy roster cache still honours its four-listener budget',
    () async {
      final auth = authFor('pool-me', 'Kamil');
      final log = <String>[];
      final rooms = _RosterRooms(firestore: db, auth: auth, log: log);
      final cache = HomeRosterCache(service: rooms);

      cache.request(['a', 'b', 'c', 'd', 'e', 'f']);
      await Future<void>.delayed(Duration.zero);
      expect(cache.openSubscriptionCount, 4);
      expect(rooms.rosterRoomIds, ['a', 'b', 'c', 'd']);

      cache.request(['c', 'd', 'x', 'y']);
      await Future<void>.delayed(Duration.zero);
      expect(cache.openSubscriptionCount, 4);
      expect(log, contains('roster(a):cancel'));
      expect(log, contains('roster(b):cancel'));
      expect(log.where((entry) => entry == 'roster(c):listen'), hasLength(1));

      cache.request(['c', 'c', '', 'd']);
      await Future<void>.delayed(Duration.zero);
      expect(cache.openSubscriptionCount, 2);
      cache.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(rooms.openRosters, 0);
    },
  );
}
