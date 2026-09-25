// Full-bleed profile banner frame harness.
//
// Renders the REAL own profile (`ProfileScreenView`), the REAL
// `FriendProfileScreen` and the REAL `EditProfileScreen` preview with fixture
// data through their constructor seams: no Firebase app, no callable. Banner
// grants resolve to a local HTTP fake that serves two generated 1600x900
// banners — a very bright one and a very dark one — so the photo, its blur,
// scrim and melt are the production code path (`NetworkImage` included).
//
// Matrix: 390x844 (status bar 47), 768x1024 (status bar 24) and 1440x900
// (none), Dark and Pearl, bright / dark / no banner, own and friend profile;
// plus the edit preview, a pending grant in Pearl, high contrast, an iPhone
// landscape and a 2560 desktop.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/profile_banner_capture.dart --concurrency=1 \
//     --dart-define=YO_CAPTURE_DIR=<evidence>/profile-banner
//
// Frames are named `<screen>_<width>x<height>_<dark|pearl>_<banner>.png`.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friend_profile_screen.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

const _outDir = String.fromEnvironment(
  'YO_CAPTURE_DIR',
  defaultValue: 'test/.screenshots/profile-banner',
);

final _capture = GlobalKey();

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

// ---------------------------------------------------------------------------
// Generated banners. Deliberately detailed (edges, dots, stripes) so the blur
// at the bottom is visible, and deliberately extreme in luminance.
// ---------------------------------------------------------------------------

Future<Uint8List> _renderBanner({required bool bright}) async {
  const w = 1600.0;
  const h = 900.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));
  final rect = const Rect.fromLTWH(0, 0, w, h);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(0, h),
        bright
            ? const [Color(0xFFFFFFFF), Color(0xFFFFF4CC)]
            : const [Color(0xFF020104), Color(0xFF120820)],
      ),
  );
  final random = math.Random(bright ? 7 : 11);
  // A sun / a moon glow.
  canvas.drawCircle(
    const Offset(w * .72, h * .34),
    bright ? 190 : 120,
    Paint()
      ..color = bright ? const Color(0xFFFFE27A) : const Color(0xFF3A1A5C)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
  );
  // Stripes or a skyline.
  for (var i = 0; i < 22; i++) {
    final x = i * 80.0;
    final height = 120 + random.nextDouble() * 380;
    canvas.drawRect(
      Rect.fromLTWH(x, h - height, 62, height),
      Paint()
        ..color = bright
            ? Color.lerp(
                const Color(0xFFFFFFFF),
                const Color(0xFFBFE6FF),
                random.nextDouble(),
              )!
            : Color.lerp(
                const Color(0xFF07040C),
                const Color(0xFF1C1030),
                random.nextDouble(),
              )!,
    );
    // Windows / highlights: fine detail for the blur to eat.
    for (var y = h - height + 16; y < h - 20; y += 34) {
      if (random.nextDouble() < .55) {
        canvas.drawRect(
          Rect.fromLTWH(x + 12 + random.nextInt(3) * 14, y, 10, 14),
          Paint()
            ..color = bright
                ? const Color(0xFFF7F0D0)
                : const Color(0xFFFFC857).withValues(alpha: .9),
        );
      }
    }
  }
  // Stars or confetti near the top.
  for (var i = 0; i < 140; i++) {
    canvas.drawCircle(
      Offset(random.nextDouble() * w, random.nextDouble() * h * .5),
      1.5 + random.nextDouble() * 3,
      Paint()
        ..color = bright
            ? const Color(0xFFFFFFFF)
            : const Color(
                0xFFFFFFFF,
              ).withValues(alpha: .4 + random.nextDouble() * .6),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(w.toInt(), h.toInt());
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

// ---------------------------------------------------------------------------
// A tiny HttpClient that serves the generated banners to NetworkImage.
// ---------------------------------------------------------------------------

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.bodies);

  final Map<String, Uint8List> bodies;

  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeRequest(bodies[url.path]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.body);

  final Uint8List? body;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(body);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.body);

  final Uint8List? body;

  @override
  int get statusCode => body == null ? 404 : 200;

  @override
  int get contentLength => body?.length ?? 0;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable([?body]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Fixtures.
// ---------------------------------------------------------------------------

enum _Banner { bright, dark, none, pending }

MockFirebaseAuth _auth() => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: 'me', email: 'me@yovoice.app', isEmailVerified: true),
);

