import 'package:cloud_firestore/cloud_firestore.dart';

/// Subscription plans the product sells. Mirrors the values written by
/// functions/premium/entitlements.js.
enum PremiumPlan {
  monthly,
  yearly,
  none;

  static PremiumPlan fromValue(Object? value) {
    return switch (value) {
      'monthly' => PremiumPlan.monthly,
      'yearly' => PremiumPlan.yearly,
      _ => PremiumPlan.none,
    };
  }

  String get label => switch (this) {
    PremiumPlan.monthly => 'Monthly',
    PremiumPlan.yearly => 'Yearly',
    PremiumPlan.none => 'Free',
  };
}

/// The client-side view of `entitlements/{uid}` — the TRUSTED subscription
/// document written exclusively by Cloud Functions. Clients can read only
/// their own doc and can never write it (firestore.rules), so everything
/// here is display/gating state the user cannot forge for the backend:
/// the server re-derives the same answers in security rules
/// (hasActivePremium) for the operations that matter.
class SubscriptionEntitlements {
  const SubscriptionEntitlements({
    required this.plan,
    required this.status,
    required this.currentPeriodEnd,
    required this.isPremium,
    required this.creatorEnabled,
    required this.canCreateClubs,
    required this.premiumIdentityEnabled,
    required this.maxOwnedClubs,
    this.hasModeratorBenefits = false,
  });

  /// What every account has before any purchase: the full free product.
  static const SubscriptionEntitlements free = SubscriptionEntitlements(
    plan: PremiumPlan.none,
    status: 'none',
    currentPeriodEnd: null,
    isPremium: false,
    creatorEnabled: false,
    canCreateClubs: false,
    premiumIdentityEnabled: false,
    maxOwnedClubs: 0,
    hasModeratorBenefits: false,
  );

  final PremiumPlan plan;
  final String status;
  final DateTime? currentPeriodEnd;
  final bool isPremium;
  final bool creatorEnabled;
  final bool canCreateClubs;
  final bool premiumIdentityEnabled;
  final int maxOwnedClubs;

  /// Complimentary product-preview access for an active `moderator` or
  /// `superModerator` account.
  ///
  /// This is deliberately separate from [isPremium], [plan],
  /// [currentPeriodEnd] and every billing field. A moderator can exercise the
  /// Premium feature set for verification without the client claiming that a
  /// subscription exists, renews or was paid for.
  final bool hasModeratorBenefits;

  /// Paid access still requires the paid identity flag before any purchased
  /// capability is exposed. The independent moderator overlay is the only
  /// non-billing path through these effective-access getters.
  bool get hasPremiumIdentity =>
      hasModeratorBenefits || (isPremium && premiumIdentityEnabled);

  bool get canUseCreator =>
      hasModeratorBenefits ||
      (isPremium && premiumIdentityEnabled && creatorEnabled);

  bool get canUseClubs =>
      hasModeratorBenefits ||
      (isPremium && premiumIdentityEnabled && canCreateClubs);

  /// True while the subscription is in a billing-retry window — premium
  /// stays on, but Settings can surface "check your payment method".
  bool get inGracePeriod => status == 'grace';

  /// Applies the role-derived preview overlay without rewriting paid state.
  SubscriptionEntitlements withModeratorBenefits(bool enabled) {
    return SubscriptionEntitlements(
      plan: plan,
      status: status,
      currentPeriodEnd: currentPeriodEnd,
      isPremium: isPremium,
      creatorEnabled: creatorEnabled,
      canCreateClubs: canCreateClubs,
      premiumIdentityEnabled: premiumIdentityEnabled,
      maxOwnedClubs: maxOwnedClubs,
      hasModeratorBenefits: enabled,
    );
  }

  factory SubscriptionEntitlements.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) return free;

    final periodEnd = (data['currentPeriodEnd'] as Timestamp?)?.toDate();
    final status = data['status'] as String? ?? 'none';

    // Paid validity requires the canonical server flag AND the local time
    // boundary. A lapsed subscription therefore goes dark before the daily
    // sweep, while a malformed/partially written document cannot fabricate
    // paid access in the client when Rules and Functions would deny it.
    final active =
        data['isPremium'] == true &&
        const {'active', 'trialing', 'grace'}.contains(status) &&
        periodEnd != null &&
        periodEnd.isAfter(DateTime.now());

    return SubscriptionEntitlements(
      plan: PremiumPlan.fromValue(data['plan']),
      status: status,
      currentPeriodEnd: periodEnd,
      isPremium: active,
      creatorEnabled: active && (data['creatorEnabled'] as bool? ?? false),
      canCreateClubs: active && (data['canCreateClubs'] as bool? ?? false),
      premiumIdentityEnabled:
          active && (data['premiumIdentityEnabled'] as bool? ?? false),
      maxOwnedClubs: active ? (data['maxOwnedClubs'] as int? ?? 3) : 0,
      hasModeratorBenefits: false,
    );
  }
}
