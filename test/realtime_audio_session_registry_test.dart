import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/audio/realtime_audio_session_registry.dart';
import 'package:yovoice/features/rooms/data/models/room_experience.dart';
import 'package:yovoice/features/servers/data/models/server.dart';
import 'package:yovoice/features/servers/data/models/server_channel.dart';
import 'package:yovoice/features/servers/data/models/server_session.dart';
import 'package:yovoice/features/servers/data/models/server_type.dart';
import 'package:yovoice/features/servers/data/services/server_media_connector.dart';
import 'package:yovoice/features/servers/data/services/server_session_controller.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/data/services/server_voice_device.dart';

void main() {
  test('direct and Server leases jointly block media configuration', () async {
    final registry = RealtimeAudioSessionRegistry();
    final direct = await registry.acquire(
      owner: Object(),
      kind: RealtimeAudioSessionOwnerKind.directOrLegacyCall,
    );
    final server = await registry.acquire(
      owner: Object(),
      kind: RealtimeAudioSessionOwnerKind.serverConversation,
    );
    var configurations = 0;

    expect(registry.activeLeaseCount, 2);
    expect(registry.activeKinds, RealtimeAudioSessionOwnerKind.values.toSet());
    expect(
      await registry.configureMediaWhenRealtimeIdle(
        () async => configurations++,
      ),
      isFalse,
    );
    expect(configurations, 0);

    direct.release();
    direct.release();
    expect(registry.activeLeaseCount, 1);
    expect(
      await registry.configureMediaWhenRealtimeIdle(
        () async => configurations++,
      ),
      isFalse,
    );

    server.release();
    expect(
      await registry.configureMediaWhenRealtimeIdle(
        () async => configurations++,
      ),
      isTrue,
    );
    expect(configurations, 1);
  });

  test('join intent waits for an in-flight media route write', () async {
    final registry = RealtimeAudioSessionRegistry();
    final configurationStarted = Completer<void>();
    final finishConfiguration = Completer<void>();
    final configuration = registry.configureMediaWhenRealtimeIdle(() async {
      configurationStarted.complete();
      await finishConfiguration.future;
    });
    await configurationStarted.future;

    final acquisition = registry.acquire(
      owner: Object(),
      kind: RealtimeAudioSessionOwnerKind.directOrLegacyCall,
    );
    var acquired = false;
    unawaited(acquisition.then((_) => acquired = true));
    await Future<void>.delayed(Duration.zero);

    expect(acquired, isFalse);
    expect(registry.pendingAcquisitionCount, 1);
    final competingConfiguration = registry.configureMediaWhenRealtimeIdle(
      () async {},
    );

    finishConfiguration.complete();
    expect(await configuration, isTrue);
    final lease = await acquisition;
    expect(
      await competingConfiguration,
      isFalse,
      reason: 'A queued RTC join wins over another media route write.',
    );
    expect(registry.activeLeaseCount, 1);
    lease.release();
  });

  test(
    'Server controller keeps its lease until native disconnect finishes',
    () async {
      final registry = RealtimeAudioSessionRegistry();
      final otherVoiceOwner = ChangeNotifier();
      final link = _GatedServerMediaLink();
      final controller = ServerSessionController(
        repository: _SessionRepository(),
        connector: _FixedServerMediaConnector(link),
        anotherVoiceSessionActive: () => false,
        otherVoiceOwner: otherVoiceOwner,
        device: const _NoopServerVoiceDevice(),
        realtimeAudioSessions: registry,
      );
      addTearDown(() {
        controller.dispose();
        otherVoiceOwner.dispose();
      });

      await controller.join(_server, _meetingChannel);
      expect(controller.phase, ServerSessionPhase.connected);
      expect(registry.activeKinds, {
        RealtimeAudioSessionOwnerKind.serverConversation,
      });

      final leaving = controller.leave();
      await link.disconnectStarted.future;
      expect(controller.phase, ServerSessionPhase.leaving);
      expect(registry.activeLeaseCount, 1);

      link.allowDisconnect.complete();
      await leaving;
      expect(controller.phase, ServerSessionPhase.idle);
      expect(registry.activeLeaseCount, 0);
    },
  );

  test(
    'Server yields when a direct call starts before its provider connects',
    () async {
      final registry = RealtimeAudioSessionRegistry();
      final otherVoiceOwner = ChangeNotifier();
      final link = _GatedServerMediaLink();
      var directCallActive = false;
      final controller = ServerSessionController(
        repository: _SessionRepository(),
        connector: _HookedServerMediaConnector(() {
          directCallActive = true;
          // This notification occurs before Server has subscribed. The
          // post-subscription state check must still observe it.
          otherVoiceOwner.notifyListeners();
          return link;
        }),
        anotherVoiceSessionActive: () => directCallActive,
        otherVoiceOwner: otherVoiceOwner,
        device: const _NoopServerVoiceDevice(),
        realtimeAudioSessions: registry,
      );
      addTearDown(() {
        controller.dispose();
        otherVoiceOwner.dispose();
      });

      await controller.join(_server, _meetingChannel);
      await link.disconnectStarted.future;

      expect(controller.phase, ServerSessionPhase.leaving);
      expect(registry.activeLeaseCount, 1);
      link.allowDisconnect.complete();
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, ServerSessionPhase.idle);
      expect(registry.activeLeaseCount, 0);
    },
  );
}

