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
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_moments_strip.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/followed_creators_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/premium_desktop_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/sponsored_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/timezone_world_map_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/voice_trending_card.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_friend_tile.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_greeting_header.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_here_now_hero.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_places_card.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_places_section.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_record_moment_card.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_header.dart';
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

/// WIDE Home — the same state and widgets as the phone, a deliberately
/// different composition.
///
/// What this file pins: the column split and its widths at every supported
/// desktop size, the anatomy switches that keep a 1280 main column from
/// pretending to be a 1440 one, the absence of a horizontal overflow at 1.0
/// and 2.0 text, and the fact that a layout flip rearranges the page without
/// re-subscribing to a single stream.
///
/// It also pins the negative space: none of the five cards Home used to host
/// on the desktop appears here any more, because each one moved to the
/// destination that owns it.
class _Rooms extends RoomService {
  _Rooms({
    required super.firestore,
    required super.auth,
    this.live = const [],
    this.owned = const [],
    this.lounges = const {},
    this.rosters = const {},
  });

  final List<VoiceRoom> live;
  final List<VoiceRoom> owned;
  final Map<String, VoiceRoom> lounges;
  final Map<String, List<RoomParticipant>> rosters;

  int liveCalls = 0;
  int ownedCalls = 0;
  int loungeCalls = 0;
  int participantCalls = 0;

  @override
  Stream<List<VoiceRoom>> watchLivePublicRooms() {
    liveCalls++;
    return Stream<List<VoiceRoom>>.multi(
      (controller) => controller.add(live),
      isBroadcast: true,
    );
  }

  @override
  Stream<List<VoiceRoom>> watchOwnedRooms() {
    ownedCalls++;
    return Stream<List<VoiceRoom>>.multi(
      (controller) => controller.add(owned),
      isBroadcast: true,
    );
  }

  @override
  Stream<VoiceRoom?> watchClubLounge(String clubId) {
    loungeCalls++;
    return Stream<VoiceRoom?>.multi(
      (controller) => controller.add(lounges[clubId]),
      isBroadcast: true,
    );
  }

  @override
  Stream<List<RoomParticipant>> watchParticipants(String roomId) {
    participantCalls++;
    return Stream<List<RoomParticipant>>.multi(
      (controller) => controller.add(rosters[roomId] ?? const []),
      isBroadcast: true,
    );
  }
}

class _Friends extends FriendService {
  _Friends({
    required super.firestore,
    required super.auth,
    this.friends = const [],
  });
  final List<FriendUser> friends;
  int calls = 0;
  @override
  Stream<List<FriendUser>> watchFriends() {
    calls++;
    return Stream<List<FriendUser>>.multi(
      (controller) => controller.add(friends),
      isBroadcast: true,
    );
  }
}

class _Follow extends FollowService {
  _Follow({required super.firestore, required super.auth});
  int calls = 0;
  @override
  Stream<List<FollowUser>> watchFollowing(String userId) {
    calls++;
    return Stream<List<FollowUser>>.multi(
      (controller) => controller.add(const <FollowUser>[]),
      isBroadcast: true,
    );
  }
}

class _Messages extends MessageService {
  _Messages({required super.firestore, required super.auth});
  int calls = 0;
  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) {
    calls++;
    return Stream<List<Conversation>>.multi(
      (controller) => controller.add(const <Conversation>[]),
      isBroadcast: true,
    );
  }
}

class _Feed extends HomeFeedService {
  _Feed({required super.firestore, required super.auth});
  int calls = 0;
  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) {
    calls++;
    return Stream<List<VoiceMoment>>.multi(
      (controller) => controller.add(const <VoiceMoment>[]),
      isBroadcast: true,
    );
  }
}

class _Views extends MomentViewsService {
  _Views({required super.firestore, required super.auth});
  @override
  Stream<Set<String>> watchViewedMomentIds() =>
      Stream<Set<String>>.multi(
        (controller) => controller.add(const <String>{}),
        isBroadcast: true,
      );
}

