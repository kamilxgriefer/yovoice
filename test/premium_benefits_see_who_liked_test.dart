import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/home/presentation/widgets/desktop/premium_desktop_card.dart';
import 'package:yovoice/features/home/presentation/widgets/mobile/mobile_home_sections.dart';
import 'package:yovoice/features/premium/data/models/premium_billing_context.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/premium_plans.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/data/services/premium_billing_service.dart';
import 'package:yovoice/features/premium/presentation/premium_benefit_icons.dart';
import 'package:yovoice/features/premium/presentation/premium_localized_copy.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_plans_screen.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';

import 'support/likers_fixtures.dart';

const _uid = 'benefits-member';
const _subtitle =
    'Badge, shimmer, privacy controls, see who liked and a modest Yeels boost';
const _subtitlePl =
    'Odznaka, połysk, ustawienia prywatności, podgląd polubień i umiarkowane wsparcie rekomendacji w Yeels';
const _included =
    'See who liked Voice Moments, Yeels, comments and Server messages';
const _includedPl =
    'Zobacz, kto polubił Momenty głosowe, Yeels, komentarze i wiadomości na serwerach';

MockFirebaseAuth _auth() =>
    MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _uid));

const _billingContext = PremiumBillingContext(
  countryCode: 'PL',
  currency: 'PLN',
  taxDisplay: 'included',
  taxNotice: 'VAT is included where required.',
  priceDisplaySource: 'base',
  localizedAtCheckout: true,
  billingManagedBy: PremiumBillingManager.none,
  checkoutAvailable: false,
  portalAvailable: false,
  currentPlan: PremiumPlan.none,
  renewalBehavior: 'none',
  currentPeriodEnd: null,
  plans: [
    PremiumLocalizedPlan(
      plan: PremiumPlan.monthly,
      interval: 'month',
      currency: 'PLN',
      unitAmount: 1999,
      formattedPrice: '19,99 zł',
      formattedEquivalent: null,
      savingsPercent: 0,
    ),
    PremiumLocalizedPlan(
      plan: PremiumPlan.yearly,
      interval: 'year',
      currency: 'PLN',
      unitAmount: 19999,
      formattedPrice: '199,99 zł',
      formattedEquivalent: '16,67 zł',
      savingsPercent: 17,
    ),
  ],
);

class _FakeBilling implements PremiumBillingGateway {
  const _FakeBilling();

  @override
  Future<PremiumBillingContext> getContext({String? countryCode}) async =>
      _billingContext;

  @override
  Future<Uri> createCheckout(PremiumPlan plan) => throw UnimplementedError();

  @override
  Future<Uri> createPortal() => throw UnimplementedError();
}

