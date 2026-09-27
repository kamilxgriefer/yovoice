// Slim redesign phase 5 (Profil) frame harness, extended for refine-look
// batch B8 (spec §10 "harness gaps": 768 px, 200 % text and the key states).
//
// Renders the REAL own-profile page (`ProfileScreenView`, the widget
// `ProfileScreen` builds once its streams deliver), its REAL error state
// (`ProfileErrorView`) and the REAL `FriendProfileScreen` with fixture data
// through their constructor seams: no Firebase app, no network, no callable.
// Locale pl. No fixture has a profile photo or banner (the media resolver
// answers "not available"), so every frame is also the no-photo state.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/slim_profile_capture.dart --concurrency=1 \
//     --dart-define=YO_CAPTURE_DIR=<evidence>/b8/after
//
// Matrices (`--dart-define=SLIM_CAPTURE_MATRIX=`):
//
// * `refine` (default) — `profile` and `friend-profile` at 390, 768 and
//   1440 px, Dark and Pearl, 100 % and 200 % text, each at the device
//   viewport (`_populated`) and on a tall viewport (`_populated-full`, every
//   block below the fold on one image); plus, across 390 / 768 / 1440 and
//   100 / 200 % text (see [_frames]):
//   - own profile: `vibe-links-full`, `pinned-playing` (the pinned bead
//     pressed and playing, scrolled into view), `bead-busy` (a play that
//     is still resolving), `bead-failed` (a play that failed: the refresh
//     glyph and its message), `bead-disabled` (a legacy pin with no media),
//     `progress-full` (no title unlocked yet: the achievement progress
//     pill), `loading` (the real `ProfileScreen` before its profile
//     arrives) and `error`;
//   - `friend-profile`: `unavailable` (the public profile is gone or
//     hidden, which is also its error state) and `loading`;
//   - `edit-profile` (the editor: preview, image actions, fields and the
//     account-type block);
//   - high-contrast twins (`..._populated-full-hc`);
//   - keyboard focus (`focus-<control>`): the CTA, the neutral actions,
//     the pinned bead, a vibe link and an account row on the own profile;
//     Zadzwoń, Wideo and Obserwuj on a friend's. Focus is moved to the
//     control and shown the way a Tab press shows it.
// * `single` — the original Slim set: 390 and 1440, 100 %, populated.
//
// Shadows are real: flutter_test flattens every BoxShadow to a hard band
// (`debugDisableShadows`, meant for golden stability), so each capture
// switches that off and restores it afterwards — otherwise the CTA lift,
// the lit bead's glow and Pearl's block shadows read as solid slabs.
//
// Frames are named `<screen>_<width>_<dark|pearl>_pl_<text>_<state>[-hc].png`.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/achievements/data/achievement_catalog.dart';
import 'package:yovoice/features/achievements/data/services/achievement_service.dart';
import 'package:yovoice/features/creator/data/models/creator_pinned_post.dart';
import 'package:yovoice/features/creator/data/services/creator_pinned_post_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/friends/data/services/social_graph_service.dart';
import 'package:yovoice/features/friends/presentation/screens/friend_profile_screen.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/profile/data/services/profile_media_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:yovoice/features/profile/presentation/screens/profile_screen.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_disc.dart';

import 'voice_moment_test_doubles.dart';

const _outDir = String.fromEnvironment(
  'YO_CAPTURE_DIR',
  defaultValue: 'test/.screenshots/slim-p5',
);
const _matrix = String.fromEnvironment(
  'SLIM_CAPTURE_MATRIX',
  defaultValue: 'refine',
);
// The macOS colour-emoji font (a Linux capture host maps a Noto colour
// emoji face to the same path). Without it a vibe's emoji draws as tofu.
const _emojiFont = '/System/Library/Fonts/Apple Color Emoji.ttc';

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
  final emoji = File(_emojiFont);
  if (emoji.existsSync()) {
    final bytes = ByteData.sublistView(emoji.readAsBytesSync());
    for (final family in const ['Apple Color Emoji', 'sans-serif']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  }
}

