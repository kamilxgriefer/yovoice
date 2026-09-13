import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_greeting_header.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';

/// INDEPENDENT QA — the widths and text sizes the owner actually asked for,
/// and every door Home draws.
///
/// A widget test fails on a RenderFlex overflow by itself, so pumping the
/// REAL composition with the REAL long Polish fixtures at every declared
/// width × 100 % / 200 % text is the assertion. What it cannot prove is what
/// the screen LOOKS like; that stays the Visual Quality Specialist's step.

class _Servers extends ServerService {
  _Servers({
    required super.firestore,
    required super.auth,
    required this.servers,
  });

  final List<Server> servers;

  @override
  Stream<List<Server>> watchMyServers() => Stream<List<Server>>.value(servers);
}

class _SilentFeed extends HomeFeedService {
  _SilentFeed({required super.firestore, required super.auth});
  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.value(const <VoiceMoment>[]);
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

/// The longest realistic Polish fixtures the brief names, plus a server with
/// no image: the data Home must survive, not the data it was designed against.
const _longName = 'Bartłomiej-Krzysztof Wojciechowski';
const _longPlace = 'Podcasty nam bliskie i dalekie';
const _server = Server(
  id: 's1',
  name: _longPlace,
  description: 'Rozmowy społeczności po godzinach.',
  ownerId: 'reflow-me',
  type: ServerType.community,
  privacy: ServerPrivacy.public,
  defaultLanguage: 'Polish',
  schemaVersion: 1,
  activationState: 'active',
);

void main() {
  const uid = 'reflow-me';
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;

  setUp(() async {
    ProfileService.resetCurrentProfileCache();
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: uid,
        email: 'bartlomiej@yovoice.app',
        displayName: _longName,
      ),
    );
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': _longName,
      'email': 'bartlomiej@yovoice.app',
    });
    // Friends with no avatar at all.
    for (final (id, name) in [
      ('f1', 'Aleksandra Nowakowska-Zielińska'),
      ('f2', 'Ola'),
      ('f3', _longName),
    ]) {
      await db.collection('publicProfiles').doc(id).set({
        'uid': id,
        'displayName': name,
        'username': id,
      });
      await db.collection('users').doc(uid).collection('friends').doc(id).set({
        'friendId': id,
        'createdAt': Timestamp.now(),
      });
    }
    await db.collection('conversations').doc('c1').set({
      'participantIds': [uid, 'f1'],
      'participantNames': {
        uid: _longName,
        'f1': 'Aleksandra Nowakowska-Zielińska',
      },
      'participantEmails': <String, String>{},
      'participantPhotoUrls': <String, String>{},
      'unreadCounts': {uid: 3, 'f1': 0},
      'lastMessage': 'Do zobaczenia w sobotę!',
      'lastMessageType': 'text',
      'lastMessageSenderId': 'f1',
      'updatedAt': Timestamp.now(),
      'createdAt': Timestamp.now(),
      'archivedBy': <String>[],
      'mutedBy': <String>[],
    });
  });
  tearDown(ProfileService.resetCurrentProfileCache);

  Widget app(Widget child, {required Size size, required double textScale}) =>
      MaterialApp(
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

  MobileHome mobileHome({
    VoidCallback? onOpenFriends,
    VoidCallback? onOpenServers,
    VoidCallback? onOpenDiscover,
    VoidCallback? onCreateMoment,
    VoidCallback? onOpenNotifications,
    VoidCallback? onOpenProfile,
    VoidCallback? onSeeAllChats,
    ValueChanged<Server>? onOpenServer,
    ValueChanged<Conversation>? onOpenConversation,
    List<Server> servers = const [_server],
  }) => MobileHome(
    currentUserId: uid,
    unreadNotificationCount: 7,
    onOpenRoom: (_) {},
    onOpenDiscover: onOpenDiscover ?? () {},
    onOpenFriends: onOpenFriends ?? () {},
    onOpenNotifications: onOpenNotifications ?? () {},
    onOpenProfile: onOpenProfile ?? () {},
    onCreateMoment: onCreateMoment ?? () {},
    onCreateRoom: () {},
    onOpenMoment: (_) {},
    onOpenComments: (_) {},
    onOpenConversation: onOpenConversation ?? (_) {},
    onSeeAllChats: onSeeAllChats ?? () {},
    onOpenServers: onOpenServers,
    onOpenServer: onOpenServer,
    serverRepository: _Servers(firestore: db, auth: auth, servers: servers),
    friendService: FriendService(firestore: db, auth: auth),
    profileService: ProfileService(firestore: db, auth: auth),
    feedService: _SilentFeed(firestore: db, auth: auth),
    messageService: MessageService(firestore: db, auth: auth),
    momentViewsService: _SilentViews(firestore: db, auth: auth),
    capabilityService: _NoCapabilities(),
  );

  DesktopHome desktopHome({
    VoidCallback? onOpenServers,
    VoidCallback? onOpenFriends,
    VoidCallback? onCreateMoment,
    VoidCallback? onSeeAllChats,
    VoidCallback? onOpenNotifications,
    VoidCallback? onOpenProfile,
    ValueChanged<Server>? onOpenServer,
    ValueChanged<Conversation>? onOpenConversation,
    List<Server> servers = const [_server],
  }) => DesktopHome(
    currentUserId: uid,
    unreadNotificationCount: 7,
    onOpenRoom: (_) {},
    onSeeAllRooms: () {},
    onViewAllFriends: onOpenFriends ?? () {},
    onStartRoom: () {},
    onOpenMoment: (_) {},
    onCreateMoment: onCreateMoment ?? () {},
    onSeeAllMoments: () {},
    onOpenConversation: onOpenConversation ?? (_) {},
    onSeeAllChats: onSeeAllChats ?? () {},
    onOpenClubs: () {},
    onOpenServers: onOpenServers,
    onOpenServer: onOpenServer,
    onOpenNotifications: onOpenNotifications,
    onOpenProfile: onOpenProfile,
    serverRepository: _Servers(firestore: db, auth: auth, servers: servers),
    friendService: FriendService(firestore: db, auth: auth),
    profileService: ProfileService(firestore: db, auth: auth),
    feedService: _SilentFeed(firestore: db, auth: auth),
    messageService: MessageService(firestore: db, auth: auth),
    momentViewsService: _SilentViews(firestore: db, auth: auth),
    capabilityService: _NoCapabilities(),
    firebaseAuth: auth,
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// Nothing may be laid out wider than the surface it is drawn on: a phone
  /// page that scrolls sideways is a broken page even when no overflow
  /// stripe is painted.
  void expectNoHorizontalOverrun(WidgetTester tester, double width) {
    for (final element in find.byType(Scrollable).evaluate()) {
      final scrollable = element.widget as Scrollable;
      if (scrollable.axisDirection == AxisDirection.right ||
          scrollable.axisDirection == AxisDirection.left) {
        // Full-bleed rails are horizontal ON PURPOSE — but they must still
        // fit the surface.
        final box = element.findRenderObject()! as RenderBox;
        expect(box.size.width, lessThanOrEqualTo(width + 0.5));
      }
    }
    final page = tester.renderObject<RenderBox>(find.byType(Scaffold).first);
    expect(page.size.width, lessThanOrEqualTo(width + 0.5));
  }

  group('the phone shell: 320 / 360 / 390 / 430 / 768 × 1.0 and 2.0 text', () {
    for (final width in [320.0, 360.0, 390.0, 430.0, 768.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('populated Home at ${width.toInt()} × $scale text', (
          tester,
        ) async {
          final size = Size(width, scale > 1 ? 6000 : 3200);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            app(mobileHome(), size: size, textScale: scale),
          );
          await settle(tester);

          expect(tester.takeException(), isNull);
          expectNoHorizontalOverrun(tester, width);
          final friend = find.byKey(const ValueKey('home-person-f1'));
          final continueServer = find.byKey(
            const ValueKey('home-server-continue-s1'),
          );
          expect(continueServer, findsOneWidget);
          expect(
            find.byKey(const ValueKey('home-record-moment')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('home-servers-overview')),
            findsOneWidget,
          );
          expect(
            friend,
            findsOneWidget,
            reason: 'a real friend with a long name and no avatar',
          );
          expect(
            tester.getTopLeft(friend).dy,
            lessThan(tester.getTopLeft(continueServer).dy),
            reason: 'friends stay above the server-first activity card',
          );
          expect(find.text('Do zobaczenia w sobotę!'), findsOneWidget);
          expect(find.text('Obserwowani'), findsNothing);
          expect(find.text('Followers'), findsNothing);
        });
      }
    }

    testWidgets('the empty account at 360 × 2.0 text', (tester) async {
      const size = Size(360, 6000);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(mobileHome(servers: const []), size: size, textScale: 2),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('home-servers-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-servers-overview')), findsNothing);
      expect(
        find.byKey(const ValueKey('home-quick-create-server')),
        findsOneWidget,
      );
      expect(find.text('Kluby'), findsNothing);
      expect(find.text('Clubs'), findsNothing);
      expectNoHorizontalOverrun(tester, 360);
    });
  });

  group('the desktop shell: 1100 / 1280 / 1440 × 1.0 and 2.0 text', () {
    for (final width in [1100.0, 1280.0, 1440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('populated Home at ${width.toInt()} × $scale text', (
          tester,
        ) async {
          // The rail is the shell's; DesktopHome is given the content slot.
          final slot = width - 264;
          final size = Size(slot, scale > 1 ? 6000 : 3200);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            app(desktopHome(), size: size, textScale: scale),
          );
          await settle(tester);

          expect(tester.takeException(), isNull);
          expectNoHorizontalOverrun(tester, slot);
          final friend = find.byKey(const ValueKey('home-person-f1'));
          final continueServer = find.byKey(
            const ValueKey('home-server-continue-s1'),
          );
          expect(continueServer, findsOneWidget);
          expect(
            find.byKey(const ValueKey('home-record-moment')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('home-servers-overview')),
            findsOneWidget,
          );
          expect(friend, findsOneWidget);
          expect(
            tester.getTopLeft(friend).dy,
            lessThan(tester.getTopLeft(continueServer).dy),
          );
          expect(find.text('Do zobaczenia w sobotę!'), findsOneWidget);
          expect(find.text('Obserwowani'), findsNothing);
          expect(find.text('Followers'), findsNothing);
        });
      }
    }
  });

  group('every door Home draws leads somewhere', () {
    testWidgets('phone', (tester) async {
      const size = Size(390, 4000);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final doors = <String, int>{};
      void ring(String name) => doors[name] = (doors[name] ?? 0) + 1;

      await tester.pumpWidget(
        app(
          mobileHome(
            onOpenFriends: () => ring('friends'),
            onOpenServers: () => ring('servers'),
            onOpenServer: (_) => ring('workspace'),
            onOpenDiscover: () => ring('discover'),
            onCreateMoment: () => ring('record'),
            onOpenNotifications: () => ring('notifications'),
            onOpenProfile: () => ring('profile'),
            onSeeAllChats: () => ring('chats'),
            onOpenConversation: (_) => ring('conversation'),
          ),
          size: size,
          textScale: 1,
        ),
      );
      await settle(tester);

      Future<void> tapKey(String key) async {
        final finder = find.byKey(ValueKey(key));
        expect(finder, findsOneWidget, reason: 'missing door: $key');
        await tester.ensureVisible(finder);
        await tester.pump();
        await tester.tap(finder, warnIfMissed: false);
        await tester.pump();
      }

      await tapKey('home-people-see-all');
      await tapKey('home-quick-create-server');
      await tapKey('home-record-moment');
      await tapKey('home-server-row-s1');
      final recentChat = find.text('Do zobaczenia w sobotę!');
      expect(recentChat, findsOneWidget);
      await tester.ensureVisible(recentChat);
      await tester.tap(recentChat, warnIfMissed: false);
      await tester.pump();

      // The header controls carry no key; they are found by their spoken
      // label, which is what a screen-reader user has.
      await tester.ensureVisible(find.byType(HomeGreetingHeader));
      await tester.tap(find.byType(HomeHeaderDisc), warnIfMissed: false);
      await tester.pump();
      await tester.tap(
        find.bySemanticsLabel('Otwórz swój profil'),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(doors['friends'], 1, reason: '"Zobacz wszystkich" → Znajomi');
      expect(doors['servers'], 1, reason: '"Stwórz serwer" → Serwery');
      expect(doors['workspace'], 1, reason: 'server row → exact workspace');
      expect(doors['record'], 1);
      expect(doors['conversation'], 1, reason: 'recent chat → conversation');
      expect(doors['notifications'], 1);
      expect(doors['profile'], 1);
      expect(find.text('Kluby'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('desktop', (tester) async {
      const size = Size(1176, 4000);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final doors = <String, int>{};
      void ring(String name) => doors[name] = (doors[name] ?? 0) + 1;

      await tester.pumpWidget(
        app(
          desktopHome(
            onOpenServers: () => ring('servers'),
            onOpenServer: (_) => ring('workspace'),
            onOpenFriends: () => ring('friends'),
            onCreateMoment: () => ring('record'),
            onOpenConversation: (_) => ring('conversation'),
            onOpenNotifications: () => ring('notifications'),
            onOpenProfile: () => ring('profile'),
          ),
          size: size,
          textScale: 1,
        ),
      );
      await settle(tester);

      await tester.tap(find.byType(HomeHeaderDisc).first, warnIfMissed: false);
      await tester.pump();
      await tester.tap(
        find.bySemanticsLabel('Otwórz swój profil').first,
        warnIfMissed: false,
      );
      await tester.pump();

      Future<void> tapKey(String key) async {
        final finder = find.byKey(ValueKey(key));
        expect(finder, findsOneWidget, reason: 'missing door: $key');
        await tester.ensureVisible(finder);
        await tester.tap(finder, warnIfMissed: false);
        await tester.pump();
      }

      await tapKey('home-people-see-all');
      await tapKey('home-quick-create-server');
      await tapKey('home-record-moment');
      await tapKey('home-server-row-s1');
      final recentChat = find.text('Do zobaczenia w sobotę!');
      await tester.ensureVisible(recentChat);
      await tester.tap(recentChat, warnIfMissed: false);
      await tester.pump();

      expect(doors['notifications'], 1);
      expect(doors['profile'], 1);
      expect(doors['servers'], 1);
      expect(doors['workspace'], 1);
      expect(doors['friends'], 1);
      expect(doors['record'], 1);
      expect(doors['conversation'], 1);
      expect(find.text('Kluby'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
