import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/data/models/premium_billing_context.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/services/premium_billing_service.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_plans_screen.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';

/// Responsive matrix (320 → 1440) for the mockup-pass Premium surfaces.
/// The real screens, pumped at every width in the device matrix, must lay out
/// without overflow exceptions and keep their core content present. This is the
/// repo-established pattern (see profile_header_layout_test.dart) for
/// responsive verification of signed-in surfaces that no headless
/// browser can reach.
const sizes = <Size>[
  Size(320, 568),
  Size(390, 844),
  Size(768, 1024),
  Size(1100, 800),
  Size(1440, 900),
];

const _uid = 'matrix-user';

MockFirebaseAuth _auth() => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: _uid, email: 'matrix@yovoice.app'),
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

class _RecordingPortalBilling implements PremiumBillingGateway {
  _RecordingPortalBilling({required this.context});

  final PremiumBillingContext context;
  int portalCalls = 0;

  @override
  Future<PremiumBillingContext> getContext({String? countryCode}) async =>
      context;

  @override
  Future<Uri> createCheckout(PremiumPlan plan) async =>
      Uri.parse('https://checkout.stripe.com/test');

  @override
  Future<Uri> createPortal() async {
    portalCalls += 1;
    // Stop before url_launcher: this test verifies the trusted Portal request,
    // not an operating-system browser integration.
    throw StateError('portal invocation recorded');
  }
}

Widget _scaledApp(Widget home) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(2)),
    child: child!,
  ),
  home: home,
);

Widget _app(Widget home) => MaterialApp(home: home);

