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
  );

  final PremiumPlan plan;
  final String status;
  final DateTime? currentPeriodEnd;
  final bool isPremium;
  final bool creatorEnabled;
  final bool canCreateClubs;
  final bool premiumIdentityEnabled;
  final int maxOwnedClubs;

  /// The paid identity is the common prerequisite for every Premium
  /// destination. Feature-specific flags remain separate so future plans can
  /// vary, but no capability is exposed before the same trusted entitlement
  /// that grants the public Premium badge is active.
  bool get hasPremiumIdentity => isPremium && premiumIdentityEnabled;

  bool get canUseCreator => hasPremiumIdentity && creatorEnabled;

  bool get canUseClubs => hasPremiumIdentity && canCreateClubs;

  /// True while the subscription is in a billing-retry window — premium
  /// stays on, but Settings can surface "check your payment method".
  bool get inGracePeriod => status == 'grace';

  factory SubscriptionEntitlements.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) return free;

    final periodEnd = (data['currentPeriodEnd'] as Timestamp?)?.toDate();
    final status = data['status'] as String? ?? 'none';

    // Validity is recomputed locally rather than trusting the stored
    // isPremium flag alone: a lapsed subscription goes dark the moment
    // currentPeriodEnd passes, even before the daily server sweep runs.
    final active =
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
    );
  }
}
