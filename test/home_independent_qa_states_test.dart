import 'dart:async';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
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
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_status.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';

FirebaseException _denied(String path) => FirebaseException(
  plugin: 'cloud_firestore',
  code: 'permission-denied',
  message: 'Missing or insufficient permissions: $path',
);

class _Servers extends ServerService {
  _Servers({
    required super.firestore,
    required super.auth,
    required this.streamFactory,
  });

  final Stream<List<Server>> Function() streamFactory;

  @override
  Stream<List<Server>> watchMyServers() => streamFactory();
}

class _DeniedFriends extends FriendService {
  _DeniedFriends({required super.firestore, required super.auth});

  @override
  Stream<List<FriendUser>> watchFriends() =>
      Stream<List<FriendUser>>.error(_denied('users/{uid}/friends'));
}

class _DeniedMessages extends MessageService {
  _DeniedMessages({required super.firestore, required super.auth});

  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) => Stream<List<Conversation>>.error(_denied('conversations'));
}

class _SilentFeed extends HomeFeedService {
  _SilentFeed({required super.firestore, required super.auth});

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.value(const <VoiceMoment>[]);
}

class _CountingFollow extends FollowService {
  _CountingFollow({required super.firestore, required super.auth});
  int calls = 0;

  @override
  Stream<List<FollowUser>> watchFollowing(String userId) {
    calls++;
    return Stream<List<FollowUser>>.value(const <FollowUser>[]);
  }
}

class _SilentViews extends MomentViewsService {
  _SilentViews({required super.firestore, required super.auth});

  @override
  Stream<Set<String>> watchViewedMomentIds() =>
      Stream<Set<String>>.value(const <String>{});
}

class _NoCapabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

const _server = Server(
  id: 'community',
  name: 'Rozmowy sąsiedzkie',
  description: 'Wspólne sprawy i wieczorne rozmowy.',
  ownerId: 'qa-me',
  type: ServerType.community,
  privacy: ServerPrivacy.public,
  defaultLanguage: 'Polish',
  schemaVersion: 1,
  activationState: 'active',
);

