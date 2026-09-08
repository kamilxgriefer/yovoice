import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/reels/data/models/reel_composition.dart';

const int maxReelImageBytes = 10 * 1024 * 1024;
const int maxReelVideoBytes = 100 * 1024 * 1024;
const int maxReelBackingAudioBytes = 15 * 1024 * 1024;

/// How many leading bytes are enough to identify a Reel asset.
///
/// [sniffReelContentType] never looks past byte 12; 64 leaves room for a
/// future signature without ever reading a whole video into the heap.
const int reelHeaderProbeBytes = 64;

@immutable
class ReelUploadPayload {
  /// A payload whose bytes are resident in the heap.
  ///
  /// Photos need them for `Image.memory` and backing audio for `BytesSource`,
  /// so those two keep the original behaviour and their caps (10 MB / 15 MB)
  /// bound the cost.
  const ReelUploadPayload({
    required this.bytes,
    required this.contentType,
    required this.durationMs,
    this.sourcePath,
  }) : file = null,
       _streamedSize = null;

  /// A payload the picker left on disk (or in a browser Blob).
  ///
  /// Video is capped at 100 MB, and reading it into a `Uint8List` cost that
  /// much heap plus the platform-channel copy on the way in — held for the
  /// whole composer session, then handed to `putData` for another copy on the
  /// way out. Here nothing but the handle and the length is retained and the
  /// transport streams from the source.
  ///
  /// [bytes] is a fresh empty list rather than null so that the preview's
  /// `identical(old.bytes, new.bytes)` change detection keeps meaning exactly
  /// what it meant: same payload instance, same source.
  ReelUploadPayload.pickedFile({
    required XFile pickedFile,
    required int size,
    required this.contentType,
    required this.durationMs,
  }) : bytes = Uint8List(0),
       file = pickedFile,
       sourcePath = pickedFile.path,
       _streamedSize = size;

  /// Resident bytes, EMPTY for a streamed source — use [readBytes] when a
  /// consumer genuinely needs the content regardless of how it is held.
  final Uint8List bytes;
  final String contentType;
  final int durationMs;

  /// The picker handle for a streamed source; null when [bytes] is the source.
  final XFile? file;

  /// Device-local picker reference used only for the pre-publish preview.
  ///
  /// It is deliberately absent from the upload/finalize contract: the asset's
  /// bytes remain the sole payload and no local path can cross the backend
  /// boundary. Streaming the upload from this file does not change that — the
  /// plugin opens it locally and Firebase Storage still receives bytes plus
  /// the same declared metadata.
  final String? sourcePath;

  final int? _streamedSize;

  /// True when the content lives at [file] rather than in [bytes].
  bool get isStreamed => file != null;

  /// The authoritative byte count, whichever way the content is held. It is
  /// what `reserveReelDraftV2` declares and what the server checks the
  /// committed object against.
  int get size => _streamedSize ?? bytes.length;

  ReelMediaKind get mediaKind => contentType.startsWith('image/')
      ? ReelMediaKind.image
      : ReelMediaKind.video;

  /// The full content, read from the source when it is not resident.
  Future<Uint8List> readBytes() async {
    final source = file;
    if (source == null) return bytes;
    return source.readAsBytes();
  }

  static Future<ReelUploadPayload> fromXFile(
    XFile file, {
    required int durationMs,
  }) async {
    final length = await file.length();
    if (length < 128 || length > maxReelVideoBytes) {
      throw const FormatException('The selected media size is unsupported.');
    }
    // Header only. A 100 MB video is identified from its first bytes exactly
    // as well as from all of them, and this is the read that used to pull the
    // whole file into memory at pick time.
    final header = await readReelHeader(file);
    final contentType = sniffReelContentType(header);
    if (contentType == null ||
        (!contentType.startsWith('image/') &&
            !contentType.startsWith('video/'))) {
      throw const FormatException('Choose a supported photo or video.');
    }
    if (contentType.startsWith('image/')) {
      final bytes = await file.readAsBytes();
      if (bytes.length != length) {
        throw const FormatException('The selected media could not be read.');
      }
      if (bytes.length > maxReelImageBytes || durationMs != 0) {
        throw const FormatException('The selected photo is unsupported.');
      }
      return ReelUploadPayload(
        bytes: bytes,
        contentType: contentType,
        durationMs: durationMs,
        sourcePath: file.path,
      );
    }
    if (durationMs < minReelDurationMs || durationMs > maxReelDurationMs) {
      throw const FormatException(
        'Choose a video between 1 second and 5 minutes.',
      );
    }
    return ReelUploadPayload.pickedFile(
      pickedFile: file,
      size: length,
      contentType: contentType,
      durationMs: durationMs,
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

/// Reads at most [reelHeaderProbeBytes] leading bytes of [file].
///
/// `XFile.openRead` is a range read on every platform this app ships to: a
/// file seek on io, a `Blob.slice` on web. A short file simply yields fewer
/// bytes, and [sniffReelContentType] refuses what it cannot identify.
Future<Uint8List> readReelHeader(
  XFile file, {
  int limit = reelHeaderProbeBytes,
}) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in file.openRead(0, limit)) {
    builder.add(chunk);
    if (builder.length >= limit) break;
  }
  final header = builder.takeBytes();
  return header.length <= limit
      ? header
      : Uint8List.sublistView(header, 0, limit);
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
