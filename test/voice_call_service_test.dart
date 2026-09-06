import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
// LiveKit's public track API exposes this transitive SDK type. The test only
// implements that boundary; the app does not take a new runtime dependency.
// ignore: depend_on_referenced_packages
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import 'package:yovoice/features/calls/data/models/voice_connection_info.dart';
import 'package:yovoice/features/calls/data/services/direct_call_service.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';
import 'package:yovoice/features/calls/data/services/voice_token_service.dart';
import 'package:yovoice/features/permissions/data/permission_readiness_service.dart';
import 'package:yovoice/features/calls/data/services/voice_session_keep_alive.dart';

class _RecordingKeepAlive implements VoiceSessionKeepAlive {
  final List<String> events = <String>[];
  bool? lastCanPublish;

  @override
  Future<void> start({
    required String title,
    required String body,
    required bool canPublish,
  }) async {
    lastCanPublish = canPublish;
    events.add('start:$title');
  }

  @override
  Future<void> stop() async => events.add('stop');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final video in <bool>[false, true]) {
    test('private ${video ? 'video' : 'audio'} microphone failure cannot '
        'become a connected muted call', () async {
      final failure = StateError('native microphone publication failed');
      final participant = _JoinParticipant(microphoneError: failure);
      final room = _JoinRoom(participant);
      final service = _joinService(room);
      final statuses = <VoiceCallStatus>[];
      service.addListener(() => statuses.add(service.status));
      addTearDown(service.dispose);

      await expectLater(
        service.joinDirectCall(
          callId: 'private-call',
          contactName: 'Test contact',
          participantName: 'Test participant',
          enableCamera: video,
          playSound: false,
        ),
        throwsA(same(failure)),
      );

      expect(statuses, <VoiceCallStatus>[
        VoiceCallStatus.connecting,
        VoiceCallStatus.failed,
      ]);
      expect(service.isConnected, isFalse);
      expect(service.micState, MicState.unavailable);
      expect(
        service.errorMessage,
        'Live audio is unavailable right now. Try again.',
      );
      expect(service.cameraChangeInProgress, isFalse);
      expect(participant.microphoneRequests, <bool>[true, false]);
      expect(participant.microphoneEnabled, isFalse);
      expect(participant.cameraAttempts, 0);
      expect(room.disconnectCount, 1);
      expect(room.disposeCount, 1);
    });
  }

  test(
    'a connected room keeps the process alive until it disconnects',
    () async {
      // The foreground service is what stops Android from silencing and then
      // freezing a backgrounded call — the reported drop when both parties
      // minimise the app.
      final keepAlive = _RecordingKeepAlive();
      final room = _JoinRoom(_JoinParticipant());
      final service = _joinService(room, keepAlive: keepAlive);
      addTearDown(service.dispose);

      await service.join(
        roomId: 'kept-alive-room',
        roomName: 'Evening talks',
        participantName: 'Test speaker',
        playSound: false,
      );
      expect(service.status, VoiceCallStatus.connected);
      expect(keepAlive.events, ['start:Evening talks']);
      expect(keepAlive.lastCanPublish, isTrue);

      await service.disconnect(playSound: false);
      expect(keepAlive.events, ['start:Evening talks', 'stop']);
    },
  );

  test(
    'a listener keeps the process alive without claiming the microphone',
    () async {
      final keepAlive = _RecordingKeepAlive();
      final room = _JoinRoom(_JoinParticipant(canPublish: false));
      final service = _joinService(
        room,
        canPublish: false,
        keepAlive: keepAlive,
      );
      addTearDown(service.dispose);

      await service.join(
        roomId: 'listen-only-room',
        roomName: 'Podcast',
        participantName: 'Test listener',
        playSound: false,
      );
      expect(keepAlive.lastCanPublish, isFalse);
      await service.disconnect(playSound: false);
      expect(keepAlive.events.last, 'stop');
    },
  );

  test(
    'listen-only room joins muted without asking for or publishing mic',
    () async {
      final participant = _JoinParticipant(canPublish: false);
      final room = _JoinRoom(participant);
      final platform = _VoicePermissionPlatform();
      final service = _joinService(room, canPublish: false, platform: platform);
      addTearDown(service.dispose);

      await service.join(
        roomId: 'broadcast-room',
        roomName: 'Test broadcast',
        participantName: 'Test listener',
        playSound: false,
      );

      expect(service.status, VoiceCallStatus.connected);
      expect(service.isMuted, isTrue);
      expect(service.canPublish, isFalse);
      expect(service.micState, MicState.listenOnly);
      expect(service.errorMessage, isNull);
      expect(participant.microphoneRequests, isEmpty);
      expect(platform.statusChecks, isEmpty);
      expect(platform.requests, isEmpty);
      await service.disconnect(playSound: false);
      expect(room.disposeCount, 1);
    },
  );

  for (final directCall in <bool>[false, true]) {
    test('${directCall ? 'private call' : 'room'} respects a narrower '
        'post-connect publishing grant', () async {
      final participant = _JoinParticipant(
        canPublish: false,
        microphoneError: StateError('must not attempt microphone capture'),
      );
      final room = _JoinRoom(participant);
      final service = _joinService(room);
      addTearDown(service.dispose);

      if (directCall) {
        await _joinPrivate(service);
      } else {
        await service.join(
          roomId: 'demoted-speaker-room',
          roomName: 'Test room',
          participantName: 'Test listener',
          playSound: false,
        );
      }

      expect(service.status, VoiceCallStatus.connected);
      expect(service.canPublish, isFalse);
      expect(service.micState, MicState.listenOnly);
      expect(service.isMuted, isTrue);
      expect(service.errorMessage, isNull);
      expect(participant.microphoneRequests, isEmpty);
      await service.disconnect(playSound: false);
    });
  }

  test('microphone failure exposes retry only after native teardown', () async {
    final disconnectGate = Completer<void>();
    final disposeGate = Completer<void>();
    final failure = StateError('microphone publication failed');
    final oldRoom = _JoinRoom(
      _JoinParticipant(microphoneError: failure),
      disconnectGate: disconnectGate.future,
      disposeGate: disposeGate.future,
    );
    final newRoom = _JoinRoom(_JoinParticipant());
    var createdRooms = 0;
    final service = _joinService(
      oldRoom,
      roomFactory: () {
        if (createdRooms++ == 0) return oldRoom;
        expect(oldRoom.disposalCompleted, isTrue);
        return newRoom;
      },
    );
    addTearDown(service.dispose);

    final failedJoin = expectLater(
      _joinPrivate(service),
      throwsA(same(failure)),
    );
    await oldRoom.disconnectStarted.future;
    expect(service.status, VoiceCallStatus.connecting);
    expect(service.errorMessage, isNull);
    expect(service.isBusy, isTrue);
    disconnectGate.complete();
    await oldRoom.disposeStarted.future;
    expect(service.status, VoiceCallStatus.connecting);
    expect(service.isBusy, isTrue);
    disposeGate.complete();
    await failedJoin;

    expect(service.status, VoiceCallStatus.failed);
    expect(oldRoom.disposalCompleted, isTrue);
    await _joinPrivate(service);
    expect(createdRooms, 2);
    expect(service.status, VoiceCallStatus.connected);
    await service.disconnect(playSound: false);
  });

  test('retries cannot bypass a detached room still tearing down', () async {
    final disconnectGate = Completer<void>();
    final disposeGate = Completer<void>();
    final oldRoom = _JoinRoom(
      _JoinParticipant(microphoneError: StateError('old microphone failure')),
      disconnectGate: disconnectGate.future,
      disposeGate: disposeGate.future,
    );
    final newRoom = _JoinRoom(_JoinParticipant());
    var createdRooms = 0;
    final service = _joinService(
      oldRoom,
      roomFactory: () {
        if (createdRooms++ == 0) return oldRoom;
        expect(oldRoom.disposalCompleted, isTrue);
        return newRoom;
      },
    );
    final statuses = <VoiceCallStatus>[];
    service.addListener(() => statuses.add(service.status));
    addTearDown(service.dispose);

    final oldJoin = _joinPrivate(service);
    await oldRoom.disconnectStarted.future;
    final supersededRetry = _joinPrivate(service, callId: 'superseded-retry');
    // The first retry cleared the old public state, but not its native work.
    expect(service.status, VoiceCallStatus.disconnected);
    expect(service.directCallId, isNull);
    final latestRetry = _joinPrivate(service, callId: 'latest-retry');
    await Future<void>.delayed(Duration.zero);
    expect(createdRooms, 1);
    expect(newRoom.connectCount, 0);
    disconnectGate.complete();
    await oldRoom.disposeStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(createdRooms, 1);
    expect(newRoom.connectCount, 0);
    disposeGate.complete();
    await Future.wait([oldJoin, supersededRetry, latestRetry]);

    expect(createdRooms, 2);
    expect(newRoom.connectCount, 1);
    expect(oldRoom.disconnectCount, 1);
    expect(oldRoom.disposeCount, 1);
    expect(service.status, VoiceCallStatus.connected);
    expect(service.directCallId, 'latest-retry');
    expect(service.errorMessage, isNull);
    expect(statuses, isNot(contains(VoiceCallStatus.failed)));
    await service.disconnect(playSound: false);
  });

  test('replacement waits for the old connect native-audio finally', () async {
    final connectGate = Completer<void>();
    final oldRoom = _JoinRoom(
      _JoinParticipant(),
      connectGate: connectGate.future,
      connectError: StateError('cancelled old connection'),
    );
    final newRoom = _JoinRoom(_JoinParticipant());
    var createdRooms = 0;
    final service = _joinService(
      oldRoom,
      roomFactory: () {
        if (createdRooms++ == 0) return oldRoom;
        expect(oldRoom.disposalCompleted, isTrue);
        expect(oldRoom.connectionSettled, isTrue);
        return newRoom;
      },
    );
    addTearDown(service.dispose);

    final oldJoin = _joinPrivate(service);
    await oldRoom.connectStarted.future;
    final ending = service.disconnect(playSound: false);
    await oldRoom.disposeFinished.future;
    final replacement = _joinPrivate(service, callId: 'replacement');
    await Future<void>.delayed(Duration.zero);
    expect(service.status, VoiceCallStatus.disconnected);
    expect(createdRooms, 1);
    expect(newRoom.connectCount, 0);
    connectGate.complete();
    await Future.wait([oldJoin, ending, replacement]);

    expect(service.status, VoiceCallStatus.connected);
    expect(service.directCallId, 'replacement');
    expect(service.errorMessage, isNull);
    expect(oldRoom.disconnectCount, 1);
    expect(oldRoom.disposeCount, 1);
    expect(newRoom.connectCount, 1);
    await service.disconnect(playSound: false);
  });

  testWidgets('unresolved connect reports bounded cleanup-busy failure', (
    tester,
  ) async {
    const connectionTimeout = Duration(milliseconds: 20);
    const cleanupTimeout = Duration(milliseconds: 3);
    final connectGate = Completer<void>();
    final room = _JoinRoom(_JoinParticipant(), connectGate: connectGate.future);
    final service = _joinService(
      room,
      connectionTimeout: connectionTimeout,
      cleanupWaitTimeout: cleanupTimeout,
    );
    addTearDown(service.dispose);

    final joining = expectLater(
      _joinPrivate(service),
      throwsA(isA<VoiceCleanupInProgressException>()),
    );
    await tester.pump();
    expect(room.connectStarted.isCompleted, isTrue);
    await tester.pump(connectionTimeout);
    expect(room.disposalCompleted, isTrue);
    await tester.pump(cleanupTimeout);
    await joining;

    expect(service.status, VoiceCallStatus.failed);
    expect(service.isBusy, isFalse);
    expect(service.isCleanupInProgress, isTrue);
    expect(
      service.errorMessage,
      'The previous call is still closing. Wait a moment before trying again.',
    );
    expect(room.connectionSettled, isFalse);
    expect(room.localParticipant.microphoneRequests, isNot(contains(true)));
    // Release only after proving the public failure; keep the SDK safety
    // barrier alive throughout the simulated never-settling network request.
    connectGate.complete();
    await tester.pump();
    expect(service.isCleanupInProgress, isFalse);
    expect(service.status, VoiceCallStatus.failed);
  });

  testWidgets('End is local-first and retry is bounded behind raw connect', (
    tester,
  ) async {
    const connectionTimeout = Duration(milliseconds: 20);
    const cleanupTimeout = Duration(milliseconds: 3);
    final connectGate = Completer<void>();
    final oldRoom = _JoinRoom(
      _JoinParticipant(),
      connectGate: connectGate.future,
    );
    final newRoom = _JoinRoom(_JoinParticipant());
    var createdRooms = 0;
    final service = _joinService(
      oldRoom,
      connectionTimeout: connectionTimeout,
      cleanupWaitTimeout: cleanupTimeout,
      roomFactory: () => createdRooms++ == 0 ? oldRoom : newRoom,
    );
    addTearDown(service.dispose);

    final oldJoin = _joinPrivate(service);
    await tester.pump();
    expect(oldRoom.connectStarted.isCompleted, isTrue);
    final ending = service.disconnect(playSound: false);
    // State changes synchronously, without waiting for signaling/disposal.
    expect(service.status, VoiceCallStatus.disconnected);
    expect(service.directCallId, isNull);
    await tester.pump();
    expect(oldRoom.disposalCompleted, isTrue);
    await tester.pump(cleanupTimeout);
    await ending;
    expect(service.isCleanupInProgress, isTrue);

    final retry = expectLater(
      _joinPrivate(service, callId: 'blocked-retry'),
      throwsA(isA<VoiceCleanupInProgressException>()),
    );
    await tester.pump(cleanupTimeout);
    await retry;
    expect(service.status, VoiceCallStatus.failed);
    expect(service.isBusy, isFalse);
    expect(service.isCleanupInProgress, isTrue);
    expect(createdRooms, 1);
    expect(newRoom.connectCount, 0);
    expect(oldRoom.connectionSettled, isFalse);
    // The superseded public join must also finish, without touching retry UI.
    await tester.pump(connectionTimeout);
    await tester.pump(cleanupTimeout);
    await oldJoin;
    expect(service.directCallId, 'blocked-retry');
    expect(service.status, VoiceCallStatus.failed);
    expect(createdRooms, 1);

    connectGate.complete();
    await tester.pump();
    await _joinPrivate(service, callId: 'safe-retry');
    expect(service.status, VoiceCallStatus.connected);
    expect(service.isCleanupInProgress, isFalse);
    expect(createdRooms, 2);
    expect(newRoom.connectCount, 1);
    await service.disconnect(playSound: false);
  });

  test('reconnect cannot bypass initial microphone readiness', () async {
    final microphoneGate = Completer<void>();
    final failure = StateError('initial microphone publication failed');
    final participant = _JoinParticipant(
      microphoneGate: microphoneGate.future,
      microphoneError: failure,
    );
    final room = _JoinRoom(participant);
    final service = _joinService(room);
    final statuses = <VoiceCallStatus>[];
    service.addListener(() => statuses.add(service.status));
    addTearDown(service.dispose);

    final joining = expectLater(_joinPrivate(service), throwsA(same(failure)));
    await participant.microphoneStarted.future;
    room.emit(const RoomReconnectingEvent());
    room.emit(const RoomReconnectedEvent());
    await Future<void>.delayed(Duration.zero);
    expect(service.isConnected, isFalse);
    expect(service.status, VoiceCallStatus.connecting);
    expect(statuses, isNot(contains(VoiceCallStatus.connected)));
    microphoneGate.complete();
    await joining;

    expect(service.status, VoiceCallStatus.failed);
    expect(statuses, isNot(contains(VoiceCallStatus.connected)));
    expect(participant.microphoneEnabled, isFalse);
    expect(room.disconnectCount, 1);
    expect(room.disposalCompleted, isTrue);
  });

  test('completed initial media can reconnect normally', () async {
    final room = _JoinRoom(_JoinParticipant());
    final service = _joinService(room);
    addTearDown(service.dispose);
    await _joinPrivate(service);

    room.emit(const RoomReconnectingEvent());
    await Future<void>.delayed(Duration.zero);
    expect(service.status, VoiceCallStatus.reconnecting);
    room.emit(const RoomReconnectedEvent());
    await Future<void>.delayed(Duration.zero);
    expect(service.status, VoiceCallStatus.connected);
    expect(service.micState, MicState.on);
    await service.disconnect(playSound: false);
  });

  test('healthy private microphone still joins and ends normally', () async {
    final participant = _JoinParticipant();
    final room = _JoinRoom(participant);
    final service = _joinService(room);
    addTearDown(service.dispose);

    await _joinPrivate(service);

    expect(service.status, VoiceCallStatus.connected);
    expect(service.micState, MicState.on);
    expect(service.isMuted, isFalse);
    expect(participant.microphoneRequests, <bool>[true]);
    await service.disconnect(playSound: false);
    expect(service.status, VoiceCallStatus.disconnected);
    expect(participant.microphoneEnabled, isFalse);
    expect(room.disposeCount, 1);
  });

  test(
    'publisher entering a room muted stays distinct from listen-only',
    () async {
      final participant = _JoinParticipant();
      final room = _JoinRoom(participant);
      final service = _joinService(room);
      addTearDown(service.dispose);

      await service.join(
        roomId: 'community-room',
        roomName: 'Test community',
        participantName: 'Test speaker',
        startMuted: true,
        playSound: false,
      );

      expect(service.status, VoiceCallStatus.connected);
      expect(service.canPublish, isTrue);
      expect(service.micState, MicState.muted);
      expect(participant.microphoneRequests, isEmpty);
      expect(participant.microphoneEnabled, isFalse);
      await service.disconnect(playSound: false);
    },
  );

  test('camera failure preserves a healthy private audio connection', () async {
    final participant = _JoinParticipant(
      cameraError: StateError('camera unavailable'),
    );
    final room = _JoinRoom(participant);
    final service = _joinService(room);
    addTearDown(service.dispose);

    await _joinPrivate(service, video: true);

    expect(service.status, VoiceCallStatus.connected);
    expect(service.micState, MicState.on);
    expect(service.isCameraEnabled, isFalse);
    expect(service.cameraChangeInProgress, isFalse);
    expect(
      service.cameraIssue,
      'Camera could not be started. Continue with audio or retry.',
    );
    expect(participant.cameraAttempts, 1);
    expect(room.disconnectCount, 0);
    await service.disconnect(playSound: false);
  });

  test(
    'late successful camera publication after End hard-stops its track',
    () async {
      final publishGate = Completer<void>();
      final candidate = _JoinVideoTrack();
      final oldParticipant = _JoinParticipant(
        videoPublishGate: publishGate.future,
      );
      final oldRoom = _JoinRoom(oldParticipant);
      final newRoom = _JoinRoom(_JoinParticipant());
      var createdRooms = 0;
      final service = _joinService(
        oldRoom,
        roomFactory: () => createdRooms++ == 0 ? oldRoom : newRoom,
        cameraTrackFactory: (_) async => candidate,
      );
      addTearDown(service.dispose);

      final oldJoin = _joinPrivate(service, video: true);
      await oldParticipant.videoPublishStarted.future;
      expect(oldParticipant.videoTrackPublications, isEmpty);
      await service.disconnect(playSound: false);
      expect(service.status, VoiceCallStatus.disconnected);
      expect(oldRoom.disposalCompleted, isTrue);
      expect(candidate.mediaStreamTrack.enabled, isFalse);
      final stopsAfterEnd = candidate.stopCount;
      expect(stopsAfterEnd, greaterThan(0));
      await _joinPrivate(service, callId: 'new-audio-call');
      publishGate.complete();
      await oldJoin;

      expect(
        oldParticipant.videoTrackPublications.single.track,
        same(candidate),
      );
      expect(candidate.mediaStreamTrack.enabled, isFalse);
      expect(candidate.stopCount, greaterThan(stopsAfterEnd));
      expect(service.status, VoiceCallStatus.connected);
      expect(service.directCallId, 'new-audio-call');
      expect(service.micState, MicState.on);
      expect(oldRoom.disconnectCount, 1);
      expect(oldRoom.disposeCount, 1);
      expect(newRoom.disposeCount, 0);
      await service.disconnect(playSound: false);
    },
  );

  test(
    'camera denial still allows private audio fallback without capture',
    () async {
      final participant = _JoinParticipant();
      final room = _JoinRoom(participant);
      final service = _joinService(
        room,
        platform: _VoicePermissionPlatform(
          microphone: AppPermissionAccess.granted,
        ),
      );
      addTearDown(service.dispose);

      await _joinPrivate(service, video: true);

      expect(service.status, VoiceCallStatus.connected);
      expect(service.micState, MicState.on);
      expect(service.isCameraEnabled, isFalse);
      expect(service.cameraPermissionDenied, isTrue);
      expect(participant.cameraAttempts, 0);
      await service.disconnect(playSound: false);
    },
  );

  test(
    'late microphone success after hang-up is stopped, never connected',
    () async {
      final startGate = Completer<void>();
      final participant = _JoinParticipant(microphoneGate: startGate.future);
      final room = _JoinRoom(participant);
      final service = _joinService(room);
      final statuses = <VoiceCallStatus>[];
      service.addListener(() => statuses.add(service.status));
      addTearDown(service.dispose);

      final joining = _joinPrivate(service);
      await participant.microphoneStarted.future;
      await service.disconnect(playSound: false);
      startGate.complete();
      await joining;

      expect(service.status, VoiceCallStatus.disconnected);
      expect(statuses, isNot(contains(VoiceCallStatus.connected)));
      expect(service.directCallId, isNull);
      expect(service.errorMessage, isNull);
      expect(participant.microphoneEnabled, isFalse);
      expect(participant.microphoneRequests.last, isFalse);
      expect(room.disconnectCount, 1);
      expect(room.disposeCount, 1);
    },
  );

  test('late microphone failure cannot fail or dispose a newer call', () async {
    final startGate = Completer<void>();
    final oldParticipant = _JoinParticipant(
      microphoneGate: startGate.future,
      microphoneError: StateError('old native failure'),
    );
    final oldRoom = _JoinRoom(oldParticipant);
    final newParticipant = _JoinParticipant();
    final newRoom = _JoinRoom(newParticipant);
    var createdRooms = 0;
    final service = _joinService(
      oldRoom,
      roomFactory: () => createdRooms++ == 0 ? oldRoom : newRoom,
    );
    addTearDown(service.dispose);

    final oldJoin = _joinPrivate(service);
    await oldParticipant.microphoneStarted.future;
    await service.disconnect(playSound: false);
    await _joinPrivate(service, callId: 'new-call');
    startGate.complete();
    await oldJoin;

    expect(service.status, VoiceCallStatus.connected);
    expect(service.directCallId, 'new-call');
    expect(service.errorMessage, isNull);
    expect(service.micState, MicState.on);
    expect(oldParticipant.microphoneEnabled, isFalse);
    expect(oldRoom.disconnectCount, 1);
    expect(oldRoom.disposeCount, 1);
    expect(newRoom.disposeCount, 0);
    await service.disconnect(playSound: false);
  });

  test(
    'late microphone disable hard-stops the captured track after room cleanup',
    () async {
      final service = VoiceCallService.forTesting(
        microphoneTeardownWaiter: (_, _) async => false,
      );
      final microphoneOff = Completer<void>();
      final lateCleanup = Completer<void>();
      final capturedMicrophone = Object();
      final publishedTracks = <Object>[capturedMicrophone];
      final events = <String>[];

      await service.guardDeferredCaptureTeardownForTesting<Object>(
        pendingDisable: microphoneOff.future,
        capturedTracks: <Object>[capturedMicrophone],
        stopCapturedTrack: (track) async {
          expect(track, same(capturedMicrophone));
          events.add('stop-captured');
        },
        stopCurrentCapture: () async {
          events.add('scan-${publishedTracks.length}');
          if (publishedTracks.isEmpty && !lateCleanup.isCompleted) {
            lateCleanup.complete();
          }
        },
      );

      // Simulate Room._cleanUp removing the publication while LiveKit's
      // restartTrack/getUserMedia Future is still pending.
      expect(events, <String>['scan-1']);
      publishedTracks.clear();
      microphoneOff.complete();
      await lateCleanup.future;

      expect(events, <String>['scan-1', 'stop-captured', 'scan-0']);
    },
  );

  test('media status gate never requests a permission', () async {
    final platform = _VoicePermissionPlatform();
    final service = VoiceCallService.forTesting(
      permissionReadiness: PermissionReadinessService(platform: platform),
    );

    final snapshot = await service.mediaPermissionStatus(includeCamera: true);

    expect(snapshot[AppPermissionKind.microphone], AppPermissionAccess.denied);
    expect(snapshot[AppPermissionKind.camera], AppPermissionAccess.denied);
    expect(platform.requests, isEmpty);
  });

  test('voice errors never expose callable or exception internals', () {
    final service = VoiceCallService.forTesting();
    final callable = service.friendlyErrorForTesting(
      FirebaseFunctionsException(
        code: 'internal',
        message: 'SQLSTATE 42P01 at private_table',
      ),
    );
    final permission = service.friendlyErrorForTesting(
      const VoicePermissionRequiredException(
        AppPermissionKind.microphone,
        AppPermissionAccess.denied,
      ),
    );

    expect(callable, 'Live audio is unavailable right now. Try again.');
    expect(callable, isNot(contains('SQLSTATE')));
    expect(permission, contains('Microphone access'));
    expect(permission, isNot(contains('VoicePermissionRequiredException')));
  });
}

