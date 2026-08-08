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

    if (dedupeKey != null) {
      final existing = await _notificationsFor(recipientId)
          .where('dedupeKey', isEqualTo: dedupeKey)
          .where('isRead', isEqualTo: false)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) return;
    }

    final actorDoc = await _users.doc(actor.uid).get();
    final actorData = actorDoc.data() ?? const <String, dynamic>{};
    final actorName =
        (actorData['displayName'] as String?)?.trim().isNotEmpty == true
        ? (actorData['displayName'] as String).trim()
        : actor.displayName?.trim().isNotEmpty == true
        ? actor.displayName!.trim()
        : 'YoVoice user';
    final actorPhotoUrl = (actorData['photoUrl'] as String?) ?? actor.photoURL;

    await _notificationsFor(recipientId).add({
      'type': type.name,
      'actorId': actor.uid,
      'actorName': actorName,
      'actorPhotoUrl': actorPhotoUrl,
      'targetId': targetId,
      'targetLabel': targetLabel,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      'dedupeKey': dedupeKey,
    });
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
