import 'package:flutter/material.dart';

import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/rooms/data/services/room_mute_coordinator.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';
import 'package:yovoice/features/rooms/presentation/widgets/mini_player/active_room_mini_player.dart';

/// The persistent mini player entry point. Every shell mount keeps using
/// this name; the implementation is [ActiveRoomMiniPlayer] — isolated tap
/// targets (room info navigates; Mute only toggles and swallows taps while
/// busy; Expand only opens the chat preview; Leave/End only leaves), a
/// live latest-message preview with a session-local "N new" count, and
/// desktop dock / mobile card layouts over one controller.
///
/// Renders nothing when no room connection exists, so the shell can mount
/// it unconditionally.
class RoomMiniBar extends StatelessWidget {
  const RoomMiniBar({
    this.voiceService,
    this.muteCoordinator,
    this.roomService,
    this.openRoom,
    super.key,
  });

  /// Test seams; production resolves the shared singletons lazily so the
  /// shell can keep mounting `const RoomMiniBar()` with no Firebase app
  /// in widget tests.
  final VoiceCallService? voiceService;
  final RoomMuteCoordinator? muteCoordinator;
  final RoomService? roomService;

  /// How "go into the room" is performed. Production pushes
  /// RoomEntryScreen; tests inject a recorder so navigation isolation is
  /// an assertable fact rather than a hope.
  final Future<void> Function(BuildContext context, String roomId)? openRoom;

  @override
  Widget build(BuildContext context) {
    return ActiveRoomMiniPlayer(
      voiceService: voiceService,
      muteCoordinator: muteCoordinator,
      roomService: roomService,
      openRoom: openRoom,
    );
  }
}
