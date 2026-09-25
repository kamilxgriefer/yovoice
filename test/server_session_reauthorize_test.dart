import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/audio/realtime_audio_session_registry.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_session.dart';
import 'package:yovoice/features/servers/data/models/server_session_hand.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/data/services/server_session_controller.dart';

import 'server_test_support.dart';

/// Request to speak, controller half: the host's queue, the listener's own
/// document, and the in-place re-mint that replaces "Połączenie zostało
/// przerwane." after a promotion, a demotion or a host/moderator mute
/// (ADR-181's "re-mint under the new grant and reconnect").
///
/// Every provider and backend effect is the deterministic fake's; nothing
/// here proves a real LiveKit reconnect, an audio route or a device.
const _server = Server(
  id: 's',
  name: 'Między słowami',
  description: '',
  ownerId: 'owner',
  type: ServerType.podcast,
  privacy: ServerPrivacy.public,
  schemaVersion: 1,
  activationState: 'active',
);

const _studio = ServerChannel(
  id: 'studio',
  serverId: 's',
  name: 'Studio LIVE',
  kind: ServerChannelKind.stage,
  roomId: 'room',
  activeSessionId: 'gen-7',
  experience: RoomExperience.broadcast,
  mediaMode: ServerMediaMode.audio,
  schemaVersion: 1,
);

ServerSessionParticipantState _own({
  int revision = 1,
  String role = 'listener',
  String fingerprint = 'token-a',
  bool hand = false,
  bool hostMuted = false,
  bool serverMuted = false,
  ServerHandDecision? decision,
}) => ServerSessionParticipantState(
  sessionId: 'gen-7',
  role: role,
  authorizationRevision: revision,
  hostMuted: hostMuted,
  serverMuted: serverMuted,
  isHandRaised: hand,
  handRaisedAt: hand ? DateTime.now() : null,
  handDecision: decision,
  tokenFingerprint: fingerprint,
);

/// Refuses the next [refusals] token requests the way the backend does while
/// a revocation is still converging.
class _RevokingRepository extends TestServerRepository {
  int refusals = 0;
  String refusalCode = 'failed-precondition';

  @override
  Future<ServerSessionConnection> createChannelToken({
    required String serverId,
    required String channelId,
    required String sessionId,
    required String requestId,
  }) {
    if (refusals > 0) {
      refusals--;
      calls.add((
        'createServerChannelTokenV1',
        <String, Object?>{'requestId': requestId},
      ));
      return Future.error(
        FirebaseFunctionsException(
          code: refusalCode,
          message: 'Previous media access is still being revoked',
        ),
      );
    }
    return super.createChannelToken(
      serverId: serverId,
      channelId: channelId,
      sessionId: sessionId,
      requestId: requestId,
    );
  }
}

class _Harness {
  _Harness({
    String sessionRole = 'listener',
    List<String> sources = const [],
    ServerMemberRole role = ServerMemberRole.member,
    List<Duration> backoff = const [
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ],
  }) {
    repository
      ..servers = [_server]
      ..channels = [_studio]
      ..myRole = role
      ..sessionRole = sessionRole
      ..permittedTrackSources = sources
      ..ownParticipantStream = own.stream
      ..sessionHandsStream = hands.stream;
    controller = ServerSessionController(
      repository: repository,
      connector: connector,
      anotherVoiceSessionActive: () => false,
      device: device,
      otherVoiceOwner: ChangeNotifier(),
      realtimeAudioSessions: registry,
      reauthorizationBackoff: backoff,
    );
    controller.addListener(() {
      phases.add(controller.phase);
      if (controller.reauthorization != null) {
        reasons.add(controller.reauthorization!);
      }
    });
  }

  final repository = _RevokingRepository();
  final connector = FakeServerMediaConnector();
  final device = FakeServerVoiceDevice();
  final registry = RealtimeAudioSessionRegistry();
  final own = StreamController<ServerSessionParticipantState?>.broadcast();
  final hands = StreamController<List<ServerSessionHand>>.broadcast();
  late final ServerSessionController controller;
  final phases = <ServerSessionPhase>[];
  final reasons = <ServerSessionReauthorization>[];

  List<String> get tokenRequests => [
    for (final call in repository.calls)
      if (call.$1 == 'createServerChannelTokenV1')
        call.$2['requestId']! as String,
  ];

  Future<void> join() async {
    await controller.join(_server, _studio);
    await settle();
  }

