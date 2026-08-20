// Developer-only VISUAL harness for the DESKTOP right column and rail.
//
// Same reason as test/moderation_screenshot.dart: the in-app browser
// cannot rasterise Flutter's CanvasKit output, so layout claims are
// proven from the widget layer instead — real widgets, real fonts, exact
// viewport.
//
// NOT a test; the name has no `_test` suffix so `flutter test` skips it.
// Run explicitly:
//
//   flutter test test/desktop_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/premium_desktop_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/voice_trending_card.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/data/services/room_experience_service.dart';
import 'package:yovoice/features/rooms/data/services/room_image_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/create_room_screen.dart';

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

Future<FakeFirebaseFirestore> _seed({required bool live}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc(_me).set(<String, dynamic>{
    'uid': _me,
    'displayName': 'CeoGriefer',
    'username': 'ceogriefer',
  });
  if (!live) return db;

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
      'participantCount': [2400, 1800, 782][entry.$1],
      'memberCount': 0,
      'isLive': true,
      'roomType': 'community',
      'status': 'active',
      'experience': 'community',
      'createdAt': Timestamp.fromDate(
        DateTime.now().subtract(Duration(minutes: 3 + entry.$1 * 9)),
      ),
    });
    final people = db
        .collection('rooms')
        .doc('room-${entry.$1}')
        .collection('participants');
    for (final (index, name) in ['Ola', 'Marek', 'Zosia', 'Piotr'].indexed) {
      await people.doc('p$index').set(<String, dynamic>{
        'userId': 'p$index',
        'displayName': name,
        'role': index == 0 ? 'host' : 'listener',
        'isMuted': index != 0,
        'isSpeaker': index == 0,
      });
    }
  }
  for (final (index, name) in ['Sieeema', 'Ola', 'Marek'].indexed) {
    final otherId = 'chat-friend-$index';
    await db.collection('conversations').doc('preview-chat-$index').set({
      'participantIds': [_me, otherId],
      'participantNames': {_me: 'CeoGriefer', otherId: name},
      'participantEmails': {
        _me: 'me@yovoice.app',
        otherId: '$name@yovoice.app',
      },
      'participantPhotoUrls': <String, String>{},
      'unreadCounts': {_me: index == 0 ? 2 : 0, otherId: 0},
      'lastMessage': [
        'Are you joining?',
        'That was fun',
        'Voice later?',
      ][index],
      'lastMessageType': 'text',
      'lastMessageSenderId': otherId,
      'updatedAt': Timestamp.fromDate(
        DateTime.now().subtract(Duration(minutes: index + 1)),
      ),
      'createdAt': Timestamp.now(),
      'archivedBy': <String>[],
      'mutedBy': <String>[],
    });
  }
  return db;
}

