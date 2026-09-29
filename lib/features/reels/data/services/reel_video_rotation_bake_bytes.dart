import 'package:flutter/foundation.dart';

import 'package:yovoice/features/reels/data/services/reel_upload.dart';
import 'package:yovoice/features/reels/data/services/reel_video_orientation.dart';
import 'package:yovoice/features/reels/data/services/reel_video_rotation_bake.dart';

/// The in-memory bake: web, and io when the pick is not a real file.
///
/// On web the byte transport already copies the whole video out of the
/// picker's Blob for `putData`; this reads that same copy once, patches the
/// matrices in it and hands it on as a resident payload, so the upload reuses
/// it and peak memory is what it was. A buffer the payload itself owns (a
/// resident payload, an `XFile.fromData`) is copied first: the user's source
/// is never mutated.
Future<ReelUploadPayload> bakeReelVideoRotationBytes(
  ReelUploadPayload source,
  int quarterTurns,
) async {
  try {
    return await _bakeBytes(source, quarterTurns);
  } on ReelVideoRotationException {
    rethrow;
  } catch (_) {
    // Nothing but the read above touches I/O; anything else unexpected is
    // still reported as a rotation failure, never as a generic media error.
    throw const ReelVideoRotationException(
      ReelVideoRotationFailure.sourceChanged,
    );
  }
}

Future<ReelUploadPayload> _bakeBytes(
  ReelUploadPayload source,
  int quarterTurns,
) async {
  final Uint8List original;
  try {
    original = await source.readBytes();
  } catch (_) {
    throw const ReelVideoRotationException(
      ReelVideoRotationFailure.sourceMissing,
    );
  }
  if (original.length != source.size) {
    throw const ReelVideoRotationException(
      ReelVideoRotationFailure.sourceChanged,
    );
  }
  final bytes = kIsWeb && source.isStreamed
      ? original
      : Uint8List.fromList(original);
  final orientation = (await scanReelVideoOrientation(
    bytesRangeReader(bytes),
  )).orientation;
  if (orientation == null) {
    throw const ReelVideoRotationException(
      ReelVideoRotationFailure.unsupported,
    );
  }
  final header = Uint8List.fromList(
    bytes.sublist(
      0,
      bytes.length < reelRotationHeaderBytes
          ? bytes.length
          : reelRotationHeaderBytes,
    ),
  );
  applyReelMatrixPatches(
    bytes,
    planReelVideoRotation(orientation, quarterTurns),
  );
  await verifyBakedReelVideo(
    baked: bytesRangeReader(bytes),
    before: orientation,
    quarterTurns: quarterTurns,
    header: header,
  );
  return ReelUploadPayload(
    bytes: bytes,
    contentType: source.contentType,
    durationMs: source.durationMs,
  );
}

Future<ReelUploadPayload> bakeReelVideoRotationOnPlatform(
  ReelUploadPayload source,
  int quarterTurns, {
  ReelTemporaryDirectoryProvider? temporaryDirectory,
}) => bakeReelVideoRotationBytes(source, quarterTurns);

/// Resident bytes cannot go missing.
Future<bool> isBakedReelVideoIntactOnPlatform(ReelUploadPayload baked) async =>
    true;

/// Nothing to delete: the patched bytes are garbage once unreferenced.
Future<void> discardBakedReelVideoOnPlatform(ReelUploadPayload baked) async {}

Future<void> sweepStaleReelRotationCopiesOnPlatform({
  required Duration olderThan,
  ReelTemporaryDirectoryProvider? temporaryDirectory,
}) async {}
