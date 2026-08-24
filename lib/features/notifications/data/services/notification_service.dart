import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

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

  /// The global bell feed — bell-suppressed records (friend-DM push
  /// carriers) are excluded here, not in the UI, so every renderer gets
  /// the already-routed list.
  ///
  /// Two merged queries, because neither alone is safe:
  ///  - the VISIBLE query (`bellSuppressed == false`, composite-indexed)
  ///    guarantees suppressed carriers can never consume the pagination
  ///    window and crowd real bell events out of the feed — every new
  ///    notification writes the field explicitly;
  ///  - the BASE query (latest [limit], filtered client-side) keeps
  ///    LEGACY documents from before the field existed visible; a
  ///    Firestore `isNotEqualTo`/`isEqualTo` filter can never match a
  ///    missing field, so no single server query covers both.
  /// The union is deduped by id, suppressed records dropped, sorted
  /// newest-first, capped at [limit]. If the indexed query fails (e.g.
  /// index still deploying), the feed degrades gracefully to the base
  /// query — exactly the pre-hardening behavior, never a dead bell.
  Stream<List<AppNotification>> watchNotifications({int limit = 50}) {
    final own = _notificationsFor(_currentUser.uid);
    final base = own.orderBy('createdAt', descending: true).limit(limit);
    final visible = own
        .where('bellSuppressed', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    late StreamController<List<AppNotification>> controller;
    List<AppNotification>? fromBase;
    List<AppNotification>? fromVisible;
    var visibleFailed = false;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? baseSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? visibleSub;

    // serverTimestamp still pending resolves to null locally — sort those
    // first, like Firestore's own local ordering of fresh writes.
    DateTime effectiveCreatedAt(AppNotification notification) =>
        notification.createdAt ??
        DateTime.fromMillisecondsSinceEpoch(8640000000000000);

    void emit() {
      if (fromBase == null && fromVisible == null) return;
      if (fromBase != null && fromVisible == null && !visibleFailed) {
        // Wait for the indexed side once unless it errored — avoids a
        // brief first paint missing older visible events.
        return;
      }
      final byId = <String, AppNotification>{
        for (final notification in [...?fromBase, ...?fromVisible])
          if (!notification.bellSuppressed) notification.id: notification,
      };
      final list = byId.values.toList(
        growable: false,
      )..sort((a, b) => effectiveCreatedAt(b).compareTo(effectiveCreatedAt(a)));
      if (!controller.isClosed) {
        controller.add(list.take(limit).toList(growable: false));
      }
    }

    controller = StreamController<List<AppNotification>>(
      onListen: () {
        // Self-healing for LEGACY documents that predate the routing
        // field: normalize `bellSuppressed: false` onto them (all legacy
        // docs are bell events — suppression didn't exist yet), so the
        // indexed visible query covers them permanently and a carrier
        // flood can never bury an unread legacy event. One-shot over the
        // (unlimited) unread set + opportunistic for read docs passing
        // through the base window; idempotent, owner-only per rules.
        unawaited(_normalizeLegacyRouting(own));
        baseSub = base.snapshots().listen(
          (snapshot) {
            fromBase = snapshot.docs
                .map(AppNotification.fromFirestore)
                .toList(growable: false);
            emit();
            unawaited(_normalizeLegacyDocs(snapshot.docs));
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          },
        );
        visibleSub = visible.snapshots().listen(
          (snapshot) {
            fromVisible = snapshot.docs
                .map(AppNotification.fromFirestore)
                .toList(growable: false);
            emit();
          },
          onError: (Object _, StackTrace __) {
            // Degrade to the base query alone rather than killing the
            // bell — same coverage the feed had before this hardening.
            visibleFailed = true;
            fromVisible = null;
            emit();
          },
        );
      },
      onCancel: () async {
        await baseSub?.cancel();
        await visibleSub?.cancel();
      },
    );

    return controller.stream;
  }

  /// One-shot: stamps `bellSuppressed: false` onto the caller's own
  /// UNREAD documents that predate the routing field. Unread is the set
  /// that matters (those are the events a flood must never hide) and it
  /// is already an unlimited indexed query, so this costs one bounded
  /// fetch per feed subscription and converges to zero writes.
  Future<void> _normalizeLegacyRouting(
    CollectionReference<Map<String, dynamic>> own,
  ) async {
    try {
      final unread = await own.where('isRead', isEqualTo: false).get();
      await _normalizeLegacyDocs(unread.docs);
    } on FirebaseException catch (error) {
      // Best-effort — the merged feed still serves in-window legacy docs,
      // so this degrades rather than failing. Still worth naming: a
      // permanent denial here means legacy documents never gain the
      // routing field and stay dependent on the base query's window.
      debugPrint(
        'NotificationService: legacy routing backfill skipped '
        '(${error.code}).',
      );
    }
  }

  Future<void> _normalizeLegacyDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final missing = docs
        .where((doc) => !doc.data().containsKey('bellSuppressed'))
        .toList(growable: false);
    if (missing.isEmpty) return;
    try {
      final batch = _firestore.batch();
      for (final doc in missing) {
        batch.update(doc.reference, {'bellSuppressed': false});
      }
      await batch.commit();
    } on FirebaseException catch (error) {
      // Best-effort — rules may lag a deploy; the base window still
      // renders these docs meanwhile.
      debugPrint(
        'NotificationService: could not stamp bellSuppressed onto '
        '${missing.length} legacy document(s) (${error.code}).',
      );
    }
  }

  /// Unread count for the bell badge — same routing rule as the feed.
  /// The query is deliberately UNLIMITED (no `.limit()`), so the badge
  /// counts every unread bell-visible record, not "whatever survived an
  /// arbitrary window"; suppression is filtered client-side because
  /// legacy documents predate the field and would be invisible to any
  /// server-side equality filter.
  Stream<int> watchUnreadCount() {
    return _notificationsFor(_currentUser.uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => doc.data()['bellSuppressed'] != true)
              .length,
        );
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

  /// Legacy fixture helper retained while older routing tests are migrated.
  /// Production Firestore Rules deny every client notification create, so no
  /// shipping flow may call this method; authoritative writers live in Cloud
  /// Functions.
  /// [suppressBell] routes the record away from the bell feed/badge while
  /// still writing it — the document is what triggers the push
  /// (onNotificationCreated), so a friend DM keeps its push without
  /// duplicating the chat unread state into the bell.
  @Deprecated(
    'Client notification creates are unsupported; use a server writer.',
  )
  Future<void> notify({
    required String recipientId,
    required NotificationType type,
    String? targetId,
    String? targetLabel,
    String? dedupeKey,
    bool suppressBell = false,
  }) async {
    final actor = _currentUser;
    if (recipientId == actor.uid) return;
    if (type == NotificationType.system ||
        type == NotificationType.moderation ||
        type == NotificationType.achievementUnlocked ||
        type == NotificationType.liveStarted) {
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
      // ALWAYS written (true or false): the bell feed's indexed
      // `bellSuppressed == false` query can only see documents that
      // carry the field, and Firestore equality filters cannot match a
      // missing field. Any future Admin-SDK notification writer must set
      // it too (false unless it is a pure push carrier).
      'bellSuppressed': suppressBell,
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
    required String expectedUserId,
  }) async {
    if (_currentUser.uid != expectedUserId) {
      throw StateError('The push-token owner changed before registration.');
    }
    await _users.doc(expectedUserId).collection('fcmTokens').doc(token).set({
      'platform': platform,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> unregisterFcmToken(
    String token, {
    required String expectedUserId,
  }) async {
    if (_currentUser.uid != expectedUserId) {
      throw StateError('The push-token owner changed before cleanup.');
    }
    await _users
        .doc(expectedUserId)
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