void main() {
  const uid = 'qa-me';
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;

  setUp(() async {
    ProfileService.resetCurrentProfileCache();
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: uid,
        email: 'me@yovoice.app',
        displayName: 'Kamil Jaguszewski',
      ),
    );
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'Kamil Jaguszewski',
      'email': 'me@yovoice.app',
    });
  });
  tearDown(ProfileService.resetCurrentProfileCache);

  Widget app(
    Widget child, {
    Size size = const Size(390, 2600),
    double textScale = 1,
  }) => MaterialApp(
    theme: AppTheme.darkTheme,
    locale: const Locale('pl'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
        disableAnimations: true,
      ),
      child: Scaffold(body: child),
    ),
  );

  ServerRepository servers(Stream<List<Server>> stream) =>
      _Servers(firestore: db, auth: auth, streamFactory: () => stream);

  MobileHome mobile({
    required ServerRepository servers,
    FriendService? friends,
    MessageService? messages,
    FollowService? follow,
    ValueChanged<Server>? onOpenServer,
    VoidCallback? onOpenServers,
  }) => MobileHome(
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
    onOpenServers: onOpenServers,
    onOpenServer: onOpenServer,
    serverRepository: servers,
    friendService: friends ?? FriendService(firestore: db, auth: auth),
    followService: follow,
    profileService: ProfileService(firestore: db, auth: auth),
    feedService: _SilentFeed(firestore: db, auth: auth),
    messageService: messages ?? MessageService(firestore: db, auth: auth),
    momentViewsService: _SilentViews(firestore: db, auth: auth),
    capabilityService: _NoCapabilities(),
  );

  DesktopHome desktop({required ServerRepository servers}) => DesktopHome(
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
    friendService: FriendService(firestore: db, auth: auth),
    profileService: ProfileService(firestore: db, auth: auth),
    feedService: _SilentFeed(firestore: db, auth: auth),
    messageService: MessageService(firestore: db, auth: auth),
    momentViewsService: _SilentViews(firestore: db, auth: auth),
    capabilityService: _NoCapabilities(),
    firebaseAuth: auth,
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

  testWidgets('server loading, empty, ready and denied stay distinct', (
    tester,
  ) async {
    useWindow(tester, const Size(390, 2600));
    final controller = StreamController<List<Server>>();
    addTearDown(controller.close);
    await tester.pumpWidget(app(mobile(servers: servers(controller.stream))));
    await settle(tester);
    expect(find.byKey(const ValueKey('home-servers-loading')), findsOneWidget);

    controller.add([]);
    await settle(tester);
    expect(find.byKey(const ValueKey('home-servers-empty')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-empty-create-server')),
      findsOneWidget,
    );

    controller.add([_server]);
    await settle(tester);
    expect(
      find.byKey(const ValueKey('home-server-continue-community')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-servers-overview')), findsOneWidget);

    controller.addError(_denied('servers'));
    await settle(tester);
    expect(find.byKey(const ValueKey('home-servers-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-servers-empty')), findsNothing);
    expect(find.text('Spróbuj ponownie'), findsWidgets);
    expect(
      find.byKey(const ValueKey('home-quick-create-server')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop keeps server actions under a denial', (tester) async {
    useWindow(tester, const Size(1440, 2400));
    await tester.pumpWidget(
      app(
        desktop(servers: servers(Stream.error(_denied('servers')))),
        size: const Size(1440, 2400),
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('home-servers-error')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-quick-create-server')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-servers-empty')), findsNothing);
  });

  testWidgets('friends denial stays separate from an available server', (
    tester,
  ) async {
    useWindow(tester, const Size(390, 2600));
    await tester.pumpWidget(
      app(
        mobile(
          servers: servers(Stream.value(const [_server])),
          friends: _DeniedFriends(firestore: db, auth: auth),
        ),
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('home-people-error')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-server-continue-community')),
      findsOneWidget,
    );
  });

  testWidgets('chat denial is not rendered as an empty recent-chat state', (
    tester,
  ) async {
    useWindow(tester, const Size(390, 2600));
    await tester.pumpWidget(
      app(
        mobile(
          servers: servers(Stream.value(const [_server])),
          messages: _DeniedMessages(firestore: db, auth: auth),
        ),
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('home-chats-error')), findsOneWidget);
    expect(find.text('Znajdź znajomych'), findsNothing);
  });

  testWidgets('simultaneous current-source denials share one error scope', (
    tester,
  ) async {
    useWindow(tester, const Size(390, 3000));
    await tester.pumpWidget(
      app(
        mobile(
          servers: servers(Stream.error(_denied('servers'))),
          friends: _DeniedFriends(firestore: db, auth: auth),
          messages: _DeniedMessages(firestore: db, auth: auth),
        ),
        size: const Size(390, 3000),
      ),
    );
    await settle(tester);
    expect(find.byType(HomeSectionError), findsNWidgets(3));
    expect(find.byType(HomeErrorAnnouncementScope), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a server card hands the shell the exact server and joins none', (
    tester,
  ) async {
    useWindow(tester, const Size(390, 2600));
    final opened = <Server>[];
    var directoryOpens = 0;
    await tester.pumpWidget(
      app(
        mobile(
          servers: servers(Stream.value(const [_server])),
          onOpenServer: opened.add,
          onOpenServers: () => directoryOpens++,
        ),
      ),
    );
    await settle(tester);
    await tester.tap(
      find.byKey(const ValueKey('home-server-continue-community')),
    );
    expect(opened, [_server]);
    expect(directoryOpens, 0);
    expect((await db.collection('rooms').get()).docs, isEmpty);
  });

  testWidgets('Home has no follower surface or following subscription', (
    tester,
  ) async {
    useWindow(tester, const Size(390, 2600));
    final follow = _CountingFollow(firestore: db, auth: auth);
    await tester.pumpWidget(
      app(
        mobile(servers: servers(Stream.value(const [_server])), follow: follow),
      ),
    );
    await settle(tester);
    expect(follow.calls, 0);
    expect(find.text('Obserwowani'), findsNothing);
    expect(find.text('Followers'), findsNothing);
  });

  testWidgets('long server copy grows cleanly at 320 px and 200% text', (
    tester,
  ) async {
    const size = Size(320, 3000);
    useWindow(tester, size);
    const longServer = Server(
      id: 'long',
      name: 'Podcasty nam bliskie i dalekie — salon po godzinach',
      description:
          'Bardzo długi opis społeczności bez awatara, okładki ani licznika.',
      ownerId: uid,
      type: ServerType.community,
      privacy: ServerPrivacy.public,
      schemaVersion: 1,
      activationState: 'active',
    );
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'Bartłomiej-Krzysztof Wojciechowski',
      'email': 'me@yovoice.app',
    });
    await tester.pumpWidget(
      app(
        mobile(servers: servers(Stream.value(const [longServer]))),
        size: size,
        textScale: 2,
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Bartłomiej-Krzysztof'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-server-continue-long')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('0 osób')), findsNothing);
  });

  test('Home imports no audio, LiveKit or microphone permission code', () {
    final home = Directory('lib/features/home/presentation/widgets');
    final offenders = <String>[];
    for (final entity in home.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final line in entity.readAsStringSync().split('\n')) {
        if (!line.trimLeft().startsWith('import ')) continue;
        if (line.contains('voice_call_service') ||
            line.contains('livekit') ||
            line.contains('permission_readiness') ||
            line.contains('room_voice_entry_coordinator') ||
            line.contains('permission_handler')) {
          offenders.add('${entity.path}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('integrated Home reads servers and no removed social-space sources', () {
    for (final path in [
      'lib/features/home/presentation/widgets/mobile/mobile_home.dart',
      'lib/features/home/presentation/widgets/desktop/desktop_home.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('watchMyServers'));
      expect(source, isNot(contains('watchLivePublicRooms')));
      expect(source, isNot(contains('watchOwnedRooms')));
      expect(source, isNot(contains('watchMyClubs')));
      expect(source, isNot(contains('watchFollowing(')));
    }
  });
}
