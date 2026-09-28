import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';

/// The client's UX pre-gate for "See who liked" (spec §5.0, §5.5).
///
/// It decides only which sheet to open first: the list, or the Premium
/// upsell. It is never authority: every list callable re-derives access from
/// the caller's own server documents (`canSeeLikers`, spec §2) and answers
/// `likersAccessRequired` when this mirror is wrong, which the list turns
/// into the upsell.
///
/// Access = paid Premium identity or the moderator preview (the
/// [SubscriptionEntitlements.hasPremiumIdentity] /
/// [SubscriptionEntitlements.hasModeratorBenefits] read the app already
/// trusts) OR a canonical owner-granted `vipGrants/{uid}` document, checked
/// with [canonicalLikersVipGrant], a port of the server's fail-closed rule.
/// Any read failure counts as "no access" for that half.
class LikersAccessService {
  LikersAccessService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    EntitlementService? entitlements,
    DateTime Function()? clock,
  }) : _firestoreOverride = firestore,
       _authOverride = auth,
       _entitlementsOverride = entitlements,
       _clock = clock ?? DateTime.now;

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;
  final EntitlementService? _entitlementsOverride;
  final DateTime Function() _clock;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  EntitlementService get _entitlements =>
      _entitlementsOverride ??
      EntitlementService(firestore: _firestore, auth: _auth);

  /// The grant sources the server accepts (`LIKERS_VIP_GRANT_SOURCES`).
  static const Set<String> vipGrantSources = <String>{
    'testerProgram',
    'legacyRoleMigration',
    'admin',
  };
  static const Set<String> _requiredGrantKeys = <String>{
    'expiresAt',
    'revoked',
    'source',
  };
  static const Set<String> _optionalGrantKeys = <String>{
    'active',
    'grantedAt',
    'grantedBy',
  };

  /// Dart port of the server's `canonicalLikersVipGrant` (spec §2): exact
  /// keys, an allowlisted source, `revoked == false`, an optional `active`
  /// that must be `true`, and a Timestamp-or-null expiry. It fails CLOSED
  /// where the badge helper `grantIsActive` fails open (`{}`,
  /// `{revoked: "true"}`, a string expiry).
  static bool canonicalLikersVipGrant(Object? grant, DateTime now) {
    if (grant is! Map) return false;
    final keys = grant.keys.toSet();
    if (!keys.every((key) => key is String)) return false;
    if (!keys.containsAll(_requiredGrantKeys)) return false;
    if (!keys.every(
      (key) =>
          _requiredGrantKeys.contains(key) || _optionalGrantKeys.contains(key),
    )) {
      return false;
    }
    if (!vipGrantSources.contains(grant['source'])) return false;
    if (grant['revoked'] != false) return false;
    if (keys.contains('active') && grant['active'] != true) return false;
    if (keys.contains('grantedBy')) {
      final grantedBy = grant['grantedBy'];
      if (grantedBy is! String || grantedBy.isEmpty || grantedBy.length > 200) {
        return false;
      }
    }
    if (keys.contains('grantedAt') && grant['grantedAt'] is! Timestamp) {
      return false;
    }
    final expiresAt = grant['expiresAt'];
    if (expiresAt == null) return true;
    if (expiresAt is! Timestamp) return false;
    return expiresAt.toDate().isAfter(now);
  }

  String? get _uid {
    try {
      return _auth.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  DocumentReference<Map<String, dynamic>> _grantRef(String uid) =>
      _firestore.collection('vipGrants').doc(uid);

  static bool _entitled(SubscriptionEntitlements value) =>
      value.hasPremiumIdentity || value.hasModeratorBenefits;

  /// The live answer: emits once both halves have resolved, then on every
  /// change. Signed out is a single `false`.
  Stream<bool> watchCanSeeLikers() {
    final uid = _uid;
    if (uid == null) return Stream<bool>.value(false);
    return Stream<bool>.multi((subscriber) {
      bool? entitled;
      Object? grant;
      var grantResolved = false;
      bool? last;
      StreamSubscription<SubscriptionEntitlements>? entitlementSub;
      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? grantSub;

      void emit() {
        final paid = entitled;
        if (paid == null || !grantResolved) return;
        final value = paid || canonicalLikersVipGrant(grant, _clock());
        if (value == last) return;
        last = value;
        subscriber.add(value);
      }

      try {
        entitlementSub = _entitlements.watchCurrentEntitlements().listen(
          (value) {
            entitled = _entitled(value);
            emit();
          },
          onError: (Object _, StackTrace _) {
            entitled = false;
            emit();
          },
        );
      } catch (_) {
        entitled = false;
      }
      try {
        grantSub = _grantRef(uid).snapshots().listen(
          (snapshot) {
            grant = snapshot.data();
            grantResolved = true;
            emit();
          },
          onError: (Object _, StackTrace _) {
            grant = null;
            grantResolved = true;
            emit();
          },
        );
      } catch (_) {
        grant = null;
        grantResolved = true;
      }
      emit();
      subscriber.onCancel = () async {
        await entitlementSub?.cancel();
        await grantSub?.cancel();
      };
    });
  }

  /// A fresh one-shot read of both halves (no cached stream), used to
  /// re-check a `false` before showing the upsell (spec §5.5 step 2).
  Future<bool> canSeeLikers() async {
    final uid = _uid;
    if (uid == null) return false;
    final entitledFuture = () async {
      try {
        return _entitled(await _entitlements.currentEntitlements());
      } catch (_) {
        return false;
      }
    }();
    final grantFuture = () async {
      try {
        final snapshot = await _grantRef(uid).get();
        return canonicalLikersVipGrant(snapshot.data(), _clock());
      } catch (_) {
        return false;
      }
    }();
    final entitled = await entitledFuture;
    final vip = await grantFuture;
    return entitled || vip;
  }
}
