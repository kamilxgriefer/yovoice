import 'package:cloud_firestore/cloud_firestore.dart';

enum ClubChannelType {
  chat,
  voice,
  announcement;

  static ClubChannelType fromValue(Object? value) {
    return switch (value) {
      'voice' => ClubChannelType.voice,
      'announcement' => ClubChannelType.announcement,
      _ => ClubChannelType.chat,
    };
  }
}

class ClubChannel {
  const ClubChannel({
    required this.id,
    required this.clubId,
    required this.name,
    required this.type,
    required this.position,
    required this.isPrivate,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String clubId;
  final String name;
  final ClubChannelType type;
  final int position;
  final bool isPrivate;
  final String createdBy;
  final DateTime? createdAt;

  factory ClubChannel.fromFirestore({
    required String clubId,
    required DocumentSnapshot<Map<String, dynamic>> document,
  }) {
    final data = document.data();
    if (data == null) {
      throw StateError('Club channel ${document.id} does not contain data.');
    }

    return ClubChannel(
      id: document.id,
      clubId: clubId,
      name: (data['name'] as String?)?.trim() ?? 'channel',
      type: ClubChannelType.fromValue(data['type']),
      position: (data['position'] as num?)?.toInt() ?? 0,
      isPrivate: data['isPrivate'] as bool? ?? false,
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }
}
