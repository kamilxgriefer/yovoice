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
  archived,
  suspended;

  static RoomStatus fromValue(Object? value) {
    return switch (value) {
      'closed' => RoomStatus.closed,
      'archived' => RoomStatus.archived,
      // Moderation writes "suspended" server-side; mapping it to active
      // would render a sanctioned room as joinable.
      'suspended' => RoomStatus.suspended,
      // A missing field is legacy data and stays active on purpose.
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
    this.storedClubId,
    this.targetAudience = TargetAudience.everyone,
    this.topicTags = const <String>[],
    this.roomGuidelines = '',
    this.conversationStyle,
    this.newcomerFriendly = false,
    this.showFormat,
    this.topic = '',
    this.audienceCanSpeak = true,
    this.handRaisingEnabled = true,
    this.stageLimit = 8,
    this.deletionInProgress = false,
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

  /// Podcast session contract. These fields predate the typed model, so
  /// legacy documents keep safe, permissive presentation defaults.
  final String topic;
  final bool audienceCanSpeak;
  final bool handRaisingEnabled;
  final int stageLimit;

  /// Server-written marker: a host deletion committed its closing
  /// transaction but the full teardown has not finished (or failed and
  /// awaits retry). Such a room must never be presented as joinable or
  /// restartable.
  final bool deletionInProgress;

  /// Set on club-lounge rooms (written by ensureClubLounge). Older lounge
  /// documents may predate the field, so fromFirestore falls back to the
  /// `club_lounge_` id prefix those rooms have always carried.
  ///
  /// PRESENTATION AND ROUTING ONLY. This is the forgiving value — it decides
  /// whether the room renders club identity, which club overview the banner
  /// opens, and whether leaving runs lounge bookkeeping. It must NOT be used
  /// to decide authority: see [storedClubId].
  final String? clubId;

  /// The `clubId` FIELD exactly as the document stores it — null when the
  /// document has no such field, even for a `club_lounge_`-prefixed id.
  ///
  /// AUTHORITY READS THIS ONE. `roomVoiceStartAllowed()` in firestore.rules
  /// gates its Club branch on `resource.data.get('clubId','')` being
  /// non-empty, and `isActiveClubRoomMember()` resolves membership through
  /// the same field. A lounge that carries only the id prefix therefore
  /// cannot satisfy that branch at all, so resolving Club start authority
  /// from [clubId] would offer a control the server refuses — which is the
  /// exact defect class this whole path exists to remove.
  final String? storedClubId;

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

  /// A copy whose liveness has moved.
  ///
  /// Used between the voice-start write committing and the document being
  /// re-read, so a failure further along the entry path still describes the
  /// room as it now actually is on the server rather than as it was when the
  /// caller navigated.
  VoiceRoom withLiveness(bool value) {
    return VoiceRoom(
      id: id,
      hostId: hostId,
      hostName: hostName,
      hostPhotoUrl: hostPhotoUrl,
      name: name,
      description: description,
      category: category,
      visibility: visibility,
      language: language,
      maxParticipants: maxParticipants,
      participantCount: participantCount,
      memberCount: memberCount,
      isLive: value,
      roomType: roomType,
      status: status,
      imageUrl: imageUrl,
      approvalRequired: approvalRequired,
      slowModeSeconds: slowModeSeconds,
      autoMuteNewUsers: autoMuteNewUsers,
      membersCanStartVoice: membersCanStartVoice,
      createdAt: createdAt,
      updatedAt: updatedAt,
      experience: experience,
      clubId: clubId,
      storedClubId: storedClubId,
      targetAudience: targetAudience,
      topicTags: topicTags,
      roomGuidelines: roomGuidelines,
      conversationStyle: conversationStyle,
      newcomerFriendly: newcomerFriendly,
      showFormat: showFormat,
      topic: topic,
      audienceCanSpeak: audienceCanSpeak,
      handRaisingEnabled: handRaisingEnabled,
      stageLimit: stageLimit,
      deletionInProgress: deletionInProgress,
    );
  }

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
      conversationStyle: ConversationStyle.fromValue(data['conversationStyle']),
      newcomerFriendly: data['newcomerFriendly'] as bool? ?? false,
      showFormat: ShowFormat.fromValue(data['showFormat']),
      topic: (data['topic'] as String?)?.trim() ?? '',
      audienceCanSpeak: data['audienceCanSpeak'] as bool? ?? true,
      handRaisingEnabled: data['handRaisingEnabled'] as bool? ?? true,
      stageLimit: ((data['stageLimit'] as num?)?.toInt() ?? 8)
          .clamp(1, 8)
          .toInt(),
      deletionInProgress: data['deletionInProgress'] as bool? ?? false,
      // The forgiving value, for identity and routing.
      clubId:
          data['clubId'] as String? ??
          (document.id.startsWith('club_lounge_')
              ? document.id.substring('club_lounge_'.length)
              : null),
      // The literal field, for authority. Deliberately NOT prefix-derived.
      storedClubId: (data['clubId'] as String?)?.trim().isNotEmpty == true
          ? (data['clubId'] as String).trim()
          : null,
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
      'targetAudience': targetAudience.value,
      'topicTags': topicTags,
      'roomGuidelines': roomGuidelines,
      if (conversationStyle != null)
        'conversationStyle': conversationStyle!.value,
      if (newcomerFriendly) 'newcomerFriendly': true,
      if (showFormat != null) 'showFormat': showFormat!.value,
      'topic': topic,
      'audienceCanSpeak': audienceCanSpeak,
      'handRaisingEnabled': handRaisingEnabled,
      'stageLimit': stageLimit,
      'deletionInProgress': deletionInProgress,
    };
  }
}
