import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'club_media_upload_source.dart';

ClubMediaUploadSource createClubMediaUploadSource(
  XFile file, {
  required int length,
}) => _FileClubMediaUploadSource(file, length: length);

/// Streams the picked file straight to Storage.
///
/// Nothing but the picker handle and the declared length is retained: on every
/// `dart:io` platform the pick IS a file, so `putFile` lets the plugin read it
/// in chunks instead of the app materialising all of it — and then a second
/// copy of all of it — in the Dart heap.
class _FileClubMediaUploadSource implements ClubMediaUploadSource {
  _FileClubMediaUploadSource(this._file, {required this.length});

  final XFile _file;

  @override
  final int length;

  @override
  Future<UploadTask> start(
    Reference reference,
    SettableMetadata metadata,
  ) async {
    final file = File(_file.path);
    final int current;
    try {
      current = await file.length();
    } on FileSystemException {
      // The picker's temporary file can be evicted by the OS between the pick
      // and the upload — a real possibility now that the bytes are no longer
      // held. Refuse locally and keep the reservation unused; picking the same
      // photo again is the whole recovery. The scene maps this to its own
      // "could not be sent" copy, so no internal text reaches the user.
      throw StateError('The selected media is no longer on this device.');
    }
    if (current != length) {
      // The reservation already declared `length` and the server checks the
      // committed object against it, so this upload could only end in a
      // finalize refusal. Failing here makes it immediate and local.
      throw StateError('The selected media changed after it was chosen.');
    }
    return reference.putFile(file, metadata);
  }
}
