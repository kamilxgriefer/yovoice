import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/rooms/data/services/room_leave_coordinator.dart';

/// Mirrors exactly how BroadcastRoomScreen/CommunityVoiceRoomScreen wire the
/// coordinator: disconnect → Navigator.pop() → background cleanup. The real
/// screens cannot be pumped here (they construct Firebase singletons), so
/// this pins the navigation contract with a real Navigator instead.
class _RoomScreenHarness extends StatefulWidget {
  const _RoomScreenHarness({
    required this.disconnectAudio,
    required this.cleanupParticipant,
  });

  final Future<void> Function() disconnectAudio;
  final Future<void> Function() cleanupParticipant;

  @override
  State<_RoomScreenHarness> createState() => _RoomScreenHarnessState();
}

class _RoomScreenHarnessState extends State<_RoomScreenHarness> {
  final RoomLeaveCoordinator _leaveCoordinator = RoomLeaveCoordinator();

  Future<void> _leave() async {
    if (_leaveCoordinator.isLeaving) return;
    await _leaveCoordinator.leave(
      disconnectAudio: widget.disconnectAudio,
      navigateAway: () {
        if (mounted) Navigator.of(context).pop();
      },
      cleanupParticipant: widget.cleanupParticipant,
      onCleanupError: (_, _) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(onPressed: _leave, child: const Text('Leave')),
      ),
    );
  }
}

Future<void> _pumpRoom(
  WidgetTester tester, {
  required Future<void> Function() disconnectAudio,
  required Future<void> Function() cleanupParticipant,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _RoomScreenHarness(
                    disconnectAudio: disconnectAudio,
                    cleanupParticipant: cleanupParticipant,
                  ),
                ),
              ),
              child: const Text('Enter room'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Enter room'));
  await tester.pumpAndSettle();
  expect(find.text('Leave'), findsOneWidget);
}

void main() {
  testWidgets('Leave closes the room screen even when cleanup fails', (
    tester,
  ) async {
    final cleanupAttempted = Completer<void>();
    await _pumpRoom(
      tester,
      disconnectAudio: () async {},
      cleanupParticipant: () async {
        cleanupAttempted.complete();
        throw StateError('leaveRoomSelf INTERNAL');
      },
    );

    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();

    // Back on the previous screen with no manual Back press.
    expect(find.text('Leave'), findsNothing);
    expect(find.text('Enter room'), findsOneWidget);
    expect(cleanupAttempted.isCompleted, isTrue);
  });

  testWidgets('Leave closes the room screen while cleanup is still pending', (
    tester,
  ) async {
    final cleanupGate = Completer<void>();
    await _pumpRoom(
      tester,
      disconnectAudio: () async {},
      cleanupParticipant: () => cleanupGate.future,
    );

    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();

    // Navigation must not wait for the server round-trip.
    expect(find.text('Enter room'), findsOneWidget);
    cleanupGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Enter room'), findsOneWidget);
  });

  testWidgets('a double tap on Leave pops exactly once', (tester) async {
    final disconnectGate = Completer<void>();
    await _pumpRoom(
      tester,
      disconnectAudio: () => disconnectGate.future,
      cleanupParticipant: () async {},
    );

    await tester.tap(find.text('Leave'));
    await tester.pump();
    // Second tap while the first leave is still disconnecting audio.
    await tester.tap(find.text('Leave'));
    await tester.pump();

    disconnectGate.complete();
    await tester.pumpAndSettle();

    // A double pop would have thrown or removed the root screen; the
    // previous route must be exactly what remains.
    expect(find.text('Enter room'), findsOneWidget);
    expect(find.text('Leave'), findsNothing);
  });
}
