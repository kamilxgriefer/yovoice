// Independent visual-review capture harness for boards 06, 07 and 08.
//
// Senior Visual Quality Specialist, 2026-09-12. This is the reviewer's OWN
// harness, not the build agents'. It renders the three production surfaces
// through the same seams production uses and writes PNGs the reviewer then
// opens and compares against the accepted boards
// (yovoice-server-concepts-2026-09-10/moments/06|07|08.png) using
// moments-contract-visual.md §9.
//
// It is GATED by a dart-define, so an ordinary suite run registers one
// trivially passing placeholder and renders nothing:
//
//   flutter test test/moments_visual_review_capture_test.dart \
//     --dart-define=YO_CAPTURE_MOMENTS_REVIEW=true --concurrency=1
//
// Frames land in the evidence directory (override with
// --dart-define=YO_CAPTURE_DIR=…), named
// `moments-{06|07|08}-{width}[-x2][-pearl]-{state}.png`.
//
// WIDTH IS THE SLOT the destination receives, not the window. Inside the
// Home shell the 264-px rail turns a 1440 window into a 1176 slot (wide-2)
// and a 1464 window into a 1200 slot (wide-3) — the C36 correction. The
// widths below are slot widths, exactly as moments-contract-visual.md §9
// tabulates them.
//
// Every fixture is controlled, reference-like data: no real account, no real
// recording, no network, no callable. The Reels media is a flat light panel
// on purpose, because white-on-media chrome has to stay legible on the worst
// case.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart' as audio;
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
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_queue_list.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'voice_moment_test_doubles.dart';

const _enabled = bool.fromEnvironment('YO_CAPTURE_MOMENTS_REVIEW');
const _outDir = String.fromEnvironment(
  'YO_CAPTURE_DIR',
  defaultValue:
      '/Users/kamil/Documents/GitHub/yovoice-evidence/2026-09-12/moments-frames',
);

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

