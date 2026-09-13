// Developer-only visual QA harness for board 07 — the expanded Voice
// Moment with its "Rozmowa" thread.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/moments_07_capture.dart
//
// PNGs land in test/.screenshots/ (git-ignored) as
// `moments-07-{width}[-x2|-rtl|-pearl]-{state}.png`, the naming the build
// brief asks for.
//
// WIDTH IS THE SLOT the screen receives, not the window. The expanded
// Moment is a PUSHED route: on desktop the Home shell hosts it beside the
// 264-px rail, so a 1440 window gives it a 1176 slot (wide-2: player +
// thread) and a 1464 window gives it 1200 (wide-3: the hand-off list
// appears). Both are captured.
//
// Why this exists: the widget tests prove keys, geometry and behaviour;
// they never prove any of it renders. These frames are what a reviewer
// looks at. Every fixture is controlled, reference-like data — nothing
// here is a real account or a real recording, and the 40 % position is
// driven through the same player seam production uses.

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
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_queue_list.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

import 'voice_moment_test_doubles.dart';

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
  int likes = 24,
  int comments = 6,
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

final _subject = _moment(
  'm1',
  author: 'maja',
  authorName: 'Maja',
  caption: 'Zanim obudzi się miasto',
  seconds: 45,
  likes: 24,
  comments: 6,
);

/// The neighbours the feed had already loaded when this Moment was opened.
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

/// The read seam only: no Firestore, no network, no callable.
class _CaptureMoments extends MomentService {
  _CaptureMoments({this.comments = const <MomentComment>[], this.subject})
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
        storage: MockFirebaseStorage(),
        mediaAccessInvoker: fakeMomentMediaAccessInvoker(),
      );

  final List<MomentComment> comments;

  /// The Moment this cell opened. The canonical view is what decides the
  /// gone state (`moment_detail_screen.dart` recomputes the expiry from the
  /// view it loads), so a cell that opens an EXPIRED Moment must get that
  /// Moment back — returning the live neighbour of the same id silently
  /// resurrects it and the "gone" frame then shows a working player.
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

/// A player that plays nothing and reports exactly the position it is told.
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

enum _Cell { listening, idle, gone, emptyThread }

void main() {
  late PublicIdentityRepository originalIdentity;

  setUpAll(_loadFonts);

  setUp(() {
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

  Future<void> cell(
    WidgetTester tester, {
    required double width,
    required double height,
    _Cell state = _Cell.listening,
    bool pearl = false,
    bool rtl = false,
    double textScale = 1,
  }) async {
    final size = Size(width, height);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final players = <_CapturePlayer>[];
    final queue = MomentNeighbourQueue()
      ..publish(viewerUid: 'me', moments: _neighbours);
    addTearDown(queue.dispose);

    final opened = state == _Cell.gone
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
          moment: opened,
          momentService: _CaptureMoments(
            subject: opened,
            comments: state == _Cell.emptyThread
                ? const <MomentComment>[]
                : _thread,
          ),
          auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
          neighbourQueue: queue,
          playerFactory: () {
            final player = _CapturePlayer();
            players.add(player);
            return player;
          },
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

    if (state == _Cell.listening) {
      // The 40 % of the board, driven through the real transport: tap the
      // one dominant control, then report a position.
      //
      // On a landscape phone (844 x 390) the page legitimately scrolls —
      // the contract's short-height rule only promises the side-by-side
      // HERO, not that a 390-px-tall viewport holds the whole card — so the
      // disc is brought into view before it is tapped instead of the tap
      // being aimed off-screen.
      final disc = find.byKey(const ValueKey('moment-detail-play'));
      await tester.ensureVisible(disc);
      await tester.pump();
      await tester.tap(disc);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      players.last.emit(const Duration(seconds: 18));
      await tester.pump();

      // …and then back to the top, so every frame shows the hero the
      // reviewer is here to look at rather than wherever the tap left the
      // scroll offset. A no-op at every width where nothing scrolled.
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('moment-detail-scroll')),
        matching: find.byType(Scrollable),
      );
      if (scrollable.evaluate().isNotEmpty) {
        tester.state<ScrollableState>(scrollable.first).position.jumpTo(0);
        await tester.pump();
      }
    }

    final suffix = [
      if (textScale >= 2) 'x2',
      if (rtl) 'rtl',
      if (pearl) 'pearl',
    ].map((tag) => '-$tag').join();
    final stateName = switch (state) {
      _Cell.listening => 'listening',
      _Cell.idle => 'idle',
      _Cell.gone => 'gone',
      _Cell.emptyThread => 'empty-thread',
    };
    await _shoot(tester, 'moments-07-${width.toInt()}$suffix-$stateName');
    expect(tester.takeException(), isNull, reason: 'no overflow at $width');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('07 listening at the six widths (+ the wide-3 threshold)', (
    tester,
  ) async {
    await cell(tester, width: 320, height: 720);
    await cell(tester, width: 390, height: 844);
    await cell(tester, width: 768, height: 1024);
    await cell(tester, width: 1100, height: 800);
    // The slots a 1440 and a 1464 WINDOW give with the 264-px rail.
    await cell(tester, width: 1176, height: 900);
    await cell(tester, width: 1200, height: 900);
    await cell(tester, width: 1440, height: 900);
    await cell(tester, width: 1920, height: 1000);
  });

  testWidgets('07 at 200 % text, RTL and Pearl', (tester) async {
    await cell(tester, width: 390, height: 1600, textScale: 2);
    await cell(tester, width: 1440, height: 1100, textScale: 2);
    await cell(tester, width: 390, height: 844, rtl: true);
    await cell(tester, width: 1920, height: 1000, rtl: true);
    await cell(tester, width: 390, height: 844, pearl: true);
    await cell(tester, width: 1920, height: 1000, pearl: true);
  });

  testWidgets('07 states: not started, gone, empty thread', (tester) async {
    await cell(tester, width: 390, height: 844, state: _Cell.idle);
    await cell(tester, width: 1920, height: 1000, state: _Cell.idle);
    await cell(tester, width: 390, height: 844, state: _Cell.gone);
    await cell(tester, width: 1920, height: 1000, state: _Cell.gone);
    await cell(tester, width: 390, height: 844, state: _Cell.emptyThread);
    await cell(tester, width: 1920, height: 1000, state: _Cell.emptyThread);
  });

  // A landscape phone: the hero takes its side-by-side form so the
  // transport stays above the fold.
  testWidgets('07 landscape phone', (tester) async {
    await cell(tester, width: 844, height: 390);
  });
}
