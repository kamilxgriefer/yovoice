import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_greeting_header.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';

/// INDEPENDENT QA — the widths and text sizes the owner actually asked for,
/// and every door Home draws.
///
/// A widget test fails on a RenderFlex overflow by itself, so pumping the
/// REAL composition with the REAL long Polish fixtures at every declared
/// width × 100 % / 200 % text is the assertion. What it cannot prove is what
/// the screen LOOKS like; that stays the Visual Quality Specialist's step.

class _Clubs extends ClubService {
  _Clubs({
    required super.firestore,
    required super.auth,
    required super.storage,
    this.clubs = const <Club>[],
  });
  final List<Club> clubs;
  @override
  Stream<List<Club>> watchMyClubs() => Stream<List<Club>>.value(clubs);
}

class _SilentFeed extends HomeFeedService {
  _SilentFeed({required super.firestore, required super.auth});
  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.value(const <VoiceMoment>[]);
}

class _SilentFollow extends FollowService {
  _SilentFollow({required super.firestore, required super.auth});
  @override
  Stream<List<FollowUser>> watchFollowing(String userId) =>
      const Stream<List<FollowUser>>.empty();
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

/// The longest realistic Polish fixtures the brief names, plus a club with no
/// avatar and a room with no cover: the data Home must survive, not the data
/// it was designed against.
const _longName = 'Bartłomiej-Krzysztof Wojciechowski';
const _longPlace = 'Podcasty nam bliskie i dalekie';
const _longRoom = 'Salon po godzinach — rozmowy o wszystkim i o niczym';

Club _club(String id, String name, {int members = 12}) => Club(
  id: id,
  name: name,
  description: 'Opis miejsca',
  ownerId: 'owner-$id',
  ownerName: _longName,
  avatarUrl: null,
  bannerUrl: null,
  privacy: ClubPrivacy.private,
  defaultLanguage: 'Polish',
  memberCount: members,
  onlineCount: 0,
  defaultChatChannelId: '',
  defaultVoiceChannelId: '',
  announcementChannelId: '',
  createdAt: null,
  updatedAt: null,
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
    // One live public room with a long name, no cover, a speaker and a
    // listener — the populated hero.
    await db.collection('rooms').doc('r1').set({
      'hostId': 'host-r1',
      'hostName': _longName,
      'name': _longRoom,
      'description': '',
      'category': 'community',
      'visibility': 'public',
      'language': 'Polish',
      'participantCount': 22,
      'memberCount': 0,
      'isLive': true,
      'roomType': 'community',
      'status': 'active',
      'experience': 'community',
      'createdAt': Timestamp.now(),
    });
    for (final (id, role, name) in [
      ('sp1', 'host', 'Małgorzata Wiśniewska-Kowalczyk'),
      ('sp2', 'speaker', 'Ola'),
      ('li1', 'listener', 'Bartek'),
    ]) {
      await db
          .collection('rooms')
          .doc('r1')
          .collection('participants')
          .doc(id)
          .set({
            'userId': id,
            'displayName': name,
            'role': role,
            'isMuted': false,
            'isSpeaker': role != 'listener',
          });
    }
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
      'participantNames': {uid: _longName, 'f1': 'Aleksandra Nowakowska-Zielińska'},
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

  ClubService clubs() => _Clubs(
    firestore: db,
    auth: auth,
    storage: MockFirebaseStorage(),
    clubs: [
      _club('c1', _longPlace),
      _club('c2', 'Klub Ł', members: 1),
      _club('c3', 'Rodzinny salon'),
    ],
  );

  Widget app(
    Widget child, {
    required Size size,
    required double textScale,
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

  MobileHome mobileHome({
    VoidCallback? onOpenFriends,
    VoidCallback? onOpenServers,
    VoidCallback? onOpenDiscover,
    VoidCallback? onCreateMoment,
    VoidCallback? onOpenNotifications,
    VoidCallback? onOpenProfile,
    VoidCallback? onSeeAllChats,
    ValueChanged<Club>? onOpenClub,
    ValueChanged<Club>? onEnterClubLounge,
    ClubService? clubService,
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
    onOpenConversation: (_) {},
    onSeeAllChats: onSeeAllChats ?? () {},
    onOpenServers: onOpenServers,
    onOpenClub: onOpenClub,
    onEnterClubLounge: onEnterClubLounge,
    roomService: RoomService(firestore: db, auth: auth),
    clubService: clubService ?? clubs(),
    friendService: FriendService(firestore: db, auth: auth),
    followService: _SilentFollow(firestore: db, auth: auth),
    profileService: ProfileService(firestore: db, auth: auth),
    feedService: _SilentFeed(firestore: db, auth: auth),
    messageService: MessageService(firestore: db, auth: auth),
    momentViewsService: _SilentViews(firestore: db, auth: auth),
    capabilityService: _NoCapabilities(),
  );

  DesktopHome desktopHome({
    VoidCallback? onOpenServers,
    VoidCallback? onOpenNotifications,
    VoidCallback? onOpenProfile,
  }) => DesktopHome(
    currentUserId: uid,
    unreadNotificationCount: 7,
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
    onOpenServers: onOpenServers,
    onOpenNotifications: onOpenNotifications,
    onOpenProfile: onOpenProfile,
    roomService: RoomService(firestore: db, auth: auth),
    clubService: clubs(),
    friendService: FriendService(firestore: db, auth: auth),
    followService: _SilentFollow(firestore: db, auth: auth),
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
    final page = tester.renderObject<RenderBox>(
      find.byType(Scaffold).first,
    );
    expect(page.size.width, lessThanOrEqualTo(width + 0.5));
  }

  group('the phone shell: 360 / 390 / 430 / 768 × 1.0 and 2.0 text', () {
    for (final width in [360.0, 390.0, 430.0, 768.0]) {
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
          // The page still says what it is for at 200 %.
          expect(find.byKey(const ValueKey('home-hero-join')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('home-record-moment')),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('home-places-rail')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('home-person-f1')),
            findsOneWidget,
            reason: 'a real friend with a long name and no avatar',
          );
        });
      }
    }

    testWidgets('the empty account at 360 × 2.0 text', (tester) async {
      const size = Size(360, 6000);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await db.collection('rooms').doc('r1').delete();

      await tester.pumpWidget(
        app(
          mobileHome(
            clubService: _Clubs(
              firestore: db,
              auth: auth,
              storage: MockFirebaseStorage(),
            ),
          ),
          size: size,
          textScale: 2,
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('home-conversation-invitation')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('home-places-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-quick-create-room')), findsOneWidget);
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
          expect(find.byKey(const ValueKey('home-hero-join')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('home-record-moment')),
            findsOneWidget,
          );
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
            onOpenDiscover: () => ring('discover'),
            onCreateMoment: () => ring('record'),
            onOpenNotifications: () => ring('notifications'),
            onOpenProfile: () => ring('profile'),
            onSeeAllChats: () => ring('chats'),
            onOpenClub: (_) => ring('club'),
            onEnterClubLounge: (_) => ring('lounge'),
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
      await tapKey('home-servers-see-all');
      await tapKey('home-places-create');
      await tapKey('home-record-moment');
      await tapKey('home-place-c1');

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
      expect(doors['servers'], 2, reason: '"Zobacz wszystkie" and "Stwórz serwer"');
      expect(doors['record'], 1);
      expect(doors['club'], 1, reason: 'a place tile opens the place');
      expect(doors['notifications'], 1);
      expect(doors['profile'], 1);
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

      final create = find.byKey(const ValueKey('home-places-create'));
      expect(create, findsOneWidget);
      await tester.ensureVisible(create);
      await tester.tap(create, warnIfMissed: false);
      await tester.pump();

      expect(doors['notifications'], 1);
      expect(doors['profile'], 1);
      expect(doors['servers'], 1);
      expect(tester.takeException(), isNull);
    });
  });
}
