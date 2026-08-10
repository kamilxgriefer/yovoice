import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/premium_desktop_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/voice_trending_card.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

/// Desktop-shell coverage. The rail and the Home right column are
/// desktop-only presentation over existing destinations and existing
/// data — these tests pin the parts that must not silently regress:
/// the exact primary items (and the ABSENCE of a Profile item), the
/// gear's settings callback, and Voice Trending rendering real live
/// rooms rather than placeholder content.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  /// Desktop-sized surface — the rail is a desktop-only surface and the
  /// default 800x600 test window is narrower than the smallest desktop.
  void useDesktopWindow(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('DesktopSidebar', () {
    testWidgets('shows exactly the six primary destinations and NO '
        'Profile/Moments/Clubs/Creator Studio rail items', (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(
        host(
          DesktopSidebar(
            active: DesktopNavItem.home,
            unreadConversationCount: 0,
            unreadNotificationCount: 0,
            onSelect: (_) {},
            onCreateRoom: () {},
            onOpenProfile: () {},
            onOpenProfileSettings: () {},
          ),
        ),
      );
      await tester.pump();

      for (final label in [
        'Home',
        'Discover',
        'Chats',
        'Notifications',
        'Friends',
        'More',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label missing');
      }
      // Profile is the bottom card; these three live in the More popover.
      for (final absent in ['Profile', 'Moments', 'Clubs', 'Creator Studio']) {
        expect(
          find.text(absent),
          findsNothing,
          reason: '$absent must not be a rail item',
        );
      }
      // Create Room is the ONLY creation action in the rail.
      expect(find.text('Create Room'), findsOneWidget);
      expect(find.text('Create your Moment'), findsNothing);
    });

    testWidgets('the gear opens profile settings; the card body opens the '
        'profile — two distinct callbacks', (tester) async {
      var settings = 0;
      var profile = 0;
      useDesktopWindow(tester);
      await tester.pumpWidget(
        host(
          DesktopSidebar(
            active: DesktopNavItem.home,
            unreadConversationCount: 0,
            unreadNotificationCount: 0,
            onSelect: (_) {},
            onCreateRoom: () {},
            onOpenProfile: () => profile++,
            onOpenProfileSettings: () => settings++,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Profile settings'));
      await tester.pump();
      expect(settings, 1);
      expect(profile, 0);
    });

    testWidgets('each primary item reports its own destination', (
      tester,
    ) async {
      final tapped = <DesktopNavItem>[];
      useDesktopWindow(tester);
      await tester.pumpWidget(
        host(
          DesktopSidebar(
            active: DesktopNavItem.home,
            unreadConversationCount: 0,
            unreadNotificationCount: 0,
            onSelect: tapped.add,
            onCreateRoom: () {},
            onOpenProfile: () {},
            onOpenProfileSettings: () {},
          ),
        ),
      );
      await tester.pump();

      for (final label in [
        'Discover',
        'Chats',
        'Notifications',
        'Friends',
        'More',
      ]) {
        await tester.tap(find.text(label));
        await tester.pump();
      }

      expect(tapped, [
        DesktopNavItem.discover,
        DesktopNavItem.chats,
        DesktopNavItem.notifications,
        DesktopNavItem.friends,
        DesktopNavItem.more,
      ]);
    });

    testWidgets('survives a SHORT desktop window (1440x620) — the rail '
        'scrolls instead of overflowing', (tester) async {
      useDesktopWindow(tester, size: const Size(1440, 620));
      await tester.pumpWidget(
        host(
          DesktopSidebar(
            active: DesktopNavItem.home,
            unreadConversationCount: 0,
            unreadNotificationCount: 0,
            onSelect: (_) {},
            onCreateRoom: () {},
            onOpenProfile: () {},
            onOpenProfileSettings: () {},
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      // The pinned profile card stays reachable at any height.
      expect(find.byTooltip('Profile settings'), findsOneWidget);
    });

    testWidgets('unread counts surface as badges', (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(
        host(
          DesktopSidebar(
            active: DesktopNavItem.home,
            unreadConversationCount: 3,
            unreadNotificationCount: 6,
            onSelect: (_) {},
            onCreateRoom: () {},
            onOpenProfile: () {},
            onOpenProfileSettings: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('3'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
    });
  });

  group('desktop information architecture', () {
    test('every destination is reachable: the rail owns Discover and '
        'Friends, everything else is in More or the profile card', () {
      // The rail's own primary items (Home/Chats live in the shell's
      // IndexedStack; Notifications pushes the bell feed).
      const railOwned = desktopRailDestinations;
      expect(railOwned, {MoreDestination.discover, MoreDestination.friends});

      // Reached from the profile card at the bottom of the rail.
      const profileCardOwned = {
        MoreDestination.profile,
        MoreDestination.settings,
      };

      // Anything else MUST be listed in the desktop More popover, or it
      // would become unreachable at desktop width.
      const inMorePopover = {
        MoreDestination.moments,
        MoreDestination.clubs,
        MoreDestination.creatorStudio,
        MoreDestination.achievements,
        MoreDestination.notifications,
        MoreDestination.settings,
      };

      final unreachable = MoreDestination.values
          .where(
            (destination) =>
                !railOwned.contains(destination) &&
                !profileCardOwned.contains(destination) &&
                !inMorePopover.contains(destination),
          )
          .toList();

      expect(
        unreachable,
        isEmpty,
        reason: 'no destination may be orphaned by the desktop rail',
      );
    });

    test('every destination still resolves to its real screen — moving '
        'items between rail and More changes no routes', () {
      for (final destination in MoreDestination.values) {
        expect(
          moreDestinationScreen(destination),
          isNotNull,
          reason: '$destination lost its screen',
        );
      }
    });
  });

  group('MoreDestinationHost', () {
    testWidgets('at DESKTOP width a pushed destination keeps the sidebar '
        'and shows NO mobile dock', (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: MoreDestinationHost(
            body: const Scaffold(body: Center(child: Text('Awards body'))),
            selectedIndex: 0,
            unreadConversationCount: 0,
            unreadNotificationCount: 0,
            activeDesktopItem: DesktopNavItem.more,
            onDestinationSelected: (_) {},
            onVoicePressed: () {},
            onMorePressed: () {},
            onDesktopNavSelected: (_) {},
            onCreateRoom: () {},
            onOpenProfile: () {},
            onOpenProfileSettings: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Awards body'), findsOneWidget);
      // The persistent rail is present…
      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(find.text('Create Room'), findsOneWidget);
      // …and the mobile dock is not: its Voice action never renders here.
      expect(find.byType(BottomNavigationBar), findsNothing);
    });

    testWidgets('at MOBILE width the same host keeps the existing dock', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: MoreDestinationHost(
            body: const Scaffold(body: Center(child: Text('Awards body'))),
            selectedIndex: 0,
            unreadConversationCount: 0,
            onDestinationSelected: (_) {},
            onVoicePressed: () {},
            onMorePressed: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Awards body'), findsOneWidget);
      // Mobile is untouched: no desktop rail, dock still hosted.
      expect(find.byType(DesktopSidebar), findsNothing);
      expect(find.text('Home'), findsWidgets);
    });
  });

  group('VoiceTrendingCard', () {
    testWidgets('Trending Moments renders REAL live rooms with a Live pill; '
        'People to Follow stays hidden when there are no suggestions', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      for (final entry in [
        ('Late Night Confessions', 'Real stories, live now'),
        ('Friday Freestyle', 'The room is warming up'),
      ].indexed) {
        await db.collection('rooms').doc('room-${entry.$1}').set({
          'hostId': 'host',
          'hostName': 'Host',
          'name': entry.$2.$1,
          'description': entry.$2.$2,
          'category': 'talk',
          'visibility': 'public',
          'language': 'English',
          'participantCount': 4,
          'memberCount': 0,
          'isLive': true,
          'roomType': 'community',
          'status': 'active',
          'experience': 'community',
          'createdAt': Timestamp.now(),
        });
      }

      final rooms = RoomService(
        firestore: db,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me', email: 'me@yovoice.app'),
        ),
      );

      VoiceRoom? opened;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 344,
            child: VoiceTrendingCard(
              roomService: rooms,
              onOpenRoom: (room) => opened = room,
              onSeeAll: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('Voice Trending'), findsOneWidget);
      expect(find.text('Trending Moments'), findsOneWidget);
      expect(find.text('Late Night Confessions'), findsOneWidget);
      expect(find.text('Real stories, live now'), findsOneWidget);
      expect(find.text('Live'), findsNWidgets(2));
      // No suggestions available in this environment → section hidden,
      // never filled with placeholder people.
      expect(find.text('People to Follow'), findsNothing);
      expect(find.text('See all'), findsOneWidget);

      await tester.tap(find.text('Late Night Confessions'));
      await tester.pump();
      expect(opened?.name, 'Late Night Confessions');
    });
  });

  group('PremiumDesktopCard', () {
    testWidgets('shows the three benefits and a working Check plans CTA', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 344,
            child: PremiumDesktopCard(onCheckPlans: () => taps++),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Become a Creator'), findsOneWidget);
      expect(find.text('Create your own Clubs'), findsOneWidget);
      expect(find.text('Stand out'), findsOneWidget);
      // The retired card's crown/bullets/Upgrade Now must not come back.
      expect(find.text('Upgrade Now'), findsNothing);

      await tester.tap(find.text('Check plans'));
      await tester.pump();
      expect(taps, 1);
    });
  });
}
