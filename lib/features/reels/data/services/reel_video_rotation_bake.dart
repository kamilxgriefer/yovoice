import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_picked_file_range.dart';
import 'package:yovoice/features/reels/data/services/reel_upload.dart';
import 'package:yovoice/features/reels/data/services/reel_video_orientation.dart';

import 'reel_video_rotation_bake_bytes.dart'
    if (dart.library.io) 'reel_video_rotation_bake_io.dart'
    as platform;

// Bakes the composer's "Obróć" rotation into the upload (ADR-235).
//
// WHAT IS WRITTEN. Only the 36-byte `tkhd` matrix of each video track, in a
// LOCAL COPY, at Publish: the file's size, content type, 64-byte header and
// duration are unchanged, so the reservation's `mediaSize`, Storage
// `putFile`/`putData`, `_recoverUpload` and the server's finalize probe all
// see exactly what they saw before. There is no recipe field and no server
// change: every player — iOS, Android and web, installed builds included —
// applies the matrix on its own.
//
// WHERE. On io, when the pick is a real file: `File.copy` into
// `<temporary>/yeel-rotation/`, re-scan the copy, positioned writes through
// `RandomAccessFile(FileMode.append)` (O_RDWR without O_APPEND, so a
// positioned write keeps the length), then re-scan and assert the new
// rotation, the length and the header before streaming the copy exactly as
// the pick would have been. On web — or io without a real file — the bytes
// the byte transport would copy for `putData` anyway are patched in memory,
// so peak memory stays what it is today.

/// Why a bake failed.
enum ReelVideoRotationFailure {
  /// The picked file is gone (evicted by the OS, moved).
  sourceMissing,

  /// The picked file no longer has the size the draft measured, or the copy
  /// is not the bytes that were planned.
  sourceChanged,

  /// No room for the temporary copy.
  noSpace,

  /// The file's matrix could not be rotated (never offered in practice: the
  /// pill appears only after a successful scan).
  unsupported,
}

class ReelVideoRotationException implements Exception {
  const ReelVideoRotationException(this.reason);

  final ReelVideoRotationFailure reason;

  @override
  String toString() => 'ReelVideoRotationException(${reason.name})';
}

/// Resolves the directory baked copies live under (their parent). Production
/// uses path_provider's temporary directory; tests pass their own.
typedef ReelTemporaryDirectoryProvider = Future<String> Function();

/// The sub-directory of the temporary directory that holds baked copies.
const String reelRotationDirectoryName = 'yeel-rotation';

/// How long an orphaned copy (a crash mid-publish) may linger.
const Duration reelRotationCopyMaxAge = Duration(hours: 24);

/// A range reader over a picked file: a file seek on io; on web a `Range`
/// request against the picker's blob URL (or one whole-Blob fetch per reader
/// where a browser ignores `Range`) — never cross_file's whole-file copy per
/// read (see reel_picked_file_range.dart).
Future<ReelByteRangeReader> xFileRangeReader(XFile file) async =>
    reelPickedFileRangeReader(file, await file.length());

/// A read-only scan of a picked video: the rotatable tracks, or null when the
/// file cannot be rotated (the composer then hides "Obróć"). Never throws.
Future<ReelVideoOrientation?> scanReelUploadOrientation(
  ReelUploadPayload payload,
) async {
  if (payload.mediaKind != ReelMediaKind.video) return null;
  try {
    final file = payload.file;
    final reader = file != null
        ? await xFileRangeReader(file)
        : bytesRangeReader(payload.bytes);
    if (reader.length != payload.size) return null;
    final scan = await scanReelVideoOrientation(reader);
    if (scan.orientation == null) {
      debugPrint('Yeel rotation unavailable: ${scan.reason?.name}');
    }
    return scan.orientation;
  } catch (error) {
    debugPrint('Yeel rotation scan failed: $error');
    return null;
  }
}