ProfileMediaService _media(MockFirebaseAuth auth, _Banner banner) =>
    ProfileMediaService(
      auth: auth,
      invoker: (_, request) {
        if (request['kind'] == 'banner' && banner == _Banner.pending) {
          // A grant that never answers: the state every profile opens in.
          return Completer<Map<Object?, Object?>>().future;
        }
        final expires = DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch;
        if (request['kind'] == 'banner' &&
            (banner == _Banner.bright || banner == _Banner.dark)) {
          return Future.value(<Object?, Object?>{
            'schemaVersion': 1,
            'available': true,
            'expiresAtMillis': expires,
            'url':
                'https://storage.googleapis.com/capture/${banner.name}.png'
                '?signature=short',
            'generation': '1',
            'contentType': 'image/png',
            'size': 4096,
          });
        }
        return Future.value(<Object?, Object?>{
          'schemaVersion': 1,
          'available': false,
          'expiresAtMillis': expires,
        });
      },
    );

PublicIdentityRepository _identity() => PublicIdentityRepository(
  auth: _auth(),
  fetchOverride: (uids) async => {
    for (final uid in uids) uid: const {'role': 'user'},
  },
  flushDelay: const Duration(milliseconds: 1),
);

UserProfile _ownProfile() => UserProfile(
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
  accountType: AccountType.personal,
  premiumIdentity: true,
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
  selectedTitleId: null,
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: DateTime(2026),
);

class _EmptyGraph implements SocialGraphService {
  @override
  Future<MutualFriendsSummary> getMutualFriends(String targetUserId) async =>
      MutualFriendsSummary.empty;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

typedef _Frame = ({
  String screen,
  double width,
  double height,
  double top,
  bool pearl,
  _Banner banner,
  bool highContrast,
});

Widget _host({
  required GlobalKey<NavigatorState> navigatorKey,
  required _Frame frame,
}) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    navigatorKey: navigatorKey,
    theme: frame.pearl ? AppTheme.lightTheme : AppTheme.darkTheme,
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
        size: Size(frame.width, frame.height),
        padding: EdgeInsets.only(top: frame.top),
        viewPadding: EdgeInsets.only(top: frame.top),
        textScaler: TextScaler.noScaling,
        disableAnimations: true,
        highContrast: frame.highContrast,
      ),
      child: child!,
    ),
    home: const Scaffold(body: SizedBox.expand()),
  ),
);

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

