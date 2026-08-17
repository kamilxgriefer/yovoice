import 'package:cloud_firestore/cloud_firestore.dart';

class PublicProfileShowcaseConsent {
  const PublicProfileShowcaseConsent({
    required this.showProfile,
    required this.showActivity,
  });

  const PublicProfileShowcaseConsent.hidden()
    : showProfile = false,
      showActivity = false;

  final bool showProfile;
  final bool showActivity;

  factory PublicProfileShowcaseConsent.fromData(Map<String, dynamic>? data) {
    if (data == null || data['schemaVersion'] != 1) {
      return const PublicProfileShowcaseConsent.hidden();
    }
    final showProfile = data['showProfileOnWebsite'] == true;
    return PublicProfileShowcaseConsent(
      showProfile: showProfile,
      showActivity: showProfile && data['showActivityOnWebsite'] == true,
    );
  }
}

class PublicShowcaseConsentService {
  PublicShowcaseConsentService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<PublicProfileShowcaseConsent> watchProfileConsent(String userId) {
    return _firestore
        .collection('marketingConsents')
        .doc(userId)
        .snapshots()
        .map(
          (snapshot) => PublicProfileShowcaseConsent.fromData(snapshot.data()),
        );
  }

  Future<void> setProfileConsent({
    required String userId,
    required bool showProfile,
    required bool showActivity,
  }) {
    final normalizedActivity = showProfile && showActivity;
    return _firestore.collection('marketingConsents').doc(userId).set({
      'schemaVersion': 1,
      'showProfileOnWebsite': showProfile,
      'showActivityOnWebsite': normalizedActivity,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<bool> watchClubConsent({
    required String clubId,
    required String ownerId,
  }) {
    return _firestore
        .collection('clubMarketingConsents')
        .doc(clubId)
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          return data?['schemaVersion'] == 1 &&
              data?['clubId'] == clubId &&
              data?['ownerId'] == ownerId &&
              data?['showOnWebsite'] == true;
        });
  }

  Future<void> setClubConsent({
    required String clubId,
    required String ownerId,
    required bool showOnWebsite,
  }) {
    return _firestore.collection('clubMarketingConsents').doc(clubId).set({
      'schemaVersion': 1,
      'clubId': clubId,
      'ownerId': ownerId,
      'showOnWebsite': showOnWebsite,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
