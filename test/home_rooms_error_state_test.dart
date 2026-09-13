import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';

/// Server-first Home keeps denied, empty and recovered repository states
/// distinct on both responsive compositions.
class _FailingServerService extends ServerService {
  _FailingServerService({super.firestore, super.auth});

  @override
  Stream<List<Server>> watchMyServers() => Stream<List<Server>>.error(
    FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Missing or insufficient permissions.',
    ),
  );
}

class _RecoveringServerService extends ServerService {
  _RecoveringServerService({super.firestore, super.auth});

  int subscriptions = 0;

  @override
  Stream<List<Server>> watchMyServers() {
    subscriptions += 1;
    if (subscriptions == 1) {
      return Stream<List<Server>>.error(
        StateError('temporary server query failure'),
      );
    }
    return Stream<List<Server>>.value(const <Server>[]);
  }
}

void main() {
  const uid = 'me-uid';

  late FakeFirebaseFirestore db;

  MockFirebaseAuth auth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: 'me@yovoice.app', displayName: 'Kamil'),
  );

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

  void useSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  MobileHome mobileHome({required ServerRepository servers}) {
    final firebaseAuth = auth();
    return MobileHome(
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
      serverRepository: servers,
      friendService: FriendService(firestore: db, auth: firebaseAuth),
      profileService: ProfileService(firestore: db, auth: firebaseAuth),
      feedService: HomeFeedService(firestore: db, auth: firebaseAuth),
      messageService: MessageService(firestore: db, auth: firebaseAuth),
      currentUserId: uid,
    );
  }

  DesktopHome desktopHome({required ServerRepository servers}) {
    final firebaseAuth = auth();
    return DesktopHome(
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
      serverRepository: servers,
      friendService: FriendService(firestore: db, auth: firebaseAuth),
      followService: FollowService(firestore: db, auth: firebaseAuth),
      profileService: ProfileService(firestore: db, auth: firebaseAuth),
      feedService: HomeFeedService(firestore: db, auth: firebaseAuth),
      messageService: MessageService(firestore: db, auth: firebaseAuth),
      firebaseAuth: firebaseAuth,
    );
  }

  testWidgets('mobile: a failed server query stays distinct from empty', (
    tester,
  ) async {
    useSize(tester, const Size(390, 2600));

    await tester.pumpWidget(
      host(
        mobileHome(
          servers: _FailingServerService(firestore: db, auth: auth()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    final error = find.byKey(const ValueKey('home-servers-error'));
    expect(error, findsOneWidget);
    expect(
      find.descendant(
        of: error,
        matching: find.text(
          "Your servers could not be loaded. You don't have permission to do that.",
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text('A good conversation starts in your server.'),
      findsNothing,
    );
    expect(
      find.descendant(
        of: error,
        matching: find.byIcon(Icons.cloud_off_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: error, matching: find.text('Try again')),
      findsOneWidget,
    );
  });

  testWidgets('mobile: an empty server list still reads as empty', (
    tester,
  ) async {
    useSize(tester, const Size(390, 2600));

    await tester.pumpWidget(
      host(
        mobileHome(
          servers: ServerService(firestore: db, auth: auth()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.text('A good conversation starts in your server.'),
      findsOneWidget,
    );
    expect(find.textContaining('could not be loaded'), findsNothing);
  });

  testWidgets('desktop: a failed server query says so', (tester) async {
    useSize(tester, const Size(1440, 2600));

    await tester.pumpWidget(
      host(
        desktopHome(
          servers: _FailingServerService(firestore: db, auth: auth()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    final error = find.byKey(const ValueKey('home-servers-error'));
    expect(error, findsOneWidget);
    expect(
      find.descendant(
        of: error,
        matching: find.text(
          "Your servers could not be loaded. You don't have permission to do that.",
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text('A good conversation starts in your server.'),
      findsNothing,
    );
    expect(
      find.descendant(
        of: error,
        matching: find.byIcon(Icons.cloud_off_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: error, matching: find.text('Try again')),
      findsOneWidget,
    );
  });

  testWidgets('desktop: an empty server list still reads as empty', (
    tester,
  ) async {
    useSize(tester, const Size(1440, 2600));

    await tester.pumpWidget(
      host(
        desktopHome(
          servers: ServerService(firestore: db, auth: auth()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.text('A good conversation starts in your server.'),
      findsOneWidget,
    );
    expect(find.textContaining('could not be loaded'), findsNothing);
  });

  testWidgets('mobile: Try again creates a fresh server subscription', (
    tester,
  ) async {
    useSize(tester, const Size(390, 2600));
    final servers = _RecoveringServerService(firestore: db, auth: auth());

    await tester.pumpWidget(host(mobileHome(servers: servers)));
    await tester.pump(const Duration(milliseconds: 150));
    final error = find.byKey(const ValueKey('home-servers-error'));
    final retry = find.descendant(of: error, matching: find.text('Try again'));
    expect(retry, findsOneWidget);

    await tester.tap(retry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(servers.subscriptions, 2);
    expect(error, findsNothing);
    expect(
      find.text('A good conversation starts in your server.'),
      findsOneWidget,
    );
    expect(find.textContaining('could not be loaded'), findsNothing);
  });

  testWidgets('desktop: Try again creates a fresh server subscription', (
    tester,
  ) async {
    useSize(tester, const Size(1440, 2600));
    final servers = _RecoveringServerService(firestore: db, auth: auth());

    await tester.pumpWidget(host(desktopHome(servers: servers)));
    await tester.pump(const Duration(milliseconds: 150));
    final error = find.byKey(const ValueKey('home-servers-error'));
    final retry = find.descendant(of: error, matching: find.text('Try again'));
    expect(retry, findsOneWidget);

    await tester.tap(retry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(servers.subscriptions, 2);
    expect(error, findsNothing);
    expect(
      find.text('A good conversation starts in your server.'),
      findsOneWidget,
    );
    expect(find.textContaining('could not be loaded'), findsNothing);
  });
}
