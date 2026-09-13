import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/creator/data/services/creator_audience_service.dart';
import 'package:yovoice/features/creator/presentation/widgets/creator_audience_setting.dart';
import 'package:yovoice/features/premium/data/models/subscription_entitlements.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';

UserProfile profile({
  AccountType type = AccountType.creator,
  bool premium = true,
  bool ageVerified = true,
  bool audienceEnabled = false,
}) => UserProfile(
  uid: 'creator',
  email: 'creator@example.com',
  displayName: 'Creator',
  username: 'creator',
  bio: '',
  country: '',
  nativeLanguage: '',
  spokenLanguages: const [],
  learningLanguages: const [],
  photoUrl: null,
  bannerUrl: null,
  premiumIdentity: premium,
  creatorAgeVerified: ageVerified,
  creatorAudienceEnabled: audienceEnabled,
  website: '',
  accountType: type,
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

SubscriptionEntitlements paidCreatorEntitlements({
  bool moderatorPreview = false,
}) => SubscriptionEntitlements(
  plan: PremiumPlan.monthly,
  status: 'active',
  currentPeriodEnd: DateTime(2027),
  isPremium: true,
  creatorEnabled: true,
  canCreateClubs: false,
  premiumIdentityEnabled: true,
  maxOwnedClubs: 0,
  hasModeratorBenefits: moderatorPreview,
);

void main() {
  test('the service sends the exact callable contract', () async {
    String? callable;
    Map<String, Object?>? payload;
    final service = CreatorAudienceService(
      mutationInvoker: (name, data) async {
        callable = name;
        payload = data;
        return const <Object?, Object?>{
          'creatorAudienceEnabled': true,
          'creatorAudienceVisible': true,
          'changed': true,
        };
      },
    );

    final result = await service.setEnabled(
      enabled: true,
      requestId: 'audience_request_001',
    );

    expect(callable, 'setCreatorAudienceEnabled');
    expect(payload, {'enabled': true, 'requestId': 'audience_request_001'});
    expect(result.enabled, isTrue);
    expect(result.visible, isTrue);
    expect(result.changed, isTrue);
  });

  test(
    'age confirmation sends only a calendar date and durable request id',
    () async {
      String? callable;
      Map<String, Object?>? payload;
      final service = CreatorAudienceService(
        mutationInvoker: (name, data) async {
          callable = name;
          payload = data;
          return const <Object?, Object?>{
            'creatorAgeVerified': true,
            'changed': true,
          };
        },
      );

      final result = await service.confirmAdultEligibility(
        birthDate: DateTime(1998, 4, 9, 23, 45),
        requestId: 'age_confirmation_001',
      );

      expect(callable, 'confirmCreatorAdultEligibility');
      expect(payload, {
        'birthDate': '1998-04-09',
        'requestId': 'age_confirmation_001',
      });
      expect(result.verified, isTrue);
      expect(result.changed, isTrue);
    },
  );

  test(
    'the public projection fails closed and owns its visible counts',
    () async {
      final firestore = FakeFirebaseFirestore();
      final document = firestore.collection('publicProfiles').doc('creator');
      await document.set({
        'creatorAudienceVisible': false,
        'followerCount': 91,
        'followingCount': 72,
      });
      final service = CreatorAudienceService(firestore: firestore);

      final hidden = await service.watchPublicProjection('creator').first;
      expect(hidden.visible, isFalse);
      expect(hidden.followerCount, 0);
      expect(hidden.followingCount, 0);

      await document.update({
        'creatorAudienceVisible': true,
        'followerCount': 12,
        'followingCount': 8,
      });
      final visible = await service.watchPublicProjection('creator').first;
      expect(visible.visible, isTrue);
      expect(visible.followerCount, 12);
      expect(visible.followingCount, 8);
    },
  );

  test('server entitlements, not a decorative VIP field, gate enabling', () {
    const free = SubscriptionEntitlements.free;
    final paid = paidCreatorEntitlements();
    expect(
      creatorAudienceSettingIsAvailable(profile(), free),
      isFalse,
      reason: 'A stale premiumIdentity flag is not billing authority.',
    );
    expect(
      creatorAudienceSettingIsAvailable(profile(premium: false), paid),
      isTrue,
      reason: 'The server-written paid entitlement is the UI authority.',
    );
    expect(creatorAudienceCanEnable(profile(premium: false), paid), isTrue);
    expect(
      creatorAudienceCanEnable(profile(ageVerified: false), paid),
      isFalse,
      reason: 'Age verification is required before the public opt-in.',
    );
    expect(
      creatorAudienceCanConfirmAge(profile(ageVerified: false), paid),
      isTrue,
    );
    expect(
      creatorAudienceSettingIsAvailable(profile(ageVerified: false), paid),
      isTrue,
      reason: 'A paid Creator must see the self-service age step.',
    );
    expect(
      creatorAudienceCanEnable(
        profile(),
        SubscriptionEntitlements.free.withModeratorBenefits(true),
      ),
      isFalse,
      reason: 'Moderator preview is excluded from Creator Audience.',
    );
    expect(
      creatorAudienceSettingIsAvailable(
        profile(premium: false, ageVerified: false, audienceEnabled: true),
        free,
      ),
      isTrue,
      reason: 'A lapsed Creator must retain the privacy opt-out.',
    );
    expect(
      creatorAudienceCanEnable(profile(type: AccountType.personal), paid),
      isFalse,
    );
    expect(
      creatorAudienceCanEnable(profile(type: AccountType.official), paid),
      isFalse,
    );
  });

  testWidgets('age confirmation unlocks the Follow opt-in in one flow', (
    tester,
  ) async {
    final calls = <String>[];
    final service = CreatorAudienceService(
      requestIdFactory: () => 'age_confirmation_002',
      mutationInvoker: (name, payload) async {
        calls.add(name);
        if (name == 'confirmCreatorAdultEligibility') {
          expect(payload['birthDate'], '1995-06-15');
          return const <Object?, Object?>{
            'creatorAgeVerified': true,
            'changed': true,
          };
        }
        return const <Object?, Object?>{
          'creatorAudienceEnabled': true,
          'creatorAudienceVisible': true,
          'changed': true,
        };
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreatorAudienceSetting(
            ownerEnabled: false,
            publicVisible: false,
            canEnable: false,
            ageVerified: false,
            canConfirmAge: true,
            birthDateSelector: (_) async => DateTime(1995, 6, 15),
            service: service,
          ),
        ),
      ),
    );

    final toggle = find.byKey(const ValueKey('creator-audience-switch'));
    expect(tester.widget<Switch>(toggle).onChanged, isNull);
    expect(
      find.byKey(const ValueKey('confirm-creator-age-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('confirm-creator-age-button')));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Age confirmed. You can now enable Follow.'),
      findsOneWidget,
    );
    expect(tester.widget<Switch>(toggle).onChanged, isNotNull);
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump();
    expect(calls, [
      'confirmCreatorAdultEligibility',
      'setCreatorAudienceEnabled',
    ]);
    expect(find.text('Your creator audience is now visible.'), findsOneWidget);
  });

  testWidgets('an ambiguous age retry reuses its date and request id', (
    tester,
  ) async {
    var requestIdsCreated = 0;
    var dateSelections = 0;
    var attempts = 0;
    final payloads = <Map<String, Object?>>[];
    final service = CreatorAudienceService(
      requestIdFactory: () {
        requestIdsCreated += 1;
        return 'age_confirmation_retry';
      },
      mutationInvoker: (_, payload) async {
        payloads.add(Map<String, Object?>.from(payload));
        attempts += 1;
        if (attempts == 1) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'network',
          );
        }
        return const <Object?, Object?>{
          'creatorAgeVerified': true,
          'changed': true,
        };
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreatorAudienceSetting(
            ownerEnabled: false,
            publicVisible: false,
            canEnable: false,
            ageVerified: false,
            canConfirmAge: true,
            birthDateSelector: (_) async {
              dateSelections += 1;
              return DateTime(1994, 3, 2);
            },
            service: service,
          ),
        ),
      ),
    );

    final button = find.byKey(const ValueKey('confirm-creator-age-button'));
    await tester.tap(button);
    await tester.pump();
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    await tester.pump();

    expect(requestIdsCreated, 1);
    expect(dateSelections, 1);
    expect(payloads, [
      {'birthDate': '1994-03-02', 'requestId': 'age_confirmation_retry'},
      {'birthDate': '1994-03-02', 'requestId': 'age_confirmation_retry'},
    ]);
  });

  testWidgets('a failed retry reuses its durable request id', (tester) async {
    final payloads = <Map<String, Object?>>[];
    var requestIdsCreated = 0;
    var attempts = 0;
    final service = CreatorAudienceService(
      requestIdFactory: () {
        requestIdsCreated += 1;
        return 'audience_request_001';
      },
      mutationInvoker: (_, payload) async {
        payloads.add(Map<String, Object?>.from(payload));
        attempts += 1;
        if (attempts == 1) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'network',
          );
        }
        return const <Object?, Object?>{
          'creatorAudienceEnabled': true,
          'creatorAudienceVisible': true,
          'changed': true,
        };
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreatorAudienceSetting(
            ownerEnabled: false,
            publicVisible: false,
            canEnable: true,
            service: service,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('creator-audience-switch')));
    await tester.pump();
    await tester.pump();
    final feedback = find.byKey(const ValueKey('creator-audience-feedback'));
    expect(feedback, findsOneWidget);
    expect(tester.widget<Text>(feedback).data, isNot(contains('age')));

    await tester.tap(find.byKey(const ValueKey('creator-audience-switch')));
    await tester.pump();
    await tester.pump();

    expect(requestIdsCreated, 1);
    expect(payloads, [
      {'enabled': true, 'requestId': 'audience_request_001'},
      {'enabled': true, 'requestId': 'audience_request_001'},
    ]);
    expect(find.text('Your creator audience is now visible.'), findsOneWidget);
  });

  testWidgets('a lapsed Creator can opt out but cannot opt back in', (
    tester,
  ) async {
    final payloads = <Map<String, Object?>>[];
    final service = CreatorAudienceService(
      requestIdFactory: () => 'audience_request_002',
      mutationInvoker: (_, payload) async {
        payloads.add(Map<String, Object?>.from(payload));
        return const <Object?, Object?>{
          'creatorAudienceEnabled': false,
          'creatorAudienceVisible': false,
          'changed': true,
        };
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreatorAudienceSetting(
            ownerEnabled: true,
            publicVisible: true,
            canEnable: false,
            service: service,
          ),
        ),
      ),
    );

    final toggle = find.byKey(const ValueKey('creator-audience-switch'));
    expect(tester.widget<Switch>(toggle).onChanged, isNotNull);
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump();

    expect(payloads, [
      {'enabled': false, 'requestId': 'audience_request_002'},
    ]);
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(tester.widget<Switch>(toggle).onChanged, isNull);
  });
}
