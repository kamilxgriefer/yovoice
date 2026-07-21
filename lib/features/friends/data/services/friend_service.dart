import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/friend_request.dart';
import '../models/friend_user.dart';

enum FriendRelationshipStatus {
  none,
  friends,
  requestSent,
  requestReceived,
}

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
    final email = user.email?.trim() ?? '';
    final displayName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : email.isNotEmpty
        ? email.split('@').first
        : 'YoVoice user';

    final data = <String, dynamic>{
      'displayName': displayName,
      'email': email.toLowerCase(),
      'photoUrl': user.photoURL,
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
    };

    await document.set(data, SetOptions(merge: snapshot.exists));
  }

  Stream<List<FriendUser>> watchFriends() {
    final currentUserId = _currentUser.uid;
    final controller = StreamController<List<FriendUser>>();
    final userSubscriptions = <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
    final friendsById = <String, FriendUser>{};
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? friendshipSubscription;
    var isClosed = false;

    void emit() {
      if (isClosed || controller.isClosed) {
        return;
      }

      final friends = friendsById.values.toList(growable: false)
        ..sort((first, second) {
          if (first.isOnline != second.isOnline) {
            return first.isOnline ? -1 : 1;
          }

          return first.displayName.toLowerCase().compareTo(
            second.displayName.toLowerCase(),
          );
        });

      controller.add(friends);
    }

    Future<void> start() async {
      try {
        await ensureUserDocument();

        friendshipSubscription = _users
            .doc(currentUserId)
            .collection('friends')
            .snapshots()
            .listen(
              (snapshot) {
                final friendIds = snapshot.docs.map((document) => document.id).toSet();
                final removedIds = userSubscriptions.keys
                    .where((friendId) => !friendIds.contains(friendId))
                    .toList(growable: false);

                for (final friendId in removedIds) {
                  userSubscriptions.remove(friendId)?.cancel();
                  friendsById.remove(friendId);
                }

                for (final friendId in friendIds) {
                  if (userSubscriptions.containsKey(friendId)) {
                    continue;
                  }

                  userSubscriptions[friendId] = _users.doc(friendId).snapshots().listen(
                    (userDocument) {
                      if (!userDocument.exists || userDocument.data() == null) {
                        friendsById.remove(friendId);
                        emit();
                        return;
                      }

                      friendsById[friendId] = FriendUser.fromFirestore(userDocument);
                      emit();
                    },
                    onError: controller.addError,
                  );
                }

                emit();
              },
              onError: controller.addError,
            );
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      }
    }

    controller.onListen = start;
    controller.onCancel = () async {
      isClosed = true;
      await friendshipSubscription?.cancel();
      for (final subscription in userSubscriptions.values) {
        await subscription.cancel();
      }
      userSubscriptions.clear();
    };

    return controller.stream;
  }

  Stream<List<FriendRequest>> watchFriendRequests() {
    final currentUserId = _currentUser.uid;

    return _users
        .doc(currentUserId)
        .collection('friendRequests')
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map(FriendRequest.fromFirestore)
              .toList(growable: false);

          requests.sort((first, second) {
            final firstDate = first.createdAt;
            final secondDate = second.createdAt;

            if (firstDate == null && secondDate == null) {
              return 0;
            }
            if (firstDate == null) {
              return 1;
            }
            if (secondDate == null) {
              return -1;
            }

            return secondDate.compareTo(firstDate);
          });

          return requests;
        });
  }

  Stream<int> watchPendingFriendRequestCount() {
    return watchFriendRequests().map((requests) => requests.length).distinct();
  }

  Future<List<FriendUser>> searchUsers(String query) async {
    final search = query.trim().toLowerCase();

    if (search.length < 2) {
      return [];
    }

    final snapshot = await _users.limit(100).get();

    final results = snapshot.docs.map(FriendUser.fromFirestore).where((user) {
      if (user.id == _currentUser.uid) {
        return false;
      }

      return user.searchableDisplayName.contains(search) ||
          user.searchableEmail.contains(search);
    }).toList(growable: false);

    results.sort(
      (first, second) => first.displayName.toLowerCase().compareTo(
        second.displayName.toLowerCase(),
      ),
    );

    return results;
  }

  Future<FriendRelationshipStatus> getRelationshipStatus(
    String otherUserId,
  ) async {
    final currentUserId = _currentUser.uid;

    final results = await Future.wait([
      _users.doc(currentUserId).collection('friends').doc(otherUserId).get(),
      _users
          .doc(otherUserId)
          .collection('friendRequests')
          .doc(currentUserId)
          .get(),
      _users
          .doc(currentUserId)
          .collection('friendRequests')
          .doc(otherUserId)
          .get(),
    ]);

    if (results[0].exists) {
      return FriendRelationshipStatus.friends;
    }
    if (results[1].exists) {
      return FriendRelationshipStatus.requestSent;
    }
    if (results[2].exists) {
      return FriendRelationshipStatus.requestReceived;
    }

    return FriendRelationshipStatus.none;
  }

  Future<void> sendFriendRequest(FriendUser receiver) async {
    final sender = _currentUser;

    if (receiver.id == sender.uid) {
      throw StateError('You cannot add yourself.');
    }

    await ensureUserDocument();

    final senderDocument = await _users.doc(sender.uid).get();
    final senderData = senderDocument.data() ?? const <String, dynamic>{};
    final senderEmail = (senderData['email'] as String?)?.trim().isNotEmpty == true
        ? (senderData['email'] as String).trim()
        : sender.email?.trim() ?? '';
    final senderName = _displayNameFromData(
      senderData,
      fallbackEmail: senderEmail,
    );
    final senderPhotoUrl = _nullableString(senderData['photoUrl']) ?? sender.photoURL;

    final myFriendReference = _users
        .doc(sender.uid)
        .collection('friends')
        .doc(receiver.id);
    final receiverFriendReference = _users
        .doc(receiver.id)
        .collection('friends')
        .doc(sender.uid);
    final outgoingRequestReference = _users
        .doc(receiver.id)
        .collection('friendRequests')
        .doc(sender.uid);
    final reverseRequestReference = _users
        .doc(sender.uid)
        .collection('friendRequests')
        .doc(receiver.id);

    await _firestore.runTransaction((transaction) async {
      final snapshots = await Future.wait([
        transaction.get(myFriendReference),
        transaction.get(outgoingRequestReference),
        transaction.get(reverseRequestReference),
        transaction.get(_users.doc(receiver.id)),
      ]);

      if (snapshots[0].exists) {
        throw StateError('You are already friends.');
      }

      if (snapshots[1].exists) {
        throw StateError('Friend request already sent.');
      }

      final receiverDocument = snapshots[3];
      if (!receiverDocument.exists || receiverDocument.data() == null) {
        throw StateError('This user no longer exists.');
      }

      if (snapshots[2].exists) {
        final receiverData = receiverDocument.data()!;
        final receiverEmail = (receiverData['email'] as String?)?.trim() ?? receiver.email;
        final receiverName = _displayNameFromData(
          receiverData,
          fallbackEmail: receiverEmail,
        );
        final receiverPhotoUrl = _nullableString(receiverData['photoUrl']);
        final now = FieldValue.serverTimestamp();

        transaction.set(myFriendReference, <String, dynamic>{
          'userId': receiver.id,
          'createdAt': now,
        });
        transaction.set(receiverFriendReference, <String, dynamic>{
          'userId': sender.uid,
          'createdAt': now,
        });
        transaction.delete(reverseRequestReference);
        transaction.delete(
          _users
              .doc(receiver.id)
              .collection('sentFriendRequests')
              .doc(sender.uid),
        );

        transaction.set(
          _users.doc(sender.uid).collection('friendCache').doc(receiver.id),
          <String, dynamic>{
            'displayName': receiverName,
            'email': receiverEmail,
            'photoUrl': receiverPhotoUrl,
          },
          SetOptions(merge: true),
        );
        transaction.set(
          _users.doc(receiver.id).collection('friendCache').doc(sender.uid),
          <String, dynamic>{
            'displayName': senderName,
            'email': senderEmail,
            'photoUrl': senderPhotoUrl,
          },
          SetOptions(merge: true),
        );
        return;
      }

      transaction.set(outgoingRequestReference, <String, dynamic>{
        'senderId': sender.uid,
        'senderName': senderName,
        'senderEmail': senderEmail.toLowerCase(),
        'senderPhotoUrl': senderPhotoUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.set(
        _users
            .doc(sender.uid)
            .collection('sentFriendRequests')
            .doc(receiver.id),
        <String, dynamic>{
          'receiverId': receiver.id,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
    });
  }

  Future<void> acceptFriendRequest(FriendRequest request) async {
    final me = _currentUser;

    await ensureUserDocument();

    final myDocumentReference = _users.doc(me.uid);
    final senderDocumentReference = _users.doc(request.senderId);
    final requestReference = myDocumentReference
        .collection('friendRequests')
        .doc(request.senderId);
    final myFriendReference = myDocumentReference
        .collection('friends')
        .doc(request.senderId);
    final senderFriendReference = senderDocumentReference
        .collection('friends')
        .doc(me.uid);

    await _firestore.runTransaction((transaction) async {
      final snapshots = await Future.wait([
        transaction.get(requestReference),
        transaction.get(myDocumentReference),
        transaction.get(senderDocumentReference),
      ]);

      if (!snapshots[0].exists) {
        throw StateError('This friend request no longer exists.');
      }

      final myData = snapshots[1].data() ?? const <String, dynamic>{};
      final senderData = snapshots[2].data() ?? const <String, dynamic>{};
      final myEmail = (myData['email'] as String?)?.trim() ?? me.email?.trim() ?? '';
      final myName = _displayNameFromData(myData, fallbackEmail: myEmail);
      final myPhotoUrl = _nullableString(myData['photoUrl']) ?? me.photoURL;
      final senderEmail = (senderData['email'] as String?)?.trim().isNotEmpty == true
          ? (senderData['email'] as String).trim()
          : request.senderEmail;
      final senderName = _displayNameFromData(
        senderData,
        fallbackEmail: senderEmail,
        fallbackName: request.senderName,
      );
      final senderPhotoUrl = _nullableString(senderData['photoUrl']) ?? request.senderPhotoUrl;
      final now = FieldValue.serverTimestamp();

      transaction.set(myFriendReference, <String, dynamic>{
        'userId': request.senderId,
        'createdAt': now,
      });
      transaction.set(senderFriendReference, <String, dynamic>{
        'userId': me.uid,
        'createdAt': now,
      });
      transaction.delete(requestReference);
      transaction.delete(
        senderDocumentReference
            .collection('sentFriendRequests')
            .doc(me.uid),
      );

      transaction.set(
        myDocumentReference.collection('friendCache').doc(request.senderId),
        <String, dynamic>{
          'displayName': senderName,
          'email': senderEmail,
          'photoUrl': senderPhotoUrl,
        },
        SetOptions(merge: true),
      );
      transaction.set(
        senderDocumentReference.collection('friendCache').doc(me.uid),
        <String, dynamic>{
          'displayName': myName,
          'email': myEmail,
          'photoUrl': myPhotoUrl,
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> cancelFriendRequest(String receiverId) async {
    final currentUserId = _currentUser.uid;
    final batch = _firestore.batch();

    batch.delete(
      _users
          .doc(receiverId)
          .collection('friendRequests')
          .doc(currentUserId),
    );
    batch.delete(
      _users
          .doc(currentUserId)
          .collection('sentFriendRequests')
          .doc(receiverId),
    );

    await batch.commit();
  }

  Future<void> declineFriendRequest(String senderId) async {
    final currentUserId = _currentUser.uid;
    final batch = _firestore.batch();

    batch.delete(
      _users
          .doc(currentUserId)
          .collection('friendRequests')
          .doc(senderId),
    );
    batch.delete(
      _users
          .doc(senderId)
          .collection('sentFriendRequests')
          .doc(currentUserId),
    );

    await batch.commit();
  }

  Future<void> removeFriend(String friendId) async {
    final currentUserId = _currentUser.uid;
    final batch = _firestore.batch();

    batch.delete(
      _users.doc(currentUserId).collection('friends').doc(friendId),
    );
    batch.delete(
      _users.doc(friendId).collection('friends').doc(currentUserId),
    );
    batch.delete(
      _users.doc(currentUserId).collection('friendCache').doc(friendId),
    );
    batch.delete(
      _users.doc(friendId).collection('friendCache').doc(currentUserId),
    );

    await batch.commit();
  }

  static String _displayNameFromData(
    Map<String, dynamic> data, {
    required String fallbackEmail,
    String? fallbackName,
  }) {
    final possibleNames = <Object?>[
      data['displayName'],
      data['username'],
      data['name'],
      fallbackName,
    ];

    for (final value in possibleNames) {
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    if (fallbackEmail.trim().isNotEmpty) {
      return fallbackEmail.trim().split('@').first;
    }

    return 'YoVoice user';
  }

  static String? _nullableString(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }

    return value.trim();
  }
}
