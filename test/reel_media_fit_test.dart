// The one fit rule composer and feed share (ADR-235, owner decision A).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/presentation/reel_media_fit.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_composition_canvas.dart';

void main() {
  group('fit table', () {
    const cover = <Size>[
      Size(1080, 1920), // 9:16, 100%
      Size(1080, 2400), // 9:20, 80%
      Size(1080, 2640), // 9:22 screen recording, 72.7%
      Size(1080, 1440), // 3:4, 75%
      Size(720, 960), // 3:4
    ];
    const contain = <Size>[
      Size(1080, 1350), // 4:5, 70.3%
      Size(1080, 1080), // 1:1, 56%
      Size(1920, 1080), // 16:9, 31.6% — the Pixel cat
      Size(2424, 1080), // 25%
    ];
    for (final size in cover) {
      test('$size is cover', () {
        expect(reelVideoFit(size), ReelMediaFit.cover);
        expect(
          reelCoverVisibleFraction(size),
          greaterThanOrEqualTo(reelCoverMinimumVisibleFraction),
        );
      });
    }
    for (final size in contain) {
      test('$size is contain', () {
        expect(reelVideoFit(size), ReelMediaFit.contain);
      });
    }

    test('exactly 72% visible is still cover', () {
      // Tall side: s / a = .72 → s = .405.
      expect(reelVideoFit(const Size(405, 1000)), ReelMediaFit.cover);
      // Wide side: a / s = .72 → s = .78125.
      expect(reelVideoFit(const Size(78125, 100000)), ReelMediaFit.cover);
      expect(reelVideoFit(const Size(404, 1000)), ReelMediaFit.contain);
      expect(reelVideoFit(const Size(78200, 100000)), ReelMediaFit.contain);
    });

    test('null, zero and non-finite sizes keep today\'s cover', () {
      expect(reelVideoFit(null), ReelMediaFit.cover);
      expect(reelVideoFit(Size.zero), ReelMediaFit.cover);
      expect(reelVideoFit(const Size(0, 1080)), ReelMediaFit.cover);
      expect(reelVideoFit(const Size(double.nan, 1080)), ReelMediaFit.cover);
      expect(
        reelVideoFit(const Size(1920, double.infinity)),
        ReelMediaFit.cover,
      );
    });

    test('the visible fractions the owner decided on', () {
      expect(
        reelCoverVisibleFraction(const Size(1920, 1080)),
        closeTo(.316, .001),
      );
      expect(
        reelCoverVisibleFraction(const Size(1080, 1350)),
        closeTo(.703, .001),
      );
      expect(
        reelCoverVisibleFraction(const Size(1080, 2640)),
        closeTo(.727, .001),
      );
    });
  });

  test('reelDisplaySize swaps on odd turns only', () {
    const size = Size(1920, 1080);
    expect(reelDisplaySize(size, 0), size);
    expect(reelDisplaySize(size, 1), const Size(1080, 1920));
    expect(reelDisplaySize(size, 2), size);
    expect(reelDisplaySize(size, 3), const Size(1080, 1920));
    // One tap turns the Pixel cat from contain to cover.
    expect(reelVideoFit(reelDisplaySize(size, 1)), ReelMediaFit.cover);
    expect(reelVideoFit(reelDisplaySize(size, 2)), ReelMediaFit.contain);
  });

  test('the fit depends on the clip alone, never the host frame', () {
    // reelVideoFit takes no host input at all; the same clip therefore gets
    // the same answer in the 9:16 composer and in a 0.588 phone feed.
    expect(reelVideoFit(const Size(1080, 1440)), ReelMediaFit.cover);
    expect(reelVideoFit(const Size(1080, 1350)), ReelMediaFit.contain);
  });

  test('reelContainRect centres a contained video', () {
    const frame = ReelCompositionFrame.designSize;
    final rect = reelContainRect(frame, const Size(1920, 1080));
    expect(rect.width, closeTo(390, 1e-9));
    expect(rect.height, closeTo(390 * 9 / 16, 1e-9));
    expect(rect.center.dx, closeTo(frame.width / 2, 1e-9));
    expect(rect.center.dy, closeTo(frame.height / 2, 1e-9));
  });

  group('pan limits', () {
    const frames = <Size>[
      Size(390, 390 * 16 / 9),
      Size(390, 663),
      Size(390, 750),
      Size(390, 930),
    ];

    test('cover and images keep frame·(s−1)/2 exactly', () {
      for (final frame in frames) {
        for (var scale = 1.0; scale <= 8; scale += .25) {
          final today = Offset(
            frame.width * (scale - 1) / 2,
            frame.height * (scale - 1) / 2,
          );
          expect(reelCropPanLimits(frame, scale), today);
          expect(
            reelCropPanLimits(frame, scale, mediaSize: const Size(1080, 1920)),
            today,
          );
          expect(
            reelCropPanLimits(frame, scale, mediaSize: const Size(1080, 1440)),
            today,
          );
        }
      }
    });

    test('contain pans on the fitted basis', () {
      const frame = Size(390, 390 * 16 / 9);
      const media = Size(1920, 1080);
      final fittedHeight = 390 * 9 / 16;
      // Y opens exactly where the zoomed picture overflows the frame.
      final threshold = frame.height / fittedHeight;
      expect(threshold, closeTo(3.16, .01));
      var previousY = 0.0;
      for (var scale = 1.0; scale <= 8; scale += .125) {
        final limits = reelCropPanLimits(frame, scale, mediaSize: media);
        expect(limits.dx, closeTo(frame.width * (scale - 1) / 2, 1e-9));
        final y = math.max(0.0, (fittedHeight * scale - frame.height) / 2);
        expect(limits.dy, closeTo(y, 1e-9));
        if (scale < threshold) expect(limits.dy, 0);
        expect(limits.dy, greaterThanOrEqualTo(previousY));
        previousY = limits.dy;
      }
    });

    test('the blurred backdrop stays edge-to-edge for any contain recipe', () {
      final random = math.Random(235);
      for (var index = 0; index < 500; index += 1) {
        final frame = Size(390, 390 * (1.4 + random.nextDouble()));
        final media = <Size>[
          const Size(1920, 1080),
          const Size(1080, 1080),
          const Size(1080, 1350),
          const Size(2424, 1080),
          const Size(400, 3000),
        ][random.nextInt(5)];
        final scale = 1 + random.nextDouble() * 7;
        final crop = ReelCropTransform(
          scale: scale,
          offsetX: random.nextDouble() * 2 - 1,
          offsetY: random.nextDouble() * 2 - 1,
        );
        final pan = reelCropTranslation(frame, crop, mediaSize: media);
        // The backdrop is a cover fill of the frame scaled about its centre,
        // then panned: it must still contain the whole frame.
        final backdrop = Rect.fromCenter(
          center: frame.center(Offset.zero) + pan,
          width: frame.width * scale,
          height: frame.height * scale,
        );
        expect(
          backdrop.left <= 1e-9 &&
              backdrop.top <= 1e-9 &&
              backdrop.right >= frame.width - 1e-9 &&
              backdrop.bottom >= frame.height - 1e-9,
          isTrue,
          reason: '$frame $media $crop',
        );
      }
    });

    test(
      'a legacy zoomed recipe renders contain × scale, centred vertically',
      () {
        const frame = Size(390, 390 * 16 / 9);
        const crop = ReelCropTransform(scale: 1.8, offsetX: -.2, offsetY: .3);
        final pan = reelCropTranslation(
          frame,
          crop,
          mediaSize: const Size(1920, 1080),
        );
        expect(pan.dx, closeTo(-.2 * 390 * .8 / 2, 1e-9));
        expect(pan.dy, 0);
        // Without a media size (a photo) the same recipe pans as before.
        expect(
          reelCropTranslation(frame, crop).dy,
          closeTo(.3 * frame.height * .8 / 2, 1e-9),
        );
      },
    );
  });
}
