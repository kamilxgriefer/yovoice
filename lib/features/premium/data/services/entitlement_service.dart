import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';

/// Read-side of the premium entitlement system.
///
/// Watches the signed-in user's `entitlements/{uid}` document (written
/// only by Cloud Functions) through one shared, replayed stream — the
/// same pattern ProfileService.watchCurrentProfile uses, for the same
/// reason: every gate and badge in the app must observe the same value.
/// A missing document emits [SubscriptionEntitlements.free].
///
/// This service has NO write methods on purpose. Entitlements change via
/// verified purchases (functions/premium/entitlements.js) — never from
/// the client.
class EntitlementService {
  EntitlementService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static final Map<String, Stream<SubscriptionEntitlements>> _shared = {};

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');
    return user.uid;
  }

  Stream<SubscriptionEntitlements> watchCurrentEntitlements() {
    final uid = _uid;
    return _shared.putIfAbsent(uid, () => _build(uid));
  }

  Future<SubscriptionEntitlements> currentEntitlements() async {
    final snapshot = await _firestore
        .collection('entitlements')
        .doc(_uid)
        .get();
    return SubscriptionEntitlements.fromFirestore(snapshot);
  }

  Stream<SubscriptionEntitlements> _build(String uid) {
    final controller = StreamController<SubscriptionEntitlements>.broadcast();
    SubscriptionEntitlements? latest;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? subscription;

    controller.onListen = () {
      subscription = _firestore
          .collection('entitlements')
          .doc(uid)
          .snapshots()
          .listen(
            (snapshot) {
              final value = SubscriptionEntitlements.fromFirestore(snapshot);
              latest = value;
              if (!controller.isClosed) controller.add(value);
            },
            onError: (Object error, StackTrace stackTrace) {
              // Fail closed: an unreadable entitlements doc means FREE,
              // never premium.
              latest = SubscriptionEntitlements.free;
              if (!controller.isClosed) {
                controller.add(SubscriptionEntitlements.free);
              }
            },
          );
    };
    controller.onCancel = () async {
      await subscription?.cancel();
      subscription = null;
    };

    return Stream<SubscriptionEntitlements>.multi((subscriber) {
      final cached = latest;
      if (cached != null) subscriber.add(cached);
      final inner = controller.stream.listen(
        subscriber.add,
        onError: subscriber.addError,
        onDone: subscriber.close,
      );
      subscriber.onCancel = inner.cancel;
    });
  }

  /// Clears cached streams on sign-out so the next account cannot inherit
  /// the previous account's entitlement snapshot.
  static void resetCache() {
    _shared.clear();
  }
}
