import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/likers/data/models/likers_target.dart';
import 'package:yovoice/features/likers/presentation/show_likers.dart';
import 'package:yovoice/features/likers/presentation/widgets/likers_upsell_sheet.dart';
import 'package:yovoice/features/premium/data/models/premium_billing_context.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/services/premium_billing_service.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_upsell_sheet.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';

import 'support/likers_fixtures.dart';

const _moment = VoiceMomentLikersTarget('m1');
const _notForSale = 'Premium isn\'t available to buy yet. It\'s coming soon.';
const _close = ValueKey<String>('likers-upsell-close');
const _explore = ValueKey<String>('likers-upsell-explore');
const _statusLine = ValueKey<String>('likers-upsell-not-for-sale');

PremiumBillingContext _billing({required bool checkout}) =>
    PremiumBillingContext(
      countryCode: 'PL',
      currency: 'PLN',
      taxDisplay: 'included',
      taxNotice: 'VAT is included where required.',
      priceDisplaySource: 'base',
      localizedAtCheckout: true,
      billingManagedBy: PremiumBillingManager.none,
      checkoutAvailable: checkout,
      portalAvailable: false,
      currentPlan: PremiumPlan.none,
      renewalBehavior: 'none',
      currentPeriodEnd: null,
      plans: const [],
    );

class _Billing implements PremiumBillingGateway {
  _Billing({this.checkout = false, this.fails = false, this.hang = false});

  final bool checkout;
  final bool fails;
  final bool hang;
  int calls = 0;

  @override
  Future<PremiumBillingContext> getContext({String? countryCode}) {
    calls++;
    if (hang) return Completer<PremiumBillingContext>().future;
    if (fails) return Future.error(StateError('offline'));
    return Future.value(_billing(checkout: checkout));
  }

  @override
  Future<Uri> createCheckout(PremiumPlan plan) => throw UnimplementedError();

  @override
  Future<Uri> createPortal() => throw UnimplementedError();
}

