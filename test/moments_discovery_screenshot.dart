// Developer-only visual QA harness for the MOMENTS discovery surface.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/moments_discovery_screenshot.dart
//
// PNGs land in test/.screenshots/ (git-ignored).
//
// Why this exists: `moments_discovery_test.dart` proves the ranking, the
// shuffle, the safety filter and which state KEY is mounted — it never
// proves any of it renders. ADR-059 requires a UI change to be looked at
// before it ships, and the Moments tab reached `main` without that. This
// covers the four states a person can land in (loading, empty, error,
// populated) plus long content, at narrow, medium and wide — for BOTH
// halves of the destination: the Discover avatar board and the compact
// Following grid.
//
// `solo` is not a nicety. Production holds exactly one published Moment,
// so a board that only looks composed when it is full would be broken on
// the only data that actually exists.
//
// The widths are measured on the space the VIEW receives, not the window:
// MomentDiscoveryView's own breakpoints are 600 and 980, and on desktop the
// shell takes 264 pt for the rail. 390 / 768 / 1100 / 1440 therefore land on
// either side of both.

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

import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
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

VoiceMoment _moment(
  String id, {
  required String author,
  required String authorName,
  required String caption,
  int likes = 0,
  int comments = 0,
}) {
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
    createdAt: DateTime(2026, 8, 18, 14, 30),
    schemaVersion: 2,
    status: 'published',
    isDeleted: false,
  );
}

/// Ordered the way the ranker would leave them: most-engaged first. The
/// harness does not re-rank, because what is being photographed is the
/// surface, not the arithmetic — `moments_discovery_test.dart` owns that.
final _populated = <VoiceMoment>[
  _moment(
    'm1',
    author: 'nadia',
    authorName: 'Nadia Rutkowska',
    caption: 'The one thing nobody tells you about moving to a new city.',
    likes: 412,
    comments: 87,
  ),
  _moment(
    'm2',
    author: 'tomas',
    authorName: 'Tomás Oliveira',
    caption: 'Three minutes on why my grandmother never measured anything.',
    likes: 268,
    comments: 51,
  ),
];

/// Production, as measured: one published Moment, 1 like, 1 comment.
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

/// A board with enough faces that the columns, the ranking and the
/// wrapping all have something to prove.
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

/// An [audio.AudioPlayer] that never touches a platform channel.
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

  /// What the Following tab's "From people you follow" section shows.
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
  'schemaVersion': 2,
  'status': 'published',
  'isDeleted': false,
};

/// A MomentService whose `watchMyMoments` really reads the seeded fake,
/// so the Following tab's own-Moments section is rendered by the same
/// code path production uses.
Future<MomentService> _seededMomentService(List<VoiceMoment> mine) async {
  final db = FakeFirebaseFirestore();
  for (final moment in mine) {
    await db.collection('voiceMoments').doc(moment.id).set(_document(moment));
  }
  return MomentService(
    firestore: db,
    auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
    storage: MockFirebaseStorage(),
  );
}

/// The capture boundary sits ABOVE the MaterialApp, not inside `home`.
/// A modal bottom sheet is a route in the Navigator's overlay, which is a
/// sibling of `home` — with the boundary inside it, the sheet frames
/// photographed the page underneath and nothing else.
Widget _host(Widget child) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
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

  HomeFeedService feed() => _QuietFeed(
    firestore: FakeFirebaseFirestore(),
    auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
  );

  Future<void> shootAt(
    WidgetTester tester, {
    required String name,
    required MomentDiscoveryService discovery,
    required double width,
    required double height,
    double textScale = 1.0,
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: MomentsScreen(
            feedService: feed(),
            discoveryService: discovery,
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
    await _shoot(tester, name);

  }

  // 390 phone, 768 tablet (above the view's 600 breakpoint), 1100 and 1440
  // desktop (above 980). Heights are realistic viewports, not square canvases,
  // because a pager that only fits when the frame is tall proves nothing.
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
    String? openTile,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final moments = await _seededMomentService(mine);
    await tester.pumpWidget(
      _host(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: MomentsScreen(
            initialTab: MomentsTab.following,
            momentService: moments,
            feedService: _QuietFeed(
              firestore: FakeFirebaseFirestore(),
              auth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: 'me'),
              ),
              social: social,
            ),
            discoveryService: _StaticDiscovery(const <VoiceMoment>[]),
            // A silent player: constructing a real one reaches for a
            // platform channel that does not exist off-device and
            // reports the failure asynchronously, after the frame has
            // been photographed.
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
    if (openTile != null) {
      await tester.tap(find.byKey(ValueKey('moment-square-$openTile')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }
    await _shoot(tester, name);
  }

  group('moments discovery', () {
    for (final entry in widths.entries) {
      final label = entry.key;
      final (width, height) = entry.value;

      testWidgets('populated $label', (tester) async {
        await shootAt(
          tester,
          name: 'moments-populated-$label',
          discovery: _StaticDiscovery(_populated),
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

    // The board with a real crowd on it: this is what proves the columns,
    // the ranking order and the name wrapping at every width.
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

      // Production's actual corpus: ONE Moment. A board that only looks
      // composed when full is broken on the data that exists today.
      testWidgets('solo $label', (tester) async {
        await shootAt(
          tester,
          name: 'moments-solo-$label',
          discovery: _StaticDiscovery(_solo),
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
              ),
          ],
        );
      });

      // The Following tab with nothing in it: both sections honest, and
      // the recorder still offered.
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

    // The sheet a tile opens: the full card, unchanged, with playback,
    // like, comment and the offline download still on it. Shot at both
    // ends of the range because a bottom sheet stretched across 1440 pt
    // is a phone layout that grew.
    for (final label in <String>['390', '1440']) {
      final (width, height) = widths[label]!;
      testWidgets('following sheet $label', (tester) async {
        await shootFollowing(
          tester,
          name: 'moments-following-sheet-$label',
          width: width,
          height: height,
          openTile: 'mine0',
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
            ),
        ],
      );
    });

    // The two frames most likely to overflow: a very long caption and a very
    // long author name, at the narrowest width, once at normal scale and once
    // at the accessibility scale a real user can set.
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
}
