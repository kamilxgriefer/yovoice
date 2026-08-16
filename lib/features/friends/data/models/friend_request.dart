import 'package:cloud_firestore/cloud_firestore.dart';

class FriendRequest {
  const FriendRequest({
    required this.senderId,
    required this.senderName,
    required this.senderEmail,
    required this.senderPhotoUrl,
    required this.createdAt,
  });

  final String senderId;
  final String senderName;
  final String senderEmail;
  final String? senderPhotoUrl;
  final DateTime? createdAt;

  factory FriendRequest.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw StateError(
        'Friend request ${document.id} does not contain any data.',
      );
    }

    return FriendRequest(
      senderId: data['senderId'] as String? ?? document.id,
      senderName: _resolveSenderName(data),
      // Historical requests can contain a private email snapshot. Keep the
      // compatibility property empty so no screen can accidentally render it.
      senderEmail: '',
      senderPhotoUrl: _normalizeNullableString(data['senderPhotoUrl']),
      createdAt: _readDateTime(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'senderPhotoUrl': senderPhotoUrl,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
    };
  }

  static String _resolveSenderName(Map<String, dynamic> data) {
    final name = (data['senderName'] as String?)?.trim();

    if (name != null && name.isNotEmpty) {
      return name;
    }

    return 'YO Voice user';
  }

  static String? _normalizeNullableString(Object? value) {
    if (value is! String) {
      return null;
    }

    final normalized = value.trim();

    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }
}