final class _VoicePermissionPlatform implements AppPermissionPlatformGateway {
  _VoicePermissionPlatform({
    this.microphone = AppPermissionAccess.denied,
    this.camera = AppPermissionAccess.denied,
  });

  final AppPermissionAccess microphone;
  final AppPermissionAccess camera;
  final List<AppPermissionKind> requests = <AppPermissionKind>[];
  final List<AppPermissionKind> statusChecks = <AppPermissionKind>[];

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<AppPermissionAccess> requestFromUserGesture(
    AppPermissionKind permission,
  ) async {
    requests.add(permission);
    return AppPermissionAccess.granted;
  }

  @override
  Future<AppPermissionAccess> status(AppPermissionKind permission) async {
    statusChecks.add(permission);
    return permission == AppPermissionKind.camera ? camera : microphone;
  }
}

const _publisherToken = VoiceConnectionInfo(
  serverUrl: 'wss://yovoice-3f7j9fb7.livekit.cloud',
  participantToken: 'test-only-token',
  canPublish: true,
);

VoiceCallService _joinService(
  _JoinRoom room, {
  bool canPublish = true,
  _VoicePermissionPlatform? platform,
  Room Function()? roomFactory,
  Duration connectionTimeout = const Duration(seconds: 20),
  Duration cleanupWaitTimeout = const Duration(seconds: 3),
  Future<LocalVideoTrack> Function(CameraCaptureOptions options)?
  cameraTrackFactory,
  VoiceSessionKeepAlive? keepAlive,
}) {
  final token = canPublish
      ? _publisherToken
      : const VoiceConnectionInfo(
          serverUrl: 'wss://yovoice-3f7j9fb7.livekit.cloud',
          participantToken: 'test-only-listener-token',
          canPublish: false,
        );
  return VoiceCallService.forTesting(
    keepAlive: keepAlive,
    roomFactory: roomFactory ?? () => room,
    connectionTimeout: connectionTimeout,
    cleanupWaitTimeout: cleanupWaitTimeout,
    cameraTrackFactory: cameraTrackFactory,
    directCallService: _JoinDirectGateway(token),
    tokenService: _JoinRoomTokens(token),
    permissionReadiness: PermissionReadinessService(
      platform:
          platform ??
          _VoicePermissionPlatform(
            microphone: AppPermissionAccess.granted,
            camera: AppPermissionAccess.granted,
          ),
    ),
  );
}

