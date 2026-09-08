import 'package:firebase_storage/firebase_storage.dart';

import 'package:yovoice/features/reels/data/services/reel_upload.dart';

/// The byte transport, used wherever there is no `dart:io` file to stream —
/// web above all.
///
/// A browser picker never produced a file: its `XFile` wraps a Blob the page
/// already holds, so `putData` costs one copy out of that Blob and no
/// filesystem is involved. `putBlob` could avoid even that copy, but reaching
/// the picker's Blob means re-fetching its object URL — a browsers-only path
/// that cannot be exercised by this repo's test suite and that breaks as soon
/// as the URL is revoked. The copy is the cheaper risk, and the video byte cap
/// bounds it.
Future<UploadTask> startReelUploadTask({
  required Reference reference,
  required ReelUploadPayload payload,
  required SettableMetadata metadata,
}) async => reference.putData(await payload.readBytes(), metadata);