Widget _host(
  Widget child, {
  required bool pearl,
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
      child: child!,
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

/// Overflow and assertion failures are FINDINGS, not reasons to abandon the
/// matrix: they are recorded and the run continues so the reviewer still gets
/// the frame that shows the defect.
void _recordException(WidgetTester tester, String name) {
  final error = tester.takeException();
  if (error != null) {
    // ignore: avoid_print
    print('EXCEPTION $name :: $error');
  }
}

// ---------------------------------------------------------------------------
// Board 06 — overview fixtures
// ---------------------------------------------------------------------------

VoiceMoment _moment(
  String id, {
  required String author,
  required String authorName,
  required String caption,
  int seconds = 45,
  int likes = 0,
  int comments = 0,
  Duration age = const Duration(hours: 2),
  bool expired = false,
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
    expiresAt: createdAt.add(
      expired ? const Duration(minutes: 1) : const Duration(hours: 24),
    ),
    schemaVersion: 2,
    status: 'published',
    isDeleted: false,
  );
}

final _feed = <VoiceMoment>[
  _moment(
    'm1',
    author: 'maja',
    authorName: 'Maja',
    caption: 'Zanim obudzi się miasto. Minuta spokoju przed całym dniem.',
    seconds: 45,
    likes: 24,
    comments: 6,
  ),
  _moment(
    'm2',
    author: 'kamil',
    authorName: 'Kamil',
    caption:
        'Mała rzecz, dobry dzień. Czasem to właśnie małe rzeczy robią wielką '
        'różnicę.',
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
        'Nagranie z tramwaju o poranku: dźwięki miasta, które zwykle mijamy '
        'bez uwagi. Chciałam sprawdzić, ile z nich naprawdę słyszymy, kiedy '
        'zwolnimy na minutę. Okazało się, że więcej niż myślałam. Ten opis ma '
        'dokładnie tyle znaków, ile pozwala serwer, żeby sprawdzić trzy linie '
        'i wielokropek na karcie.',
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
];

class _StaticDiscovery implements MomentDiscoveryService {
  _StaticDiscovery(this.moments);

  final List<VoiceMoment> moments;

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) async => MomentDiscoveryFeed(
    moments: moments,
    fetchedCount: moments.length,
    drops: const <String, MomentDropReason>{},
    seed: seed ?? 0,
    poolExhausted: false,
  );

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

// ---------------------------------------------------------------------------
// Board 07 — expanded Voice fixtures
// ---------------------------------------------------------------------------

final _subject = _moment(
  'm1',
  author: 'maja',
  authorName: 'Maja',
  caption: 'Zanim obudzi się miasto',
  seconds: 45,
  likes: 24,
  comments: 6,
);

final _neighbours = <VoiceMoment>[
  _subject,
  _moment(
    'm2',
    author: 'kuba',
    authorName: 'Kuba',
    caption: 'Mała rzecz, dobry dzień',
    seconds: 38,
    age: const Duration(hours: 5),
  ),
  _moment(
    'm3',
    author: 'ania',
    authorName: 'Ania',
    caption: 'Droga bez pośpiechu',
    seconds: 52,
    age: const Duration(hours: 7),
  ),
];

MomentComment _comment({
  required String id,
  required String author,
  required String authorName,
  String text = '',
  int? duration,
  required Duration age,
}) => MomentComment(
  id: id,
  type: duration == null ? 'text' : 'voice',
  authorId: author,
  authorName: authorName,
  authorPhotoUrl: null,
  text: text,
  durationSeconds: duration ?? 0,
  createdAt: DateTime.now().subtract(age),
  reportReceipt: 'capture-receipt',
);

final _thread = <MomentComment>[
  _comment(
    id: 'c1',
    author: 'ola',
    authorName: 'Ola',
    duration: 12,
    text: 'Też potrzebowałam takiego poranka.',
    age: const Duration(hours: 2),
  ),
  _comment(
    id: 'c2',
    author: 'bartek',
    authorName: 'Bartek',
    text: 'Ten spokój zostaje na dłużej.',
    age: const Duration(hours: 4),
  ),
];

class _CaptureMoments extends MomentService {
  _CaptureMoments({this.comments = const <MomentComment>[], this.subject})
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
        storage: MockFirebaseStorage(),
        mediaAccessInvoker: fakeMomentMediaAccessInvoker(),
      );

  final List<MomentComment> comments;
  final VoiceMoment? subject;

  @override
  Future<VoiceMomentViewV2> loadMomentView(
    String momentId, {
    String? commentCursor,
    int commentLimit = 7,
    int reactionLimit = 3,
  }) async {
    final opened = subject;
    final moment = opened != null && opened.id == momentId
        ? opened
        : _neighbours.firstWhere(
            (item) => item.id == momentId,
            orElse: () => _subject,
          );
    return VoiceMomentViewV2(
      moment: moment,
      comments: comments,
      commentsTruncated: false,
      nextCommentCursor: null,
      topReactions: const <MomentReactor>[],
    );
  }

  @override
  Future<Uri> resolveMediaUri({
    required String momentId,
    String? commentId,
  }) async => Uri.parse('https://storage.googleapis.com/capture/$momentId.m4a');
}

class _CapturePlayer implements audio.AudioPlayer {
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration>.broadcast();

  @override
  Stream<Duration> get onPositionChanged => _positions.stream;

  @override
  Stream<Duration> get onDurationChanged => _durations.stream;

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
  }) async {
    _durations.add(const Duration(seconds: 45));
  }

  void emit(Duration position) => _positions.add(position);

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async => _positions.add(position);

  @override
  Future<void> dispose() async {
    unawaited(_positions.close());
    unawaited(_durations.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// ---------------------------------------------------------------------------
// Board 08 — Reels fixtures
// ---------------------------------------------------------------------------

const _reelCaptions = <String>[
  'Poranek w porcie, zanim ruszą pierwsze łodzie',
  'Mała rzecz, dobry dzień',
];

Map<String, Object?> _reelWire(int index) {
  final millis = 1725000000000 + index;
  return <String, Object?>{
    'id': 'reel_$index',
    'authorId': 'creator_$index',
    'authorName': index == 1 ? 'Maja Nowak' : 'Kuba',
    'media': <String, Object?>{
      'kind': 'video',
      'contentType': 'video/mp4',
      'size': 4096,
      'generation': '7',
      'durationMs': 18000,
    },
    'backingAudio': null,
    'composition': ReelComposition(
      trimStartMs: 0,
      trimEndMs: 18000,
      originalAudioVolume: 100,
      caption: _reelCaptions[index - 1],
    ).toWire(),
    'publishedAtMillis': millis,
    'sortKey': '${millis}_reel_$index',
    'availability': <String, Object?>{
      'schemaVersion': 1,
      'availabilityHours': 'permanent',
      'expiresAtMillis': null,
    },
    'likeCount': index == 1 ? 42 : 8,
    'commentCount': index == 1 ? 8 : 1,
    'callerLiked': false,
  };
}

enum _ReelCell { populated, thread, empty, error }

ReelService _reelService(_ReelCell state) => ReelService(
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'me', isEmailVerified: true),
  ),
  callableInvoker: (name, payload) async {
    switch (name) {
      case 'listReelsV2':
        if (state == _ReelCell.error) throw StateError('offline');
        return <Object?, Object?>{
          'schemaVersion': 2,
          'items': state == _ReelCell.empty
              ? <Object?>[]
              : <Object?>[_reelWire(1), _reelWire(2)],
          'nextCursor': null,
        };
      case 'getReelMediaAccessV2':
        return <Object?, Object?>{
          'schemaVersion': 2,
          'url': 'https://storage.googleapis.com/yovoice/reel.mp4',
          'expiresAtMillis': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'generation': '7',
          'availabilityHours': 'permanent',
          'contentExpiresAtMillis': null,
        };
      case 'getReelViewV2':
        return <Object?, Object?>{
          'schemaVersion': 2,
          'reel': _reelWire(1),
          'comments': <Object?>[
            for (final entry in const <List<String>>[
              ['c1', 'Ola', 'To ujęcie o świcie jest cudowne.'],
              ['c2', 'Kuba', 'Gdzie to było?'],
            ])
              <String, Object?>{
                'schemaVersion': 1,
                'commentId': entry[0],
                'type': 'text',
                'authorId': entry[0],
                'authorName': entry[1],
                'authorPhotoUrl': null,
                'text': entry[2],
                'durationSeconds': null,
                'createdAtMillis': 1725000000000,
              },
          ],
          'commentsTruncated': false,
          'nextCommentCursor': null,
        };
      case 'listReelCommentsV2':
        return <Object?, Object?>{
          'schemaVersion': 2,
          'items': <Object?>[],
          'nextCursor': null,
        };
    }
    throw StateError('Unexpected callable $name with $payload');
  },
);

FollowService _follows() => FollowService(
  firestore: FakeFirebaseFirestore(),
  auth: MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'me', isEmailVerified: true),
  ),
  mutationInvoker: (_) async => <String, dynamic>{},
);