Future<void> _joinPrivate(
  VoiceCallService service, {
  String callId = 'private-call',
  bool video = false,
}) => service.joinDirectCall(
  callId: callId,
  contactName: 'Test contact',
  participantName: 'Test participant',
  enableCamera: video,
  playSound: false,
);

final class _JoinDirectGateway extends Fake implements DirectCallGateway {
  _JoinDirectGateway(this.token);
  final VoiceConnectionInfo token;

  @override
  Future<VoiceConnectionInfo> createJoinToken(String callId) async => token;
}

final class _JoinRoomTokens extends Fake implements VoiceTokenService {
  _JoinRoomTokens(this.token);
  final VoiceConnectionInfo token;

  @override
  Future<VoiceConnectionInfo> createJoinToken({
    required String roomId,
    required String participantName,
  }) async => token;
}

/// SDK boundary double: service join/state/epoch/cleanup code stays real.
final class _JoinRoom extends Fake implements Room {
  _JoinRoom(
    this.localParticipant, {
    this.disconnectGate,
    this.disposeGate,
    this.connectGate,
    this.connectError,
  });

  @override
  final _JoinParticipant localParticipant;
  final Future<void>? disconnectGate;
  final Future<void>? disposeGate;
  final Future<void>? connectGate;
  final Object? connectError;
  final connectStarted = Completer<void>();
  final disconnectStarted = Completer<void>();
  final disposeStarted = Completer<void>();
  final disposeFinished = Completer<void>();
  final _events = EventsEmitter<RoomEvent>();
  int connectCount = 0;
  int disconnectCount = 0;
  int disposeCount = 0;
  bool disposalCompleted = false;
  bool connectionSettled = false;

