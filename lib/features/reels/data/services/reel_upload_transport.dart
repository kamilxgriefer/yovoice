import 'package:firebase_storage/firebase_storage.dart';

import 'package:yovoice/features/reels/data/services/reel_upload.dart';

import 'reel_upload_transport_bytes.dart'
    if (dart.library.io) 'reel_upload_transport_io.dart';

/// Starts the Storage upload for one Reel asset and hands back the running
/// task, so the caller keeps owning progress, cancellation and the
/// lost-acknowledgement recovery it already implements.
///
/// WHY A PLATFORM SEAM. `putData` needs the whole asset resident in the Dart
/// heap. For a photo (10 MB) or backing audio (15 MB) that is already paid —
/// the preview needs those bytes. For a video (up to 100 MB) it was pure
/// overhead: the picker wrote a file, the app copied it across the platform
/// channel into a `Uint8List`, held it for the entire composer session, then
/// handed it to `putData`, which copies it again on the way out. Where a real
/// file exists (io) the plugin can stream it instead.
///
/// WHAT DOES NOT CHANGE. The backend contract. Storage receives the same
/// bytes and the same [SettableMetadata] — `contentType` plus `ownerId`,
/// `reelId` and `assetKind` — and `reserveReelDraftV2`/`finalizeReelDraftV2`
/// still carry no path of any kind. The server continues to derive truth from
/// the object's own headers and Storage metadata, so a file swapped between
/// the sniff and the upload is refused there exactly as before; the io
/// transport additionally re-checks the length immediately before uploading
/// so the common case fails early and locally.
Future<UploadTask> startReelUpload({
  required Reference reference,
  required ReelUploadPayload payload,
  required SettableMetadata metadata,
}) => startReelUploadTask(
  reference: reference,
  payload: payload,
  metadata: metadata,
);
