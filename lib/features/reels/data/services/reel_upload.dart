import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/reels/data/models/reel_composition.dart';

const int maxReelImageBytes = 10 * 1024 * 1024;
const int maxReelVideoBytes = 100 * 1024 * 1024;
const int maxReelBackingAudioBytes = 15 * 1024 * 1024;

@immutable
class ReelUploadPayload {
  const ReelUploadPayload({
    required this.bytes,
    required this.contentType,
    required this.durationMs,
    this.sourcePath,
  });

  final Uint8List bytes;
  final String contentType;
  final int durationMs;

  /// Device-local picker reference used only for the pre-publish preview.
  ///
  /// It is deliberately absent from the upload/finalize contract: the
  /// original bytes remain the sole payload and no local path can cross the
  /// backend boundary.
  final String? sourcePath;

  int get size => bytes.length;

  ReelMediaKind get mediaKind => contentType.startsWith('image/')
      ? ReelMediaKind.image
      : ReelMediaKind.video;

  static Future<ReelUploadPayload> fromXFile(
    XFile file, {
    required int durationMs,
  }) async {
    final length = await file.length();
    if (length < 128 || length > maxReelVideoBytes) {
      throw const FormatException('The selected media size is unsupported.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length != length) {
      throw const FormatException('The selected media could not be read.');
    }
    final contentType = sniffReelContentType(bytes);
    if (contentType == null ||
        (!contentType.startsWith('image/') &&
            !contentType.startsWith('video/'))) {
      throw const FormatException('Choose a supported photo or video.');
    }
    if (contentType.startsWith('image/')) {
      if (bytes.length > maxReelImageBytes || durationMs != 0) {
        throw const FormatException('The selected photo is unsupported.');
      }
    } else if (durationMs < minReelDurationMs ||
        durationMs > maxReelDurationMs) {
      throw const FormatException(
        'Choose a video between 1 second and 5 minutes.',
      );
    }
    return ReelUploadPayload(
      bytes: bytes,
      contentType: contentType,
      durationMs: durationMs,
      sourcePath: file.path,
    );
  }

  static ReelUploadPayload backingAudio({
    required Uint8List bytes,
    required int durationMs,
  }) {
    final contentType = sniffReelContentType(bytes);
    if (contentType == null ||
        !contentType.startsWith('audio/') ||
        bytes.length < 512 ||
        bytes.length > maxReelBackingAudioBytes ||
        durationMs < minReelDurationMs ||
        durationMs > maxReelDurationMs) {
      throw const FormatException('The backing audio is unsupported.');
    }
    return ReelUploadPayload(
      bytes: bytes,
      contentType: contentType,
      durationMs: durationMs,
    );
  }
}

/// Header-only media sniffing mirrored by the server. The client-provided MIME
/// type is never trusted on its own.
String? sniffReelContentType(Uint8List bytes) {
  bool at(int offset, List<int> values) {
    if (bytes.length < offset + values.length) return false;
    for (var index = 0; index < values.length; index += 1) {
      if (bytes[offset + index] != values[index]) return false;
    }
    return true;
  }

  if (at(0, const <int>[0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (at(0, const <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return 'image/png';
  }
  if (at(0, const <int>[0x52, 0x49, 0x46, 0x46]) &&
      at(8, const <int>[0x57, 0x45, 0x42, 0x50])) {
    return 'image/webp';
  }
  if (at(0, const <int>[0x1a, 0x45, 0xdf, 0xa3])) return 'video/webm';
  if (at(4, const <int>[0x66, 0x74, 0x79, 0x70])) {
    final brand = bytes.length >= 12
        ? String.fromCharCodes(bytes.sublist(8, 12))
        : '';
    if (brand == 'M4A ') return 'audio/mp4';
    if (<String>{'qt  ', 'M4V '}.contains(brand)) return 'video/quicktime';
    return 'video/mp4';
  }
  if (at(0, const <int>[0x49, 0x44, 0x33]) ||
      (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0)) {
    return 'audio/mpeg';
  }
  if (at(0, const <int>[0x52, 0x49, 0x46, 0x46]) &&
      at(8, const <int>[0x57, 0x41, 0x56, 0x45])) {
    return 'audio/wav';
  }
  return null;
}
