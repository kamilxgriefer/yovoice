import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// A photo re-encoded for a Page post (spec premium-pages §1.1, §4.5):
/// JPEG, at most [ImageSanitizer.maxEdge] px on its long edge, orientation
/// baked into the pixels and no metadata at all.
@immutable
class SanitizedJpeg {
  const SanitizedJpeg({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Why a photo could not be prepared. The composer shows one line for all
/// of them ("Nie udało się przygotować zdjęcia N"), so the kind is kept for
/// logs and tests only.
enum ImageSanitizerProblem { undecodable, tooLarge, metadataLeft }

class ImageSanitizerException implements Exception {
  const ImageSanitizerException(this.problem);

  final ImageSanitizerProblem problem;

  @override
  String toString() => 'ImageSanitizerException(${problem.name})';
}

/// Decodes, bakes in the EXIF orientation, resizes and re-encodes a picked
/// photo as a metadata-free JPEG, in a background isolate (web runs it on
/// the event loop; the image stays ≤ 2048 px there too).
///
/// Every photo is re-encoded, whatever the picker already did: Android's
/// picker copies GPS EXIF into its output, and iOS's behaviour on resize is
/// not something to rely on. The server refuses any JPEG that still carries
/// an APP1-APP15 or COM segment (`pageMediaMetadata`), so this is the
/// client's half of one contract, and [jpegMetadataMarkers] re-checks the
/// output before it can be reserved.
Future<SanitizedJpeg> stripAndReencodeJpeg(Uint8List bytes) =>
    compute(ImageSanitizer.sanitize, bytes, debugLabel: 'page-photo');

abstract final class ImageSanitizer {
  /// §4.5: 2048 px on the long edge, quality 88.
  static const int maxEdge = 2048;
  static const int quality = 88;

  /// §1.1: the server's per-photo bounds.
  static const int maxBytes = 4 * 1024 * 1024;
  static const int minBytes = 128;

  /// A decoded bitmap above this many pixels is refused before allocation
  /// (a hostile header must not exhaust memory).
  static const int maxSourcePixels = 48 * 1024 * 1024;
  static const int maxSourceEdge = 16384;

  /// Qualities tried in order when a re-encode is still above [maxBytes].
  static const List<int> _fallbackQualities = <int>[quality, 80, 72, 64];

  static SanitizedJpeg sanitize(Uint8List bytes) {
    final decoder = img.findDecoderForData(bytes);
    if (decoder == null) {
      throw const ImageSanitizerException(ImageSanitizerProblem.undecodable);
    }
    final info = decoder.startDecode(bytes);
    if (info == null) {
      throw const ImageSanitizerException(ImageSanitizerProblem.undecodable);
    }
    if (info.width <= 0 ||
        info.height <= 0 ||
        info.width > maxSourceEdge ||
        info.height > maxSourceEdge ||
        info.width * info.height > maxSourcePixels) {
      throw const ImageSanitizerException(ImageSanitizerProblem.tooLarge);
    }
    img.Image? decoded;
    try {
      decoded = decoder.decode(bytes, frame: 0);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      throw const ImageSanitizerException(ImageSanitizerProblem.undecodable);
    }

    // Orientation first, so the long edge is the one the viewer sees.
    var image = img.bakeOrientation(decoded);
    final longEdge = math.max(image.width, image.height);
    if (longEdge > maxEdge) {
      image = image.width >= image.height
          ? img.copyResize(
              image,
              width: maxEdge,
              interpolation: img.Interpolation.average,
            )
          : img.copyResize(
              image,
              height: maxEdge,
              interpolation: img.Interpolation.average,
            );
    }
    if (image.hasAlpha) {
      // JPEG has no alpha: flatten a transparent picture onto white instead
      // of letting the encoder drop the channel into black.
      final flat = img.Image(width: image.width, height: image.height)
        ..clear(img.ColorRgb8(255, 255, 255));
      image = img.compositeImage(flat, image);
    }
    // Nothing but pixels leaves: no EXIF (GPS, camera, time), no ICC, no
    // text chunks carried over from a PNG.
    image
      ..exif = img.ExifData()
      ..iccProfile = null
      ..textData = null;

    for (final q in _fallbackQualities) {
      final encoded = img.encodeJpg(image, quality: q);
      if (jpegMetadataMarkers(encoded).isNotEmpty) {
        throw const ImageSanitizerException(ImageSanitizerProblem.metadataLeft);
      }
      if (encoded.length <= maxBytes) {
        if (encoded.length < minBytes) break;
        return SanitizedJpeg(
          bytes: encoded,
          width: image.width,
          height: image.height,
        );
      }
    }
    throw const ImageSanitizerException(ImageSanitizerProblem.tooLarge);
  }
}

/// The metadata markers a JPEG carries before its first scan: every APP1-
/// APP15 (`0xE1`-`0xEF`: Exif, XMP, ICC, …) and COM (`0xFE`) segment, as
/// the server's `assertNoImageMetadata` reads them (§2.4 step 3). APP0
/// (JFIF) is allowed. A stream that is not a well-formed JPEG header
/// reports `-1`.
List<int> jpegMetadataMarkers(Uint8List bytes) {
  final found = <int>[];
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return const <int>[-1];
  }
  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) return <int>[...found, -1];
    var marker = bytes[offset + 1];
    // Fill bytes (0xFF 0xFF …) before a marker are legal.
    while (marker == 0xFF && offset + 2 < bytes.length) {
      offset += 1;
      marker = bytes[offset + 1];
    }
    if (marker == 0xDA) return found; // SOS: the header is over.
    if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7) || marker == 1) {
      offset += 2;
      continue;
    }
    final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (length < 2) return <int>[...found, -1];
    if ((marker >= 0xE1 && marker <= 0xEF) || marker == 0xFE) {
      found.add(marker);
    }
    offset += 2 + length;
  }
  return <int>[...found, -1];
}
