import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'club_media_upload_source_stub.dart'
    if (dart.library.io) 'club_media_upload_source_io.dart'
    if (dart.library.js_interop) 'club_media_upload_source_web.dart';

/// The content of one picked photo or video on its way to the Storage object a
/// server channel reservation named, in whatever form the platform that
/// produced it happens to hold it.
///
/// WHY THIS EXISTS. Sending channel media used to begin with
/// `await image.readAsBytes()` in the scene — the complete pick pulled across
/// the platform channel into one `Uint8List` merely to measure it — and end
/// with `reference.putData(bytes, …)`, which copies the same bytes again on
/// the way out. A 64 MiB video therefore cost roughly 128 MiB of transient
/// heap, which is an out-of-memory kill on a mid-range Android phone. The
/// picker had written a file the entire time.
///
/// Direct messages already avoid this: their payload store is platform-split
/// and uploads with `putFile` on io
/// (`lib/features/messages/data/services/direct_attachment_payload_store_io.dart`),
/// keeping `putData` for the browser, where there is no file to stream. This is
/// the same split for the one remaining bytes-shaped upload.
///
/// WHAT DOES NOT CHANGE. What may be sent, and the backend contract. The image
/// (128 B .. 8 MiB) and video (1 KiB .. 64 MiB, at most 60 s) bounds are still
/// decided in the scene before anything is reserved, [length] is still what the
/// reservation declares and what the committed object is checked against, and
/// no device path reaches a callable or the upload's metadata. Storage receives
/// the same bytes with the same [SettableMetadata], so the server keeps
/// deriving truth from the committed object's own headers.
abstract class ClubMediaUploadSource {
  /// A pick as the platform picker left it: a file on io, a Blob on web.
  ///
  /// [length] is the authoritative byte count, measured once with
  /// `XFile.length()` — never by reading the pick — and reused for the
  /// reservation and for the post-upload size check.
  factory ClubMediaUploadSource.pickedFile(XFile file, {required int length}) =>
      createClubMediaUploadSource(file, length: length);

  /// The byte count the reservation declared, known before any read.
  int get length;

  /// Starts the Storage upload and hands the running task back.
  ///
  /// Deliberately only the start: progress, the committed generation and the
  /// lost-acknowledgement recovery stay in `ClubChatService`, so the platform
  /// files differ in exactly one thing — whether the bytes are streamed from a
  /// file or handed over resident.
  Future<UploadTask> start(Reference reference, SettableMetadata metadata);
}
