import 'dart:io';
import 'dart:math';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:yovoice/features/reels/data/services/reel_upload.dart';
import 'package:yovoice/features/reels/data/services/reel_video_orientation.dart';
import 'package:yovoice/features/reels/data/services/reel_video_rotation_bake.dart';

import 'reel_video_rotation_bake_bytes.dart';

/// The file bake: a copy of the picked video with its matrices rewritten in
/// place, streamed to Storage exactly as the pick would have been (the io
/// transport re-checks its length right before `putFile`).
///
/// Every failure is a [ReelVideoRotationException]: a raw I/O error from
/// reading, scanning or verifying (the copy or the source removed mid-bake,
/// the temporary directory unavailable) is reported as the source having
/// changed, so the composer names the remedy instead of a generic message.
Future<ReelUploadPayload> bakeReelVideoRotationOnPlatform(
  ReelUploadPayload source,
  int quarterTurns, {
  ReelTemporaryDirectoryProvider? temporaryDirectory,
}) async {
  try {
    return await _bakeFile(
      source,
      quarterTurns,
      temporaryDirectory: temporaryDirectory,
    );
  } on ReelVideoRotationException {
    rethrow;
  } on FileSystemException catch (error) {
    throw ReelVideoRotationException(
      _isNoSpace(error)
          ? ReelVideoRotationFailure.noSpace
          : ReelVideoRotationFailure.sourceChanged,
    );
  } catch (_) {
    throw const ReelVideoRotationException(
      ReelVideoRotationFailure.sourceChanged,
    );
  }
}

Future<ReelUploadPayload> _bakeFile(
  ReelUploadPayload source,
  int quarterTurns, {
  ReelTemporaryDirectoryProvider? temporaryDirectory,
}) async {
  final path = source.sourcePath;
  if (!source.isStreamed ||
      path == null ||
      path.isEmpty ||
      !await File(path).exists()) {
    // No real file behind the pick (a resident payload, XFile.fromData) — or
    // one that has vanished, which the bytes path reports as sourceMissing.
    return bakeReelVideoRotationBytes(source, quarterTurns);
  }
  final sourceFile = File(path);
  final int length;
  try {
    length = await sourceFile.length();
  } on FileSystemException {
    throw const ReelVideoRotationException(
      ReelVideoRotationFailure.sourceMissing,
    );
  }
  if (length != source.size) {
    throw const ReelVideoRotationException(
      ReelVideoRotationFailure.sourceChanged,
    );
  }
  final directory = await _rotationDirectory(temporaryDirectory);
  final extension = source.contentType == 'video/quicktime' ? 'mov' : 'mp4';
  final copyPath = '${directory.path}/${_randomName()}.$extension';
  try {
    final File copy;
    try {
      copy = await sourceFile.copy(copyPath);
    } on FileSystemException catch (error) {
      throw ReelVideoRotationException(
        _isNoSpace(error)
            ? ReelVideoRotationFailure.noSpace
            : ReelVideoRotationFailure.sourceMissing,
      );
    }
    final reader = await xFileRangeReader(XFile(copy.path));
    if (reader.length != source.size) {
      throw const ReelVideoRotationException(
        ReelVideoRotationFailure.sourceChanged,
      );
    }
    final orientation = (await scanReelVideoOrientation(reader)).orientation;
    if (orientation == null) {
      throw const ReelVideoRotationException(
        ReelVideoRotationFailure.unsupported,
      );
    }
    final header = await reader.read(
      0,
      reader.length < reelRotationHeaderBytes
          ? reader.length
          : reelRotationHeaderBytes,
    );
    // FileMode.append opens O_RDWR WITHOUT O_APPEND: setPosition is honoured
    // and a positioned write overwrites in place, keeping the length. The
    // re-scan below turns any platform deviation into a safe failure rather
    // than a corrupt upload.
    final file = await copy.open(mode: FileMode.append);
    try {
      for (final patch in planReelVideoRotation(orientation, quarterTurns)) {
        await file.setPosition(patch.offset);
        await file.writeFrom(patch.bytes);
      }
      await file.flush();
    } on FileSystemException catch (error) {
      throw ReelVideoRotationException(
        _isNoSpace(error)
            ? ReelVideoRotationFailure.noSpace
            : ReelVideoRotationFailure.sourceChanged,
      );
    } finally {
      await file.close();
    }
    await verifyBakedReelVideo(
      baked: await xFileRangeReader(XFile(copy.path)),
      before: orientation,
      quarterTurns: quarterTurns,
      header: header,
    );
    return ReelUploadPayload.pickedFile(
      pickedFile: XFile(copy.path, mimeType: source.contentType),
      size: source.size,
      contentType: source.contentType,
      durationMs: source.durationMs,
    );
  } catch (_) {
    try {
      await File(copyPath).delete();
    } catch (_) {}
    rethrow;
  }
}

/// True while a baked copy can still be streamed: a copy under the rotation
/// directory must exist with its planned length (the OS may trim the cache
/// directory between attempts). Anything else is resident or not ours.
Future<bool> isBakedReelVideoIntactOnPlatform(ReelUploadPayload baked) async {
  final path = baked.sourcePath;
  if (!baked.isStreamed || path == null || !_isRotationCopy(path)) return true;
  try {
    final file = File(path);
    return await file.exists() && await file.length() == baked.size;
  } catch (_) {
    return false;
  }
}

Future<void> discardBakedReelVideoOnPlatform(ReelUploadPayload baked) async {
  final path = baked.sourcePath;
  if (!baked.isStreamed || path == null || !_isRotationCopy(path)) return;
  try {
    await File(path).delete();
  } catch (_) {}
}

Future<void> sweepStaleReelRotationCopiesOnPlatform({
  required Duration olderThan,
  ReelTemporaryDirectoryProvider? temporaryDirectory,
}) async {
  try {
    final directory = Directory(
      '${await _temporaryRoot(temporaryDirectory)}/$reelRotationDirectoryName',
    );
    if (!await directory.exists()) return;
    final cutoff = DateTime.now().subtract(olderThan);
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (_) {}
    }
  } catch (_) {}
}

Future<String> _temporaryRoot(ReelTemporaryDirectoryProvider? provider) async =>
    provider != null ? await provider() : (await getTemporaryDirectory()).path;

Future<Directory> _rotationDirectory(
  ReelTemporaryDirectoryProvider? provider,
) async {
  final Directory directory;
  try {
    directory = Directory(
      '${await _temporaryRoot(provider)}/$reelRotationDirectoryName',
    );
    await directory.create(recursive: true);
  } on FileSystemException catch (error) {
    throw ReelVideoRotationException(
      _isNoSpace(error)
          ? ReelVideoRotationFailure.noSpace
          : ReelVideoRotationFailure.sourceMissing,
    );
  }
  return directory;
}

bool _isRotationCopy(String path) {
  final separator = Platform.pathSeparator;
  final segments = path.split(separator == '/' ? '/' : RegExp(r'[\\/]'));
  return segments.length >= 2 &&
      segments[segments.length - 2] == reelRotationDirectoryName &&
      RegExp(r'^[0-9a-f]{32}\.(mp4|mov)$').hasMatch(segments.last);
}

String _randomName() {
  final random = Random.secure();
  return List<String>.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// ENOSPC (28 on Linux, Android, macOS and iOS) and Windows' disk-full codes.
bool _isNoSpace(FileSystemException error) {
  final code = error.osError?.errorCode;
  return code == 28 || code == 112 || code == 39;
}
