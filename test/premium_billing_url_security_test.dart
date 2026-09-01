import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/premium/data/services/premium_billing_service.dart';

void main() {
  test('accepts only the exact Stripe hosted checkout origin', () {
    final uri = parsePremiumHostedUrl(<String, Object?>{
      'url': 'https://checkout.stripe.com/c/pay/session?locale=pl',
    }, expectedHost: 'checkout.stripe.com');
    expect(uri.host, 'checkout.stripe.com');

    for (final url in <String>[
      'http://checkout.stripe.com/c/pay/session',
      'https://checkout.stripe.com.evil.test/c/pay/session',
      'https://checkout.stripe.com@evil.test/c/pay/session',
      'https://user:password@checkout.stripe.com/c/pay/session',
      'https://checkout.stripe.com:444/c/pay/session',
    ]) {
      expect(
        () => parsePremiumHostedUrl(<String, Object?>{
          'url': url,
        }, expectedHost: 'checkout.stripe.com'),
        throwsFormatException,
        reason: url,
      );
    }
  });

  test('does not interchange Checkout and Billing Portal origins', () {
    expect(
      () => parsePremiumHostedUrl(<String, Object?>{
        'url': 'https://checkout.stripe.com/c/pay/session',
      }, expectedHost: 'billing.stripe.com'),
      throwsFormatException,
    );
    expect(
      parsePremiumHostedUrl(<String, Object?>{
        'url': 'https://billing.stripe.com/p/session',
      }, expectedHost: 'billing.stripe.com').host,
      'billing.stripe.com',
    );
  });
}
