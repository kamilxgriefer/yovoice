import 'package:flutter/material.dart';

import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_upsell_sheet.dart';

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

  /// Returns true when club creation should proceed. Otherwise shows the
  /// contextual upsell (free member) or the owned-club limit message
  /// (premium member at cap) and returns false.
  static Future<bool> ensureCanCreateClub(
    BuildContext context, {
    EntitlementService? entitlementService,
    ClubService? clubService,
  }) async {
    final entitlements = await (entitlementService ?? EntitlementService())
        .currentEntitlements();

    if (!context.mounted) return false;

    if (!entitlements.canCreateClubs) {
      await showPremiumUpsellSheet(
        context,
        upsellContext: PremiumUpsellContext.clubCreation,
      );
      return false;
    }

    final owned = await (clubService ?? ClubService()).countOwnedClubs();
    if (!context.mounted) return false;

    if (owned >= entitlements.maxOwnedClubs) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Premium includes up to ${entitlements.maxOwnedClubs} owned '
            'clubs — you already own $owned.',
          ),
        ),
      );
      return false;
    }

    return true;
  }
}
