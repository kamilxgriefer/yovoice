import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// The caller's own viewed-state for Voice Moments.
///
/// Lives at `users/{uid}/momentViews/{momentId}` with the exact shape
/// `{ viewedAt: <server time> }` — owner-only by rules, never readable by
/// anyone else, and NEVER aggregated: there is no global view counter
/// anywhere, because no server-side counter exists and printing one would
/// be fabricated data. This service answers exactly two questions:
/// "which Moments has *this account* heard" and "record that this account
/// just started hearing one".
class MomentViewsService {
  MomentViewsService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> _views(String uid) =>
      _firestore.collection('users').doc(uid).collection('momentViews');

  /// ONE listener over the caller's whole `momentViews` subcollection,
  /// emitting the set of viewed Moment ids. The strip derives per-chain
  /// unviewed state from this single set rather than opening a listener
  /// per chain.
  ///
  /// Signed out: a single empty set, so every chain simply reads as
  /// unviewed rather than the surface throwing.
  Stream<Set<String>> watchViewedMomentIds() {
    final uid = _uid;
    if (uid.isEmpty) return Stream.value(const <String>{});
    return _views(
      uid,
    ).snapshots().map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());
  }

  /// Records that playback of [momentId] started, with the exact
  /// rules-pinned shape — one key, server time. `set` covers both the
  /// first view (create) and a re-listen (update refreshes `viewedAt`).
  ///
  /// Fire-and-forget by design: a failed viewed-write must never
  /// interrupt playback, so callers may ignore the returned future.
  Future<void> markViewed(String momentId) async {
    final uid = _uid;
    if (uid.isEmpty || momentId.isEmpty) return;
    await _views(uid).doc(momentId).set(<String, dynamic>{
      'viewedAt': FieldValue.serverTimestamp(),
    });
  }
}
