import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/rooms/data/models/room_voice_access.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_voice_entry_coordinator.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room/broadcast_colors.dart';
import 'package:yovoice/features/rooms/presentation/screens/community_voice_room_screen.dart';
import 'package:yovoice/features/rooms/presentation/screens/broadcast_room_screen.dart';
import 'package:yovoice/features/rooms/presentation/widgets/room_ended_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

/// The one door into a room, whichever surface opened it.
///
/// Nine call sites push this screen — Home, Discover, the mini bar, the Club
/// overview, notifications, a profile, Creator Studio and room creation — and
/// only two of them ever did anything about the room's voice session. So this
/// is where the voice lifecycle belongs: resolve the room ONCE, from the
/// server, and decide from that single snapshot both which experience to
/// route to and whether live audio may be requested at all.
///
/// The routing snapshot and the liveness snapshot are now the SAME document
/// read, which also removes a second round trip from every room entry.
class RoomEntryScreen extends StatefulWidget {
  const RoomEntryScreen({
    required this.room,
    this.coordinator,
    this.playInitialJoinSound = true,
    super.key,
  });

  final VoiceRoom room;

  /// False only when room creation already played its richer confirmation.
  /// Connecting LiveKit immediately afterwards must not turn one successful
  /// action into a two-cue jingle.
  final bool playInitialJoinSound;

  /// Test seam. Production builds the Firebase-backed coordinator lazily, so
  /// this screen can be pumped without a Firebase app.
  final RoomVoiceEntryCoordinator? coordinator;

  @override
  State<RoomEntryScreen> createState() => _RoomEntryScreenState();
}

class _RoomEntryScreenState extends State<RoomEntryScreen> {
  late Future<RoomVoiceEntry> _entry;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  void _prepare() {
    final coordinator =
        widget.coordinator ?? RoomVoiceEntryCoordinator.production();
    _entry = coordinator.enter(widget.room);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RoomVoiceEntry>(
      future: _entry,
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
                onRetry: () => setState(_prepare),
              ),
            ),
          );
        }

        final entry = snapshot.data ?? RoomVoiceEntry.unresolved(widget.room);

        // Closed, archived, suspended or mid-deletion: there is no room to
        // enter, so say so instead of opening a stage nothing can happen on.
        if (entry.outcome == RoomVoiceEntryOutcome.unavailable) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: entry.room.isBroadcast
                  // The palette is the single source of truth (CLAUDE.md).
                  // This used to carry a remembered 0xFFFF4D6D that had
                  // already drifted from the real broadcast accent.
                  ? RoomEndedState(
                      roomName: entry.room.name,
                      accent: BroadcastRoomColors.accent,
                    )
                  // Community keeps RoomEndedState's own default, which is
                  // what CommunityVoiceRoomScreen's ended state already uses
                  // — changing it here would make the same room end in two
                  // different colours depending on which screen caught it.
                  : RoomEndedState(roomName: entry.room.name),
            ),
          );
        }

        // Community and Broadcast are different products routed to different
        // screens. The experience comes from the SAME refreshed document the
        // liveness decision came from, so routing and voice can never
        // disagree about which room this is.
        if (entry.room.roomExperience == RoomExperience.broadcast) {
          return BroadcastRoomScreen(
            room: entry.room,
            voiceEntry: entry,
            playInitialJoinSound: widget.playInitialJoinSound,
          );
        }
        // Straight into the room — the lobby detour is gone. The liveness
        // transition and the roster join have already happened above; the
        // room screen owns the live-audio connection from here.
        return CommunityVoiceRoomScreen(
          room: entry.room,
          voiceEntry: entry,
          playInitialJoinSound: widget.playInitialJoinSound,
        );
      },
    );
  }
}
