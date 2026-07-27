import 'package:cloud_firestore/cloud_firestore.dart';

enum ClubRole {
  owner,
  coOwner,
  admin,
  moderator,
  member,
  guest;

  static ClubRole fromValue(Object? value) {
    return switch (value) {
      'owner' => ClubRole.owner,
      'coOwner' => ClubRole.coOwner,
      'admin' => ClubRole.admin,
      'moderator' => ClubRole.moderator,
      'guest' => ClubRole.guest,
      _ => ClubRole.member,
    };
  }

  String get label => switch (this) {
    ClubRole.owner => 'Owner',
    ClubRole.coOwner => 'Co-owner',
    ClubRole.admin => 'Admin',
    ClubRole.moderator => 'Moderator',
    ClubRole.member => 'Member',
    ClubRole.guest => 'Guest',
  };

  int get power => switch (this) {
    ClubRole.owner => 60,
    ClubRole.coOwner => 50,
    ClubRole.admin => 40,
    ClubRole.moderator => 30,
    ClubRole.member => 20,
    ClubRole.guest => 10,
  };

  bool get canInvite => power >= ClubRole.moderator.power;
  bool get canRemoveMembers => power >= ClubRole.moderator.power;
  bool get canManageChannels => power >= ClubRole.admin.power;
  bool get canManageRoles => power >= ClubRole.coOwner.power;
  bool get canEditClub => power >= ClubRole.coOwner.power;
}

class ClubMember {
  const ClubMember({
    required this.userId,
    required this.displayName,
    required this.photoUrl,
    required this.role,
    required this.isOnline,
    required this.joinedAt,
    required this.invitedBy,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final ClubRole role;
  final bool isOnline;
  final DateTime? joinedAt;
  final String? invitedBy;

  String get initial {
    final normalized = displayName.trim();
    return normalized.isEmpty ? '?' : normalized[0].toUpperCase();
  }

  factory ClubMember.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('Club member ${document.id} does not contain data.');
    }

    return ClubMember(
      userId: data['userId'] as String? ?? document.id,
      displayName: (data['displayName'] as String?)?.trim() ?? 'YoVoice user',
      photoUrl: _nullableString(data['photoUrl']),
      role: ClubRole.fromValue(data['role']),
      isOnline: data['isOnline'] as bool? ?? false,
      joinedAt: _readDate(data['joinedAt']),
      invitedBy: _nullableString(data['invitedBy']),
    );
  }

  static String? _nullableString(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
