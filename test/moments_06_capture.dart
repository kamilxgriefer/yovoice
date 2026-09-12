// Developer-only visual QA harness for board 06 — YO Moments overview with
// Voice active.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/moments_06_capture.dart
//
// PNGs land in test/.screenshots/ (git-ignored) as
// `moments-06-{width}[-x2|-rtl|-pearl]-{state}.png`, the naming the build
// brief (slice 1, "done" item 1) asks for.
//
// WIDTH IS THE SLOT, not the window. The destination decides on the
// constraints it receives (docs/UI.md "Responsive layout contract"), and
// here it receives the whole viewport because the Home shell is not in the
// frame. With the rail the Home program kept at 264 (desktop_sidebar.dart),
// a window maps to a slot by subtracting it, which is the C36 correction in
// picture form:
//
//   window 1440 → slot 1176 → WIDE-2, no calm panel  (`…-1176-…`)
//   window 1464 → slot 1200 → WIDE-3, the threshold  (`…-1200-…`)
//   window 1920 → slot 1656 → WIDE-3                 (`…-1920-…` is drawn at
//                                                     a 1920 slot, wider still)
//
// The 1440 and 1464 cells are ALSO captured as slots, because the same
// destination is hosted at those slot widths by a narrower rail and by the
// pushed routes; they are wide-3 there, and that is not a contradiction of
// C36 — it is the same slot rule read at a different width.
//
// Why this exists: the widget tests prove keys, geometry and behaviour;
// they never prove any of it renders. These frames are what a reviewer
// looks at. Every fixture is controlled, reference-like data — nothing
// here is a real account or a real recording.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart' as audio;
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
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

final _capture = GlobalKey();

String get _fontRoot {
  const candidates = [
    '/opt/homebrew/Caskroom/flutter/3.44.6/flutter/bin/cache/artifacts/material_fonts',
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts',
    '/usr/local/share/flutter/bin/cache/artifacts/material_fonts',
  ];
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

VoiceMoment _moment(
  String id, {
  required String author,
  required String authorName,
  required String caption,
  int seconds = 45,
  int likes = 0,
  int comments = 0,
  Duration age = const Duration(hours: 2),
}) {
  final createdAt = DateTime.now().subtract(age);
  return VoiceMoment(
    id: id,
    authorId: author,
    authorName: authorName,
    authorPhotoUrl: null,
    caption: caption,
    audioUrl: 'https://cdn.example/$id.m4a',
    durationSeconds: seconds,
    likeCount: likes,
    commentCount: comments,
    isPublished: true,
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(hours: 24)),
    schemaVersion: 2,
    status: 'published',
    isDeleted: false,
  );
}

/// The board's four authors, with real chain shapes (Maja and Kamil hold
/// two each) and one 280-character caption for the long-content cell.
final _populated = <VoiceMoment>[
  _moment(
    'm1',
    author: 'maja',
    authorName: 'Maja',
    caption: 'Zanim obudzi się miasto. Minuta spokoju przed całym dniem.',
    seconds: 45,
    likes: 24,
    comments: 6,
    age: const Duration(hours: 2),
  ),
  _moment(
    'm2',
    author: 'kamil',
    authorName: 'Kamil',
    caption:
        'Mała rzecz, dobry dzień. Czasem to właśnie małe rzeczy robią wielką różnicę.',
    seconds: 28,
    likes: 11,
    comments: 2,
    age: const Duration(hours: 5),
  ),
  _moment(
    'm3',
    author: 'ola',
    authorName: 'Ola',
    caption:
        'Nagranie z tramwaju o poranku: dźwięki miasta, które zwykle mijamy bez uwagi. '
        'Chciałam sprawdzić, ile z nich naprawdę słyszymy, kiedy zwolnimy na minutę. '
        'Okazało się, że więcej niż myślałam. Ten opis ma dokładnie tyle znaków, ile '
        'pozwala serwer, żeby sprawdzić trzy linie i wielokropek na karcie.',
    seconds: 60,
    likes: 58,
    comments: 9,
    age: const Duration(hours: 7),
  ),
  _moment(
    'm4',
    author: 'bartek',
    authorName: 'Bartek',
    caption: '',
    seconds: 12,
    likes: 3,
    comments: 0,
    age: const Duration(minutes: 40),
  ),
  _moment(
    'm5',
    author: 'maja',
    authorName: 'Maja',
    caption: 'Druga część: co usłyszałam, kiedy miasto już się obudziło.',
    seconds: 39,
    likes: 8,
    comments: 1,
    age: const Duration(hours: 1),
  ),
  _moment(
    'm6',
    author: 'kamil',
    authorName: 'Kamil',
    caption: 'Krótka notatka po spacerze.',
    seconds: 19,
    likes: 2,
    comments: 0,
    age: const Duration(hours: 9),
  ),
];

