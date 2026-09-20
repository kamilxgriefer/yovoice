import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'club_media_upload_source.dart';

ClubMediaUploadSource createClubMediaUploadSource(
  XFile file, {
  required int length,
}) => _BytesClubMediaUploadSource(file, length: length);

/// The byte transport: the default wherever there is no `dart:io` file to
/// stream, and what the browser implementation delegates to.
///
/// `putData` needs the whole pick resident, so this is the cost the platform
/// split cannot remove — only confine. It is paid at upload time rather than at
/// pick time, and the image (8 MiB) and video (64 MiB) caps bound it, exactly
/// as they bound the direct-message store's own web path.
class _BytesClubMediaUploadSource implements ClubMediaUploadSource {
  _BytesClubMediaUploadSource(this._file, {required this.length});

  final XFile _file;

  @override
  final int length;

  @override
  Future<UploadTask> start(
    Reference reference,
    SettableMetadata metadata,
  ) async {
    final bytes = await _file.readAsBytes();
    if (bytes.lengthInBytes != length) {
      // The reservation declared `length`; sending a different number of bytes
      // would only be refused at finalize. Same refusal as the io path, for the
      // same reason.
      throw StateError('The selected media changed after it was chosen.');
    }
    return reference.putData(bytes, metadata);
  }
}
