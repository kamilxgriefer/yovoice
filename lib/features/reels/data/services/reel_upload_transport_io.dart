import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import 'package:yovoice/features/reels/data/services/reel_upload.dart';

/// Streams a picked file straight to Storage; keeps `putData` for assets whose
/// bytes are legitimately resident (photos, backing audio).
Future<UploadTask> startReelUploadTask({
  required Reference reference,
  required ReelUploadPayload payload,
  required SettableMetadata metadata,
}) async {
  final path = payload.sourcePath;
  if (!payload.isStreamed || path == null || path.isEmpty) {
    return reference.putData(await payload.readBytes(), metadata);
  }
  final file = File(path);
  final int length;
  try {
    length = await file.length();
  } on FileSystemException {
    // The picker's temporary file can be evicted by the OS while the composer
    // is open. Say what happened instead of surfacing a filesystem error: the
    // draft is recoverable by choosing the video again.
    throw const FormatException(
      'The selected video is no longer available. Choose it again.',
    );
  }
  if (length != payload.size) {
    // The reservation already declared `payload.size`, and the server checks
    // the committed object against it. Refusing here turns a guaranteed
    // server-side rejection into an immediate, honest local failure.
    throw const FormatException(
      'The selected video changed after it was chosen. Choose it again.',
    );
  }
  return reference.putFile(file, metadata);
}
