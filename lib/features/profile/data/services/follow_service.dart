import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

import '../models/follow_user.dart';

class FollowService {
  FollowService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    NotificationService? notificationService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _notifications = notificationService ?? NotificationService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final NotificationService _notifications;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');
    return user.uid;
  }

  Stream<bool> watchIsFollowing(String targetUserId) {
    if (targetUserId == _uid) return Stream<bool>.value(false);
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('following')
        .doc(targetUserId)
        .snapshots()
        .map((document) => document.exists);
  }

  Stream<List<FollowUser>> watchFollowers(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('followers')
        .orderBy('followedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(FollowUser.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<List<FollowUser>> watchFollowing(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('following')
        .orderBy('followedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(FollowUser.fromFirestore)
              .toList(growable: false),
        );
  }

  Future<void> follow(String targetUserId) async {
    final currentUserId = _uid;
    if (targetUserId == currentUserId) {
      throw ArgumentError('You cannot follow yourself.');
    }

    final currentRef = _firestore.collection('users').doc(currentUserId);
    final targetRef = _firestore.collection('users').doc(targetUserId);
    final followingRef = currentRef.collection('following').doc(targetUserId);
    final followerRef = targetRef.collection('followers').doc(currentUserId);

    await _firestore.runTransaction((transaction) async {
      final currentSnapshot = await transaction.get(currentRef);
      final targetSnapshot = await transaction.get(targetRef);
      final existing = await transaction.get(followingRef);
      if (!currentSnapshot.exists || !targetSnapshot.exists) {
        throw StateError('User profile does not exist.');
      }
      if (existing.exists) return;

      final currentData = currentSnapshot.data() ?? const <String, dynamic>{};
      final targetData = targetSnapshot.data() ?? const <String, dynamic>{};
      final timestamp = FieldValue.serverTimestamp();

      transaction.set(
        followingRef,
        _snapshotData(targetUserId, targetData, timestamp),
      );
      transaction.set(
        followerRef,
        _snapshotData(currentUserId, currentData, timestamp),
      );
      transaction.update(currentRef, {
        'followingCount': FieldValue.increment(1),
      });
      transaction.update(targetRef, {'followerCount': FieldValue.increment(1)});
    });

    try {
      await _notifications.notify(
        recipientId: targetUserId,
        type: NotificationType.follow,
        dedupeKey: 'follow:$currentUserId',
      );
    } catch (_) {
      // Best-effort — the follow edge itself already succeeded above.
    }
  }

  Future<void> unfollow(String targetUserId) async {
    final currentUserId = _uid;
    if (targetUserId == currentUserId) return;

    final currentRef = _firestore.collection('users').doc(currentUserId);
    final targetRef = _firestore.collection('users').doc(targetUserId);
    final followingRef = currentRef.collection('following').doc(targetUserId);
    final followerRef = targetRef.collection('followers').doc(currentUserId);

    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(followingRef);
      if (!existing.exists) return;

      final currentSnapshot = await transaction.get(currentRef);
      final targetSnapshot = await transaction.get(targetRef);
      final currentCount =
          (currentSnapshot.data()?['followingCount'] as num?)?.toInt() ?? 0;
      final targetCount =
          (targetSnapshot.data()?['followerCount'] as num?)?.toInt() ?? 0;

      transaction.delete(followingRef);
      transaction.delete(followerRef);
      transaction.update(currentRef, {
        'followingCount': currentCount > 0 ? currentCount - 1 : 0,
      });
      transaction.update(targetRef, {
        'followerCount': targetCount > 0 ? targetCount - 1 : 0,
      });
    });
  }

  Map<String, dynamic> _snapshotData(
    String uid,
    Map<String, dynamic> data,
    FieldValue timestamp,
  ) {
    return {
      'uid': uid,
      'displayName': data['displayName'] ?? data['username'] ?? 'YO Voice user',
      'username': data['username'] ?? '',
      'photoUrl': data['photoUrl'],
      'followedAt': timestamp,
    };
  }
}
