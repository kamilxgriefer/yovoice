import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/premium_gates.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_feature_gate.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_upsell_sheet.dart';

import 'support/likers_fixtures.dart';

const _uid = 'see-who-liked-member';

MockFirebaseAuth _auth() =>
    MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid));

SubscriptionEntitlements _paid({bool identity = true}) =>
    SubscriptionEntitlements(
      plan: PremiumPlan.monthly,
      status: 'active',
      currentPeriodEnd: DateTime(2099),
      isPremium: true,
      creatorEnabled: true,
      canCreateClubs: true,
      premiumIdentityEnabled: identity,
      maxOwnedClubs: 30,
    );

class _Entitlements extends EntitlementService {
  _Entitlements(this.value)
    : super(firestore: FakeFirebaseFirestore(), auth: _auth());

  final SubscriptionEntitlements value;

  @override
  Future<SubscriptionEntitlements> currentEntitlements() async => value;
}

void main() {
  setUp(EntitlementService.resetCache);
  tearDown(EntitlementService.resetCache);

  group('PremiumFeature.seeWhoLiked', () {
    test('the paid half: Premium identity or the moderator preview', () {
      const feature = PremiumFeature.seeWhoLiked;
      expect(feature.isEnabledBy(SubscriptionEntitlements.free), isFalse);
      expect(feature.isEnabledBy(_paid()), isTrue);
      // Paid without the identity flag never exposes a purchased capability.
      expect(feature.isEnabledBy(_paid(identity: false)), isFalse);
      expect(
        feature.isEnabledBy(
          SubscriptionEntitlements.free.withModeratorBenefits(true),
        ),
        isTrue,
      );
      expect(feature.upsellContext, PremiumUpsellContext.seeWhoLiked);
      expect(feature.label, 'See who liked');
    });
  });

  group('PremiumFeatureGate', () {
    for (final (locale, heading, template) in const [
      (
        Locale('en'),
        'See who liked is included with Premium',
        'See who liked requires Premium',
      ),
      (
        Locale('pl'),
        'Funkcja „Zobacz, kto polubił” jest w Premium',
        'Zobacz, kto polubił wymaga Premium',
      ),
    ]) {
      testWidgets('${locale.languageCode}: the locked destination reads '
          '"$heading", not the requires-Premium template', (tester) async {
        await tester.pumpWidget(
          likersHost(
            PremiumFeatureGate(
              feature: PremiumFeature.seeWhoLiked,
              entitlementService: EntitlementService(
                firestore: FakeFirebaseFirestore(),
                auth: _auth(),
              ),
              child: const Text('Protected'),
            ),
            locale: locale,
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(find.text('Protected'), findsNothing);
        expect(find.text(heading), findsOneWidget);
        expect(find.text(template), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('other features keep their requires-Premium heading', (
      tester,
    ) async {
      await tester.pumpWidget(
        likersHost(
          PremiumFeatureGate(
            feature: PremiumFeature.creatorStudio,
            entitlementService: EntitlementService(
              firestore: FakeFirebaseFirestore(),
              auth: _auth(),
            ),
            child: const Text('Protected'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Creator Studio requires Premium'), findsOneWidget);
    });
  });

  group('PremiumGates.ensureFeatureAccess(seeWhoLiked)', () {
    Future<bool?> run(
      WidgetTester tester,
      SubscriptionEntitlements entitlements,
    ) async {
      bool? result;
      await tester.pumpWidget(
        likersHost(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await PremiumGates.ensureFeatureAccess(
                    context,
                    feature: PremiumFeature.seeWhoLiked,
                    entitlementService: _Entitlements(entitlements),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('a free member gets the billing-aware U1 upsell', (
      tester,
    ) async {
      await run(tester, SubscriptionEntitlements.free);
      expect(find.byKey(kLikersUpsellSurface), findsOneWidget);
      expect(
        find.text('Premium isn\'t available to buy yet. It\'s coming soon.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('likers-upsell-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(kLikersUpsellSurface), findsNothing);
    });

    testWidgets('a paid member passes with no sheet', (tester) async {
      final result = await run(tester, _paid());
      expect(result, isTrue);
      expect(find.byKey(kLikersUpsellSurface), findsNothing);
    });
  });
}
