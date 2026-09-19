import 'package:cloud_firestore/cloud_firestore.dart';

import 'server_member_role.dart';

/// A member row displayed inside server management.
///
/// The callable remains the authority for every role, removal and ban change;
/// this model only describes the roster the signed-in member may read.
class ServerMember {
  const ServerMember({
    required this.id,
    required this.displayName,
    required this.role,
    this.photoUrl,
    this.isOnline = false,
    this.isBanned = false,
    this.authorizationRevision = 0,
    this.joinedAt,
  });

  final String id;
  final String displayName;
  final String? photoUrl;
  final ServerMemberRole role;
  final bool isOnline;
  final bool isBanned;
  final int authorizationRevision;
  final DateTime? joinedAt;

  factory ServerMember.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) throw const FormatException('Member is unavailable.');
    final id = _string(data['userId']);
    final name = _string(data['displayName']);
    final role = ServerMemberRole.parse(data['role']);
    final authorizationRevision = data['authorizationRevision'];
    if (id == null ||
        id != document.id ||
        id.contains('/') ||
        name == null ||
        role == null ||
        authorizationRevision is! int ||
        authorizationRevision < 1 ||
        (data.containsKey('banned') && data['banned'] is! bool) ||
        (data.containsKey('isOnline') && data['isOnline'] is! bool)) {
      throw const FormatException('Unsupported server member.');
    }
    final joinedAt = data['joinedAt'];
    return ServerMember(
      id: id,
      displayName: name,
      // Deliberately dropped, not parsed: a denormalized member photo URL
      // bypasses the live visibility/block recheck. Member avatars resolve
      // from the uid through ProfileMediaImage like everywhere else.
      photoUrl: null,
      role: role,
      isOnline: data['isOnline'] == true,
      isBanned: data['banned'] == true,
      authorizationRevision: authorizationRevision,
      joinedAt: switch (joinedAt) {
        Timestamp value => value.toDate(),
        DateTime value => value,
        _ => null,
      },
    );
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
