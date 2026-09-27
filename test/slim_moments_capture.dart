// Slim redesign phase 4 (YO Moments) frame harness, extended for the
// refine-look batch 5 (the voice bead and Głos, signature moment W3).
//
// Adapted from `test/moments_visual_review_capture_test.dart` (same fixtures,
// same production seams): the Moments screen with Głos selected, with Yeels
// selected, and the Moment detail view — at 390, 768 and 1440, Dark and
// Pearl, locale pl, 100 % and 200 % text, plus high-contrast frames — in the
// states the refine spec's §11 matrix names for Głos / detail: populated,
// one card playing (exactly one lit card), paused, busy (the grant is
// resolving), failed, uncaptioned with < 1 h left, loading, empty and error;
// the detail playing, paused, busy, failed and gone. Also keyboard focus
// (card, bead, chip, capsule, the chosen Yeels chip), pointer hover (card,
// refresh), two frames with motion ON (the lit fade 90 ms in, the pour
// mid-way — every other frame is the Reduce Motion path), and three
// component boards: `MomentCard` (the 44 px bead), `VoiceCore` on the
// LiveNowHero empty state, and the shared voice row (the thread row in
// every state plus the chat bubble's opt-in bead and pour for B7).
//
// Shadows: flutter_test paints every BoxShadow as a hard, unblurred slab by
// default (`debugDisableShadows`, meant for golden stability). Each case
// switches that off while it renders and restores it before it ends, so the
// lit bead's glow, the CTA lift and Pearl's block shadows are drawn as on a
// device.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/slim_moments_capture.dart --concurrency=1 \
//     --dart-define=YO_CAPTURE_DIR=<evidence>/slim-p4-frames/after
//
// `YO_CAPTURE_DIR` defaults to `test/.screenshots/slim-p4`. Add
// `--dart-define=YO_CAPTURE_MATRIX=slim` for the original 12-frame Slim set
// only. Frames are named
// `<screen>_<width>_<dark|pearl>_pl_<100|200>_<state>[-hc].png`
// (`moments-voice`, `moments-yeels`, `moment-detail`).
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
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/home/presentation/widgets/live_now_hero.dart';
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
import 'package:yovoice/shared/widgets/voice/voice_core.dart';
import 'package:yovoice/shared/widgets/voice/voice_player_row.dart';

import 'voice_moment_test_doubles.dart';

const _outDir = String.fromEnvironment(
  'YO_CAPTURE_DIR',
  defaultValue: 'test/.screenshots/slim-p4',
);

/// `full` (default): the refine-look B5 matrix. `slim`: the original Slim
/// set (390 / 1440, Dark / Pearl, 100 %, populated).
const _matrixName = String.fromEnvironment(
  'YO_CAPTURE_MATRIX',
  defaultValue: 'full',
);

/// The capture host's colour-emoji face, when it has one (macOS; a Linux
/// host maps its Noto Color Emoji to the same path).
const _emojiFont = '/System/Library/Fonts/Apple Color Emoji.ttc';

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
  // The test renderer has no system fallback for emoji, which a phone
  // always has: register the host's colour-emoji face under the generic
  // family that closes the app's own fallback list, so a caption with an
  // emoji is drawn rather than a tofu box. The app's styles are untouched.
  final emoji = File(_emojiFont);
  if (emoji.existsSync()) {
    final bytes = ByteData.sublistView(emoji.readAsBytesSync());
    for (final family in const ['Apple Color Emoji', 'sans-serif']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  }
}

Widget _host(
  Widget child, {
  required bool pearl,
  required double textScale,
  required Size size,
  bool highContrast = false,
  bool animations = false,
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
        disableAnimations: !animations,
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
  Duration lifetime = const Duration(hours: 24),
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
    expiresAt: createdAt.add(expired ? const Duration(minutes: 1) : lifetime),
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

/// Two Moments in the last hour of their 24 h window, the newest one
/// without a caption: the uncaptioned fallback and the amber (< 1 h) pill.
final _urgentFeed = <VoiceMoment>[
  _moment(
    'u1',
    author: 'zuzia',
    authorName: 'Zuzia',
    caption: '',
    seconds: 14,
    likes: 2,
    age: const Duration(hours: 23, minutes: 18),
  ),
  _moment(
    'u2',
    author: 'ola',
    authorName: 'Ola',
    caption: 'Ostatnie słowo przed północą — zostało mu kilka minut.',
    seconds: 31,
    likes: 5,
    comments: 1,
    age: const Duration(hours: 23, minutes: 36),
  ),
];

/// A first page that never arrives: the loading skeleton.
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
        // The calm panel lists only friends whose creator audience is
        // public (a server-written flag); the fixture sets it so the wide
        // frames show the panel's blocks.
        creatorAudienceVisible: true,
      ),
  ]);
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

