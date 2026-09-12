import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/clubs/data/models/club.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_friend_tile.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_here_now_hero.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_people_strip.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_places_section.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_roster_cache.dart';
import 'package:yovoice/features/home/presentation/widgets/shared/home_section_status.dart';
import 'package:yovoice/features/profile/data/models/profile_visibility.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/rooms/data/models/room_participant.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/shared/widgets/profile/people_status_ring.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// The defects the gate reviews found on Home, each pinned so it cannot come
/// back silently.
///
/// Three of them are the same class of accessibility mistake (`Semantics`
/// wrapped AROUND a Material button, which is its own semantics boundary), two
/// are claims about facts the app never checked, one is a hard text clip, and
/// the rest are marks that meant two different things on one rail. Every case
/// here failed before the fix that accompanies it.
void main() {
  const pl = AppLocalizations(Locale('pl'));

  Widget host(
    Widget child, {
    Size size = const Size(390, 1400),
    double scale = 1,
    double pad = 16,
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
          child: Padding(padding: EdgeInsets.all(pad), child: child),
        ),
      ),
    ),
  );

  VoiceRoom room({
    String id = 'r1',
    String name = 'Wieczorne rozmowy',
    bool broadcast = false,
  }) => VoiceRoom(
    id: id,
    hostId: 'host',
    hostName: 'Host',
    hostPhotoUrl: null,
    name: name,
    description: '',
    category: 'community',
    visibility: 'public',
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
    experience: broadcast ? 'broadcast' : 'community',
  );

  Club club(String id, String name, {int members = 12}) => Club(
    id: id,
    name: name,
    description: '',
    ownerId: 'owner',
    ownerName: 'Owner',
    avatarUrl: null,
    bannerUrl: null,
    privacy: ClubPrivacy.private,
    defaultLanguage: 'Polish',
    memberCount: members,
    onlineCount: 99,
    defaultChatChannelId: '',
    defaultVoiceChannelId: '',
    announcementChannelId: '',
    createdAt: null,
    updatedAt: null,
    type: ClubType.community,
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

  /// Every semantics node under [finder], flattened.
  List<SemanticsNode> nodesUnder(WidgetTester tester, Finder finder) {
    final root = tester.getSemantics(finder);
    final all = <SemanticsNode>[];
    void visit(SemanticsNode node) {
      all.add(node);
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(root);
    return all;
  }

  group('B3 — the hero CTA is ONE named, tappable button', () {
    testWidgets('name, role, hint and tap all live on the same node', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        host(
          HomeHereNowHero(
            candidate: HomeLiveCandidate(
              room: room(),
              tier: HomeHereNowTier.public,
            ),
            roster: null,
            friendIds: const {},
            onJoin: () => taps++,
          ),
        ),
      );
      await tester.pump();

      final pill = find.descendant(
        of: find.byKey(const ValueKey('home-hero-join')),
        matching: find.byType(FilledButton),
      );
      expect(pill, findsOneWidget);
      final node = tester.getSemantics(pill);
      final data = node.getSemanticsData();
      expect(node.label, pl.homeJoinConversation);
      expect(node.hint, 'Otwiera ekran przed dołączeniem');
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      // The real control still accepts focus, which an `excludeSemantics`
      // wrapper would have thrown away along with the duplicate node.
      expect(data.hasAction(SemanticsAction.focus), isTrue);

      // And there is no second, nameless button on the same rectangle.
      final buttons = nodesUnder(
        tester,
        find.byType(HomeHereNowHero),
      ).where((n) => n.getSemanticsData().flagsCollection.isButton).toList();
      expect(buttons, isNotEmpty);
      for (final button in buttons) {
        expect(
          button.label,
          isNotEmpty,
          reason: 'every button on the hero has an accessible name',
        );
      }

      await tester.tap(pill);
      expect(taps, 1);
      handle.dispose();
    });
  });

  group('B4 — a place card announces the action it performs', () {
    testWidgets('the card opens the place; "Zajrzyj" stays its own control', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var opened = 0;
      var entered = 0;
      await tester.pumpWidget(
        host(
          HomeServerActivitySection(
            places: [
              HomePlace(club: club('c1', 'Nasz dom'), lounge: lounge('c1')),
            ],
            rosters: HomeRosterCache(service: null),
            onSeeAll: () {},
            onOpenPlace: (_) => opened++,
            onEnterLounge: (_) => entered++,
          ),
        ),
      );
      await tester.pump();

      final card = find.byKey(const ValueKey('home-club-activity-c1'));
      final node = tester.getSemantics(card);
      expect(node.label, contains('Otwórz miejsce.'));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'the node that promises "Otwórz miejsce" must perform it',
      );

      // "Zajrzyj" is a second node with its own name and its own tap — not a
      // fragment merged into the card, and not the card's only action.
      final pill = nodesUnder(tester, card).firstWhere(
        (n) => n.label.startsWith('Zajrzyj'),
        orElse: () => throw StateError('no "Zajrzyj" node'),
      );
      expect(pill.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(pill.label, 'Zajrzyj: Nasz dom');

      // The card's own label is not a run-on of every painted fragment.
      expect(node.label.contains('Zajrzyj'), isFalse);

      handle.dispose();

      await tester.tap(find.text('Zajrzyj'));
      await tester.pump();
      expect(entered, 1);
      expect(opened, 0);
    });
  });

  group('B5 — the hero headline never clips', () {
    for (final width in <double>[1280, 1440]) {
      for (final scale in <double>[1, 2]) {
        testWidgets('$width at ${scale}x keeps every word', (tester) async {
          await tester.pumpWidget(
            host(
              SizedBox(
                // The desktop main column at this viewport, minus the rail.
                width: width == 1280 ? 626 : 788,
                child: HomeHereNowHero(
                  candidate: HomeLiveCandidate(
                    room: room(),
                    tier: HomeHereNowTier.public,
                  ),
                  // Two friends in the roster is what earns the longest
                  // headline the copy table can produce.
                  roster: HomeRosterEntry(
                    participants: [
                      person('maja', 'Maja'),
                      person('olek', 'Olek'),
                    ],
                    failed: false,
                  ),
                  friendIds: const {'maja', 'olek'},
                  onJoin: () {},
                  compact: false,
                  expanded: true,
                ),
              ),
              size: Size(width, 2400),
              scale: scale,
              // The column IS the measure under test: the page gutter is
              // already outside it in the real composition.
              pad: 0,
            ),
          );
          await tester.pump();

          final headline = find.text('Twoi ludzie już rozmawiają.');
          expect(headline, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: headline, matching: find.byType(RichText)),
          );
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: 'the card grows; the headline is never cut',
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('B6 — Home only calls a place quiet if it looked at it', () {
    testWidgets('with nothing unchecked it speaks for all of them', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          HomeServerActivitySection(
            places: [HomePlace(club: club('c1', 'Nasz dom'))],
            rosters: HomeRosterCache(service: null),
            onSeeAll: () {},
            onOpenPlace: (_) {},
            onEnterLounge: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Teraz cicho w Twoich miejscach.'), findsOneWidget);
    });

    testWidgets('memberships beyond the listener budget are unknown, not '
        'quiet', (tester) async {
      await tester.pumpWidget(
        host(
          HomeServerActivitySection(
            places: [
              for (var i = 0; i < 4; i++)
                HomePlace(club: club('c$i', 'Miejsce $i')),
            ],
            uncheckedPlaces: 3,
            rosters: HomeRosterCache(service: null),
            onSeeAll: () {},
            onOpenPlace: (_) {},
            onEnterLounge: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Teraz cicho w Twoich miejscach.'), findsNothing);
      expect(
        find.textContaining('które udało się sprawdzić'),
        findsOneWidget,
        reason: 'a place Home never read is not a quiet place',
      );
    });
  });

  group('H5 — a place with no counter says nothing about its size', () {
    testWidgets('the phone rail guards memberCount the way the desktop does', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          HomePlacesRail(
            places: [
              HomePlace(club: club('c1', 'Bez licznika', members: 0)),
              HomePlace(club: club('c2', 'Z licznikiem', members: 12)),
            ],
            onOpenPlace: (_) {},
            onCreateServer: () {},
          ),
        ),
      );
      await tester.pump();

      final labels = nodesUnder(
        tester,
        find.byType(HomePlacesRail),
      ).map((n) => n.label).where((label) => label.isNotEmpty).toList();
      expect(labels, contains('Bez licznika. Otwórz.'));
      expect(labels, contains('Z licznikiem, 12 osób. Otwórz.'));
      expect(labels.any((l) => l.contains('0 osób')), isFalse);
      handle.dispose();
    });
  });

  group('V1/V9 — one rail, one meaning per mark', () {
    UserProfile profile() => UserProfile(
      uid: 'me',
      email: 'me@yovoice.app',
      displayName: 'Kamil',
      username: 'kamil',
      bio: '',
      country: '',
      nativeLanguage: '',
      spokenLanguages: const [],
      learningLanguages: const [],
      photoUrl: null,
      bannerUrl: null,
      website: '',
      accountType: AccountType.personal,
      friendCount: 0,
      followerCount: 0,
      followingCount: 0,
      roomCount: 0,
      communityCount: 0,
      voiceMinutes: 0,
      messageCount: 0,
      activeDays: 0,
      momentCount: 0,
      reactionCount: 0,
      hostMinutes: 0,
      selectedTitleId: null,
      unlockedTitleIds: const [],
      unlockedTitleTimestamps: const {},
      createdAt: DateTime(2026, 1, 1),
      profileVisibility: ProfileVisibility.public,
    );

    testWidgets('the own tile carries presence as a dot, never as the ring '
        'that means "new Voice Moment"', (tester) async {
      await tester.pumpWidget(
        host(
          HomePeopleStrip(
            friends: Stream<List<FriendUser>>.value(const []),
            profile: Stream<UserProfile>.value(profile()),
            onSeeAll: () {},
          ),
        ),
      );
      await tester.pump();

      final me = find.byKey(const ValueKey('home-people-me'));
      expect(me, findsOneWidget);
      expect(
        find.byType(PeopleStatusAvatar),
        findsNothing,
        reason: "PeopleStatusAvatar's ring means STATUS everywhere else",
      );
      final tile = tester.widget<HomeFriendTile>(me);
      expect(tile.voice, isNull, reason: 'so the ring slot stays unpainted');
      expect(tile.showChangeCaret, isTrue);
      expect(tile.statusLabel, 'Dostępny');
    });

    testWidgets('the own tile sits on the same column as every friend', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          HomePeopleStrip(
            friends: Stream<List<FriendUser>>.value([
              const FriendUser(
                id: 'f1',
                displayName: 'Maja',
                email: 'maja@yovoice.app',
                photoUrl: null,
                isOnline: true,
                lastSeen: null,
              ),
            ]),
            profile: Stream<UserProfile>.value(profile()),
            // Wide enough that the standard column already holds
            // "Dostępny ⌄" in the widget-test font, where every glyph is a
            // full em square and a phone-sized column never could.
            avatarRadius: 44,
            onSeeAll: () {},
          ),
        ),
      );
      await tester.pump();

      // The own tile used to add the caret's width to its column
      // UNCONDITIONALLY, which pushed its disc ~9 px further inboard than
      // every neighbour on a rail whose whole job is to read as one line of
      // faces. It now widens only when the status WORD needs the room.
      final me = tester.getSize(find.byKey(const ValueKey('home-people-me')));
      final friend = tester.getSize(
        find.byKey(const ValueKey('home-person-f1')),
      );
      expect(me.width, friend.width);
      // Both tiles print the presence word; only the own tile carries the
      // caret that opens the availability picker.
      expect(find.text('Dostępny'), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-people-me')),
          matching: find.byIcon(Icons.expand_more_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a failed friends read keeps the standing "add" action', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          HomePeopleStrip(
            friends: Stream<List<FriendUser>>.error(
              StateError('permission-denied'),
            ),
            profile: Stream<UserProfile>.value(profile()),
            onSeeAll: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('home-people-error')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-people-add')),
        findsOneWidget,
        reason: 'a denial must not also cost the reader an unrelated door',
      );
    });
  });

  group('V6 — every hero portrait is the same circle', () {
    testWidgets('a listener renders exactly the face a speaker does', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          HomeHereNowHero(
            candidate: HomeLiveCandidate(
              room: room(),
              tier: HomeHereNowTier.public,
            ),
            roster: HomeRosterEntry(
              participants: [
                person('a', 'Maja'),
                person('b', 'Olek'),
                person('c', 'Ala', speaker: false),
              ],
              failed: false,
            ),
            friendIds: const {},
            onJoin: () {},
          ),
        ),
      );
      await tester.pump();

      final faces = tester
          .renderObjectList<RenderBox>(
            find.descendant(
              of: find.byType(HomeHereNowHero),
              matching: find.byType(UserAvatar),
            ),
          )
          .toList();
      expect(faces.length, 3);
      final widths = faces.map((box) => box.size.width).toSet();
      expect(
        widths.length,
        1,
        reason:
            'the ring slot is constant, so the person who is only listening '
            'does not render a larger face than the two who are talking',
      );
    });
  });

  group('V8 — an error card says WHICH section failed', () {
    testWidgets('the section sentence leads and the cause follows', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          HomeSectionError(
            error: StateError('permission-denied'),
            message: 'Nie udało się wczytać Twoich miejsc.',
            onRetry: () {},
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text(
          'Nie udało się wczytać Twoich miejsc. '
          'Nie masz uprawnień, aby to zrobić.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an unrecognised error adds nothing generic', (tester) async {
      await tester.pumpWidget(
        host(
          HomeSectionError(
            error: StateError('something nobody mapped'),
            message: 'Nie udało się wczytać ostatnich czatów.',
            onRetry: () {},
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text('Nie udało się wczytać ostatnich czatów.'),
        findsOneWidget,
      );
    });
  });
}
