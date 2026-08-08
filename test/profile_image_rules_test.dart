import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/profile/data/services/profile_image_rules.dart';

Uint8List _withHeader(List<int> header, {int totalBytes = 64}) {
  final bytes = Uint8List(totalBytes);
  for (var i = 0; i < header.length && i < totalBytes; i++) {
    bytes[i] = header[i];
  }
  return bytes;
}

Uint8List get _jpeg => _withHeader([0xFF, 0xD8, 0xFF, 0xE0]);
Uint8List get _png =>
    _withHeader([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
Uint8List get _webp => _withHeader([
  0x52, 0x49, 0x46, 0x46, // RIFF
  0x00, 0x00, 0x00, 0x00, // size
  0x57, 0x45, 0x42, 0x50, // WEBP
]);

/// HEIC/HEIF, which iPhones produce by default and which no supported
/// platform can decode uniformly.
Uint8List get _heic => _withHeader([
  0x00, 0x00, 0x00, 0x18, //
  0x66, 0x74, 0x79, 0x70, // ftyp
  0x68, 0x65, 0x69, 0x63, // heic
]);

void main() {
  group('detectFormat', () {
    test('identifies formats from magic bytes, not the file name', () {
      expect(ProfileImageRules.detectFormat(_jpeg), ProfileImageFormat.jpeg);
      expect(ProfileImageRules.detectFormat(_png), ProfileImageFormat.png);
      expect(ProfileImageRules.detectFormat(_webp), ProfileImageFormat.webp);
    });

    test('rejects formats the app cannot decode everywhere', () {
      expect(ProfileImageRules.detectFormat(_heic), isNull);
    });

    test('rejects truncated data instead of reading past the end', () {
      expect(ProfileImageRules.detectFormat(Uint8List(0)), isNull);
      expect(
        ProfileImageRules.detectFormat(Uint8List.fromList([0xFF, 0xD8])),
        isNull,
      );
    });
  });

  group('validateSource', () {
    test('accepts a normal JPEG for both kinds', () {
      expect(
        () => ProfileImageRules.avatar.validateSource(_jpeg),
        returnsNormally,
      );
      expect(
        () => ProfileImageRules.banner.validateSource(_jpeg),
        returnsNormally,
      );
    });

    test('avatars are capped at 5 MB', () {
      final oversized = _withHeader([
        0xFF,
        0xD8,
        0xFF,
        0xE0,
      ], totalBytes: 5 * 1024 * 1024 + 1);

      expect(
        () => ProfileImageRules.avatar.validateSource(oversized),
        throwsA(
          isA<ProfileImageException>().having(
            (e) => e.message,
            'message',
            'Image must be smaller than 5 MB.',
          ),
        ),
      );
    });

    test('banners allow more than avatars but are capped at 10 MB', () {
      final sevenMegabytes = _withHeader([
        0xFF,
        0xD8,
        0xFF,
        0xE0,
      ], totalBytes: 7 * 1024 * 1024);

      // Too big for an avatar...
      expect(
        () => ProfileImageRules.avatar.validateSource(sevenMegabytes),
        throwsA(isA<ProfileImageException>()),
      );
      // ...but fine as a banner.
      expect(
        () => ProfileImageRules.banner.validateSource(sevenMegabytes),
        returnsNormally,
      );

      final oversized = _withHeader([
        0xFF,
        0xD8,
        0xFF,
        0xE0,
      ], totalBytes: 10 * 1024 * 1024 + 1);
      expect(
        () => ProfileImageRules.banner.validateSource(oversized),
        throwsA(
          isA<ProfileImageException>().having(
            (e) => e.message,
            'message',
            'Banner image must be smaller than 10 MB.',
          ),
        ),
      );
    });

    test('unsupported and corrupt files get actionable copy', () {
      expect(
        () => ProfileImageRules.avatar.validateSource(_heic),
        throwsA(
          isA<ProfileImageException>().having(
            (e) => e.message,
            'message',
            contains('JPG, PNG or WebP'),
          ),
        ),
      );

      expect(
        () => ProfileImageRules.avatar.validateSource(Uint8List(0)),
        throwsA(
          isA<ProfileImageException>().having(
            (e) => e.message,
            'message',
            "We couldn't process this image. Try another one.",
          ),
        ),
      );
    });
  });

  group('rules', () {
    test('avatar crops square, banner is wider than the phone header band', () {
      // The Profile header is a full-bleed 320pt band, so its displayed
      // ratio varies by viewport; the stored banner must be at least as
      // wide as the widest presentation because it is drawn with cover.
      expect(
        ProfileImageRules.banner.aspectRatio,
        greaterThan(430 / 320),
        reason: 'must not be narrower than the largest phone header band',
      );
    });

    test('documented ratios', () {
      expect(ProfileImageRules.avatar.aspectRatio, 1);
      expect(ProfileImageRules.banner.aspectRatio, closeTo(16 / 9, 0.001));
    });

    test('output edges stay within the documented budget', () {
      expect(ProfileImageRules.avatar.maxOutputEdge, 1024);
      expect(ProfileImageRules.banner.maxOutputEdge, 1920);
    });
  });
}
