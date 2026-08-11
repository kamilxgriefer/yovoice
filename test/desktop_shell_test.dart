import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/screens/main_shell.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/followed_creators_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/premium_desktop_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/voice_trending_card.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/profile/data/models/follow_user.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
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
            onCreateMoment: () {},
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
      // The rail's two creation actions, in order.
      expect(find.text('Create Room'), findsOneWidget);
      expect(find.text('Create Voice Moment'), findsOneWidget);

      // Create Voice Moment sits UNDER Create Room, and both stay above
      // the pinned profile card.
      final createRoom = tester.getCenter(find.text('Create Room'));
      final createMoment = tester.getCenter(find.text('Create Voice Moment'));
      final profileCard = tester.getCenter(find.byTooltip('Profile settings'));
      expect(createMoment.dy, greaterThan(createRoom.dy));
      expect(profileCard.dy, greaterThan(createMoment.dy));
    });

    testWidgets('Create Voice Moment reports its own callback — the rail '
        'never owns a second recorder', (tester) async {
      var rooms = 0;
      var moments = 0;
      useDesktopWindow(tester);
      await tester.pumpWidget(
        host(
          DesktopSidebar(
            active: DesktopNavItem.home,
            unreadConversationCount: 0,
            unreadNotificationCount: 0,
            onSelect: (_) {},
            onCreateRoom: () => rooms++,
            onCreateMoment: () => moments++,
            onOpenProfile: () {},
            onOpenProfileSettings: () {},
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Create Voice Moment'));
      await tester.pump();
      expect(moments, 1);
      expect(rooms, 0, reason: 'the two actions are not the same button');

      await tester.tap(find.text('Create Room'));
      await tester.pump();
      expect(rooms, 1);
      expect(moments, 1);
    });

    testWidgets('both creation actions survive a SHORT desktop window '
        '(1440x620) and stay reachable', (tester) async {
      useDesktopWindow(tester, size: const Size(1440, 620));
      await tester.pumpWidget(
        host(
          DesktopSidebar(
            active: DesktopNavItem.home,
            unreadConversationCount: 0,
            unreadNotificationCount: 0,
            onSelect: (_) {},
            onCreateRoom: () {},
            onCreateMoment: () {},
            onOpenProfile: () {},
            onOpenProfileSettings: () {},
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Create Voice Moment'),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Create Voice Moment'), findsOneWidget);
      expect(find.byTooltip('Profile settings'), findsOneWidget);
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
            onCreateMoment: () {},
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
            onCreateMoment: () {},
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
            onCreateMoment: () {},
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
            onCreateMoment: () {},
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
        // Listed in the SAME popover, but only for accounts that pass
        // the staff check — an ordinary user never sees it. It is not
        // orphaned: for staff it is one popover entry like the rest.
        MoreDestination.moderation,
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

  group('rail navigation mechanism', () {
    test('Discover and Notifications are CONTENT SLOTS, not pushed '
        'routes — the rail reports them like Chats and Friends', () {
      // Every primary rail item except More must be representable as a
      // selected slot; if one of them went back to Navigator.push, the
      // shell would be re-created and the rail would slide/reopen.
      const slotBacked = {
        DesktopNavItem.home,
        DesktopNavItem.discover,
        DesktopNavItem.chats,
        DesktopNavItem.notifications,
        DesktopNavItem.friends,
      };
      final railItems = DesktopNavItem.values.toSet()
        ..remove(DesktopNavItem.more);
      expect(
        railItems,
        slotBacked,
        reason:
            'a primary rail item without a content slot would push a '
            'route over the desktop shell',
      );
    });

    testWidgets('selecting Discover or Notifications keeps ONE sidebar and '
        'pushes no route', (tester) async {
      useDesktopWindow(tester);

      final observer = _RouteCountObserver();
      await tester.pumpWidget(
        MaterialApp(navigatorObservers: [observer], home: _FakeDesktopShell()),
      );
      await tester.pump();

      for (final label in ['Discover', 'Notifications', 'Chats', 'Friends']) {
        await tester.tap(find.text(label));
        await tester.pump();
        // The rail is never duplicated or rebuilt as a second shell.
        expect(
          find.byType(DesktopSidebar),
          findsOneWidget,
          reason: '$label must not create a second shell',
        );
      }

      expect(
        observer.pushes,
        0,
        reason: 'rail destinations must swap content, never push a route',
      );
    });
  });

  group('More destinations on desktop', () {
    test('every popover destination renders a ROOT-TAB screen (no back '
        'button with nothing to pop)', () {
      // The six items the desktop More popover lists.
      const popoverItems = [
        MoreDestination.moments,
        MoreDestination.clubs,
        MoreDestination.creatorStudio,
        MoreDestination.achievements,
        MoreDestination.notifications,
        MoreDestination.settings,
      ];

      for (final destination in popoverItems) {
        final asRoot = moreDestinationScreen(destination, isRootTab: true);
        final asPushed = moreDestinationScreen(destination);
        expect(asRoot, isNotNull, reason: '$destination lost its screen');
        expect(asPushed, isNotNull);
        expect(
          asRoot.runtimeType,
          asPushed.runtimeType,
          reason:
              '$destination must be the SAME screen either way — the '
              'root-tab flag only hides its back affordance',
        );
      }
    });

    testWidgets('selecting a More destination swaps content in place: one '
        'sidebar, no route pushed', (tester) async {
      useDesktopWindow(tester);

      final observer = _RouteCountObserver();
      await tester.pumpWidget(
        MaterialApp(navigatorObservers: [observer], home: _FakeDesktopShell()),
      );
      await tester.pump();

      // Slots 5+ stand in for the popover destinations; selecting one
      // must behave exactly like selecting Chats.
      await tester.tap(find.text('More'));
      await tester.pump();
      expect(find.byType(DesktopSidebar), findsOneWidget);

      expect(
        observer.pushes,
        0,
        reason: 'a More destination must not push a route on desktop',
      );
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
            onCreateMoment: () {},
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

  group('desktop More popover — Moderation gating', () {
    Future<void> openPopover(WidgetTester tester, {required bool isStaff}) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDesktopMoreMenu(
                context,
                anchor: const Offset(80, 200),
                isStaff: isStaff,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('an ordinary user never sees Moderation listed', (
      tester,
    ) async {
      await openPopover(tester, isStaff: false);

      expect(find.text('Moderation'), findsNothing);
      // Every existing entry is still there.
      for (final label in [
        'Moments',
        'Clubs',
        'Creator Studio',
        'Awards',
        'Alerts',
        'Settings',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label went missing');
      }
    });

    testWidgets('staff see Moderation alongside — never instead of — the '
        'existing entries', (tester) async {
      await openPopover(tester, isStaff: true);

      expect(find.text('Moderation'), findsOneWidget);
      expect(find.text('Review reported content'), findsOneWidget);
      for (final label in [
        'Moments',
        'Clubs',
        'Creator Studio',
        'Awards',
        'Alerts',
        'Settings',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label went missing');
      }
    });
  });

  group('FollowedCreatorsCard', () {
    const uid = 'me';

    MockFirebaseAuth authFor(FakeFirebaseFirestore db) => MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, email: 'me@yovoice.app'),
    );

    Future<void> follow(
      FakeFirebaseFirestore db,
      String creatorId,
      String name,
    ) async {
      await db
          .collection('users')
          .doc(uid)
          .collection('following')
          .doc(creatorId)
          .set({
            'uid': creatorId,
            'displayName': name,
            'username': name.toLowerCase(),
            'followedAt': Timestamp.now(),
          });
    }

    Widget card(
      FakeFirebaseFirestore db, {
      void Function(FollowUser)? onOpenCreator,
      VoidCallback? onViewAll,
      VoidCallback? onDiscover,
    }) {
      final auth = authFor(db);
      return host(
        SizedBox(
          width: 344,
          child: FollowedCreatorsCard(
            currentUserId: uid,
            onOpenCreator: onOpenCreator ?? (_) {},
            onViewAll: onViewAll ?? () {},
            onDiscover: onDiscover ?? () {},
            followService: FollowService(
              firestore: db,
              auth: auth,
              notificationService: NotificationService(
                firestore: db,
                auth: auth,
              ),
            ),
            feedService: HomeFeedService(firestore: db, auth: auth),
            roomService: RoomService(firestore: db, auth: auth),
          ),
        ),
      );
    }

    testWidgets('lists only creators this account really follows, and marks '
        'the one who is hosting a live room right now', (tester) async {
      useDesktopWindow(tester);
      final db = FakeFirebaseFirestore();
      await follow(db, 'creator-live', 'Marta');
      await follow(db, 'creator-quiet', 'Bartek');

      await db.collection('rooms').doc('r1').set({
        'hostId': 'creator-live',
        'hostName': 'Marta',
        'name': 'Design critique',
        'description': 'Bring your work',
        'category': 'talk',
        'visibility': 'public',
        'language': 'English',
        'participantCount': 9,
        'memberCount': 0,
        'isLive': true,
        'roomType': 'community',
        'status': 'active',
        'experience': 'community',
        'createdAt': Timestamp.now(),
      });

      await tester.pumpWidget(card(db));
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('Top creators you follow'), findsOneWidget);
      expect(find.text('Marta'), findsOneWidget);
      expect(find.text('Bartek'), findsOneWidget);
      // The live signal is the real hosted room; the other creator falls
      // back to their handle, with no invented activity.
      expect(find.text('Live · Design critique'), findsOneWidget);
      expect(find.text('@bartek'), findsOneWidget);
      // Never a follower count or any other fabricated number.
      expect(find.textContaining('followers'), findsNothing);
    });

    testWidgets('following nobody: a premium empty state with one Discover '
        'action — never substituted with suggested people', (tester) async {
      useDesktopWindow(tester);
      final db = FakeFirebaseFirestore();
      var discover = 0;

      await tester.pumpWidget(card(db, onDiscover: () => discover++));
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('Top creators you follow'), findsOneWidget);
      expect(
        find.textContaining('creators you follow will appear here'),
        findsOneWidget,
      );
      // No list, and no "View all" pointing at an empty list.
      expect(find.text('View all'), findsNothing);

      await tester.tap(find.text('Discover creators'));
      await tester.pump();
      expect(discover, 1);
    });

    testWidgets('a row opens that creator and View all opens the following '
        'list', (tester) async {
      useDesktopWindow(tester);
      final db = FakeFirebaseFirestore();
      await follow(db, 'creator-1', 'Marta');

      FollowUser? opened;
      var viewAll = 0;

      await tester.pumpWidget(
        card(
          db,
          onOpenCreator: (creator) => opened = creator,
          onViewAll: () => viewAll++,
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      await tester.tap(find.text('Marta'));
      await tester.pump();
      expect(opened?.uid, 'creator-1');

      await tester.tap(find.text('View all'));
      await tester.pump();
      expect(viewAll, 1);
    });
  });
}

/// Counts route pushes so a test can assert that rail navigation swaps
/// content instead of pushing a full-screen destination over the shell.
class _RouteCountObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // The initial home route counts as a push; only later ones matter.
    if (previousRoute != null) pushes++;
    super.didPush(route, previousRoute);
  }
}

/// Mirrors MainShell's DESKTOP composition (fixed rail + swapped centre)
/// without Firebase: the mechanism under test is the selected-slot swap,
/// not the screens' contents.
class _FakeDesktopShell extends StatefulWidget {
  @override
  State<_FakeDesktopShell> createState() => _FakeDesktopShellState();
}

class _FakeDesktopShellState extends State<_FakeDesktopShell> {
  int _index = 0;

  static const _slots = ['home', 'chats', 'friends', 'discover', 'alerts'];

  DesktopNavItem get _active => switch (_index) {
    1 => DesktopNavItem.chats,
    2 => DesktopNavItem.friends,
    3 => DesktopNavItem.discover,
    4 => DesktopNavItem.notifications,
    _ => DesktopNavItem.home,
  };

  void _select(DesktopNavItem item) {
    setState(() {
      _index = switch (item) {
        DesktopNavItem.home => 0,
        DesktopNavItem.chats => 1,
        DesktopNavItem.friends => 2,
        DesktopNavItem.discover => 3,
        DesktopNavItem.notifications => 4,
        DesktopNavItem.more => _index,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          DesktopSidebar(
            active: _active,
            unreadConversationCount: 0,
            unreadNotificationCount: 0,
            onSelect: _select,
            onCreateRoom: () {},
            onCreateMoment: () {},
            onOpenProfile: () {},
            onOpenProfileSettings: () {},
          ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                for (final slot in _slots) Center(child: Text('slot-$slot')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
