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
    final reference = _usersCollection.doc(user.uid);

    // Firebase Auth publishes its signed-in user before signInWithPopup()
    // returns. AuthGate/presence can therefore create a partial users/{uid}
    // document while social sign-in is still provisioning the same profile.
    // A blind merge then becomes an UPDATE and `createdAt` is correctly
    // rejected by Rules (it is create-only), which used to bounce every new
    // Google account back to Login. Keep the decision and write in one
    // transaction so a concurrent first write is retried with the narrow
    // update shape.
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);

      if (!snapshot.exists) {
        transaction.set(reference, {
          ...user.toMap(),
          'displayName': user.username,
          'username': user.username,
          'email': user.email.toLowerCase(),
          'isOnline': true,
          'lastSeen': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      final existing = snapshot.data() ?? const <String, dynamic>{};
      final missingIdentity = <String, Object?>{};

      if (existing['uid'] is! String || (existing['uid'] as String).isEmpty) {
        missingIdentity['uid'] = user.uid;
      }
      if (existing['email'] is! String ||
          (existing['email'] as String).trim().isEmpty) {
        missingIdentity['email'] = user.email.toLowerCase();
      }
      if (existing['displayName'] is! String ||
          (existing['displayName'] as String).trim().isEmpty) {
        missingIdentity['displayName'] = user.username;
      }
      if (existing['username'] is! String ||
          (existing['username'] as String).trim().isEmpty) {
        missingIdentity['username'] = user.username;
      }
      if (existing['isOnline'] is! bool) {
        missingIdentity['isOnline'] = true;
      }
      if (existing['lastSeen'] is! Timestamp) {
        missingIdentity['lastSeen'] = FieldValue.serverTimestamp();
      }

      if (missingIdentity.isNotEmpty) {
        transaction.update(reference, missingIdentity);
      }
    });
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
