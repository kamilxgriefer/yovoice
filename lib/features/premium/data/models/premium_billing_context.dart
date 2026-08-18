import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';

enum PremiumBillingManager { stripe, apple, google, admin, none }

class PremiumLocalizedPlan {
  const PremiumLocalizedPlan({
    required this.plan,
    required this.interval,
    required this.currency,
    required this.unitAmount,
    required this.formattedPrice,
    required this.formattedEquivalent,
    required this.savingsPercent,
  });

  final PremiumPlan plan;
  final String interval;
  final String currency;
  final int unitAmount;
  final String formattedPrice;
  final String? formattedEquivalent;
  final int savingsPercent;

  factory PremiumLocalizedPlan.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid billing plan.');
    final data = Map<String, Object?>.from(value);
    const keys = {
      'id',
      'interval',
      'currency',
      'unitAmount',
      'formattedPrice',
      'formattedEquivalent',
      'savingsPercent',
    };
    if (data.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(data.keys.toSet()).isNotEmpty) {
      throw const FormatException('Invalid billing plan contract.');
    }
    final plan = PremiumPlan.fromValue(data['id']);
    final interval = data['interval'];
    final currency = data['currency'];
    final unitAmount = data['unitAmount'];
    final price = data['formattedPrice'];
    final equivalent = data['formattedEquivalent'];
    final savings = data['savingsPercent'];
    final expectedInterval = switch (plan) {
      PremiumPlan.monthly => 'month',
      PremiumPlan.yearly => 'year',
      PremiumPlan.none => null,
    };
    if (plan == PremiumPlan.none ||
        (interval != 'month' && interval != 'year') ||
        interval != expectedInterval ||
        currency is! String ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        unitAmount is! int ||
        unitAmount < 0 ||
        price is! String ||
        price.trim().isEmpty ||
        (equivalent != null && equivalent is! String) ||
        savings is! int ||
        savings < 0) {
      throw const FormatException('Invalid billing plan values.');
    }
    return PremiumLocalizedPlan(
      plan: plan,
      interval: interval as String,
      currency: currency,
      unitAmount: unitAmount,
      formattedPrice: price,
      formattedEquivalent: equivalent as String?,
      savingsPercent: savings,
    );
  }
}

class PremiumBillingContext {
  const PremiumBillingContext({
    required this.countryCode,
    required this.currency,
    required this.taxDisplay,
    required this.taxNotice,
    required this.priceDisplaySource,
    required this.localizedAtCheckout,
    required this.billingManagedBy,
    required this.checkoutAvailable,
    required this.portalAvailable,
    required this.currentPlan,
    required this.renewalBehavior,
    required this.currentPeriodEnd,
    required this.plans,
  });

  final String? countryCode;
  final String currency;
  final String taxDisplay;
  final String taxNotice;
  final String priceDisplaySource;
  final bool localizedAtCheckout;
  final PremiumBillingManager billingManagedBy;
  final bool checkoutAvailable;
  final bool portalAvailable;
  final PremiumPlan currentPlan;
  final String renewalBehavior;
  final DateTime? currentPeriodEnd;
  final List<PremiumLocalizedPlan> plans;

  factory PremiumBillingContext.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid billing response.');
    }
    final data = Map<String, Object?>.from(value);
    const keys = {
      'countryCode',
      'currency',
      'taxDisplay',
      'taxNotice',
      'priceDisplaySource',
      'localizedAtCheckout',
      'billingManagedBy',
      'checkoutAvailable',
      'portalAvailable',
      'currentPlan',
      'renewalBehavior',
      'currentPeriodEndMs',
      'plans',
    };
    if (data.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(data.keys.toSet()).isNotEmpty) {
      throw const FormatException('Invalid billing response contract.');
    }
    final country = data['countryCode'];
    final currency = data['currency'];
    final taxDisplay = data['taxDisplay'];
    final taxNotice = data['taxNotice'];
    final priceDisplaySource = data['priceDisplaySource'];
    final localizedAtCheckout = data['localizedAtCheckout'];
    final manager = switch (data['billingManagedBy']) {
      'stripe' => PremiumBillingManager.stripe,
      'apple' => PremiumBillingManager.apple,
      'google' => PremiumBillingManager.google,
      'admin' => PremiumBillingManager.admin,
      'none' => PremiumBillingManager.none,
      _ => null,
    };
    final checkoutAvailable = data['checkoutAvailable'];
    final portalAvailable = data['portalAvailable'];
    final currentPlan = switch (data['currentPlan']) {
      'monthly' => PremiumPlan.monthly,
      'yearly' => PremiumPlan.yearly,
      'none' => PremiumPlan.none,
      _ => null,
    };
    final renewalBehavior = data['renewalBehavior'];
    final currentPeriodEndMs = data['currentPeriodEndMs'];
    final rawPlans = data['plans'];
    if ((country != null &&
            (country is! String || !RegExp(r'^[A-Z]{2}$').hasMatch(country))) ||
        currency is! String ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        (taxDisplay != 'included' && taxDisplay != 'calculated_at_checkout') ||
        taxNotice is! String ||
        taxNotice.trim().isEmpty ||
        priceDisplaySource != 'base' ||
        localizedAtCheckout is! bool ||
        manager == null ||
        checkoutAvailable is! bool ||
        portalAvailable is! bool ||
        currentPlan == null ||
        (renewalBehavior != 'renews' &&
            renewalBehavior != 'ends' &&
            renewalBehavior != 'none') ||
        (currentPeriodEndMs != null &&
            (currentPeriodEndMs is! int || currentPeriodEndMs < 0)) ||
        rawPlans is! List) {
      throw const FormatException('Invalid billing response values.');
    }
    final plans = rawPlans.map(PremiumLocalizedPlan.fromJson).toList();
    if (plans.length != 2 ||
        plans.map((plan) => plan.plan).toSet().length != 2 ||
        plans.any((plan) => plan.currency != currency) ||
        (currentPlan == PremiumPlan.none &&
            (renewalBehavior != 'none' || currentPeriodEndMs != null)) ||
        (currentPlan != PremiumPlan.none && currentPeriodEndMs == null)) {
      throw const FormatException('Billing plans are incomplete.');
    }
    return PremiumBillingContext(
      countryCode: country as String?,
      currency: currency,
      taxDisplay: taxDisplay as String,
      taxNotice: taxNotice,
      priceDisplaySource: priceDisplaySource as String,
      localizedAtCheckout: localizedAtCheckout,
      billingManagedBy: manager,
      checkoutAvailable: checkoutAvailable,
      portalAvailable: portalAvailable,
      currentPlan: currentPlan,
      renewalBehavior: renewalBehavior as String,
      currentPeriodEnd: currentPeriodEndMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              currentPeriodEndMs as int,
              isUtc: true,
            ).toLocal(),
      plans: List.unmodifiable(plans),
    );
  }
}
