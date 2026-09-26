// Slim redesign phase 4 (YO Moments) frame harness, extended for the
// refine-look batch 5 (voice bead + Głos, spec §11 "Głos / detail").
//
// Adapted from `test/moments_visual_review_capture_test.dart` (same fixtures,
// same production seams): the Moments screen with Głos selected, with Yeels
// selected, and the Moment detail view, at 390, 768 and 1440, Dark and
// Pearl, locale pl, 100 % and 200 % text.
//
// States (refine-look §11):
// * Głos (`moments-voice`): populated (idle; m4 is the uncaptioned card),
//   playing (m1 at 40 % — the one lit card), paused (m1 paused at 40 %),
//   failed (m1's grant refused), expiring (m1 inside its last hour — the
//   amber pill), loading, empty, error.
// * Detail (`moment-detail`): populated (listening at 40 %, lit), paused
//   (paused at 40 %), empty (empty thread), error (the gone state).
// * Yeels (`moments-yeels`): populated (the over-media chips and switch);
//   white (refine-look batch 6: the same stage over a PURE WHITE frame, the
//   worst case the §11 "chrome text on a white frame" measurement needs).
// * Głos `create` (batch 6): the create chooser opened from the "+" (the
//   R6 disc) or, at 1440, the panel's "Utwórz" — its R2 tiles.
// * Recorder (`voice-recorder`, batch 6, spec §5 W4): idle (the lifted
//   bead), requesting (the microphone prompt open), recording (a spoken
//   phrase of real-shaped levels — the halo swollen by the last samples),
//   silent (the same take gone quiet for over 3 s — the halo settled, the
//   silence hint), review (the take stopped: preview, fields, actions).
//   Immersive in both themes, so Dark and Pearl must match.
// * Yeel stage (`yeels-stage`, batch 6): the stage itself with a finger held
//   on the first Reel's timeline at 62 % (`scrub`: the thick track, thumb
//   and time) and after letting go (`played`: the 2 px hairline keeps the
//   committed position) — the theme-invariant brand sweep. It is the Yeel
//   stage the Moments screen embeds, pumped directly with the test engines
//   (`FakeReelPlayers`) so a position exists at all; at 390 and 768 it
//   carries the Moments immersive header, as the screen hands it over.
// * High contrast (`-hc` suffix on the state): Głos playing and detail
//   populated at 390, both themes, 100 %; the recorder recording at 390.
// Reduce Motion is on for every frame (the host sets disableAnimations), so
// each frame is the settled end state: no pour tween, lit light already in.
// The recorder is the exception: its moment IS motion (the halo follows the
// voice), so its frames run with motion on and its Reduce Motion frames
// carry an `-rm` suffix (recording at 390: the fixed halo).
//
// Frames render with REAL shadows: flutter_test paints every BoxShadow as a
// hard, unblurred block by default (`debugDisableShadows`, meant for golden
// stability), which would misrepresent the bead's contact shadow and glow,
// the CTA lift and Pearl's block shadows. The flag is off while a frame is
// rendered and restored inside the test body, before the binding checks its
// painting invariants. The `-hc` frames use the app's high-contrast theme
// twins (`AppTheme.*HighContrastTheme`), as lib/app/app.dart hands them over.
// Asset images (the page scenery) get a short real-time window to decode, so
// every state shows the same backdrop.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/slim_moments_capture.dart --concurrency=1 \
//     --dart-define=YO_CAPTURE_DIR=<evidence>/frames/after/moments
//
// Narrow a run with `--dart-define=YO_CAPTURE_ONLY=<a>,<b>`: only frames
// whose name contains one of the comma-separated fragments are rendered
// (for example `moments-voice_768,_200_playing`).
//
// Frames are named `<screen>_<width>_<dark|pearl>_pl_<100|200>_<state>.png`
// (`moments-voice`, `moments-yeels`, `moment-detail`, `voice-recorder`,
// `yeels-stage`).
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
import 'package:record/record.dart' show Amplitude;

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_recorder.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_queue_list.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_progress_row.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'reel_stage_test_support.dart';
import 'voice_moment_test_doubles.dart';

const _outDir = String.fromEnvironment(
  'YO_CAPTURE_DIR',
  defaultValue: 'test/.screenshots/slim-p4',
);

/// Comma-separated name fragments; empty renders the whole matrix.
const _only = String.fromEnvironment('YO_CAPTURE_ONLY');

final _capture = GlobalKey();

