import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/audio/realtime_audio_session_registry.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_session_controller.dart';

import 'server_test_support.dart';

// Leaving a server conversation sends one best-effort release signal for the
// generation this device was connected to (releaseServerChannelSessionIfEmptyV1).
// The backend decides, on its own clock, whether the room stayed empty for the
// whole reconnect grace; leaving never waits for that answer and never fails
// because of it.

const _server = Server(
  id: 's',
  name: 'Serwer',
  description: '',
  ownerId: 'owner',
  type: ServerType.friends,
  privacy: ServerPrivacy.inviteOnly,
  schemaVersion: 1,
  activationState: 'active',
);

const _lounge = ServerChannel(
  id: 'lounge',
  serverId: 's',
  name: 'Lounge',
  kind: ServerChannelKind.voice,
);

const _gaming = ServerChannel(
  id: 'gaming',
  serverId: 's',
  name: 'Gaming',
  kind: ServerChannelKind.voice,
);

ServerSessionController _controller(
  TestServerRepository repository,
  FakeServerMediaConnector connector, {
  bool Function()? anotherVoiceSessionActive,
}) {
  final otherVoiceOwner = ChangeNotifier();
  final controller = ServerSessionController(
    repository: repository,
    connector: connector,
    anotherVoiceSessionActive: anotherVoiceSessionActive ?? () => false,
    otherVoiceOwner: otherVoiceOwner,
    device: FakeServerVoiceDevice(),
    realtimeAudioSessions: RealtimeAudioSessionRegistry(),
  );
  addTearDown(() {
    controller.dispose();
    otherVoiceOwner.dispose();
  });
  return controller;
}

void main() {
  testWidgets(
    'leave() after a connected generation releases exactly that generation '
    'once, after the link is gone, and never ends it',
    (tester) async {
      final repository = TestServerRepository();
      final connector = FakeServerMediaConnector();
      final controller = _controller(repository, connector);
      await controller.join(_server, _lounge);
      expect(controller.phase, ServerSessionPhase.connected);
      final sessionId = repository.calls[1].$2['sessionId'];
      final link = connector.links.single;
      expect(repository.releases, isEmpty, reason: 'joining releases nothing');

      await controller.leave();
      await tester.pump();

      expect(link.disconnects, 1);
      expect(controller.phase, ServerSessionPhase.idle);
      expect(repository.releases, [
        {
          'serverId': 's',
          'channelId': 'lounge',
          'sessionId': sessionId,
          'requestId': 'request-3',
        },
      ]);
      expect(
        repository.calls.map((call) => call.$1),
        ['startServerChannelSessionV1', 'createServerChannelTokenV1'],
        reason: 'leaving never ends the generation for everybody',
      );
    },
  );

  testWidgets('a failing release never blocks or breaks leaving', (
    tester,
  ) async {
    final repository = TestServerRepository()
      ..failNextRelease = FirebaseFunctionsException(
        code: 'unavailable',
        message: 'Offline',
      );
    final connector = FakeServerMediaConnector();
    final controller = _controller(repository, connector);
    await controller.join(_server, _lounge);
    final link = connector.links.single;

    await controller.leave();
    await tester.pump();

    expect(repository.releases, hasLength(1));
    expect(link.disconnects, 1);
    expect(controller.phase, ServerSessionPhase.idle);
    expect(controller.isActive, isFalse);
    expect(controller.error, isNull);
    expect(tester.takeException(), isNull);
    // Leaving stays reversible after a failed signal.
    await controller.join(_server, _lounge);
    expect(controller.phase, ServerSessionPhase.connected);
  });

  testWidgets(
    'nothing is released for a join that never reached the provider, a '
    'blocked join, or a generation endSession() already ended',
    (tester) async {
      final failing = TestServerRepository();
      final unreachable = FakeServerMediaConnector()
        ..failWith = StateError('no provider');
      final failed = _controller(failing, unreachable);
      await failed.join(_server, _lounge);
      expect(failed.phase, ServerSessionPhase.failed);
      await failed.leave();
      await tester.pump();
      expect(failing.releases, isEmpty);

      final blockedRepository = TestServerRepository();
      final blocked = _controller(
        blockedRepository,
        FakeServerMediaConnector(),
        anotherVoiceSessionActive: () => true,
      );
      await blocked.join(_server, _lounge);
      expect(blocked.phase, ServerSessionPhase.blocked);
      await blocked.leave();
      await tester.pump();
      expect(blockedRepository.releases, isEmpty);
      expect(blockedRepository.calls, isEmpty);

      final ending = TestServerRepository();
      final connector = FakeServerMediaConnector();
      final host = _controller(ending, connector);
      await host.join(_server, _lounge);
      await host.endSession();
      await tester.pump();
      expect(connector.links.single.disconnects, 1);
      expect(host.phase, ServerSessionPhase.idle);
      expect(
        ending.calls.map((call) => call.$1),
        contains('endServerChannelSessionV1'),
      );
      expect(ending.releases, isEmpty);
    },
  );

  testWidgets(
    'moving to another media channel releases the one it left, exactly once',
    (tester) async {
      final repository = TestServerRepository();
      final connector = FakeServerMediaConnector();
      final controller = _controller(repository, connector);
      await controller.join(_server, _lounge);
      await controller.join(_server, _gaming);
      await tester.pump();
      expect(controller.isIn('gaming'), isTrue);
      expect(repository.releases.map((release) => release['channelId']), [
        'lounge',
      ]);
    },
  );

  testWidgets(
    'a pending receipt schedules one re-check when the backend grace runs '
    'out; rejoining that channel or disposing cancels it',
    (tester) async {
      final repository = TestServerRepository()
        ..releaseOutcome = 'pending'
        ..releaseRecheckAfter = const Duration(seconds: 60);
      final controller = _controller(repository, FakeServerMediaConnector());
      await controller.join(_server, _lounge);
      await controller.leave();
      await tester.pump();
      expect(repository.releases, hasLength(1));
      await tester.pump(const Duration(seconds: 59));
      expect(repository.releases, hasLength(1));
      await tester.pump(const Duration(seconds: 3));
      expect(repository.releases, hasLength(2));
      expect(
        repository.releases[1]['sessionId'],
        repository.releases[0]['sessionId'],
      );
      expect(
        repository.releases[1]['requestId'],
        isNot(repository.releases[0]['requestId']),
        reason: 'a re-check is a new request, never a replay',
      );
      // The re-check answered `pending` again: nothing more is scheduled.
      await tester.pump(const Duration(minutes: 5));
      expect(repository.releases, hasLength(2));

      // Rejoining the same channel inside the grace: this device is the
      // rejoin, so it never asks again.
      final rejoining = TestServerRepository()
        ..releaseOutcome = 'pending'
        ..releaseRecheckAfter = const Duration(seconds: 60);
      final again = _controller(rejoining, FakeServerMediaConnector());
      await again.join(_server, _lounge);
      await again.leave();
      await tester.pump();
      await again.join(_server, _lounge);
      await tester.pump(const Duration(minutes: 2));
      expect(rejoining.releases, hasLength(1));

      final disposing = TestServerRepository()
        ..releaseOutcome = 'pending'
        ..releaseRecheckAfter = const Duration(seconds: 60);
      final gone = _controller(disposing, FakeServerMediaConnector());
      await gone.join(_server, _lounge);
      await gone.leave();
      await tester.pump();
      gone.dispose();
      await tester.pump(const Duration(minutes: 2));
      expect(disposing.releases, hasLength(1));
    },
  );
}