Widget _footage(BuildContext context, Uri uri, Object reel) =>
    const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFEFE6DA), Color(0xFF9FB3C8)],
        ),
      ),
    );

MockFirebaseAuth _authMe() =>
    MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me'));

// ---------------------------------------------------------------------------

enum _State { populated, empty, error, thread }

typedef _Frame = ({
  String board,
  double width,
  double height,
  _State state,
  bool pearl,
  double textScale,
});

String _frameName(_Frame frame) {
  final suffix = [
    if (frame.textScale >= 2) 'x2',
    if (frame.pearl) 'pearl',
  ].map((tag) => '-$tag').join();
  final state = switch (frame.state) {
    _State.populated => 'populated',
    _State.empty => 'empty',
    _State.error => 'error',
    _State.thread => 'thread',
  };
  return 'moments-${frame.board}-${frame.width.toInt()}$suffix-$state';
}

const _widths = <(double, double)>[
  (320, 568),
  (390, 844),
  (768, 1024),
  (1100, 900),
  (1440, 900),
  (1920, 1000),
];

List<_Frame> _matrix(String board) => <_Frame>[
  for (final (width, height) in _widths)
    (
      board: board,
      width: width,
      height: height,
      state: _State.populated,
      pearl: false,
      textScale: 1,
    ),
  for (final (width, height) in _widths)
    (
      board: board,
      width: width,
      height: height,
      state: _State.populated,
      pearl: true,
      textScale: 1,
    ),
  for (final (width, height) in _widths)
    (
      board: board,
      width: width,
      height: height,
      state: _State.populated,
      pearl: false,
      textScale: 2,
    ),
  // Round 2 widens the Pearl x2 row from the single 1440 cell to every
  // width. The round-1 report could not say whether S2's mid-word breaks and
  // S3's collapsed names were dark-only; with the full row it can.
  for (final (width, height) in _widths)
    (
      board: board,
      width: width,
      height: height,
      state: _State.populated,
      pearl: true,
      textScale: 2,
    ),
  for (final (width, height) in const <(double, double)>[
    (390, 844),
    (1440, 900),
  ]) ...<_Frame>[
    (
      board: board,
      width: width,
      height: height,
      state: _State.empty,
      pearl: false,
      textScale: 1,
    ),
    (
      board: board,
      width: width,
      height: height,
      state: _State.error,
      pearl: false,
      textScale: 1,
    ),
  ],
];

