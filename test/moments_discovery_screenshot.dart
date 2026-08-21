// Developer-only visual QA harness for the MOMENTS stories feed.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/moments_discovery_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored).
//
// Why this exists: `moments_discovery_test.dart` and
// `moments_board_test.dart` prove the ranking, the expiry filter and
// which state KEY is mounted — they never prove any of it renders.
// ADR-059 requires a UI change to be looked at before it ships. This
// covers the states a person can land in (loading, empty, error,
// populated, long content) at narrow, medium and wide, for the feed
// (story strip + featured + recent list + the 1100+ detail panel), the
// story viewer (phone route and desktop dialog), the Following slice and
// its empty state, the sheet a row opens, and the sidebar clock's dotted
// world map.
//
// `solo` is not a nicety. Production holds roughly one live Moment, so a
// feed that only looks composed when it is full would be broken on the
// data that actually exists.
//
// The widths land on either side of the feed's own breakpoints (600 for
// compact padding, 1100 for the detail panel): 390 / 768 / 1100 / 1440.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/sidebar_clock.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
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

  // The app's real typeface. Without it anything styled through
  // AppTypography renders as missing-glyph boxes and the screenshot proves
  // nothing about the copy.
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

/// Every fixture is a LIVE Moment: `expiresAt = createdAt + 24h`, the
/// shape `finalizeMomentDraft` writes — which is also what puts a real
/// "Expires in Xh" label on every frame.
VoiceMoment _moment(
  String id, {
  required String author,
  required String authorName,
  required String caption,
  int likes = 0,
  int comments = 0,
  Duration age = const Duration(hours: 3),
}) {
  final createdAt = DateTime.now().subtract(age);
  return VoiceMoment(
    id: id,
    authorId: author,
    authorName: authorName,
    authorPhotoUrl: null,
    caption: caption,
    audioUrl: 'https://cdn.example/$id.m4a',
    durationSeconds: 27,
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

/// A populated feed with real chain shapes: Nadia holds a 3-Moment
/// chain, Tomás a 2-Moment one — the strip badges, the viewer's progress
/// bars and "1 of 3" all have something to prove.
final _populated = <VoiceMoment>[
  // Nadia's chain in the order it was told: the viewer walks oldest →
  // newest, so "part one" carries the oldest createdAt.
  _moment(
    'm1',
    author: 'nadia',
    authorName: 'Nadia Rutkowska',
    caption: 'The one thing nobody tells you about moving to a new city.',
    likes: 412,
    comments: 87,
    age: const Duration(hours: 9),
  ),
  _moment(
    'm2',
    author: 'nadia',
    authorName: 'Nadia Rutkowska',
    caption: 'Part two — the grocery store epiphany.',
    likes: 121,
    comments: 14,
    age: const Duration(hours: 5),
  ),
  _moment(
    'm3',
    author: 'nadia',
    authorName: 'Nadia Rutkowska',
    caption: 'Part three, recorded on the night bus home.',
    likes: 58,
    comments: 6,
    age: const Duration(hours: 2),
  ),
  _moment(
    'm4',
    author: 'tomas',
    authorName: 'Tomás Oliveira',
    caption: 'Three minutes on why my grandmother never measured anything.',
    likes: 268,
    comments: 51,
    age: const Duration(hours: 4),
  ),
  _moment(
    'm5',
    author: 'tomas',
    authorName: 'Tomás Oliveira',
    caption: 'The follow-up: measuring everything for one week.',
    likes: 34,
    comments: 3,
    age: const Duration(hours: 12),
  ),
  _moment(
    'm6',
    author: 'joana',
    authorName: 'Joana Almeida',
    caption: 'A field recording from the tram, and what it taught me.',
    likes: 91,
    comments: 12,
    age: const Duration(hours: 7),
  ),
];

/// Production, as measured: one live Moment, 1 like, 1 comment.
final _solo = <VoiceMoment>[
  _moment(
    'solo',
    author: 'kamil',
    authorName: 'Kamil',
    caption: 'Testing the very first Voice Moment.',
    likes: 1,
    comments: 1,
  ),
];

/// Enough authors that the strip, the featured rail and the list all
/// have to compose, wrap and scroll.
final _crowd = <VoiceMoment>[
  for (var i = 0; i < 23; i++)
    _moment(
      'c$i',
      author: 'a$i',
      authorName: i.isEven
          ? 'Person $i'
          : 'Aleksandra-Konstantina Wielkopolska $i',
      caption: 'A Moment from person $i.',
      likes: (23 - i) * 3,
      comments: 23 - i,
      age: Duration(hours: 1 + (i % 20)),
    ),
];

final _longContent = <VoiceMoment>[
  _moment(
    'long',
    author: 'aleksandra',
    authorName: 'Aleksandra-Konstantina Wielkopolska-Nowakowska',
    caption:
        'A deliberately long caption that has to wrap without pushing the '
        'transport controls off the viewport, because a Moment whose play '
        'button cannot be reached is a Moment nobody can listen to, and that '
        'is the failure this particular frame exists to rule out.',
    likes: 1284,
    comments: 306,
  ),
];

class _StaticDiscovery implements MomentDiscoveryService {
  _StaticDiscovery(this.moments, {this.gate});

  final List<VoiceMoment> moments;

  /// Holds the load open so the loading state can be photographed, which
  /// otherwise resolves inside the same microtask drain as the first pump.
  ///
  /// A Completer, deliberately, NOT `Future.delayed`: a pending timer trips
  /// `!timersPending` when the tree is disposed, and pumping past it does not
  /// clear it reliably once `runAsync` has been used to capture the frame.
  /// A completer creates no timer at all, so the harness closes it by hand.
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
  Stream<Map<String, MomentEngagement>> watchEngagement({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
  }) => const Stream<Map<String, MomentEngagement>>.empty();

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async => throw StateError('pool query failed');

  @override
  Future<List<VoiceMoment>> topLikedMoments({int limit = 3}) async =>
      throw StateError('pool query failed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An [audio.AudioPlayer] that never touches a platform channel — the
/// story viewer auto-plays on open, and a real player reports its missing
/// channel asynchronously, after the frame has been photographed.
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietFeed extends HomeFeedService {
  _QuietFeed({super.firestore, super.auth, this.social = const []});

  /// What the Following filter's "From your circle" section shows.
  final List<VoiceMoment> social;

  @override
  Stream<List<VoiceMoment>> watchSocialMoments({int limit = 40}) =>
      Stream<List<VoiceMoment>>.value(social);

  @override
  Stream<bool> watchLiked(String momentId) => Stream<bool>.value(false);

  @override
  Future<void> toggleLike(String momentId) async {}
}

Map<String, dynamic> _document(VoiceMoment moment) => <String, dynamic>{
  'authorId': moment.authorId,
  'authorName': moment.authorName,
  'authorPhotoUrl': null,
  'caption': moment.caption,
  'audioUrl': moment.audioUrl,
  'durationSeconds': moment.durationSeconds,
  'likeCount': moment.likeCount,
  'commentCount': moment.commentCount,
  'isPublished': moment.isPublished,
  'createdAt': Timestamp.fromDate(moment.createdAt!),
  'expiresAt': Timestamp.fromDate(moment.expiresAt!),
  'schemaVersion': 2,
  'status': 'published',
  'isDeleted': false,
};

/// A MomentService over a seeded fake, so the Following slice, the sheet
/// and the desktop detail panel's inline comment thread are all rendered
/// by the same code paths production uses.
Future<MomentService> _seededMomentService(
  List<VoiceMoment> mine, {
  Map<String, List<(String, String)>> comments = const {},
}) async {
  final db = FakeFirebaseFirestore();
  for (final moment in mine) {
    await db.collection('voiceMoments').doc(moment.id).set(_document(moment));
  }
  for (final entry in comments.entries) {
    var minute = 0;
    for (final (author, text) in entry.value) {
      minute += 7;
      await db
          .collection('voiceMoments')
          .doc(entry.key)
          .collection('comments')
          .add(<String, dynamic>{
            'authorId': author.toLowerCase(),
            'authorName': author,
            'text': text,
            'type': 'text',
            'createdAt': Timestamp.fromDate(
              DateTime.now().subtract(Duration(minutes: 90 - minute)),
            ),
          });
    }
  }
  return MomentService(
    firestore: db,
    auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
    storage: MockFirebaseStorage(),
  );
}

/// The capture boundary sits ABOVE the MaterialApp, not inside `home`.
/// A modal sheet, the story viewer's route and the desktop dialog are all
/// routes in the Navigator's overlay, which is a sibling of `home` — with
/// the boundary inside it, those frames photographed the page underneath
/// and nothing else.
Widget _host(Widget child) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.darkTheme,
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

void main() {
  late PublicIdentityRepository originalIdentity;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  setUp(() {
    // Identity badges resolve through the shared singleton; point it at a
    // scripted fetcher so no Firebase app is needed.
    originalIdentity = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentity;
  });

  MockFirebaseAuth authMe() =>
      MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me'));

  HomeFeedService feed({List<VoiceMoment> social = const []}) => _QuietFeed(
    firestore: FakeFirebaseFirestore(),
    auth: authMe(),
    social: social,
  );

  void useSize(WidgetTester tester, double width, double height) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> shootAt(
    WidgetTester tester, {
    required String name,
    required MomentDiscoveryService discovery,
    required double width,
    required double height,
    double textScale = 1.0,
    bool settle = true,
    MomentService? momentService,
    MomentViewsService? viewsService,
    String? openChain,
  }) async {
    useSize(tester, width, height);

    await tester.pumpWidget(
      _host(
        MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: TextScaler.linear(textScale),
          ),
          child: MomentsScreen(
            feedService: feed(),
            auth: authMe(),
            discoveryService: discovery,
            momentService: momentService,
            viewsService: viewsService,
            playerFactory: _SilentPlayer.new,
            isRootTab: true,
          ),
        ),
      ),
    );
    await tester.pump();
    if (settle) {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }
    if (openChain != null) {
      await tester.tap(find.byKey(ValueKey('moments-chain-$openChain')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }
    await _shoot(tester, name);
  }

  // 390 phone, 768 tablet, 1100 and 1440 desktop — either side of the
  // feed's 600 (compact) and 1100 (detail panel) breakpoints. Heights are
  // realistic viewports, not square canvases.
  const widths = <String, (double, double)>{
    '390': (390, 844),
    '768': (768, 1024),
    '1100': (1100, 800),
    '1440': (1440, 900),
  };

  Future<void> shootFollowing(
    WidgetTester tester, {
    required String name,
    required double width,
    required double height,
    required List<VoiceMoment> mine,
    required List<VoiceMoment> social,
    double textScale = 1.0,
    String? openRow,
  }) async {
    useSize(tester, width, height);

    final moments = await _seededMomentService(mine);
    await tester.pumpWidget(
      _host(
        MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: TextScaler.linear(textScale),
          ),
          child: MomentsScreen(
            initialTab: MomentsTab.following,
            momentService: moments,
            auth: authMe(),
            feedService: feed(social: social),
            discoveryService: _StaticDiscovery(const <VoiceMoment>[]),
            playerFactory: _SilentPlayer.new,
            isRootTab: true,
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    if (openRow != null) {
      await tester.tap(find.byKey(ValueKey('moment-row-$openRow')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }
    await _shoot(tester, name);
  }

  group('moments feed', () {
    // The composed page at every width: strip + featured + recent list,
    // and from 1100 the right detail panel with the player, the actions
    // and the inline thread. The "Expires in Xh" labels on the rows and
    // in the panel come from the fixtures' real expiresAt.
    for (final entry in widths.entries) {
      final label = entry.key;
      final (width, height) = entry.value;

      testWidgets('populated $label', (tester) async {
        await shootAt(
          tester,
          name: 'moments-populated-$label',
          discovery: _StaticDiscovery(_populated),
          momentService: await _seededMomentService(
            _populated,
            // On the newest Moment, because that is the one the detail
            // panel selects first.
            comments: {
              'm3': [
                ('Tomás Oliveira', 'The night bus is where the truth lives.'),
                ('Joana Almeida', 'Came for part one, stayed for part three.'),
              ],
            },
          ),
          width: width,
          height: height,
        );
      });

      testWidgets('empty $label', (tester) async {
        await shootAt(
          tester,
          name: 'moments-empty-$label',
          discovery: _StaticDiscovery(const <VoiceMoment>[]),
          width: width,
          height: height,
        );
      });

      testWidgets('error $label', (tester) async {
        await shootAt(
          tester,
          name: 'moments-error-$label',
          discovery: _ThrowingDiscovery(),
          width: width,
          height: height,
        );
      });
    }

    testWidgets('loading 390', (tester) async {
      final gate = Completer<void>();
      await shootAt(
        tester,
        name: 'moments-loading-390',
        discovery: _StaticDiscovery(_populated, gate: gate),
        width: 390,
        height: 844,
        settle: false,
      );
      gate.complete();
      await tester.pump();
    });

    testWidgets('loading 1100', (tester) async {
      final gate = Completer<void>();
      await shootAt(
        tester,
        name: 'moments-loading-1100',
        discovery: _StaticDiscovery(_populated, gate: gate),
        width: 1100,
        height: 800,
        settle: false,
      );
      gate.complete();
      await tester.pump();
    });

    // The feed with a real crowd on it: columns, ranking order, name
    // wrapping, and the strip's chain badges at every width.
    for (final entry in widths.entries) {
      final label = entry.key;
      final (width, height) = entry.value;

      testWidgets('crowd $label', (tester) async {
        await shootAt(
          tester,
          name: 'moments-crowd-$label',
          discovery: _StaticDiscovery(_crowd),
          width: width,
          height: height,
        );
      });

      // Production's actual corpus: ONE Moment. A feed that only looks
      // composed when full is broken on the data that exists today.
      testWidgets('solo $label', (tester) async {
        await shootAt(
          tester,
          name: 'moments-solo-$label',
          discovery: _StaticDiscovery(_solo),
          momentService: await _seededMomentService(_solo),
          width: width,
          height: height,
        );
      });

      testWidgets('following $label', (tester) async {
        await shootFollowing(
          tester,
          name: 'moments-following-$label',
          width: width,
          height: height,
          mine: [
            for (var i = 0; i < 3; i++)
              _moment(
                'mine$i',
                author: 'me',
                authorName: 'Kamil',
                caption: 'my moment $i',
                likes: i,
                comments: i * 2,
                age: Duration(hours: 1 + i),
              ),
          ],
          social: [
            for (var i = 0; i < 9; i++)
              _moment(
                'theirs$i',
                author: 'friend$i',
                authorName: i.isEven
                    ? 'Friend $i'
                    : 'Aleksandra-Konstantina Wielkopolska $i',
                caption: 'their moment $i',
                likes: i * 4,
                comments: i,
                age: Duration(hours: 2 + i),
              ),
          ],
        );
      });

      // The Following filter with nothing in it: the honest empty state,
      // with the recorder still offered.
      testWidgets('following empty $label', (tester) async {
        await shootFollowing(
          tester,
          name: 'moments-following-empty-$label',
          width: width,
          height: height,
          mine: const <VoiceMoment>[],
          social: const <VoiceMoment>[],
        );
      });
    }

    // The story viewer, both shells: the full-screen route a phone gets
    // and the centred overlay dialog a desktop window gets. Nadia's chain
    // holds three Moments, so the progress bars and "1 of 3" are real.
    testWidgets('story viewer 390', (tester) async {
      await shootAt(
        tester,
        name: 'moments-viewer-390',
        discovery: _StaticDiscovery(_populated),
        momentService: await _seededMomentService(_populated),
        width: 390,
        height: 844,
        openChain: 'nadia',
      );
    });

    testWidgets('story viewer 1440', (tester) async {
      await shootAt(
        tester,
        name: 'moments-viewer-1440',
        discovery: _StaticDiscovery(_populated),
        momentService: await _seededMomentService(_populated),
        width: 1440,
        height: 900,
        openChain: 'nadia',
      );
    });

    // The sheet a row opens on a narrow surface: the full existing card
    // with playback, like, comment and the offline download. Shot at both
    // ends because a bottom sheet stretched across 1440 pt is a phone
    // layout that grew.
    for (final label in <String>['390', '1440']) {
      final (width, height) = widths[label]!;
      testWidgets('following sheet $label', (tester) async {
        await shootFollowing(
          tester,
          name: 'moments-following-sheet-$label',
          width: width,
          height: height,
          openRow: 'mine0',
          mine: [
            _moment(
              'mine0',
              author: 'me',
              authorName: 'Kamil',
              caption: 'Testing the very first Voice Moment.',
              likes: 1,
              comments: 1,
            ),
          ],
          social: const <VoiceMoment>[],
        );
      });
    }

    testWidgets('crowd 390 at 2x text', (tester) async {
      await shootAt(
        tester,
        name: 'moments-crowd-390-x2',
        discovery: _StaticDiscovery(_crowd),
        width: 390,
        height: 844,
        textScale: 2.0,
      );
    });

    testWidgets('following 390 at 2x text', (tester) async {
      await shootFollowing(
        tester,
        name: 'moments-following-390-x2',
        width: 390,
        height: 844,
        textScale: 2.0,
        mine: [
          _moment(
            'mine0',
            author: 'me',
            authorName: 'Kamil',
            caption: 'my moment',
            likes: 2,
            comments: 1,
          ),
        ],
        social: [
          for (var i = 0; i < 4; i++)
            _moment(
              'theirs$i',
              author: 'friend$i',
              authorName: 'Aleksandra-Konstantina Wielkopolska $i',
              caption: 'their moment $i',
              likes: i * 4,
              age: Duration(hours: 3 + i),
            ),
        ],
      );
    });

    // The two frames most likely to overflow: a very long caption and a
    // very long author name, at the narrowest width, once at normal scale
    // and once at the accessibility scale a real user can set.
    testWidgets('long content 390', (tester) async {
      await shootAt(
        tester,
        name: 'moments-longcontent-390',
        discovery: _StaticDiscovery(_longContent),
        width: 390,
        height: 844,
      );
    });

    testWidgets('long content 390 at 2x text', (tester) async {
      await shootAt(
        tester,
        name: 'moments-longcontent-390-x2',
        discovery: _StaticDiscovery(_longContent),
        width: 390,
        height: 844,
        textScale: 2.0,
      );
    });
  });

  group('sidebar clock', () {
    // The desktop sidebar's local-time block with its dotted world map,
    // in its real 264-pt column at a desktop window size. The time is
    // injected so the frame is reproducible; the zone label and the glow
    // dot's longitude still come from the machine's real UTC offset —
    // the block deliberately names no city and no country.
    testWidgets('sidebar clock map 1440x900', (tester) async {
      useSize(tester, 1440, 900);

      await tester.pumpWidget(
        _host(
          Scaffold(
            backgroundColor: AppColors.background,
            body: Row(
              children: [
                Container(
                  width: 264,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                      right: BorderSide(color: AppColors.divider),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Spacer(),
                      SidebarClock(
                        source: ClockSource(
                          now: () => DateTime(2026, 8, 21, 21, 42),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await _shoot(tester, 'sidebar-clock-map-1440');

      // The clock schedules a minute-boundary timer; unmount it inside
      // the test body so no timer outlives the tree.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