/// A player that plays without a platform: the pinned bead's playing state
/// is captured exactly as a real play leaves it.
class _SilentPlayer implements audio.AudioPlayer {
  @override
  Stream<void> get onPlayerComplete => const Stream<void>.empty();

  @override
  Future<void> play(
    audio.Source source, {
    double? volume,
    double? balance,
    audio.AudioContext? ctx,
    Duration? position,
    audio.PlayerMode? mode,
  }) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A play that is still resolving: the bead's busy state.
class _HangingPlayer extends _SilentPlayer {
  @override
  Future<void> play(
    audio.Source source, {
    double? volume,
    double? balance,
    audio.AudioContext? ctx,
    Duration? position,
    audio.PlayerMode? mode,
  }) => Completer<void>().future;
}

/// A play that fails (a revoked grant, a dropped network): the bead's
/// failed state.
class _FailingPlayer extends _SilentPlayer {
  @override
  Future<void> play(
    audio.Source source, {
    double? volume,
    double? balance,
    audio.AudioContext? ctx,
    Duration? position,
    audio.PlayerMode? mode,
  }) async => throw StateError('playback failed');
}

/// One fixed pin: a legacy Moment with no media reference, which the bead
/// shows disabled.
class _LegacyPinService extends CreatorPinnedPostService {
  _LegacyPinService({required super.firestore, required super.auth});

  @override
  Stream<PinnedVoiceMoment?> watchPinnedPostForCreator(String creatorId) {
    final createdAt = DateTime.now().subtract(const Duration(hours: 3));
    return Stream.value(
      PinnedVoiceMoment(
        pin: CreatorPinnedPost(
          creatorId: creatorId,
          momentId: 'legacy',
          pinnedAt: createdAt,
        ),
        moment: VoiceMoment(
          id: 'legacy',
          authorId: creatorId,
          authorName: 'Maja Kowalska',
          authorPhotoUrl: null,
          caption: 'Poranek nad Wisłą: minuta ciszy przed całym dniem',
          audioUrl: null,
          durationSeconds: 42,
          likeCount: 18,
          commentCount: 4,
          isPublished: true,
          createdAt: createdAt,
          expiresAt: createdAt.add(const Duration(hours: 24)),
        ),
      ),
    );
  }
}

/// A profile that has not arrived yet (the loading state).
class _PendingProfileService extends ProfileService {
  _PendingProfileService({required super.firestore, required super.auth});

  final _never = StreamController<UserProfile>.broadcast();

  @override
  Stream<UserProfile> watchCurrentProfile() => _never.stream;

  @override
  Stream<UserProfile> watchProfile(String userId) => _never.stream;

  @override
  Future<void> ensureProfile() async {}
}

class _QuietAchievements extends AchievementService {
  _QuietAchievements({required super.firestore, required super.auth});

  @override
  Future<void> refreshUnlockedTitles() async {}
}

class _NoServers implements ServerRepository {
  @override
  Stream<List<Server>> watchMyServers() => const Stream<List<Server>>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

UserProfile _ownProfile({String? vibe, bool titles = true}) {
  final unlocked = titles
      ? AchievementCatalog.all.take(3).map((a) => a.id).toList()
      : const <String>[];
  return UserProfile(
    uid: 'me',
    email: 'maja@yovoice.app',
    displayName: 'Maja Kowalska',
    username: 'maja.kowalska',
    bio: 'Nagrywam poranne Momenty i prowadzę wieczorne rozmowy o muzyce.',
    statusMessage: vibe ?? 'Muzyka + nocne rozmowy',
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
    selectedTitleId: unlocked.isEmpty ? null : unlocked.first,
    unlockedTitleIds: unlocked,
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
  double textScale = 1,
  bool highContrast = false,
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
        textScaler: textScale == 1
            ? TextScaler.noScaling
            : TextScaler.linear(textScale),
        disableAnimations: true,
        highContrast: highContrast,
      ),
      child: child!,
    ),
    home: const Scaffold(body: SizedBox.expand()),
  ),
);

/// One capture: which page, how it is sized and themed, and which state.
typedef _Frame = ({
  String screen,
  double width,
  double height,
  bool pearl,
  int text,
  String state,
  bool full,
  bool highContrast,
});

