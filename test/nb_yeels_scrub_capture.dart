// Next build, task 1 (Yeels drag-to-seek, ADR-211) frame harness.
//
// The filename deliberately has no `_test` suffix, so the ordinary suite
// skips it. Run explicitly:
//
//   flutter test test/nb_yeels_scrub_capture.dart --concurrency=1 \
//     --dart-define=YO_CAPTURE_DIR=<evidence>/next-build/yeels-scrub
//
// Frames: `<surface>_<width>_<dark|pearl>_<state>.png`.
//   * yeels-phone / yeels-card: the Yeel stage at rest and with a finger held
//     on the timeline (the chrome faded, thicker track, thumb, time label).
//   * story: the Voice full-screen story player, whose stage waveform now
//     takes a finger (it is an immersive dark surface in both themes).
//
// Every fixture is controlled data from the existing test seams: no account,
// no network, no decoder. The Yeel media is a flat light-to-dark panel on
// purpose, because white-on-media chrome has to stay legible on the worst
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
import 'package:yovoice/core/theme/app_immersive_colors.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/moment_chain.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_viewer.dart';
import 'package:yovoice/features/reels/presentation/screens/reels_feed_screen.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';

import 'reel_stage_test_support.dart';
import 'voice_moment_test_doubles.dart';

const _outDir = String.fromEnvironment(
  'YO_CAPTURE_DIR',
  defaultValue: 'test/.screenshots/nb-yeels-scrub',
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
  await loadStageFonts();
}

Widget _host(Widget child, {required bool pearl, required Size size}) =>
    RepaintBoundary(
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
          data: MediaQueryData(size: size),
          child: child!,
        ),
        home: Scaffold(body: child),
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

void _recordException(WidgetTester tester, String name) {
  final error = tester.takeException();
  if (error != null) {
    // ignore: avoid_print
    print('EXCEPTION $name :: $error');
  }
}

/// A flat panel with a light top and a darker bottom, standing in for
/// footage: the hairline and the time label must read on both.
Widget _panel(BuildContext context, Uri _, dynamic _) => const DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Colors.blueGrey, Colors.brown],
    ),
  ),
);

VoiceMoment _moment(String id, String caption, Duration age) {
  final createdAt = DateTime.now().subtract(age);
  return VoiceMoment(
    id: id,
    authorId: 'maja',
    authorName: 'Maja',
    authorPhotoUrl: null,
    caption: caption,
    audioUrl: 'https://cdn.example/$id.m4a',
    durationSeconds: 45,
    likeCount: 24,
    commentCount: 6,
    isPublished: true,
    createdAt: createdAt,
    expiresAt: createdAt.add(const Duration(hours: 24)),
    schemaVersion: 2,
    status: 'published',
    isDeleted: false,
  );
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
    _positions.add(const Duration(seconds: 4));
  }

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

void main() {
  setUpAll(_loadFonts);

  for (final pearl in <bool>[false, true]) {
    final theme = pearl ? 'pearl' : 'dark';
    for (final size in <Size>[const Size(390, 844), const Size(1440, 900)]) {
      final phone = size.width < 600;
      final surface = phone ? 'yeels-phone' : 'yeels-card';
      final name = '${surface}_${size.width.toInt()}_$theme';
      testWidgets(name, (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final players = FakeReelPlayers();
        await tester.pumpWidget(
          _host(
            ReelsFeedScreen(
              embedded: true,
              immersive: phone,
              service: reelStageService(count: 2),
              audioPlaybackFactory: FakeReelAudioPlayback.new,
              videoPlaybackFactory: (uri, reel) => players.of(reel.id),
              videoBuilder: _panel,
            ),
            pearl: pearl,
            size: size,
          ),
        );
        await tester.pumpAndSettle();
        _recordException(tester, name);
        await _shoot(tester, '${name}_rest');

        final card = find.byType(ReelCard).first;
        final band = tester.getRect(
          find
              .descendant(
                of: card,
                matching: find.byKey(
                  const ValueKey<String>('reel-progress-scrub'),
                ),
              )
              .first,
        );
        final gesture = await tester.startGesture(
          Offset(band.left + band.width * .2, band.bottom - 4),
        );
        await gesture.moveTo(
          Offset(band.left + band.width * .62, band.bottom - 4),
        );
        await tester.pumpAndSettle();
        _recordException(tester, name);
        await _shoot(tester, '${name}_scrubbing');
        await gesture.up();
        await tester.pumpAndSettle();
        _recordException(tester, name);
        // Released: the hairline keeps the committed position.
        await _shoot(tester, '${name}_released');
      });
    }

    for (final size in <Size>[const Size(390, 844), const Size(1440, 900)]) {
      final name = 'story_${size.width.toInt()}_$theme';
      testWidgets(name, (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final auth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me'),
        );
        final player = _CapturePlayer();
        final chain = buildMomentChains(<VoiceMoment>[
          _moment('s1', 'Zanim obudzi się miasto', const Duration(hours: 3)),
          _moment('s2', 'Druga część', const Duration(hours: 1)),
        ]).single;
        await tester.pumpWidget(
          _host(
            // As showMomentStoryViewer hosts it: the immersive surface in
            // either app theme.
            ColoredBox(
              color: AppImmersiveColors.background,
              child: MomentStoryViewer(
                chain: chain,
                feedService: HomeFeedService(
                  firestore: FakeFirebaseFirestore(),
                  auth: auth,
                ),
                momentService: MomentService(
                  firestore: FakeFirebaseFirestore(),
                  auth: auth,
                  storage: MockFirebaseStorage(),
                  mediaAccessInvoker: fakeMomentMediaAccessInvoker(),
                ),
                playerFactory: () => player,
                autoPlay: false,
              ),
            ),
            pearl: pearl,
            size: size,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.byKey(const ValueKey('story-play-toggle')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        final scrub = tester.getRect(
          find.byKey(const ValueKey('story-progress-scrub')),
        );
        await tester.dragFrom(
          Offset(scrub.left + 8, scrub.center.dy),
          Offset(scrub.width * .55, 0),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        _recordException(tester, name);
        await _shoot(tester, '${name}_seeked');
      });
    }
  }
}
