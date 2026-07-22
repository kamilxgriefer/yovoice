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

  Future<XFile?> pickImage() {
    return _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 86,
      maxWidth: 1600,
      maxHeight: 1600,
    );
  }

  Future<String> uploadRoomImage({
    required String roomId,
    required XFile file,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to upload a room image.');
    }

    final Uint8List bytes = await file.readAsBytes();
    final extension = file.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';

    final reference = _storage.ref(
      'room_images/$roomId/${user.uid}_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );

    final metadata = SettableMetadata(
      contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
      cacheControl: 'public,max-age=86400',
    );

    await reference.putData(bytes, metadata);
    return reference.getDownloadURL();
  }
}
