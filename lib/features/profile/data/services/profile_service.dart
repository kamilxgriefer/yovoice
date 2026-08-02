import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/profile/data/models/user_profile.dart';

enum ProfileImageKind { avatar, banner }

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

  Future<String?> pickAndUploadImage(ProfileImageKind kind) async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: kind == ProfileImageKind.avatar ? 1200 : 2200,
    );

    if (image == null) return null;

    final bytes = await image.readAsBytes();
    final extension = image.name.split('.').last.toLowerCase();
    final safeExtension = {'jpg', 'jpeg', 'png', 'webp'}.contains(extension)
        ? extension
        : 'jpg';
    final filename =
        '${kind.name}_${DateTime.now().millisecondsSinceEpoch}.$safeExtension';

    return _uploadBytes(
      bytes: bytes,
      path: 'users/$_uid/profile/$filename',
      contentType: _contentType(safeExtension),
      field: kind == ProfileImageKind.avatar ? 'photoUrl' : 'bannerUrl',
      updateAuthPhoto: kind == ProfileImageKind.avatar,
    );
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

  String _contentType(String extension) {
    return switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }
}
