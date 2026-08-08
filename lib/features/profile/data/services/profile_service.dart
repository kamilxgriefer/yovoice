import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/data/services/profile_image_rules.dart';

export 'package:yovoice/features/profile/data/services/profile_image_rules.dart'
    show
        ProfileImageException,
        ProfileImageFormat,
        ProfileImageKind,
        ProfileImageRules;

class ProfileService {
  ProfileService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
    ImagePicker? picker,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _picker = picker ?? ImagePicker();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final ImagePicker _picker;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');
    return user.uid;
  }

  DocumentReference<Map<String, dynamic>> get _document =>
      _firestore.collection('users').doc(_uid);

  Stream<UserProfile> watchCurrentProfile() {
    return _document.snapshots().map(UserProfile.fromFirestore);
  }

  Stream<UserProfile> watchProfile(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map(UserProfile.fromFirestore);
  }

  Future<void> ensureProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Only the very first call should write the counter fields below — this
    // runs on every Profile screen visit, and re-writing them each time was
    // stomping real progress (friendCount, followerCount, etc.) back to 0
    // on top of whatever friend_service/follow_service had already
    // incremented.
    final existing = await _document.get();
    if (existing.exists) return;

    final displayName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : (user.email?.split('@').first ?? 'YoVoice user');

    await _document.set({
      'uid': user.uid,
      'email': user.email ?? '',
      'displayName': displayName,
      'username': displayName,
      'photoUrl': user.photoURL,
      'bio': '',
      'country': '',
      'nativeLanguage': '',
      'spokenLanguages': <String>[],
      'learningLanguages': <String>[],
      'website': '',
      'accountType': AccountType.personal.name,
      'friendCount': 0,
      'followerCount': 0,
      'followingCount': 0,
      'roomCount': 0,
      'communityCount': 0,
      'voiceMinutes': 0,
      'messageCount': 0,
      'activeDays': 0,
      'momentCount': 0,
      'reactionCount': 0,
      'hostMinutes': 0,
      'unlockedTitleIds': <String>[],
      'profileUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateProfile({
    required String displayName,
    required String username,
    required String bio,
    required String country,
    required String nativeLanguage,
    required List<String> spokenLanguages,
    required List<String> learningLanguages,
    required String website,
    required AccountType accountType,
  }) async {
    final cleanDisplayName = displayName.trim();
    final cleanUsername = username.trim();

    if (cleanDisplayName.length < 2) {
      throw ArgumentError('Display name must contain at least 2 characters.');
    }
    if (cleanUsername.length < 2) {
      throw ArgumentError('Username must contain at least 2 characters.');
    }

    await _document.set({
      'displayName': cleanDisplayName,
      'username': cleanUsername,
      'bio': bio.trim(),
      'country': country.trim(),
      'nativeLanguage': nativeLanguage.trim(),
      'spokenLanguages': spokenLanguages,
      'learningLanguages': learningLanguages,
      'website': website.trim(),
      'accountType': accountType.name,
      'profileUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _auth.currentUser?.updateDisplayName(cleanDisplayName);
  }

  /// Opens the gallery and returns validated bytes for [kind], or null when
  /// the user cancels the picker.
  ///
  /// Nothing is uploaded here. Edit profile holds the result as a pending
  /// change and commits it on Save, so backing out of the screen cannot
  /// leave a changed remote avatar or an orphaned Storage object behind.
  ///
  /// Throws [ProfileImageException] with a user-facing message when the file
  /// is too large or is not a format every supported platform can decode.
  Future<PickedProfileImage?> pickProfileImage(ProfileImageKind kind) async {
    final rules = ProfileImageRules.of(kind);

    // maxWidth keeps a 50MP camera original from being read into memory at
    // full size on the way in. image_picker ignores it on Web, which is why
    // the byte-size check below is the real guard.
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: rules.maxOutputEdge.toDouble(),
    );

    if (image == null) return null;

    final bytes = await image.readAsBytes();
    rules.validateSource(bytes);

    return PickedProfileImage(
      kind: kind,
      bytes: bytes,
      format: ProfileImageRules.detectFormat(bytes)!,
    );
  }

  /// Uploads an already-validated image and persists its URL.
  Future<String> uploadProfileImage(PickedProfileImage image) {
    final kind = image.kind;
    final filename =
        '${kind.name}_${DateTime.now().millisecondsSinceEpoch}'
        '.${image.format.extension}';

    return _uploadBytes(
      bytes: image.bytes,
      path: 'users/$_uid/profile/$filename',
      contentType: image.format.mimeType,
      field: kind == ProfileImageKind.avatar ? 'photoUrl' : 'bannerUrl',
      updateAuthPhoto: kind == ProfileImageKind.avatar,
    );
  }

  /// Kept for callers that still want the old one-shot behaviour.
  Future<String?> pickAndUploadImage(ProfileImageKind kind) async {
    final picked = await pickProfileImage(kind);
    if (picked == null) return null;
    return uploadProfileImage(picked);
  }

  Future<String> _uploadBytes({
    required Uint8List bytes,
    required String path,
    required String contentType,
    required String field,
    required bool updateAuthPhoto,
  }) async {
    final reference = _storage.ref().child(path);
    final uploadTask = reference.putData(
      bytes,
      SettableMetadata(
        contentType: contentType,
        cacheControl: 'public,max-age=3600',
      ),
    );
    final snapshot = await uploadTask;

    if (snapshot.state != TaskState.success) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'upload-failed',
        message: 'The image upload did not finish successfully.',
      );
    }

    // Use the exact reference returned by the completed upload task. This
    // avoids asking Storage for a stale or differently-normalized path.
    final url = await snapshot.ref.getDownloadURL();

    await _document.set({
      field: url,
      'profileUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (updateAuthPhoto) {
      await _auth.currentUser?.updatePhotoURL(url);
    }

    return url;
  }
}

/// An image chosen by the user and validated, but not yet uploaded.
class PickedProfileImage {
  const PickedProfileImage({
    required this.kind,
    required this.bytes,
    required this.format,
  });

  final ProfileImageKind kind;
  final Uint8List bytes;
  final ProfileImageFormat format;
}
