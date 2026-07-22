import 'package:cloud_firestore/cloud_firestore.dart';

enum RoomType {
  temporary,
  community;

  static RoomType fromValue(Object? value) {
    return value == 'community' ? RoomType.community : RoomType.temporary;
  }
}

class VoiceRoom {
  const VoiceRoom({
    required this.id,
    required this.hostId,
    required this.hostName,
    required this.hostPhotoUrl,
    required this.name,
    required this.description,
    required this.category,
    required this.visibility,
    required this.language,
    required this.maxParticipants,
    required this.participantCount,
    required this.memberCount,
    required this.isLive,
    required this.roomType,
    required this.imageUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String hostId;
  final String hostName;
  final String? hostPhotoUrl;
  final String name;
  final String description;
  final String category;
  final String visibility;
  final String language;
  final int? maxParticipants;
  final int participantCount;
  final int memberCount;
  final bool isLive;
  final RoomType roomType;
  final String? imageUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPersistent => roomType == RoomType.community;

  factory VoiceRoom.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw StateError(
        'Room document ${document.id} does not contain any data.',
      );
    }

    DateTime? readDate(Object? value) {
      return value is Timestamp ? value.toDate() : null;
    }

    return VoiceRoom(
      id: document.id,
      hostId: data['hostId'] as String? ?? '',
      hostName: data['hostName'] as String? ?? 'YoVoice user',
      hostPhotoUrl: data['hostPhotoUrl'] as String?,
      name: data['name'] as String? ?? 'Untitled room',
      description: data['description'] as String? ?? '',
      category: data['category'] as String? ?? 'talk',
      visibility: data['visibility'] as String? ?? 'public',
      language: data['language'] as String? ?? 'English',
      maxParticipants: (data['maxParticipants'] as num?)?.toInt(),
      participantCount: (data['participantCount'] as num?)?.toInt() ?? 0,
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
      isLive: data['isLive'] as bool? ?? false,
      roomType: RoomType.fromValue(data['roomType']),
      imageUrl: data['imageUrl'] as String?,
      createdAt: readDate(data['createdAt']),
      updatedAt: readDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hostId': hostId,
      'hostName': hostName,
      'hostPhotoUrl': hostPhotoUrl,
      'name': name,
      'description': description,
      'category': category,
      'visibility': visibility,
      'language': language,
      'maxParticipants': maxParticipants,
      'participantCount': participantCount,
      'memberCount': memberCount,
      'isLive': isLive,
      'roomType': roomType.name,
      'imageUrl': imageUrl,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(updatedAt!),
    };
  }
}
