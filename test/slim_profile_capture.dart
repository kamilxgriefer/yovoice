// Slim redesign phase 5 (Profil) frame harness.
//
// Renders the REAL own-profile page (`ProfileScreenView`, the widget
// `ProfileScreen` builds once its streams deliver) and the REAL
// `FriendProfileScreen` with fixture data through their constructor seams:
// no Firebase app, no network, no callable. Widths 390 and 1440, Dark and
// Pearl, locale pl, 100 % text, populated.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/slim_profile_capture.dart --concurrency=1 \
//     --dart-define=YO_CAPTURE_DIR=<evidence>/slim-p5-frames/after
//
// Frames are named `<screen>_<width>_<dark|pearl>_pl_100_populated.png`
// (`profile`, `friend-profile`) at the device viewport, plus a
// `..._populated-full.png` twin rendered on a tall viewport so every block
// below the fold is on one image.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/achievements/data/achievement_catalog.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friend_profile_screen.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'voice_moment_test_doubles.dart';

const _outDir = String.fromEnvironment(
  'YO_CAPTURE_DIR',
  defaultValue: 'test/.screenshots/slim-p5',
);

final _capture = GlobalKey();

/// The Material fonts of whichever Flutter SDK runs the test: walked up from
/// the tester binary, with the Mac install paths as fallbacks.
String get _fontRoot {
  final candidates = <String>[];
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    candidates.add('${dir.path}/bin/cache/artifacts/material_fonts');
    candidates.add('${dir.path}/material_fonts');
    dir = dir.parent;
  }
  candidates.addAll(const <String>[
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ]);
  return candidates.firstWhere(
    (path) => File('$path/Roboto-Regular.ttf').existsSync(),
  );
}

Future<void> _loadFonts() async {
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
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('MaterialIcons-Regular.otf'))).load();
  final inter = FontLoader('Inter');
  inter.addFont(
    Future.value(
      ByteData.view(
        Uint8List.fromList(
          File('assets/fonts/InterVariable.ttf').readAsBytesSync(),
        ).buffer,
      ),
    ),
  );
  await inter.load();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${file.path}');
    } finally {
      image.dispose();
    }
  });
}

void _recordException(WidgetTester tester, String name) {
  final error = tester.takeException();
  if (error != null) {
    // ignore: avoid_print
    print('EXCEPTION $name :: $error');
  }
}

MockFirebaseAuth _auth() => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: 'me', email: 'me@yovoice.app', isEmailVerified: true),
);

ProfileMediaService _media(MockFirebaseAuth auth) => ProfileMediaService(
  auth: auth,
  invoker: (_, _) async => {
    'schemaVersion': 1,
    'available': false,
    'expiresAtMillis': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch,
  },
);

PublicIdentityRepository _identity() => PublicIdentityRepository(
  auth: _auth(),
  fetchOverride: (uids) async => {
    for (final uid in uids) uid: const {'role': 'user'},
  },
  flushDelay: const Duration(milliseconds: 1),
);

Map<String, dynamic> _moment(String id, String authorId, String caption) {
  final createdAt = DateTime.now().subtract(const Duration(hours: 3));
  return {
    'id': id,
    'schemaVersion': 2,
    'status': 'published',
    'isDeleted': false,
    'authorId': authorId,
    'authorName': 'Autor',
    'authorPhotoUrl': null,
    'caption': caption,
    'audioUrl': 'https://example.invalid/$id.m4a',
    'durationSeconds': 42,
    'likeCount': 18,
    'commentCount': 4,
    'isPublished': true,
    'createdAt': Timestamp.fromDate(createdAt),
    'expiresAt': Timestamp.fromDate(createdAt.add(const Duration(hours: 24))),
  };
}

Future<CreatorPinnedPostService> _pinnedService({
  required FakeFirebaseFirestore db,
  required MockFirebaseAuth auth,
  required String creatorId,
  required String caption,
}) async {
  final momentId = 'pinned-$creatorId';
  await db
      .collection('voiceMoments')
      .doc(momentId)
      .set(_moment(momentId, creatorId, caption));
  await db.collection('creatorPinnedPosts').doc(creatorId).set({
    'schemaVersion': 1,
    'creatorId': creatorId,
    'momentId': momentId,
    'pinnedAt': Timestamp.fromDate(DateTime.now()),
    'updatedAt': Timestamp.fromDate(DateTime.now()),
  });
  return CreatorPinnedPostService(
    firestore: db,
    auth: auth,
    mutationInvoker: (_) async => const {},
    voiceMomentReadService: VoiceMomentReadService(
      viewInvoker: fakeVoiceMomentViewInvoker(firestore: db, viewerUid: 'me'),
    ),
  );
}

