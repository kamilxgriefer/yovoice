import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/premium/data/models/premium_billing_context.dart';

Map<String, Object?> validContext() => {
  'countryCode': 'PL',
  'currency': 'PLN',
  'taxDisplay': 'included',
  'taxNotice': 'VAT is included where required.',
  'priceDisplaySource': 'base',
  'localizedAtCheckout': true,
  'billingManagedBy': 'stripe',
  'checkoutAvailable': false,
  'portalAvailable': true,
  'currentPlan': 'monthly',
  'renewalBehavior': 'renews',
  'currentPeriodEndMs': 1800000000000,
  'plans': [
    {
      'id': 'monthly',
      'interval': 'month',
      'currency': 'PLN',
      'unitAmount': 1999,
      'formattedPrice': '19,99 zł',
      'formattedEquivalent': null,
      'savingsPercent': 0,
    },
    {
      'id': 'yearly',
      'interval': 'year',
      'currency': 'PLN',
      'unitAmount': 19999,
      'formattedPrice': '199,99 zł',
      'formattedEquivalent': '16,67 zł',
      'savingsPercent': 17,
    },
  ],
};

void main() {
  test('strictly parses localized prices and lifecycle truth', () {
    final context = PremiumBillingContext.fromJson(validContext());
    expect(context.currency, 'PLN');
    expect(context.plans.last.formattedPrice, '199,99 zł');
    expect(context.plans.last.savingsPercent, 17);
    expect(context.renewalBehavior, 'renews');
    expect(context.currentPeriodEnd, isNotNull);
  });

  test('rejects extra context keys and non-integer timestamps', () {
    expect(
      () => PremiumBillingContext.fromJson({
        ...validContext(),
        'priceId': 'secret',
      }),
      throwsFormatException,
    );
    expect(
      () => PremiumBillingContext.fromJson({
        ...validContext(),
        'currentPeriodEndMs': 1.5,
      }),
      throwsFormatException,
    );
  });

  test('rejects duplicate or incomplete plan catalogs', () {
    final context = validContext();
    final plans = context['plans']! as List<Object?>;
    expect(
      () => PremiumBillingContext.fromJson({
        ...context,
        'plans': [plans.first, plans.first],
      }),
      throwsFormatException,
    );
  });

  test('rejects unknown current plans and impossible lifecycle states', () {
    expect(
      () => PremiumBillingContext.fromJson({
        ...validContext(),
        'currentPlan': 'unexpected-plan',
      }),
      throwsFormatException,
    );
    expect(
      () => PremiumBillingContext.fromJson({
        ...validContext(),
        'currentPlan': 'none',
        'renewalBehavior': 'none',
      }),
      throwsFormatException,
    );
  });

  test('binds plan intervals and currencies to the context', () {
    final context = validContext();
    final plans = context['plans']! as List<Object?>;
    final monthly = Map<String, Object?>.from(plans.first! as Map);
    final yearly = Map<String, Object?>.from(plans.last! as Map);
    expect(
      () => PremiumBillingContext.fromJson({
        ...context,
        'plans': [
          {...monthly, 'interval': 'year'},
          yearly,
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => PremiumBillingContext.fromJson({
        ...context,
        'plans': [
          {...monthly, 'currency': 'EUR'},
          yearly,
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => PremiumBillingContext.fromJson({...context, 'countryCode': 'pl'}),
      throwsFormatException,
    );
  });
}
