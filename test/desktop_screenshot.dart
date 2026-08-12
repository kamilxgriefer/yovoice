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
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_home.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/desktop_sidebar.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/premium_desktop_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/voice_trending_card.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

const String _me = 'preview-me';
const String _fontRoot =
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts';

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
    ('Late Night Confessions', 'Real stories, live now'),
    ('Friday Freestyle', 'The room is warming up'),
  ].indexed) {
    await db.collection('rooms').doc('room-${entry.$1}').set(<String, dynamic>{
      'hostId': 'host',
      'hostName': 'Host',
      'name': entry.$2.$1,
      'description': entry.$2.$2,
      'category': 'talk',
      'visibility': 'public',
      'language': 'English',
      'participantCount': 4 + entry.$1,
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
  return db;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _shoot(String name) async {
  final boundary =
      _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('test/.screenshots/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote ${file.path}');
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
      await tester.tap(find.text('7 in the room'));
      await _settle(tester);
      await _shoot('roster-${size.width.toInt()}x${size.height.toInt()}');
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
      await _shoot(label);
    });
  }
}
