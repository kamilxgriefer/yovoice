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
// populated) plus long content, at narrow, medium and wide.
//
// The widths are measured on the space the VIEW receives, not the window:
// MomentDiscoveryView's own breakpoints are 600 and 980, and on desktop the
// shell takes 264 pt for the rail. 390 / 768 / 1100 / 1440 therefore land on
// either side of both.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/data/services/home_feed_service.dart';
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
  }) async => throw StateError('pool query failed');

  @override
  Future<List<VoiceMoment>> topLikedMoments({int limit = 3}) async =>
      throw StateError('pool query failed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietFeed extends HomeFeedService {
  _QuietFeed({super.firestore, super.auth});

  @override
  Stream<bool> watchLiked(String momentId) => Stream<bool>.value(false);

  @override
  Future<void> toggleLike(String momentId) async {}
}

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData.dark(useMaterial3: true),
  home: RepaintBoundary(key: _capture, child: child),
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
