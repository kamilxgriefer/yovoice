import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/marketing/data/services/public_showcase_consent_service.dart';

void main() {
  test(
    'profile consent is exact and activity cannot outlive profile consent',
    () async {
      final firestore = FakeFirebaseFirestore();
      final service = PublicShowcaseConsentService(firestore: firestore);

      await service.setProfileConsent(
        userId: 'user-1',
        showProfile: false,
        showActivity: true,
      );

      final data = (await firestore.doc('marketingConsents/user-1').get())
          .data()!;
      expect(data.keys.toSet(), {
        'schemaVersion',
        'showProfileOnWebsite',
        'showActivityOnWebsite',
        'updatedAt',
      });
      expect(data['showProfileOnWebsite'], isFalse);
      expect(data['showActivityOnWebsite'], isFalse);
      expect(
        await service.watchProfileConsent('user-1').first,
        isA<PublicProfileShowcaseConsent>(),
      );
    },
  );

  test('club consent publishes only the explicit boolean preference', () async {
    final firestore = FakeFirebaseFirestore();
    final service = PublicShowcaseConsentService(firestore: firestore);

    await service.setClubConsent(
      clubId: 'club-1',
      ownerId: 'owner-1',
      showOnWebsite: true,
    );

    final data = (await firestore.doc('clubMarketingConsents/club-1').get())
        .data()!;
    expect(data.keys.toSet(), {
      'schemaVersion',
      'clubId',
      'ownerId',
      'showOnWebsite',
      'updatedAt',
    });
    expect(
      await service
          .watchClubConsent(clubId: 'club-1', ownerId: 'owner-1')
          .first,
      isTrue,
    );
    expect(
      await service
          .watchClubConsent(clubId: 'club-1', ownerId: 'new-owner')
          .first,
      isFalse,
      reason: 'an ownership transfer must not inherit marketing consent',
    );
  });
}
