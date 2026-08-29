// Developer-only visual harness for the semantic Home + mobile dock theme.
//
// Run explicitly:
//   flutter test test/home_light_theme_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored). This is deliberately not
// named *_test.dart, so the regular suite does not generate artifacts.

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
import 'package:yovoice/features/home/presentation/widgets/desktop/followed_creators_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/premium_desktop_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/sponsored_card.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/voice_trending_card.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home.dart';
import 'package:yovoice/features/home/presentation/widgets/navigation/yo_floating_navigation_dock.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/staff/data/staff_capabilities.dart';

const _me = 'preview-me';
final _capture = GlobalKey();

String get _fontRoot =>
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts';

Future<void> _loadRealFonts() async {
  Future<ByteData> read(String name) async {
    final bytes = File('$_fontRoot/$name').readAsBytesSync();
    return ByteData.view(bytes.buffer);
  }

  final inter = FontLoader('Inter')
    ..addFont(
      Future.value(
        ByteData.view(
          File('assets/fonts/InterVariable.ttf').readAsBytesSync().buffer,
        ),
      ),
    )
    ..addFont(
      Future.value(
        ByteData.view(
          File(
            'assets/fonts/InterVariable-Italic.ttf',
          ).readAsBytesSync().buffer,
        ),
      ),
    );
  await inter.load();

  final icons = FontLoader('MaterialIcons')
    ..addFont(read('MaterialIcons-Regular.otf'));
  await icons.load();
}

enum _FeedState { populated, empty, error }

class _FailingRoomService extends RoomService {
  _FailingRoomService({super.firestore, super.auth});

  @override
  Stream<List<VoiceRoom>> watchLivePublicRooms() =>
      Stream<List<VoiceRoom>>.error(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Missing or insufficient permissions.',
        ),
      );
}

class _NoCapabilities extends StaffCapabilityService {
  @override
  Future<StaffCapabilities> load({bool refresh = false}) async =>
      StaffCapabilities.none;
}