  // The Room double owns this SDK event source; production receives its events
  // only through Room.createListener, the same path exercised by these tests.
  // ignore: invalid_use_of_internal_member
  void emit(RoomEvent event) => _events.emit(event);

  @override
  void addListener(void Function() listener) {}

  @override
  void removeListener(void Function() listener) {}

  @override
  EventsListener<RoomEvent> createListener({bool synchronized = false}) =>
      EventsListener<RoomEvent>(_events, synchronized: synchronized);

  @override
  Future<void> connect(
    String url,
    String token, {
    ConnectOptions? connectOptions,
    RoomOptions? roomOptions,
    FastConnectOptions? fastConnectOptions,
  }) async {
    connectCount++;
    connectStarted.complete();
    try {
      await connectGate;
      if (connectError case final error?) throw error;
    } finally {
      connectionSettled = true;
    }
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    if (!disconnectStarted.isCompleted) disconnectStarted.complete();
    await disconnectGate;
  }

  @override
  Future<bool> dispose() async {
    if (disposeCount != 0) return false;
    disposeCount++;
    disposeStarted.complete();
    await disposeGate;
    await _events.dispose();
    disposalCompleted = true;
    disposeFinished.complete();
    return true;
  }
}

final class _JoinParticipant extends Fake implements LocalParticipant {
  _JoinParticipant({
    bool canPublish = true,
    this.microphoneError,
    this.microphoneGate,
    this.cameraError,
    this.videoPublishGate,
  }) : permissions = ParticipantPermissions(canPublish: canPublish);

