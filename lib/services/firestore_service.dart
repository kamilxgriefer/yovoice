import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:yovoice/shared/models/app_user.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _usersCollection {
    return _firestore.collection('users');
  }

  /// Seeds the registration-time identity fields of `users/{uid}`.
  ///
  /// Deliberately does NOT write `photoUrl` — not even null. This field is
  /// owned exclusively by ProfileService, and merging `photoUrl: null`
  /// here was the fourth occurrence of the clobber-the-avatar bug class
  /// (PresenceService, friend_service's ensureUserDocument and Home's
  /// Auth-fallback read were the first three; see docs/Bugs.md). For a
  /// Google account, the avatar is seeded once by
  /// ProfileService.ensureProfile(), which runs at sign-in and only when
  /// the profile has none.
  Future<void> createUserProfile(AppUser user) async {
    await _usersCollection.doc(user.uid).set({
      ...user.toMap(),

      // Friends feature
      'displayName': user.username,
      'username': user.username,
      'email': user.email.toLowerCase(),
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updatePresence({
    required String uid,
    required bool isOnline,
  }) async {
    await _usersCollection.doc(uid).set({
      'isOnline': isOnline,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // updatePhotoUrl/updateDisplayName used to live here — parallel write
  // paths into fields ProfileService owns. Removed; nothing called them.

  Future<AppUser?> getUserProfile(String uid) async {
    final document = await _usersCollection.doc(uid).get();

    final data = document.data();

    if (!document.exists || data == null) {
      return null;
    }

    return AppUser.fromMap(data);
  }
}
