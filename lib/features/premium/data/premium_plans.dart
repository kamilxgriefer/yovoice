import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';

/// The single source of product/pricing configuration for YO Voice
/// Premium. Nothing else in the app hard-codes prices or product ids.
///
/// The displayed prices below are the product's configured EUR prices.
/// Once App Store / Play products exist, the store's localized price
/// (fetched at runtime through the billing plugin) is authoritative for
/// display on those platforms — these strings are the web/marketing and
/// fallback copy.
class PremiumProduct {
  const PremiumProduct({
    required this.plan,
    required this.storeProductId,
    required this.displayPrice,
    required this.billingPeriodLabel,
    this.equivalentMonthlyPrice,
    this.savingsLabel,
    this.highlight = false,
  });

  final PremiumPlan plan;

  /// Shared id for App Store Connect / Play Console products — must match
  /// what gets configured in both consoles.
  final String storeProductId;
  final String displayPrice;
  final String billingPeriodLabel;
  final String? equivalentMonthlyPrice;
  final String? savingsLabel;
  final bool highlight;
}

class PremiumPlans {
  PremiumPlans._();

  static const PremiumProduct monthly = PremiumProduct(
    plan: PremiumPlan.monthly,
    storeProductId: 'yovoice_premium_monthly',
    displayPrice: '€9.99',
    billingPeriodLabel: '/ month',
  );

  static const PremiumProduct yearly = PremiumProduct(
    plan: PremiumPlan.yearly,
    storeProductId: 'yovoice_premium_yearly',
    displayPrice: '€89.99',
    billingPeriodLabel: '/ year',
    equivalentMonthlyPrice: '≈ €7.50 / month',
    savingsLabel: 'Save about 25%',
    highlight: true,
  );

  static const List<PremiumProduct> all = [yearly, monthly];

  /// The benefits list rendered by the paywall and the marketing site —
  /// one place, so copy can't drift between surfaces.
  static const List<(String, String)> benefits = [
    (
      'Creator profile',
      'Build a public Creator identity and unlock Creator tools.',
    ),
    ('Create Clubs', 'Build and own your own communities.'),
    ('Stand out', 'Premium identity styling across profiles and rooms.'),
    ('More to come', 'New Premium capabilities plug into your subscription.'),
  ];
}