class _StaticDiscovery implements MomentDiscoveryService {
  _StaticDiscovery(this.moments, {this.gate});

  final List<VoiceMoment> moments;

  /// Holds the load open so the loading state can be photographed.
  final Completer<void>? gate;

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async {
    if (gate != null) await gate!.future;
    return MomentDiscoveryFeed(
      moments: moments,
      fetchedCount: moments.length,
      drops: const <String, MomentDropReason>{},
      seed: seed ?? 0,
      poolExhausted: false,
    );
  }

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => const Stream<Map<String, MomentEngagement>>.empty();

  @override
  Future<List<VoiceMoment>> topLikedMoments({int limit = 3}) async =>
      moments.take(limit).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingDiscovery implements MomentDiscoveryService {
  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async => throw StateError('unavailable');

  @override
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => const Stream<Map<String, MomentEngagement>>.empty();

  @override
  Future<List<VoiceMoment>> topLikedMoments({int limit = 3}) async =>
      const <VoiceMoment>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticViews implements MomentViewsService {
  _StaticViews(this.viewed);

  final Set<String> viewed;

  @override
  Stream<Set<String>> watchViewedMomentIds() => Stream.value(viewed);

  @override
  Future<void> markViewed(String momentId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietFeed extends HomeFeedService {
  _QuietFeed({super.firestore, super.auth});

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.value(const <VoiceMoment>[]);
}

/// The calm panel's pool: three friends the viewer does not follow yet.
class _StaticFriends extends FriendService {
  _StaticFriends({required super.firestore, required super.auth});

  @override
  Stream<List<FriendUser>> watchFriends() => Stream.value(<FriendUser>[
    for (final (id, name, handle) in const <(String, String, String)>[
      ('ola', 'Ola', 'ola.codziennie'),
      ('bartek', 'Bartek', 'bartek'),
      ('zuzia', 'Zuzia', 'zuzia.later'),
    ])
      FriendUser(
        id: id,
        displayName: name,
        username: handle,
        email: '',
        photoUrl: null,
        isOnline: false,
        lastSeen: null,
      ),
  ]);
}

class _SilentPlayer implements audio.AudioPlayer {
  @override
  Stream<Duration> get onPositionChanged => const Stream<Duration>.empty();

  @override
  Stream<Duration> get onDurationChanged => const Stream<Duration>.empty();

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
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

MockFirebaseAuth _authMe() =>
    MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me'));

Widget _host(
  Widget child, {
  required bool pearl,
  required bool rtl,
  required double textScale,
  required Size size,
}) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
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
        textScaler: TextScaler.linear(textScale),
        disableAnimations: true,
      ),
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
    ),
    home: child,
  ),
);

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
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

enum _Cell { populated, loading, emptyDiscover, emptyFollowing, error }

void main() {
  late PublicIdentityRepository originalIdentity;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  setUp(() {
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: _authMe(),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  Future<void> cell(
    WidgetTester tester, {
    required double width,
    required double height,
    _Cell state = _Cell.populated,
    double textScale = 1,
    bool rtl = false,
    bool pearl = false,
    bool friends = true,
    String tag = '',
  }) async {
    final size = Size(width, height);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = _authMe();
    final firestore = FakeFirebaseFirestore();
    final gate = state == _Cell.loading ? Completer<void>() : null;
    final discovery = switch (state) {
      _Cell.error => _ThrowingDiscovery(),
      _Cell.emptyDiscover ||
      _Cell.emptyFollowing => _StaticDiscovery(const <VoiceMoment>[]),
      _Cell.loading => _StaticDiscovery(_populated, gate: gate),
      _Cell.populated => _StaticDiscovery(_populated),
    };

    await tester.pumpWidget(
      _host(
        MomentsScreen(
          isRootTab: true,
          auth: auth,
          initialFilter: state == _Cell.emptyFollowing
              ? MomentsFilter.following
              : MomentsFilter.discover,
          discoveryService: discovery,
          feedService: _QuietFeed(firestore: firestore, auth: auth),
          viewsService: _StaticViews(const {'m2', 'm6'}),
          friendService: friends
              ? _StaticFriends(firestore: firestore, auth: auth)
              : null,
          followService: FollowService(firestore: firestore, auth: auth),
          playerFactory: _SilentPlayer.new,
        ),
        pearl: pearl,
        rtl: rtl,
        textScale: textScale,
        size: size,
      ),
    );
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final suffix = [
      if (textScale >= 2) 'x2',
      if (rtl) 'rtl',
      if (pearl) 'pearl',
    ].map((tag) => '-$tag').join();
    final stateName = switch (state) {
      _Cell.populated => 'populated',
      _Cell.loading => 'loading',
      _Cell.emptyDiscover => 'empty-discover',
      _Cell.emptyFollowing => 'empty-following',
      _Cell.error => 'error',
    };
    await _shoot(tester, 'moments-06-${width.toInt()}$suffix-$stateName$tag');
    expect(tester.takeException(), isNull, reason: 'no overflow at $width');
    gate?.complete();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('06 populated at the six widths (+ wide-3 threshold)', (
    tester,
  ) async {
    await cell(tester, width: 320, height: 640);
    await cell(tester, width: 390, height: 844);
    await cell(tester, width: 768, height: 1024);
    await cell(tester, width: 1100, height: 800);
    // The two slots a 1440 and a 1464 WINDOW give with the 264 rail: the
    // first is wide-2 (no calm panel), the second is the wide-3 threshold.
    await cell(tester, width: 1176, height: 900);
    await cell(tester, width: 1200, height: 900);
    await cell(tester, width: 1440, height: 900);
    await cell(tester, width: 1464, height: 900);
    await cell(tester, width: 1920, height: 1000);
  });

  testWidgets('06 at 200 % text, RTL and Pearl', (tester) async {
    await cell(tester, width: 320, height: 1400, textScale: 2);
    await cell(tester, width: 1440, height: 900, textScale: 2);
    await cell(tester, width: 390, height: 844, rtl: true);
    await cell(tester, width: 1920, height: 1000, rtl: true);
    await cell(tester, width: 390, height: 844, pearl: true);
    await cell(tester, width: 1920, height: 1000, pearl: true);
  });

  testWidgets('06 states: loading, empty pools, error', (tester) async {
    for (final (width, height) in const <(double, double)>[
      (390, 844),
      (1920, 1000),
    ]) {
      await cell(tester, width: width, height: height, state: _Cell.loading);
      await cell(
        tester,
        width: width,
        height: height,
        state: _Cell.emptyDiscover,
      );
      await cell(
        tester,
        width: width,
        height: height,
        state: _Cell.emptyFollowing,
      );
      await cell(tester, width: width, height: height, state: _Cell.error);
    }
    // Wide-3 with an EMPTY pool: the calm panel must not reserve a column.
    await cell(
      tester,
      width: 1920,
      height: 1000,
      friends: false,
      tag: '-nopool',
    );
  });
}
