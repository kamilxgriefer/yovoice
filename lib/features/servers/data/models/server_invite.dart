import 'package:cloud_firestore/cloud_firestore.dart';

/// The invitee-safe preview stored at
/// `clubs/{serverId}/invites/{inviteeId}`.
///
/// A private Server root is deliberately unreadable before acceptance. This
/// document is therefore the only authority the invitation screen consumes;
/// it carries no channels, roster, description or member counts.
class ServerInvite {
  const ServerInvite({
    required this.serverId,
    required this.inviteeId,
    required this.inviterId,
    required this.serverName,
    required this.inviterName,
    required this.status,
    required this.generation,
    required this.expiresAt,
  });

  final String serverId;
  final String inviteeId;
  final String inviterId;
  final String serverName;
  final String inviterName;
  final String status;
  final int generation;
  final DateTime expiresAt;

  bool isActionableAt(DateTime now) =>
      status == 'pending' && expiresAt.isAfter(now.toUtc());

  factory ServerInvite.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final serverId = document.reference.parent.parent?.id;
    if (data == null || serverId == null) {
      throw const FormatException('Server invitation is unavailable.');
    }
    return ServerInvite.fromMap(
      serverId: serverId,
      inviteeId: document.id,
      data: data,
    );
  }

  factory ServerInvite.fromMap({
    required String serverId,
    required String inviteeId,
    required Map<String, dynamic> data,
  }) {
    String requiredText(String field) {
      final value = data[field];
      if (value is! String || value.trim().isEmpty) {
        throw const FormatException('Malformed server invitation.');
      }
      return value.trim();
    }

    final storedServerId = requiredText('serverId');
    final storedInviteeId = requiredText('inviteeId');
    final inviterId = requiredText('inviterId');
    final serverName = requiredText('serverName');
    final inviterName = requiredText('inviterName');
    final status = requiredText('status');
    final generation = data['generation'];
    final inviterRevision = data['inviterAuthorizationRevision'];
    final expiresAt = data['expiresAt'];
    final createdAt = data['createdAt'];
    final updatedAt = data['updatedAt'];
    if (data['serverSchemaVersion'] != 1 ||
        storedServerId != serverId ||
        storedInviteeId != inviteeId ||
        !const {
          'pending',
          'accepted',
          'declined',
          'revoked',
        }.contains(status) ||
        generation is! int ||
        generation < 1 ||
        inviterRevision is! int ||
        inviterRevision < 1 ||
        expiresAt is! Timestamp ||
        createdAt is! Timestamp ||
        updatedAt is! Timestamp) {
      throw const FormatException('Malformed server invitation.');
    }
    return ServerInvite(
      serverId: storedServerId,
      inviteeId: storedInviteeId,
      inviterId: inviterId,
      serverName: serverName,
      inviterName: inviterName,
      status: status,
      generation: generation,
      expiresAt: expiresAt.toDate().toUtc(),
    );
  }
}
