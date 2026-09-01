import 'package:cloud_firestore/cloud_firestore.dart';

/// The four things a family check-in can say. Deliberately a closed set,
/// mirrored by `firestore.rules`, which rejects any other value.
///
/// These are ORDINARY STATUS UPDATES. They are not an emergency feature,
/// they summon nobody, and they carry no location of any kind — the rules
/// refuse a document containing `latitude`, `longitude` or `location`
/// outright rather than quietly dropping it.
enum FamilyCheckInStatus {
  home('home', "I'm home"),
  onMyWay('onMyWay', 'On my way'),
  allGood('allGood', 'All good'),
  callMe('callMe', 'Call me');

  const FamilyCheckInStatus(this.value, this.label);

  /// The stored value. Never the label — copy can change, the four
  /// accepted values cannot without a rules change.
  final String value;
  final String label;

  static FamilyCheckInStatus? fromValue(Object? value) {
    for (final status in FamilyCheckInStatus.values) {
      if (status.value == value) return status;
    }
    return null;
  }
}

class FamilyCheckIn {
  const FamilyCheckIn({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.photoUrl,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String displayName;
  final String? photoUrl;

  /// Null when the stored value is not one this build knows — an older or
  /// newer client's value. The row is then simply not rendered, rather
  /// than shown as something it might not be.
  final FamilyCheckInStatus? status;

  /// Server time, not device time: a check-in's "when" must not be
  /// something the sending phone can decide.
  final DateTime? createdAt;

  factory FamilyCheckIn.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return FamilyCheckIn(
      id: document.id,
      userId: data['userId'] as String? ?? '',
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? (data['displayName'] as String).trim()
          : 'YO Voice user',
      photoUrl: null,
      status: FamilyCheckInStatus.fromValue(data['status']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
