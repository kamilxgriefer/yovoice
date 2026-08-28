import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/premium/data/models/premium_billing_context.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/premium/data/services/premium_billing_service.dart';
import 'package:yovoice/features/premium/premium_gates.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';
import 'package:yovoice/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:yovoice/features/premium/presentation/screens/premium_screen.dart';
import 'package:yovoice/features/premium/presentation/widgets/premium_feature_gate.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';

const _uid = 'premium-user';

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
  const _FakeBilling();
  @override
  Future<PremiumBillingContext> getContext({String? countryCode}) async =>
      _billingContext;
  @override
  Future<Uri> createCheckout(PremiumPlan plan) async =>
      Uri.parse('https://checkout.stripe.com/test');
  @override
  Future<Uri> createPortal() async =>
      Uri.parse('https://billing.stripe.com/test');
}

MockFirebaseAuth _auth() => MockFirebaseAuth(
  signedIn: true,
  mockUser: MockUser(uid: _uid, email: 'p@yovoice.app'),
);

Future<void> _seedEntitlements(
  FakeFirebaseFirestore db, {
  required String status,
  required DateTime periodEnd,
  String plan = 'monthly',
  bool creatorEnabled = true,
  bool canCreateClubs = true,
  bool premiumIdentityEnabled = true,
  bool isPremium = true,
}) {
  return db.collection('entitlements').doc(_uid).set({
    'plan': plan,
    'status': status,
    'currentPeriodEnd': Timestamp.fromDate(periodEnd),
    'isPremium': isPremium,
    'creatorEnabled': creatorEnabled,
    'canCreateClubs': canCreateClubs,
    'premiumIdentityEnabled': premiumIdentityEnabled,
    'maxOwnedClubs': 3,
  });
}

Future<void> _seedProfile(
  FakeFirebaseFirestore db, {
  String role = 'user',
  bool banned = false,
  bool disabled = false,
  bool deleted = false,
  String status = 'active',
}) {
  return db.collection('users').doc(_uid).set({
    'role': role,
    'banned': banned,
    'disabled': disabled,
    'deleted': deleted,
    'status': status,
  });
}

class _SelectiveThrowingFirestore extends FakeFirebaseFirestore {
  _SelectiveThrowingFirestore(this.failingCollection);

  final String failingCollection;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    if (path == failingCollection) {
      throw StateError('$path is unavailable');
    }
    return super.collection(path);
  }
}