/// How a capture player answers `play()`: normally, never (the grant /
/// transport is still resolving — the busy bead), or with an error (the
/// failed state).
enum _PlayMode { normal, hang, fail }

class _CapturePlayer implements audio.AudioPlayer {
  _CapturePlayer({
    this.duration = const Duration(seconds: 45),
    this.playMode = _PlayMode.normal,
  });

  final Duration duration;
  final _PlayMode playMode;
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
    switch (playMode) {
      case _PlayMode.hang:
        await Completer<void>().future;
      case _PlayMode.fail:
        throw StateError('capture: playback refused');
      case _PlayMode.normal:
        _durations.add(duration);
    }
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

enum _State {
  populated,
  playing,
  paused,
  busy,
  failed,
  urgent,
  loading,
  empty,
  error,
  thread,
  focusCard,
  focusBead,
  focusChip,
  focusCapsule,
  hoverCard,
  hoverRefresh,
  motionLit,
  motionPour,
  rest,
  states,
}

typedef _Frame = ({
  String board,
  double width,
  double height,
  _State state,
  bool pearl,
  double textScale,
  bool highContrast,
});

/// `<screen>_<width>_<dark|pearl>_pl_<text>_<state>[-hc]`, the refine-look
/// frame naming.
String _frameName(_Frame frame) {
  final screen = switch (frame.board) {
    '06' => 'moments-voice',
    '07' => 'moment-detail',
    '09' => 'moment-card',
    '10' => 'voice-core',
    '11' => 'voice-row',
    _ => 'moments-yeels',
  };
  final theme = frame.pearl ? 'pearl' : 'dark';
  final scale = frame.textScale >= 2 ? '200' : '100';
  final state = switch (frame.state) {
    _State.populated => 'populated',
    _State.playing => 'playing',
    _State.paused => 'paused',
    _State.busy => 'busy',
    _State.failed => 'failed',
    _State.urgent => 'uncaptioned-under1h',
    _State.loading => 'loading',
    _State.empty => 'empty',
    _State.error => frame.board == '07' ? 'gone' : 'error',
    _State.thread => 'thread',
    _State.focusCard => 'focus-card',
    _State.focusBead => 'focus-bead',
    _State.focusChip => 'focus-chip',
    _State.focusCapsule => 'focus-capsule',
    _State.hoverCard => 'hover-card',
    _State.hoverRefresh => 'hover-refresh',
    _State.motionLit => 'motion-lit-90ms',
    _State.motionPour => 'motion-pour-100ms',
    _State.rest => 'rest',
    _State.states => 'states',
  };
  final hc = frame.highContrast ? '-hc' : '';
  return '${screen}_${frame.width.toInt()}_${theme}_pl_${scale}_$state$hc';
}

/// Motion ON only where the frame is evidence of motion itself.
bool _animates(_Frame frame) =>
    frame.state == _State.motionLit || frame.state == _State.motionPour;

const _phone = (390.0, 844.0);
const _tablet = (768.0, 1024.0);
const _desktop = (1440.0, 900.0);

_Frame _f(
  String board,
  (double, double) size,
  _State state, {
  bool pearl = false,
  double textScale = 1,
  bool highContrast = false,
}) => (
  board: board,
  width: size.$1,
  height: size.$2,
  state: state,
  pearl: pearl,
  textScale: textScale,
  highContrast: highContrast,
);

/// The original Slim set: 390 / 1440, Dark / Pearl, 100 %, populated.
List<_Frame> _slimMatrix(String board) => <_Frame>[
  for (final pearl in const <bool>[false, true])
    for (final size in const [_phone, _desktop])
      _f(board, size, _State.populated, pearl: pearl),
];

/// The refine-look B5 matrix (spec §11, Głos / detail row).
List<_Frame> _fullMatrix() => <_Frame>[
  // Głos feed: every width, both themes, both text sizes, populated.
  for (final pearl in const <bool>[false, true])
    for (final size in const [_phone, _tablet, _desktop])
      for (final scale in const <double>[1, 2])
        _f('06', size, _State.populated, pearl: pearl, textScale: scale),
  // One card playing — exactly one lit card — in every width and theme.
  for (final pearl in const <bool>[false, true])
    for (final size in const [_phone, _tablet, _desktop])
      _f('06', size, _State.playing, pearl: pearl),
  _f('06', _phone, _State.playing, textScale: 2),
  _f('06', _phone, _State.playing, pearl: true, textScale: 2),
  for (final pearl in const <bool>[false, true]) ...[
    _f('06', _phone, _State.paused, pearl: pearl),
    _f('06', _phone, _State.failed, pearl: pearl),
    _f('06', _phone, _State.urgent, pearl: pearl),
    _f('06', _phone, _State.loading, pearl: pearl),
    _f('06', _phone, _State.empty, pearl: pearl),
    _f('06', _phone, _State.error, pearl: pearl),
  ],
  _f('06', _phone, _State.busy),
  _f('06', _desktop, _State.paused),
  _f('06', _desktop, _State.urgent, pearl: true),
  _f('06', _desktop, _State.loading),
  _f('06', _desktop, _State.empty),
  _f('06', _desktop, _State.error, pearl: true),
  _f('06', _tablet, _State.loading),
  _f('06', _tablet, _State.empty),
  _f('06', _tablet, _State.error),
  _f('06', _phone, _State.urgent, textScale: 2),
  // High contrast: flat surfaces, borderStrong, no glow or tint.
  _f('06', _phone, _State.playing, highContrast: true),
  _f('06', _phone, _State.playing, pearl: true, highContrast: true),
  _f('06', _desktop, _State.playing, pearl: true, highContrast: true),
  // Keyboard focus and pointer hover.
  for (final pearl in const <bool>[false, true]) ...[
    _f('06', _phone, _State.focusCard, pearl: pearl),
    _f('06', _phone, _State.focusChip, pearl: pearl),
    _f('06', _desktop, _State.hoverCard, pearl: pearl),
  ],
  _f('06', _phone, _State.focusBead),
  _f('06', _phone, _State.focusCapsule),
  _f('06', _tablet, _State.hoverRefresh),
  // Motion ON: the light 90 ms into its 180 ms fade; the pour mid-way.
  _f('06', _phone, _State.motionLit),
  _f('06', _phone, _State.motionPour),
  // Detail: playing (lit) and paused.
  for (final pearl in const <bool>[false, true])
    for (final size in const [_phone, _tablet, _desktop])
      _f('07', size, _State.playing, pearl: pearl),
  for (final pearl in const <bool>[false, true]) ...[
    _f('07', _phone, _State.playing, pearl: pearl, textScale: 2),
    _f('07', _phone, _State.paused, pearl: pearl),
  ],
  _f('07', _tablet, _State.playing, textScale: 2),
  _f('07', _desktop, _State.playing, textScale: 2),
  _f('07', _desktop, _State.paused),
  _f('07', _phone, _State.busy),
  _f('07', _phone, _State.failed),
  _f('07', _phone, _State.error),
  _f('07', _phone, _State.playing, highContrast: true),
  // Yeels: the over-media chips and switch (immersive, theme-invariant).
  for (final size in const [_phone, _tablet, _desktop])
    _f('08', size, _State.populated),
  _f('08', _phone, _State.populated, pearl: true),
  _f('08', _phone, _State.populated, textScale: 2),
  _f('08', _phone, _State.focusChip),
  // MomentCard (the 44 px bead), at rest and playing.
  for (final pearl in const <bool>[false, true]) ...[
    _f('09', _phone, _State.rest, pearl: pearl),
    _f('09', _phone, _State.playing, pearl: pearl),
  ],
  _f('09', _phone, _State.playing, textScale: 2),
  // VoiceCore (LiveNowHero's empty state).
  for (final pearl in const <bool>[false, true])
    _f('10', _phone, _State.rest, pearl: pearl),
  // The shared voice row: the thread row in every state and the chat
  // bubble's opt-in bead and pour.
  for (final pearl in const <bool>[false, true])
    for (final scale in const <double>[1, 2])
      _f('11', _phone, _State.states, pearl: pearl, textScale: scale),
];

void main() {
  late PublicIdentityRepository originalIdentity;
  final feedPlayers = <_CapturePlayer>[];

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
    // Asset decodes (the studio scenery) complete on the real event loop:
    // give them real turns so the frame is not shot before the page
    // background has painted.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Keyboard focus on the node that owns [finder]'s element: the nearest
  /// enclosing `Focus` (an ink well's or a button's). The target is taken
  /// where it lies (no scroll, as `requestFocus` does not scroll either).
  /// Focus changes land in a microtask, the ring on the next frame.
  Future<void> focusOn(WidgetTester tester, Finder finder) async {
    Focus.of(tester.element(finder.first)).requestFocus();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// A mouse over [finder]'s centre, removed when the case ends.
  Future<void> hoverOn(WidgetTester tester, Finder finder) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(finder.first));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Plays the second card of the feed (`m5`), moves it to a real position
  /// and — for [pause] — pauses it there. The list is scrolled so the card
  /// above it stays partly in view: one lit card among resting ones.
  /// [emit] false leaves the transport where `play()` left it (busy or
  /// failed).
  /// Scrolls the second card (`m5`) into view with the card above it still
  /// partly visible; returns its play bead, or null when it is absent.
  Future<Finder?> revealSecondCard(WidgetTester tester) async {
    final play = find.byKey(const ValueKey('moment-row-play-m5'));
    if (play.evaluate().isEmpty) return null;
    await tester.ensureVisible(play);
    await tester.pump();
    final scroll = find.descendant(
      of: find.byKey(const ValueKey('moments-feed-scroll')),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    );
    if (scroll.evaluate().isNotEmpty) {
      final position = tester.state<ScrollableState>(scroll.first).position;
      position.jumpTo(
        (position.pixels - 260).clamp(0.0, position.maxScrollExtent),
      );
      await tester.pump();
    }
    return play;
  }

  Future<void> playSecondCard(
    WidgetTester tester, {
    bool pause = false,
    bool emit = true,
  }) async {
    final play = await revealSecondCard(tester);
    if (play == null) return;
    await tester.tap(play, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    if (emit && feedPlayers.isNotEmpty) {
      feedPlayers.last.emit(const Duration(seconds: 16));
    }
    await tester.pump();
    await tester.pump();
    if (pause) {
      await tester.tap(play, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
  }

  Future<void> shoot06(WidgetTester tester, _Frame frame) async {
    final size = Size(frame.width, frame.height);
    sizeView(tester, size);
    final auth = _authMe();
    final firestore = FakeFirebaseFirestore();
    final MomentDiscoveryService discovery = switch (frame.state) {
      _State.error => _ThrowingDiscovery(),
      _State.empty => _StaticDiscovery(const <VoiceMoment>[]),
      _State.loading => _PendingDiscovery(),
      _State.urgent => _StaticDiscovery(_urgentFeed),
      _ => _StaticDiscovery(_feed),
    };
    final mode = switch (frame.state) {
      _State.busy => _PlayMode.hang,
      _State.failed => _PlayMode.fail,
      _ => _PlayMode.normal,
    };
    feedPlayers.clear();

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
          momentService: _CaptureMoments(),
          playerFactory: () {
            final player = _CapturePlayer(
              duration: const Duration(seconds: 39),
              playMode: mode,
            );
            feedPlayers.add(player);
            return player;
          },
        ),
        pearl: frame.pearl,
        textScale: frame.textScale,
        size: size,
        highContrast: frame.highContrast,
        animations: _animates(frame),
      ),
    );
    await settle(tester);
    switch (frame.state) {
      case _State.playing || _State.paused:
        await playSecondCard(tester, pause: frame.state == _State.paused);
      case _State.busy || _State.failed:
        await playSecondCard(tester, emit: false);
        // The indeterminate spinner is a real Material animation (Reduce
        // Motion does not stop it): shoot it with a readable arc.
        await tester.pump(const Duration(milliseconds: 450));
      case _State.focusCard:
        // The first card's own ink well (the card body, not a control in
        // it): the lit block paints the 2 px focus ring for it.
        await focusOn(
          tester,
          find.descendant(
            of: find.byWidgetPredicate(
              (w) =>
                  w is InkWell &&
                  w.excludeFromSemantics &&
                  w.borderRadius == const BorderRadius.all(Radius.circular(20)),
            ),
            matching: find.byType(Padding),
          ),
        );
      case _State.focusBead:
        await focusOn(
          tester,
          find.descendant(
            of: find.byKey(const ValueKey('moment-row-play-m4')),
            matching: find.byType(Icon),
          ),
        );
      case _State.focusChip:
        // The chosen chip: the ring on the inverted fill is the hard case.
        await focusOn(
          tester,
          find.descendant(
            of: find.byKey(const ValueKey('moments-filter-discover')),
            matching: find.byType(Text),
          ),
        );
      case _State.focusCapsule:
        await focusOn(
          tester,
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == 'MomentAuthorCapsule',
            ),
            matching: find.byType(Row),
          ),
        );
      case _State.hoverCard:
        // A pointer on the card's own surface (the header row between the
        // author and the badge), not on a control inside it.
        final card = tester.getRect(
          find.byKey(const ValueKey('moment-row-m4')),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(Offset(card.center.dx, card.top + 40));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      case _State.hoverRefresh:
        await hoverOn(
          tester,
          find.byKey(const ValueKey('moments-discovery-refresh-ring')),
        );
      case _State.motionLit:
        final play = await revealSecondCard(tester);
        if (play == null) break;
        await tester.tap(play, warnIfMissed: false);
        // The grant and play() resolve in microtasks; the light starts on
        // the frame after that and is shot 90 ms into its 180 ms fade.
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
      case _State.motionPour:
        await playSecondCard(tester);
        await tester.pump(const Duration(milliseconds: 400));
        if (feedPlayers.isNotEmpty) {
          feedPlayers.last.emit(const Duration(seconds: 26));
        }
        // The event lands in a microtask; the tween starts on the next
        // frame and is shot half-way through its 200 ms.
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      default:
        break;
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
    final mode = switch (frame.state) {
      _State.busy => _PlayMode.hang,
      _State.failed => _PlayMode.fail,
      _ => _PlayMode.normal,
    };

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
            final player = _CapturePlayer(playMode: mode);
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

    if (frame.state == _State.populated ||
        frame.state == _State.playing ||
        frame.state == _State.paused ||
        frame.state == _State.busy ||
        frame.state == _State.failed) {
      final disc = find.byKey(const ValueKey('moment-detail-play'));
      if (disc.evaluate().isNotEmpty) {
        await tester.ensureVisible(disc);
        await tester.pump();
        await tester.tap(disc, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        if (players.isNotEmpty && mode == _PlayMode.normal) {
          players.last.emit(const Duration(seconds: 18));
        }
        await tester.pump();
        await tester.pump();
        if (frame.state == _State.paused) {
          await tester.tap(disc, warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
        }
      }
      // The busy spinner is shot with a readable arc.
      if (frame.state == _State.busy) {
        await tester.pump(const Duration(milliseconds: 450));
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
          reelVideoBuilder: _footage,
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
    if (frame.state == _State.focusChip) {
      // The chosen, white "Odkrywaj" chip: its ring must not vanish into
      // its own fill.
      await focusOn(tester, find.text('Odkrywaj'));
    }
  }

  /// Board 09: two `MomentCard`s (the 44 px bead) on the page canvas, the
  /// first one playing for [_State.playing].
  Future<void> shoot09(WidgetTester tester, _Frame frame) async {
    final size = Size(frame.width, frame.height);
    sizeView(tester, size);
    final players = <_CapturePlayer>[];
    Widget card(VoiceMoment moment) => MomentCard(
      moment: moment,
      onComments: () {},
      mediaUriResolver: (id) async => Uri.parse('https://cdn.example/$id.m4a'),
      playerFactory: () {
        final player = _CapturePlayer(duration: const Duration(seconds: 45));
        players.add(player);
        return player;
      },
    );
    await tester.pumpWidget(
      _host(
        Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                card(_feed[0]),
                const SizedBox(height: 16),
                card(_feed[3]),
              ],
            ),
          ),
        ),
        pearl: frame.pearl,
        textScale: frame.textScale,
        size: size,
      ),
    );
    await settle(tester);
    if (frame.state == _State.playing) {
      await tester.tap(find.byIcon(Icons.play_arrow_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
    }
  }

  /// Board 10: `VoiceCore` in the LiveNowHero empty state (its tokens
  /// replaced three hand-picked violets) and alone at 96.
  Future<void> shoot10(WidgetTester tester, _Frame frame) async {
    final size = Size(frame.width, frame.height);
    sizeView(tester, size);
    await tester.pumpWidget(
      _host(
        Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              children: [
                LiveNowHero(room: null, onJoin: (_) {}),
                const SizedBox(height: 32),
                const Center(child: VoiceCore(size: 96)),
              ],
            ),
          ),
        ),
        pearl: frame.pearl,
        textScale: frame.textScale,
        size: size,
      ),
    );
    await settle(tester);
  }

