import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/core/theme/place_identity.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_participant_stack.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_places_section.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_roster_cache.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';

/// "W Twoich serwerach" and "Twoje miejsca": the account's REAL memberships.
///
/// Two facts this section must never confuse. `Club.onlineCount` is a
/// membership counter written by Cloud Functions, not presence, so it is
/// never phrased as activity — it is never rendered at all. And a lounge that
/// could not be read is not a quiet lounge: it says so and offers a retry.
void main() {
  Club club(
    String id,
    String name, {
    ClubType type = ClubType.community,
    int members = 12,
    int online = 99,
    String? avatarUrl,
  }) => Club(
    id: id,
    name: name,
    description: '',
    ownerId: 'owner',
    ownerName: 'Owner',
    avatarUrl: avatarUrl,
    bannerUrl: null,
    privacy: ClubPrivacy.private,
    defaultLanguage: 'Polish',
    memberCount: members,
    onlineCount: online,
    defaultChatChannelId: '',
    defaultVoiceChannelId: '',
    announcementChannelId: '',
    createdAt: null,
    updatedAt: null,
    type: type,
  );

  VoiceRoom lounge(String clubId, {bool live = true, bool broadcast = false}) =>
      VoiceRoom(
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
        participantCount: 2,
        memberCount: 0,
        isLive: live,
        roomType: RoomType.community,
        status: RoomStatus.active,
        imageUrl: null,
        approvalRequired: false,
        slowModeSeconds: 0,
        autoMuteNewUsers: false,
        membersCanStartVoice: true,
        createdAt: null,
        updatedAt: null,
        experience: broadcast ? 'broadcast' : 'community',
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
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );

  group('W Twoich serwerach', () {
    testWidgets('only live lounges become rows, and at most three', (
      tester,
    ) async {
      final places = [
        for (var i = 0; i < 5; i++)
          HomePlace(club: club('c$i', 'Miejsce $i'), lounge: lounge('c$i')),
        HomePlace(
          club: club('quiet', 'Ciche miejsce'),
          lounge: lounge('quiet', live: false),
        ),
      ];
      await tester.pumpWidget(
        host(
          HomeServerActivitySection(
            places: places,
            rosters: HomeRosterCache(),
            onSeeAll: () {},
            onOpenPlace: (_) {},
            onEnterLounge: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('W Twoich serwerach'), findsOneWidget);
      expect(find.byType(HomeServerActivityCard), findsNWidgets(3));
      expect(find.text('Ciche miejsce'), findsNothing);
    });

    testWidgets('memberships with nothing live read as quiet, not as empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          HomeServerActivitySection(
            places: [
              HomePlace(
                club: club('c1', 'Nasz dom'),
                lounge: lounge('c1', live: false),
              ),
            ],
            rosters: HomeRosterCache(),
            onSeeAll: () {},
            onOpenPlace: (_) {},
            onEnterLounge: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('W Twoich serwerach'), findsOneWidget);
      expect(find.text('Teraz cicho w Twoich miejscach.'), findsOneWidget);
      expect(find.byType(HomeServerActivityCard), findsNothing);
    });

    testWidgets('no memberships: no heading at all — a title is a promise', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          HomeServerActivitySection(
            places: const [],
            rosters: HomeRosterCache(),
            onSeeAll: () {},
            onOpenPlace: (_) {},
            onEnterLounge: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('W Twoich serwerach'), findsNothing);
      expect(find.text('Teraz cicho w Twoich miejscach.'), findsNothing);
    });

    testWidgets('a lounge that could not be read says so and offers a retry, '
        'while its neighbours keep working', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        host(
          HomeServerActivitySection(
            places: [
              HomePlace(club: club('ok', 'Działa'), lounge: lounge('ok')),
              HomePlace(club: club('bad', 'Odmowa'), loungeFailed: true),
            ],
            rosters: HomeRosterCache(),
            onSeeAll: () {},
            onOpenPlace: (_) {},
            onEnterLounge: (_) {},
            onRetryPlace: (_) => retries++,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Nie udało się sprawdzić rozmowy'), findsOneWidget);
      expect(find.text('Działa'), findsOneWidget);
      // The failed row offers no way in and claims no activity.
      expect(find.text('Zajrzyj'), findsOneWidget);
      await tester.tap(find.text('Spróbuj ponownie'));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('the row shows the real roster and the club-room context, '
        'never the stored lounge name and never onlineCount', (tester) async {
      final cache = HomeRosterCache();
      addTearDown(cache.dispose);
      await tester.pumpWidget(
        host(
          HomeServerActivitySection(
            places: [
              HomePlace(club: club('c1', 'Nasz dom'), lounge: lounge('c1')),
            ],
            rosters: _SeededRosters({
              'club_lounge_c1': HomeRosterEntry(
                participants: [
                  person('mama', 'Mama'),
                  person('tata', 'Tata'),
                ],
              ),
            }),
            onSeeAll: () {},
            onOpenPlace: (_) {},
            onEnterLounge: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Nasz dom'), findsOneWidget);
      expect(find.text('Pokój klubu'), findsOneWidget);
      expect(find.textContaining('Lounge'), findsNothing);
      expect(find.text('Mama i Tata rozmawiają'), findsOneWidget);
      expect(find.text('Rozmowa głosowa'), findsOneWidget);
      expect(find.byType(HomeParticipantStack), findsOneWidget);
      // The membership counter is never phrased as activity.
      expect(find.textContaining('99'), findsNothing);
    });

    testWidgets('a broadcast lounge keeps the two products distinct', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          HomeServerActivitySection(
            places: [
              HomePlace(
                club: club('c1', 'Nasz dom'),
                lounge: lounge('c1', broadcast: true),
              ),
            ],
            rosters: HomeRosterCache(),
            onSeeAll: () {},
            onOpenPlace: (_) {},
            onEnterLounge: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Transmisja'), findsOneWidget);
      expect(find.text('Rozmowa głosowa'), findsNothing);
    });

    testWidgets('the pill enters the lounge; the card body opens the place', (
      tester,
    ) async {
      HomePlace? entered;
      Club? opened;
      await tester.pumpWidget(
        host(
          HomeServerActivitySection(
            places: [
              HomePlace(club: club('c1', 'Nasz dom'), lounge: lounge('c1')),
            ],
            rosters: HomeRosterCache(),
            onSeeAll: () {},
            onOpenPlace: (value) => opened = value,
            onEnterLounge: (value) => entered = value,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Zajrzyj'));
      await tester.pump();
      expect(entered?.club.id, 'c1');
      expect(opened, isNull);

      await tester.tap(find.text('Nasz dom'));
      await tester.pump();
      expect(opened?.id, 'c1');
    });

    testWidgets('"Zobacz wszystkie" leads to the Serwery destination', (
      tester,
    ) async {
      var seeAll = 0;
      await tester.pumpWidget(
        host(
          HomeServerActivitySection(
            places: [
              HomePlace(club: club('c1', 'Nasz dom'), lounge: lounge('c1')),
            ],
            rosters: HomeRosterCache(),
            onSeeAll: () => seeAll++,
            onOpenPlace: (_) {},
            onEnterLounge: (_) {},
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('home-servers-see-all')));
      await tester.pump();
      expect(seeAll, 1);
    });
  });

  group('Twoje miejsca', () {
    testWidgets('every membership is a door, and the last tile creates one', (
      tester,
    ) async {
      Club? opened;
      var create = 0;
      await tester.pumpWidget(
        host(
          HomePlacesRail(
            places: [
              HomePlace(club: club('c1', 'Nasz dom', type: ClubType.family)),
              HomePlace(club: club('c2', 'Po godzinach')),
            ],
            onOpenPlace: (value) => opened = value,
            onCreateServer: () => create++,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Twoje miejsca'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-place-c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-place-c2')), findsOneWidget);
      expect(find.text('Stwórz serwer'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('home-place-c2')));
      await tester.pump();
      expect(opened?.id, 'c2');

      await tester.tap(find.byKey(const ValueKey('home-places-create')));
      await tester.pump();
      expect(create, 1);
    });

    testWidgets('a place announces its full name and its member count with '
        'Polish declension', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          HomePlacesRail(
            places: [
              HomePlace(
                club: club(
                  'c1',
                  'Podcasty nam bliskie i dalekie',
                  members: 22,
                ),
              ),
            ],
            onOpenPlace: (_) {},
            onCreateServer: () {},
          ),
        ),
      );
      await tester.pump();
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('home-place-c1')))
            .label,
        'Podcasty nam bliskie i dalekie, 22 osoby. Otwórz.',
      );
      handle.dispose();
    });

    testWidgets('identity follows the club type, and a real avatar wins over '
        'the glyph', (tester) async {
      await tester.pumpWidget(
        host(
          HomePlacesRail(
            places: [
              HomePlace(club: club('fam', 'Nasz dom', type: ClubType.family)),
              HomePlace(club: club('com', 'Po godzinach')),
              HomePlace(
                club: club(
                  'pic',
                  'Z okładką',
                  avatarUrl: 'https://example.test/a.png',
                ),
              ),
            ],
            onOpenPlace: (_) {},
            onCreateServer: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(PlaceIdentity.family.icon), findsOneWidget);
      expect(find.byIcon(PlaceIdentity.community.icon), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no memberships: one honest empty card with real actions', (
      tester,
    ) async {
      var create = 0;
      var discover = 0;
      await tester.pumpWidget(
        host(
          HomePlacesEmptyCard(
            onCreateServer: () => create++,
            onDiscover: () => discover++,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Nie masz jeszcze swoich miejsc.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-places-empty-create')));
      await tester.tap(
        find.byKey(const ValueKey('home-places-empty-discover')),
      );
      await tester.pump();
      expect(create, 1);
      expect(discover, 1);
    });

    testWidgets('loading draws static squares, never a shimmering name', (
      tester,
    ) async {
      await tester.pumpWidget(host(const HomePlacesLoading()));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('home-places-loading')),
        findsOneWidget,
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('long Polish names and 200 % text do not overflow at 360', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          HomePlacesRail(
            places: [
              for (var i = 0; i < 6; i++)
                HomePlace(
                  club: club('c$i', 'Podcasty nam bliskie i dalekie $i'),
                ),
            ],
            onOpenPlace: (_) {},
            onCreateServer: () {},
          ),
          size: const Size(360, 900),
          scale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final tile = tester.getSize(find.byKey(const ValueKey('home-place-c0')));
      expect(tile.width, greaterThanOrEqualTo(AppSizing.minimumTouchTarget));
    });
  });
}

/// A roster pool with fixed answers — the section under test never opens a
/// listener of its own, it only reads the shared pool.
class _SeededRosters extends HomeRosterCache {
  _SeededRosters(this._entries);

  final Map<String, HomeRosterEntry> _entries;

  @override
  HomeRosterEntry? entryFor(String roomId) => _entries[roomId];
}