void main() {
  setUp(() {
    EntitlementService.resetCache();
    ProfileService.resetCurrentProfileCache();
  });
  tearDown(() {
    EntitlementService.resetCache();
    ProfileService.resetCurrentProfileCache();
  });

  void size(WidgetTester tester, Size logical) {
    tester.view.physicalSize = logical;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('PremiumPlans data (spec §5.4: keep 3 cards)', () {
    test('card 3 carries the benefit; titles unchanged', () {
      expect(PremiumPlans.benefits, hasLength(3));
      expect(PremiumPlans.benefits[2].$1, 'Premium presence & privacy');
      expect(PremiumPlans.benefits[2].$2, _subtitle);
    });

    test('checklist has "See who liked" right before "Exclusive features"', () {
      final list = PremiumPlans.planChecklist;
      expect(
        list.indexOf('See who liked'),
        list.indexOf('Exclusive features') - 1,
      );
    });

    test('included list has 7 lines, the new one before "More benefits"', () {
      final list = PremiumPlans.everythingIncluded;
      expect(list, hasLength(7));
      expect(
        list.indexOf(_included),
        list.indexOf('More benefits coming soon') - 1,
      );
    });
  });

  group('title-keyed icons (no positional RangeError)', () {
    test('every current benefit and included line has its own glyph', () {
      expect(
        PremiumPlans.benefits.map((b) => premiumBenefitKind(b.$1)),
        isNot(contains(PremiumBenefitKind.other)),
      );
      expect(premiumIncludedItemIcon(_included), Icons.favorite_border_rounded);
      final icons = PremiumPlans.everythingIncluded
          .map(premiumIncludedItemIcon)
          .toList();
      expect(icons.toSet(), hasLength(icons.length));
    });

    test('an unknown title falls back instead of throwing', () {
      expect(premiumBenefitKind('A future card'), PremiumBenefitKind.other);
      expect(premiumBenefitIcon('A future card'), Icons.auto_awesome_rounded);
      expect(
        premiumIncludedItemIcon('A future line'),
        Icons.auto_awesome_outlined,
      );
    });
  });

  group('Polish copy is never the generic fallback', () {
    testWidgets('subtitle, checklist and included line', (tester) async {
      late AppLocalizations copy;
      await tester.pumpWidget(
        likersHost(
          Builder(
            builder: (context) {
              copy = AppLocalizations.of(context);
              return const SizedBox();
            },
          ),
          locale: const Locale('pl'),
        ),
      );
      expect(
        localizedPremiumBenefit(copy, PremiumPlans.benefits[2]).$2,
        _subtitlePl,
      );
      expect(
        localizedPremiumChecklistItem(copy, 'See who liked'),
        'Zobacz, kto polubił',
      );
      expect(localizedPremiumIncludedItem(copy, _included), _includedPl);
      for (final item in PremiumPlans.planChecklist) {
        expect(
          localizedPremiumChecklistItem(copy, item),
          isNot('Funkcja Premium'),
        );
      }
      for (final item in PremiumPlans.everythingIncluded) {
        expect(
          localizedPremiumIncludedItem(copy, item),
          isNot('Korzyść Premium'),
        );
      }
    });
  });

  group('surfaces', () {
    for (final (locale, subtitle) in const [
      (Locale('en'), _subtitle),
      (Locale('pl'), _subtitlePl),
    ]) {
      testWidgets('${locale.languageCode}: PremiumScreen shows 3 cards with '
          'the new subtitle at 390 and 1280', (tester) async {
        for (final width in const [390.0, 1280.0]) {
          size(tester, Size(width, 2400));
          final db = FakeFirebaseFirestore();
          final auth = _auth();
          await tester.pumpWidget(
            likersHost(
              PremiumScreen(
                entitlementService: EntitlementService(
                  firestore: db,
                  auth: auth,
                ),
                profileService: ProfileService(firestore: db, auth: auth),
                billingService: const _FakeBilling(),
              ),
              locale: locale,
            ),
          );
          // Fixed pumps: the hero ring animates forever.
          await tester.pump(const Duration(milliseconds: 120));
          expect(find.text(subtitle), findsOneWidget);
          expect(find.byIcon(Icons.mic_rounded), findsWidgets);
          expect(tester.takeException(), isNull);
          if (width < 420) {
            // Stacked, the three cards line up at one full column width.
            final cards = find.byWidgetPredicate(
              (widget) => widget.runtimeType.toString() == '_BenefitCard',
            );
            expect(cards, findsNWidgets(3));
            final widths = <double>{
              for (var i = 0; i < 3; i++) tester.getSize(cards.at(i)).width,
            };
            expect(widths, hasLength(1), reason: '$widths');
          }
          await tester.pumpWidget(const SizedBox());
          EntitlementService.resetCache();
          ProfileService.resetCurrentProfileCache();
        }
      });
    }

    for (final locale in const [Locale('en'), Locale('pl'), Locale('de')]) {
      testWidgets('${locale.languageCode}: the 318 px desktop column lists the '
          'benefits as rows; a wide card keeps the three tiles', (
        tester,
      ) async {
        size(tester, const Size(1280, 900));
        await tester.pumpWidget(
          likersHost(
            Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 318,
                    child: PremiumDesktopCard(
                      key: const ValueKey('narrow'),
                      onCheckPlans: () {},
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 520,
                    child: PremiumDesktopCard(
                      key: const ValueKey('wide'),
                      onCheckPlans: () {},
                    ),
                  ),
                ],
              ),
            ),
            locale: locale,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        const list = ValueKey('desktop-premium-benefit-list');
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('narrow')),
            matching: find.byKey(list),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('wide')),
            matching: find.byKey(list),
          ),
          findsNothing,
        );
        // The narrow card is a compact list, not three 12-line columns.
        expect(
          tester.getSize(find.byKey(const ValueKey('narrow'))).height,
          lessThan(
            tester.getSize(find.byKey(const ValueKey('wide'))).height + 120,
          ),
        );
      });
    }

    testWidgets('desktop card and mobile card: 3 tiles, new subtitle', (
      tester,
    ) async {
      size(tester, const Size(1280, 900));
      await tester.pumpWidget(
        likersHost(
          Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 380,
                  child: PremiumDesktopCard(onCheckPlans: () {}),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 358,
                  child: MobilePremiumCard(onCheckPlans: () {}),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(_subtitle), findsNWidgets(2));
      expect(find.text('Premium presence & privacy'), findsNWidgets(2));
      expect(find.byIcon(Icons.auto_awesome_rounded), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    for (final (locale, included, check) in const [
      (Locale('en'), _included, 'See who liked'),
      (Locale('pl'), _includedPl, 'Zobacz, kto polubił'),
    ]) {
      testWidgets('${locale.languageCode}: plans screen renders the 7-line '
          'included list and the checklist item', (tester) async {
        size(tester, const Size(390, 4000));
        await tester.pumpWidget(
          likersHost(
            PremiumPlansScreen(
              entitlementService: EntitlementService(
                firestore: FakeFirebaseFirestore(),
                auth: _auth(),
              ),
              billingService: const _FakeBilling(),
            ),
            locale: locale,
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull);
        expect(find.text(included), findsOneWidget);
        expect(find.text(check), findsWidgets);
        expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      });
    }
  });
}