  /// Board 11: the shared voice row. The thread row (`contained`) at rest,
  /// playing at 40 %, loading, failed and disabled; then the chat bubble's
  /// opt-in finish for B7 (`VoicePlayerRowStyle.bubble`) — incoming at rest
  /// and playing, outgoing at rest and playing — and the legacy outgoing
  /// row every bubble draws until it opts in.
  Future<void> shoot11(WidgetTester tester, _Frame frame) async {
    final size = Size(frame.width, frame.height);
    sizeView(tester, size);
    final position = ValueNotifier<double?>(.4);
    addTearDown(position.dispose);
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) {
            final palette = context.appPalette;
            final colors = Theme.of(context).colorScheme;
            Widget row(
              VoicePlayerRowStatus status, {
              bool progress = false,
              bool enabled = true,
            }) => VoicePlayerRow(
              status: status,
              durationSeconds: 27,
              semanticsLabel: 'clip',
              onTap: enabled ? () {} : null,
              progress: progress ? position : null,
              style: VoicePlayerRowStyle.contained(palette, colors),
            );
            Widget bubble({required bool outgoing, required bool playing}) =>
                Align(
                  alignment: outgoing
                      ? AlignmentDirectional.centerEnd
                      : AlignmentDirectional.centerStart,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                    decoration: BoxDecoration(
                      gradient: outgoing
                          ? AppGradients.primaryAction(colors)
                          : palette.blockGradient,
                      border: outgoing
                          ? null
                          : Border.all(color: palette.hairline),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: VoicePlayerRow(
                      status: playing
                          ? VoicePlayerRowStatus.playing
                          : VoicePlayerRowStatus.idle,
                      durationSeconds: 14,
                      semanticsLabel: 'voice message',
                      onTap: () {},
                      progress: playing ? position : null,
                      style: VoicePlayerRowStyle.bubble(
                        outgoing: outgoing,
                        palette: palette,
                        colors: colors,
                        foreground: outgoing
                            ? AppColors.white
                            : palette.textPrimary,
                        mutedForeground: outgoing
                            ? AppFinish.outgoingMeta
                            : palette.textSecondary,
                        errorForeground: outgoing
                            ? AppColors.white
                            : palette.dangerForeground,
                      ),
                    ),
                  ),
                );
            final legacy = Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                decoration: BoxDecoration(
                  gradient: AppGradients.primaryAction(colors),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: VoicePlayerRow(
                  status: VoicePlayerRowStatus.idle,
                  durationSeconds: 14,
                  semanticsLabel: 'voice message',
                  onTap: () {},
                  style: VoicePlayerRowStyle.inline(
                    foreground: AppColors.white,
                    mutedForeground: AppFinish.outgoingMeta,
                    errorForeground: AppColors.white,
                  ),
                ),
              ),
            );
            return Scaffold(
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final child in <Widget>[
                      row(VoicePlayerRowStatus.idle),
                      row(VoicePlayerRowStatus.playing, progress: true),
                      row(VoicePlayerRowStatus.loading),
                      row(VoicePlayerRowStatus.failed),
                      row(VoicePlayerRowStatus.idle, enabled: false),
                      bubble(outgoing: false, playing: false),
                      bubble(outgoing: false, playing: true),
                      bubble(outgoing: true, playing: false),
                      bubble(outgoing: true, playing: true),
                      legacy,
                    ]) ...[child, const SizedBox(height: 12)],
                  ],
                ),
              ),
            );
          },
        ),
        pearl: frame.pearl,
        textScale: frame.textScale,
        size: size,
      ),
    );
    await settle(tester);
    // The loading row's spinner, with a readable arc.
    await tester.pump(const Duration(milliseconds: 450));
  }

  final frames = _matrixName == 'slim'
      ? <_Frame>[
          ..._slimMatrix('06'),
          ..._slimMatrix('07'),
          ..._slimMatrix('08'),
        ]
      : _fullMatrix();
  for (final frame in frames) {
    final name = _frameName(frame);
    testWidgets(name, (tester) async {
      final strategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
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
          case '11':
            await shoot11(tester, frame);
        }
        await _shoot(tester, name);
        _recordException(tester, name);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 20));
      } finally {
        debugDisableShadows = true;
        FocusManager.instance.highlightStrategy = strategy;
      }
    });
  }
}