const _server = Server(
  id: 'server',
  name: 'Company',
  description: 'Team',
  ownerId: 'owner',
  type: ServerType.company,
  privacy: ServerPrivacy.inviteOnly,
  defaultChannelId: 'meeting',
  schemaVersion: 1,
  templateVersion: 1,
  revision: 1,
  activationState: 'active',
);

const _meetingChannel = ServerChannel(
  id: 'meeting',
  serverId: 'server',
  name: 'Meeting',
  kind: ServerChannelKind.meeting,
  position: 0,
  access: ServerChannelAccess.members,
  roomId: 'room',
  experience: RoomExperience.community,
  mediaMode: ServerMediaMode.meeting,
  schemaVersion: 1,
  revision: 1,
  aclRevision: 1,
);

final class _FixedServerMediaConnector implements ServerMediaConnector {
  const _FixedServerMediaConnector(this.link);

  final ServerMediaLink link;

  @override
  Future<ServerMediaLink> connect({
    required String serverUrl,
    required String token,
  }) async => link;
}

final class _HookedServerMediaConnector implements ServerMediaConnector {
  const _HookedServerMediaConnector(this.connectLink);

  final ServerMediaLink Function() connectLink;

  @override
  Future<ServerMediaLink> connect({
    required String serverUrl,
    required String token,
  }) async => connectLink();
}

final class _SessionRepository extends Fake implements ServerRepository {
  var _request = 0;

  @override
  String get currentUserId => 'owner';

  @override
  String newRequestId() => 'request-${++_request}';

  @override
  Future<ServerSessionStart> startChannelSession({
    required String serverId,
    required String channelId,
    required String requestId,
  }) async => const ServerSessionStart(roomId: 'room', sessionId: 'session');

  @override
  Future<ServerSessionConnection> createChannelToken({
    required String serverId,
    required String channelId,
    required String sessionId,
    required String requestId,
  }) async => const ServerSessionConnection(
    serverUrl: 'wss://livekit.test',
    participantToken: 'token',
    roomName: 'room',
    participantIdentity: 'owner',
    participantName: 'Owner',
    expiresAtMillis: 0,
    canPublish: true,
    canSubscribe: true,
    permittedTrackSources: <String>['microphone'],
    sessionRole: 'host',
    roomId: 'room',
    sessionId: 'session',
  );
}

final class _NoopServerVoiceDevice implements ServerVoiceDevice {
  const _NoopServerVoiceDevice();

  @override
  Future<void> preferSpeakerOutput() async {}

  @override
  Future<void> startKeepAlive({
    required String title,
    required String body,
    required bool canPublish,
  }) async {}

  @override
  Future<void> stopKeepAlive() async {}
}

final class _GatedServerMediaLink extends ServerMediaLink {
  final Completer<void> disconnectStarted = Completer<void>();
  final Completer<void> allowDisconnect = Completer<void>();

  @override
  ServerMediaLinkState get state => ServerMediaLinkState.connected;

  @override
  bool get isCameraEnabled => false;

  @override
  bool get isDeafened => false;

  @override
  bool get isMicrophoneEnabled => false;

  @override
  bool get isScreenShareEnabled => false;

  @override
  List<ServerMediaParticipant> get participants => const [];

  @override
  Future<void> disconnect() async {
    if (!disconnectStarted.isCompleted) disconnectStarted.complete();
    await allowDisconnect.future;
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {}

  @override
  Future<void> setDeafened(bool deafened) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> setScreenShareEnabled(bool enabled) async {}
}
