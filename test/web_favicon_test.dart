import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// The app's browser tab used to show the YO Voice mark inside a solid
/// black square while the landing page showed the clean transparent one.
/// The cause was the icon set itself — RealFaviconGenerator output built
/// from artwork with the square baked in — so these tests pin the two
/// things that made it wrong and stay wrong:
///
///  1. every icon the app declares is really transparent, and
///  2. `index.html` / `site.webmanifest` point ONLY at that set, with a
///     cache-busting version on each reference.
///
/// See web/README.md for how the set is generated from the marketing
/// site's canonical icon.
void main() {
  final web = Directory('web');

  /// Alpha of the top-left pixel, decoded straight from the PNG (no
  /// rasteriser needed). That corner is exactly what a baked-in square
  /// fills and what transparent artwork leaves empty.
  ///
  /// Only the FIRST pixel is decoded, which keeps this honest and tiny:
  /// for the first pixel of the first scanline every PNG filter type
  /// reduces to the raw bytes, because all of its predictors (left,
  /// above, above-left) are outside the image and defined as zero.
  int cornerAlpha(File file) {
    final bytes = file.readAsBytesSync();
    expect(bytes.sublist(0, 8), const [
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
    ], reason: '${file.path} is not a PNG');

    // IHDR always comes first: length(4) type(4) then w(4) h(4) depth(1)
    // colour(1) compression(1) filter(1) interlace(1).
    expect(bytes[24], 8, reason: '${file.path} must be 8-bit');
    expect(
      bytes[25],
      6,
      reason:
          '${file.path} must be RGBA (colour type 6); anything else '
          'cannot carry transparency at all',
    );
    expect(bytes[28], 0, reason: '${file.path} must not be interlaced');

    final idat = <int>[];
    var offset = 8;
    final view = ByteData.sublistView(Uint8List.fromList(bytes));
    while (offset + 8 <= bytes.length) {
      final length = view.getUint32(offset);
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      if (type == 'IDAT') {
        idat.addAll(bytes.sublist(offset + 8, offset + 8 + length));
      }
      if (type == 'IEND') break;
      offset += 12 + length; // length + type + data + CRC
    }
    expect(idat, isNotEmpty, reason: '${file.path} has no image data');

    final raw = ZLibDecoder().convert(idat);
    // [0] is the scanline's filter byte, then R G B A of pixel (0, 0).
    return raw[4];
  }

  group('favicon assets', () {
    const icons = [
      'favicon-16x16.png',
      'favicon-32x32.png',
      'favicon-96x96.png',
      'apple-touch-icon.png',
      'web-app-manifest-192x192.png',
      'web-app-manifest-512x512.png',
    ];

    test('every declared PNG icon is transparent behind the mark, not a '
        'black tile', () {
      for (final name in icons) {
        final file = File('${web.path}/$name');
        expect(file.existsSync(), isTrue, reason: '$name is missing');
        expect(
          cornerAlpha(file),
          0,
          reason:
              '$name has an opaque corner — the square is back. Regenerate '
              'from the transparent master (see web/README.md).',
        );
      }
      expect(File('${web.path}/favicon.ico').existsSync(), isTrue);
    });

    test('the retired black-square assets are gone', () {
      for (final name in [
        // RealFaviconGenerator leftovers built from the squared artwork.
        'favicon.svg',
        'favicon.zip',
        'favicon.png',
        // `flutter create` scaffolding: a second manifest nothing linked,
        // still branded "A new Flutter project" with Flutter's blue.
        'manifest.json',
        'icons/Icon-192.png',
        'icons/Icon-512.png',
        'icons/Icon-maskable-192.png',
        'icons/Icon-maskable-512.png',
      ]) {
        expect(
          File('${web.path}/$name').existsSync(),
          isFalse,
          reason: '$name is an obsolete favicon asset and must stay deleted',
        );
      }
    });
  });

  group('web/index.html', () {
    final html = File('${web.path}/index.html').readAsStringSync();

    test('declares the current icon set with cache-busting versions', () {
      for (final href in [
        'favicon-16x16.png?v=',
        'favicon-32x32.png?v=',
        'favicon-96x96.png?v=',
        'favicon.ico?v=',
        'apple-touch-icon.png?v=',
        'site.webmanifest?v=',
      ]) {
        expect(html, contains(href), reason: 'missing link to $href');
      }
    });

    test('references no retired icon and no second manifest', () {
      expect(html, isNot(contains('favicon.svg')));
      expect(html, isNot(contains('href="manifest.json"')));
    });

    test('the browser-tab title is untouched', () {
      expect(html, contains('<title>YoVoice</title>'));
    });

    test('owns the one real startup surface with an animated voice wave', () {
      expect(html, contains('id="yovoice-bootstrap"'));
      expect(html, contains('class="boot-wave"'));
      expect(html, contains('YO VOICE'));
      expect(html, contains('Create your space'));

      final bootstrap = File(
        '${web.path}/flutter_bootstrap.js',
      ).readAsStringSync();
      expect(bootstrap, contains('await appRunner.runApp()'));
      expect(bootstrap, contains('splash.classList.add("boot-leaving")'));
      expect(bootstrap, contains('splash.remove()'));
    });
  });

  group('web/site.webmanifest', () {
    final manifest =
        jsonDecode(File('${web.path}/site.webmanifest').readAsStringSync())
            as Map<String, dynamic>;

    test('PWA icons point at the current set', () {
      final icons = (manifest['icons'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(icons, hasLength(2));
      for (final icon in icons) {
        expect(icon['src'] as String, startsWith('web-app-manifest-'));
        expect(icon['src'] as String, contains('?v='));
        // The artwork is transparent with ~8% padding: declaring it
        // maskable would let the platform crop into the mark.
        expect(icon['purpose'], 'any');
      }
    });
  });

  group('native launcher icons', () {
    final config = File('pubspec.yaml').readAsStringSync();

    test('uses the favicon mark instead of the retired squared artwork', () {
      expect(config, contains('image_path: assets/images/app-store-icon.png'));
      expect(
        config,
        contains(
          'adaptive_icon_foreground: '
          'assets/images/yo-voice-favicon-512.png',
        ),
      );
      expect(
        config,
        isNot(contains('adaptive_icon_foreground: assets/images/logo.png')),
      );
      expect(config, contains('adaptive_icon_background: "#0B1026"'));
      expect(config, contains('adaptive_icon_foreground_inset: 8'));
    });

    test('all generated store and desktop masters exist', () {
      for (final path in [
        'assets/images/app-store-icon.png',
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
            'Icon-App-1024x1024@1x.png',
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
        'android/app/src/main/res/drawable-xxxhdpi/'
            'ic_launcher_foreground.png',
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
        'windows/runner/resources/app_icon.ico',
      ]) {
        expect(File(path).existsSync(), isTrue, reason: '$path is missing');
      }
    });
  });
}
