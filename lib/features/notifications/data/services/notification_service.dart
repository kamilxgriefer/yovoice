import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/notifications/data/models/app_notification.dart';

class NotificationService {
  NotificationService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  User get _currentUser {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');
    return user;
  }

  CollectionReference<Map<String, dynamic>> _notificationsFor(String userId) =>
      _users.doc(userId).collection('notifications');

  Stream<List<AppNotification>> watchNotifications({int limit = 50}) {
    return _notificationsFor(_currentUser.uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(AppNotification.fromFirestore)
              .toList(growable: false),
        );
  }

  Stream<int> watchUnreadCount() {
    return _notificationsFor(_currentUser.uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  Future<void> markAsRead(String notificationId) async {
    await _notificationsFor(_currentUser.uid).doc(notificationId).update({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAllAsRead() async {
    final unread = await _notificationsFor(
      _currentUser.uid,
    ).where('isRead', isEqualTo: false).limit(400).get();
    if (unread.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> deleteNotification(String notificationId) async {
    await _notificationsFor(_currentUser.uid).doc(notificationId).delete();
  }

  /// Writes a notification into [recipientId]'s subcollection. Only
  /// structured fields are ever sent — no free-text body — because
  /// firestore.rules authorizes this purely on actorId == caller and type
  /// being one of a known set; there is deliberately nothing here a
  /// malicious actor could use to write deceptive content into someone
  /// else's notification feed.
  Future<void> notify({
    required String recipientId,
    required NotificationType type,
    String? targetId,
    String? targetLabel,
    String? dedupeKey,
  }) async {
    final actor = _currentUser;
    if (recipientId == actor.uid) return;
    if (type == NotificationType.system ||
        type == NotificationType.moderation ||
        type == NotificationType.achievementUnlocked) {
      throw ArgumentError.value(
        type,
        'type',
        'Server-only notification type; must be created via a Cloud Function.',
      );
    }

    final actorDoc = await _users.doc(actor.uid).get();
    final actorData = actorDoc.data() ?? const <String, dynamic>{};
    final actorName =
        (actorData['displayName'] as String?)?.trim().isNotEmpty == true
        ? (actorData['displayName'] as String).trim()
        : actor.displayName?.trim().isNotEmpty == true
        ? actor.displayName!.trim()
        : 'YO Voice user';
    final actorPhotoUrl = (actorData['photoUrl'] as String?) ?? actor.photoURL;

    final payload = {
      'type': type.name,
      'actorId': actor.uid,
      'actorName': actorName,
      'actorPhotoUrl': actorPhotoUrl,
      'targetId': targetId,
      'targetLabel': targetLabel,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      'dedupeKey': dedupeKey,
    };

    // Dedupe via DETERMINISTIC DOC ID, not a query: rules only let a user
    // read their OWN notification feed, so the old approach — querying the
    // RECIPIENT's subcollection for an existing dedupeKey — was
    // permission-denied every time it ran, which silently killed any
    // notify() call that passed a dedupeKey. With a fixed id, a repeat of
    // the same event is an UPDATE to an existing doc, which the rules
    // reject for non-owners — exactly the dedupe behaviour we want, with
    // zero extra reads.
    if (dedupeKey != null) {
      try {
        await _notificationsFor(recipientId).doc(dedupeKey).set(payload);
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied') {
          // Duplicate: the deterministic doc already exists and the write
          // became a (forbidden) cross-user update. Intended outcome.
          return;
        }
        rethrow;
      }
      return;
    }

    await _notificationsFor(recipientId).add(payload);
  }

  /// Marks the caller's own unread notifications matching [type] +
  /// [actorId] as read — used when the underlying event is resolved (e.g.
  /// accepting a friend request retires the request notification) so
  /// stale entries don't stay actionable.
  Future<void> markMatchingRead({
    required NotificationType type,
    required String actorId,
  }) async {
    final own = _notificationsFor(_currentUser.uid);
    final matches = await own
        .where('type', isEqualTo: type.name)
        .where('actorId', isEqualTo: actorId)
        .where('isRead', isEqualTo: false)
        .get();
    if (matches.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in matches.docs) {
      batch.update(doc.reference, {
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  // --- FCM device tokens ---
  //
  // Stored as a subcollection (not an array field) so multiple devices per
  // account work cleanly and a single device can be removed on sign-out
  // without needing an exact-match arrayRemove.

  Future<void> registerFcmToken(
    String token, {
    required String platform,
  }) async {
    await _users.doc(_currentUser.uid).collection('fcmTokens').doc(token).set({
      'platform': platform,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> unregisterFcmToken(String token) async {
    await _users
        .doc(_currentUser.uid)
        .collection('fcmTokens')
        .doc(token)
        .delete();
  }

  // --- Preferences ---

  Stream<Map<String, bool>> watchPreferences() {
    return _users.doc(_currentUser.uid).snapshots().map((doc) {
      final raw = doc.data()?['notificationPreferences'];
      if (raw is Map) {
        return raw.map((key, value) => MapEntry('$key', value == true));
      }
      return const <String, bool>{};
    });
  }

  Future<void> setPreference(NotificationType type, bool enabled) async {
    await _users.doc(_currentUser.uid).update({
      'notificationPreferences.${type.name}': enabled,
    });
  }
}