UserProfile _ownProfile() {
  final titles = AchievementCatalog.all.take(3).map((a) => a.id).toList();
  return UserProfile(
    uid: 'me',
    email: 'maja@yovoice.app',
    displayName: 'Maja Kowalska',
    username: 'maja.kowalska',
    bio: 'Nagrywam poranne Momenty i prowadzę wieczorne rozmowy o muzyce.',
    statusMessage: 'Muzyka + nocne rozmowy',
    country: 'Polska',
    nativeLanguage: 'polski',
    spokenLanguages: const ['angielski'],
    learningLanguages: const ['hiszpański'],
    photoUrl: null,
    bannerUrl: null,
    website: 'yovoice.app',
    accountType: AccountType.creator,
    premiumIdentity: true,
    creatorAudienceVisible: true,
    friendCount: 148,
    followerCount: 1840,
    followingCount: 212,
    roomCount: 1,
    communityCount: 3,
    voiceMinutes: 1265,
    messageCount: 842,
    activeDays: 64,
    momentCount: 27,
    reactionCount: 310,
    hostMinutes: 420,
    selectedTitleId: titles.isEmpty ? null : titles.first,
    unlockedTitleIds: titles,
    unlockedTitleTimestamps: const {},
    createdAt: DateTime(2026),
  );
}

const _servers = <Server>[
  Server(
    id: 's1',
    name: 'Nocne Rozmowy',
    description: '',
    ownerId: 'me',
    type: ServerType.podcast,
    privacy: ServerPrivacy.public,
    memberCount: 128,
  ),
  Server(
    id: 's2',
    name: 'Ekipa z liceum',
    description: '',
    ownerId: 'ola',
    type: ServerType.friends,
    privacy: ServerPrivacy.private,
    memberCount: 9,
  ),
  Server(
    id: 's3',
    name: 'Kraków Muzycznie',
    description: '',
    ownerId: 'kuba',
    type: ServerType.community,
    privacy: ServerPrivacy.public,
    memberCount: 2140,
  ),
];

class _MutualGraph implements SocialGraphService {
  @override
  Future<MutualFriendsSummary> getMutualFriends(String targetUserId) async =>
      MutualFriendsSummary(
        count: 6,
        sample: [
          for (final (uid, name) in const [
            ('ola', 'Ola'),
            ('kuba', 'Kuba'),
            ('zuzia', 'Zuzia'),
          ])
            SuggestedFriend(
              uid: uid,
              displayName: name,
              photoUrl: null,
              mutualCount: 1,
            ),
        ],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host({
  required GlobalKey<NavigatorState> navigatorKey,
  required bool pearl,
  required Size size,
}) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    navigatorKey: navigatorKey,
    theme: pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
    locale: const Locale('pl'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.noScaling,
        disableAnimations: true,
      ),
      child: child!,
    ),
    home: const Scaffold(body: SizedBox.expand()),
  ),
);

typedef _Frame = ({String screen, double width, double height, bool pearl});