/// Returns [source] with every video track turned [quarterTurns] clockwise.
/// A whole number of turns returns [source] itself.
Future<ReelUploadPayload> bakeReelVideoRotation(
  ReelUploadPayload source,
  int quarterTurns, {
  ReelTemporaryDirectoryProvider? temporaryDirectory,
}) {
  if (quarterTurns % 4 == 0) return Future<ReelUploadPayload>.value(source);
  return platform.bakeReelVideoRotationOnPlatform(
    source,
    quarterTurns % 4,
    temporaryDirectory: temporaryDirectory,
  );
}

/// Deletes a copy [bakeReelVideoRotation] made. Anything that is not such a
/// copy — the user's own picked file above all — is never touched.
Future<void> discardBakedReelVideo(ReelUploadPayload baked) =>
    platform.discardBakedReelVideoOnPlatform(baked);

/// Whether a payload [bakeReelVideoRotation] returned can still be uploaded:
/// false when its temporary copy was removed or truncated since (the OS may
/// trim the cache directory between attempts), so the caller bakes again
/// instead of failing every retry.
Future<bool> isBakedReelVideoIntact(ReelUploadPayload baked) =>
    platform.isBakedReelVideoIntactOnPlatform(baked);

/// Deletes copies older than [olderThan] left behind by an interrupted
/// session. Best effort; never throws.
Future<void> sweepStaleReelRotationCopies({
  Duration olderThan = reelRotationCopyMaxAge,
  ReelTemporaryDirectoryProvider? temporaryDirectory,
}) => platform.sweepStaleReelRotationCopiesOnPlatform(
  olderThan: olderThan,
  temporaryDirectory: temporaryDirectory,
);

/// The composer's seam over the calls above.
class ReelVideoRotationBaker {
  const ReelVideoRotationBaker({this.temporaryDirectory});

  final ReelTemporaryDirectoryProvider? temporaryDirectory;

  Future<ReelUploadPayload> bake(ReelUploadPayload source, int quarterTurns) =>
      bakeReelVideoRotation(
        source,
        quarterTurns,
        temporaryDirectory: temporaryDirectory,
      );

  Future<void> discard(ReelUploadPayload baked) => discardBakedReelVideo(baked);

  Future<bool> isIntact(ReelUploadPayload baked) =>
      isBakedReelVideoIntact(baked);

  Future<void> sweep() =>
      sweepStaleReelRotationCopies(temporaryDirectory: temporaryDirectory);
}

/// Asserts a patched source is exactly what was planned: same length, same
/// leading [header], every video track at (r + taps) mod 4 and every other
/// track untouched.
Future<void> verifyBakedReelVideo({
  required ReelByteRangeReader baked,
  required ReelVideoOrientation before,
  required int quarterTurns,
  required Uint8List header,
}) async {
  if (baked.length != before.length) {
    throw const ReelVideoRotationException(
      ReelVideoRotationFailure.sourceChanged,
    );
  }
  final head = await baked.read(0, header.length);
  if (!listEquals(head, header)) {
    throw const ReelVideoRotationException(
      ReelVideoRotationFailure.sourceChanged,
    );
  }
  final after = (await scanReelVideoOrientation(baked)).orientation;
  if (after == null || after.tracks.length != before.tracks.length) {
    throw const ReelVideoRotationException(
      ReelVideoRotationFailure.unsupported,
    );
  }
  for (var index = 0; index < after.tracks.length; index += 1) {
    final was = before.tracks[index];
    final now = after.tracks[index];
    final expected = was.isVideo
        ? (was.quarterTurns! + quarterTurns) % 4
        : was.quarterTurns;
    if (now.matrixOffset != was.matrixOffset ||
        now.handler != was.handler ||
        now.quarterTurns != expected) {
      throw const ReelVideoRotationException(
        ReelVideoRotationFailure.unsupported,
      );
    }
  }
}

/// How many leading bytes a bake proves unchanged (the sniffed header).
const int reelRotationHeaderBytes = reelHeaderProbeBytes;
