import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:yovoice/shared/models/app_user.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _usersCollection {
    return _firestore.collection('users');
  }

  Future<void> createUserProfile(AppUser user) async {
    await _usersCollection.doc(user.uid).set({
      ...user.toMap(),

      // Friends feature
      'displayName': user.username,
      'username': user.username,
      'email': user.email.toLowerCase(),
      'photoUrl': null,
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

  Future<void> updatePhotoUrl({
    required String uid,
    required String? photoUrl,
  }) async {
    await _usersCollection.doc(uid).set({
      'photoUrl': photoUrl,
    }, SetOptions(merge: true));
  }

  Future<void> updateDisplayName({
    required String uid,
    required String displayName,
  }) async {
    await _usersCollection.doc(uid).set({
      'displayName': displayName.trim(),
      'username': displayName.trim(),
    }, SetOptions(merge: true));
  }

  Future<AppUser?> getUserProfile(String uid) async {
    final document = await _usersCollection.doc(uid).get();

    final data = document.data();

    if (!document.exists || data == null) {
      return null;
    }

    return AppUser.fromMap(data);
  }
}
