import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/settings/data/models/message_privacy.dart';

class MessagePrivacyService {
  MessagePrivacyService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');
    return user.uid;
  }

  Stream<MessagePrivacyOption> watchCurrent() {
    return _firestore
        .collection('users')
        .doc(_uid)
        .snapshots()
        .map(
          (snapshot) => MessagePrivacyOption.fromStoredValue(
            snapshot.data()?['messagePrivacy'],
          ),
        );
  }

  Future<void> setCurrent(MessagePrivacyOption option) {
    return _firestore.collection('users').doc(_uid).update({
      'messagePrivacy': option.storageValue,
    });
  }
}
