import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/profile/data/models/user_profile.dart';

void main() {
  test(
    'creator audience visibility uses only the safe server projection',
    () async {
      final firestore = FakeFirebaseFirestore();
      final profile = firestore.collection('publicProfiles').doc('creator');
      await profile.set({
        'accountType': 'creator',
        'premiumIdentity': true,
        'creatorAgeVerified': true,
        'creatorAudienceEnabled': true,
        'followerCount': 91,
        'followingCount': 17,
      });

      final withoutProjection = UserProfile.fromFirestore(await profile.get());
      expect(withoutProjection.canExposeCreatorAudience, isFalse);
      expect(withoutProjection.followerCount, 0);
      expect(withoutProjection.followingCount, 0);

      await profile.update({'creatorAudienceVisible': true});
      final visible = UserProfile.fromFirestore(await profile.get());
      expect(visible.canExposeCreatorAudience, isTrue);
      expect(visible.followerCount, 91);
      expect(visible.followingCount, 17);
    },
  );

  test('friend projection carries the public gate and fails closed', () async {
    final firestore = FakeFirebaseFirestore();
    final profile = firestore.collection('publicProfiles').doc('friend');
    await profile.set({
      'displayName': 'Eligible Creator',
      'creatorAudienceVisible': true,
    });

    final visible = FriendUser.fromFirestore(await profile.get());
    expect(visible.canExposeCreatorAudience, isTrue);

    await profile.update({'creatorAudienceVisible': FieldValue.delete()});
    final legacy = FriendUser.fromFirestore(await profile.get());
    expect(legacy.canExposeCreatorAudience, isFalse);

    final malformed = FriendUser.fromMap(
      id: 'malformed',
      data: const {
        'displayName': 'Malformed Creator',
        'creatorAudienceVisible': 'true',
      },
    );
    expect(malformed.canExposeCreatorAudience, isFalse);
  });
}