/// Two friends and a Moment — enough for the rail to show a ringed tile,
/// an online dot, the divider and a Follow action.
Future<void> _seedCircle(FakeFirebaseFirestore db) async {
  for (final (index, name) in ['Sieeema', 'testGriefer'].indexed) {
    final id = 'friend-$index';
    await db.collection('users').doc(id).set(<String, dynamic>{
      'uid': id,
      'displayName': name,
      'username': name.toLowerCase(),
      'isOnline': true,
      'premiumIdentity': index == 1,
    });
    await db.collection('users').doc(_me).collection('friends').doc(id).set(
      <String, dynamic>{'friendId': id, 'createdAt': Timestamp.now()},
    );
  }
  await db.collection('voiceMoments').doc('m1').set(<String, dynamic>{
    'authorId': 'friend-0',
    'authorName': 'Sieeema',
    'caption': 'Morning thoughts',
    'audioUrl': 'https://example.invalid/m1.m4a',
    'durationSeconds': 42,
    'likeCount': 0,
    'commentCount': 0,
    'isPublished': true,
    'createdAt': Timestamp.fromDate(
      DateTime.now().subtract(const Duration(minutes: 30)),
    ),
  });
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

void main() {
  setUpAll(_loadRealFonts);

  // Roster-open captures. The -150 MenuAnchor offset has never been seen
  // rendered; these exist to look at it at each supported width.
  for (final size in const [
    Size(1920, 1080),
    Size(1440, 900),
    Size(1366, 768),
    Size(1100, 800),
  ]) {
    testWidgets('roster-${size.width.toInt()}x${size.height.toInt()}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'me', displayName: 'Me'),
      );
      await db.collection('users').doc('me').set(<String, dynamic>{
        'uid': 'me',
        'displayName': 'Me',
      });
      await db.collection('rooms').doc('r1').set(<String, dynamic>{
        'hostId': 'host',
        'hostName': 'Hosty',
        'name': 'what is going on',
        'description': 'haha yes',
        'category': 'talk',
        'visibility': 'public',
        'language': 'English',
        'participantCount': 7,
        'memberCount': 0,
        'isLive': true,
        'roomType': 'community',
        'status': 'active',
        'experience': 'community',
        'createdAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 4)),
        ),
      });
      final people = db
          .collection('rooms')
          .doc('r1')
          .collection('participants');
      await people.doc('host').set(<String, dynamic>{
        'userId': 'host',
        'displayName': 'Hosty McLongnameThatKeepsGoing',
        'role': 'host',
        'isMuted': false,
        'isSpeaker': true,
      });
      await people.doc('mod').set(<String, dynamic>{
        'userId': 'mod',
        'displayName': 'Moddy',
        'role': 'moderator',
        'isMuted': false,
        'isSpeaker': true,
      });
      for (var i = 0; i < 5; i++) {
        await people.doc('l$i').set(<String, dynamic>{
          'userId': 'l$i',
          'displayName': 'Listener number $i with a long name',
          'role': 'listener',
          'isMuted': true,
          'isSpeaker': false,
        });
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: _capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              useMaterial3: true,
              fontFamily: 'Roboto',
            ),
            home: Scaffold(
              backgroundColor: const Color(0xFF080711),
              body: DesktopHome(
                currentUserId: 'me',
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
                roomService: RoomService(firestore: db, auth: auth),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.byTooltip('See who is in the room'));
      await _settle(tester);
      await _shoot(
        tester,
        'roster-${size.width.toInt()}x${size.height.toInt()}',
      );
    });
  }

  // The rail plus the full right column, at each width that matters:
  // a normal laptop, a wide desktop, and the narrowest width still
  // classified as desktop (the shell's breakpoint is 1100).
  for (final (size, live) in const [
    (Size(1440, 900), true),
    (Size(1920, 1000), true),
    (Size(1100, 900), true),
    (Size(1440, 900), false), // the empty states
  ]) {
    final label =
        'desktop-${size.width.toInt()}x${size.height.toInt()}'
        '${live ? '' : '-empty'}';

    testWidgets(label, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final db = await _seed(live: live);
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _me, displayName: 'CeoGriefer'),
      );

      await tester.pumpWidget(
        RepaintBoundary(
          key: _capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              useMaterial3: true,
              fontFamily: 'Roboto',
            ),
            home: Scaffold(
              backgroundColor: const Color(0xFF080711),
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DesktopSidebar(
                    active: DesktopNavItem.home,
                    unreadConversationCount: 4,
                    unreadNotificationCount: 2,
                    onSelect: (_) {},
                    onCreateRoom: () {},
                    onCreateMoment: () {},
                    onOpenProfile: () {},
                    onOpenProfileSettings: () {},
                    profileService: ProfileService(firestore: db, auth: auth),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: SizedBox(
                      width: 320,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VoiceTrendingCard(
                            roomService: RoomService(firestore: db, auth: auth),
                            onOpenRoom: (_) {},
                            onSeeAll: () {},
                            onSeeAllRooms: () {},
                          ),
                          const SizedBox(height: 14),
                          PremiumDesktopCard(onCheckPlans: () {}),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      await _shoot(tester, label);
    });
  }
  // The Home surface itself — the room board, the People & Moments rail,
  // Your active rooms and recent private chats — at the desktop widths
  // that matter and at phone size.
  for (final size in const [
    Size(1440, 900),
    Size(1100, 900),
    Size(1440, 1800),
  ]) {
    final label = 'home-${size.width.toInt()}x${size.height.toInt()}';
    testWidgets(label, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final db = await _seed(live: true);
      await _seedCircle(db);
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _me, displayName: 'CeoGriefer'),
      );

      await tester.pumpWidget(
        RepaintBoundary(
          key: _capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              useMaterial3: true,
              fontFamily: 'Roboto',
            ),
            home: Scaffold(
              backgroundColor: const Color(0xFF080711),
              body: DesktopHome(
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
                roomService: RoomService(firestore: db, auth: auth),
                friendService: FriendService(firestore: db, auth: auth),
                followService: FollowService(firestore: db, auth: auth),
                capabilityService: _OwnerCapabilities(),
                profileService: ProfileService(firestore: db, auth: auth),
                feedService: HomeFeedService(firestore: db, auth: auth),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      await _shoot(tester, label);
    });
  }

  testWidgets('home-mobile-390x844', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = await _seed(live: true);
    await _seedCircle(db);
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: _me, displayName: 'CeoGriefer'),
    );

    await tester.pumpWidget(
      RepaintBoundary(
        key: _capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            fontFamily: 'Roboto',
          ),
          home: Scaffold(
            backgroundColor: const Color(0xFF080711),
            body: MobileHome(
              currentUserId: _me,
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
              roomService: RoomService(firestore: db, auth: auth),
              friendService: FriendService(firestore: db, auth: auth),
              profileService: ProfileService(firestore: db, auth: auth),
              feedService: HomeFeedService(firestore: db, auth: auth),
              messageService: MessageService(firestore: db, auth: auth),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    await _shoot(tester, 'home-mobile-390x844');
  });
  // The two creation wizards, at phone width and desktop, so the
  // identity colours and the step layout are looked at rather than
  // merely asserted.
  for (final (label, size, experience) in <(String, Size, RoomExperience)>[
    ('create-community-390', Size(390, 900), RoomExperience.community),
    ('create-podcast-390', Size(390, 900), RoomExperience.broadcast),
    ('create-community-1440', Size(1440, 900), RoomExperience.community),
  ]) {
    testWidgets(label, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: _me, displayName: 'CeoGriefer'),
      );

      await tester.pumpWidget(
        RepaintBoundary(
          key: _capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              useMaterial3: true,
              fontFamily: 'Roboto',
            ),
            home: CreateRoomScreen(
              experience: experience,
              roomService: RoomService(firestore: db, auth: auth),
              imageService: RoomImageService(
                auth: auth,
                storage: MockFirebaseStorage(),
              ),
              experienceService: RoomExperienceService(
                firestore: db,
                auth: auth,
                notificationService: NotificationService(
                  firestore: db,
                  auth: auth,
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      await _shoot(tester, label);
    });
  }
}

/// Screenshot-only: the owner's capability set, so the crimson shield is
/// visible in the capture without any network.
class _OwnerCapabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      const StaffCapabilities(
        staffRole: 'superAdmin',
        isOwner: true,
        permanentDeleteSpaces: true,
        quarantineSpaces: true,
        endAnyRoom: true,
        endPublicRoomWithReason: true,
      );
}
