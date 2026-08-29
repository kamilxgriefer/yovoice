import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/premium_gates.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_badge_pill.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_feature_gate.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_upsell_sheet.dart';

void _useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _pearlApp(Widget home, {double textScale = 1}) => MaterialApp(
  theme: AppTheme.lightTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: home,
);

void main() {
  testWidgets('locked destination fits Pearl at 320px and 200 percent text', (
    tester,
  ) async {
    _useSurface(tester, const Size(320, 640));
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'free-premium-member'),
    );

    await tester.pumpWidget(
      _pearlApp(
        PremiumFeatureGate(
          feature: PremiumFeature.creatorStudio,
          entitlementService: EntitlementService(
            firestore: firestore,
            auth: auth,
          ),
          child: const Text('Protected'),
        ),
        textScale: 2,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Creator Studio requires Premium'), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      AppPalette.light.background,
    );
    await tester.ensureVisible(find.text('Explore Premium'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('upsell sheet is scrollable at 320px and uses Pearl surface', (
    tester,
  ) async {
    _useSurface(tester, const Size(320, 640));
    await tester.pumpWidget(
      _pearlApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showPremiumUpsellSheet(
                  context,
                  upsellContext: PremiumUpsellContext.creatorStudio,
                ),
                child: const Text('Open Premium offer'),
              ),
            ),
          ),
        ),
        textScale: 2,
      ),
    );
    await tester.tap(find.text('Open Premium offer'));
    await tester.pumpAndSettle();

    final surface = tester.widget<Material>(
      find.byKey(const ValueKey('premium-upsell-surface')),
    );
    expect(surface.color, AppPalette.light.surfaceRaised);
    expect(find.text('Creator Studio is a Premium feature'), findsOneWidget);
    await tester.ensureVisible(find.text('Explore Premium'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Premium badge keeps an accessible Pearl pairing at 1440px', (
    tester,
  ) async {
    _useSurface(tester, const Size(1440, 900));
    await tester.pumpWidget(
      _pearlApp(const Scaffold(body: Center(child: PremiumBadgePill()))),
    );

    final container = tester.widget<Container>(
      find.byKey(const ValueKey('premium-badge-pill')),
    );
    final decoration = container.decoration! as BoxDecoration;
    final colors = AppTheme.lightTheme.colorScheme;
    expect(decoration.color, colors.primaryContainer);
    final label = tester.widget<Text>(find.text('YO VOICE PREMIUM'));
    expect(label.style?.color, colors.onPrimaryContainer);
    expect(tester.takeException(), isNull);
  });
}