  final Object? microphoneError;
  final Future<void>? microphoneGate;
  final Object? cameraError;
  final Future<void>? videoPublishGate;
  final videoPublishStarted = Completer<void>();
  final List<LocalTrackPublication<LocalVideoTrack>> _videoPublications = [];
  final microphoneRequests = <bool>[];
  final microphoneStarted = Completer<void>();
  bool microphoneEnabled = false;
  int cameraAttempts = 0;

  @override
  final ParticipantPermissions permissions;

  @override
  List<LocalTrackPublication<LocalAudioTrack>> get audioTrackPublications =>
      const [];

  @override
  List<LocalTrackPublication<LocalVideoTrack>> get videoTrackPublications =>
      _videoPublications;

  @override
  Future<LocalTrackPublication<LocalVideoTrack>> publishVideoTrack(
    LocalVideoTrack track, {
    VideoPublishOptions? publishOptions,
  }) async {
    videoPublishStarted.complete();
    await videoPublishGate;
    // The SDK can finish native track.start after disposal took its snapshot.
    track.mediaStreamTrack.enabled = true;
    final publication = _JoinVideoPublication(track);
    _videoPublications.add(publication);
    return publication;
  }

  @override
  bool isMicrophoneEnabled() => microphoneEnabled;

  @override
  bool isCameraEnabled() => false;

