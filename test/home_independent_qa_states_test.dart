import 'dart:io';

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
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';

/// INDEPENDENT QA — Home "Tu i teraz": denied vs empty vs error, per section.
///
/// Written from the build brief (§2.2 "Done means", §2.0 "Every new section
/// has loading / empty / error-with-retry / denied states; denied ≠ empty")
/// rather than from the implementation, and deliberately not reusing the
/// authors' fixtures: a permission denial is the one state the reader can do
/// nothing about, so it must never be drawn as "there is nothing here", and it
/// must never cost the reader a capability that the populated state offers.

/// A `permission-denied` exactly as Firestore raises it.
FirebaseException _denied(String path) => FirebaseException(
  plugin: 'cloud_firestore',
  code: 'permission-denied',
  message: 'Missing or insufficient permissions: $path',
);

class _DeniedRooms extends RoomService {
  _DeniedRooms({
    required super.firestore,
    required super.auth,
    this.denyLive = false,
    this.pendingLive = false,
    this.denyOwned = false,
    this.denyParticipants = false,
    this.lounge,
  });

  final bool pendingLive;
  final bool denyLive;
  final bool denyOwned;
  final bool denyParticipants;
  final VoiceRoom? lounge;

  @override
  Stream<List<VoiceRoom>> watchLivePublicRooms() {
    if (denyLive) return Stream<List<VoiceRoom>>.error(_denied('rooms'));
    if (pendingLive) return const Stream<List<VoiceRoom>>.empty();
    return super.watchLivePublicRooms();
  }

  @override
  Stream<List<VoiceRoom>> watchOwnedRooms() => denyOwned
      ? Stream<List<VoiceRoom>>.error(_denied('rooms'))
      : super.watchOwnedRooms();

  @override
  Stream<VoiceRoom?> watchClubLounge(String clubId) =>
      lounge == null ? super.watchClubLounge(clubId) : Stream.value(lounge);

  @override
  Stream<List<RoomParticipant>> watchParticipants(String roomId) =>
      denyParticipants
      ? Stream<List<RoomParticipant>>.error(
          _denied('rooms/$roomId/participants'),
        )
      : super.watchParticipants(roomId);
}

class _DeniedClubs extends ClubService {
  _DeniedClubs({
    required super.firestore,
    required super.auth,
    required super.storage,
    this.deny = false,
    this.clubs = const <Club>[],
    this.pending = false,
  });

  final bool deny;
  final bool pending;
  final List<Club> clubs;

  @override
  Stream<List<Club>> watchMyClubs() {
    if (deny) return Stream<List<Club>>.error(_denied('users/{uid}/clubs'));
    if (pending) return const Stream<List<Club>>.empty();
    return Stream<List<Club>>.value(clubs);
  }
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
      const Stream<List<VoiceMoment>>.empty();
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
      const Stream<Set<String>>.empty();
}

class _NoCapabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

