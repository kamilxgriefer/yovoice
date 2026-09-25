import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/shared/widgets/branding/yo_logo.dart';

/// `assets/images/logo-bloom.png` is DERIVED from `logo.png` (refine-look §4:
/// the logo at 320 px centred on a transparent 512 canvas, Gaussian σ 24,
/// colour and alpha kept). The widget draws it at 1.6 × the mark box so its
/// inner footprint equals the mark; that only holds for a 512 px RGBA file
/// that is transparent at the edges and coloured in the middle.
void main() {
  test('logo-bloom.png is a 512 × 512 RGBA PNG', () {
    final bytes = File(YoBrandMark.bloomAsset).readAsBytesSync();
    // PNG signature, then the IHDR chunk.
    expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(String.fromCharCodes(bytes.sublist(12, 16)), 'IHDR');
    final header = ByteData.sublistView(bytes, 16, 26);
    expect(header.getUint32(0), 512, reason: 'width');
    expect(header.getUint32(4), 512, reason: 'height');
    expect(header.getUint8(8), 8, reason: 'bit depth');
    expect(header.getUint8(9), 6, reason: 'colour type 6 = RGBA');
  });

  test('the bloom is transparent at the edges and lit in the middle', () async {
    final bytes = File(YoBrandMark.bloomAsset).readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    int alphaAt(int x, int y) => rgba.getUint8((y * 512 + x) * 4 + 3);
    expect(alphaAt(0, 0), 0);
    expect(alphaAt(511, 511), 0);
    expect(alphaAt(256, 20), 0, reason: 'the 96 px margin exceeds 3 sigma');
    expect(alphaAt(256, 256), greaterThan(96));
    // Partial alpha exists (a real blur, not a hard cut-out).
    var partial = 0;
    for (var x = 0; x < 512; x += 4) {
      final a = alphaAt(x, 256);
      if (a > 0 && a < 255) partial++;
    }
    expect(partial, greaterThan(20));
    image.dispose();
  });

  test('the mark source is unchanged: logo.png is 512 × 512 RGBA', () {
    final bytes = File(YoBrandMark.markAsset).readAsBytesSync();
    final header = ByteData.sublistView(bytes, 16, 26);
    expect(header.getUint32(0), 512);
    expect(header.getUint32(4), 512);
    expect(header.getUint8(9), 6);
  });
}
