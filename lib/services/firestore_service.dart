import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _usersCollection {
    return _firestore.collection('users');
  }

  Future<void> createUserProfile(AppUser user) async {
    await _usersCollection
        .doc(user.uid)
        .set(user.toMap(), SetOptions(merge: true));
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
