import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'server.dart';

/// The answer a raised hand received, exactly as the backend writes
/// `handDecision` on the participant's own document
/// (`functions/servers/session_participation.js` HAND_DECISIONS).
///
/// * [approved] — a promotion answered the hand; the person is on the stage.
/// * [declined] — the host or a moderator declined it.
/// * [lowered] — the provider reported the person left the generation with the
///   hand still up, so the backend lowered it.
enum ServerHandDecision { approved, declined, lowered }

ServerHandDecision? serverHandDecision(Object? value) => switch (value) {
  'approved' => ServerHandDecision.approved,
  'declined' => ServerHandDecision.declined,
  'lowered' => ServerHandDecision.lowered,
  _ => null,
};

DateTime? _instant(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  _ => null,
};

/// One raised hand in the live generation, as the host's and moderators' queue
/// reads it: `rooms/{roomId}/participants` filtered by the four equalities the
/// rules require (`canListServerSessionHands`). Only people who asked are ever
/// in it — the rules make a roster listing impossible by construction.
@immutable
class ServerSessionHand {
  const ServerSessionHand({
    required this.userId,
    required this.displayName,
    required this.role,
    this.raisedAt,
  });

  /// The Firebase uid, which is also the provider identity in the generation.
  final String userId;
  final String displayName;

  /// `listener | guest` for this generation (the host never queues).
  final String role;

  /// When the hand went up, from the backend's own clock. Null only for a
  /// document written by an older backend without the instant.
  final DateTime? raisedAt;

  /// Parses one queue document. The document id is the uid; a row that does
  /// not name the same person, is not raised, or carries no usable role is
  /// refused rather than shown under somebody else's name.
  static ServerSessionHand? fromDocument(
    String id,
    Map<String, Object?> data, {
    required String sessionId,
  }) {
    final userId = serverString(data['userId']);
    final role = serverString(data['role']);
    if (userId == null ||
        userId != id ||
        data['isHandRaised'] != true ||
        serverString(data['sessionId']) != sessionId ||
        (role != 'listener' && role != 'guest')) {
      return null;
    }
    return ServerSessionHand(
      userId: userId,
      displayName: serverString(data['displayName']) ?? userId,
      role: role!,
      raisedAt: _instant(data['handRaisedAt']),
    );
  }

  /// Oldest first; a hand with no instant goes last, and the uid breaks ties
  /// so two devices always draw the same order.
  static int oldestFirst(ServerSessionHand a, ServerSessionHand b) {
    final left = a.raisedAt;
    final right = b.raisedAt;
    if (left != null && right != null) {
      final byTime = left.compareTo(right);
      if (byTime != 0) return byTime;
    } else if (left != null) {
      return -1;
    } else if (right != null) {
      return 1;
    }
    return a.userId.compareTo(b.userId);
  }

  @override
  bool operator ==(Object other) =>
      other is ServerSessionHand &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.role == role &&
      other.raisedAt == raisedAt;

  @override
  int get hashCode => Object.hash(userId, displayName, role, raisedAt);
}

/// This person's own participant document in the live generation — the one
/// point read `canReadOwnServerSessionParticipant` allows. It is authorization
/// state the backend writes (session role, revision, mutes, hand and its
/// answer); the client only ever reads it.
///
/// `handDecidedById` is deliberately not carried: nothing in the product needs
/// to tell somebody which moderator answered them.
@immutable
class ServerSessionParticipantState {
  const ServerSessionParticipantState({
    required this.sessionId,
    required this.role,
    required this.authorizationRevision,
    required this.hostMuted,
    required this.serverMuted,
    required this.isHandRaised,
    this.handRaisedAt,
    this.handDecision,
    this.handDecidedAt,
    this.tokenFingerprint,
  });

  final String sessionId;

  /// `host | guest | listener`.
  final String role;

  /// Moves on every role or mute change — exactly the changes that revoke the
  /// current media token (ADR-181).
  final int authorizationRevision;
  final bool hostMuted;
  final bool serverMuted;
  final bool isHandRaised;
  final DateTime? handRaisedAt;
  final ServerHandDecision? handDecision;
  final DateTime? handDecidedAt;

  /// `tokenAuthorityFingerprint`: written by token issuance, never by a role
  /// or mute change. A revision that moved while this stayed the same is an
  /// authority change the current media token no longer matches; a new value
  /// means a token was issued under the current authority.
  final String? tokenFingerprint;

  bool get isOnStage => role == 'host' || role == 'guest';

  static ServerSessionParticipantState? fromDocument(
    Map<String, Object?> data, {
    required String userId,
    required String sessionId,
  }) {
    final role = serverString(data['role']);
    final revision = data['authorizationRevision'];
    if (serverString(data['userId']) != userId ||
        serverString(data['sessionId']) != sessionId ||
        (role != 'host' && role != 'guest' && role != 'listener') ||
        revision is! int ||
        revision < 1) {
      return null;
    }
    return ServerSessionParticipantState(
      sessionId: sessionId,
      role: role!,
      authorizationRevision: revision,
      hostMuted: data['hostMuted'] == true,
      serverMuted: data['serverMuted'] == true,
      isHandRaised: data['isHandRaised'] == true,
      handRaisedAt: _instant(data['handRaisedAt']),
      handDecision: serverHandDecision(data['handDecision']),
      handDecidedAt: _instant(data['handDecidedAt']),
      tokenFingerprint: serverString(data['tokenAuthorityFingerprint']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ServerSessionParticipantState &&
      other.sessionId == sessionId &&
      other.role == role &&
      other.authorizationRevision == authorizationRevision &&
      other.hostMuted == hostMuted &&
      other.serverMuted == serverMuted &&
      other.isHandRaised == isHandRaised &&
      other.handRaisedAt == handRaisedAt &&
      other.handDecision == handDecision &&
      other.handDecidedAt == handDecidedAt &&
      other.tokenFingerprint == tokenFingerprint;

  @override
  int get hashCode => Object.hash(
    sessionId,
    role,
    authorizationRevision,
    hostMuted,
    serverMuted,
    isHandRaised,
    handRaisedAt,
    handDecision,
    handDecidedAt,
    tokenFingerprint,
  );
}

/// `answerServerSessionHandV1`'s receipt.
@immutable
class ServerSessionHandAnswerResult {
  const ServerSessionHandAnswerResult({
    required this.serverId,
    required this.channelId,
    required this.sessionId,
    required this.participantId,
    required this.decision,
    required this.changed,
  });

  final String serverId;
  final String channelId;
  final String sessionId;
  final String participantId;
  final ServerHandDecision decision;

  /// False when the hand was no longer up (already answered, withdrawn or
  /// lowered on leaving) — not a failure, simply nothing left to answer.
  final bool changed;

  factory ServerSessionHandAnswerResult.fromMap(Map<Object?, Object?> data) {
    String requiredString(String key) =>
        serverString(data[key]) ??
        (throw FormatException('Incomplete hand answer receipt: $key.'));
    final decision = serverHandDecision(data['decision']);
    final changed = data['changed'];
    if (decision == null || changed is! bool) {
      throw const FormatException('Invalid hand answer receipt.');
    }
    return ServerSessionHandAnswerResult(
      serverId: requiredString('serverId'),
      channelId: requiredString('channelId'),
      sessionId: requiredString('sessionId'),
      participantId: requiredString('participantId'),
      decision: decision,
      changed: changed,
    );
  }
}
