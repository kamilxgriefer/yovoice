import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/premium/data/models/premium_billing_context.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/data/services/premium_billing_service.dart';
import 'package:yovoice/features/premium/premium_gates.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_plans_screen.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_feature_gate.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_upsell_sheet.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';

const _uid = 'premium-polish-member';

MockFirebaseAuth _auth() => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: _uid, email: 'premium-polish@yovoice.app'),
);

const _billingContext = PremiumBillingContext(
  countryCode: 'PL',
  currency: 'PLN',
  taxDisplay: 'included',
  taxNotice: 'VAT is included where required.',
  priceDisplaySource: 'base',
  localizedAtCheckout: true,
  billingManagedBy: PremiumBillingManager.none,
  checkoutAvailable: true,
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
  const _FakeBilling({this.context = _billingContext, this.fails = false});

  final PremiumBillingContext context;
  final bool fails;

  @override
  Future<PremiumBillingContext> getContext({String? countryCode}) async {
    if (fails) throw StateError('offline');
    return context;
  }

  @override
  Future<Uri> createCheckout(PremiumPlan plan) async =>
      Uri.parse('https://checkout.stripe.com/test');

  @override
  Future<Uri> createPortal() async =>
      Uri.parse('https://billing.stripe.com/test');
}

Widget _polishApp(Widget home) => MaterialApp(
  locale: const Locale('pl'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: AppTheme.lightTheme,
  home: home,
);

void main() {
  setUp(() {
    EntitlementService.resetCache();
    ProfileService.resetCurrentProfileCache();
  });

  tearDown(() {
    EntitlementService.resetCache();
    ProfileService.resetCurrentProfileCache();
  });

  testWidgets('Premium presentation uses complete natural Polish copy', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final auth = _auth();

    await tester.pumpWidget(
      _polishApp(
        PremiumScreen(
          entitlementService: EntitlementService(
            firestore: firestore,
            auth: auth,
          ),
          profileService: ProfileService(firestore: firestore, auth: auth),
          billingService: const _FakeBilling(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Więcej przestrzeni\ndla Twojego głosu.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Zostań twórcą'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Zostań twórcą'), findsOneWidget);
    expect(find.text('Twórz własne kluby'), findsOneWidget);
    expect(find.text('Wyróżnij się'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sprawdź plany'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Sprawdź plany'), findsOneWidget);
    expect(find.text('More room\nfor your voice.'), findsNothing);
    expect(find.text('Check plans'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Premium plan selection localizes plans, prices and legal copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _polishApp(
        PremiumPlansScreen(
          entitlementService: EntitlementService(
            firestore: FakeFirebaseFirestore(),
            auth: _auth(),
          ),
          billingService: const _FakeBilling(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Wybierz plan'), findsOneWidget);
    expect(find.text('Miesięczny'), findsWidgets);
    expect(find.text('Roczny'), findsWidgets);
    expect(find.text('19,99 zł'), findsOneWidget);
    expect(find.text('199,99 zł'), findsOneWidget);
    expect(find.text('/ miesiąc'), findsOneWidget);
    expect(find.text('/ rok'), findsOneWidget);
    expect(find.text('Oszczędzasz 17%'), findsOneWidget);
    expect(find.text('Dostęp do funkcji twórcy'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Premium obejmuje:'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Premium obejmuje:'), findsOneWidget);
    expect(find.text('Profil i narzędzia twórcy'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Regulamin'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Regulamin'), findsOneWidget);
    expect(find.text('Prywatność'), findsOneWidget);
    expect(find.text('Choose your plan'), findsNothing);
    expect(find.text('Everything Premium includes:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Premium gate explains blocked Creator Studio in Polish', (
    tester,
  ) async {
    await tester.pumpWidget(
      _polishApp(
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

    expect(find.text('Studio twórcy wymaga Premium'), findsOneWidget);
    expect(
      find.text(
        'Aktywuj Premium, aby korzystać z panelu twórcy i narzędzi publikowania.',
      ),
      findsOneWidget,
    );
    expect(find.text('Poznaj Premium'), findsOneWidget);
    expect(find.text('Creator Studio requires Premium'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Premium upsell sheet localizes its title, actions and semantics',
    (tester) async {
      await tester.pumpWidget(
        _polishApp(
          Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => showPremiumUpsellSheet(
                  context,
                  upsellContext: PremiumUpsellContext.creatorStudio,
                ),
                child: const Text('Otwórz'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Otwórz'));
      await tester.pumpAndSettle();

      expect(find.text('Studio twórcy jest funkcją Premium'), findsOneWidget);
      expect(find.text('Poznaj Premium'), findsOneWidget);
      expect(find.text('Nie teraz'), findsOneWidget);
      expect(find.bySemanticsLabel('Oferta Premium'), findsOneWidget);
      expect(find.text('Creator Studio is a Premium feature'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('current Stripe plan uses Polish lifecycle and date labels', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final end = DateTime.now().add(const Duration(days: 50));
    await firestore.collection('entitlements').doc(_uid).set({
      'plan': 'monthly',
      'status': 'active',
      'currentPeriodEnd': Timestamp.fromDate(end),
      'isPremium': true,
    });
    final stripeContext = PremiumBillingContext(
      countryCode: _billingContext.countryCode,
      currency: _billingContext.currency,
      taxDisplay: _billingContext.taxDisplay,
      taxNotice: _billingContext.taxNotice,
      priceDisplaySource: _billingContext.priceDisplaySource,
      localizedAtCheckout: _billingContext.localizedAtCheckout,
      billingManagedBy: PremiumBillingManager.stripe,
      checkoutAvailable: false,
      portalAvailable: true,
      currentPlan: PremiumPlan.monthly,
      renewalBehavior: 'ends',
      currentPeriodEnd: end,
      plans: _billingContext.plans,
    );

    await tester.pumpWidget(
      _polishApp(
        PremiumPlansScreen(
          entitlementService: EntitlementService(
            firestore: firestore,
            auth: _auth(),
          ),
          billingService: _FakeBilling(context: stripeContext),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Zarządzaj swoim planem'), findsOneWidget);
    expect(find.text('YO Voice Premium · Miesięczny'), findsOneWidget);
    expect(find.textContaining('Kończy się '), findsOneWidget);
    expect(
      find.textContaining('Zarządzane bezpiecznie przez Stripe'),
      findsOneWidget,
    );
    expect(find.text('Zmień lub anuluj'), findsOneWidget);
    expect(find.textContaining('Ends '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('billing load failure is actionable in Polish', (tester) async {
    await tester.pumpWidget(
      _polishApp(
        PremiumPlansScreen(
          entitlementService: EntitlementService(
            firestore: FakeFirebaseFirestore(),
            auth: _auth(),
          ),
          billingService: const _FakeBilling(fails: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Plany są chwilowo niedostępne'), findsOneWidget);
    expect(
      find.text(
        'Nie udało się wczytać cen planów. Sprawdź połączenie i spróbuj ponownie.',
      ),
      findsOneWidget,
    );
    expect(find.text('Spróbuj ponownie'), findsOneWidget);
    expect(find.text('Plans are temporarily unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