void main() {
  setUp(() {
    EntitlementService.resetCache();
    ProfileService.resetCurrentProfileCache();
  });
  tearDown(() {
    EntitlementService.resetCache();
    ProfileService.resetCurrentProfileCache();
  });

  for (final size in sizes) {
    testWidgets('Premium presentation lays out cleanly at '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final db = FakeFirebaseFirestore();
      final auth = _auth();
      await tester.pumpWidget(
        _app(
          PremiumScreen(
            entitlementService: EntitlementService(firestore: db, auth: auth),
            profileService: ProfileService(firestore: db, auth: auth),
            billingService: const _FakeBilling(),
          ),
        ),
      );
      // Fixed pumps only — the premium hero ring animates forever.
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.text('More room\nfor your voice.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Check plans'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('Check plans'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Plans screen lays out cleanly at '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(
        _scaledApp(
          PremiumPlansScreen(
            entitlementService: EntitlementService(
              firestore: db,
              auth: _auth(),
            ),
            billingService: const _FakeBilling(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));

      await tester.scrollUntilVisible(
        find.text('19,99 zł'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('19,99 zł'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('199,99 zł'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('199,99 zł'), findsOneWidget);
      // Force the full lazy list to lay out — overflow below the fold
      // must fail the matrix too.
      await tester.scrollUntilVisible(
        find.text('Everything Premium includes:'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('Everything Premium includes:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'billing toggle and plan cards are keyboard-selectable controls',
    (tester) async {
      tester.view.physicalSize = const Size(560, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _scaledApp(
          PremiumPlansScreen(
            entitlementService: EntitlementService(
              firestore: FakeFirebaseFirestore(),
              auth: _auth(),
            ),
            billingService: const _FakeBilling(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));

      final monthlyToggle = find.bySemanticsLabel(
        'Select Monthly billing plan',
      );
      final monthlyCard = find.bySemanticsLabel(
        'Select Monthly plan, 19,99 zł',
      );
      final yearlyCard = find.bySemanticsLabel('Select Yearly plan, 199,99 zł');
      expect(monthlyToggle, findsOneWidget);
      expect(monthlyCard, findsOneWidget);
      expect(yearlyCard, findsOneWidget);
      expect(tester.getSize(monthlyToggle).height, greaterThanOrEqualTo(44));

      Focus.of(
        tester.element(
          find.descendant(of: monthlyToggle, matching: find.text('Monthly')),
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        tester
            .getSemantics(monthlyToggle)
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        ui.Tristate.isTrue,
      );
      expect(
        tester
            .getSemantics(monthlyCard)
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        ui.Tristate.isTrue,
      );

      Focus.of(
        tester.element(
          find.descendant(of: yearlyCard, matching: find.text('199,99 zł')),
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        tester
            .getSemantics(yearlyCard)
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        ui.Tristate.isTrue,
      );
    },
  );

  testWidgets('admin Premium is truthful and has no cancel action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = FakeFirebaseFirestore();
    await db.collection('entitlements').doc(_uid).set({
      'plan': 'yearly',
      'status': 'active',
      'currentPeriodEnd': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 100)),
      ),
      'isPremium': true,
    });
    final admin = PremiumBillingContext(
      countryCode: _billingContext.countryCode,
      currency: _billingContext.currency,
      taxDisplay: _billingContext.taxDisplay,
      taxNotice: _billingContext.taxNotice,
      priceDisplaySource: 'base',
      localizedAtCheckout: true,
      billingManagedBy: PremiumBillingManager.admin,
      checkoutAvailable: false,
      portalAvailable: false,
      currentPlan: PremiumPlan.yearly,
      renewalBehavior: 'none',
      currentPeriodEnd: DateTime.now().add(const Duration(days: 100)),
      plans: _billingContext.plans,
    );
    await tester.pumpWidget(
      _scaledApp(
        PremiumPlansScreen(
          entitlementService: EntitlementService(firestore: db, auth: _auth()),
          billingService: _FakeBilling(context: admin),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Manage your plan'), findsOneWidget);
    expect(find.textContaining('Complimentary Premium access'), findsOneWidget);
    expect(find.text('Change or cancel'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stripe Premium exposes portal and exact ending lifecycle', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final end = DateTime.now().add(const Duration(days: 20));
    await db.collection('entitlements').doc(_uid).set({
      'plan': 'monthly',
      'status': 'active',
      'currentPeriodEnd': Timestamp.fromDate(end),
      'isPremium': true,
    });
    final stripe = PremiumBillingContext(
      countryCode: 'PL',
      currency: 'PLN',
      taxDisplay: 'included',
      taxNotice: _billingContext.taxNotice,
      priceDisplaySource: 'base',
      localizedAtCheckout: true,
      billingManagedBy: PremiumBillingManager.stripe,
      checkoutAvailable: false,
      portalAvailable: true,
      currentPlan: PremiumPlan.monthly,
      renewalBehavior: 'ends',
      currentPeriodEnd: end,
      plans: _billingContext.plans,
    );
    await tester.pumpWidget(
      _app(
        PremiumPlansScreen(
          entitlementService: EntitlementService(firestore: db, auth: _auth()),
          billingService: _FakeBilling(context: stripe),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Change or cancel'), findsOneWidget);
    expect(find.textContaining('Ends '), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'canonical Stripe billing stays manageable without claiming active Premium',
    (tester) async {
      final recovery = PremiumBillingContext(
        countryCode: 'PL',
        currency: 'PLN',
        taxDisplay: 'included',
        taxNotice: _billingContext.taxNotice,
        priceDisplaySource: 'base',
        localizedAtCheckout: true,
        billingManagedBy: PremiumBillingManager.stripe,
        checkoutAvailable: true,
        portalAvailable: true,
        currentPlan: PremiumPlan.none,
        renewalBehavior: 'none',
        currentPeriodEnd: null,
        plans: _billingContext.plans,
      );
      final billing = _RecordingPortalBilling(context: recovery);

      await tester.pumpWidget(
        _app(
          PremiumPlansScreen(
            entitlementService: EntitlementService(
              firestore: FakeFirebaseFirestore(),
              auth: _auth(),
            ),
            billingService: billing,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Review your billing'), findsOneWidget);
      expect(find.text('Open billing portal'), findsOneWidget);
      expect(find.text('Current plan'), findsNothing);
      expect(find.textContaining('Renews '), findsNothing);
      expect(find.textContaining('Ends '), findsNothing);

      await tester.tap(find.text('Open billing portal'));
      await tester.pump();
      expect(billing.portalCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('billing load failure is friendly and retryable', (tester) async {
    await tester.pumpWidget(
      _app(
        PremiumPlansScreen(
          entitlementService: EntitlementService(
            firestore: FakeFirebaseFirestore(),
            auth: _auth(),
          ),
          billingService: const _FakeBilling(fails: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Plans are temporarily unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