void main() {
  late PublicIdentityRepository originalIdentity;
  final bodies = <String, Uint8List>{};

  setUpAll(() async {
    await _loadFonts();
    bodies['/capture/bright.png'] = await _renderBanner(bright: true);
    bodies['/capture/dark.png'] = await _renderBanner(bright: false);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in const [
      MethodChannel('xyz.luan/audioplayers.global'),
      MethodChannel('xyz.luan/audioplayers'),
      MethodChannel('xyz.luan/audioplayers.global/events'),
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
    }
  });

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = _identity();
    ProfileMediaService.clearAllMediaAccessCaches();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 3; round++) {
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Image decoding and the fake network need real async time.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
    }
    await tester.pump();
  }

  Widget screenFor(_Frame frame, FakeFirebaseFirestore db, MockFirebaseAuth a) {
    final media = _media(a, frame.banner);
    switch (frame.screen) {
      case 'profile':
        return ProfileScreenView(
          profile: _ownProfile(),
          servers: const [],
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
          mediaService: media,
        );
      case 'edit-profile':
        return EditProfileScreen(
          profile: _ownProfile(),
          service: ProfileService(firestore: db, auth: a),
          entitlements: EntitlementService(firestore: db, auth: a),
          mediaService: media,
        );
      default:
        final notifications = NotificationService(firestore: db, auth: a);
        return FriendProfileScreen(
          friend: const FriendUser(
            id: 'friend-ola',
            displayName: 'Ola Nowak',
            email: '',
            photoUrl: null,
            isOnline: true,
            lastSeen: null,
          ),
          firestore: db,
          auth: a,
          friendService: FriendService(
            firestore: db,
            auth: a,
            notificationService: notifications,
          ),
          messageService: MessageService(
            firestore: db,
            auth: a,
            notificationService: notifications,
          ),
          profileService: ProfileService(firestore: db, auth: a),
          followService: FollowService(firestore: db, auth: a),
          socialGraphService: _EmptyGraph(),
          profileMediaService: media,
        );
    }
  }

  final frames = <_Frame>[
    for (final screen in const ['profile', 'friend-profile'])
      for (final pearl in const [false, true])
        for (final (width, height, top) in const [
          (390.0, 844.0, 47.0),
          (768.0, 1024.0, 24.0),
          (1440.0, 900.0, 0.0),
        ])
          for (final banner in const [
            _Banner.bright,
            _Banner.dark,
            _Banner.none,
          ])
            (
              screen: screen,
              width: width,
              height: height,
              top: top,
              pearl: pearl,
              banner: banner,
              highContrast: false,
            ),
    for (final pearl in const [false, true])
      for (final banner in const [_Banner.bright, _Banner.dark, _Banner.none])
        (
          screen: 'edit-profile',
          width: 390.0,
          height: 844.0,
          top: 47.0,
          pearl: pearl,
          banner: banner,
          highContrast: false,
        ),
    for (final screen in const ['profile', 'friend-profile'])
      (
        screen: screen,
        width: 390.0,
        height: 844.0,
        top: 47.0,
        pearl: true,
        banner: _Banner.pending,
        highContrast: false,
      ),
    for (final pearl in const [false, true])
      (
        screen: 'profile',
        width: 390.0,
        height: 844.0,
        top: 47.0,
        pearl: pearl,
        banner: _Banner.bright,
        highContrast: true,
      ),
    (
      screen: 'friend-profile',
      width: 844.0,
      height: 390.0,
      top: 0.0,
      pearl: false,
      banner: _Banner.bright,
      highContrast: false,
    ),
    (
      screen: 'friend-profile',
      width: 2560.0,
      height: 1440.0,
      top: 0.0,
      pearl: false,
      banner: _Banner.bright,
      highContrast: false,
    ),
    (
      screen: 'profile',
      width: 2560.0,
      height: 1440.0,
      top: 0.0,
      pearl: true,
      banner: _Banner.dark,
      highContrast: false,
    ),
  ];

  for (final frame in frames) {
    final name =
        '${frame.screen}_${frame.width.toInt()}x${frame.height.toInt()}'
        '_${frame.pearl ? 'pearl' : 'dark'}_${frame.banner.name}'
        '${frame.highContrast ? '_high-contrast' : ''}';
    testWidgets(name, (tester) async {
      tester.view.physicalSize = Size(frame.width, frame.height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      debugNetworkImageHttpClientProvider = () => _FakeHttpClient(bodies);
      try {
        final auth = _auth();
        final db = FakeFirebaseFirestore();
        await tester.runAsync(() async {
          await db.collection('users').doc('me').set({
            'uid': 'me',
            'displayName': 'Maja Kowalska',
            'email': 'me@yovoice.app',
          });
          await db.collection('publicProfiles').doc('friend-ola').set({
            'uid': 'friend-ola',
            'displayName': 'Ola Nowak',
            'username': 'ola.codziennie',
            'statusMessage': 'Poranne spacery i dobre podcasty',
            'bio':
                'Robię Momenty o dźwiękach miasta. Wieczorami prowadzę '
                'serwer o książkach.',
            'friendCount': 312,
            'followerCount': 4210,
            'followingCount': 188,
            'accountType': 'personal',
            'premiumIdentity': true,
          });
          await db.collection('socialPresence').doc('friend-ola').set({
            'uid': 'friend-ola',
            'isOnline': true,
          });
        });
        final navigatorKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          _host(navigatorKey: navigatorKey, frame: frame),
        );
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => screenFor(frame, db, auth)),
        );
        await settle(tester);
        final error = tester.takeException();
        if (error != null) {
          // ignore: avoid_print
          print('EXCEPTION $name :: $error');
        }
        await _shoot(tester, name);
        // Unmount before the fake client is removed.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      } finally {
        debugNetworkImageHttpClientProvider = null;
      }
    });
  }
}
