// Who may create a Page, client side (owner decisions 2026-09-29): a
// canonical VIP grant OR active paid/admin Premium identity. The moderator
// preview is not an authority for Pages (the server refuses staffPreview).
// Followers never matter.
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/pages/data/services/page_access_service.dart';
import 'package:yovoice/features/pages/presentation/screens/create_page_screen.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';

void main() {
  group('PageAccessService', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me'));
    });

    tearDown(EntitlementService.resetCache);

    PageAccessService service() =>
        PageAccessService(firestore: firestore, auth: auth);

    Future<void> paid({bool identity = true}) =>
        firestore.doc('entitlements/me').set(<String, Object?>{
          'isPremium': true,
          'status': 'active',
          'currentPeriodEnd': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 30)),
          ),
          'premiumIdentityEnabled': identity,
        });

    test('a free account without a grant cannot create', () async {
      final state = await service().watch().first;
      expect(state.resolved, isTrue);
      expect(state.hasVipGrant, isFalse);
      expect(state.hasPaidPremium, isFalse);
      expect(state.canCreatePage, isFalse);
    });

    test('active paid Premium identity can create without a grant', () async {
      await paid();
      final state = await service().watch().first;
      expect(state.hasVipGrant, isFalse);
      expect(state.hasPaidPremium, isTrue);
      expect(state.canRunPage, isTrue);
      expect(state.canCreatePage, isTrue);
    });

    test('Premium without the identity flag does not count', () async {
      await paid(identity: false);
      expect((await service().watch().first).canCreatePage, isFalse);
    });

    test('the moderator preview is not a Pages authority', () async {
      await firestore.doc('users/me').set(<String, Object?>{
        'role': 'moderator',
      });
      final state = await service().watch().first;
      expect(state.hasPaidPremium, isFalse);
      expect(state.canCreatePage, isFalse);
    });

    test('a canonical grant still can, and an owner is past create', () async {
      await firestore.doc('vipGrants/me').set(<String, Object?>{
        'source': 'testerProgram',
        'expiresAt': null,
        'revoked': false,
      });
      expect((await service().watch().first).canCreatePage, isTrue);
      await paid();
      await firestore.doc('pages/me').set(<String, Object?>{
        'kind': 'business',
        'status': 'active',
      });
      final owner = await service().watch().first;
      expect(owner.ownPage, isNotNull);
      expect(owner.canCreatePage, isFalse);
    });
  });

  group('openCreatePageFlow gate', () {
    Future<void> open(WidgetTester tester, PageAccessState access) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          locale: const Locale('pl'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const ValueKey('open'),
                onPressed: () => openCreatePageFlow(
                  context,
                  accessStream: () => Stream.value(access),
                  screenBuilder: (_) =>
                      const Scaffold(body: Text('CREATE FORM')),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('paid Premium without a grant gets the form', (tester) async {
      await open(
        tester,
        const PageAccessState(
          resolved: true,
          hasVipGrant: false,
          hasPaidPremium: true,
          ownPage: null,
        ),
      );
      expect(find.text('CREATE FORM'), findsOneWidget);
      expect(find.byKey(const ValueKey('pages-upsell')), findsNothing);
    });

    testWidgets('neither grant nor Premium gets the honest upsell', (
      tester,
    ) async {
      await open(
        tester,
        const PageAccessState(
          resolved: true,
          hasVipGrant: false,
          ownPage: null,
        ),
      );
      expect(find.text('CREATE FORM'), findsNothing);
      expect(find.byKey(const ValueKey('pages-upsell')), findsOneWidget);
    });
  });
}