Future<FakeFirebaseFirestore> _seed(_FeedState state) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc(_me).set(<String, dynamic>{
    'uid': _me,
    'displayName': 'CeoGriefer',
    'username': 'ceogriefer',
    'email': 'preview@yovoice.app',
  });
  if (state != _FeedState.populated) return db;

  for (final entry in [
    (
      'Late Night Creators',
      'Deep conversations and creative energy. Connect, share and inspire.',
    ),
    (
      'Gaming After Hours',
      'Chill gaming sessions, strategy talks and good vibes.',
    ),
  ].indexed) {
    final id = 'room-${entry.$1}';
    await db.collection('rooms').doc(id).set(<String, dynamic>{
      'hostId': entry.$1 == 0 ? _me : 'host-${entry.$1}',
      'hostName': entry.$1 == 0 ? 'CeoGriefer' : 'Host',
      'name': entry.$2.$1,
      'description': entry.$2.$2,
      'category': entry.$1 == 0 ? 'Talk' : 'Gaming',
      'visibility': 'public',
      'language': 'English',
      'participantCount': entry.$1 == 0 ? 2400 : 782,
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

  for (final (index, name) in ['Sieeema', 'Ola', 'Marek'].indexed) {
    final otherId = 'chat-friend-$index';
    await db.collection('conversations').doc('preview-chat-$index').set(
      <String, dynamic>{
        'participantIds': [_me, otherId],
        'participantNames': {_me: 'CeoGriefer', otherId: name},
        'participantEmails': {
          _me: 'me@yovoice.app',
          otherId: '$otherId@yovoice.app',
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
      },
    );
  }

  const friendId = 'friend-with-moment';
  await db.collection('users').doc(friendId).set(<String, dynamic>{
    'uid': friendId,
    'displayName': 'Sieeema',
    'username': 'sieeema',
  });
  await db.collection('publicProfiles').doc(friendId).set(<String, dynamic>{
    'uid': friendId,
    'displayName': 'Sieeema',
    'username': 'sieeema',
    'photoUrl': null,
  });
  await db
      .collection('users')
      .doc(_me)
      .collection('following')
      .doc(friendId)
      .set(<String, dynamic>{'uid': friendId, 'followedAt': Timestamp.now()});
  await db.collection('voiceMoments').doc('moment-1').set(<String, dynamic>{
    'authorId': friendId,
    'authorName': 'Sieeema',
    'audioUrl': 'https://example.invalid/moment.m4a',
    'durationSeconds': 42,
    'likeCount': 0,
    'commentCount': 0,
    'isPublished': true,
    'createdAt': Timestamp.fromDate(
      DateTime.now().subtract(const Duration(minutes: 30)),
    ),
    'expiresAt': Timestamp.fromDate(
      DateTime.now().add(const Duration(hours: 23)),
    ),
  });
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
    // Prime the raster cache before taking the evidence frame. A single
    // first toImage call can otherwise be the operation that uploads the
    // font atlas / clipped asset layer in headless Flutter, leaving an
    // intermittent blank label or logo in that same frame.
    final warmup = await boundary.toImage(pixelRatio: 1);
    warmup.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final image = await boundary.toImage(pixelRatio: 1);
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

Widget _home({
  required FakeFirebaseFirestore db,
  required MockFirebaseAuth auth,
  required RoomService rooms,
  required bool desktop,
}) {
  final profiles = ProfileService(firestore: db, auth: auth);
  final follows = FollowService(firestore: db, auth: auth);
  final feed = HomeFeedService(firestore: db, auth: auth);
  final messages = MessageService(firestore: db, auth: auth);
  final capabilities = _NoCapabilities();

  if (desktop) {
    return DesktopHome(
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
      roomService: rooms,
      friendService: FriendService(firestore: db, auth: auth),
      followService: follows,
      profileService: profiles,
      feedService: feed,
      messageService: messages,
      firebaseAuth: auth,
      capabilityService: capabilities,
    );
  }

  return MobileHome(
    onOpenRoom: (_) {},
    onOpenDiscover: () {},
    onOpenFriends: () {},
    onOpenNotifications: () {},
    unreadNotificationCount: 3,
    onOpenProfile: () {},
    onCreateMoment: () {},
    onCreateRoom: () {},
    onOpenMoment: (_) {},
    onOpenComments: (_) {},
    onOpenConversation: (_) {},
    onSeeAllChats: () {},
    roomService: rooms,
    friendService: FriendService(firestore: db, auth: auth),
    followService: follows,
    profileService: profiles,
    feedService: feed,
    messageService: messages,
    capabilityService: capabilities,
    currentUserId: _me,
  );
}

Future<void> _render(
  WidgetTester tester, {
  required Size size,
  required Brightness brightness,
  required _FeedState state,
  required double textScale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  ProfileService.resetCurrentProfileCache();

  final db = await _seed(state);
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: _me, displayName: 'CeoGriefer'),
  );
  final rooms = state == _FeedState.error
      ? _FailingRoomService(firestore: db, auth: auth)
      : RoomService(firestore: db, auth: auth);
  final desktop = size.width >= 1100;

  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: _home(db: db, auth: auth, rooms: rooms, desktop: desktop),
            bottomNavigationBar: desktop
                ? null
                : YoFloatingNavigationDock(
                    selectedTabIndex: 0,
                    momentsTabIndex: 5,
                    unreadConversationCount: 7,
                    onDestinationSelected: (_) {},
                    onVoicePressed: () {},
                    onMorePressed: () {},
                  ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/images/logo.png'),
      _capture.currentContext!,
    ),
  );
  await tester.pump();
  // Font shaping and asset decode happen on the real async queue. Giving
  // them one short turn makes the PNG deterministic when every viewport is
  // generated in one process instead of only one selected test.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

/// The actual Pearl desktop chrome at the shipping 1440x900 viewport:
/// fixed [DesktopSidebar], live Home content and the same four modules
/// MainShell installs in its 344px right column. Kept separate from [_render]
/// so none of the existing Home evidence frames changes composition.
Future<void> _renderPearlDesktopShellChrome(WidgetTester tester) async {
  const size = Size(1440, 900);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  ProfileService.resetCurrentProfileCache();

  final db = await _seed(_FeedState.populated);
  final auth = MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: _me, displayName: 'CeoGriefer'),
  );
  final rooms = RoomService(firestore: db, auth: auth);
  final profiles = ProfileService(firestore: db, auth: auth);
  final follows = FollowService(firestore: db, auth: auth);
  final feed = HomeFeedService(firestore: db, auth: auth);

  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DesktopSidebar(
                  active: DesktopNavItem.home,
                  unreadConversationCount: 7,
                  unreadNotificationCount: 3,
                  onSelect: (_) {},
                  onCreateRoom: () {},
                  onCreateMoment: () {},
                  onOpenProfile: () {},
                  onOpenProfileSettings: () {},
                  profileService: profiles,
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _home(
                          db: db,
                          auth: auth,
                          rooms: rooms,
                          desktop: true,
                        ),
                      ),
                      SizedBox(
                        width: 344,
                        child: ListView(
                          primary: false,
                          padding: const EdgeInsets.fromLTRB(6, 20, 20, 20),
                          children: [
                            FollowedCreatorsCard(
                              currentUserId: _me,
                              onOpenCreator: (_) {},
                              onViewAll: () {},
                              followService: follows,
                              feedService: feed,
                              roomService: rooms,
                            ),
                            const SizedBox(height: 16),
                            VoiceTrendingCard(
                              onOpenRoom: (_) {},
                              onSeeAll: () {},
                              onSeeAllRooms: () {},
                              roomService: rooms,
                              discoveryService: MomentDiscoveryService(
                                firestore: db,
                                auth: auth,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const SponsoredCard(),
                            const SizedBox(height: 16),
                            PremiumDesktopCard(onCheckPlans: () {}),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/images/logo.png'),
      _capture.currentContext!,
    ),
  );
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(_loadRealFonts);

  final populated = <(Size, double)>[
    (const Size(320, 640), 2),
    (const Size(390, 844), 1),
    (const Size(768, 1024), 1),
    (const Size(1440, 900), 1),
  ];

  for (final brightness in Brightness.values) {
    for (final (size, textScale) in populated) {
      final mode = brightness.name;
      final label =
          'home-$mode-populated-${size.width.toInt()}x${size.height.toInt()}'
          '${textScale == 2 ? '-scale2' : ''}';
      testWidgets(label, (tester) async {
        await _render(
          tester,
          size: size,
          brightness: brightness,
          state: _FeedState.populated,
          textScale: textScale,
        );
        await _shoot(tester, label);
      });
    }
  }

  for (final state in [_FeedState.empty, _FeedState.error]) {
    for (final size in [const Size(390, 844), const Size(1440, 900)]) {
      final label =
          'home-light-${state.name}-${size.width.toInt()}x${size.height.toInt()}';
      testWidgets(label, (tester) async {
        await _render(
          tester,
          size: size,
          brightness: Brightness.light,
          state: state,
          textScale: 1,
        );
        await _shoot(tester, label);
      });
    }
  }

  testWidgets('pearl-desktop-shell-chrome-1440x900', (tester) async {
    await _renderPearlDesktopShellChrome(tester);
    await _shoot(tester, 'pearl-desktop-shell-chrome-1440x900');
  });
}
