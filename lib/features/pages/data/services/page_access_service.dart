import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/likers/data/services/likers_access_service.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/shared/identity/public_identity.dart';

/// The signed-in account's own Page, as its owner may read it
/// (`pages/{uid}`, spec premium-pages §1.2 and §3.1): the state the Treści
/// entries need, and the editable fields Page settings shows.
class OwnPage {
  const OwnPage({
    required this.kind,
    required this.status,
    required this.ownerPaused,
    required this.suspended,
    this.category = '',
    this.description = '',
    this.business,
    this.rules,
    this.linkedServerId,
    this.displayName,
    this.lapsedAt,
    this.suspensionReason,
  });

  final PageKind? kind;

  /// `active` | `readOnly` | `hidden` as stored (§2.8).
  final String status;
  final bool ownerPaused;
  final bool suspended;

  final String category;
  final String description;

  /// Business Pages only.
  final PageBusinessInfo? business;

  /// Community Pages only.
  final String? rules;
  final String? linkedServerId;

  /// The server's mirror of the public display name.
  final String? displayName;

  /// When the Page lost its capability (readOnly / hidden, §2.8).
  final DateTime? lapsedAt;

  /// A moderator's reason key while [suspended].
  final String? suspensionReason;

  /// Publishing is possible only while the Page is active and running.
  bool get canPublish => status == 'active' && !ownerPaused && !suspended;

  @override
  bool operator ==(Object other) =>
      other is OwnPage &&
      other.kind == kind &&
      other.status == status &&
      other.ownerPaused == ownerPaused &&
      other.suspended == suspended &&
      other.category == category &&
      other.description == description &&
      other.business == business &&
      other.rules == rules &&
      other.linkedServerId == linkedServerId &&
      other.displayName == displayName &&
      other.lapsedAt == lapsedAt &&
      other.suspensionReason == suspensionReason;

  @override
  int get hashCode => Object.hash(
    kind,
    status,
    ownerPaused,
    suspended,
    category,
    description,
    business,
    rules,
    linkedServerId,
    displayName,
    lapsedAt,
    suspensionReason,
  );
}

/// What the Treści entries need to know about the viewer (UX only).
class PageAccessState {
  const PageAccessState({
    required this.resolved,
    required this.hasVipGrant,
    required this.ownPage,
  });

  static const unknown = PageAccessState(
    resolved: false,
    hasVipGrant: false,
    ownPage: null,
  );

  /// False until both halves answered once; every entry stays hidden.
  final bool resolved;

  /// A canonical owner-granted `vipGrants/{uid}` (D3: paid Premium does not
  /// open Pages while `PAGES_ALLOW_PAID_SOURCE` is false).
  final bool hasVipGrant;

  /// The account's own Page, or null when it has none.
  final OwnPage? ownPage;

  /// "Utwórz swoją stronę" entries (E2, E3, the phone card, the desktop
  /// panel row): a VIP without a Page.
  bool get canCreatePage => resolved && hasVipGrant && ownPage == null;

  @override
  bool operator ==(Object other) =>
      other is PageAccessState &&
      other.resolved == resolved &&
      other.hasVipGrant == hasVipGrant &&
      other.ownPage == ownPage;

  @override
  int get hashCode => Object.hash(resolved, hasVipGrant, ownPage);
}

/// The Pages UX pre-gate (spec §4.8 `PageAccessService`). It only decides
/// which entries to draw: every Pages callable re-derives access on the
/// server (§2.2), so a wrong answer here costs a refusal, never access.
///
/// Reads fail closed: an unreadable grant counts as no grant, an unreadable
/// `pages/{uid}` as "unknown", which hides the create entries too.
class PageAccessService {
  PageAccessService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    DateTime Function()? clock,
  }) : _firestoreOverride = firestore,
       _authOverride = auth,
       _clock = clock ?? DateTime.now;

  static final PageAccessService instance = PageAccessService();

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;
  final DateTime Function() _clock;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  String? get currentUserId {
    try {
      return _auth.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  static OwnPage? ownPageFrom(Map<String, dynamic>? data) {
    if (data == null) return null;
    final status = data['status'];
    String text(Object? value) => value is String ? value : '';
    String? optional(Object? value) =>
        value is String && value.trim().isNotEmpty ? value : null;
    final community = data['community'];
    final lapsedAt = data['lapsedAt'];
    return OwnPage(
      kind: PageKind.fromWire(data['kind']),
      status: status is String ? status : 'active',
      ownerPaused: data['ownerPaused'] == true,
      suspended: data['suspended'] == true,
      category: text(data['category']),
      description: text(data['description']),
      business: data['business'] is Map
          ? PageBusinessInfo.fromStored(data['business'])
          : null,
      rules: community is Map ? optional(community['rules']) : null,
      linkedServerId: community is Map
          ? optional(community['linkedServerId'])
          : null,
      displayName: optional(data['displayName']),
      lapsedAt: lapsedAt is Timestamp ? lapsedAt.toDate() : null,
      suspensionReason: optional(data['suspensionReason']),
    );
  }

  Stream<PageAccessState> watch() {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) {
      return Stream<PageAccessState>.value(
        const PageAccessState(
          resolved: true,
          hasVipGrant: false,
          ownPage: null,
        ),
      );
    }
    return Stream<PageAccessState>.multi((subscriber) {
      bool? grant;
      OwnPage? page;
      var pageResolved = false;
      var pageReadable = true;
      PageAccessState? last;
      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? grantSub;
      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? pageSub;

      void emit() {
        if (grant == null || !pageResolved) return;
        final next = pageReadable
            ? PageAccessState(
                resolved: true,
                hasVipGrant: grant!,
                ownPage: page,
              )
            : PageAccessState(
                resolved: false,
                hasVipGrant: grant!,
                ownPage: null,
              );
        if (next == last) return;
        last = next;
        subscriber.add(next);
      }

      try {
        grantSub = _firestore
            .collection('vipGrants')
            .doc(uid)
            .snapshots()
            .listen(
              (snapshot) {
                grant = LikersAccessService.canonicalLikersVipGrant(
                  snapshot.data(),
                  _clock(),
                );
                emit();
              },
              onError: (Object _, StackTrace _) {
                grant = false;
                emit();
              },
            );
        pageSub = _firestore
            .collection('pages')
            .doc(uid)
            .snapshots()
            .listen(
              (snapshot) {
                pageResolved = true;
                pageReadable = true;
                page = snapshot.exists ? ownPageFrom(snapshot.data()) : null;
                emit();
              },
              onError: (Object _, StackTrace _) {
                pageResolved = true;
                pageReadable = false;
                page = null;
                emit();
              },
            );
      } catch (_) {
        subscriber.add(PageAccessState.unknown);
      }
      subscriber.onCancel = () async {
        await grantSub?.cancel();
        await pageSub?.cancel();
      };
    });
  }
}
