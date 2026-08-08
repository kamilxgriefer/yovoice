import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

import '../models/friend_request.dart';
import '../models/friend_user.dart';

enum FriendRelationshipStatus {
  none,
  friends,
  requestSent,
  requestReceived,
  blocked,
}

class FriendService {
  FriendService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    NotificationService? notificationService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _notifications = notificationService ?? NotificationService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final NotificationService _notifications;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  User get _currentUser {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');
    return user;
  }

  Future<void> ensureUserDocument() async {
    final user = _currentUser;
    final email = user.email?.trim() ?? '';
    final displayName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : email.isNotEmpty
        ? email.split('@').first
        : 'YoVoice user';

    await _users.doc(user.uid).set({
      'uid': user.uid,
      'displayName': displayName,
      'email': email.toLowerCase(),
      'photoUrl': user.photoURL,
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Watches the signed-in user's friends.
  ///
  /// The returned stream supports **multiple simultaneous listeners** and
  /// replays the most recent list to anyone who subscribes late.
  ///
  /// Both matter: `MessagesScreen` creates this stream once and hands the
  /// same instance to `_FriendsRow` *and* to `NewMessageSheet`. While this
  /// returned a plain single-subscription controller, opening the New
  /// message sheet threw `Bad state: Stream has already been listened to`
  /// inside the sheet's StreamBuilder, and Flutter swapped that whole
  /// subtree for a bare [ErrorWidget] — which renders as an unlabelled
  /// light-grey rectangle in release web builds. Replay matters because the
  /// second listener joins after the first value was already emitted, and
  /// without it the sheet would sit on a spinner until a friend document
  /// happened to change.
  Stream<List<FriendUser>> watchFriends() {
    final currentUserId = _currentUser.uid;
    final controller = StreamController<List<FriendUser>>.broadcast();
    final subscriptions =
        <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
    final friends = <String, FriendUser>{};
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? rootSubscription;
    var closed = false;
    List<FriendUser>? latest;

    void emit() {
      if (closed || controller.isClosed) return;
      final result = friends.values.toList(growable: false)
        ..sort((a, b) {
          if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
          return a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          );
        });
      latest = result;
      controller.add(result);
    }

    Future<void> start() async {
      // A broadcast controller calls onListen again if every listener
      // cancels and a new one arrives later, so reset the teardown flag.
      closed = false;
      try {
        await ensureUserDocument();
        rootSubscription = _users
            .doc(currentUserId)
            .collection('friends')
            .snapshots()
            .listen((snapshot) {
              final ids = snapshot.docs.map((doc) => doc.id).toSet();

              for (final removed
                  in subscriptions.keys
                      .where((id) => !ids.contains(id))
                      .toList(growable: false)) {
                subscriptions.remove(removed)?.cancel();
                friends.remove(removed);
              }

              for (final id in ids) {
                if (subscriptions.containsKey(id)) continue;
                subscriptions[id] = _users.doc(id).snapshots().listen((
                  document,
                ) {
                  if (!document.exists || document.data() == null) {
                    friends.remove(id);
                  } else {
                    friends[id] = FriendUser.fromFirestore(document);
                  }
                  emit();
                }, onError: controller.addError);
              }
              emit();
            }, onError: controller.addError);
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      }
    }

    controller.onListen = start;
    controller.onCancel = () async {
      closed = true;
      await rootSubscription?.cancel();
      rootSubscription = null;
      for (final subscription in subscriptions.values) {
        await subscription.cancel();
      }
      subscriptions.clear();
    };

    // Stream.multi gives every listener its own subscription, which lets us
    // hand the cached list straight to late subscribers before forwarding
    // live updates.
    return Stream<List<FriendUser>>.multi((subscriber) {
      final cached = latest;
      if (cached != null) {
        subscriber.add(cached);
      }
      final subscription = controller.stream.listen(
        subscriber.add,
        onError: subscriber.addError,
        onDone: subscriber.close,
      );
      subscriber.onCancel = subscription.cancel;
    });
  }

  Stream<List<FriendRequest>> watchFriendRequests() {
    return _users
        .doc(_currentUser.uid)
        .collection('friendRequests')
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map(FriendRequest.fromFirestore)
              .toList(growable: false);
          requests.sort((a, b) {
            if (a.createdAt == null && b.createdAt == null) return 0;
            if (a.createdAt == null) return 1;
            if (b.createdAt == null) return -1;
            return b.createdAt!.compareTo(a.createdAt!);
          });
          return requests;
        });
  }

