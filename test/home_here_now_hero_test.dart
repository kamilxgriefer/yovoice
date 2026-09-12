import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_here_now_hero.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_roster_cache.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

/// "Tu i teraz": which room Home features, what it is allowed to say about
/// it, and the one action that leads into it.
///
/// The rules under test are the honesty rules. A friend claim requires a
/// roster the caller actually read. A name is never inflected. A roster the
/// caller may not read is said out loud, not printed as silence. And opening
/// Home never joins anything — the CTA leads to the existing pre-join screen.
class _Rooms extends RoomService {
  _Rooms({required super.firestore, required super.auth});

  final Map<String, StreamController<List<RoomParticipant>>> controllers = {};
  int opened = 0;

  @override
  Stream<List<RoomParticipant>> watchParticipants(String roomId) {
    opened++;
    final controller = controllers.putIfAbsent(
      roomId,
      () => StreamController<List<RoomParticipant>>.broadcast(),
    );
    return controller.stream;
  }

  Future<void> dispose() async {
    for (final controller in controllers.values) {
      await controller.close();
    }
  }
}

RoomParticipant _participant(
  String id, {
  String? name,
  bool speaker = true,
  String role = 'listener',
}) => RoomParticipant(
  userId: id,
  displayName: name ?? id,
  photoUrl: null,
  role: role,
  isMuted: false,
  isSpeaker: speaker,
  isHandRaised: false,
  joinedAt: null,
);

VoiceRoom _room({
  required String id,
  String name = 'Wieczorne rozmowy',
  String category = 'community',
  bool broadcast = false,
  String? imageUrl,
  String hostId = 'host',
}) => VoiceRoom(
  id: id,
  hostId: hostId,
  hostName: 'Host',
  hostPhotoUrl: null,
  name: name,
  description: '',
  category: category,
  visibility: 'public',
  language: 'Polish',
  maxParticipants: null,
  participantCount: 3,
  memberCount: 0,
  isLive: true,
  roomType: RoomType.community,
  status: RoomStatus.active,
  imageUrl: imageUrl,
  approvalRequired: false,
  slowModeSeconds: 0,
  autoMuteNewUsers: false,
  membersCanStartVoice: true,
  createdAt: null,
  updatedAt: null,
  experience: broadcast ? 'broadcast' : 'community',
);

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
  memberCount: 12,
  onlineCount: 0,
  defaultChatChannelId: '',
  defaultVoiceChannelId: '',
  announcementChannelId: '',
  createdAt: null,
  updatedAt: null,
  type: ClubType.family,
);

