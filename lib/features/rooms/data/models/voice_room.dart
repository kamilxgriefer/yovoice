import 'package:cloud_firestore/cloud_firestore.dart';

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
    required this.isLive,
    required this.createdAt,
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
  final bool isLive;
  final DateTime? createdAt;

  factory VoiceRoom.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw StateError(
        'Room document ${document.id} does not contain any data.',
      );
    }

    final createdAtValue = data['createdAt'];

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
      maxParticipants: data['maxParticipants'] as int?,
      participantCount: data['participantCount'] as int? ?? 0,
      isLive: data['isLive'] as bool? ?? false,
      createdAt: createdAtValue is Timestamp ? createdAtValue.toDate() : null,
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
      'isLive': isLive,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
    };
  }

  VoiceRoom copyWith({
    String? id,
    String? hostId,
    String? hostName,
    String? hostPhotoUrl,
    bool clearHostPhotoUrl = false,
    String? name,
    String? description,
    String? category,
    String? visibility,
    String? language,
    int? maxParticipants,
    bool clearMaxParticipants = false,
    int? participantCount,
    bool? isLive,
    DateTime? createdAt,
  }) {
    return VoiceRoom(
      id: id ?? this.id,
      hostId: hostId ?? this.hostId,
      hostName: hostName ?? this.hostName,
      hostPhotoUrl: clearHostPhotoUrl
          ? null
          : hostPhotoUrl ?? this.hostPhotoUrl,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      visibility: visibility ?? this.visibility,
      language: language ?? this.language,
      maxParticipants: clearMaxParticipants
          ? null
          : maxParticipants ?? this.maxParticipants,
      participantCount: participantCount ?? this.participantCount,
      isLive: isLive ?? this.isLive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
