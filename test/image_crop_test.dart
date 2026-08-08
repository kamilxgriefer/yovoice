import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:yovoice/features/profile/data/services/image_crop.dart';
import 'package:yovoice/features/profile/data/services/profile_image_rules.dart';

/// Regression suite for the crop pipeline: the viewport→source geometry
/// must be exact, and the avatar output must remain exactly 1:1.
Future<ui.Image> _solidImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF7B2FF7),
  );
  return recorder.endRecording().toImage(width, height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('avatar rules pin the crop to exactly 1:1', () {
    expect(ProfileImageRules.avatar.aspectRatio, 1);
    expect(ProfileImageRules.banner.aspectRatio, 16 / 9);
  });

  test('cover-centered transform maps the viewport to the centered band', () {
    // 200x100 image behind a 100x100 frame at cover scale (1.0),
    // centered: the visible square is the middle 100px of the width.
    final matrix = Matrix4.identity()
      ..translateByDouble(-50, 0, 0, 1)
      ..scaleByDouble(1, 1, 1, 1);
    final rect = ImageCrop.sourceRectFor(
      matrix: matrix,
      viewport: const Size(100, 100),
      imageSize: const Size(200, 100),
    );
    expect(rect, const Rect.fromLTRB(50, 0, 150, 100));
  });

  test('zoomed transform maps to the proportionally smaller region', () {
    // Same image, zoomed 2x and centered: displayed 400x200, so the
    // 100x100 viewport sees a 50x50 source region in the middle.
    final matrix = Matrix4.identity()
      ..translateByDouble(-150, -50, 0, 1)
      ..scaleByDouble(2, 2, 1, 1);
    final rect = ImageCrop.sourceRectFor(
      matrix: matrix,
      viewport: const Size(100, 100),
      imageSize: const Size(200, 100),
    );
    expect(rect, const Rect.fromLTRB(75, 25, 125, 75));
  });

  test('source rect is clamped inside the image bounds', () {
    // A transform that would look past the edges cannot produce a rect
    // outside the image — no empty space can enter the final crop.
    final matrix = Matrix4.identity()
      ..translateByDouble(20, 20, 0, 1)
      ..scaleByDouble(1, 1, 1, 1);
    final rect = ImageCrop.sourceRectFor(
      matrix: matrix,
      viewport: const Size(100, 100),
      imageSize: const Size(60, 60),
    );
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(60));
    expect(rect.bottom, lessThanOrEqualTo(60));
  });

  test('rendered avatar crop is a JPEG at exactly the requested 1:1 '
      'dimensions', () async {
    final source = await _solidImage(300, 200);
    final bytes = await ImageCrop.renderCroppedJpeg(
      image: source,
      sourceRect: const Rect.fromLTRB(50, 0, 250, 200),
      outputWidth: 512,
      outputHeight: 512,
    );

    expect(ProfileImageRules.detectFormat(bytes), ProfileImageFormat.jpeg);
    final decoded = img.decodeJpg(bytes)!;
    expect(decoded.width, 512);
    expect(decoded.height, 512, reason: 'avatar output must stay 1:1');
  });

  test('rendered banner crop honours the 16:9 output size', () async {
    final source = await _solidImage(640, 360);
    final bytes = await ImageCrop.renderCroppedJpeg(
      image: source,
      sourceRect: const Rect.fromLTRB(0, 0, 640, 360),
      outputWidth: 1920,
      outputHeight: 1080,
    );
    final decoded = img.decodeJpg(bytes)!;
    expect(decoded.width, 1920);
    expect(decoded.height, 1080);
  });
}