Club _club(String id, {String name = 'Klub sąsiedzki', int members = 6}) =>
    Club(
      id: id,
      name: name,
      description: 'Opis',
      ownerId: 'owner-$id',
      ownerName: 'Owner',
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

  Future<void> seedLiveRoom({
    String id = 'r1',
    String name = 'Wieczorne rozmowy',
    bool live = true,
    String experience = 'community',
  }) async {
    await db.collection('rooms').doc(id).set({
      'hostId': 'host-$id',
      'hostName': 'Host',
      'name': name,
      'description': '',
      'category': 'community',
      'visibility': 'public',
      'language': 'Polish',
      'participantCount': 3,
      'memberCount': 0,
      'isLive': live,
      'roomType': experience == 'broadcast' ? 'broadcast' : 'community',
      'status': 'active',
      'experience': experience,
      'createdAt': Timestamp.now(),
    });
    await db
        .collection('rooms')
        .doc(id)
        .collection('participants')
        .doc('speaker-$id')
        .set({
          'userId': 'speaker-$id',
          'displayName': 'Ola',
          'role': 'host',
          'isMuted': false,
          'isSpeaker': true,
        });
  }

  Widget app(Widget child, {Locale locale = const Locale('pl')}) => MaterialApp(
    theme: AppTheme.darkTheme,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );

  MobileHome mobile({
    RoomService? rooms,
    ClubService? clubs,
    FriendService? friends,
    MessageService? messages,
    VoidCallback? onCreateRoom,
    ValueChanged<VoiceRoom>? onOpenRoom,
  }) => MobileHome(
    currentUserId: uid,
    onOpenRoom: onOpenRoom ?? (_) {},
    onOpenDiscover: () {},
    onOpenFriends: () {},
    onOpenNotifications: () {},
    onOpenProfile: () {},
    onCreateMoment: () {},
    onCreateRoom: onCreateRoom ?? () {},
    onOpenMoment: (_) {},
    onOpenComments: (_) {},
    onOpenConversation: (_) {},
    onSeeAllChats: () {},
    roomService: rooms ?? RoomService(firestore: db, auth: auth),
    clubService:
        clubs ??
        _DeniedClubs(firestore: db, auth: auth, storage: MockFirebaseStorage()),
    friendService: friends ?? FriendService(firestore: db, auth: auth),
    followService: _SilentFollow(firestore: db, auth: auth),
    profileService: ProfileService(firestore: db, auth: auth),
    feedService: _SilentFeed(firestore: db, auth: auth),
    messageService: messages ?? MessageService(firestore: db, auth: auth),
    momentViewsService: _SilentViews(firestore: db, auth: auth),
    capabilityService: _NoCapabilities(),
  );

  DesktopHome desktop({
    RoomService? rooms,
    ClubService? clubs,
    MessageService? messages,
  }) => DesktopHome(
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
    roomService: rooms ?? RoomService(firestore: db, auth: auth),
    clubService:
        clubs ??
        _DeniedClubs(firestore: db, auth: auth, storage: MockFirebaseStorage()),
    friendService: FriendService(firestore: db, auth: auth),
    followService: _SilentFollow(firestore: db, auth: auth),
    profileService: ProfileService(firestore: db, auth: auth),
    feedService: _SilentFeed(firestore: db, auth: auth),
    messageService: messages ?? MessageService(firestore: db, auth: auth),
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

  group('phone — a denial is never an empty state', () {
    testWidgets('live rooms denied: the error card, never the invitation', (
      tester,
    ) async {
      useWindow(tester, const Size(390, 2600));
      await tester.pumpWidget(
        app(
          mobile(
            rooms: _DeniedRooms(firestore: db, auth: auth, denyLive: true),
          ),
        ),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('home-rooms-error')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-conversation-invitation')),
        findsNothing,
        reason: 'a denial must not be dressed as "nobody is talking"',
      );
      expect(find.byKey(const ValueKey('home-featured-room')), findsNothing);
      expect(find.text('Spróbuj ponownie'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('live rooms denied: the create-room pill survives the denial', (
      tester,
    ) async {
      // Brief §2.2 item 4: "Quick actions row (always present:
      // home-quick-create-room = the mobile tour anchor, home-quick-friends)".
      // The desktop composition keeps them in every state for exactly this
      // reason ("a failed room read must not also cost the reader the way to
      // start a room of their own", desktop_home.dart), and the pre-redesign
      // phone Home rendered them whenever the room list was not empty.
      useWindow(tester, const Size(390, 2600));
      await tester.pumpWidget(
        app(
          mobile(
            rooms: _DeniedRooms(firestore: db, auth: auth, denyLive: true),
          ),
        ),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('home-rooms-error')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-quick-create-room')),
        findsOneWidget,
        reason:
            'the guided tour anchors its Create step on this pill and it is '
            'the only create-room affordance left on Home',
      );
      expect(find.byKey(const ValueKey('home-quick-friends')), findsOneWidget);

      // The same hole is open on the cold-start frame, which is exactly when
      // the guided tour spotlights the Create step. Home is torn down first:
      // `roomService` is a constructor-time dependency that production never
      // swaps, so re-pumping with a different fake would keep the first
      // subscription rather than open the pending one.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        app(
          mobile(
            rooms: _DeniedRooms(firestore: db, auth: auth, pendingLive: true),
          ),
        ),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('home-rooms-loading')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-quick-create-room')),
        findsOneWidget,
        reason: 'the tour anchor must exist while the room list is loading',
      );
    });

    testWidgets('desktop keeps the same actions under a denial', (
      tester,
    ) async {
      useWindow(tester, const Size(1440, 2400));
      await tester.pumpWidget(
        app(
          desktop(
            rooms: _DeniedRooms(firestore: db, auth: auth, denyLive: true),
          ),
        ),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('home-rooms-error')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-conversation-invitation')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('home-quick-create-room')),
        findsOneWidget,
      );
    });

    testWidgets('places denied: the places error, no empty card, no heading '
        'over nothing', (tester) async {
      useWindow(tester, const Size(390, 2600));
      await tester.pumpWidget(
        app(
          mobile(
            clubs: _DeniedClubs(
              firestore: db,
              auth: auth,
              storage: MockFirebaseStorage(),
              deny: true,
            ),
          ),
        ),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('home-places-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-places-empty')), findsNothing);
      expect(find.byKey(const ValueKey('home-places-rail')), findsNothing);
      expect(find.byKey(const ValueKey('home-places-loading')), findsNothing);
      expect(
        find.text('Twoje miejsca'),
        findsNothing,
        reason: 'a section title is a promise about content',
      );
    });

    testWidgets('places: loading, empty and denied are three different '
        'screens', (tester) async {
      useWindow(tester, const Size(390, 2600));

      await tester.pumpWidget(
        app(
          mobile(
            clubs: _DeniedClubs(
              firestore: db,
              auth: auth,
              storage: MockFirebaseStorage(),
              pending: true,
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('home-places-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-places-empty')), findsNothing);
      expect(find.byKey(const ValueKey('home-places-error')), findsNothing);

      await tester.pumpWidget(
        app(
          mobile(
            clubs: _DeniedClubs(
              firestore: db,
              auth: auth,
              storage: MockFirebaseStorage(),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('home-places-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-places-loading')), findsNothing);
      expect(find.byKey(const ValueKey('home-places-error')), findsNothing);
      expect(find.text('Nie masz jeszcze swoich miejsc.'), findsOneWidget);
    });

    testWidgets('friends denied: the people error, and never a silent rail', (
      tester,
    ) async {
      useWindow(tester, const Size(390, 2600));
      await tester.pumpWidget(
        app(
          mobile(
            friends: _DeniedFriends(firestore: db, auth: auth),
          ),
        ),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('home-people-error')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chats denied: the chats error, never the "find friends" '
        'empty state', (tester) async {
      useWindow(tester, const Size(390, 2600));
      await tester.pumpWidget(
        app(
          mobile(
            messages: _DeniedMessages(firestore: db, auth: auth),
          ),
        ),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('home-chats-error')), findsOneWidget);
    });

    testWidgets('owned rooms denied: the block is drawn with its error, never '
        'silently dropped', (tester) async {
      useWindow(tester, const Size(390, 2600));
      await tester.pumpWidget(
        app(
          mobile(
            rooms: _DeniedRooms(firestore: db, auth: auth, denyOwned: true),
          ),
        ),
      );
      await settle(tester);

      final owned = find.byKey(const ValueKey('home-owned-rooms'));
      expect(owned, findsOneWidget);
      expect(
        find.descendant(of: owned, matching: find.byType(HomeSectionError)),
        findsOneWidget,
      );
    });

    testWidgets('four simultaneous denials: four distinct sections, one '
        'polite announcement region', (tester) async {
      useWindow(tester, const Size(390, 3000));
      await tester.pumpWidget(
        app(
          mobile(
            rooms: _DeniedRooms(
              firestore: db,
              auth: auth,
              denyLive: true,
              denyOwned: true,
            ),
            clubs: _DeniedClubs(
              firestore: db,
              auth: auth,
              storage: MockFirebaseStorage(),
              deny: true,
            ),
            friends: _DeniedFriends(firestore: db, auth: auth),
            messages: _DeniedMessages(firestore: db, auth: auth),
          ),
        ),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('home-rooms-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-places-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-people-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-chats-error')), findsOneWidget);
      expect(
        find.byType(HomeErrorAnnouncementScope),
        findsOneWidget,
        reason: 'ADR-058: one polite region for the whole screen',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a roster denial never fakes faces and never becomes the '
        'rooms error', (tester) async {
      useWindow(tester, const Size(390, 2600));
      await seedLiveRoom();
      await tester.pumpWidget(
        app(
          mobile(
            rooms: _DeniedRooms(
              firestore: db,
              auth: auth,
              denyParticipants: true,
            ),
          ),
        ),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('home-featured-room')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-hero-join')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-rooms-error')), findsNothing);
      expect(
        find.byKey(const ValueKey('home-hero-roster-note')),
        findsOneWidget,
      );
      expect(
        find.text('Ola'),
        findsNothing,
        reason: 'no name may be printed from a roster the client never read',
      );
    });
  });

  group('phone — the join path is the only way in', () {
    testWidgets('the hero CTA hands the shell the real room and joins nothing '
        'itself', (tester) async {
      useWindow(tester, const Size(390, 2600));
      await seedLiveRoom(id: 'r-join', name: 'Salon');
      final opened = <VoiceRoom>[];
      await tester.pumpWidget(app(mobile(onOpenRoom: opened.add)));
      await settle(tester);

      final cta = find.byKey(const ValueKey('home-hero-join'));
      expect(cta, findsOneWidget);
      await tester.tap(cta);
      await tester.pump();

      expect(opened, hasLength(1));
      expect(opened.single.id, 'r-join');
      // Nothing was written anywhere by looking at, or tapping, the hero.
      final participants = await db
          .collection('rooms')
          .doc('r-join')
          .collection('participants')
          .get();
      expect(participants.docs.map((d) => d.id), ['speaker-r-join']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a broadcast room keeps its own product wording', (
      tester,
    ) async {
      useWindow(tester, const Size(390, 2600));
      await seedLiveRoom(
        id: 'b1',
        name: 'Transmisja wieczorna',
        experience: 'broadcast',
      );
      await tester.pumpWidget(app(mobile()));
      await settle(tester);

      expect(find.text('Dołącz do transmisji'), findsOneWidget);
      expect(find.text('Dołącz do rozmowy'), findsNothing);
    });

    test('Home imports no audio, LiveKit or microphone permission code', () {
      // The cheapest possible proof that opening Home cannot start audio: the
      // screen has no way to reach the services that could.
      final home = Directory('lib/features/home/presentation/widgets');
      final offenders = <String>[];
      for (final entity in home.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final line in source.split('\n')) {
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
      expect(
        offenders,
        isEmpty,
        reason:
            'RoomEntryScreen is the single consent boundary; no Home '
            'composition may import the audio or microphone layer at all',
      );

      // The shell itself does touch PermissionReadinessService — for the
      // pre-existing first-run permission SHEET offered after the guided
      // tour (present since before this redesign). Pin that this is still
      // its only use, so a future "warm up the mic on Home" cannot slip in.
      final shell = File(
        'lib/features/home/presentation/screens/main_shell.dart',
      ).readAsStringSync();
      expect(shell.contains('showPermissionSetupSheet'), isTrue);
      expect(
        RegExp(r'_permissionReadiness').allMatches(shell).length,
        5,
        reason:
            'declaration, assignment and the three onboarding-sheet uses — '
            'no new caller',
      );
    });

    test('Home reaches no KIND of listener it did not reach before the '
        'redesign', () {
      // The counts are pinned by home_independent_qa_lifecycle_test; this
      // pins the SET. Everything here existed on Home before "Tu i teraz"
      // (watchMyClubs/watchClubLounge came from the "From your clubs" block,
      // watchParticipants from the featured banner's face pile), so a new
      // entry in this list is a new subscription on the app's first screen
      // and has to be argued for, not slipped in.
      const allowed = <String>{
        'watchClub', // owner overflow menu only, and only for a club room
        'watchClubLounge',
        'watchConversations',
        'watchCurrentProfile',
        'watchFollowing',
        'watchFriends',
        'watchLivePublicRooms',
        'watchMyClubs',
        'watchOwnedRooms',
        'watchParticipants',
        'watchProfile',
        'watchSocialMoments',
        'watchViewedMomentIds',
      };
      final found = <String>{};
      final pattern = RegExp(r'\.(watch[A-Za-z]+)\(');
      for (final entity in Directory(
        'lib/features/home/presentation/widgets',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        for (final match in pattern.allMatches(entity.readAsStringSync())) {
          found.add(match.group(1)!);
        }
      }
      expect(found.difference(allowed), isEmpty, reason: 'new listener kind');
    });
  });

  group('the new lounge door checks access before it opens', () {
    // "Zajrzyj" is the one entry point this redesign ADDS to a room, and the
    // shell reaches it through RoomService.prepareClubLounge. MainShell is
    // not pumpable (it builds FirebaseAuth/RoomService in initState), so the
    // access check is proven at the service the shell calls.
    test('a non-member is refused, and nothing is written', () async {
      await db.collection('clubs').doc('c1').set({
        'name': 'Klub sąsiedzki',
        'ownerId': 'owner-c1',
      });
      final rooms = RoomService(firestore: db, auth: auth);

      await expectLater(
        rooms.prepareClubLounge(
          clubId: 'c1',
          clubName: 'Klub sąsiedzki',
          clubDescription: '',
          language: 'Polish',
          ownerId: 'owner-c1',
          ownerName: 'Owner',
        ),
        throwsA(isA<StateError>()),
      );
      final lounge = await db.collection('rooms').doc('club_lounge_c1').get();
      expect(
        lounge.exists,
        isFalse,
        reason: 'a refused member creates no room, live or otherwise',
      );
    });

    test(
      'a member gets the room and no roster row is written for them',
      () async {
        await db.collection('clubs').doc('c2').set({
          'name': 'Rodzinny salon',
          'ownerId': 'owner-c2',
        });
        await db
            .collection('clubs')
            .doc('c2')
            .collection('members')
            .doc(uid)
            .set({'userId': uid, 'role': 'member'});
        final rooms = RoomService(firestore: db, auth: auth);

        final room = await rooms.prepareClubLounge(
          clubId: 'c2',
          clubName: 'Rodzinny salon',
          clubDescription: '',
          language: 'Polish',
          ownerId: 'owner-c2',
          ownerName: 'Owner',
        );
        expect(room.id, 'club_lounge_c2');
        final participants = await db
            .collection('rooms')
            .doc('club_lounge_c2')
            .collection('participants')
            .get();
        expect(
          participants.docs,
          isEmpty,
          reason:
              'looking is not joining: the roster row belongs to '
              'RoomEntryScreen, after consent',
        );
      },
    );
  });

  group('partial and hostile data', () {
    testWidgets('a very long Polish name, no avatar, no cover and a club with '
        'no lounge render without an exception', (tester) async {
      useWindow(tester, const Size(360, 3000));
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'displayName': 'Bartłomiej-Krzysztof Wojciechowski',
        'email': 'me@yovoice.app',
      });
      await seedLiveRoom(
        id: 'long',
        name: 'Podcasty nam bliskie i dalekie — salon po godzinach',
      );
      await tester.pumpWidget(
        app(
          mobile(
            clubs: _DeniedClubs(
              firestore: db,
              auth: auth,
              storage: MockFirebaseStorage(),
              clubs: [
                _club('c1', name: 'Podcasty nam bliskie i dalekie'),
                _club('c2', name: 'Ł', members: 0),
              ],
            ),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      // The greeting is the FIRST token of the display name, never the email
      // local part.
      expect(find.textContaining('Bartłomiej-Krzysztof'), findsOneWidget);
      expect(find.textContaining('me@yovoice.app'), findsNothing);
      expect(find.byKey(const ValueKey('home-places-rail')), findsOneWidget);
    });

    testWidgets('a place whose member counter was never written says nothing '
        'about its size — on the phone too', (tester) async {
      // The desktop list already refuses to print "0 osób" about a place the
      // reader is a member of (home_places_card.dart: "a count only where a
      // count actually exists"). The phone rail speaks the same fact to a
      // screen reader and must not turn it into a false claim.
      useWindow(tester, const Size(390, 2600));
      await tester.pumpWidget(
        app(
          mobile(
            clubs: _DeniedClubs(
              firestore: db,
              auth: auth,
              storage: MockFirebaseStorage(),
              clubs: [_club('c0', name: 'Klub bez licznika', members: 0)],
            ),
          ),
        ),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('home-place-c0')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('0 osób')),
        findsNothing,
        reason:
            'a place the reader belongs to never has zero people in it; '
            'silence is the honest reading',
      );
    });

    testWidgets('a club whose lounge is live but whose roster is denied still '
        'offers the door', (tester) async {
      useWindow(tester, const Size(390, 2600));
      final lounge = VoiceRoom(
        id: 'club_lounge_c1',
        hostId: 'owner-c1',
        hostName: 'Owner',
        hostPhotoUrl: null,
        name: 'Klub sąsiedzki Lounge',
        description: '',
        category: 'club',
        visibility: 'private',
        language: 'Polish',
        maxParticipants: null,
        participantCount: 2,
        memberCount: 6,
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
      await tester.pumpWidget(
        app(
          mobile(
            rooms: _DeniedRooms(
              firestore: db,
              auth: auth,
              denyParticipants: true,
              lounge: lounge,
            ),
            clubs: _DeniedClubs(
              firestore: db,
              auth: auth,
              storage: MockFirebaseStorage(),
              clubs: [_club('c1')],
            ),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Lounge'),
        findsNothing,
        reason: 'the stored English lounge name is never printed on Home',
      );
      expect(
        find.byKey(const ValueKey('home-club-activity-c1')),
        findsOneWidget,
      );
    });
  });
}
