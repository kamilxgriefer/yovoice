import 'package:cloud_firestore/cloud_firestore.dart';

class ClubInvite {
  const ClubInvite({
    required this.clubId,
    required this.clubName,
    required this.clubAvatarUrl,
    required this.inviteeId,
    required this.inviterId,
    required this.inviterName,
    required this.createdAt,
  });

  final String clubId;
  final String clubName;
  final String? clubAvatarUrl;
  final String inviteeId;
  final String inviterId;
  final String inviterName;
  final DateTime? createdAt;

  factory ClubInvite.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return ClubInvite(
      clubId:
          data['clubId'] as String? ??
          document.reference.parent.parent?.id ??
          '',
      clubName: (data['clubName'] as String?)?.trim() ?? 'YO Voice club',
      clubAvatarUrl: _nullable(data['clubAvatarUrl']),
      inviteeId: data['inviteeId'] as String? ?? document.id,
      inviterId: data['inviterId'] as String? ?? '',
      inviterName: (data['inviterName'] as String?)?.trim() ?? 'YO Voice user',
      createdAt: _date(data['createdAt']),
    );
  }

  static String? _nullable(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