  @override
  LocalTrackPublication? getTrackPublicationBySource(TrackSource source) {
    if (source == TrackSource.camera) {
      cameraAttempts++;
      if (cameraError case final error?) throw error;
    }
    return null;
  }

  @override
  Future<LocalTrackPublication?> setMicrophoneEnabled(
    bool enabled, {
    AudioCaptureOptions? audioCaptureOptions,
  }) async {
    microphoneRequests.add(enabled);
    if (enabled) {
      if (!microphoneStarted.isCompleted) microphoneStarted.complete();
      await microphoneGate;
      if (microphoneError case final error?) throw error;
    }
    microphoneEnabled = enabled;
    return null;
  }
}

final class _JoinVideoPublication extends Fake
    implements LocalTrackPublication<LocalVideoTrack> {
  _JoinVideoPublication(this.track);

  @override
  final LocalVideoTrack track;
}

final class _JoinVideoTrack extends Fake implements LocalVideoTrack {
  @override
  final mediaStreamTrack = _JoinMediaTrack();
  int stopCount = 0;

  @override
  Future<bool> stop() async {
    stopCount++;
    await mediaStreamTrack.stop();
    return true;
  }
}

final class _JoinMediaTrack extends Fake implements rtc.MediaStreamTrack {
  @override
  bool enabled = true;

  @override
  Future<void> stop() async {
    enabled = false;
  }
}