void main() {
  late PublicIdentityRepository originalIdentity;
  // The pinned Voice Moment's play button constructs a real AudioPlayer; the
  // plugin has no host here, so its channels answer with nothing (the
  // technique of test/report_visual_qa.dart).
  const audioChannels = <MethodChannel>[
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
    MethodChannel('xyz.luan/audioplayers.global/events'),
  ];

  setUpAll(() async {
    await _loadFonts();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in audioChannels) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in audioChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = _identity();
    ProfileMediaService.clearAllMediaAccessCaches();
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpOwn(WidgetTester tester, _Frame frame) async {
    final auth = _auth();
    final db = FakeFirebaseFirestore();
    final pinned = await tester.runAsync(
      () => _pinnedService(
        db: db,
        auth: auth,
        creatorId: 'me',
        caption: 'Poranek nad Wisłą: minuta ciszy przed całym dniem',
      ),
    );
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _host(
        navigatorKey: navigatorKey,
        pearl: frame.pearl,
        size: Size(frame.width, frame.height),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreenView(
          profile: _ownProfile(),
          servers: _servers,
          serversLoading: false,
          onEdit: () {},
          onAchievements: () {},
          onOpenServer: (_) {},
          showSuperAdminActivation: false,
          isActivatingSuperAdmin: false,
          currentRole: 'user',
          onActivateSuperAdmin: () async {},
          onLogout: () async {},
          identityRepository: _identity(),
          mediaService: _media(auth),
          creatorPinnedPostService: pinned,
        ),
      ),
    );
    await settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await settle(tester);
  }

  Future<void> pumpFriend(WidgetTester tester, _Frame frame) async {
    final auth = _auth();
    final db = FakeFirebaseFirestore();
    const friendId = 'friend-ola';
    final pinned = await tester.runAsync(() async {
      await db.collection('users').doc('me').set({
        'uid': 'me',
        'displayName': 'Maja Kowalska',
        'email': 'me@yovoice.app',
      });
      await db.collection('publicProfiles').doc(friendId).set({
        'uid': friendId,
        'displayName': 'Ola Nowak',
        'username': 'ola.codziennie',
        'statusMessage': 'Poranne spacery i dobre podcasty',
        'bio':
            'Robię Momenty o dźwiękach miasta. Wieczorami prowadzę serwer '
            'o książkach.',
        'nativeLanguage': 'polski',
        'spokenLanguages': ['angielski'],
        'learningLanguages': ['włoski'],
        'friendCount': 312,
        'followerCount': 4210,
        'followingCount': 188,
        'accountType': 'creator',
        'premiumIdentity': true,
        'creatorAudienceVisible': true,
      });
      await db.collection('socialPresence').doc(friendId).set({
        'uid': friendId,
        'isOnline': true,
      });
      return _pinnedService(
        db: db,
        auth: auth,
        creatorId: friendId,
        caption: 'Tramwaj o 6:40 — dźwięki, które zwykle mijamy',
      );
    });
    final notifications = NotificationService(firestore: db, auth: auth);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _host(
        navigatorKey: navigatorKey,
        pearl: frame.pearl,
        size: Size(frame.width, frame.height),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => FriendProfileScreen(
          friend: const FriendUser(
            id: friendId,
            displayName: 'Ola Nowak',
            email: '',
            photoUrl: null,
            isOnline: true,
            lastSeen: null,
          ),
          firestore: db,
          auth: auth,
          friendService: FriendService(
            firestore: db,
            auth: auth,
            notificationService: notifications,
          ),
          messageService: MessageService(
            firestore: db,
            auth: auth,
            notificationService: notifications,
          ),
          profileService: ProfileService(firestore: db, auth: auth),
          followService: FollowService(firestore: db, auth: auth),
          socialGraphService: _MutualGraph(),
          profileMediaService: _media(auth),
          creatorPinnedPostService: pinned,
        ),
      ),
    );
    await settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await settle(tester);
  }

  final frames = <_Frame>[
    for (final screen in const ['profile', 'friend-profile'])
      for (final pearl in const [false, true])
        for (final (width, height) in const [(390.0, 844.0), (1440.0, 900.0)])
          (screen: screen, width: width, height: height, pearl: pearl),
  ];

  for (final frame in frames) {
    for (final full in const [false, true]) {
      final theme = frame.pearl ? 'pearl' : 'dark';
      final name =
          '${frame.screen}_${frame.width.toInt()}_${theme}_pl_100_populated'
          '${full ? '-full' : ''}';
      testWidgets(name, (tester) async {
        final height = full ? 2600.0 : frame.height;
        tester.view.physicalSize = Size(frame.width, height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final sized = (
          screen: frame.screen,
          width: frame.width,
          height: height,
          pearl: frame.pearl,
        );
        if (frame.screen == 'profile') {
          await pumpOwn(tester, sized);
        } else {
          await pumpFriend(tester, sized);
        }
        await _shoot(tester, name);
        _recordException(tester, name);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 20));
      });
    }
  }
}
