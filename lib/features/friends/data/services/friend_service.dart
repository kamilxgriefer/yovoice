import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/friend_request.dart';
import '../models/friend_user.dart';

class FriendService {
  FriendService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  User get _currentUser {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('User is not signed in.');
    }

    return user;
  }

  Future<void> ensureUserDocument() async {
    final user = _currentUser;

    final document = _users.doc(user.uid);

    final snapshot = await document.get();

    final displayName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : user.email!.split('@').first;

    final data = {
      'displayName': displayName,
      'email': user.email?.toLowerCase(),
      'photoUrl': user.photoURL,
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
    };

    if (snapshot.exists) {
      await document.set(data, SetOptions(merge: true));
      return;
    }

    await document.set(data);
  }

  Stream<List<FriendUser>> watchFriends() {
    final user = _currentUser;

    return _users.doc(user.uid).collection('friends').snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) => FriendUser.fromMap(id: doc.id, data: doc.data()))
          .toList();
    });
  }

  Stream<List<FriendRequest>> watchFriendRequests() {
    final user = _currentUser;

    return _users
        .doc(user.uid)
        .collection('friendRequests')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map(FriendRequest.fromFirestore).toList();
        });
  }

  Future<List<FriendUser>> searchUsers(String query) async {
    final search = query.trim().toLowerCase();

    if (search.length < 2) {
      return [];
    }

    final snapshot = await _users.limit(100).get();

    return snapshot.docs.map(FriendUser.fromFirestore).where((user) {
      if (user.id == _currentUser.uid) {
        return false;
      }

      return user.displayName.toLowerCase().contains(search) ||
          user.email.toLowerCase().contains(search);
    }).toList();
  }

  Future<void> sendFriendRequest(FriendUser receiver) async {
    final sender = _currentUser;

    if (receiver.id == sender.uid) {
      throw StateError('You cannot add yourself.');
    }

    final senderDocument = await _users.doc(sender.uid).get();

    final senderData = senderDocument.data();

    final senderName =
        senderData?['displayName'] ??
        sender.displayName ??
        sender.email!.split('@').first;

    final requestDocument = _users
        .doc(receiver.id)
        .collection('friendRequests')
        .doc(sender.uid);

    final requestExists = await requestDocument.get();

    if (requestExists.exists) {
      throw StateError('Friend request already sent.');
    }

    await requestDocument.set({
      'senderId': sender.uid,
      'senderName': senderName,
      'senderEmail': sender.email,
      'senderPhotoUrl': sender.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> acceptFriendRequest(FriendRequest request) async {
    final me = _currentUser;

    final myDocument = await _users.doc(me.uid).get();

    final myData = myDocument.data();

    final myName =
        myData?['displayName'] ?? me.displayName ?? me.email!.split('@').first;

    final batch = _firestore.batch();

    batch.set(_users.doc(me.uid).collection('friends').doc(request.senderId), {
      'displayName': request.senderName,
      'email': request.senderEmail,
      'photoUrl': request.senderPhotoUrl,
      'isOnline': false,
    });

    batch.set(_users.doc(request.senderId).collection('friends').doc(me.uid), {
      'displayName': myName,
      'email': me.email,
      'photoUrl': me.photoURL,
      'isOnline': true,
    });

    batch.delete(
      _users.doc(me.uid).collection('friendRequests').doc(request.senderId),
    );

    await batch.commit();
  }

  Future<void> declineFriendRequest(String senderId) async {
    final me = _currentUser;

    await _users
        .doc(me.uid)
        .collection('friendRequests')
        .doc(senderId)
        .delete();
  }
}
