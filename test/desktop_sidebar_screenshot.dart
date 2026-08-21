// Developer-only VISUAL harness for the redesigned DESKTOP SIDEBAR.
//
// Same reason as test/desktop_screenshot.dart: the in-app browser cannot
// rasterise Flutter's CanvasKit output, so layout claims are proven from
// the widget layer instead — real widgets, real fonts, exact viewport,
// and REAL seeded Firestore data behind every number on screen (the bell
// badge counts seeded notification documents through the production
// NotificationService; the Chats badge counts seeded conversations
// through the production MessageService).
//
// NOT a test; the name has no `_test` suffix so `flutter test` skips it.
// Run explicitly:
//
//   flutter test test/desktop_sidebar_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/more_sheet.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

const String _me = 'preview-me';

String get _fontRoot {
  const candidates = [
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ];
  return candidates.firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
  );
}

final _capture = GlobalKey();

Future<void> _loadRealFonts() async {
  Future<ByteData> read(String name) async {
    final bytes = File('$_fontRoot/$name').readAsBytesSync();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  final roboto = FontLoader('Roboto');
  for (final face in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]) {
    roboto.addFont(read(face));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

/// Seeds the signed-in profile, three live rooms (for a real Home feed
/// behind the rail), one conversation with unread messages (the Chats
/// badge) and three unread notification documents (the bell badge).
Future<FakeFirebaseFirestore> _seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc(_me).set(<String, dynamic>{
    'uid': _me,
    'displayName': 'CeoGriefer',
    'username': 'ceogriefer',
  });

  for (final entry in [
    (
      'Late Night Creators',
      'Deep conversations and creative energy. Connect, share and inspire.',
    ),
    (
      'Gaming After Hours',
      'Chill gaming sessions, strategy talks and good vibes.',
    ),
    (
      'Polish Coffee Talk',
      'Friendly talks in Polish over coffee. Share stories and meet people.',
    ),
  ].indexed) {
    await db.collection('rooms').doc('room-${entry.$1}').set(<String, dynamic>{
      'hostId': entry.$1 == 0 ? _me : 'host',
      'hostName': entry.$1 == 0 ? 'CeoGriefer' : 'Host',
      'name': entry.$2.$1,
      'description': entry.$2.$2,
      'category': ['Talk', 'Gaming', 'Talk'][entry.$1],
      'visibility': 'public',
      'language': entry.$1 == 2 ? 'Polish' : 'English',
      'participantCount': [24, 18, 7][entry.$1],
      'memberCount': 0,
      'isLive': true,
      'roomType': 'community',
      'status': 'active',
      'experience': 'community',
      'createdAt': Timestamp.fromDate(
        DateTime.now().subtract(Duration(minutes: 3 + entry.$1 * 9)),
      ),
    });
  }

  // One conversation with unread messages -> Chats badge shows 1
  // (MainShell counts conversations with unread, not messages).
  await db.collection('conversations').doc('preview-chat-0').set({
    'participantIds': [_me, 'chat-friend'],
    'participantNames': {_me: 'CeoGriefer', 'chat-friend': 'Sieeema'},
    'participantEmails': {
      _me: 'me@yovoice.app',
      'chat-friend': 'sieeema@yovoice.app',
    },
    'participantPhotoUrls': <String, String>{},
    'unreadCounts': {_me: 2, 'chat-friend': 0},
    'lastMessage': 'Are you joining?',
    'lastMessageType': 'text',
    'lastMessageSenderId': 'chat-friend',
    'updatedAt': Timestamp.now(),
    'createdAt': Timestamp.now(),
    'archivedBy': <String>[],
    'mutedBy': <String>[],
  });

  // Three REAL unread notification documents — the bell badge is the
  // production NotificationService counting these, not a passed-in int.
  for (final (index, seed) in const [
    ('friendRequest', 'Sieeema'),
    ('follow', 'Marek'),
    ('liveStarted', 'Ola'),
  ].indexed) {
    await db
        .collection('users')
        .doc(_me)
        .collection('notifications')
        .doc('n$index')
        .set(<String, dynamic>{
          'type': seed.$1,
          'actorId': 'actor-$index',
          'actorName': seed.$2,
          'isRead': false,
          'createdAt': Timestamp.fromDate(
            DateTime.now().subtract(Duration(minutes: index * 7 + 2)),
          ),
        });
  }
  return db;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('test/.screenshots/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

Widget _app(Widget child) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.darkTheme,
    home: child,
  ),
);

Finder _homeScrollable() => find
    .descendant(of: find.byType(DesktopHome), matching: find.byType(Scrollable))
    .first;

Finder _railScrollable() => find
    .descendant(
      of: find.byType(DesktopSidebar),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  setUpAll(_loadRealFonts);

  Future<void> pumpShell(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = await _seed();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _me, displayName: 'CeoGriefer'),
    );
    await tester.pumpWidget(_app(_HarnessShell(db: db, auth: auth)));
    // Asset decoding is real async work: without an explicit precache the
    // FIRST capture of a run races the logo decode and photographs the
    // wordmark without its mark.
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/logo.png'),
        tester.element(find.byType(DesktopSidebar)),
      ),
    );
    await _settle(tester);
  }

  // ── Default rail with REAL badge data at each supported width ──────
  for (final size in const [
    Size(1280, 800),
    Size(1440, 900),
    Size(2560, 1200),
  ]) {
    final label = 'sidebar-${size.width.toInt()}x${size.height.toInt()}';
    testWidgets(label, (tester) async {
      await pumpShell(tester, size);

      // The bell badge is the count of the three seeded unread
      // notification docs, delivered by the production service.
      expect(find.text('3'), findsOneWidget);
      // One conversation carries unread messages -> Chats badge "1".
      expect(find.text('1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _shoot(tester, label);
    });
  }

  // ── Selected states: two different tabs, plus the active bell ─────
  testWidgets('sidebar selected states', (tester) async {
    await pumpShell(tester, const Size(1440, 900));

    await tester.tap(find.text('Chats'));
    await _settle(tester);
    await _shoot(tester, 'sidebar-selected-chats-1440x900');

    await tester.tap(find.text('Discover'));
    await _settle(tester);
    await _shoot(tester, 'sidebar-selected-discover-1440x900');

    await tester.tap(find.byTooltip('Notifications'));
    await _settle(tester);
    await _shoot(tester, 'sidebar-notifications-active-1440x900');
  });

  // ── The More POPOVER, open — and Home content must not move ────────
  testWidgets('more popover keeps home content still', (tester) async {
    await pumpShell(tester, const Size(1440, 900));

    // Scroll the Home feed so a non-zero offset can prove itself.
    await tester.drag(_homeScrollable(), const Offset(0, -140));
    await _settle(tester);

    final scrollable = tester.state<ScrollableState>(_homeScrollable());
    final offsetBefore = scrollable.position.pixels;
    final homeTopLeftBefore = tester.getTopLeft(find.byType(DesktopHome));
    expect(offsetBefore, greaterThan(0));

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    // The popover is an overlay: every entry visible, and the page
    // behind it neither scrolled nor shifted nor resized.
    for (final label in [
      'Clubs',
      'Creator Studio',
      'Awards',
      'Alerts',
      'Settings',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label missing');
    }
    expect(
      tester.state<ScrollableState>(_homeScrollable()).position.pixels,
      offsetBefore,
      reason: 'opening the popover must not scroll the page',
    );
    expect(
      tester.getTopLeft(find.byType(DesktopHome)),
      homeTopLeftBefore,
      reason: 'opening the popover must not move or resize Home',
    );
    await _shoot(tester, 'sidebar-more-popover-1440x900');
  });

  // ── SHORT viewport: the rail scrolls INTERNALLY, nothing overflows ─
  testWidgets('short viewport scrolls internally', (tester) async {
    await pumpShell(tester, const Size(1280, 620));

    expect(tester.takeException(), isNull, reason: 'no overflow at 620px');
    // Pinned edges: header bell on top, profile card at the bottom.
    expect(find.byTooltip('Notifications'), findsOneWidget);
    expect(find.byTooltip('Profile settings'), findsOneWidget);
    await _shoot(tester, 'sidebar-short-1280x620');

    // The middle section reaches the More row by its OWN scroll.
    await tester.drag(_railScrollable(), const Offset(0, -220));
    await _settle(tester);
    expect(find.text('More'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _shoot(tester, 'sidebar-short-1280x620-scrolled');
  });
}

/// Mirrors MainShell's DESKTOP composition for the rail under test: the
/// sidebar's unread counts come from the SAME production streams the
/// shell subscribes to (NotificationService.watchUnreadCount and
/// MessageService.watchConversations over seeded documents), selection
/// swaps content in place, and the More row opens the real
/// showDesktopMoreMenu anchored to the rail item.
class _HarnessShell extends StatefulWidget {
  const _HarnessShell({required this.db, required this.auth});

  final FakeFirebaseFirestore db;
  final MockFirebaseAuth auth;

  @override
  State<_HarnessShell> createState() => _HarnessShellState();
}

class _HarnessShellState extends State<_HarnessShell> {
  final GlobalKey _moreItemKey = GlobalKey();
  DesktopNavItem _active = DesktopNavItem.home;

  late final NotificationService _notifications = NotificationService(
    firestore: widget.db,
    auth: widget.auth,
  );
  late final MessageService _messages = MessageService(
    firestore: widget.db,
    auth: widget.auth,
  );

  Future<void> _select(DesktopNavItem item) async {
    if (item == DesktopNavItem.more) {
      final box = _moreItemKey.currentContext?.findRenderObject() as RenderBox?;
      final anchor = box == null
          ? const Offset(16, 320)
          : box.localToGlobal(Offset(box.size.width - 8, 0));
      await showDesktopMoreMenu(context, anchor: anchor);
      return;
    }
    setState(() => _active = item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080711),
      body: Row(
        children: [
          StreamBuilder<int>(
            stream: _notifications.watchUnreadCount(),
            initialData: 0,
            builder: (context, unreadNotifications) {
              return StreamBuilder<List<Conversation>>(
                stream: _messages.watchConversations(includeArchived: true),
                initialData: const [],
                builder: (context, conversations) {
                  final unreadConversations = (conversations.data ?? const [])
                      .where((c) => c.unreadCountFor(_me) > 0)
                      .length;
                  return DesktopSidebar(
                    moreItemKey: _moreItemKey,
                    active: _active,
                    unreadConversationCount: unreadConversations,
                    unreadNotificationCount: unreadNotifications.data ?? 0,
                    onSelect: _select,
                    onCreateRoom: () {},
                    onCreateMoment: () {},
                    onOpenProfile: () {},
                    onOpenProfileSettings: () {},
                    profileService: ProfileService(
                      firestore: widget.db,
                      auth: widget.auth,
                    ),
                  );
                },
              );
            },
          ),
          Expanded(
            child: ResponsiveContentFrame(
              width: ResponsiveContentWidth.workbench,
              child: _active == DesktopNavItem.home
                  ? DesktopHome(
                      currentUserId: _me,
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
                      roomService: RoomService(
                        firestore: widget.db,
                        auth: widget.auth,
                      ),
                      friendService: FriendService(
                        firestore: widget.db,
                        auth: widget.auth,
                      ),
                      followService: FollowService(
                        firestore: widget.db,
                        auth: widget.auth,
                      ),
                      profileService: ProfileService(
                        firestore: widget.db,
                        auth: widget.auth,
                      ),
                      feedService: HomeFeedService(
                        firestore: widget.db,
                        auth: widget.auth,
                      ),
                    )
                  // The harness photographs the RAIL; non-Home slots keep
                  // the shell's dark canvas rather than mounting screens
                  // whose services are out of scope here.
                  : const ColoredBox(color: Color(0xFF080711)),
            ),
          ),
        ],
      ),
    );
  }
}
