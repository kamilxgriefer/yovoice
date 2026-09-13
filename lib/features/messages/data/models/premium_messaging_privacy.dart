import 'package:cloud_firestore/cloud_firestore.dart';

enum PremiumMessagingPrivacyPreference {
  hideReadReceipts('hideReadReceipts'),
  hideTyping('hideTyping');

  const PremiumMessagingPrivacyPreference(this.storageValue);

  final String storageValue;
}

class PremiumMessagingPrivacy {
  const PremiumMessagingPrivacy({
    required this.hideReadReceipts,
    required this.hideTyping,
  });

  static const disabled = PremiumMessagingPrivacy(
    hideReadReceipts: false,
    hideTyping: false,
  );

  /// Matches the backend's fail-safe response to a malformed server-owned
  /// projection while a paid entitlement is active.
  static const privacySafeHidden = PremiumMessagingPrivacy(
    hideReadReceipts: true,
    hideTyping: true,
  );

  final bool hideReadReceipts;
  final bool hideTyping;

  factory PremiumMessagingPrivacy.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => PremiumMessagingPrivacy.fromMap(snapshot.data(), ownerId: snapshot.id);

  factory PremiumMessagingPrivacy.fromMap(
    Map<String, dynamic>? data, {
    required String ownerId,
  }) {
    if (data == null) return disabled;
    final keys = data.keys.toSet();
    const expected = <String>{
      'schemaVersion',
      'ownerId',
      'hideReadReceipts',
      'hideTyping',
      'updatedAt',
    };
    final canonical =
        keys.length == expected.length &&
        keys.containsAll(expected) &&
        data['schemaVersion'] == 1 &&
        data['ownerId'] == ownerId &&
        data['hideReadReceipts'] is bool &&
        data['hideTyping'] is bool &&
        data['updatedAt'] is Timestamp;
    if (!canonical) {
      throw const FormatException(
        'Malformed Premium messaging privacy projection.',
      );
    }
    return PremiumMessagingPrivacy(
      hideReadReceipts: data['hideReadReceipts'] as bool,
      hideTyping: data['hideTyping'] as bool,
    );
  }

  bool valueFor(PremiumMessagingPrivacyPreference preference) =>
      switch (preference) {
        PremiumMessagingPrivacyPreference.hideReadReceipts => hideReadReceipts,
        PremiumMessagingPrivacyPreference.hideTyping => hideTyping,
      };
}
