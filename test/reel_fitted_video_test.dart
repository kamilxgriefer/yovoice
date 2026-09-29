// ReelFittedVideo: today's cover tree for upright clips, the whole picture
// over a blurred copy of itself otherwise (ADR-235).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:yovoice/features/reels/presentation/reel_video_backdrop_policy.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_fitted_video.dart';

import 'reel_fit_test_support.dart';

/// Lays [child] out at exactly [host], whatever the test window's size.
Widget _host(Size host, Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: OverflowBox(
    alignment: Alignment.topLeft,
    minWidth: 0,
    minHeight: 0,
    maxWidth: double.infinity,
    maxHeight: double.infinity,
    child: SizedBox(
      key: const ValueKey<String>('fit-host'),
      width: host.width,
      height: host.height,
      child: child,
    ),
  ),
);

/// Exactly what both surfaces built before ADR-235.
Widget _today(Size size, Widget video) => FittedBox(
  fit: BoxFit.cover,
  child: SizedBox(width: size.width, height: size.height, child: video),
);

Rect _videoRect(WidgetTester tester, Finder video) {
  final host = tester.getTopLeft(find.byKey(const ValueKey('fit-host')));
  return tester.getRect(video).shift(-host);
}

void main() {
  late FakeSizedVideoController controller;

  setUp(() {
    controller = FakeSizedVideoController(const Size(1920, 1080));
    ReelVideoBackdropPolicy.debugOverride = ReelVideoBackdrop.blurred;
  });

  tearDown(() {
    ReelVideoBackdropPolicy.debugOverride = null;
    ReelVideoBackdropPolicy.debugIsWeb = null;
    ReelVideoBackdropPolicy.debugAndroidMemoryProbe = null;
    ReelVideoBackdropPolicy.instance.debugReset();
  });

  group('portrait control: exactly today', () {
    const hosts = <Size>[
      Size(320, 568),
      Size(360, 800),
      Size(390, 844),
      Size(412, 915),
      Size(280, 653),
      Size(768, 1024),
      Size(1440, 1000),
      Size(390, 390 * 16 / 9), // the composer's 9:16 canvas
    ];
    for (final host in hosts) {
      testWidgets('1080x1920 in $host', (tester) async {
        const size = Size(1080, 1920);
        await tester.pumpWidget(
          _host(
            host,
            ReelFittedVideo(size: size, video: () => VideoPlayer(controller)),
          ),
        );
        expect(find.byType(VideoPlayer), findsOneWidget);
        expect(find.byType(Stack), findsNothing);
        expect(find.byType(ImageFiltered), findsNothing);
        final fitted = tester.widget<FittedBox>(find.byType(FittedBox));
        expect(fitted.fit, BoxFit.cover);
        final sized = tester.widget<SizedBox>(
          find.descendant(
            of: find.byType(FittedBox),
            matching: find.byType(SizedBox),
          ),
        );
        expect(Size(sized.width!, sized.height!), size);
        final rect = _videoRect(tester, find.byType(VideoPlayer));

        await tester.pumpWidget(
          _host(host, _today(size, VideoPlayer(controller))),
        );
        expect(_videoRect(tester, find.byType(VideoPlayer)), rect);
      });
    }
  });

  testWidgets('landscape 1920x1080 is contained over a blurred copy', (
    tester,
  ) async {
    const canvas = Size(390, 390 * 16 / 9);
    await tester.pumpWidget(
      _host(
        canvas,
        ReelFittedVideo(
          size: const Size(1920, 1080),
          video: () => VideoPlayer(controller),
        ),
      ),
    );
    final players = tester.widgetList<VideoPlayer>(find.byType(VideoPlayer));
    expect(players, hasLength(2));
    expect(players.every((p) => identical(p.controller, controller)), isTrue);

    final filtered = tester.widget<ImageFiltered>(find.byType(ImageFiltered));
    expect(
      filtered.imageFilter,
      ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18, tileMode: TileMode.mirror),
    );
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('reel-fitted-video-scrim')),
          )
          .color,
      const Color(0x66000000),
    );
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('reel-fitted-video-base')),
          )
          .color,
      Colors.black,
    );

    final foreground = find.descendant(
      of: find.byKey(const ValueKey('reel-fitted-video-foreground')),
      matching: find.byType(VideoPlayer),
    );
    final rect = _videoRect(tester, foreground);
    expect(rect.width, closeTo(canvas.width, 1e-6));
    expect(rect.height, closeTo(canvas.width * 9 / 16, 1e-6));
    expect(rect.center.dx, closeTo(canvas.width / 2, 1e-6));
    expect(rect.center.dy, closeTo(canvas.height / 2, 1e-6));
  });

  for (final media in const <Size>[Size(64, 36), Size(320, 180)]) {
    testWidgets('a low-resolution $media clip is scaled UP to the frame', (
      tester,
    ) async {
      // A loosely constrained FittedBox would keep a clip smaller than the
      // 390-unit canvas at its own size (found on the web probe).
      const canvas = Size(390, 390 * 16 / 9);
      await tester.pumpWidget(
        _host(
          canvas,
          ReelFittedVideo(size: media, video: () => VideoPlayer(controller)),
        ),
      );
      final rect = _videoRect(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('reel-fitted-video-foreground')),
          matching: find.byType(VideoPlayer),
        ),
      );
      expect(rect.width, closeTo(canvas.width, 1e-6));
      expect(
        rect.height,
        closeTo(canvas.width * media.height / media.width, 1e-6),
      );
      expect(rect.center.dy, closeTo(canvas.height / 2, 1e-6));
    });
  }

  testWidgets('the backdrop is excluded from semantics and hit testing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Size(390, 693),
        ReelFittedVideo(
          size: const Size(1920, 1080),
          video: () => VideoPlayer(controller),
        ),
      ),
    );
    final backdrop = find.byKey(const ValueKey('reel-fitted-video-backdrop'));
    expect(
      find.ancestor(of: backdrop, matching: find.byType(ExcludeSemantics)),
      findsWidgets,
    );
    expect(
      find.ancestor(of: backdrop, matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
    final ignore = tester.widget<IgnorePointer>(
      find.ancestor(of: backdrop, matching: find.byType(IgnorePointer)).first,
    );
    expect(ignore.ignoring, isTrue);
  });

  testWidgets('black policy draws one player over black', (tester) async {
    ReelVideoBackdropPolicy.debugOverride = ReelVideoBackdrop.black;
    await tester.pumpWidget(
      _host(
        const Size(390, 693),
        ReelFittedVideo(
          size: const Size(1920, 1080),
          video: () => VideoPlayer(controller),
        ),
      ),
    );
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byKey(const ValueKey('reel-fitted-video-scrim')), findsNothing);
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('reel-fitted-video-base')),
          )
          .color,
      Colors.black,
    );
  });

  testWidgets('web resolves to black', (tester) async {
    ReelVideoBackdropPolicy.debugOverride = null;
    ReelVideoBackdropPolicy.debugIsWeb = true;
    ReelVideoBackdropPolicy.instance.debugReset();
    await tester.pumpWidget(
      _host(
        const Size(390, 693),
        ReelFittedVideo(
          size: const Size(1920, 1080),
          video: () => VideoPlayer(controller),
        ),
      ),
    );
    await tester.pump();
    expect(ReelVideoBackdropPolicy.instance.effective, ReelVideoBackdrop.black);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  group('Android policy', () {
    Future<ReelVideoBackdrop> resolve(
      WidgetTester tester, {
      required bool lowRam,
      required int ramMb,
    }) async {
      ReelVideoBackdropPolicy.debugOverride = null;
      ReelVideoBackdropPolicy.debugIsWeb = false;
      ReelVideoBackdropPolicy.debugAndroidMemoryProbe = () async =>
          (isLowRamDevice: lowRam, physicalRamMb: ramMb);
      ReelVideoBackdropPolicy.instance.debugReset();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        // A fresh contained video: its initState is what starts the probe.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _host(
            const Size(390, 693),
            ReelFittedVideo(
              size: const Size(1920, 1080),
              video: () => VideoPlayer(controller),
            ),
          ),
        );
        // Black until the probe answers.
        expect(find.byType(ImageFiltered), findsNothing);
        await tester.pump();
        await tester.pump();
        return ReelVideoBackdropPolicy.instance.effective;
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('a capable device gets the blur', (tester) async {
      expect(
        await resolve(tester, lowRam: false, ramMb: 8192),
        ReelVideoBackdrop.blurred,
      );
      expect(find.byType(ImageFiltered), findsOneWidget);
    });

    testWidgets('a low-RAM device stays black', (tester) async {
      expect(
        await resolve(tester, lowRam: true, ramMb: 8192),
        ReelVideoBackdrop.black,
      );
    });

    testWidgets('a nominal 4 GB phone (or less) stays black', (tester) async {
      // Android reports totalMem, a little under the nominal size.
      for (final ramMb in <int>[2800, 3072, 3800, 4096]) {
        expect(
          await resolve(tester, lowRam: false, ramMb: ramMb),
          ReelVideoBackdrop.black,
          reason: '$ramMb MB',
        );
        expect(find.byType(ImageFiltered), findsNothing);
      }
    });

    testWidgets('a nominal 6 GB phone gets the blur', (tester) async {
      expect(
        await resolve(tester, lowRam: false, ramMb: 5600),
        ReelVideoBackdrop.blurred,
      );
    });
  });

  testWidgets('one quarter turn makes the Pixel cat an upright cover', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Size(390, 693),
        ReelFittedVideo(
          size: const Size(1920, 1080),
          quarterTurns: 1,
          video: () => VideoPlayer(controller),
        ),
      ),
    );
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(tester.widget<FittedBox>(find.byType(FittedBox)).fit, BoxFit.cover);
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 1);
    final sized = tester.widget<SizedBox>(
      find
          .ancestor(
            of: find.byType(RotatedBox),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(Size(sized.width!, sized.height!), const Size(1080, 1920));

    await tester.pumpWidget(
      _host(
        const Size(390, 693),
        ReelFittedVideo(
          size: const Size(1920, 1080),
          quarterTurns: 2,
          video: () => VideoPlayer(controller),
        ),
      ),
    );
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(
      tester
          .widgetList<RotatedBox>(find.byType(RotatedBox))
          .map((b) => b.quarterTurns),
      everyElement(2),
    );
  });

  test('both surfaces draw their video only through ReelFittedVideo', () {
    const files = <String>[
      'lib/features/reels/presentation/widgets/reel_draft_preview.dart',
      'lib/features/reels/presentation/widgets/reel_card.dart',
    ];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      final all = RegExp(r'(?<![A-Za-z_])VideoPlayer\(').allMatches(source);
      final fitted = RegExp(
        r'ReelFittedVideo\(\s*size:[^;]*?video: \(\) => VideoPlayer\(',
      ).allMatches(source);
      expect(all, isNotEmpty, reason: path);
      expect(
        fitted.length,
        all.length,
        reason: '$path: every VideoPlayer goes through ReelFittedVideo',
      );
    }
    final presentation = Directory('lib/features/reels/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in presentation) {
      if (files.contains(file.path)) continue;
      expect(
        RegExp(
          r'(?<![A-Za-z_])VideoPlayer\(',
        ).hasMatch(file.readAsStringSync()),
        isFalse,
        reason: '${file.path} draws a video outside the shared fit',
      );
    }
  });
}
