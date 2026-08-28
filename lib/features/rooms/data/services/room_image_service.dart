import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class RoomImageService {
  RoomImageService({
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    ImagePicker? picker,
  }) : _storage = storage ?? FirebaseStorage.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _picker = picker ?? ImagePicker();

  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  final ImagePicker _picker;

  static const maxRoomCoverBytes = 8 * 1024 * 1024;

  /// Selects a room-cover source at twice the final output width so portrait
  /// photos still have enough horizontal detail for a 21:9 crop. The source
  /// byte guard in RoomCoverEditor remains the platform-independent limit.
  Future<XFile?> pickRoomCoverSource() {
    return _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 3200,
      maxHeight: 3200,
    );
  }

  /// Uploads the confirmed crop using a platform-independent contract.
  ///
  /// `XFile.fromData().name` is not stable across every implementation of
  /// cross_file, so deriving Storage metadata from that name could label the
  /// same in-memory crop differently on mobile and web. The crop renderer
  /// always emits JPEG; accept its bytes directly and pin both extension and
  /// MIME type here.
  Future<String> uploadRoomCover({
    required String roomId,
    required Uint8List bytes,
  }) {
    if (bytes.isEmpty || bytes.lengthInBytes > maxRoomCoverBytes) {
      throw StateError('The processed room cover must be smaller than 8 MB.');
    }
    final isJpeg =
        bytes.lengthInBytes >= 4 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF &&
        bytes[bytes.lengthInBytes - 2] == 0xFF &&
        bytes[bytes.lengthInBytes - 1] == 0xD9;
    if (!isJpeg) {
      throw StateError('The processed room cover must be a JPEG image.');
    }
    return _uploadBytes(
      roomId: roomId,
      bytes: bytes,
      extension: 'jpg',
      contentType: 'image/jpeg',
    );
  }

  Future<String> _uploadBytes({
    required String roomId,
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to upload a room image.');
    }

    final reference = _storage.ref(
      'room_images/$roomId/${user.uid}_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );

    final metadata = SettableMetadata(
      contentType: contentType,
      cacheControl: 'public,max-age=86400',
    );

    await reference.putData(bytes, metadata);
    return reference.getDownloadURL();
  }

  /// Best-effort removal of a replaced/abandoned cover. Only a Storage
  /// reference whose bucket and exact path belong to this room is eligible;
  /// inherited Club Lounge art and arbitrary external URLs stay untouched.
  Future<void> deleteManagedRoomCover({
    required String roomId,
    required String? url,
  }) async {
    final normalized = url?.trim();
    if (normalized == null || normalized.isEmpty) return;
    Reference reference;
    try {
      reference = _storage.refFromURL(normalized);
    } catch (_) {
      return;
    }
    final segments = reference.fullPath.split('/');
    final isExactRoomObject =
        reference.bucket == _storage.bucket &&
        segments.length == 3 &&
        segments[0] == 'room_images' &&
        segments[1] == roomId &&
        segments[2].isNotEmpty;
    if (!isExactRoomObject) return;
    try {
      await reference.delete();
    } catch (_) {
      // Cleanup must never roll back a cover pointer that already committed.
    }
  }
}
