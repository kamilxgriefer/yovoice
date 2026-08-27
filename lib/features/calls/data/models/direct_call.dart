import 'package:cloud_firestore/cloud_firestore.dart';

enum DirectCallStatus {
  ringing,
  active,
  declined,
  cancelled,
  ended,
  missed;

  static DirectCallStatus fromName(String? value) {
    return DirectCallStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => DirectCallStatus.ended,
    );
  }

  bool get isTerminal => switch (this) {
    DirectCallStatus.declined ||
    DirectCallStatus.cancelled ||
    DirectCallStatus.ended ||
    DirectCallStatus.missed => true,
    DirectCallStatus.ringing || DirectCallStatus.active => false,
  };
}

class DirectCallIdentity {
  const DirectCallIdentity({
    required this.userId,
    required this.displayName,
    required this.photoUrl,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;

  factory DirectCallIdentity.fromMap(Object? value) {
    final data = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    final name = (data['displayName'] as String?)?.trim();
    final photo = (data['photoUrl'] as String?)?.trim();
    return DirectCallIdentity(
      userId: data['userId'] as String? ?? '',
      displayName: name?.isNotEmpty == true ? name! : 'YO Voice user',
      photoUrl: photo?.isNotEmpty == true ? photo : null,
    );
  }
}

class DirectCall {
  const DirectCall({
    required this.id,
    required this.callerId,
    required this.calleeId,
    required this.caller,
    required this.callee,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.answeredAt,
    required this.conversationId,
  });

  final String id;
  final String callerId;
  final String calleeId;
  final DirectCallIdentity caller;
  final DirectCallIdentity callee;
  final DirectCallStatus status;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? answeredAt;
  final String? conversationId;

  bool isIncomingFor(String userId) => calleeId == userId;

  DirectCallIdentity otherIdentity(String userId) =>
      callerId == userId ? callee : caller;

  factory DirectCall.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    DateTime? date(Object? value) => value is Timestamp ? value.toDate() : null;
    return DirectCall(
      id: document.id,
      callerId: data['callerId'] as String? ?? '',
      calleeId: data['calleeId'] as String? ?? '',
      caller: DirectCallIdentity.fromMap(data['caller']),
      callee: DirectCallIdentity.fromMap(data['callee']),
      status: DirectCallStatus.fromName(data['status'] as String?),
      createdAt: date(data['createdAt']),
      expiresAt: date(data['expiresAt']),
      answeredAt: date(data['answeredAt']),
      conversationId: data['conversationId'] as String?,
    );
  }
}

class IncomingDirectCallSignal {
  const IncomingDirectCallSignal({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.callerPhotoUrl,
    required this.status,
    required this.expiresAt,
  });

  final String callId;
  final String callerId;
  final String callerName;
  final String? callerPhotoUrl;
  final DirectCallStatus status;
  final DateTime? expiresAt;

  factory IncomingDirectCallSignal.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final name = (data['callerName'] as String?)?.trim();
    final photo = (data['callerPhotoUrl'] as String?)?.trim();
    final expiresAt = data['expiresAt'];
    return IncomingDirectCallSignal(
      callId: data['callId'] as String? ?? document.id,
      callerId: data['callerId'] as String? ?? '',
      callerName: name?.isNotEmpty == true ? name! : 'YO Voice user',
      callerPhotoUrl: photo?.isNotEmpty == true ? photo : null,
      status: DirectCallStatus.fromName(data['status'] as String?),
      expiresAt: expiresAt is Timestamp ? expiresAt.toDate() : null,
    );
  }
}