UserProfile _profile(AccountType accountType) => UserProfile(
  uid: _uid,
  email: 'p@yovoice.app',
  displayName: 'Premium Tester',
  username: 'premium',
  bio: '',
  country: '',
  nativeLanguage: '',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  website: '',
  accountType: accountType,
  friendCount: 0,
  followerCount: 0,
  followingCount: 0,
  roomCount: 0,
  communityCount: 0,
  voiceMinutes: 0,
  messageCount: 0,
  activeDays: 0,
  momentCount: 0,
  reactionCount: 0,
  hostMinutes: 0,
  selectedTitleId: null,
  unlockedTitleIds: const [],
  unlockedTitleTimestamps: const {},
  createdAt: DateTime(2026),
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

  group('SubscriptionEntitlements mapping', () {
    test('missing document means the free product, nothing premium', () async {
      final db = FakeFirebaseFirestore();
      final service = EntitlementService(firestore: db, auth: _auth());

      final entitlements = await service.currentEntitlements();
      expect(entitlements.isPremium, isFalse);
      expect(entitlements.creatorEnabled, isFalse);
      expect(entitlements.canCreateClubs, isFalse);
      expect(entitlements.premiumIdentityEnabled, isFalse);
      expect(entitlements.maxOwnedClubs, 0);
      expect(entitlements.plan, PremiumPlan.none);
    });

    test('active subscription with future period end is premium', () async {
      final db = FakeFirebaseFirestore();
      await _seedEntitlements(
        db,
        status: 'active',
        periodEnd: DateTime.now().add(const Duration(days: 20)),
      );

      final entitlements = await EntitlementService(
        firestore: db,
        auth: _auth(),
      ).currentEntitlements();

      expect(entitlements.isPremium, isTrue);
      expect(entitlements.creatorEnabled, isTrue);
      expect(entitlements.canCreateClubs, isTrue);
      expect(entitlements.hasPremiumIdentity, isTrue);
      expect(entitlements.canUseCreator, isTrue);
      expect(entitlements.canUseClubs, isTrue);
      expect(entitlements.maxOwnedClubs, 3);
      expect(entitlements.plan, PremiumPlan.monthly);
    });

    test(
      'missing or false canonical isPremium fails paid access closed',
      () async {
        for (final value in <bool?>[null, false]) {
          final db = FakeFirebaseFirestore();
          await db.collection('entitlements').doc(_uid).set({
            'plan': 'monthly',
            'status': 'active',
            'currentPeriodEnd': Timestamp.fromDate(
              DateTime.now().add(const Duration(days: 20)),
            ),
            'isPremium': ?value,
            'creatorEnabled': true,
            'canCreateClubs': true,
            'premiumIdentityEnabled': true,
            'maxOwnedClubs': 3,
          });

          final entitlements = await EntitlementService(
            firestore: db,
            auth: _auth(),
          ).currentEntitlements();

          expect(entitlements.isPremium, isFalse, reason: 'isPremium=$value');
          expect(entitlements.hasPremiumIdentity, isFalse);
          expect(entitlements.canUseCreator, isFalse);
          expect(entitlements.canUseClubs, isFalse);
        }
      },
    );

    test(
      'active status without the Premium identity grants no paid tools',
      () async {
        final db = FakeFirebaseFirestore();
        await _seedEntitlements(
          db,
          status: 'active',
          periodEnd: DateTime.now().add(const Duration(days: 20)),
          premiumIdentityEnabled: false,
        );

        final entitlements = await EntitlementService(
          firestore: db,
          auth: _auth(),
        ).currentEntitlements();

        expect(entitlements.isPremium, isTrue);
        expect(entitlements.hasPremiumIdentity, isFalse);
        expect(entitlements.canUseCreator, isFalse);
        expect(entitlements.canUseClubs, isFalse);
      },
    );

    test(
      'missing capability flags fail closed for a legacy active document',
      () async {
        final db = FakeFirebaseFirestore();
        await db.collection('entitlements').doc(_uid).set({
          'plan': 'monthly',
          'status': 'active',
          'isPremium': true,
          'currentPeriodEnd': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 20)),
          ),
        });

        final entitlements = await EntitlementService(
          firestore: db,
          auth: _auth(),
        ).currentEntitlements();

        expect(entitlements.isPremium, isTrue);
        expect(entitlements.hasPremiumIdentity, isFalse);
        expect(entitlements.canUseCreator, isFalse);
        expect(entitlements.canUseClubs, isFalse);
      },
    );

    test('EXPIRED subscription is free even if the server flags are stale — '
        'the client recomputes validity from currentPeriodEnd', () async {
      final db = FakeFirebaseFirestore();
      await _seedEntitlements(
        db,
        status: 'active', // server sweep hasn't run yet
        periodEnd: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      final entitlements = await EntitlementService(
        firestore: db,
        auth: _auth(),
      ).currentEntitlements();

      expect(entitlements.isPremium, isFalse);
      expect(entitlements.creatorEnabled, isFalse);
      expect(entitlements.canCreateClubs, isFalse);
      expect(entitlements.maxOwnedClubs, 0);
    });

    test(
      'grace period keeps premium on and reports the billing issue',
      () async {
        final db = FakeFirebaseFirestore();
        await _seedEntitlements(
          db,
          status: 'grace',
          periodEnd: DateTime.now().add(const Duration(days: 3)),
          plan: 'yearly',
        );

        final entitlements = await EntitlementService(
          firestore: db,
          auth: _auth(),
        ).currentEntitlements();

        expect(entitlements.isPremium, isTrue);
        expect(entitlements.inGracePeriod, isTrue);
        expect(entitlements.plan, PremiumPlan.yearly);
      },
    );

    test('two service instances share one stream per uid', () async {
      final db = FakeFirebaseFirestore();
      final a = EntitlementService(firestore: db, auth: _auth());
      final b = EntitlementService(firestore: db, auth: _auth());
      expect(
        identical(a.watchCurrentEntitlements(), b.watchCurrentEntitlements()),
        isTrue,
      );
    });

    for (final role in const ['moderator', 'superModerator']) {
      test('$role gets feature preview without a fake subscription', () async {
        final db = FakeFirebaseFirestore();
        await _seedProfile(db, role: role);

        final entitlements = await EntitlementService(
          firestore: db,
          auth: _auth(),
        ).currentEntitlements();

        expect(entitlements.hasModeratorBenefits, isTrue);
        expect(entitlements.hasPremiumIdentity, isTrue);
        expect(entitlements.canUseCreator, isTrue);
        expect(entitlements.canUseClubs, isTrue);

        // Billing truth stays untouched: no plan, renewal or paid flags are
        // fabricated by the complimentary role benefit.
        expect(entitlements.isPremium, isFalse);
        expect(entitlements.plan, PremiumPlan.none);
        expect(entitlements.currentPeriodEnd, isNull);
        expect(entitlements.creatorEnabled, isFalse);
        expect(entitlements.canCreateClubs, isFalse);
        expect(entitlements.premiumIdentityEnabled, isFalse);
        expect(entitlements.maxOwnedClubs, 0);
      });
    }

    for (final role in const [
      'user',
      'guideMaster',
      'support',
      'auditor',
      'superAdmin',
      'admin',
      'unknown',
    ]) {
      test('$role does not inherit moderator Premium benefits', () async {
        final db = FakeFirebaseFirestore();
        await _seedProfile(db, role: role);

        final entitlements = await EntitlementService(
          firestore: db,
          auth: _auth(),
        ).currentEntitlements();

        expect(entitlements.hasModeratorBenefits, isFalse);
        expect(entitlements.hasPremiumIdentity, isFalse);
        expect(entitlements.canUseCreator, isFalse);
        expect(entitlements.canUseClubs, isFalse);
      });
    }

    for (final inactive in <String, Map<String, Object>>{
      'banned': {'banned': true},
      'disabled': {'disabled': true},
      'deleted flag': {'deleted': true},
      'deleted status': {'status': 'deleted'},
    }.entries) {
      test('a ${inactive.key} moderator gets no role benefit', () async {
        final db = FakeFirebaseFirestore();
        await _seedProfile(
          db,
          role: 'moderator',
          banned: inactive.value['banned'] == true,
          disabled: inactive.value['disabled'] == true,
          deleted: inactive.value['deleted'] == true,
          status: inactive.value['status'] as String? ?? 'active',
        );

        final entitlements = await EntitlementService(
          firestore: db,
          auth: _auth(),
        ).currentEntitlements();

        expect(entitlements.hasModeratorBenefits, isFalse);
        expect(entitlements.canUseCreator, isFalse);
        expect(entitlements.canUseClubs, isFalse);
      });
    }

    test('role demotion removes the preview reactively', () async {
      final db = FakeFirebaseFirestore();
      await _seedProfile(db, role: 'moderator');
      final iterator = StreamIterator(
        EntitlementService(
          firestore: db,
          auth: _auth(),
        ).watchCurrentEntitlements(),
      );

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.hasModeratorBenefits, isTrue);

      await db.collection('users').doc(_uid).update({'role': 'user'});
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.hasModeratorBenefits, isFalse);
      expect(iterator.current.canUseCreator, isFalse);
      expect(iterator.current.canUseClubs, isFalse);
      await iterator.cancel();
    });

    test(
      'role demotion removes only the overlay and preserves paid access',
      () async {
        final db = FakeFirebaseFirestore();
        await _seedProfile(db, role: 'moderator');
        await _seedEntitlements(
          db,
          status: 'active',
          periodEnd: DateTime.now().add(const Duration(days: 20)),
        );
        final iterator = StreamIterator(
          EntitlementService(
            firestore: db,
            auth: _auth(),
          ).watchCurrentEntitlements(),
        );

        expect(await iterator.moveNext(), isTrue);
        expect(iterator.current.hasModeratorBenefits, isTrue);
        expect(iterator.current.isPremium, isTrue);

        await db.collection('users').doc(_uid).update({'role': 'user'});
        expect(await iterator.moveNext(), isTrue);
        expect(iterator.current.hasModeratorBenefits, isFalse);
        expect(iterator.current.isPremium, isTrue);
        expect(iterator.current.canUseCreator, isTrue);
        expect(iterator.current.canUseClubs, isTrue);
        await iterator.cancel();
      },
    );

    test(
      'an unreadable role source preserves independently valid paid access',
      () async {
        final db = _SelectiveThrowingFirestore('users');
        await _seedEntitlements(
          db,
          status: 'active',
          periodEnd: DateTime.now().add(const Duration(days: 20)),
        );

        final entitlements = await EntitlementService(
          firestore: db,
          auth: _auth(),
        ).currentEntitlements();

        expect(entitlements.isPremium, isTrue);
        expect(entitlements.hasModeratorBenefits, isFalse);
        expect(entitlements.canUseCreator, isTrue);
        expect(entitlements.canUseClubs, isTrue);
      },
    );

    test(
      'an unreadable billing source preserves verified moderator access',
      () async {
        final db = _SelectiveThrowingFirestore('entitlements');
        await _seedProfile(db, role: 'superModerator');

        final entitlements = await EntitlementService(
          firestore: db,
          auth: _auth(),
        ).currentEntitlements();

        expect(entitlements.isPremium, isFalse);
        expect(entitlements.plan, PremiumPlan.none);
        expect(entitlements.hasModeratorBenefits, isTrue);
        expect(entitlements.canUseCreator, isTrue);
        expect(entitlements.canUseClubs, isTrue);
      },
    );

    test('the live stream separates billing and role read failures', () async {
      final roleFailure = _SelectiveThrowingFirestore('users');
      await _seedEntitlements(
        roleFailure,
        status: 'active',
        periodEnd: DateTime.now().add(const Duration(days: 20)),
      );
      final paid = await EntitlementService(
        firestore: roleFailure,
        auth: _auth(),
      ).watchCurrentEntitlements().first;
      expect(paid.isPremium, isTrue);
      expect(paid.hasModeratorBenefits, isFalse);
      expect(paid.canUseCreator, isTrue);

      EntitlementService.resetCache();
      final billingFailure = _SelectiveThrowingFirestore('entitlements');
      await _seedProfile(billingFailure, role: 'superModerator');
      final moderator = await EntitlementService(
        firestore: billingFailure,
        auth: _auth(),
      ).watchCurrentEntitlements().first;
      expect(moderator.isPremium, isFalse);
      expect(moderator.hasModeratorBenefits, isTrue);
      expect(moderator.canUseCreator, isTrue);
      expect(moderator.canUseClubs, isTrue);
    });
  });

  group('Premium presentation and plans', () {
    testWidgets('free member sees the presentation and Check plans leads '
        'to the real plans screen', (tester) async {
      final db = FakeFirebaseFirestore();
      final auth = _auth();
      await tester.pumpWidget(
        MaterialApp(
          home: PremiumScreen(
            entitlementService: EntitlementService(firestore: db, auth: auth),
            profileService: ProfileService(firestore: db, auth: auth),
            billingService: const _FakeBilling(),
          ),
        ),
      );
      // Fixed pumps only: the premium hero ring animates forever, so
      // pumpAndSettle would never settle.
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('More room\nfor your voice.'), findsOneWidget);
      expect(find.text('YO VOICE PREMIUM'), findsOneWidget);

      // The benefit cards and CTA sit below the fold.
      await tester.scrollUntilVisible(
        find.text('Check plans'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('Become a Creator'), findsOneWidget);
      expect(find.text('Create your own Clubs'), findsOneWidget);
      expect(find.text('Stand out'), findsOneWidget);
      // No pricing on the presentation — that's the plans screen's job.
      expect(find.text('19,99 zł'), findsNothing);

      await tester.tap(find.text('Check plans'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Choose your plan'), findsOneWidget);
      expect(find.text('19,99 zł'), findsOneWidget);
      expect(find.text('199,99 zł'), findsOneWidget);
      expect(find.text('Best value'), findsOneWidget);
      expect(find.text('16,67 zł / month'), findsOneWidget);
      expect(find.text('Save 17%'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Everything Premium includes:'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pump();
      expect(find.text('Everything Premium includes:'), findsOneWidget);
    });

    testWidgets('active premium member sees status, not the paywall', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      final auth = _auth();
      await _seedEntitlements(
        db,
        status: 'active',
        periodEnd: DateTime.now().add(const Duration(days: 200)),
        plan: 'yearly',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PremiumScreen(
            entitlementService: EntitlementService(firestore: db, auth: auth),
            profileService: ProfileService(firestore: db, auth: auth),
            billingService: const _FakeBilling(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.text('You have YO Voice Premium'), findsOneWidget);
      expect(find.textContaining('Yearly plan'), findsOneWidget);
      expect(find.text('19,99 zł'), findsNothing);
      expect(find.text('Check plans'), findsNothing);
    });
  });

  group('Creator gating in Edit profile', () {
    Future<void> pumpEditProfile(
      WidgetTester tester, {
      required FakeFirebaseFirestore db,
      AccountType accountType = AccountType.personal,
    }) async {
      final auth = _auth();
      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            profile: _profile(accountType),
            service: ProfileService(firestore: db, auth: auth),
            entitlements: EntitlementService(firestore: db, auth: auth),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Account type lives below the fold of the lazily-built form.
      await tester.scrollUntilVisible(
        find.text('Account type'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('free member tapping Creator gets the Premium upsell, '
        'selection stays Personal', (tester) async {
      final db = FakeFirebaseFirestore();
      await pumpEditProfile(tester, db: db);

      expect(
        find.byKey(const ValueKey('creator-premium-lock')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('creator-premium-required')),
        findsOneWidget,
      );

      await tester.tap(find.text('Creator'));
      await tester.pumpAndSettle();

      expect(
        find.text('Creator is included with YO Voice Premium'),
        findsOneWidget,
      );
      expect(find.text('Explore Premium'), findsOneWidget);
    });

    testWidgets('premium member can select Creator without an upsell', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await _seedEntitlements(
        db,
        status: 'active',
        periodEnd: DateTime.now().add(const Duration(days: 20)),
      );
      await pumpEditProfile(tester, db: db);

      expect(find.byKey(const ValueKey('creator-premium-lock')), findsNothing);

      await tester.tap(find.text('Creator'));
      await tester.pumpAndSettle();

      expect(
        find.text('Creator is included with YO Voice Premium'),
        findsNothing,
      );
    });

    testWidgets(
      'Save re-checks Premium if it expires after Creator selection',
      (tester) async {
        final db = FakeFirebaseFirestore();
        await _seedEntitlements(
          db,
          status: 'active',
          periodEnd: DateTime.now().add(const Duration(days: 20)),
        );
        await pumpEditProfile(tester, db: db);

        await tester.tap(find.text('Creator'));
        await tester.pump();
        await _seedEntitlements(
          db,
          status: 'expired',
          periodEnd: DateTime.now().subtract(const Duration(minutes: 1)),
        );
        await tester.pump(const Duration(milliseconds: 50));

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(
          find.text('Creator is included with YO Voice Premium'),
          findsOneWidget,
        );
        final profile = await db.collection('users').doc(_uid).get();
        expect(profile.data()?['accountType'], isNot('creator'));
      },
    );

    testWidgets('expired Creator copy requires explicit reactivation', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await _seedEntitlements(
        db,
        status: 'expired',
        periodEnd: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      await pumpEditProfile(tester, db: db, accountType: AccountType.creator);

      expect(find.textContaining('reactivate Creator'), findsOneWidget);
      expect(find.textContaining('unlock again with Premium'), findsNothing);
    });
  });

  group('Premium destination boundary', () {
    Widget guarded({
      required FakeFirebaseFirestore db,
      required PremiumFeature feature,
      DateTime Function() now = DateTime.now,
    }) {
      return MaterialApp(
        home: PremiumFeatureGate(
          feature: feature,
          entitlementService: EntitlementService(firestore: db, auth: _auth()),
          now: now,
          child: const Scaffold(body: Text('Protected destination content')),
        ),
      );
    }

    testWidgets('free member cannot mount Creator Studio directly', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(
        guarded(db: db, feature: PremiumFeature.creatorStudio),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Creator Studio requires Premium'), findsOneWidget);
      expect(find.text('Protected destination content'), findsNothing);
      expect(
        find.byKey(const ValueKey('premium-destination-lock')),
        findsOneWidget,
      );
    });

    testWidgets('open Clubs locks exactly when Premium expires, without a '
        'new Firestore snapshot', (tester) async {
      final db = FakeFirebaseFirestore();
      final periodEnd = DateTime.now().add(const Duration(days: 20));
      var clock = periodEnd.subtract(const Duration(seconds: 1));
      await _seedEntitlements(db, status: 'active', periodEnd: periodEnd);
      await tester.pumpWidget(
        guarded(db: db, feature: PremiumFeature.clubs, now: () => clock),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Protected destination content'), findsOneWidget);
      expect(find.text('Clubs requires Premium'), findsNothing);

      clock = periodEnd.add(const Duration(milliseconds: 1));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Protected destination content'), findsNothing);
      expect(find.text('Clubs requires Premium'), findsOneWidget);
    });

    testWidgets('paid expiry does not evict an active moderator, but demotion '
        'does', (tester) async {
      final db = FakeFirebaseFirestore();
      final periodEnd = DateTime.now().add(const Duration(days: 20));
      var clock = periodEnd.subtract(const Duration(seconds: 1));
      await _seedEntitlements(db, status: 'active', periodEnd: periodEnd);
      await _seedProfile(db, role: 'moderator');
      await tester.pumpWidget(
        guarded(
          db: db,
          feature: PremiumFeature.creatorStudio,
          now: () => clock,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Protected destination content'), findsOneWidget);

      clock = periodEnd.add(const Duration(milliseconds: 1));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Protected destination content'), findsOneWidget);
      expect(find.text('Creator Studio requires Premium'), findsNothing);

      await db.collection('users').doc(_uid).update({'role': 'user'});
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Protected destination content'), findsNothing);
      expect(find.text('Creator Studio requires Premium'), findsOneWidget);
    });
  });
}

// Appended: paywall rendering coverage (free + active states).
// ignore_for_file: directives_ordering
