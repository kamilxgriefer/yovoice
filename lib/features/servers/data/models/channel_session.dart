import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';

import 'server.dart';
import 'server_channel.dart';

enum ChannelSessionStatus { starting, live, ending, ended, failed }

/// Session metadata only. This model never acquires or starts media devices.
class ChannelSession {
  const ChannelSession({
    required this.serverId,
    required this.channelId,
    required this.roomId,
    required this.sessionId,
    required this.experience,
    required this.mediaMode,
    required this.status,
    this.startedAt,
    this.endedAt,
  });

  final String serverId;
  final String channelId;
  final String roomId;
  final String sessionId;
  final RoomExperience experience;
  final ServerMediaMode mediaMode;
  final ChannelSessionStatus status;
  final DateTime? startedAt;
  final DateTime? endedAt;

  factory ChannelSession.fromMap(Map<String, dynamic> data) {
    String requiredId(String key) =>
        serverString(data[key]) ??
        (throw const FormatException('Incomplete session binding.'));
    final status = ChannelSessionStatus.values.where(
      (value) => value.name == data['status'],
    );
    final mode = ServerMediaMode.values.where(
      (value) => value.name == data['mediaMode'],
    );
    if (status.length != 1 || mode.length != 1) {
      throw const FormatException('Unsupported channel session.');
    }
    return ChannelSession(
      serverId: requiredId('serverId'),
      channelId: requiredId('channelId'),
      roomId: requiredId('roomId'),
      sessionId: requiredId('sessionId'),
      experience: switch (data['experience']) {
        'community' => RoomExperience.community,
        'broadcast' => RoomExperience.broadcast,
        _ => throw const FormatException('Unsupported session experience.'),
      },
      mediaMode: mode.single,
      status: status.single,
      startedAt: _date(data['startedAt']),
      endedAt: _date(data['endedAt']),
    );
  }

  static DateTime? _date(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime date => date,
    _ => null,
  };
}