String _name(_Frame f) =>
    '${f.screen}_${f.width.toInt()}_${f.pearl ? 'pearl' : 'dark'}_pl_'
    '${f.text}_${f.state}${f.full ? '-full' : ''}'
    '${f.highContrast ? '-hc' : ''}';

List<_Frame> _frames() {
  _Frame frame(
    String screen,
    double width,
    bool pearl, {
    int text = 100,
    String state = 'populated',
    bool full = false,
    bool highContrast = false,
  }) => (
    screen: screen,
    width: width,
    height: width >= 1000 ? 900 : (width >= 700 ? 1024 : 844),
    pearl: pearl,
    text: text,
    state: state,
    full: full,
    highContrast: highContrast,
  );
  if (_matrix == 'single') {
    return [
      for (final screen in const ['profile', 'friend-profile'])
        for (final pearl in const [false, true])
          for (final width in const [390.0, 1440.0])
            for (final full in const [false, true])
              frame(screen, width, pearl, full: full),
    ];
  }
  // (width, pearl, text) cells, compactly.
  const d390 = (390.0, false, 100), p390 = (390.0, true, 100);
  const d768 = (768.0, false, 100), p768 = (768.0, true, 100);
  const d1440 = (1440.0, false, 100), p1440 = (1440.0, true, 100);
  const d390x2 = (390.0, false, 200), p390x2 = (390.0, true, 200);
  const d768x2 = (768.0, false, 200), p768x2 = (768.0, true, 200);
  const d1440x2 = (1440.0, false, 200);
  List<_Frame> cells(
    String screen,
    String state,
    List<(double, bool, int)> at, {
    bool full = false,
    bool highContrast = false,
  }) => [
    for (final (width, pearl, text) in at)
      frame(
        screen,
        width,
        pearl,
        text: text,
        state: state,
        full: full,
        highContrast: highContrast,
      ),
  ];
  return [
    for (final screen in const ['profile', 'friend-profile'])
      for (final width in const [390.0, 768.0, 1440.0])
        for (final pearl in const [false, true])
          for (final text in const [100, 200])
            for (final full in const [false, true])
              frame(screen, width, pearl, text: text, full: full),
    ...cells('profile', 'vibe-links', full: true, [
      d390,
      p390,
      d768,
      p768,
      p1440,
      d390x2,
      p390x2,
      p768x2,
    ]),
    ...cells('profile', 'pinned-playing', [
      d390,
      p390,
      d768,
      p768,
      d1440,
      p1440,
      d390x2,
      p390x2,
      d768x2,
    ]),
    ...cells('profile', 'bead-busy', [d390, p390]),
    ...cells('profile', 'bead-failed', [d390, p390, d1440]),
    ...cells('profile', 'bead-disabled', [d390, p390]),
    ...cells('profile', 'progress', full: true, [
      d390,
      p390,
      p768,
      d1440,
      d390x2,
    ]),
    ...cells('profile', 'loading', [d390, p1440]),
    ...cells('profile', 'error', [
      d390,
      p390,
      d768,
      p768,
      d1440,
      p1440,
      d390x2,
      p390x2,
      p768x2,
      d1440x2,
    ]),
    ...cells('profile', 'error', [d390], highContrast: true),
    ...cells('friend-profile', 'unavailable', [
      d390,
      p390,
      d768,
      p1440,
      d390x2,
    ]),
    ...cells('friend-profile', 'loading', [d390, p1440]),
    ...cells('edit-profile', 'populated', full: true, [
      d390,
      p390,
      d768,
      p768,
      d1440,
      p1440,
      d390x2,
      p390x2,
      d768x2,
    ]),
    ...cells('profile', 'populated', full: true, highContrast: true, [
      d390,
      d768,
      p1440,
      d390x2,
      p768x2,
    ]),
    ...cells('friend-profile', 'populated', full: true, highContrast: true, [
      p390,
      p768,
      d1440,
      d390x2,
    ]),
    ...cells('profile', 'focus-edit', [d390, p390, d1440]),
    ...cells('profile', 'focus-edit', [p390], highContrast: true),
    ...cells('profile', 'focus-awards', [p390]),
    ...cells('profile', 'focus-more', [p390]),
    ...cells('profile', 'focus-bead', [p390, d1440]),
    ...cells('profile', 'focus-vibe-link', [p390, d768]),
    ...cells('profile', 'focus-logout', [p390, d1440]),
    ...cells('friend-profile', 'focus-call', [d390, p390, d1440]),
    ...cells('friend-profile', 'focus-video', [p390]),
    ...cells('friend-profile', 'focus-follow', [p390, d768]),
  ];
}

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

  Future<GlobalKey<NavigatorState>> host(
    WidgetTester tester,
    _Frame frame,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _host(
        navigatorKey: navigatorKey,
        pearl: frame.pearl,
        size: Size(frame.width, frame.height),
        textScale: frame.text / 100,
        highContrast: frame.highContrast,
      ),
    );
    return navigatorKey;
  }

  /// Scrolls the lazily built page until [target] exists, then brings it
  /// to the middle of the viewport (with context above and below it).
  Future<void> reveal(WidgetTester tester, Finder target, _Frame frame) async {
    final scrollable = find.byType(Scrollable).first;
    ScrollPosition position() =>
        tester.state<ScrollableState>(scrollable).position;
    for (var i = 0; i < 24 && target.evaluate().isEmpty; i++) {
      final at = position();
      if (at.pixels >= at.maxScrollExtent) break;
      at.jumpTo(
        (at.pixels + 240).clamp(at.minScrollExtent, at.maxScrollExtent),
      );
      await settle(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await settle(tester);
    }
    final rect = tester.getRect(target.first);
    final at = position();
    at.jumpTo(
      (at.pixels + rect.center.dy - frame.height / 2).clamp(
        at.minScrollExtent,
        at.maxScrollExtent,
      ),
    );
    await settle(tester);
  }

  /// Keyboard focus on the control that owns [target], shown the way a Tab
  /// press shows it.
  Future<void> focus(WidgetTester tester, Finder target, _Frame frame) async {
    await reveal(tester, target, frame);
    final manager = tester.binding.focusManager;
    manager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => manager.highlightStrategy = FocusHighlightStrategy.automatic,
    );
    Focus.of(tester.element(target.first)).requestFocus();
    await settle(tester);
  }

  Finder focusTarget(String state) => switch (state) {
    'focus-edit' => find.descendant(
      of: find.byKey(const ValueKey('profile-edit-button')),
      matching: find.byType(Text),
    ),
    'focus-awards' => find.descendant(
      of: find.byKey(const ValueKey('profile-awards-button')),
      matching: find.byType(Text),
    ),
    'focus-more' => find.descendant(
      of: find.byKey(const ValueKey('profile-more-button')),
      matching: find.byType(Icon),
    ),
    'focus-bead' => find.byType(YoGradientDisc),
    'focus-vibe-link' => find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'profile-vibe-link-leading-',
          ),
    ),
    'focus-logout' => find.text('Wyloguj się'),
    'focus-call' => find.descendant(
      of: find.byKey(const ValueKey('friend-profile-call-button')),
      matching: find.byType(Icon),
    ),
    'focus-video' => find.descendant(
      of: find.byKey(const ValueKey('friend-profile-video-button')),
      matching: find.byType(Icon),
    ),
    'focus-follow' => find.descendant(
      of: find.byKey(const ValueKey('friend-profile-follow-button')),
      matching: find.byType(Text),
    ),
    _ => throw ArgumentError(state),
  };

  Future<void> pumpOwn(WidgetTester tester, _Frame frame) async {
    final auth = _auth();
    final db = FakeFirebaseFirestore();
    final pinned = frame.state == 'bead-disabled'
        ? _LegacyPinService(firestore: db, auth: auth)
        : await tester.runAsync(
            () => _pinnedService(
              db: db,
              auth: auth,
              creatorId: 'me',
              caption: 'Poranek nad Wisłą: minuta ciszy przed całym dniem',
            ),
          );
    final audio.AudioPlayer Function() player = switch (frame.state) {
      'bead-busy' => _HangingPlayer.new,
      'bead-failed' => _FailingPlayer.new,
      _ => _SilentPlayer.new,
    };
    final navigatorKey = await host(tester, frame);
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreenView(
          profile: _ownProfile(
            vibe:
                frame.state == 'vibe-links' || frame.state == 'focus-vibe-link'
                ? 'Nocne rozmowy https://open.spotify.com/track/7ouMYWpwJ422jRcDASZB7P'
                : null,
            titles: frame.state != 'progress',
          ),
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
          pinnedMomentService: MomentService(
            firestore: db,
            auth: auth,
            storage: MockFirebaseStorage(),
            mediaAccessInvoker: fakeMomentMediaAccessInvoker(),
          ),
          pinnedPlayerFactory: player,
        ),
      ),
    );
    await settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await settle(tester);
    final bead = find.byType(YoGradientDisc);
    if (frame.state.startsWith('focus-')) {
      await focus(tester, focusTarget(frame.state), frame);
    } else if (frame.state == 'pinned-playing' ||
        frame.state.startsWith('bead-')) {
      // The pin is below the fold on a phone and the list builds lazily:
      // scroll it in (its stream then delivers), then press play (a
      // disabled bead is shown at rest: it takes no press).
      await reveal(tester, bead, frame);
      if (frame.state != 'bead-disabled') {
        await tester.tap(bead);
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await settle(tester);
      }
    }
  }

  /// The real `ProfileScreen` before its profile arrives: the loading state.
  Future<void> pumpLoading(WidgetTester tester, _Frame frame) async {
    final auth = _auth();
    final db = FakeFirebaseFirestore();
    final navigatorKey = await host(tester, frame);
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(
          profileService: _PendingProfileService(firestore: db, auth: auth),
          achievementService: _QuietAchievements(firestore: db, auth: auth),
          serverRepository: _NoServers(),
          auth: auth,
          identityRepository: _identity(),
          mediaService: _media(auth),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> pumpError(WidgetTester tester, _Frame frame) async {
    final navigatorKey = await host(tester, frame);
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileErrorView(
          message: 'Nie udało się wczytać profilu. Spróbuj ponownie.',
          onRetry: () {},
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> pumpEdit(WidgetTester tester, _Frame frame) async {
    final auth = _auth();
    final db = FakeFirebaseFirestore();
    final navigatorKey = await host(tester, frame);
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => EditProfileScreen(
          profile: _ownProfile(),
          service: ProfileService(firestore: db, auth: auth),
          entitlements: EntitlementService(firestore: db, auth: auth),
          mediaService: _media(auth),
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
      // Unavailable: the public projection is gone (deleted, or hidden by
      // its owner) — the screen's error state as well.
      if (frame.state != 'unavailable') {
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
      }
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
    final navigatorKey = await host(tester, frame);
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
          profileService: frame.state == 'loading'
              ? _PendingProfileService(firestore: db, auth: auth)
              : ProfileService(firestore: db, auth: auth),
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
    if (frame.state.startsWith('focus-')) {
      await focus(tester, focusTarget(frame.state), frame);
    }
  }

  for (final frame in _frames()) {
    final name = _name(frame);
    testWidgets(name, (tester) async {
      // 200 % text roughly doubles the page: give its full frame room.
      final height = frame.full
          ? (frame.text >= 200 ? 4600.0 : 2600.0)
          : frame.height;
      tester.view.physicalSize = Size(frame.width, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sized = (
        screen: frame.screen,
        width: frame.width,
        height: height,
        pearl: frame.pearl,
        text: frame.text,
        state: frame.state,
        full: frame.full,
        highContrast: frame.highContrast,
      );
      // Real shadows for the frame (see the header comment).
      debugDisableShadows = false;
      try {
        if (frame.state == 'error') {
          await pumpError(tester, sized);
        } else if (frame.screen == 'edit-profile') {
          await pumpEdit(tester, sized);
        } else if (frame.screen == 'profile' && frame.state == 'loading') {
          await pumpLoading(tester, sized);
        } else if (frame.screen == 'profile') {
          await pumpOwn(tester, sized);
        } else {
          await pumpFriend(tester, sized);
        }
        await _shoot(tester, name);
        _recordException(tester, name);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 20));
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