void main() {
  const pl = AppLocalizations(Locale('pl'));
  const en = AppLocalizations(Locale('en'));

  group('the selection rule', () {
    late FakeFirebaseFirestore db;
    late _Rooms rooms;
    late HomeRosterCache cache;

    setUp(() {
      db = FakeFirebaseFirestore();
      rooms = _Rooms(
        firestore: db,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me'),
        ),
      );
      cache = HomeRosterCache(service: rooms);
    });

    tearDown(() async {
      cache.dispose();
      await rooms.dispose();
    });

    List<HomeLiveCandidate> candidates() => [
      HomeLiveCandidate(
        room: _room(id: 'lounge'),
        tier: HomeHereNowTier.place,
        club: _club('c1', 'Nasz dom'),
      ),
      HomeLiveCandidate(room: _room(id: 'owned'), tier: HomeHereNowTier.owned),
      HomeLiveCandidate(
        room: _room(id: 'public'),
        tier: HomeHereNowTier.public,
      ),
    ];

    test('with no rosters loaded it takes the first tier, never a guess', () {
      final chosen = selectHereNowCandidate(
        candidates: candidates(),
        rosters: cache,
        friendIds: const {'maja'},
      );
      expect(chosen!.roomId, 'lounge');
    });

    test('a friend in a LOADED roster wins across tiers', () async {
      final list = candidates();
      cache.request(list.map((c) => c.roomId));
      rooms.controllers['lounge']!.add([_participant('nobody')]);
      rooms.controllers['public']!.add([_participant('maja')]);
      await Future<void>.delayed(Duration.zero);
      final chosen = selectHereNowCandidate(
        candidates: list,
        rosters: cache,
        friendIds: const {'maja'},
      );
      expect(chosen!.roomId, 'public');
    });

    test('a denied roster never promotes and never blocks', () async {
      final list = candidates();
      cache.request(list.map((c) => c.roomId));
      rooms.controllers['lounge']!.addError(StateError('permission-denied'));
      await Future<void>.delayed(Duration.zero);
      expect(cache.failedFor('lounge'), isTrue);
      final chosen = selectHereNowCandidate(
        candidates: list,
        rosters: cache,
        friendIds: const {'maja'},
      );
      expect(chosen!.roomId, 'lounge');
    });

    test('at most four rosters are ever subscribed', () {
      cache.request(['a', 'b', 'c', 'd', 'e', 'f']);
      expect(cache.openSubscriptionCount, 4);
      expect(rooms.opened, 4);
    });

    test('an empty candidate list features nothing', () {
      expect(
        selectHereNowCandidate(
          candidates: const [],
          rosters: cache,
          friendIds: const {'maja'},
        ),
        isNull,
      );
    });
  });

  group('the copy', () {
    test('headlines never inflect a room or place name', () {
      expect(
        homeHeroHeadline(
          copy: pl,
          friendsInRoom: [_participant('a'), _participant('b')],
          isBroadcast: false,
        ),
        'Twoi ludzie już rozmawiają.',
      );
      expect(
        homeHeroHeadline(
          copy: pl,
          friendsInRoom: [_participant('a', name: 'Maja')],
          isBroadcast: false,
        ),
        'Maja już rozmawia.',
      );
      expect(
        homeHeroHeadline(copy: pl, friendsInRoom: const [], isBroadcast: false),
        'Rozmowa właśnie trwa.',
      );
      expect(
        homeHeroHeadline(copy: pl, friendsInRoom: const [], isBroadcast: true),
        'Transmisja właśnie trwa.',
      );
      expect(
        homeHeroHeadline(copy: en, friendsInRoom: const [], isBroadcast: false),
        'A conversation is on right now.',
      );
    });

    test('the summary names speakers and declines the Polish tail', () {
      String summary(List<RoomParticipant> people) =>
          homeActivitySummary(copy: pl, participants: people)!;

      expect(summary([_participant('1', name: 'Maja')]), 'Maja rozmawia');
      expect(
        summary([
          _participant('1', name: 'Maja'),
          _participant('2', name: 'Ola'),
        ]),
        'Maja i Ola rozmawiają',
      );
      expect(
        summary([
          _participant('1', name: 'Maja'),
          _participant('2', name: 'Ola'),
          _participant('3', name: 'Bartek'),
        ]),
        'Maja, Ola i Bartek rozmawiają',
      );
      expect(
        summary([
          for (var i = 0; i < 5; i++) _participant('$i', name: 'Osoba $i'),
        ]),
        'Osoba 0, Osoba 1 i Osoba 2 oraz 2 osoby',
      );
      // Nameless speakers fall back to a count, never to an invented name.
      expect(
        summary([for (var i = 0; i < 22; i++) _participant('$i', name: ' ')]),
        '22 osoby rozmawiają',
      );
      expect(
        summary([for (var i = 0; i < 5; i++) _participant('$i', name: ' ')]),
        '5 osób rozmawia',
      );
      // Listeners only: the room is on, but nobody holds the microphone.
      expect(
        summary([
          for (var i = 0; i < 3; i++)
            _participant('$i', name: 'Ktoś', speaker: false),
        ]),
        '3 osoby słuchają',
      );
      expect(
        homeActivitySummary(copy: pl, participants: const []),
        isNull,
      );
    });

    test('the Polish count buckets follow the 2-4 / 12-14 rule', () {
      const expected = {
        1: HomeCountForm.one,
        2: HomeCountForm.few,
        4: HomeCountForm.few,
        5: HomeCountForm.many,
        12: HomeCountForm.many,
        14: HomeCountForm.many,
        22: HomeCountForm.few,
        25: HomeCountForm.many,
        101: HomeCountForm.many,
        112: HomeCountForm.many,
      };
      for (final entry in expected.entries) {
        expect(homeCountForm(entry.key), entry.value, reason: '${entry.key}');
      }
    });

    test('the eyebrow names the place and the room, in the nominative', () {
      expect(
        homeHeroEyebrow(
          copy: pl,
          room: _room(id: 'r', name: 'Nasz dom Lounge'),
          club: _club('c', 'Nasz dom'),
        ),
        'Nasz dom • Pokój klubu',
        reason: 'the stored lounge name is machine-written, never printed',
      );
      expect(
        homeHeroEyebrow(
          copy: pl,
          room: _room(id: 'r', name: 'Salon po godzinach'),
        ),
        'community • Salon po godzinach',
      );
      expect(
        homeHeroEyebrow(
          copy: pl,
          room: _room(id: 'r', name: 'Salon', category: '  '),
        ),
        'Salon',
      );
      expect(
        homeHeroEyebrow(
          copy: pl,
          room: _room(id: 'r', name: 'Salon', category: '', broadcast: true),
        ),
        'Salon • Transmisja',
      );
    });
  });

  group('the card', () {
    Widget host(
      Widget child, {
      Size size = const Size(390, 900),
      double scale = 1,
    }) => MaterialApp(
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
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    );

    HomeHereNowHero hero({
      VoiceRoom? room,
      Club? club,
      HomeRosterEntry? roster,
      Set<String> friendIds = const {},
      VoidCallback? onJoin,
      VoidCallback? onOpenRoster,
    }) => HomeHereNowHero(
      candidate: HomeLiveCandidate(
        room: room ?? _room(id: 'r1'),
        tier: club == null ? HomeHereNowTier.public : HomeHereNowTier.place,
        club: club,
      ),
      roster: roster,
      friendIds: friendIds,
      onJoin: onJoin ?? () {},
      onOpenRoster: onOpenRoster,
    );

    testWidgets('the CTA names the product it leads into', (tester) async {
      await tester.pumpWidget(host(hero()));
      await tester.pump();
      expect(find.text('Dołącz do rozmowy'), findsOneWidget);

      await tester.pumpWidget(
        host(hero(room: _room(id: 'b1', broadcast: true))),
      );
      await tester.pump();
      expect(find.text('Dołącz do transmisji'), findsOneWidget);
      expect(find.text('Dołącz do rozmowy'), findsNothing);
    });

    testWidgets('the CTA is a 48 px control and fires once per tap', (
      tester,
    ) async {
      var joins = 0;
      await tester.pumpWidget(host(hero(onJoin: () => joins++)));
      await tester.pump();
      final cta = find.byKey(const ValueKey('home-hero-join'));
      expect(
        tester.getSize(cta).height,
        greaterThanOrEqualTo(AppSizing.standardControlHeight),
      );
      await tester.tap(cta);
      await tester.pump();
      expect(joins, 1);
    });

    testWidgets('a disabled CTA (a pre-join already opening) does nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          HomeHereNowHero(
            candidate: HomeLiveCandidate(
              room: _room(id: 'r1'),
              tier: HomeHereNowTier.public,
            ),
            roster: null,
            friendIds: const {},
            onJoin: null,
          ),
        ),
      );
      await tester.pump();
      final button = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const ValueKey('home-hero-join')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a friend in the roster earns the friend headline', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          hero(
            roster: HomeRosterEntry(
              participants: [
                _participant('maja', name: 'Maja'),
                _participant('ola', name: 'Ola'),
              ],
            ),
            friendIds: const {'maja', 'ola'},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Twoi ludzie już rozmawiają.'), findsOneWidget);
      expect(find.text('Maja i Ola rozmawiają'), findsOneWidget);
    });

    testWidgets('a roster still loading makes no friend claim', (tester) async {
      await tester.pumpWidget(
        host(hero(roster: null, friendIds: const {'maja'})),
      );
      await tester.pump();
      expect(find.text('Rozmowa właśnie trwa.'), findsOneWidget);
      expect(find.textContaining('Twoi ludzie'), findsNothing);
    });

    testWidgets('a denied roster says so, keeps the CTA and shows no names', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          hero(
            roster: const HomeRosterEntry(failed: true),
            friendIds: const {'maja'},
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('home-hero-roster-note')),
        findsOneWidget,
      );
      expect(find.text('Nie udało się sprawdzić, kto rozmawia.'), findsOneWidget);
      expect(find.text('Maja'), findsNothing);
      expect(find.byKey(const ValueKey('home-hero-join')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-rooms-error')), findsNothing);
    });

    testWidgets('the portrait cluster is one secondary control, not three', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        host(
          hero(
            roster: HomeRosterEntry(
              participants: [
                _participant('a', name: 'Ala'),
                _participant('b', name: 'Bo', speaker: false),
                _participant('c', name: 'Cyd', speaker: false),
              ],
            ),
            onOpenRoster: () => opened++,
          ),
        ),
      );
      await tester.pump();
      final cluster = find.byKey(const ValueKey('home-hero-cluster'));
      expect(cluster, findsOneWidget);
      await tester.tap(cluster);
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('no roster, no cluster — never a placeholder person', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(hero(roster: const HomeRosterEntry(participants: []))),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('home-hero-cluster')), findsNothing);
    });

    testWidgets('a room without a cover falls back to the branded gradient', (
      tester,
    ) async {
      await tester.pumpWidget(host(hero()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNothing);
    });

    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$width at ${scale}x wraps without overflowing', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 1600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            host(
              hero(
                room: _room(id: 'r1', name: 'Salon po godzinach'),
                club: _club('c1', 'Podcasty nam bliskie i dalekie'),
                roster: HomeRosterEntry(
                  participants: [
                    _participant(
                      'a',
                      name: 'Bartłomiej-Krzysztof Wojciechowski',
                    ),
                    _participant('b', name: 'Aleksandra Nowakowska-Kowalska'),
                  ],
                ),
              ),
              size: Size(width, 1600),
              scale: scale,
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
