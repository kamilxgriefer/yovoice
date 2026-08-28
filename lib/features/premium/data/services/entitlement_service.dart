import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

/// Read-side of the premium entitlement system.
///
/// Watches the signed-in user's `entitlements/{uid}` document (written only
/// by Cloud Functions) and their private `users/{uid}` role mirror through one
/// shared, replayed stream. Paid state and role-derived moderator benefits are
/// resolved independently: a failure reading one source can never fabricate
/// it or erase valid access proven by the other source.
///
/// A missing entitlement document emits the free billing state. Only an
/// active account whose exact server-written role is `moderator` or
/// `superModerator` receives the separate preview overlay.
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
    final uid = _uid;
    final paidFuture = _readPaidEntitlements(uid);
    final moderatorBenefitsFuture = _readModeratorBenefits(uid);
    final paid = await paidFuture;
    final moderatorBenefits = await moderatorBenefitsFuture;
    return paid.withModeratorBenefits(moderatorBenefits);
  }

  Stream<SubscriptionEntitlements> _build(String uid) {
    final controller = StreamController<SubscriptionEntitlements>.broadcast();
    SubscriptionEntitlements? latest;
    var paid = SubscriptionEntitlements.free;
    var moderatorBenefits = false;
    var paidResolved = false;
    var moderatorBenefitsResolved = false;
    bool? lastAuthoritativeModeratorBenefits;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
    entitlementSubscription;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
    profileSubscription;

    void emitIfResolved() {
      if (!paidResolved || !moderatorBenefitsResolved) return;
      final value = paid.withModeratorBenefits(moderatorBenefits);
      latest = value;
      if (!controller.isClosed) controller.add(value);
    }

    void acceptPaid(SubscriptionEntitlements value) {
      paid = value;
      paidResolved = true;
      emitIfResolved();
    }

    void acceptModeratorBenefits(bool value, {required bool authoritative}) {
      final changed = !moderatorBenefitsResolved || moderatorBenefits != value;
      moderatorBenefits = value;
      moderatorBenefitsResolved = true;

      if (authoritative) {
        final previous = lastAuthoritativeModeratorBenefits;
        lastAuthoritativeModeratorBenefits = value;
        if ((previous == null && value) ||
            (previous != null && previous != value)) {
          // The badge projection is rewritten server-side from this same role
          // source. Drop a session-stale own badge so it re-resolves after a
          // promotion or demotion instead of waiting for app restart.
          PublicIdentityRepository.instance.invalidate(uid);
        }
      }

      if (changed) emitIfResolved();
    }

    controller.onListen = () {
      try {
        entitlementSubscription = _firestore
            .collection('entitlements')
            .doc(uid)
            .snapshots()
            .listen(
              (snapshot) =>
                  acceptPaid(SubscriptionEntitlements.fromFirestore(snapshot)),
              onError: (Object error, StackTrace stackTrace) {
                // Billing fails closed without erasing a separately proven
                // moderator benefit.
                acceptPaid(SubscriptionEntitlements.free);
              },
            );
      } catch (_) {
        acceptPaid(SubscriptionEntitlements.free);
      }

      try {
        profileSubscription = _firestore
            .collection('users')
            .doc(uid)
            .snapshots()
            .listen(
              (snapshot) => acceptModeratorBenefits(
                _hasModeratorBenefits(snapshot.data()),
                authoritative: true,
              ),
              onError: (Object error, StackTrace stackTrace) {
                // Role access fails closed without erasing valid paid access.
                acceptModeratorBenefits(false, authoritative: false);
              },
            );
      } catch (_) {
        acceptModeratorBenefits(false, authoritative: false);
      }
    };
    controller.onCancel = () async {
      await entitlementSubscription?.cancel();
      await profileSubscription?.cancel();
      entitlementSubscription = null;
      profileSubscription = null;
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

  Future<SubscriptionEntitlements> _readPaidEntitlements(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('entitlements')
          .doc(uid)
          .get();
      return SubscriptionEntitlements.fromFirestore(snapshot);
    } catch (_) {
      return SubscriptionEntitlements.free;
    }
  }

  Future<bool> _readModeratorBenefits(String uid) async {
    try {
      final snapshot = await _firestore.collection('users').doc(uid).get();
      return _hasModeratorBenefits(snapshot.data());
    } catch (_) {
      return false;
    }
  }

  static bool _hasModeratorBenefits(Map<String, dynamic>? profile) {
    if (profile == null ||
        profile['banned'] == true ||
        profile['disabled'] == true ||
        profile['deleted'] == true ||
        profile['status'] == 'deleted') {
      return false;
    }
    return const {'moderator', 'superModerator'}.contains(profile['role']);
  }

  /// Clears cached streams on sign-out so the next account cannot inherit
  /// the previous account's entitlement snapshot.
  static void resetCache() {
    _shared.clear();
  }
}
