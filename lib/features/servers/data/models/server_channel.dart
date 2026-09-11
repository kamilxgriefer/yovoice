import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';

import 'server.dart';

enum ServerChannelKind {
  text,
  voice,
  stage,
  events,
  announcements,
  rules,
  questions,
  episodes,
  calendar,
  memories,
  list,
  meeting,
  whiteboard,
  files;

  static ServerChannelKind parse(Object? value) {
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    throw const FormatException('Unsupported server channel kind.');
  }

  bool get isMedia => this == voice || this == stage || this == meeting;
}

enum ServerChannelAccess { members, restricted }

enum ServerMediaMode { audio, video, meeting }

class ServerChannel {
  const ServerChannel({
    required this.id,
    required this.serverId,
    required this.name,
    required this.kind,
    this.position = 0,
    this.access = ServerChannelAccess.members,
    this.categoryId,
    this.seedKey,
    this.roomId,
    this.activeSessionId,
    this.experience,
    this.mediaMode,
    this.schemaVersion,
    this.status = 'active',
  });

  final String id;
  final String serverId;
  final String name;
  final ServerChannelKind kind;
  final int position;
  final ServerChannelAccess access;
  final String? categoryId;
  final String? seedKey;
  final String? roomId;
  final String? activeSessionId;
  final RoomExperience? experience;
  final ServerMediaMode? mediaMode;
  final int? schemaVersion;
  final String status;

  bool get isLegacy => schemaVersion == null;

  factory ServerChannel.fromFirestore({
    required String serverId,
    required DocumentSnapshot<Map<String, dynamic>> document,
  }) {
    final data = document.data();
    if (data == null) throw const FormatException('Channel is unavailable.');
    return ServerChannel.fromMap(serverId, document.id, data);
  }

  factory ServerChannel.fromMap(
    String serverId,
    String id,
    Map<String, dynamic> data,
  ) {
    final version = data['serverSchemaVersion'];
    if (version != null && version != 1) {
      throw const FormatException('Unsupported channel schema version.');
    }
    final legacy = version == null;
    final kind = legacy
        ? switch (data['type']) {
            'voice' => ServerChannelKind.voice,
            'announcement' => ServerChannelKind.announcements,
            _ => ServerChannelKind.text,
          }
        : ServerChannelKind.parse(data['kind']);
    final access = legacy
        ? (data['isPrivate'] == true
              ? ServerChannelAccess.restricted
              : ServerChannelAccess.members)
        : switch (data['accessMode']) {
            'members' => ServerChannelAccess.members,
            'restricted' => ServerChannelAccess.restricted,
            _ => throw const FormatException('Unsupported channel access.'),
          };
    if (!legacy &&
        (data['serverId'] != serverId ||
            data['isPrivate'] != (access == ServerChannelAccess.restricted))) {
      throw const FormatException('Invalid channel binding.');
    }
    final experienceValue = data['experience'];
    final modeValue = data['mediaMode'];
    final experience = !kind.isMedia
        ? null
        : legacy
        ? RoomExperience.fromValue(experienceValue)
        : switch (experienceValue) {
            'community' => RoomExperience.community,
            'broadcast' => RoomExperience.broadcast,
            _ => throw const FormatException('Unsupported channel experience.'),
          };
    final mode = !kind.isMedia
        ? null
        : switch (modeValue) {
            'audio' => ServerMediaMode.audio,
            'video' => ServerMediaMode.video,
            'meeting' => ServerMediaMode.meeting,
            _ when legacy => ServerMediaMode.audio,
            _ => throw const FormatException('Unsupported channel media mode.'),
          };
    final roomId = serverString(data['roomId']);
    if (!legacy && kind.isMedia && roomId == null) {
      throw const FormatException('Media channel has no room binding.');
    }
    return ServerChannel(
      id: id,
      serverId: serverId,
      name: serverString(data['name']) ?? '',
      kind: kind,
      position: serverInt(data['position']),
      access: access,
      categoryId: serverString(data['categoryId']),
      seedKey: serverString(data['seedKey']),
      roomId: roomId,
      activeSessionId: serverString(data['activeSessionId']),
      experience: experience,
      mediaMode: mode,
      schemaVersion: legacy ? null : 1,
      status: serverString(data['status']) ?? (legacy ? 'active' : 'unknown'),
    );
  }
}
