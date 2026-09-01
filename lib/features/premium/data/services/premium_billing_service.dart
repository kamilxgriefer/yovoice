import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:yovoice/features/premium/data/models/premium_billing_context.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';

abstract interface class PremiumBillingGateway {
  Future<PremiumBillingContext> getContext({String? countryCode});
  Future<Uri> createCheckout(PremiumPlan plan);
  Future<Uri> createPortal();
}

class PremiumBillingService implements PremiumBillingGateway {
  PremiumBillingService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFunctions _functions;

  @override
  Future<PremiumBillingContext> getContext({String? countryCode}) async {
    final normalized = countryCode?.trim().toUpperCase();
    final result = await _functions
        .httpsCallable('getPremiumBillingContext')
        .call<Object?>(
          normalized == null || normalized.isEmpty
              ? <String, Object?>{}
              : <String, Object?>{'countryCode': normalized},
        );
    return PremiumBillingContext.fromJson(result.data);
  }

  @override
  Future<Uri> createCheckout(PremiumPlan plan) async {
    if (plan == PremiumPlan.none) {
      throw ArgumentError.value(plan, 'plan', 'A paid plan is required.');
    }
    final result = await _functions
        .httpsCallable('createPremiumCheckoutSession')
        .call<Object?>({'plan': plan.name});
    return parsePremiumHostedUrl(
      result.data,
      expectedHost: 'checkout.stripe.com',
    );
  }

  @override
  Future<Uri> createPortal() async {
    final result = await _functions
        .httpsCallable('createPremiumPortalSession')
        .call<Object?>(<String, Object?>{});
    return parsePremiumHostedUrl(
      result.data,
      expectedHost: 'billing.stripe.com',
    );
  }
}

@visibleForTesting
Uri parsePremiumHostedUrl(Object? value, {required String expectedHost}) {
  if (value is! Map || value.length != 1 || value['url'] is! String) {
    throw const FormatException('Invalid billing link response.');
  }
  final uri = Uri.tryParse(value['url'] as String);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != expectedHost ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('Invalid billing link.');
  }
  return uri;
}