void main() {
  void size(WidgetTester tester, Size logical) {
    tester.view.physicalSize = logical * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> open(
    WidgetTester tester, {
    PremiumCanBuyResolver? canBuy,
    LikersTarget? target = _moment,
    Locale locale = const Locale('en'),
    bool pearl = false,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      likersHost(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showLikersUpsell(
                  context,
                  target,
                  totalCount: 24,
                  canBuyPremium: canBuy,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        locale: locale,
        pearl: pearl,
        textScale: textScale,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('premiumCheckoutAvailable', () {
    test('iOS and Android never ask the billing backend', () async {
      final billing = _Billing(checkout: true);
      expect(
        await premiumCheckoutAvailable(billing: billing, isWeb: false),
        isFalse,
      );
      expect(billing.calls, 0);
    });

    test('web follows the trusted checkoutAvailable flag', () async {
      expect(
        await premiumCheckoutAvailable(
          billing: _Billing(checkout: true),
          isWeb: true,
        ),
        isTrue,
      );
      expect(
        await premiumCheckoutAvailable(
          billing: _Billing(checkout: false),
          isWeb: true,
        ),
        isFalse,
      );
    });

    test('a failure or a slow answer is "cannot buy"', () async {
      expect(
        await premiumCheckoutAvailable(
          billing: _Billing(fails: true),
          isWeb: true,
        ),
        isFalse,
      );
      expect(
        await premiumCheckoutAvailable(
          billing: _Billing(hang: true),
          isWeb: true,
          timeout: const Duration(milliseconds: 10),
        ),
        isFalse,
      );
    });
  });

  group('U1 upsell, billing off (today on every platform)', () {
    testWidgets('default resolver off the web: honest line + one Close, '
        'no purchase CTA, no link', (tester) async {
      size(tester, const Size(390, 844));
      await open(tester);
      expect(find.text(_notForSale), findsOneWidget);
      expect(find.byKey(_explore), findsNothing);
      expect(find.textContaining('Explore'), findsNothing);
      expect(find.textContaining('Learn about'), findsNothing);
      expect(find.textContaining('yovoice.app'), findsNothing);
      final surface = find.byKey(const ValueKey('likers-upsell-surface'));
      expect(
        find.descendant(of: surface, matching: find.byType(FilledButton)),
        findsOneWidget,
      );
      final close = tester.widget<YoGradientFilledButton>(
        find.ancestor(
          of: find.byKey(_close),
          matching: find.byType(YoGradientFilledButton),
        ),
      );
      expect(close.emphasis, YoActionEmphasis.neutral);
      await tester.tap(find.byKey(_close));
      await tester.pumpAndSettle();
      expect(surface, findsNothing);
    });

    for (final (label, resolver) in <(String, PremiumCanBuyResolver)>[
      ('checkout off', () async => false),
      ('billing error', () => Future<bool>.error(StateError('offline'))),
    ]) {
      testWidgets('$label resolves to the honest variant', (tester) async {
        size(tester, const Size(390, 844));
        await open(tester, canBuy: resolver);
        expect(find.text(_notForSale), findsOneWidget);
        expect(find.byKey(_explore), findsNothing);
        expect(find.byKey(_close), findsOneWidget);
      });
    }

    testWidgets('Polish copy (owner §13)', (tester) async {
      size(tester, const Size(390, 844));
      await open(tester, locale: const Locale('pl'));
      expect(
        find.text('Zobacz, kto polubił — funkcja Premium'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Premium nie jest jeszcze dostępne w sprzedaży. Już wkrótce.',
        ),
        findsOneWidget,
      );
      expect(find.text('Zamknij'), findsOneWidget);
      expect(find.text('Poznaj Premium'), findsNothing);
    });
  });

  group('U1 upsell, billing on (web with checkout)', () {
    testWidgets('Explore Premium + Not now, no "not for sale" line', (
      tester,
    ) async {
      size(tester, const Size(390, 844));
      await tester.pumpWidget(
        likersHost(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => LikersUpsellSheet(
                    target: _moment,
                    totalCount: 24,
                    canBuyPremium: () async => true,
                    premiumDestination: (_) =>
                        const Scaffold(body: Text('premium-destination')),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(_notForSale), findsNothing);
      expect(find.text('See who liked — a Premium feature'), findsOneWidget);
      expect(find.text('24 people liked this Moment'), findsOneWidget);
      expect(find.text('Explore Premium'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      final explore = tester.widget<YoGradientFilledButton>(
        find.ancestor(
          of: find.byKey(_explore),
          matching: find.byType(YoGradientFilledButton),
        ),
      );
      expect(explore.emphasis, YoActionEmphasis.lifted);

      await tester.tap(find.byKey(_explore));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('likers-upsell-surface')), findsNothing);
      expect(find.text('premium-destination'), findsOneWidget);
    });

    testWidgets('while the web answer loads, Close works and the status '
        'line space is held but not shown or announced', (tester) async {
      size(tester, const Size(390, 844));
      final semantics = tester.ensureSemantics();
      final pending = Completer<bool>();
      await open(tester, canBuy: () => pending.future);
      final line = find.byKey(_statusLine);
      expect(line, findsOneWidget);
      expect(
        tester
            .widget<Visibility>(
              find.ancestor(of: line, matching: find.byType(Visibility)).first,
            )
            .visible,
        isFalse,
      );
      expect(find.semantics.byLabel(_notForSale), findsNothing);
      final heldHeight = tester.getSize(line).height;
      expect(heldHeight, greaterThan(0));
      expect(find.byKey(_explore), findsNothing);

      pending.complete(false);
      await tester.pumpAndSettle();
      expect(find.text(_notForSale), findsOneWidget);
      expect(find.semantics.byLabel(_notForSale), findsOneWidget);
      expect(tester.getSize(line).height, heldHeight);
      await tester.tap(find.byKey(_close));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('likers-upsell-surface')), findsNothing);
      semantics.dispose();
    });
  });

  testWidgets('PremiumUpsellContext.seeWhoLiked opens the U1 sheet without a '
      'count line', (tester) async {
    size(tester, const Size(390, 844));
    await tester.pumpWidget(
      likersHost(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPremiumUpsellSheet(
                context,
                upsellContext: PremiumUpsellContext.seeWhoLiked,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('likers-upsell-surface')), findsOneWidget);
    expect(find.byKey(const ValueKey('premium-upsell-surface')), findsNothing);
    expect(find.byKey(const ValueKey('likers-upsell-count')), findsNothing);
    expect(find.text(_notForSale), findsOneWidget);
    expect(find.textContaining('Explore'), findsNothing);
  });

  for (final width in const [390.0, 800.0, 1280.0]) {
    testWidgets('fits at $width px and 200 % text in both themes', (
      tester,
    ) async {
      size(tester, Size(width, 844));
      for (final pearl in const [false, true]) {
        await open(tester, pearl: pearl, textScale: 2);
        expect(tester.takeException(), isNull);
        final sheet = tester.getSize(
          find.byKey(const ValueKey('likers-upsell-surface')),
        );
        expect(sheet.width, lessThanOrEqualTo(kLikersSheetMaxWidth));
        await tester.ensureVisible(find.byKey(_close));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_close));
        await tester.pumpAndSettle();
      }
    });
  }
}
