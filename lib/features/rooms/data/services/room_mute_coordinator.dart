import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/rooms/data/services/room_mute_sync.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

/// What a coordinated mute toggle actually did, so every surface can react
/// honestly instead of guessing from a raw exception.
enum RoomMuteOutcome {
  /// Roster and microphone now match the requested state.
  applied,

  /// Another toggle was already in flight; nothing changed.
  busy,

  /// The server no longer recognizes this room/participant as live. The
  /// stale audio session has been disconnected so no surface keeps a
  /// phantom room open.
  sessionEnded,

  /// A transient failure; state is unchanged and a retry is reasonable.
  failed,

  /// The privacy-critical local mute succeeded, but its roster mirror did
  /// not. The microphone remains safely off and only synchronization needs
  /// another try.
  mutedLocally,
}

/// The one mute/unmute path shared by the room screens and the mini bar.
///
/// Both surfaces previously diverged: screens persisted the roster through
/// the server callable while the mini bar flipped only the local LiveKit
/// track, so the two controls could disagree with each other and with the
/// server. Muting disables the local track first; unmuting still waits for
/// server authority. A refusal that means "this voice session is gone" tears
/// the stale session down instead of trapping the user behind an error loop.
class RoomMuteCoordinator extends ChangeNotifier {
  RoomMuteCoordinator({
    required Future<void> Function(String roomId, bool muted)
    persistRosterState,
    required Future<void> Function(bool muted) applyMicrophoneState,
    required bool Function() readCurrentMuted,
    required Future<void> Function() disconnectStaleSession,
  }) : _persistRosterState = persistRosterState,
       _applyMicrophoneState = applyMicrophoneState,
       _readCurrentMuted = readCurrentMuted,
       _disconnectStaleSession = disconnectStaleSession {
    _sync = RoomMuteSync(onBusyChanged: notifyListeners);
  }

  /// The instance every production surface shares. One serializer means a
  /// double tap that spans the room screen and the mini bar is still a
  /// single operation.
  static RoomMuteCoordinator get production =>
      _production ??= RoomMuteCoordinator(
        persistRosterState: (roomId, muted) =>
            RoomService().setMuted(roomId: roomId, isMuted: muted),
        applyMicrophoneState: (muted) =>
            VoiceCallService.instance.setMuted(muted),
        readCurrentMuted: () => VoiceCallService.instance.isMuted,
        disconnectStaleSession: () => VoiceCallService.instance.disconnect(),
      );
  static RoomMuteCoordinator? _production;

  final Future<void> Function(String roomId, bool muted) _persistRosterState;
  final Future<void> Function(bool muted) _applyMicrophoneState;
  final bool Function() _readCurrentMuted;
  final Future<void> Function() _disconnectStaleSession;
  late final RoomMuteSync _sync;

  bool get isBusy => _sync.isBusy;

  Future<RoomMuteOutcome> toggle({required String roomId}) async {
    if (_sync.isBusy) return RoomMuteOutcome.busy;

    final wasMuted = _readCurrentMuted();
    try {
      final applied = await _sync.toggle(
        currentMuted: wasMuted,
        persistRosterState: (muted) => _persistRosterState(roomId, muted),
        applyMicrophoneState: _applyMicrophoneState,
      );
      return applied ? RoomMuteOutcome.applied : RoomMuteOutcome.busy;
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'failed-precondition' || error.code == 'not-found') {
        // "This room is not currently live." / participant row gone: the
        // authority says this voice session should not exist any more.
        try {
          await _disconnectStaleSession();
        } catch (_) {
          // The disconnect is best-effort; the outcome already tells the
          // surface to stop treating the session as live.
        }
        return RoomMuteOutcome.sessionEnded;
      }
      if (!wasMuted && _readCurrentMuted()) {
        return RoomMuteOutcome.mutedLocally;
      }
      return RoomMuteOutcome.failed;
    } catch (_) {
      if (!wasMuted && _readCurrentMuted()) {
        return RoomMuteOutcome.mutedLocally;
      }
      return RoomMuteOutcome.failed;
    }
  }
}