  /// Lets the fake streams, the zero back-off and the fake connector run.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void promote() {
    repository
      ..sessionRole = 'guest'
      ..permittedTrackSources = const ['microphone'];
  }

  Future<void> dispose() async {
    controller.dispose();
    await own.close();
    await hands.close();
  }
}

void main() {
  test(
    'a promotion re-mints in place: same generation, new request id, '
    'nothing released, keep-alive and lease kept, microphone still off',
    () async {
      final h = _Harness();
      await h.join();
      expect(h.controller.phase, ServerSessionPhase.connected);
      expect(h.controller.canPublish, isFalse);
      h.own.add(_own(hand: true));
      await h.settle();
      final first = h.connector.links.single;
      expect(h.registry.activeLeaseCount, 1);

      // The host approves: the listener's own document moves (revision 2, role
      // guest, answer approved) under the token this device still holds.
      h.promote();
      h.own.add(
        _own(revision: 2, role: 'guest', decision: ServerHandDecision.approved),
      );
      await h.settle();

      expect(h.reasons, contains(ServerSessionReauthorization.promoted));
      expect(h.phases, contains(ServerSessionPhase.reconnecting));
      expect(h.phases, isNot(contains(ServerSessionPhase.failed)));
      expect(h.phases, isNot(contains(ServerSessionPhase.idle)));
      expect(h.controller.phase, ServerSessionPhase.connected);
      expect(h.controller.reauthorization, isNull);
      expect(h.controller.error, isNull);
      // One provider link per token: the old one released, the new one live.
      expect(first.disconnects, 1);
      expect(h.connector.links, hasLength(2));
      expect(h.connector.connections.last.$2, 'token-gen-7');
      // Two token requests for the same generation, never the same id twice.
      expect(h.tokenRequests, hasLength(2));
      expect(h.tokenRequests.toSet(), hasLength(2));
      expect(
        h.repository.calls
            .where((call) => call.$1 == 'createServerChannelTokenV1')
            .map((call) => call.$2['sessionId']),
        everyElement('gen-7'),
      );
      // Not a leave: no release signal, no start of a second generation.
      expect(h.repository.releases, isEmpty);
      expect(
        h.repository.calls.map((call) => call.$1),
        isNot(contains('startServerChannelSessionV1')),
      );
      // The device stayed claimed; the keep-alive was told the new grant.
      expect(h.device.keepAliveStops, 0);
      expect(h.device.keepAliveStarts, 2);
      expect(h.device.lastCanPublish, isTrue);
      expect(h.device.speakerRequests, 2);
      expect(h.registry.activeLeaseCount, 1);
      // A promotion grants permission only.
      expect(h.controller.canPublish, isTrue);
      expect(h.controller.isMicrophoneEnabled, isFalse);
      expect(h.connector.links.last.microphoneCalls, isEmpty);
      await h.dispose();
      expect(h.registry.activeLeaseCount, 0);
    },
  );

  test(
    '"still being revoked" is retried with a new request id each time',
    () async {
      final h = _Harness();
      await h.join();
      h.own.add(_own());
      await h.settle();
      h.repository.refusals = 2;
      h.promote();
      h.own.add(_own(revision: 2, role: 'guest'));
      await h.settle();
      expect(h.controller.phase, ServerSessionPhase.connected);
      expect(h.tokenRequests, hasLength(4));
      expect(h.tokenRequests.toSet(), hasLength(4));
      expect(h.connector.links, hasLength(2));
      await h.dispose();
    },
  );

  test('a provider removal while the generation is readable is a re-mint too, '
      'when the document has not caught up yet', () async {
    final h = _Harness(sessionRole: 'guest', sources: const ['microphone']);
    await h.join();
    h.own.add(_own(role: 'guest'));
    await h.settle();
    h.connector.links.single.drop(
      ServerMediaDisconnectReason.participantRemoved,
    );
    await h.settle();
    expect(h.reasons, contains(ServerSessionReauthorization.changed));
    expect(h.controller.phase, ServerSessionPhase.connected);
    expect(h.connector.links, hasLength(2));
    expect(h.device.keepAliveStops, 0);
    await h.dispose();
  });

  for (final (name, before, after, reason) in [
    (
      'a host mute',
      _own(role: 'guest'),
      _own(revision: 2, role: 'guest', hostMuted: true),
      ServerSessionReauthorization.muted,
    ),
    (
      'a moderator mute',
      _own(role: 'guest'),
      _own(revision: 2, role: 'guest', serverMuted: true),
      ServerSessionReauthorization.muted,
    ),
    (
      'releasing a mute',
      _own(role: 'guest', hostMuted: true),
      _own(revision: 2, role: 'guest'),
      ServerSessionReauthorization.unmuted,
    ),
    (
      'a demotion to the audience',
      _own(role: 'guest'),
      _own(revision: 2),
      ServerSessionReauthorization.demoted,
    ),
  ]) {
    test('$name reconnects in place instead of failing', () async {
      final h = _Harness(sessionRole: 'guest', sources: const ['microphone']);
      await h.join();
      h.own.add(before);
      await h.settle();
      if (reason == ServerSessionReauthorization.demoted ||
          reason == ServerSessionReauthorization.muted) {
        h.repository
          ..sessionRole = after.role
          ..permittedTrackSources = const [];
      }
      h.own.add(after);
      await h.settle();
      expect(h.reasons, contains(reason));
      expect(h.phases, isNot(contains(ServerSessionPhase.failed)));
      expect(h.controller.phase, ServerSessionPhase.connected);
      expect(h.controller.error, isNull);
      expect(h.device.keepAliveStops, 0);
      expect(h.repository.releases, isEmpty);
      await h.dispose();
    });
  }

  test('a plain network loss still ends in the honest failure', () async {
    final h = _Harness();
    await h.join();
    h.own.add(_own());
    await h.settle();
    h.connector.links.single.drop(ServerMediaDisconnectReason.other);
    await h.settle();
    expect(h.controller.phase, ServerSessionPhase.failed);
    expect(h.controller.error, isA<ServerSessionDisconnected>());
    expect(h.reasons, isEmpty);
    expect(h.tokenRequests, hasLength(1));
    expect(h.device.keepAliveStops, 1);
    await h.dispose();
  });

  test('the end of the generation is not mistaken for a role change', () async {
    final h = _Harness();
    await h.join();
    h.own.add(_own());
    await h.settle();
    // Ending a generation closes the own-document read, then removes
    // everybody from the provider room.
    h.own.add(null);
    await h.settle();
    h.connector.links.single.drop(
      ServerMediaDisconnectReason.participantRemoved,
    );
    await h.settle();
    expect(h.controller.phase, ServerSessionPhase.failed);
    expect(h.controller.error, isA<ServerSessionDisconnected>());
    expect(h.tokenRequests, hasLength(1));
    await h.dispose();
  });

  test(
    'a re-mint that never gets through gives up into the ordinary failure',
    () async {
      final h = _Harness();
      await h.join();
      h.own.add(_own());
      await h.settle();
      h.repository.refusals = 99;
      h.promote();
      h.own.add(_own(revision: 2, role: 'guest'));
      await h.settle();
      expect(h.controller.phase, ServerSessionPhase.failed);
      expect(h.controller.error, isA<ServerSessionDisconnected>());
      // One request per back-off step, then nothing more.
      expect(h.tokenRequests, hasLength(1 + 3));
      expect(h.device.keepAliveStops, 1);
      await h.dispose();
      expect(h.registry.activeLeaseCount, 0);
    },
  );

  test('a refusal that is not "still being revoked" fails at once', () async {
    final h = _Harness();
    await h.join();
    h.own.add(_own());
    await h.settle();
    h.repository
      ..refusals = 1
      ..refusalCode = 'permission-denied';
    h.own.add(_own(revision: 2, role: 'guest'));
    await h.settle();
    expect(h.controller.phase, ServerSessionPhase.failed);
    expect(h.tokenRequests, hasLength(2));
    await h.dispose();
  });

  test('leaving during a re-mint stops it and asks for nothing more', () async {
    final h = _Harness(backoff: const [Duration(milliseconds: 300)]);
    await h.join();
    h.own.add(_own());
    await h.settle();
    h.own.add(_own(revision: 2, role: 'guest'));
    await h.settle();
    expect(h.controller.phase, ServerSessionPhase.reconnecting);
    await h.controller.leave();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await h.settle();
    expect(h.controller.phase, ServerSessionPhase.idle);
    expect(h.tokenRequests, hasLength(1));
    expect(h.connector.links, hasLength(1));
    expect(h.registry.activeLeaseCount, 0);
    await h.dispose();
  });

  test('leaving with a raised hand takes the request back', () async {
    final h = _Harness();
    await h.join();
    h.own.add(_own(hand: true));
    await h.settle();
    await h.controller.leave();
    await h.settle();
    final lower = h.repository.calls.lastWhere(
      (call) => call.$1 == 'setServerSessionHandV1',
    );
    expect(lower.$2['raised'], isFalse);
    expect(lower.$2['sessionId'], 'gen-7');
    await h.dispose();
  });

  test('leaving without a raised hand sends no hand call', () async {
    final h = _Harness();
    await h.join();
    h.own.add(_own());
    await h.settle();
    await h.controller.leave();
    await h.settle();
    expect(
      h.repository.calls.map((call) => call.$1),
      isNot(contains('setServerSessionHandV1')),
    );
    await h.dispose();
  });

  group('the host queue', () {
    const kamil = ServerMediaParticipant(
      identity: 'kamil',
      name: 'Kamil',
      isLocal: false,
      sessionRole: 'listener',
    );
    final kamilHand = ServerSessionHand(
      userId: 'kamil',
      displayName: 'Kamil',
      role: 'listener',
      raisedAt: DateTime(2026, 9, 25, 18),
    );
    final olaHand = ServerSessionHand(
      userId: 'ola',
      displayName: 'Ola',
      role: 'listener',
      raisedAt: DateTime(2026, 9, 25, 17),
    );

    test('the session host reads exactly the live generation and sees only '
        'people still in it', () async {
      final h = _Harness(sessionRole: 'host', sources: const ['microphone']);
      await h.join();
      expect(h.controller.canAnswerHands, isTrue);
      expect(h.repository.handQueueReads, [
        {
          'roomId': 'room',
          'serverId': 's',
          'channelId': 'studio',
          'sessionId': 'gen-7',
        },
      ]);
      h.connector.links.single.setRoster(const [kamil]);
      h.hands.add([olaHand, kamilHand]);
      await h.settle();
      // Ola asked and then left: never offered.
      expect(h.controller.raisedHands, [kamilHand]);
      await h.dispose();
    });

    test(
      'a listener never reads the queue; a moderator listener does',
      () async {
        final listener = _Harness();
        await listener.join();
        expect(listener.controller.canAnswerHands, isFalse);
        expect(listener.repository.handQueueReads, isEmpty);
        listener.hands.add([kamilHand]);
        await listener.settle();
        expect(listener.controller.raisedHands, isEmpty);
        await listener.dispose();

        final moderator = _Harness(role: ServerMemberRole.moderator);
        await moderator.join();
        expect(moderator.controller.canAnswerHands, isTrue);
        expect(moderator.repository.handQueueReads, hasLength(1));
        await moderator.dispose();
      },
    );

    test('approve promotes, decline answers, and a refused answer is kept '
        'for the surface', () async {
      final h = _Harness(sessionRole: 'host', sources: const ['microphone']);
      await h.join();
      h.connector.links.single.setRoster(const [kamil]);
      h.hands.add([kamilHand]);
      await h.settle();

      await h.controller.approveHand(kamilHand);
      final approve = h.repository.calls.last;
      expect(approve.$1, 'setServerSessionParticipantRoleV1');
      expect(approve.$2['participantId'], 'kamil');
      expect(approve.$2['role'], 'guest');
      expect(approve.$2['sessionId'], 'gen-7');

      await h.controller.declineHand(kamilHand);
      final decline = h.repository.calls.last;
      expect(decline.$1, 'answerServerSessionHandV1');
      expect(decline.$2['participantId'], 'kamil');
      expect(decline.$2['decision'], 'declined');
      expect(decline.$2['requestId'], isNot(approve.$2['requestId']));

      h.repository.failNextCall['answerServerSessionHandV1'] =
          FirebaseFunctionsException(code: 'unavailable', message: 'offline');
      await h.controller.declineHand(kamilHand);
      expect(h.controller.handAnswerError, isA<FirebaseFunctionsException>());
      expect(h.controller.isAnsweringHand('kamil'), isFalse);
      await h.dispose();
    });

    test('leaving ends every subscription the generation opened', () async {
      final h = _Harness(sessionRole: 'host', sources: const ['microphone']);
      await h.join();
      expect(h.own.hasListener, isTrue);
      expect(h.hands.hasListener, isTrue);
      await h.controller.leave();
      expect(h.own.hasListener, isFalse);
      expect(h.hands.hasListener, isFalse);
      expect(h.controller.canAnswerHands, isFalse);
      expect(h.controller.ownParticipant, isNull);
      await h.dispose();
    });
  });
}
