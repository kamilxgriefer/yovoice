// Composer preview and feed player agree on every clip shape (ADR-235):
// the same fit, and the same picture as a fraction of the frame.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
// The installed video_player plugin owns this locked test-only platform seam.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_upload.dart';
import 'package:yovoice/features/reels/presentation/reel_media_fit.dart';
import 'package:yovoice/features/reels/presentation/reel_video_backdrop_policy.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_composition_canvas.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_draft_preview.dart';

import 'reel_fit_test_support.dart';
import 'reel_stage_test_support.dart';

const _sizes = <Size>[
  Size(1080, 1920),
  Size(1080, 2400),
  Size(1080, 2640),
  Size(1080, 1440),
  Size(720, 960),
  Size(1080, 1350),
  Size(1080, 1080),
  Size(1920, 1080),
  Size(2424, 1080),
];

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme,
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

Future<void> _settle(WidgetTester tester) async {
  for (var index = 0; index < 10; index += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _foreground() {
  final contained = find.descendant(
    of: find.byKey(const ValueKey<String>('reel-fitted-video-foreground')),
    matching: find.byType(VideoPlayer),
  );
  return contained.evaluate().isEmpty ? find.byType(VideoPlayer) : contained;
}

/// The foreground video's rect as a fraction of the composition canvas.
Rect _fraction(WidgetTester tester) {
  final frame = tester.getRect(find.byType(ReelCompositionCanvas));
  final video = tester.getRect(_foreground());
  return Rect.fromLTRB(
    (video.left - frame.left) / frame.width,
    (video.top - frame.top) / frame.height,
    (video.right - frame.left) / frame.width,
    (video.bottom - frame.top) / frame.height,
  );
}

ReelMediaFit _mode(WidgetTester tester) =>
    find
        .byKey(const ValueKey<String>('reel-fitted-video-base'))
        .evaluate()
        .isEmpty
    ? ReelMediaFit.cover
    : ReelMediaFit.contain;

Future<(ReelMediaFit, Rect)> _composer(WidgetTester tester, Size media) async {
  await tester.pumpWidget(
    _app(
      Center(
        child: SizedBox(
          width: 350 * 9 / 16,
          height: 350,
          child: ReelDraftPreview(
            media: ReelUploadPayload(
              bytes: Uint8List(256),
              contentType: 'video/mp4',
              durationMs: 18000,
              sourcePath: '/tmp/clip.mp4',
            ),
            composition: const ReelComposition(
              trimEndMs: 18000,
              originalAudioVolume: 100,
            ),
            videoControllerFactory: (_) => FakeSizedVideoController(media),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  final result = (_mode(tester), _fraction(tester));
  await tester.pumpWidget(const SizedBox());
  return result;
}

Future<(ReelMediaFit, Rect)> _feed(
  WidgetTester tester,
  SizedVideoPlatform platform,
  Size media, {
  required Size window,
  required bool fillViewport,
}) async {
  platform.size = media;
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  final reel = Reel.fromV2Wire(reelWire(1));
  await tester.pumpWidget(
    _app(
      ReelCard(
        key: ValueKey<String>('${reel.id}-$media-$fillViewport'),
        reel: reel,
        service: reelStageService(),
        fillViewport: fillViewport,
        autoplay: false,
        videoControllerFactory: VideoPlayerController.networkUrl,
      ),
    ),
  );
  await _settle(tester);
  final result = (_mode(tester), _fraction(tester));
  await tester.pumpWidget(const SizedBox());
  await _settle(tester);
  return result;
}

void main() {
  late VideoPlayerPlatform original;
  late SizedVideoPlatform platform;

  setUp(() {
    ReelVideoBackdropPolicy.debugOverride = ReelVideoBackdrop.blurred;
    original = VideoPlayerPlatform.instance;
    platform = SizedVideoPlatform(const Size(720, 1280));
    VideoPlayerPlatform.instance = platform;
  });

  tearDown(() {
    ReelVideoBackdropPolicy.debugOverride = null;
    VideoPlayerPlatform.instance = original;
  });

  for (final media in _sizes) {
    testWidgets('composer and feed agree for $media', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      final composer = await _composer(tester, media);
      expect(composer.$1, reelVideoFit(media));

      // The ≥ 600 stage: the same 9:16 recipe frame as the composer.
      final stage = await _feed(
        tester,
        platform,
        media,
        window: const Size(900, 1200),
        fillViewport: false,
      );
      expect(stage.$1, composer.$1);
      for (final (a, b) in <(double, double)>[
        (stage.$2.left, composer.$2.left),
        (stage.$2.top, composer.$2.top),
        (stage.$2.right, composer.$2.right),
        (stage.$2.bottom, composer.$2.bottom),
      ]) {
        expect(
          a,
          closeTo(b, 1e-3),
          reason: '$media ${stage.$2} ${composer.$2}',
        );
      }

      // A 390×844 phone fills the viewport; the fit mode is still the same.
      final phone = await _feed(
        tester,
        platform,
        media,
        window: const Size(390, 844),
        fillViewport: true,
      );
      expect(phone.$1, composer.$1, reason: '$media on a phone');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the feed contains a 16:9 Yeel over its blurred copy', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    platform.size = const Size(1920, 1080);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final reel = Reel.fromV2Wire(reelWire(1));
    await tester.pumpWidget(
      _app(
        ReelCard(
          reel: reel,
          service: reelStageService(),
          fillViewport: true,
          autoplay: false,
          videoControllerFactory: VideoPlayerController.networkUrl,
        ),
      ),
    );
    await _settle(tester);
    final players = tester.widgetList<VideoPlayer>(find.byType(VideoPlayer));
    expect(players, hasLength(2));
    expect(
      identical(players.first.controller, players.last.controller),
      isTrue,
    );
    expect(find.byType(ImageFiltered), findsOneWidget);
    final frame = tester.widget<ReelCompositionFrame>(
      find.byType(ReelCompositionFrame),
    );
    expect(frame.mediaSize, const Size(1920, 1080));
    final canvas = tester.getRect(find.byType(ReelCompositionCanvas));
    final video = tester.getRect(_foreground());
    expect(video.width, closeTo(canvas.width, 1e-6));
    expect(video.center.dy, closeTo(canvas.center.dy, 1e-6));
    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });

  testWidgets('the feed keeps today\'s tree for a 720x1280 Yeel', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    final reel = Reel.fromV2Wire(reelWire(1));
    await tester.pumpWidget(
      _app(
        ReelCard(
          reel: reel,
          service: reelStageService(),
          fillViewport: true,
          autoplay: false,
          videoControllerFactory: VideoPlayerController.networkUrl,
        ),
      ),
    );
    await _settle(tester);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
    final fitted = tester.widget<FittedBox>(
      find
          .ancestor(
            of: find.byType(VideoPlayer),
            matching: find.byType(FittedBox),
          )
          .first,
    );
    expect(fitted.fit, BoxFit.cover);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });

  testWidgets(
    'the composer and the feed decide blur or black before a video is ready',
    (tester) async {
      // Otherwise the first landscape Yeel after a cold start draws black
      // bands and then swaps to the blur on screen once the probe answers.
      var probes = 0;
      ReelVideoBackdropPolicy.debugOverride = null;
      ReelVideoBackdropPolicy.debugIsWeb = false;
      ReelVideoBackdropPolicy.debugAndroidMemoryProbe = () async {
        probes += 1;
        return (isLowRamDevice: false, physicalRamMb: 8192);
      };
      addTearDown(() {
        ReelVideoBackdropPolicy.debugAndroidMemoryProbe = null;
        ReelVideoBackdropPolicy.debugIsWeb = null;
        ReelVideoBackdropPolicy.instance.debugReset();
      });
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;

      /// Pumps frame by frame until a video is on screen; reports whether
      /// that FIRST frame already carried the blurred backdrop.
      Future<bool> firstVideoFrameIsBlurred() async {
        for (var frame = 0; frame < 40; frame += 1) {
          await tester.pump(const Duration(milliseconds: 16));
          if (find.byType(VideoPlayer).evaluate().isNotEmpty) {
            return find.byType(ImageFiltered).evaluate().isNotEmpty;
          }
        }
        fail('no video frame');
      }

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        // The composer: the probe starts while the decoder is still opening.
        ReelVideoBackdropPolicy.instance.debugReset();
        final opening = Completer<void>();
        await tester.pumpWidget(
          _app(
            SizedBox(
              width: 350 * 9 / 16,
              height: 350,
              child: ReelDraftPreview(
                media: ReelUploadPayload(
                  bytes: Uint8List(256),
                  contentType: 'video/mp4',
                  durationMs: 18000,
                  sourcePath: '/tmp/clip.mp4',
                ),
                composition: const ReelComposition(
                  trimEndMs: 18000,
                  originalAudioVolume: 100,
                ),
                videoControllerFactory: (_) =>
                    _OpeningVideoController(opening.future),
              ),
            ),
          ),
        );
        expect(find.byType(VideoPlayer), findsNothing, reason: 'opening');
        expect(probes, 1);
        opening.complete();
        expect(await firstVideoFrameIsBlurred(), isTrue);
        await tester.pumpWidget(const SizedBox());

        // The feed: the player starts the probe as it is created, so a
        // landscape Yeel's first frame already has its final backdrop.
        ReelVideoBackdropPolicy.instance.debugReset();
        platform.size = const Size(1920, 1080);
        final reel = Reel.fromV2Wire(reelWire(1));
        await tester.pumpWidget(
          _app(
            ReelCard(
              reel: reel,
              service: reelStageService(),
              fillViewport: true,
              autoplay: false,
              videoControllerFactory: VideoPlayerController.networkUrl,
            ),
          ),
        );
        expect(await firstVideoFrameIsBlurred(), isTrue);
        expect(probes, 2);
        await tester.pumpWidget(const SizedBox());
        await _settle(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}

/// A composer decoder still opening: [initialize] waits on [opened].
class _OpeningVideoController extends FakeSizedVideoController {
  _OpeningVideoController(this.opened) : super(const Size(1920, 1080));

  final Future<void> opened;

  @override
  Future<void> initialize() async {
    await opened;
    await super.initialize();
  }
}
