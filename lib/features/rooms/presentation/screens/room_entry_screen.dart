import 'package:flutter/material.dart';

import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_experience_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/community_room_lobby_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room_screen.dart';

class RoomEntryScreen extends StatelessWidget {
  const RoomEntryScreen({required this.room, super.key});

  final VoiceRoom room;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RoomExperience>(
      future: RoomExperienceService().getExperience(room.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Color(0xFF080711),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data == RoomExperience.broadcast) {
          return BroadcastRoomScreen(room: room);
        }
        return CommunityRoomLobbyScreen(room: room);
      },
    );
  }
}