void main() {
  if (!_enabled) {
    test('capture harness is gated behind YO_CAPTURE_MOMENTS_REVIEW', () {
      expect(_enabled, isFalse);
    });
    return;
  }

  late PublicIdentityRepository originalIdentity;

  setUpAll(_loadFonts);

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

  void sizeView(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shoot06(WidgetTester tester, _Frame frame) async {
    final size = Size(frame.width, frame.height);
    sizeView(tester, size);
    final auth = _authMe();
    final firestore = FakeFirebaseFirestore();
    final discovery = switch (frame.state) {
      _State.error => _ThrowingDiscovery(),
      _State.empty => _StaticDiscovery(const <VoiceMoment>[]),
      _ => _StaticDiscovery(_feed),
    };

    await tester.pumpWidget(
      _host(
        MomentsScreen(
          key: UniqueKey(),
          isRootTab: true,
          auth: auth,
          discoveryService: discovery,
          feedService: _QuietFeed(firestore: firestore, auth: auth),
          viewsService: _StaticViews(const {'m2', 'm5'}),
          friendService: _StaticFriends(firestore: firestore, auth: auth),
          followService: FollowService(firestore: firestore, auth: auth),
          playerFactory: _SilentPlayer.new,
        ),
        pearl: frame.pearl,
        textScale: frame.textScale,
        size: size,
      ),
    );
    await settle(tester);
  }

  Future<void> shoot07(WidgetTester tester, _Frame frame) async {
    final size = Size(frame.width, frame.height);
    sizeView(tester, size);

    final players = <_CapturePlayer>[];
    final queue = MomentNeighbourQueue()
      ..publish(viewerUid: 'me', moments: _neighbours);
    addTearDown(queue.dispose);

    // For 07 the three cells map to the states the contract names for this
    // view (§9.2): populated = listening at 40 %, empty = an empty thread,
    // error = the gone state a deep link to an expired Moment renders.
    final opened = frame.state == _State.error
        ? _moment(
            'm1',
            author: 'maja',
            authorName: 'Maja',
            caption: 'Zanim obudzi się miasto',
            age: const Duration(hours: 30),
            expired: true,
          )
        : _subject;

    await tester.pumpWidget(
      _host(
        MomentDetailScreen(
          key: UniqueKey(),
          moment: opened,
          momentService: _CaptureMoments(
            subject: opened,
            comments: frame.state == _State.empty
                ? const <MomentComment>[]
                : _thread,
          ),
          auth: _authMe(),
          neighbourQueue: queue,
          playerFactory: () {
            final player = _CapturePlayer();
            players.add(player);
            return player;
          },
        ),
        pearl: frame.pearl,
        textScale: frame.textScale,
        size: size,
      ),
    );
    await settle(tester);

    if (frame.state == _State.populated) {
      final disc = find.byKey(const ValueKey('moment-detail-play'));
      if (disc.evaluate().isNotEmpty) {
        await tester.ensureVisible(disc);
        await tester.pump();
        await tester.tap(disc, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        if (players.isNotEmpty) {
          players.last.emit(const Duration(seconds: 18));
        }
        await tester.pump();
      }
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('moment-detail-scroll')),
        matching: find.byType(Scrollable),
      );
      if (scrollable.evaluate().isNotEmpty) {
        tester.state<ScrollableState>(scrollable.first).position.jumpTo(0);
        await tester.pump();
      }
    }
  }

  Future<void> shoot08(WidgetTester tester, _Frame frame) async {
    final size = Size(frame.width, frame.height);
    sizeView(tester, size);
    final state = switch (frame.state) {
      _State.empty => _ReelCell.empty,
      _State.error => _ReelCell.error,
      _State.thread => _ReelCell.thread,
      _State.populated => _ReelCell.populated,
    };

    await tester.pumpWidget(
      _host(
        MomentsScreen(
          key: UniqueKey(),
          isRootTab: true,
          initialFormat: YoMomentsFormat.reels,
          reelService: _reelService(state),
          reelVideoBuilder: _footage,
          followService: _follows(),
          onCreateReel: () async {},
        ),
        pearl: frame.pearl,
        textScale: frame.textScale,
        size: size,
      ),
    );
    await settle(tester);

    if (frame.state == _State.thread) {
      final toggle = find.byKey(
        const ValueKey<String>('reel-panel-thread-toggle'),
      );
      if (toggle.evaluate().isNotEmpty) {
        await tester.tap(toggle, warnIfMissed: false);
        await settle(tester);
      }
    }
  }

  for (final frame in <_Frame>[
    ..._matrix('06'),
    ..._matrix('07'),
    ..._matrix('08'),
    // The docked conversation beside a playing Reel (D5) is a board-08 cell
    // of its own.
    (
      board: '08',
      width: 1440,
      height: 900,
      state: _State.thread,
      pearl: false,
      textScale: 1,
    ),
    (
      board: '08',
      width: 1920,
      height: 1000,
      state: _State.thread,
      pearl: false,
      textScale: 1,
    ),
  ]) {
    final name = _frameName(frame);
    testWidgets(name, (tester) async {
      switch (frame.board) {
        case '06':
          await shoot06(tester, frame);
        case '07':
          await shoot07(tester, frame);
        case '08':
          await shoot08(tester, frame);
      }
      await _shoot(tester, name);
      _recordException(tester, name);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    });
  }
}
