import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/rooms/data/services/room_mute_coordinator.dart';

/// The platform constructor is @protected; a subclass is the supported way
/// to build the exact exception shape production callables raise.
class _ServerRefusal extends FirebaseFunctionsException {
  _ServerRefusal(String code) : super(code: code, message: 'refused');
}

class _Harness {
  _Harness({bool muted = true, this.persistError}) : _muted = muted {
    coordinator = RoomMuteCoordinator(
      persistRosterState: (roomId, targetMuted) async {
        events.add('persist:$roomId:$targetMuted');
        final error = persistError;
        if (error != null) throw error;
      },
      applyMicrophoneState: (targetMuted) async {
        events.add('apply:$targetMuted');
        _muted = targetMuted;
      },
      readCurrentMuted: () => _muted,
      disconnectStaleSession: () async => events.add('disconnect'),
    );
  }

  final Object? persistError;
  final List<String> events = [];
  bool _muted;
  late final RoomMuteCoordinator coordinator;
}

void main() {
  test('toggle persists the roster before touching the microphone', () async {
    final harness = _Harness(muted: true);

    final outcome = await harness.coordinator.toggle(roomId: 'room-1');

    expect(outcome, RoomMuteOutcome.applied);
    expect(harness.events, ['persist:room-1:false', 'apply:false']);
  });

  test('mute changes the local track before the roster round trip', () async {
    final harness = _Harness(muted: false);

    final outcome = await harness.coordinator.toggle(roomId: 'room-1');

    expect(outcome, RoomMuteOutcome.applied);
    expect(harness.events, ['apply:true', 'persist:room-1:true']);
  });

  test('a not-live refusal tears down the stale session', () async {
    final harness = _Harness(
      persistError: _ServerRefusal('failed-precondition'),
    );

    final outcome = await harness.coordinator.toggle(roomId: 'room-1');

    expect(outcome, RoomMuteOutcome.sessionEnded);
    expect(harness.events, ['persist:room-1:false', 'disconnect']);
  });

  test('a missing participant refusal tears down the stale session', () async {
    final harness = _Harness(persistError: _ServerRefusal('not-found'));

    final outcome = await harness.coordinator.toggle(roomId: 'room-1');

    expect(outcome, RoomMuteOutcome.sessionEnded);
    expect(harness.events.last, 'disconnect');
  });

  test('a transient failure keeps the session and reports failed', () async {
    final harness = _Harness(persistError: _ServerRefusal('internal'));

    final outcome = await harness.coordinator.toggle(roomId: 'room-1');

    expect(outcome, RoomMuteOutcome.failed);
    expect(harness.events, ['persist:room-1:false']);
  });

  test('a non-Firebase failure reports failed without disconnecting', () async {
    final harness = _Harness(persistError: StateError('offline'));

    final outcome = await harness.coordinator.toggle(roomId: 'room-1');

    expect(outcome, RoomMuteOutcome.failed);
    expect(harness.events, ['persist:room-1:false']);
  });

  test('a failed roster sync keeps the privacy-critical local mute', () async {
    final harness = _Harness(
      muted: false,
      persistError: _ServerRefusal('internal'),
    );

    final outcome = await harness.coordinator.toggle(roomId: 'room-1');

    expect(outcome, RoomMuteOutcome.mutedLocally);
    expect(harness.events, ['apply:true', 'persist:room-1:true']);
  });

  test('a second toggle while one is in flight reports busy', () async {
    final gate = Completer<void>();
    final events = <String>[];
    var muted = true;
    final coordinator = RoomMuteCoordinator(
      persistRosterState: (roomId, targetMuted) async {
        events.add('persist:$targetMuted');
        await gate.future;
      },
      applyMicrophoneState: (targetMuted) async {
        events.add('apply:$targetMuted');
        muted = targetMuted;
      },
      readCurrentMuted: () => muted,
      disconnectStaleSession: () async => events.add('disconnect'),
    );

    final first = coordinator.toggle(roomId: 'room-1');
    final second = await coordinator.toggle(roomId: 'room-1');

    expect(second, RoomMuteOutcome.busy);
    expect(coordinator.isBusy, isTrue);
    gate.complete();
    expect(await first, RoomMuteOutcome.applied);
    expect(coordinator.isBusy, isFalse);
    // Exactly one persist and one apply: the double tap did not double-fire.
    expect(events, ['persist:false', 'apply:false']);
  });

  test('busy state notifies listeners for every surface', () async {
    final harness = _Harness(muted: false);
    final observed = <bool>[];
    harness.coordinator.addListener(
      () => observed.add(harness.coordinator.isBusy),
    );

    await harness.coordinator.toggle(roomId: 'room-1');

    expect(observed, [true, false]);
    expect(harness.events, ['apply:true', 'persist:room-1:true']);
  });

  test(
    'a stalled unmute becomes a retryable failure, not a hung control',
    () async {
      // `RoomService.setMuted` now carries a 15 s deadline, so a cold or stalled
      // `setOwnRoomParticipantMute` raises this instead of holding the control
      // for the plugin's full 60 s. It must NOT read as "this session is gone".
      final harness = _Harness(
        persistError: _ServerRefusal('deadline-exceeded'),
      );

      final outcome = await harness.coordinator.toggle(roomId: 'room-1');

      expect(outcome, RoomMuteOutcome.failed);
      expect(harness.events, ['persist:room-1:false']);
      expect(
        harness.events,
        isNot(contains('disconnect')),
        reason: 'A slow server is not a dead session.',
      );
      expect(harness.coordinator.isBusy, isFalse);
      expect(harness.coordinator.pendingUnmute, isFalse);
    },
  );

  test('the unmute wait is visible while it lasts', () async {
    final gate = Completer<void>();
    var muted = true;
    final coordinator = RoomMuteCoordinator(
      persistRosterState: (_, _) => gate.future,
      applyMicrophoneState: (targetMuted) async => muted = targetMuted,
      readCurrentMuted: () => muted,
      disconnectStaleSession: () async {},
    );

    expect(coordinator.pendingUnmute, isFalse);
    final operation = coordinator.toggle(roomId: 'room-1');
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.isBusy, isTrue);
    expect(
      coordinator.pendingUnmute,
      isTrue,
      reason:
          'Unmute stays server-first (ADR-149); the only honest improvement '
          'is naming the wait instead of showing a dead control.',
    );

    gate.complete();
    expect(await operation, RoomMuteOutcome.applied);
    expect(coordinator.pendingUnmute, isFalse);
  });

  test('a mute never reports a pending wait', () async {
    final gate = Completer<void>();
    var muted = false;
    final coordinator = RoomMuteCoordinator(
      persistRosterState: (_, _) => gate.future,
      applyMicrophoneState: (targetMuted) async => muted = targetMuted,
      readCurrentMuted: () => muted,
      disconnectStaleSession: () async {},
    );

    final operation = coordinator.toggle(roomId: 'room-1');
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.isBusy, isFalse);
    expect(coordinator.pendingUnmute, isFalse);
    gate.complete();
    expect(await operation, RoomMuteOutcome.applied);
  });

  test(
    'a stale server refusal never disconnects the replacement room',
    () async {
      final gate = Completer<void>();
      final events = <String>[];
      var current = true;
      var muted = true;
      final coordinator = RoomMuteCoordinator(
        persistRosterState: (roomId, targetMuted) async {
          events.add('persist:$roomId:$targetMuted');
          await gate.future;
          throw _ServerRefusal('not-found');
        },
        applyMicrophoneState: (targetMuted) async {
          events.add('apply:$targetMuted');
          muted = targetMuted;
        },
        readCurrentMuted: () => muted,
        disconnectStaleSession: () async => events.add('disconnect'),
      );

      final operation = coordinator.toggle(
        roomId: 'room-1',
        isOperationCurrent: () => current,
      );
      await Future<void>.delayed(Duration.zero);
      current = false;
      gate.complete();

      expect(await operation, RoomMuteOutcome.busy);
      expect(events, ['persist:room-1:false']);
      expect(coordinator.isBusy, isFalse);
    },
  );
}
