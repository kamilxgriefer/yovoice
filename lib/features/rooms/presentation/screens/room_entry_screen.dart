import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_experience_service.dart';
import 'package:yovoice/features/rooms/presentation/screens/community_room_lobby_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room_screen.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

class RoomEntryScreen extends StatefulWidget {
  const RoomEntryScreen({required this.room, super.key});

  final VoiceRoom room;

  @override
  State<RoomEntryScreen> createState() => _RoomEntryScreenState();
}

class _RoomEntryScreenState extends State<RoomEntryScreen> {
  late Future<RoomExperience> _experience;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _fetch() {
    _experience = RoomExperienceService().getExperience(widget.room.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RoomExperience>(
      future: _experience,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: YoLoadingIndicator.fullscreen(message: 'Joining room…'),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: YoErrorState(
                error: snapshot.error,
                onRetry: () => setState(_fetch),
              ),
            ),
          );
        }

        if (snapshot.data == RoomExperience.broadcast) {
          return BroadcastRoomScreen(room: widget.room);
        }
        return CommunityRoomLobbyScreen(room: widget.room);
      },
    );
  }
}