class _Clubs extends ClubService {
  _Clubs({
    required super.firestore,
    required super.auth,
    required super.storage,
    this.clubs = const [],
  });
  final List<Club> clubs;
  int calls = 0;
  @override
  Stream<List<Club>> watchMyClubs() {
    calls++;
    return Stream<List<Club>>.multi(
      (controller) => controller.add(clubs),
      isBroadcast: true,
    );
  }
}

class _Capabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

void main() {
  const uid = 'wide-me';
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;

  Club club(String id, {String? name, int members = 12}) => Club(
    id: id,
    name: name ?? 'Miejsce $id',
    description: '',
    ownerId: 'owner',
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

  VoiceRoom lounge(String clubId) => VoiceRoom(
    id: 'club_lounge_$clubId',
    hostId: 'owner',
    hostName: 'Owner',
    hostPhotoUrl: null,
    name: '$clubId Lounge',
    description: '',
    category: 'club',
    visibility: 'private',
    language: 'Polish',
    maxParticipants: null,
    participantCount: 3,
    memberCount: 0,
    isLive: true,
    roomType: RoomType.community,
    status: RoomStatus.active,
    imageUrl: null,
    approvalRequired: false,
    slowModeSeconds: 0,
    autoMuteNewUsers: false,
    membersCanStartVoice: true,
    createdAt: null,
    updatedAt: null,
    experience: 'community',
    clubId: clubId,
    storedClubId: clubId,
  );

  RoomParticipant person(String id, String name, {bool speaker = true}) =>
      RoomParticipant(
        userId: id,
        displayName: name,
        photoUrl: null,
        role: speaker ? 'host' : 'listener',
        isMuted: false,
        isSpeaker: speaker,
        isHandRaised: false,
        joinedAt: null,
      );

  FriendUser friend(String id, String name) => FriendUser(
    id: id,
    displayName: name,
    email: '$id@yovoice.app',
    photoUrl: null,
    isOnline: true,
    lastSeen: null,
    availability: 'available',
  );

  setUp(() async {
    ProfileService.resetCurrentProfileCache();
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid));
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'Kamil Jaguszewski',
      'email': 'me@yovoice.app',
    });
  });
  tearDown(ProfileService.resetCurrentProfileCache);

  Widget app(Widget child, {double scale = 1}) => MaterialApp(
    locale: const Locale('pl'),
    theme: AppTheme.darkTheme,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: child,
      ),
    ),
  );

  /// The desktop shell reserves 264 px for the rail (528 at >= 2x text), so
  /// the slot Home is handed is the viewport minus the rail — the number the
  /// column rule is actually about.
  double slotFor(double viewport, {double scale = 1}) =>
      viewport - (scale >= 1.6 ? 528 : 264);

  DesktopHome buildHome({
    required _Rooms rooms,
    _Clubs? clubs,
    _Friends? friends,
    _Follow? follow,
    _Messages? messages,
    _Feed? feed,
    VoidCallback? onOpenNotifications,
    VoidCallback? onOpenProfile,
    VoidCallback? onOpenServers,
    ValueChanged<Club>? onOpenClub,
    ValueChanged<Club>? onEnterClubLounge,
    int unread = 0,
  }) => DesktopHome(
    key: const ValueKey('wide-home'),
    currentUserId: uid,
    unreadNotificationCount: unread,
    onOpenRoom: (_) {},
    onSeeAllRooms: () {},
    onViewAllFriends: () {},
    onStartRoom: () {},
    onOpenMoment: (_) {},
    onCreateMoment: () {},
    onSeeAllMoments: () {},
    onOpenConversation: (_) {},
    onOpenClub: onOpenClub ?? (_) {},
    onSeeAllChats: () {},
    onOpenClubs: () {},
    onOpenNotifications: onOpenNotifications,
    onOpenProfile: onOpenProfile,
    onOpenServers: onOpenServers,
    onEnterClubLounge: onEnterClubLounge,
    roomService: rooms,
    clubService:
        clubs ??
        _Clubs(firestore: db, auth: auth, storage: MockFirebaseStorage()),
    friendService: friends ?? _Friends(firestore: db, auth: auth),
    followService: follow ?? _Follow(firestore: db, auth: auth),
    profileService: ProfileService(firestore: db, auth: auth),
    feedService: feed ?? _Feed(firestore: db, auth: auth),
    messageService: messages ?? _Messages(firestore: db, auth: auth),
    momentViewsService: _Views(firestore: db, auth: auth),
    capabilityService: _Capabilities(),
  );

  Future<void> pumpAt(
    WidgetTester tester,
    Widget home, {
    required double viewport,
    double scale = 1,
    double height = 2400,
  }) async {
    tester.view.physicalSize = Size(slotFor(viewport, scale: scale), height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(home, scale: scale));
    // Clubs → lounges → candidates → rosters: each hop is one frame, and
    // the roster is what the hero's faces and summary are made of.
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump();
    }
  }

  double widthOf(WidgetTester tester, Key key) =>
      tester.getSize(find.byKey(key)).width;

  group('the two-column region', () {
    for (final (viewport, mainWidth) in <(double, double)>[
      (1280, 628),
      (1440, 788),
    ]) {
      testWidgets(
        'at ${viewport.toInt()} the main column is '
        '${mainWidth.toInt()} beside a 300 px context column',
        (tester) async {
          final rooms = _Rooms(
            firestore: db,
            auth: auth,
            lounges: {'c1': lounge('c1')},
            rosters: {
              'club_lounge_c1': [person('p1', 'Maja')],
            },
          );
          await pumpAt(
            tester,
            buildHome(
              rooms: rooms,
              clubs: _Clubs(
                firestore: db,
                auth: auth,
                storage: MockFirebaseStorage(),
                clubs: [club('c1')],
              ),
            ),
            viewport: viewport,
          );

          expect(find.byKey(const ValueKey('home-main-column')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('home-secondary-column')),
            findsOneWidget,
          );
          expect(
            widthOf(tester, const ValueKey('home-secondary-column')),
            300,
          );
          expect(widthOf(tester, const ValueKey('home-main-column')), mainWidth);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('at 1100 the context column folds into one flow, and the '
        'same modules are all still on the page', (tester) async {
      final rooms = _Rooms(firestore: db, auth: auth);
      await pumpAt(
        tester,
        buildHome(
          rooms: rooms,
          clubs: _Clubs(
            firestore: db,
            auth: auth,
            storage: MockFirebaseStorage(),
            clubs: [club('c1')],
          ),
        ),
        viewport: 1100,
      );

      expect(find.byKey(const ValueKey('home-secondary-column')), findsNothing);
      expect(find.byKey(const ValueKey('home-main-column')), findsNothing);
      // Nothing is lost: places become the phone's tile rail, and the
      // record card and the chats keep their place in the single flow.
      expect(find.byType(HomePlacesRail), findsOneWidget);
      expect(find.byType(HomePlacesCard), findsNothing);
      expect(find.byType(HomeRecordMomentCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 200 % text a 1440 viewport is one column, because the '
        'rail has taken half of it', (tester) async {
      final rooms = _Rooms(firestore: db, auth: auth);
      await pumpAt(
        tester,
        buildHome(rooms: rooms),
        viewport: 1440,
        scale: 2,
        height: 6000,
      );
      expect(find.byKey(const ValueKey('home-secondary-column')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('no horizontal overflow', () {
    for (final viewport in <double>[1100, 1280, 1440, 1920]) {
      for (final scale in <double>[1, 2]) {
        testWidgets(
          'desktop ${viewport.toInt()} at ${scale.toStringAsFixed(1)}x',
          (tester) async {
            final rooms = _Rooms(
              firestore: db,
              auth: auth,
              lounges: {'c1': lounge('c1'), 'c2': lounge('c2')},
              rosters: {
                'club_lounge_c1': [
                  person('p1', 'Maja'),
                  person('p2', 'Ola'),
                  person('p3', 'Bartek', speaker: false),
                ],
                'club_lounge_c2': [person('p4', 'Ania')],
              },
            );
            await pumpAt(
              tester,
              buildHome(
                rooms: rooms,
                clubs: _Clubs(
                  firestore: db,
                  auth: auth,
                  storage: MockFirebaseStorage(),
                  clubs: [
                    club(
                      'c1',
                      name: 'Podcasty nam bliskie i dalekie',
                      members: 284,
                    ),
                    club('c2', name: 'Nasz dom'),
                  ],
                ),
                friends: _Friends(
                  firestore: db,
                  auth: auth,
                  friends: [
                    friend('f1', 'Bartłomiej-Krzysztof Wojciechowski'),
                    friend('f2', 'Ola'),
                    friend('f3', 'Maja'),
                    friend('f4', 'Ania'),
                    friend('f5', 'Bartek'),
                  ],
                ),
              ),
              viewport: viewport,
              scale: scale,
              height: scale >= 2 ? 9000 : 3600,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('the phone shell at 768 keeps the same modules without an '
        'overflow, and the hero is horizontal there too', (tester) async {
      tester.view.physicalSize = const Size(768, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(
          MobileHome(
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
            roomService: _Rooms(
              firestore: db,
              auth: auth,
              lounges: {'c1': lounge('c1')},
              rosters: {
                'club_lounge_c1': [
                  person('p1', 'Maja'),
                  person('p2', 'Ola'),
                  person('p3', 'Bartek'),
                ],
              },
            ),
            clubService: _Clubs(
              firestore: db,
              auth: auth,
              storage: MockFirebaseStorage(),
              clubs: [club('c1', name: 'Podcasty nam bliskie i dalekie')],
            ),
            friendService: _Friends(firestore: db, auth: auth),
            followService: _Follow(firestore: db, auth: auth),
            profileService: ProfileService(firestore: db, auth: auth),
            feedService: _Feed(firestore: db, auth: auth),
            messageService: _Messages(firestore: db, auth: auth),
            momentViewsService: _Views(firestore: db, auth: auth),
            capabilityService: _Capabilities(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final hero = tester.widget<HomeHereNowHero>(
        find.byType(HomeHereNowHero),
      );
      // 768 is the phone shell (the dock, not the rail) — so the hero uses
      // the wide COMPOSITION but keeps the phone type ramp.
      expect(hero.compact, isFalse);
      expect(hero.expanded, isFalse);
      expect(find.byType(HomePlacesRail), findsOneWidget);
      expect(find.byType(HomeRecordMomentCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the hero and the server rows change anatomy, not content', () {
    testWidgets('the desktop hero takes the desktop ramp; the card is one '
        'stage with copy left and portraits right', (tester) async {
      final rooms = _Rooms(
        firestore: db,
        auth: auth,
        lounges: {'c1': lounge('c1')},
        rosters: {
          'club_lounge_c1': [
            person('p1', 'Maja'),
            person('p2', 'Ola'),
            person('p3', 'Bartek'),
          ],
        },
      );
      await pumpAt(
        tester,
        buildHome(
          rooms: rooms,
          clubs: _Clubs(
            firestore: db,
            auth: auth,
            storage: MockFirebaseStorage(),
            clubs: [club('c1', name: 'Po godzinach')],
          ),
        ),
        viewport: 1440,
      );
      final hero = tester.widget<HomeHereNowHero>(find.byType(HomeHereNowHero));
      expect(hero.expanded, isTrue);
      expect(hero.compact, isFalse);
      // The CTA and the portrait cluster are the two controls on the card,
      // and the CTA sits to the LEFT of the portraits.
      final cta = tester.getRect(find.byKey(const ValueKey('home-hero-join')));
      final cluster = tester.getRect(
        find.byKey(const ValueKey('home-hero-cluster')),
      );
      expect(cta.right, lessThanOrEqualTo(cluster.left));
      expect(cta.height, greaterThanOrEqualTo(52));
      expect(cta.width, greaterThanOrEqualTo(200));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 788 px main column gets the one-line server row; a 628 px '
        'one keeps the stacked anatomy — same facts either way', (
      tester,
    ) async {
      Future<Rect> rowRect(double viewport) async {
        final rooms = _Rooms(
          firestore: db,
          auth: auth,
          lounges: {'c1': lounge('c1')},
          rosters: {
            'club_lounge_c1': [person('p1', 'Maja')],
          },
        );
        await pumpAt(
          tester,
          buildHome(
            rooms: rooms,
            clubs: _Clubs(
              firestore: db,
              auth: auth,
              storage: MockFirebaseStorage(),
              clubs: [club('c1', name: 'Nasz dom')],
            ),
          ),
          viewport: viewport,
        );
        expect(find.byType(HomeServerActivityCard), findsOneWidget);
        // The pill, the name and the activity are on the page at both
        // widths: only the shape changes.
        expect(find.text('Zajrzyj'), findsOneWidget);
        expect(find.text('Nasz dom'), findsWidgets);
        return tester.getRect(find.byType(HomeServerActivityCard));
      }

      final wide = await rowRect(1440);
      final narrow = await rowRect(1280);
      expect(wide.width, 788);
      expect(narrow.width, 628);
      // One line is shorter than two.
      expect(wide.height, lessThan(narrow.height));
      expect(tester.takeException(), isNull);
    });
  });

  group('the hero is about the reader\'s own world', () {
    testWidgets('a live place beats an owned room, which beats the public '
        'board — the same rule the phone uses', (tester) async {
      VoiceRoom public(String id) => VoiceRoom(
        id: id,
        hostId: 'someone',
        hostName: 'Ktoś',
        hostPhotoUrl: null,
        name: 'Otwarta rozmowa',
        description: '',
        category: 'talk',
        visibility: 'public',
        language: 'Polish',
        maxParticipants: null,
        participantCount: 40,
        memberCount: 0,
        isLive: true,
        roomType: RoomType.community,
        status: RoomStatus.active,
        imageUrl: null,
        approvalRequired: false,
        slowModeSeconds: 0,
        autoMuteNewUsers: false,
        membersCanStartVoice: true,
        createdAt: null,
        updatedAt: null,
        experience: 'community',
      );
      VoiceRoom mine(String id) => VoiceRoom(
        id: id,
        hostId: uid,
        hostName: 'Kamil',
        hostPhotoUrl: null,
        name: 'Mój pokój',
        description: '',
        category: 'talk',
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
        autoMuteNewUsers: false,
        membersCanStartVoice: true,
        createdAt: null,
        updatedAt: null,
        experience: 'community',
      );

      await pumpAt(
        tester,
        buildHome(
          rooms: _Rooms(
            firestore: db,
            auth: auth,
            live: [public('public-1')],
            owned: [mine('mine-1')],
            lounges: {'c1': lounge('c1')},
            rosters: {
              'club_lounge_c1': [person('p1', 'Maja')],
            },
          ),
          clubs: _Clubs(
            firestore: db,
            auth: auth,
            storage: MockFirebaseStorage(),
            clubs: [club('c1', name: 'Po godzinach')],
          ),
        ),
        viewport: 1440,
        height: 3600,
      );

      final hero = tester.widget<HomeHereNowHero>(find.byType(HomeHereNowHero));
      expect(hero.candidate.tier, HomeHereNowTier.place);
      expect(hero.candidate.room.id, 'club_lounge_c1');
      // The owned room is still reachable from its own section.
      expect(find.text('Twoje aktywne pokoje'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the context column', () {
    testWidgets('lists at most six places, then offers the way to the rest', (
      tester,
    ) async {
      var servers = 0;
      await pumpAt(
        tester,
        buildHome(
          rooms: _Rooms(firestore: db, auth: auth),
          clubs: _Clubs(
            firestore: db,
            auth: auth,
            storage: MockFirebaseStorage(),
            clubs: [for (var i = 0; i < 9; i++) club('c$i')],
          ),
          onOpenServers: () => servers++,
        ),
        viewport: 1440,
        height: 3200,
      );

      expect(find.byType(HomePlaceRow), findsNWidgets(6));
      expect(find.byKey(const ValueKey('home-places-see-all')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('home-places-see-all')));
      await tester.pump();
      expect(servers, 1);

      await tester.tap(find.byKey(const ValueKey('home-places-create')));
      await tester.pump();
      expect(servers, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a place prints a member count only where a real one exists', (
      tester,
    ) async {
      await pumpAt(
        tester,
        buildHome(
          rooms: _Rooms(firestore: db, auth: auth),
          clubs: _Clubs(
            firestore: db,
            auth: auth,
            storage: MockFirebaseStorage(),
            clubs: [
              club('counted', name: 'Po godzinach', members: 284),
              club('uncounted', name: 'Nasza firma', members: 0),
            ],
          ),
        ),
        viewport: 1440,
      );

      expect(find.text('284 osoby'), findsOneWidget);
      // Never "0 osób": a place with an unwritten counter has at least the
      // reader in it, so the honest thing is to print no number at all.
      expect(find.text('0 osób'), findsNothing);
      expect(find.text('Nasza firma'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a place row opens the place, and no membership counter is '
        'ever phrased as activity', (tester) async {
      Club? opened;
      await pumpAt(
        tester,
        buildHome(
          rooms: _Rooms(firestore: db, auth: auth),
          clubs: _Clubs(
            firestore: db,
            auth: auth,
            storage: MockFirebaseStorage(),
            clubs: [club('c1', name: 'Nasz dom', members: 12)],
          ),
          onOpenClub: (club) => opened = club,
        ),
        viewport: 1440,
      );
      await tester.tap(find.byKey(const ValueKey('home-place-c1')));
      await tester.pump();
      expect(opened?.id, 'c1');
      expect(find.textContaining('online'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('one heading per promise', () {
    testWidgets('the single-column places section prints "Twoje miejsca" '
        'exactly once — the rail owns its own heading', (tester) async {
      await pumpAt(
        tester,
        buildHome(
          rooms: _Rooms(firestore: db, auth: auth),
          clubs: _Clubs(
            firestore: db,
            auth: auth,
            storage: MockFirebaseStorage(),
            clubs: [club('c1'), club('c2')],
          ),
        ),
        viewport: 1100,
      );
      expect(find.text('Twoje miejsca'), findsOneWidget);
      expect(find.byType(HomePlacesRail), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the 300 px context column takes the compact type ramp while '
        'the main column keeps the desktop one', (tester) async {
      await pumpAt(
        tester,
        buildHome(rooms: _Rooms(firestore: db, auth: auth)),
        viewport: 1440,
      );

      HomeSectionHeaderScale scaleOf(String title) => tester
          .widget<HomeSectionHeader>(
            find.ancestor(
              of: find.text(title),
              matching: find.byType(HomeSectionHeader),
            ),
          )
          .scale;

      // A 19 px heading with a "Zobacz wszystkie" beside it wraps in a
      // 300 px column, and its neighbours there are cards with 16 px
      // titles — so the column reads on its own ramp.
      expect(scaleOf('Ostatnie czaty'), HomeSectionHeaderScale.compact);
      // The main column is the desktop ramp, unchanged.
      expect(scaleOf('Tu i teraz'), HomeSectionHeaderScale.expanded);
      expect(scaleOf('Twoi znajomi'), HomeSectionHeaderScale.expanded);

      // And in one column there is no narrow neighbour to match, so the
      // chats heading joins the desktop ramp with everything else.
      await pumpAt(
        tester,
        buildHome(rooms: _Rooms(firestore: db, auth: auth)),
        viewport: 1100,
      );
      expect(scaleOf('Ostatnie czaty'), HomeSectionHeaderScale.expanded);
      expect(tester.takeException(), isNull);
    });

    testWidgets('768 is the PHONE shell, so the dock — not the rail — '
        'carries navigation there', (tester) async {
      expect(MainShell.usesDesktopLayout(const Size(768, 1024)), isFalse);
      expect(MainShell.usesDesktopLayout(const Size(1100, 800)), isTrue);
      // A short window is the phone shell whatever its width.
      expect(MainShell.usesDesktopLayout(const Size(1100, 600)), isFalse);
    });
  });

  group('the greeting card', () {
    testWidgets('the bell and the avatar call the shell, once each, and the '
        'real unread count is on the bell', (tester) async {
      var notifications = 0;
      var profile = 0;
      await pumpAt(
        tester,
        buildHome(
          rooms: _Rooms(firestore: db, auth: auth),
          onOpenNotifications: () => notifications++,
          onOpenProfile: () => profile++,
          unread: 7,
        ),
        viewport: 1440,
      );

      expect(find.byKey(const ValueKey('home-greeting-card')), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      // The greeting is the account's FIRST name, never the email local part.
      expect(find.textContaining('Cześć, Kamil'), findsOneWidget);
      expect(find.textContaining('me@yovoice.app'), findsNothing);

      await tester.tap(find.byType(HomeHeaderDisc));
      await tester.pump();
      expect(notifications, 1);

      await tester.tap(find.bySemanticsLabel('Otwórz swój profil'));
      await tester.pump();
      expect(profile, 1);
      // One door each: the bell did not also open the profile.
      expect(notifications, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('the friends row', () {
    testWidgets('all five friends, the own tile and the add tile are on one '
        'full-width row at 1280 and 1440', (tester) async {
      for (final viewport in <double>[1280, 1440]) {
        await pumpAt(
          tester,
          buildHome(
            rooms: _Rooms(firestore: db, auth: auth),
            friends: _Friends(
              firestore: db,
              auth: auth,
              friends: [
                friend('f1', 'Maja'),
                friend('f2', 'Ola'),
                friend('f3', 'Bartek'),
                friend('f4', 'Ania'),
                friend('f5', 'Kuba'),
              ],
            ),
          ),
          viewport: viewport,
        );
        // Five friends plus the own tile: it is a `HomeFriendTile` too, so
        // the ring on this rail means CONTENT for every disc on it.
        expect(find.byType(HomeFriendTile), findsNWidgets(6));
        expect(find.byKey(const ValueKey('home-people-me')), findsOneWidget);
        expect(find.byKey(const ValueKey('home-people-add')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('what Home no longer hosts', () {
    testWidgets('none of the relocated desktop cards is mounted', (
      tester,
    ) async {
      await pumpAt(
        tester,
        buildHome(rooms: _Rooms(firestore: db, auth: auth)),
        viewport: 1440,
      );
      expect(find.byType(PremiumDesktopCard), findsNothing);
      expect(find.byType(SponsoredCard), findsNothing);
      expect(find.byType(FollowedCreatorsCard), findsNothing);
      expect(find.byType(VoiceTrendingCard), findsNothing);
      expect(find.byType(TimezoneWorldMapCard), findsNothing);
      // The followed-Moments rail moved to the Momenty destination; the
      // record affordance it carried survives as the "Masz chwilę?" card.
      expect(find.byType(DesktopMomentsStrip), findsNothing);
      expect(find.byType(HomeRecordMomentCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('a layout flip rearranges, it does not re-subscribe', () {
    testWidgets('1440 → 1100 → 1440 opens every stream exactly once', (
      tester,
    ) async {
      final rooms = _Rooms(
        firestore: db,
        auth: auth,
        lounges: {'c1': lounge('c1')},
        rosters: {
          'club_lounge_c1': [person('p1', 'Maja')],
        },
      );
      final clubs = _Clubs(
        firestore: db,
        auth: auth,
        storage: MockFirebaseStorage(),
        clubs: [club('c1')],
      );
      final friends = _Friends(firestore: db, auth: auth);
      final follow = _Follow(firestore: db, auth: auth);
      final messages = _Messages(firestore: db, auth: auth);
      final feed = _Feed(firestore: db, auth: auth);

      final home = buildHome(
        rooms: rooms,
        clubs: clubs,
        friends: friends,
        follow: follow,
        messages: messages,
        feed: feed,
      );

      await pumpAt(tester, home, viewport: 1440);
      expect(find.byKey(const ValueKey('home-secondary-column')), findsOneWidget);

      tester.view.physicalSize = Size(slotFor(1100), 2400);
      await tester.pumpWidget(app(home));
      await tester.pump();
      expect(find.byKey(const ValueKey('home-secondary-column')), findsNothing);

      tester.view.physicalSize = Size(slotFor(1440), 2400);
      await tester.pumpWidget(app(home));
      await tester.pump();
      expect(find.byKey(const ValueKey('home-secondary-column')), findsOneWidget);

      expect(rooms.liveCalls, 1);
      expect(rooms.ownedCalls, 1);
      expect(clubs.calls, 1);
      expect(friends.calls, 1);
      expect(follow.calls, 1);
      expect(messages.calls, 1);
      expect(feed.calls, 1);
      // One lounge listener for the one membership, and the roster pool
      // stays inside its budget across both layouts.
      expect(rooms.loungeCalls, 1);
      expect(rooms.participantCalls, lessThanOrEqualTo(4));
      expect(tester.takeException(), isNull);
    });
  });
}
