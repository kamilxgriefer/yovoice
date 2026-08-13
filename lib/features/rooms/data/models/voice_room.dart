import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/data/models/room_metadata.dart';

enum RoomType {
  temporary,
  community;

  static RoomType fromValue(Object? value) {
    return value == 'community' ? RoomType.community : RoomType.temporary;
  }
}

enum RoomStatus {
  active,
  closed,
  archived;

  static RoomStatus fromValue(Object? value) {
    return switch (value) {
      'closed' => RoomStatus.closed,
      'archived' => RoomStatus.archived,
      _ => RoomStatus.active,
    };
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
    required this.status,
    required this.imageUrl,
    required this.approvalRequired,
    required this.slowModeSeconds,
    required this.autoMuteNewUsers,
    required this.membersCanStartVoice,
    required this.createdAt,
    required this.updatedAt,
    this.experience = 'community',
    this.clubId,
    this.targetAudience = TargetAudience.everyone,
    this.topicTags = const <String>[],
    this.roomGuidelines = '',
    this.conversationStyle,
    this.newcomerFriendly = false,
    this.showFormat,
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
  final RoomStatus status;
  final String? imageUrl;
  final bool approvalRequired;
  final int slowModeSeconds;
  final bool autoMuteNewUsers;
  final bool membersCanStartVoice;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String experience;

  /// Descriptive metadata — never authorization. See room_metadata.dart.
  /// Every one of these is optional on the document, so a room written
  /// before they existed loads with the same safe defaults a brand-new
  /// room would get.
  final TargetAudience targetAudience;
  final List<String> topicTags;
  final String roomGuidelines;

  /// Community only; null on a broadcast room.
  final ConversationStyle? conversationStyle;
  final bool newcomerFriendly;

  /// Podcast only; null on a community room.
  final ShowFormat? showFormat;

  /// Set on club-lounge rooms (written by ensureClubLounge). Older lounge
  /// documents may predate the field, so fromFirestore falls back to the
  /// `club_lounge_` id prefix those rooms have always carried.
  final String? clubId;

  bool get isClubRoom => clubId != null;

  RoomExperience get roomExperience => RoomExperience.fromValue(experience);

  bool get isBroadcast => roomExperience == RoomExperience.broadcast;
  bool get isCommunityExperience => roomExperience == RoomExperience.community;

  /// Temporary compatibility getter for code created before Podcast Rooms.
  @Deprecated('Use isBroadcast instead.')
  bool get isPodcast => isBroadcast;

  bool get isPersistent => roomType == RoomType.community;
  bool get isActive => status == RoomStatus.active;
  bool get isClosed => status == RoomStatus.closed;
  bool get isArchived => status == RoomStatus.archived;

  factory VoiceRoom.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw StateError('Room document ${document.id} does not contain data.');
    }

    DateTime? readDate(Object? value) {
      return value is Timestamp ? value.toDate() : null;
    }

    return VoiceRoom(
      id: document.id,
      hostId: data['hostId'] as String? ?? '',
      hostName: data['hostName'] as String? ?? 'YO Voice user',
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
      status: RoomStatus.fromValue(data['status']),
      imageUrl: data['imageUrl'] as String?,
      approvalRequired: data['approvalRequired'] as bool? ?? false,
      slowModeSeconds: (data['slowModeSeconds'] as num?)?.toInt() ?? 0,
      autoMuteNewUsers: data['autoMuteNewUsers'] as bool? ?? true,
      membersCanStartVoice: data['membersCanStartVoice'] as bool? ?? false,
      createdAt: readDate(data['createdAt']),
      updatedAt: readDate(data['updatedAt']),
      experience: data['experience'] as String? ?? 'community',
      targetAudience: TargetAudience.fromValue(data['targetAudience']),
      topicTags: RoomMetadataLimits.normalizeTags(
        (data['topicTags'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>(),
      ),
      roomGuidelines: (data['roomGuidelines'] as String?)?.trim() ?? '',
      conversationStyle: ConversationStyle.fromValue(
        data['conversationStyle'],
      ),
      newcomerFriendly: data['newcomerFriendly'] as bool? ?? false,
      showFormat: ShowFormat.fromValue(data['showFormat']),
      clubId:
          data['clubId'] as String? ??
          (document.id.startsWith('club_lounge_')
              ? document.id.substring('club_lounge_'.length)
              : null),
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
      'status': status.name,
      'imageUrl': imageUrl,
      'approvalRequired': approvalRequired,
      'slowModeSeconds': slowModeSeconds,
      'autoMuteNewUsers': autoMuteNewUsers,
      'membersCanStartVoice': membersCanStartVoice,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(updatedAt!),
      'experience': experience,
    };
  }
}
