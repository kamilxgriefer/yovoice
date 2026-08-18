import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/rooms/data/services/room_leave_coordinator.dart';

void main() {
  test('navigates away before participant cleanup completes', () async {
    final cleanup = Completer<void>();
    final events = <String>[];
    final coordinator = RoomLeaveCoordinator();

    final result = await coordinator.leave(
      disconnectAudio: () async => events.add('disconnect'),
      navigateAway: () => events.add('navigate'),
      cleanupParticipant: () async {
        events.add('cleanup-start');
        await cleanup.future;
      },
    );

    expect(result, isTrue);
    expect(events, ['disconnect', 'navigate', 'cleanup-start']);
    cleanup.complete();
  });

  test('cleanup failure cannot prevent navigation', () async {
    final errors = <Object>[];
    final events = <String>[];
    final coordinator = RoomLeaveCoordinator();

    await coordinator.leave(
      disconnectAudio: () async => events.add('disconnect'),
      navigateAway: () => events.add('navigate'),
      cleanupParticipant: () async => throw StateError('offline'),
      onCleanupError: (error, _) => errors.add(error),
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, ['disconnect', 'navigate']);
    expect(errors.single, isA<StateError>());
  });

  test('disconnect failure cannot prevent navigation or cleanup', () async {
    final events = <String>[];
    final coordinator = RoomLeaveCoordinator();

    await coordinator.leave(
      disconnectAudio: () async => throw StateError('transport'),
      navigateAway: () => events.add('navigate'),
      cleanupParticipant: () async => events.add('cleanup'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, ['navigate', 'cleanup']);
  });

  test('a second leave tap is ignored', () async {
    final disconnect = Completer<void>();
    var navigations = 0;
    final coordinator = RoomLeaveCoordinator();

    final first = coordinator.leave(
      disconnectAudio: () => disconnect.future,
      navigateAway: () => navigations += 1,
      cleanupParticipant: () async {},
    );
    final second = await coordinator.leave(
      disconnectAudio: () async {},
      navigateAway: () => navigations += 1,
      cleanupParticipant: () async {},
    );

    expect(second, isFalse);
    disconnect.complete();
    expect(await first, isTrue);
    expect(navigations, 1);
  });
}
