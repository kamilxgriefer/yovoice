import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/rooms/presentation/room_mic_affordance.dart';

/// The affordance must match the authority.
///
/// A mute/unmute control implies a live session and a token that already
/// exists. Offering one in a dormant room is exactly the reported failure:
/// press unmute, get "This room is not currently live." from
/// `setOwnRoomParticipantMute`. This mapping is the structural guarantee that
/// the state cannot be reached, and the exhaustive case below is the one that
/// keeps it true as [MicState] grows.
void main() {
  test('NO MicState can produce a mute control in a room that is not live', () {
    for (final micState in MicState.values) {
      expect(
        roomMicAffordance(
          roomIsLive: false,
          canStartVoice: false,
          micState: micState,
        ).isMuteControl,
        isFalse,
        reason: 'dormant + $micState must never offer mute',
      );
      expect(
        roomMicAffordance(
          roomIsLive: false,
          canStartVoice: true,
          micState: micState,
        ).isMuteControl,
        isFalse,
        reason: 'dormant + $micState must never offer mute',
      );
    }
  });

  test('a dormant room offers a start ONLY to someone who may start it', () {
    expect(
      roomMicAffordance(
        roomIsLive: false,
        canStartVoice: true,
        micState: MicState.unavailable,
      ),
      RoomMicAffordance.startVoice,
    );
    expect(
      roomMicAffordance(
        roomIsLive: false,
        canStartVoice: false,
        micState: MicState.unavailable,
      ),
      RoomMicAffordance.waitingForHost,
    );
  });

  test('a dormant room never reads as broken audio — "OFFLINE" describes a '
      'failed transport, not a room nobody has opened yet', () {
    expect(
      roomMicAffordance(
        roomIsLive: false,
        canStartVoice: false,
        micState: MicState.unavailable,
      ),
      isNot(RoomMicAffordance.unavailable),
    );
  });

  test('a live room maps the audio session straight through', () {
    RoomMicAffordance forState(MicState state) => roomMicAffordance(
      roomIsLive: true,
      canStartVoice: false,
      micState: state,
    );

    expect(forState(MicState.on), RoomMicAffordance.live);
    expect(forState(MicState.muted), RoomMicAffordance.muted);
    expect(forState(MicState.connecting), RoomMicAffordance.connecting);
    expect(forState(MicState.listenOnly), RoomMicAffordance.listenOnly);
    expect(forState(MicState.unavailable), RoomMicAffordance.unavailable);
  });

  test('exactly two states are mute controls and exactly one is a start', () {
    expect(RoomMicAffordance.values.where((a) => a.isMuteControl).toSet(), {
      RoomMicAffordance.live,
      RoomMicAffordance.muted,
    });
    expect(RoomMicAffordance.values.where((a) => a.isStartControl).toSet(), {
      RoomMicAffordance.startVoice,
    });
  });
}
