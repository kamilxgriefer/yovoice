import 'package:flutter/material.dart';

import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_upsell_sheet.dart';

enum PremiumFeature { creatorAccount, creatorStudio, clubs }

extension PremiumFeatureAccess on PremiumFeature {
  bool isEnabledBy(SubscriptionEntitlements entitlements) => switch (this) {
    PremiumFeature.creatorAccount ||
    PremiumFeature.creatorStudio => entitlements.canUseCreator,
    PremiumFeature.clubs => entitlements.canUseClubs,
  };

  PremiumUpsellContext get upsellContext => switch (this) {
    PremiumFeature.creatorAccount => PremiumUpsellContext.creator,
    PremiumFeature.creatorStudio => PremiumUpsellContext.creatorStudio,
    PremiumFeature.clubs => PremiumUpsellContext.clubs,
  };

  String get label => switch (this) {
    PremiumFeature.creatorAccount => 'Creator',
    PremiumFeature.creatorStudio => 'Creator Studio',
    PremiumFeature.clubs => 'Clubs',
  };

  String get lockedDescription => switch (this) {
    PremiumFeature.creatorAccount =>
      'A Premium identity is required before this profile can become a Creator.',
    PremiumFeature.creatorStudio =>
      'Activate Premium to use your creator dashboard and publishing tools.',
    PremiumFeature.clubs =>
      'Activate Premium to open the Clubs hub and build communities.',
  };
}

/// UX-layer premium gates — the single place every "is this allowed, and
/// what does the user see if not" decision lives, so the two Create Club
/// entry points (Clubs tab, Creator Studio) and any future ones behave
/// identically.
///
/// These gates are user experience, not security: firestore.rules
/// enforces the same premium requirement on the actual club create and
/// accountType write, so a modified client that skips this file changes
/// nothing.
class PremiumGates {
  PremiumGates._();

  /// Gates a complete Premium destination or account capability. The trusted
  /// entitlement grants both the feature and the public Premium identity in
  /// one server batch; a cosmetic VIP grant alone never unlocks paid tools.
  static Future<bool> ensureFeatureAccess(
    BuildContext context, {
    required PremiumFeature feature,
    EntitlementService? entitlementService,
  }) async {
    SubscriptionEntitlements entitlements;
    try {
      entitlements = await (entitlementService ?? EntitlementService())
          .currentEntitlements();
    } catch (_) {
      // Fail closed when subscription state cannot be verified.
      entitlements = SubscriptionEntitlements.free;
    }

    if (!context.mounted) return false;
    if (feature.isEnabledBy(entitlements)) return true;

    await showPremiumUpsellSheet(context, upsellContext: feature.upsellContext);
    return false;
  }

  /// Returns true when the Premium capability is present. The callable is
  /// the only authority for the live owned-Club quota: a client-side count
  /// both races concurrent devices and used to include the free Family Room.
  /// `clubService` remains accepted for source compatibility with injected
  /// widget tests, but is deliberately not consulted for authorization.
  static Future<bool> ensureCanCreateClub(
    BuildContext context, {
    EntitlementService? entitlementService,
    ClubService? clubService,
  }) async {
    SubscriptionEntitlements entitlements;
    try {
      entitlements = await (entitlementService ?? EntitlementService())
          .currentEntitlements();
    } catch (_) {
      entitlements = SubscriptionEntitlements.free;
    }

    if (!context.mounted) return false;

    if (!entitlements.canUseClubs) {
      await showPremiumUpsellSheet(
        context,
        upsellContext: PremiumUpsellContext.clubCreation,
      );
      return false;
    }

    return true;
  }
}