/// The Material fonts of whichever Flutter SDK runs the test: walked up from
/// the tester binary (`<sdk>/bin/cache/artifacts/engine/...`), with the Mac
/// install paths as fallbacks.
String get _fontRoot {
  final candidates = <String>[];
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    candidates.add('${dir.path}/bin/cache/artifacts/material_fonts');
    candidates.add('${dir.path}/material_fonts');
    dir = dir.parent;
  }
  candidates.addAll(const <String>[
    '/opt/homebrew/Caskroom/flutter/3.44.6/flutter/bin/cache/artifacts/material_fonts',
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

Widget _host(
  Widget child, {
  required bool pearl,
  required double textScale,
  required Size size,
  bool highContrast = false,
  bool reduceMotion = true,
}) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: switch ((pearl, highContrast)) {
      (true, true) => AppTheme.lightHighContrastTheme,
      (false, true) => AppTheme.darkHighContrastTheme,
      (true, false) => AppTheme.lightTheme,
      (false, false) => AppTheme.darkTheme,
    },
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
        disableAnimations: reduceMotion,
        highContrast: highContrast,
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

/// The first page never arrives: the loading skeleton.
class _PendingDiscovery implements MomentDiscoveryService {
  final _never = Completer<MomentDiscoveryFeed>();

  @override
  Future<MomentDiscoveryFeed> loadDiscoveryFeed({
    int poolSize = MomentDiscoveryService.defaultPoolSize,
    int? seed,
  }) => _never.future;

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

/// The Głos feed with m1 inside its last hour (the amber R12 pill): it was
/// published 23 h 18 min ago with the default 24 h availability.
List<VoiceMoment> _expiringFeed() => <VoiceMoment>[
  _moment(
    'm1',
    author: 'maja',
    authorName: 'Maja',
    caption: 'Zanim obudzi się miasto. Minuta spokoju przed całym dniem.',
    seconds: 45,
    likes: 24,
    comments: 6,
    age: const Duration(hours: 23, minutes: 18),
  ),
  ..._feed.skip(1),
];

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

/// A grant that is refused: the feed's failed-playback state.
class _RefusingMoments extends _CaptureMoments {
  @override
  Future<Uri> resolveMediaUri({
    required String momentId,
    String? commentId,
  }) async => throw StateError('capture: grant refused');
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

/// The worst case for white chrome: a pure white frame (batch 6, the §11
/// "chrome text on a white frame" measurement).
Widget _whiteFootage(BuildContext context, Uri uri, Object reel) =>
    const ColoredBox(color: Colors.white);

MockFirebaseAuth _authMe() =>
    MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me'));

// ---------------------------------------------------------------------------

enum _State {
  populated,
  empty,
  error,
  thread,
  loading,
  playing,
  paused,
  failed,
  expiring,
  // Batch 6.
  white,
  create,
  idle,
  requesting,
  recording,
  silent,
  review,
  scrub,
  played,
}

typedef _Frame = ({
  String board,
  double width,
  double height,
  _State state,
  bool pearl,
  double textScale,
  bool highContrast,
  bool reduceMotion,
});

/// Boards whose moment is motion: they render with motion ON, and their
/// Reduce Motion frames carry an `-rm` suffix. Every other board renders
/// under Reduce Motion (the settled end state) without a suffix.
const _motionBoards = <String>{'09'};

/// `<screen>_<width>_<dark|pearl>_pl_<100|200>_<state>[-hc][-rm]`, the Slim
/// frame naming.
String _frameName(_Frame frame) {
  final screen = switch (frame.board) {
    '06' => 'moments-voice',
    '07' => 'moment-detail',
    '09' => 'voice-recorder',
    '10' => 'yeels-stage',
    _ => 'moments-yeels',
  };
  final theme = frame.pearl ? 'pearl' : 'dark';
  final scale = frame.textScale >= 2 ? '200' : '100';
  final state = frame.state.name;
  final hc = frame.highContrast ? '-hc' : '';
  final rm = _motionBoards.contains(frame.board) && frame.reduceMotion
      ? '-rm'
      : '';
  return '${screen}_${frame.width.toInt()}_${theme}_pl_${scale}_$state$hc$rm';
}

const _widths = <(double, double)>[(390, 844), (768, 1024), (1440, 900)];
const _scales = <double>[1, 2];

List<_Frame> _matrix(String board, List<_State> states) => <_Frame>[
  for (final state in states)
    for (final pearl in const <bool>[false, true])
      for (final (width, height) in _widths)
        for (final scale in _scales)
          (
            board: board,
            width: width,
            height: height,
            state: state,
            pearl: pearl,
            textScale: scale,
            highContrast: false,
            reduceMotion: !_motionBoards.contains(board),
          ),
];

/// High contrast: no glow, gloss or tint; the playing card carries a 1.5 px
/// ink edge instead (refine-look W3); the recorder drops its halo (W4).
List<_Frame> _highContrast(String board, _State state) => <_Frame>[
  for (final pearl in const <bool>[false, true])
    (
      board: board,
      width: 390,
      height: 844,
      state: state,
      pearl: pearl,
      textScale: 1,
      highContrast: true,
      reduceMotion: !_motionBoards.contains(board),
    ),
];

/// Reduce Motion on a motion board: the recorder's fixed halo (W4).
List<_Frame> _reduceMotion(String board, _State state) => <_Frame>[
  for (final pearl in const <bool>[false, true])
    (
      board: board,
      width: 390,
      height: 844,
      state: state,
      pearl: pearl,
      textScale: 1,
      highContrast: false,
      reduceMotion: true,
    ),
];

bool _selected(String name) {
  if (_only.trim().isEmpty) return true;
  return _only
      .split(',')
      .map((fragment) => fragment.trim())
      .where((fragment) => fragment.isNotEmpty)
      .any(name.contains);
}

void main() {
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
    // Real time for asset decodes (the scenery), which fake time never runs.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
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
      _State.loading => _PendingDiscovery(),
      _State.expiring => _StaticDiscovery(_expiringFeed()),
      _ => _StaticDiscovery(_feed),
    };
    final plays =
        frame.state == _State.playing ||
        frame.state == _State.paused ||
        frame.state == _State.failed;
    final players = <_CapturePlayer>[];

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
          // The playback states need the real grant seam and a player that
          // reports positions; the still states keep the silent one.
          momentService: !plays
              ? null
              : frame.state == _State.failed
              ? _RefusingMoments()
              : _CaptureMoments(),
          playerFactory: plays
              ? () {
                  final player = _CapturePlayer();
                  players.add(player);
                  return player;
                }
              : _SilentPlayer.new,
        ),
        pearl: frame.pearl,
        textScale: frame.textScale,
        size: size,
        highContrast: frame.highContrast,
      ),
    );
    await settle(tester);

    if (frame.state == _State.create) {
      // Batch 6: the chooser the "+" disc (or, at 1440, the panel's
      // "Utwórz") opens — its R2 tiles. A miss is a finding in the frame.
      final create = find.byKey(const ValueKey('moments-create-cta'));
      if (create.evaluate().isNotEmpty) {
        await tester.tap(create.first, warnIfMissed: false);
        await settle(tester);
      }
    }

    if (plays || frame.state == _State.expiring) {
      // The feed is newest-first, so m1 (2 h old, or 23 h 18 min in the
      // expiring feed) is not the first card. Scroll its card into view with
      // a sliver of the card above it, so every width shows the lit card —
      // or the amber pill — next to an unlit neighbour. This happens BEFORE
      // the tap: on a phone the Głos header overlays the top of the list, so
      // a play button scrolled flush to the top would sit under it.
      final row = find.byKey(const ValueKey('moment-row-m1'));
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('moments-feed-scroll')),
        matching: find.byType(Scrollable),
      );
      if (row.evaluate().isEmpty && scrollable.evaluate().isNotEmpty) {
        // A lazy list builds only near the viewport: page down until the
        // card exists.
        await tester.scrollUntilVisible(
          row,
          300,
          scrollable: scrollable.first,
          maxScrolls: 20,
        );
      }
      if (row.evaluate().isNotEmpty) {
        await Scrollable.ensureVisible(
          tester.element(row.first),
          alignment: .12,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    if (plays) {
      // m1 is the subject: start it, report 18 of 45 s (40 %), and for the
      // paused frame stop there. A miss is a finding, not a silent frame.
      final play = find.byKey(const ValueKey('moment-row-play-m1'));
      if (play.evaluate().isNotEmpty) {
        await tester.tap(play);
        await settle(tester);
        if (players.isNotEmpty) {
          // The broadcast report lands on a microtask: settle so the frame
          // shows it.
          players.last.emit(const Duration(seconds: 18));
          await settle(tester);
        }
        if (frame.state == _State.paused) {
          await tester.tap(play);
          await settle(tester);
        }
      }
    }
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
        highContrast: frame.highContrast,
      ),
    );
    await settle(tester);

    if (frame.state == _State.populated || frame.state == _State.paused) {
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
        if (frame.state == _State.paused) {
          await tester.tap(disc, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
        }
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
      _ => _ReelCell.populated,
    };

    await tester.pumpWidget(
      _host(
        MomentsScreen(
          key: UniqueKey(),
          isRootTab: true,
          initialFormat: YoMomentsFormat.reels,
          reelService: _reelService(state),
          reelVideoBuilder: frame.state == _State.white
              ? _whiteFootage
              : _footage,
          followService: _follows(),
          onCreateReel: () async {},
        ),
        pearl: frame.pearl,
        textScale: frame.textScale,
        size: size,
        highContrast: frame.highContrast,
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

  /// A spoken phrase as the microphone reports it (dBFS, about eight
  /// samples a second): the recorder normalises each one exactly as it does
  /// a real microphone's, so the meter and the halo show real-shaped input.
  const phrase = <double>[
    -38, -30, -22, -14, -9, -12, -18, -11, -7, -10, //
    -16, -24, -13, -8, -6, -9, -15, -21, -12, -7,
  ];

  /// The `requesting` frame's microphone prompt, held open until the frame
  /// is shot and the screen is gone; answering it then ends the request's
  /// 20 s timeout with the test.
  Completer<MicrophoneAccess>? openPrompt;

  Future<void> shoot09(WidgetTester tester, _Frame frame) async {
    final size = Size(frame.width, frame.height);
    sizeView(tester, size);
    final backend = FakeRecorderBackend();
    final capture = FakeAudioCapture()..result = FakeRecordedAudio();
    if (frame.state == _State.requesting) {
      // The microphone prompt stays open: the request never answers.
      capture.microphoneGate = openPrompt = Completer<MicrophoneAccess>();
    }
    final clock = FakeStopwatch();

    await tester.pumpWidget(
      _host(
        RecordVoiceMomentScreen(
          key: UniqueKey(),
          recorder: VoiceMomentRecorder(
            backend: backend,
            capture: capture,
            clock: clock,
          ),
          momentService: StubMomentService(),
          previewPlayerFactory: () =>
              FakePreviewAudioPlayer(duration: const Duration(seconds: 23)),
        ),
        pearl: frame.pearl,
        textScale: frame.textScale,
        size: size,
        highContrast: frame.highContrast,
        reduceMotion: frame.reduceMotion,
      ),
    );
    await settle(tester);

    final mic = find.byIcon(Icons.mic_rounded);
    if (mic.evaluate().isEmpty) return;
    // Centre the bead: at 200 % it sits below the fold of a phone.
    await Scrollable.ensureVisible(tester.element(mic), alignment: .5);
    await tester.pump();
    if (frame.state == _State.idle) return;

    await tester.tap(mic, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    if (frame.state == _State.requesting) {
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }

    for (var i = 0; i < phrase.length; i++) {
      clock.value = Duration(milliseconds: 1000 + i * 1100);
      backend.amplitudes.add(Amplitude(current: phrase[i], max: 0));
      await tester.pump(const Duration(milliseconds: 125));
    }
    var end = const Duration(seconds: 23);
    if (frame.state == _State.silent) {
      // The take goes quiet for longer than the 3 s silence warning: the
      // halo settles on real zero samples and the hint appears.
      for (var i = 0; i < 14; i++) {
        clock.value = Duration(milliseconds: 23000 + i * 300);
        backend.amplitudes.add(Amplitude(current: -160, max: -160));
        await tester.pump(const Duration(milliseconds: 125));
      }
      end = const Duration(seconds: 27);
    }
    clock.value = end;
    // The clock's own tick and the halo's last ease.
    await tester.pump(const Duration(milliseconds: 250));

    if (frame.state == _State.review) {
      final stop = find.byIcon(Icons.stop_rounded);
      if (stop.evaluate().isEmpty) return;
      await tester.ensureVisible(stop);
      await tester.pump();
      await tester.tap(stop, warnIfMissed: false);
      await settle(tester);
    }
  }

  /// The finger that holds the `scrub` frame's timeline until it is shot.
  TestGesture? held;

  Future<void> shoot10(WidgetTester tester, _Frame frame) async {
    final size = Size(frame.width, frame.height);
    sizeView(tester, size);
    final players = FakeReelPlayers();
    // The Moments screen embeds the stage immersively below its 1100 px
    // local-panel breakpoint and hands it the immersive header there — its
    // canvas variant at the card-stage widths (600-1099), exactly as
    // `MomentsScreen` does since the batch-6 review.
    final immersive = frame.width < 1100;
    final onCanvas = immersive && frame.width >= 600;

    await tester.pumpWidget(
      _host(
        Scaffold(
          key: UniqueKey(),
          body: SafeArea(
            child: Builder(
              builder: (context) => ReelsFeedScreen(
                embedded: true,
                immersive: immersive,
                immersiveHeader: immersive
                    ? buildImmersiveMomentsHeader(
                        context,
                        showBack: false,
                        selectedFormat: YoMomentsFormat.reels,
                        onFormatSelected: (_) {},
                        onCreate: () {},
                        onCanvas: onCanvas,
                      )
                    : null,
                service: _reelService(_ReelCell.populated),
                audioPlaybackFactory: FakeReelAudioPlayback.new,
                videoPlaybackFactory: (uri, reel) => players.of(reel.id),
                videoBuilder: _footage,
                onCreate: () async {},
              ),
            ),
          ),
        ),
        pearl: frame.pearl,
        textScale: frame.textScale,
        size: size,
        highContrast: frame.highContrast,
        reduceMotion: frame.reduceMotion,
      ),
    );
    await settle(tester);

    final band = find.descendant(
      of: find.byType(ReelCard).first,
      matching: find.byKey(const ValueKey<String>('reel-progress-scrub')),
    );
    if (band.evaluate().isEmpty) return;
    final rect = tester.getRect(band.first);
    // The finger maps onto the visible bar's own extent, which on the card
    // stage (768, 1440) is narrower than the band (the times sit beside
    // it): aim at 20 % and 62 % of the bar itself, inside the band.
    final bar = find.descendant(
      of: find.byType(ReelCard).first,
      matching: find.byType(ReelProgressBar),
    );
    final track = bar.evaluate().isEmpty ? rect : tester.getRect(bar.first);
    final y = rect.bottom - 4;
    final gesture = await tester.startGesture(
      Offset(track.left + track.width * .2, y),
    );
    await gesture.moveTo(Offset(track.left + track.width * .62, y));
    await settle(tester);
    if (frame.state == _State.scrub) {
      held = gesture;
      return;
    }
    await gesture.up();
    await settle(tester);
  }

  for (final frame in <_Frame>[
    ..._matrix('06', const <_State>[
      _State.populated,
      _State.playing,
      _State.paused,
      _State.failed,
      _State.expiring,
      _State.loading,
      _State.empty,
      _State.error,
    ]),
    ..._highContrast('06', _State.playing),
    ..._matrix('07', const <_State>[
      _State.populated,
      _State.paused,
      _State.empty,
      _State.error,
    ]),
    ..._highContrast('07', _State.populated),
    ..._matrix('08', const <_State>[_State.populated]),
    // Batch 6 — capture and Yeels.
    ..._matrix('06', const <_State>[_State.create]),
    ..._matrix('08', const <_State>[_State.white]),
    ..._matrix('09', const <_State>[
      _State.idle,
      _State.requesting,
      _State.recording,
      _State.silent,
      _State.review,
    ]),
    ..._highContrast('09', _State.recording),
    ..._reduceMotion('09', _State.recording),
    ..._matrix('10', const <_State>[_State.scrub, _State.played]),
  ]) {
    final name = _frameName(frame);
    if (!_selected(name)) continue;
    testWidgets(name, (tester) async {
      debugDisableShadows = false;
      try {
        switch (frame.board) {
          case '06':
            await shoot06(tester, frame);
          case '07':
            await shoot07(tester, frame);
          case '08':
            await shoot08(tester, frame);
          case '09':
            await shoot09(tester, frame);
          case '10':
            await shoot10(tester, frame);
        }
        await _shoot(tester, name);
        _recordException(tester, name);
        final finger = held;
        held = null;
        if (finger != null) {
          await finger.up();
          await tester.pump();
          _recordException(tester, name);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 20));
        final prompt = openPrompt;
        openPrompt = null;
        if (prompt != null && !prompt.isCompleted) {
          // The screen is gone, so the answer lands on nothing; it only
          // cancels the request's pending timeout.
          prompt.complete(
            const MicrophoneAccess.denied(
              outcome: MicrophoneOutcome.dismissed,
              message: 'The capture harness closed the prompt.',
            ),
          );
          await tester.pump(const Duration(milliseconds: 20));
          _recordException(tester, name);
        }
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