  Stream<int> watchPendingFriendRequestCount() =>
      watchFriendRequests().map((items) => items.length).distinct();

  Future<List<FriendUser>> searchUsers(String query) async {
    final search = query.trim().toLowerCase();
    if (search.length < 2) return const [];

    final snapshot = await _users.limit(100).get();
    final blockedIds =
        (await _users.doc(_currentUser.uid).collection('blocked').get()).docs
            .map((doc) => doc.id)
            .toSet();
    final results =
        snapshot.docs
            .map(FriendUser.fromFirestore)
            .where((user) {
              if (user.id == _currentUser.uid) return false;
              if (blockedIds.contains(user.id)) return false;
              return user.searchableDisplayName.contains(search) ||
                  user.searchableEmail.contains(search);
            })
            .toList(growable: false)
          ..sort(
            (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
          );
    return results;
  }

  Future<FriendRelationshipStatus> getRelationshipStatus(
    String otherUserId,
  ) async {
    final me = _currentUser.uid;
    final results = await Future.wait([
      _users.doc(me).collection('friends').doc(otherUserId).get(),
      _users.doc(otherUserId).collection('friendRequests').doc(me).get(),
      _users.doc(me).collection('friendRequests').doc(otherUserId).get(),
      _users.doc(me).collection('blocked').doc(otherUserId).get(),
    ]);
    if (results[3].exists) return FriendRelationshipStatus.blocked;
    if (results[0].exists) return FriendRelationshipStatus.friends;
    if (results[1].exists) return FriendRelationshipStatus.requestSent;
    if (results[2].exists) return FriendRelationshipStatus.requestReceived;
    return FriendRelationshipStatus.none;
  }

  Future<void> sendFriendRequest(FriendUser receiver) async {
    final sender = _currentUser;
    if (receiver.id == sender.uid) throw StateError('You cannot add yourself.');
    if (await isBlocked(receiver.id)) {
      throw StateError('You have blocked this user.');
    }
    await ensureUserDocument();

    final senderDoc = await _users.doc(sender.uid).get();
    final senderData = senderDoc.data() ?? const <String, dynamic>{};
    final senderEmail =
        (senderData['email'] as String?)?.trim() ?? sender.email?.trim() ?? '';
    final senderName = _displayName(senderData, senderEmail);
    final senderPhoto = _nullable(senderData['photoUrl']) ?? sender.photoURL;

    final myFriend = _users
        .doc(sender.uid)
        .collection('friends')
        .doc(receiver.id);
    final theirFriend = _users
        .doc(receiver.id)
        .collection('friends')
        .doc(sender.uid);
    final outgoing = _users
        .doc(receiver.id)
        .collection('friendRequests')
        .doc(sender.uid);
    final incoming = _users
        .doc(sender.uid)
        .collection('friendRequests')
        .doc(receiver.id);

    final mutualAccept = await _firestore.runTransaction<bool>((tx) async {
      final snapshots = await Future.wait([
        tx.get(myFriend),
        tx.get(outgoing),
        tx.get(incoming),
        tx.get(_users.doc(receiver.id)),
      ]);
      if (snapshots[0].exists) throw StateError('You are already friends.');
      if (snapshots[1].exists) {
        throw StateError('Friend request already sent.');
      }
      final receiverDoc = snapshots[3];
      if (!receiverDoc.exists || receiverDoc.data() == null) {
        throw StateError('This user no longer exists.');
      }

      if (snapshots[2].exists) {
        final now = FieldValue.serverTimestamp();
        tx.set(myFriend, {'userId': receiver.id, 'createdAt': now});
        tx.set(theirFriend, {'userId': sender.uid, 'createdAt': now});
        tx.delete(incoming);
        tx.delete(
          _users
              .doc(receiver.id)
              .collection('sentFriendRequests')
              .doc(sender.uid),
        );
        tx.update(_users.doc(sender.uid), {
          'friendCount': FieldValue.increment(1),
        });
        tx.update(_users.doc(receiver.id), {
          'friendCount': FieldValue.increment(1),
        });
        return true;
      }

      tx.set(outgoing, {
        'senderId': sender.uid,
        'senderName': senderName,
        'senderEmail': senderEmail.toLowerCase(),
        'senderPhotoUrl': senderPhoto,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(
        _users
            .doc(sender.uid)
            .collection('sentFriendRequests')
            .doc(receiver.id),
        {'receiverId': receiver.id, 'createdAt': FieldValue.serverTimestamp()},
      );
      return false;
    });

    try {
      await _notifications.notify(
        recipientId: receiver.id,
        type: mutualAccept
            ? NotificationType.friendAccepted
            : NotificationType.friendRequest,
        dedupeKey: mutualAccept ? null : 'friendRequest:${sender.uid}',
      );
    } catch (_) {
      // Best-effort: the friend request/friendship itself already
      // succeeded above, a notification failure shouldn't undo that.
    }
  }

  Future<void> cancelFriendRequest(String receiverId) async {
    final me = _currentUser.uid;
    final batch = _firestore.batch();
    batch.delete(_users.doc(receiverId).collection('friendRequests').doc(me));
    batch.delete(
      _users.doc(me).collection('sentFriendRequests').doc(receiverId),
    );
    await batch.commit();
  }

  Future<void> acceptFriendRequest(FriendRequest request) async {
    final me = _currentUser;
    await ensureUserDocument();

    final myDoc = _users.doc(me.uid);
    final senderDoc = _users.doc(request.senderId);
    final requestRef = myDoc.collection('friendRequests').doc(request.senderId);
    final myFriend = myDoc.collection('friends').doc(request.senderId);
    final senderFriend = senderDoc.collection('friends').doc(me.uid);

    await _firestore.runTransaction((tx) async {
      final snapshots = await Future.wait([
        tx.get(requestRef),
        tx.get(myDoc),
        tx.get(senderDoc),
        tx.get(myFriend),
      ]);
      if (!snapshots[0].exists) {
        throw StateError('This friend request no longer exists.');
      }
      if (!snapshots[3].exists) {
        final now = FieldValue.serverTimestamp();
        tx.set(myFriend, {'userId': request.senderId, 'createdAt': now});
        tx.set(senderFriend, {'userId': me.uid, 'createdAt': now});
        tx.update(myDoc, {'friendCount': FieldValue.increment(1)});
        tx.update(senderDoc, {'friendCount': FieldValue.increment(1)});
      }
      tx.delete(requestRef);
      tx.delete(senderDoc.collection('sentFriendRequests').doc(me.uid));
    });

    try {
      await _notifications.notify(
        recipientId: request.senderId,
        type: NotificationType.friendAccepted,
      );
    } catch (_) {}
  }

  Future<void> declineFriendRequest(String senderId) async {
    final me = _currentUser.uid;
    final batch = _firestore.batch();
    batch.delete(_users.doc(me).collection('friendRequests').doc(senderId));
    batch.delete(_users.doc(senderId).collection('sentFriendRequests').doc(me));
    await batch.commit();
  }

  Future<void> removeFriend(String friendId) async {
    final me = _currentUser.uid;
    final myDoc = _users.doc(me);
    final friendDoc = _users.doc(friendId);
    final myFriend = myDoc.collection('friends').doc(friendId);
    final theirFriend = friendDoc.collection('friends').doc(me);

    await _firestore.runTransaction((tx) async {
      final existing = await tx.get(myFriend);
      if (!existing.exists) return;
      tx.delete(myFriend);
      tx.delete(theirFriend);
      tx.update(myDoc, {'friendCount': FieldValue.increment(-1)});
      tx.update(friendDoc, {'friendCount': FieldValue.increment(-1)});
    });
  }

  Stream<List<FriendUser>> watchBlockedUsers() {
    return _users
        .doc(_currentUser.uid)
        .collection('blocked')
        .snapshots()
        .asyncMap((snapshot) async {
          if (snapshot.docs.isEmpty) return const <FriendUser>[];
          final documents = await Future.wait(
            snapshot.docs.map((doc) => _users.doc(doc.id).get()),
          );
          return documents
              .where((doc) => doc.exists && doc.data() != null)
              .map(FriendUser.fromFirestore)
              .toList(growable: false)
            ..sort(
              (a, b) => a.displayName.toLowerCase().compareTo(
                b.displayName.toLowerCase(),
              ),
            );
        });
  }

  Future<bool> isBlocked(String userId) async {
    final doc = await _users
        .doc(_currentUser.uid)
        .collection('blocked')
        .doc(userId)
        .get();
    return doc.exists;
  }

  /// Blocks [targetUserId]: severs any friendship, pending friend request
  /// (either direction), and follow relationship (either direction) with
  /// them, then records the block. Firestore rules use the resulting
  /// `blocked` doc to reject any new friend request/follow/conversation
  /// between the two users in either direction going forward.
  Future<void> blockUser(String targetUserId) async {
    final me = _currentUser.uid;
    if (targetUserId == me) throw StateError('You cannot block yourself.');

    final myDoc = _users.doc(me);
    final targetDoc = _users.doc(targetUserId);
    final myFriend = myDoc.collection('friends').doc(targetUserId);
    final theirFriend = targetDoc.collection('friends').doc(me);
    final myFollowing = myDoc.collection('following').doc(targetUserId);
    final theirFollower = targetDoc.collection('followers').doc(me);
    final theirFollowing = targetDoc.collection('following').doc(me);
    final myFollower = myDoc.collection('followers').doc(targetUserId);

    await _firestore.runTransaction((tx) async {
      final snapshots = await Future.wait([
        tx.get(myFriend),
        tx.get(myFollowing),
        tx.get(theirFollowing),
      ]);
      final wasFriend = snapshots[0].exists;
      final iWasFollowingThem = snapshots[1].exists;
      final theyWereFollowingMe = snapshots[2].exists;

      if (wasFriend) {
        tx.delete(myFriend);
        tx.delete(theirFriend);
        tx.update(myDoc, {'friendCount': FieldValue.increment(-1)});
        tx.update(targetDoc, {'friendCount': FieldValue.increment(-1)});
      }

      // Pending requests in either direction — deleting a doc that doesn't
      // exist is a harmless no-op, so no existence check needed first.
      tx.delete(targetDoc.collection('friendRequests').doc(me));
      tx.delete(myDoc.collection('friendRequests').doc(targetUserId));
      tx.delete(myDoc.collection('sentFriendRequests').doc(targetUserId));
      tx.delete(targetDoc.collection('sentFriendRequests').doc(me));

      if (iWasFollowingThem) {
        tx.delete(myFollowing);
        tx.delete(theirFollower);
        tx.update(myDoc, {'followingCount': FieldValue.increment(-1)});
        tx.update(targetDoc, {'followerCount': FieldValue.increment(-1)});
      }
      if (theyWereFollowingMe) {
        tx.delete(theirFollowing);
        tx.delete(myFollower);
        tx.update(targetDoc, {'followingCount': FieldValue.increment(-1)});
        tx.update(myDoc, {'followerCount': FieldValue.increment(-1)});
      }

      tx.set(myDoc.collection('blocked').doc(targetUserId), {
        'userId': targetUserId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> unblockUser(String targetUserId) async {
    await _users
        .doc(_currentUser.uid)
        .collection('blocked')
        .doc(targetUserId)
        .delete();
  }

  String _displayName(Map<String, dynamic> data, String fallbackEmail) {
    for (final key in ['displayName', 'username', 'name']) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return fallbackEmail.isNotEmpty
        ? fallbackEmail.split('@').first
        : 'YoVoice user';
  }

  String? _nullable(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }
}
