import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/rooms/data/services/room_mute_sync.dart';

void main() {
  test('clears the roster before enabling the microphone', () async {
    final persisted = Completer<void>();
    final events = <String>[];
    final sync = RoomMuteSync();

    final operation = sync.toggle(
      currentMuted: true,
      persistRosterState: (muted) async {
        events.add('persist:$muted');
        await persisted.future;
      },
      applyMicrophoneState: (muted) async {
        events.add('microphone:$muted');
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(events, ['persist:false']);
    expect(sync.isBusy, isTrue);

    persisted.complete();
    expect(await operation, isTrue);
    expect(events, ['persist:false', 'microphone:false']);
    expect(sync.isBusy, isFalse);
  });

  test('disables the microphone before persisting mute', () async {
    final events = <String>[];
    final sync = RoomMuteSync();

    await sync.toggle(
      currentMuted: false,
      persistRosterState: (muted) async => events.add('persist:$muted'),
      applyMicrophoneState: (muted) async => events.add('microphone:$muted'),
    );

    expect(events, ['microphone:true', 'persist:true']);
  });

  test('does not unmute LiveKit when the roster write is rejected', () async {
    final microphoneStates = <bool>[];
    final sync = RoomMuteSync();

    await expectLater(
      sync.toggle(
        currentMuted: true,
        persistRosterState: (_) async => throw StateError('denied'),
        applyMicrophoneState: (muted) async => microphoneStates.add(muted),
      ),
      throwsStateError,
    );

    expect(microphoneStates, isEmpty);
    expect(sync.isBusy, isFalse);
  });

  test('local mute does not wait for the network', () async {
    final persisted = Completer<void>();
    final events = <String>[];
    final sync = RoomMuteSync();

    final operation = sync.toggle(
      currentMuted: false,
      persistRosterState: (muted) async {
        events.add('persist:$muted');
        await persisted.future;
      },
      applyMicrophoneState: (muted) async {
        events.add('microphone:$muted');
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(events, ['microphone:true', 'persist:true']);
    expect(sync.isBusy, isTrue);
    persisted.complete();
    expect(await operation, isTrue);
  });

  test('ignores a second tap while synchronization is in progress', () async {
    final persisted = Completer<void>();
    var persistCalls = 0;
    final sync = RoomMuteSync();

    final first = sync.toggle(
      currentMuted: true,
      persistRosterState: (_) async {
        persistCalls += 1;
        await persisted.future;
      },
      applyMicrophoneState: (_) async {},
    );
    final second = await sync.toggle(
      currentMuted: true,
      persistRosterState: (_) async => persistCalls += 1,
      applyMicrophoneState: (_) async {},
    );

    expect(second, isFalse);
    expect(persistCalls, 1);
    persisted.complete();
    expect(await first, isTrue);
  });
}
