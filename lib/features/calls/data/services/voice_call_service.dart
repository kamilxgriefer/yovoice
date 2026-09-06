import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import 'package:yovoice/core/audio/ui_sound.dart';
import 'package:yovoice/core/audio/ui_sound_service.dart';
import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/features/permissions/data/permission_readiness_service.dart';

import '../models/voice_connection_info.dart';
import 'direct_call_service.dart';
import 'voice_token_service.dart';

Future<bool> _waitForCaptureDisable(
  Future<void> pendingDisable,
  Duration timeout,
) async {
  try {
    await pendingDisable.timeout(timeout);
    return true;
  } on TimeoutException {
    return false;
  }
}

enum VoiceCallStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

enum VoiceSessionKind { room, directCall }

/// What the microphone button should show — one enum, no combinations of
/// guessed booleans. Every value is a visually distinct UI state.
enum MicState {
  /// Publishing and audible.
  on,

  /// Can publish, currently muted — tap to unmute.
  muted,

  /// Connected but the token has no publish rights (podcast audience).
  /// Not an error and not "disabled-looking": the UI should offer
  /// raise-hand instead of a dead mic.
  listenOnly,

  /// Connecting or reconnecting — show progress, not a dead button.
  connecting,

  /// Disconnected, failed, or missing permission — tapping should
  /// surface what's wrong instead of silently doing nothing.
  unavailable,
}

final class VoicePermissionRequiredException implements Exception {
  const VoicePermissionRequiredException(this.permission, this.status);

  final AppPermissionKind permission;
  final AppPermissionAccess status;

  @override
  String toString() =>
      'VoicePermissionRequiredException(${permission.name}, ${status.name})';
}

/// Native SDK work is still being drained. Retrying may wait, but must never
/// start overlapping process-wide audio while that work remains unresolved.
final class VoiceCleanupInProgressException implements Exception {
  const VoiceCleanupInProgressException();

  @override
  String toString() => 'VoiceCleanupInProgressException';
}

class VoiceCallService extends ChangeNotifier {
  VoiceCallService._({PermissionReadinessService? permissionReadiness})
    : _microphoneTeardownTimeout = const Duration(seconds: 3),
      _connectionTimeout = const Duration(seconds: 20),
      _cleanupWaitTimeout = const Duration(seconds: 3),
      _captureDisableWaiter = _waitForCaptureDisable,
      _roomFactoryOverride = null,
      _cameraTrackFactoryOverride = null,
      _tokenServiceOverride = null,
      _directCallServiceOverride = null,
      _permissionReadiness =
          permissionReadiness ?? PermissionReadinessService.instance;

  /// Test seam. The production service is a singleton behind a private
  /// constructor, which left no way for a widget test to observe whether a
  /// screen asked for a LiveKit token — the single most important assertion
  /// about the room entry path, since requesting one against a dormant room
  /// is the failure this whole path exists to prevent. A subclass may now
  /// stand in for it and record the calls.
  @visibleForTesting
  VoiceCallService.forTesting({
    Duration microphoneTeardownTimeout = const Duration(seconds: 3),
    Duration connectionTimeout = const Duration(seconds: 20),
    Duration cleanupWaitTimeout = const Duration(seconds: 3),
    Future<bool> Function(Future<void> pendingDisable, Duration timeout)
        microphoneTeardownWaiter =
        _waitForCaptureDisable,
    PermissionReadinessService? permissionReadiness,
    Room Function()? roomFactory,
    Future<LocalVideoTrack> Function(CameraCaptureOptions options)?
    cameraTrackFactory,
    VoiceTokenService? tokenService,
    DirectCallGateway? directCallService,
  }) : _microphoneTeardownTimeout = microphoneTeardownTimeout,
       _connectionTimeout = connectionTimeout,
       _cleanupWaitTimeout = cleanupWaitTimeout,
       _captureDisableWaiter = microphoneTeardownWaiter,
       _roomFactoryOverride = roomFactory,
       _cameraTrackFactoryOverride = cameraTrackFactory,
       _tokenServiceOverride = tokenService,
       _directCallServiceOverride = directCallService,
       _permissionReadiness =
           permissionReadiness ?? PermissionReadinessService.instance;

  static final VoiceCallService instance = VoiceCallService._();

  final Duration _microphoneTeardownTimeout;
  final Duration _connectionTimeout;
  final Duration _cleanupWaitTimeout;
  final Future<bool> Function(Future<void> pendingDisable, Duration timeout)
  _captureDisableWaiter;
  final PermissionReadinessService _permissionReadiness;
  // Inject SDK/network boundaries only through the test constructor so tests
  // exercise the real join, epoch checks and cleanup instead of overriding it.
  final Room Function()? _roomFactoryOverride;
  final Future<LocalVideoTrack> Function(CameraCaptureOptions options)?
  _cameraTrackFactoryOverride;
  final VoiceTokenService? _tokenServiceOverride;
  final DirectCallGateway? _directCallServiceOverride;

  // Lazy: VoiceTokenService touches FirebaseFunctions at construction,
  // and this singleton is now reachable from always-mounted UI (the
  // shell's RoomMiniBar) — including in widget tests with no Firebase
  // app. Nothing needs the token service until an actual join().
  late final VoiceTokenService _tokenService =
      _tokenServiceOverride ?? VoiceTokenService();
  late final DirectCallGateway _directCallService =
      _directCallServiceOverride ?? DirectCallService();
  final UiSoundService _sounds = UiSoundService.instance;

  Room? _room;
  EventsListener<RoomEvent>? _events;
  Timer? _audioMeterTimer;
  // SDK teardown can stop the process-wide Android audio session. Clearing
  // _room alone must not let a replacement connect before teardown finishes.
  Future<void> _roomTeardownTail = Future<void>.value();
  final Expando<Future<void>> _roomDisposals = Expando<Future<void>>();
  final Expando<Future<void>> _roomConnections = Expando<Future<void>>();
  final Expando<Set<LocalVideoTrack>> _cameraCandidates =
      Expando<Set<LocalVideoTrack>>();
  int _pendingRoomTeardowns = 0;

  VoiceCallStatus _status = VoiceCallStatus.disconnected;
  String? _roomId;
  String? _roomName;
  String? _errorMessage;
  VoiceSessionKind? _sessionKind;
  String? _directCallId;
  bool _isMuted = false;
  bool _muteChangeInProgress = false;
  bool _videoRequested = false;
  bool _cameraChangeInProgress = false;
  bool _cameraPermissionDenied = false;
  String? _cameraIssue;
  CameraPosition _cameraPosition = CameraPosition.front;
  int _sessionEpoch = 0;
  int _microphoneOperationEpoch = 0;
  bool _desiredMicrophoneEnabled = false;
  int _cameraOperationEpoch = 0;
  bool _desiredCameraEnabled = false;
  int _speakerOperationEpoch = 0;
  bool _desiredSpeakerPreferred = false;
  Future<void> _speakerRouteTail = Future<void>.value();
  bool _speakerChangeInProgress = false;
  bool _appIsForeground = true;

  VoiceCallStatus get status => _status;
  String? get roomId => _roomId;
  String? get roomName => _roomName;
  String? get errorMessage => _errorMessage;
  VoiceSessionKind? get sessionKind => _sessionKind;
  String? get directCallId => _directCallId;
  bool get isDirectCall =>
      _sessionKind == VoiceSessionKind.directCall || directCallId != null;

  // The fallback keeps the established test seam and any in-memory room
  // session created by a pre-upgrade hot restart visible. New joins always set
  // the explicit kind; a directCallId still wins and can never look like a
  // room mini-player.
  bool get isRoomSession =>
      _sessionKind == VoiceSessionKind.room ||
      (_sessionKind == null && roomId != null && directCallId == null);

  /// AUTHORITATIVE mute state: while connected, this is LiveKit's own
  /// publication state, not our remembered boolean. The remembered flag
  /// only bridges the moments where LiveKit has no answer (connecting,
  /// or mid-toggle). Guessed local state is exactly what made the mic
  /// button lie after reconnects and role changes.
  bool get isMuted {
    final local = _room?.localParticipant;
    if (isConnected && local != null && !_muteChangeInProgress) {
      return !local.isMicrophoneEnabled();
    }
    return _isMuted;
  }

  /// Whether the server-minted token lets us publish audio at all
  /// (hosts/speakers yes, podcast audience no). Distinct from muted:
  /// a listener isn't "muted", they're listen-only until promoted.
  bool get canPublish {
    final local = _room?.localParticipant;
    if (local == null) return false;
    return local.permissions.canPublish;
  }

  /// The one state the mic UI should render from.
  MicState get micState {
    switch (_status) {
      case VoiceCallStatus.connecting:
      case VoiceCallStatus.reconnecting:
        return MicState.connecting;
      case VoiceCallStatus.disconnected:
      case VoiceCallStatus.failed:
        return MicState.unavailable;
      case VoiceCallStatus.connected:
        if (!canPublish) return MicState.listenOnly;
        return isMuted ? MicState.muted : MicState.on;
    }
  }

  bool get muteChangeInProgress => _muteChangeInProgress;
  bool get isConnected => _status == VoiceCallStatus.connected;
  bool get isBusy =>
      _status == VoiceCallStatus.connecting ||
      _status == VoiceCallStatus.reconnecting;
  bool get isCleanupInProgress => _pendingRoomTeardowns > 0;
  bool get isVideoCall => isDirectCall && _videoRequested;
  bool get cameraChangeInProgress => _cameraChangeInProgress;
  bool get cameraPermissionDenied => _cameraPermissionDenied;
  String? get cameraIssue => _cameraIssue;
  bool get shouldMirrorLocalCamera => _cameraPosition == CameraPosition.front;
  bool get canSwitchSpeakerphone => AudioManager.instance.canSwitchSpeakerphone;
  bool get speakerChangeInProgress => _speakerChangeInProgress;
  bool get isSpeakerPreferred => AudioManager.instance.isSpeakerOutputPreferred;

  bool get isCameraEnabled {
    final local = _room?.localParticipant;
    return isConnected && local != null && local.isCameraEnabled();
  }

  VideoTrack? get localCameraTrack {
    final local = _room?.localParticipant;
    if (local == null) return null;
    for (final publication in local.videoTrackPublications) {
      if (publication.source == TrackSource.camera &&
          !publication.muted &&
          publication.track != null) {
        return publication.track;
      }
    }
    return null;
  }

  VideoTrack? get remoteCameraTrack {
    final room = _room;
    if (room == null) return null;
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        if (publication.source == TrackSource.camera &&
            publication.subscribed &&
            !publication.muted &&
            publication.track != null) {
          return publication.track;
        }
      }
    }
    return null;
  }

  double get roomEnergy {
    final values = participants
        .where((participant) => participant.isSpeaking)
        .map((participant) => participant.audioLevel)
        .toList(growable: false);

    if (values.isEmpty) return 0;
    final sum = values.fold<double>(0, (total, value) => total + value);
    return (sum / values.length).clamp(0, 1).toDouble();
  }

  /// Number used by lightweight persistent chrome.
  ///
  /// Unlike [participants], this does not allocate view models or read audio
  /// levels. The service emits meter notifications every 50 ms, so a cheap
  /// count prevents the mini player from rebuilding an O(n) participant list
  /// merely to display one integer.
  int get participantCount {
    final room = _room;
    if (room == null) return 0;
    return (room.localParticipant == null ? 0 : 1) +
        room.remoteParticipants.length;
  }

  List<VoiceParticipantViewData> get participants {
    final room = _room;
    if (room == null) return const [];

    final result = <VoiceParticipantViewData>[];
    final local = room.localParticipant;

    if (local != null) {
      result.add(
        VoiceParticipantViewData(
          identity: local.identity,
          displayName: _displayName(local.name, local.identity),
          isLocal: true,
          isSpeaking: local.isSpeaking,
          audioLevel: local.audioLevel.clamp(0, 1).toDouble(),
          isMuted: isMuted,
        ),
      );
    }

    for (final participant in room.remoteParticipants.values) {
      result.add(
        VoiceParticipantViewData(
          identity: participant.identity,
          displayName: _displayName(participant.name, participant.identity),
          isLocal: false,
          isSpeaking: participant.isSpeaking,
          audioLevel: participant.audioLevel.clamp(0, 1).toDouble(),
          isMuted: false,
        ),
      );
    }

    result.sort((a, b) {
      if (a.isLocal != b.isLocal) return a.isLocal ? -1 : 1;
      if (a.isSpeaking != b.isSpeaking) return a.isSpeaking ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

    return result;
  }

  /// Check-only gate used by [join]. It never opens a native/browser prompt.
  Future<PermissionReadinessSnapshot> mediaPermissionStatus({
    bool includeCamera = false,
  }) => _permissionReadiness.mediaSnapshot(includeCamera: includeCamera);

  /// Explicit prejoin/call-control API. UI must invoke it directly from a
  /// button press so web permission requests retain a genuine user gesture.
  Future<PermissionReadinessSnapshot> prepareMediaPermissionsFromUserGesture({
    bool includeCamera = false,
  }) => _permissionReadiness.prepareMediaFromUserGesture(
    includeCamera: includeCamera,
  );

  Future<void> join({
    required String roomId,
    required String roomName,
    required String participantName,
    bool playSound = true,
    bool startMuted = false,
  }) async {
    return _joinWithToken(
      sessionRoomId: roomId,
      roomName: roomName,
      kind: VoiceSessionKind.room,
      startMuted: startMuted,
      tokenLoader: () => _tokenService.createJoinToken(
        roomId: roomId,
        participantName: participantName,
      ),
      playSound: playSound,
    );
  }

  Future<void> joinDirectCall({
    required String callId,
    required String contactName,
    required String participantName,
    bool enableCamera = false,
    bool playSound = true,
  }) {
    return _joinWithToken(
      sessionRoomId: 'call_$callId',
      roomName: contactName,
      kind: VoiceSessionKind.directCall,
      directCallId: callId,
      enableCamera: enableCamera,
      tokenLoader: () => _directCallService.createJoinToken(callId),
      playSound: playSound,
    );
  }

  Future<void> _joinWithToken({
    required String sessionRoomId,
    required String roomName,
    required VoiceSessionKind kind,
    required Future<VoiceConnectionInfo> Function() tokenLoader,
    String? directCallId,
    bool enableCamera = false,
    bool startMuted = false,
    bool playSound = true,
  }) async {
    if (_roomId == sessionRoomId && isConnected) {
      if (startMuted && !isMuted) {
        await _muteCurrentRoomForSafeReentry(sessionRoomId);
      }
      return;
    }

    // Reserve this attempt before waiting for the previous room to tear down.
    // A second join that starts while teardown is in flight must win; the
    // older Future must not resume later and replace the newer session.
    final joinEpoch = ++_sessionEpoch;
    final initialMicrophoneEpoch = ++_microphoneOperationEpoch;
    final initialCameraEpoch = ++_cameraOperationEpoch;
    final initialSpeakerEpoch = ++_speakerOperationEpoch;
    try {
      if (_roomId != null ||
          _room != null ||
          _status != VoiceCallStatus.disconnected) {
        await _disconnectCurrentSession(
          playSound: false,
          invalidateOperations: false,
          requireCleanupComplete: true,
        );
      }
      // Never start new process-wide audio until the old raw SDK work ends.
      // The public wait is bounded; the underlying safety barrier is not.
      await _waitForRoomTeardown();
    } on VoiceCleanupInProgressException catch (error) {
      if (_sessionEpoch != joinEpoch) return;
      _roomId = sessionRoomId;
      _roomName = roomName;
      _sessionKind = kind;
      _directCallId = directCallId;
      _videoRequested = enableCamera;
      _isMuted = true;
      _desiredMicrophoneEnabled = false;
      _desiredCameraEnabled = false;
      _cameraChangeInProgress = false;
      _errorMessage = _friendlyError(error);
      _setStatus(VoiceCallStatus.failed);
      rethrow;
    }
    if (_sessionEpoch != joinEpoch ||
        _microphoneOperationEpoch != initialMicrophoneEpoch ||
        _cameraOperationEpoch != initialCameraEpoch ||
        _speakerOperationEpoch != initialSpeakerEpoch) {
      return;
    }

    Room? joiningRoom;
    EventsListener<RoomEvent>? joiningEvents;
    final cameraRequestedNow = enableCamera && _appIsForeground;

    _roomId = sessionRoomId;
    _roomName = roomName;
    _sessionKind = kind;
    _directCallId = directCallId;
    _errorMessage = null;
    _isMuted = startMuted;
    _desiredMicrophoneEnabled = !startMuted;
    _videoRequested = enableCamera;
    _desiredCameraEnabled = cameraRequestedNow;
    // Private audio starts on the earpiece. Video calls and social rooms use
    // speakerphone by default, without forcing over a wired/Bluetooth route.
    _desiredSpeakerPreferred = kind == VoiceSessionKind.room || enableCamera;
    _cameraChangeInProgress = cameraRequestedNow;
    _cameraPermissionDenied = false;
    _cameraIssue = null;
    _cameraPosition = CameraPosition.front;
    _setStatus(VoiceCallStatus.connecting);

    try {
      final connectionInfo = await tokenLoader();
      if (!_isJoinCurrent(joinEpoch, sessionRoomId)) return;

      // The server grant is known before checking media readiness.
      // Broadcast/podcast audience can listen without granting a microphone
      // they are not allowed to use.
      final cameraAvailable = await _checkPermissions(
        requireMicrophone:
            kind == VoiceSessionKind.directCall || connectionInfo.canPublish,
        requireCamera: cameraRequestedNow,
      );
      if (!_isJoinCurrent(joinEpoch, sessionRoomId)) return;

      if (canSwitchSpeakerphone) {
        try {
          await _enqueueSpeakerPreference(
            operationEpoch: initialSpeakerEpoch,
            preferred: _desiredSpeakerPreferred,
          );
        } catch (_) {
          // Routing failure is recoverable from the in-call output control.
        }
      }
      if (!_isJoinCurrent(joinEpoch, sessionRoomId) ||
          _speakerOperationEpoch != initialSpeakerEpoch) {
        return;
      }

      final room =
          _roomFactoryOverride?.call() ??
          Room(
            roomOptions: const RoomOptions(
              adaptiveStream: true,
              dynacast: true,
            ),
          );
      joiningRoom = room;
      var initialMediaReady = false;

      _room = room;
      room.addListener(_handleRoomChanged);

      joiningEvents = room.createListener()
        ..on<RoomReconnectingEvent>((_) {
          if (_isJoinCurrent(joinEpoch, sessionRoomId)) {
            _setStatus(VoiceCallStatus.reconnecting);
          }
        })
        ..on<RoomReconnectedEvent>((_) {
          if (_isJoinCurrent(joinEpoch, sessionRoomId)) {
            _setStatus(
              initialMediaReady
                  ? VoiceCallStatus.connected
                  : VoiceCallStatus.connecting,
            );
          }
        })
        ..on<RoomDisconnectedEvent>((_) {
          if (_isJoinCurrent(joinEpoch, sessionRoomId)) {
            // A terminal SDK disconnect is also a local capture boundary. Do
            // not merely repaint the status while retaining native tracks.
            unawaited(
              _disconnectCurrentSession(
                playSound: false,
                invalidateOperations: true,
              ),
            );
          }
        })
        ..on<ParticipantConnectedEvent>((_) {
          unawaited(_sounds.play(UiSound.participantJoined));
        })
        ..on<ParticipantDisconnectedEvent>((_) {
          unawaited(_sounds.play(UiSound.participantLeft));
        });
      _events = joiningEvents;

      final connecting = room.connect(
        connectionInfo.serverUrl,
        connectionInfo.participantToken,
      );
      // Room.connect has its own native-audio cleanup on failure. Track its
      // settlement separately from this join Future (which itself can await
      // teardown) so an old connect's finally cannot stop replacement audio.
      _roomConnections[room] = connecting.catchError((Object _) {});
      await connecting.timeout(_connectionTimeout);
      if (!_isJoinCurrent(joinEpoch, sessionRoomId) ||
          !identical(_room, room)) {
        await _disposeStaleRoomInstance(room, joiningEvents);
        return;
      }

      final localParticipant = room.localParticipant;
      if (localParticipant == null) {
        throw StateError('Local voice participant was not created.');
      }

      // The post-connect grant can be narrower than the token snapshot (for
      // example, a speaker demoted while joining). Both must permit capture.
      final shouldStartMicrophone =
          connectionInfo.canPublish &&
          localParticipant.permissions.canPublish &&
          !startMuted;
      _desiredMicrophoneEnabled = shouldStartMicrophone;
      if (shouldStartMicrophone) {
        // A permitted microphone that fails to start/publish is a failed join,
        // not a successful muted call. Let the outer failure boundary retain
        // the error, invalidate media operations and dispose this session.
        await localParticipant.setMicrophoneEnabled(true);
      } else {
        // New rooms have no microphone publication to disable. Listeners and
        // speakers starting muted should not invoke native capture at all.
        _isMuted = true;
      }
      if (!_isMicrophoneOperationCurrent(
        initialMicrophoneEpoch,
        room,
        desiredEnabled: shouldStartMicrophone,
      )) {
        if (shouldStartMicrophone) {
          await _disableStaleMicrophone(localParticipant, room);
        }
        await _disposeStaleRoomInstance(room, joiningEvents);
        return;
      }
      _isMuted = !shouldStartMicrophone;
      if (!_isJoinCurrent(joinEpoch, sessionRoomId) ||
          !identical(_room, room)) {
        await _disposeStaleRoomInstance(room, joiningEvents);
        return;
      }
      if (cameraRequestedNow &&
          cameraAvailable &&
          _isCameraOperationCurrent(
            initialCameraEpoch,
            room,
            desiredEnabled: true,
          )) {
        try {
          await _enableCameraSafely(
            localParticipant: localParticipant,
            room: room,
            operationEpoch: initialCameraEpoch,
            position: CameraPosition.front,
          );
          if (!_isJoinCurrent(joinEpoch, sessionRoomId) ||
              !identical(_room, room)) {
            await _disposeStaleRoomInstance(room, joiningEvents);
            return;
          }
          if (!_isCameraOperationCurrent(
                initialCameraEpoch,
                room,
                desiredEnabled: true,
              ) &&
              !_desiredCameraEnabled) {
            await _disableCameraOrCloseSession(
              localParticipant,
              room,
              joiningEvents,
            );
          }
        } catch (_) {
          // Camera failure must not tear down a healthy private audio path.
          // The user can continue safely with camera off and retry in place.
          if (_cameraOperationEpoch == initialCameraEpoch) {
            _cameraIssue =
                'Camera could not be started. Continue with audio or retry.';
          }
        } finally {
          if (_cameraOperationEpoch == initialCameraEpoch) {
            _cameraChangeInProgress = false;
          }
        }
      } else if (_cameraOperationEpoch == initialCameraEpoch) {
        _cameraChangeInProgress = false;
      }
      // The room UI needs rapid speaking-level updates. A direct video call
      // does not: rebuilding a full-screen renderer every 50 ms wastes both
      // CPU and battery and can cause visible jank.
      if (kind == VoiceSessionKind.room) _startAudioMeter();
      if (!_isJoinCurrent(joinEpoch, sessionRoomId)) {
        await _disposeStaleRoomInstance(room, joiningEvents);
        return;
      }
      initialMediaReady = true;
      _setStatus(VoiceCallStatus.connected);
      if (playSound) {
        unawaited(_sounds.play(UiSound.roomJoined));
      }
    } catch (error, stackTrace) {
      if (!_isJoinCurrent(joinEpoch, sessionRoomId)) {
        final room = joiningRoom;
        if (room != null) {
          await _disposeStaleRoomInstance(room, joiningEvents);
        }
        return;
      }
      _cameraOperationEpoch++;
      _desiredCameraEnabled = false;
      _microphoneOperationEpoch++;
      _desiredMicrophoneEnabled = false;
      _speakerOperationEpoch++;
      _cameraChangeInProgress = false;
      Object failure = error;
      try {
        await _disposeRoom();
      } on VoiceCleanupInProgressException catch (cleanupError) {
        failure = cleanupError;
      } catch (_) {
        // Capture has already been stopped locally; if SDK disposal reports
        // an error, keep the original join error and leave connecting state.
      }
      // Report failure/cleanup-busy without allowing another native session
      // through the barrier. End/newer attempts can supersede this UI update.
      if (!_isJoinCurrent(joinEpoch, sessionRoomId)) return;
      _errorMessage = _friendlyError(failure);
      _setStatus(VoiceCallStatus.failed);
      Error.throwWithStackTrace(failure, stackTrace);
    }
  }

  Future<void> setMuted(bool muted) async {
    final operationRoom = _room;
    final localParticipant = operationRoom?.localParticipant;
    if (localParticipant == null || !isConnected || _muteChangeInProgress) {
      return;
    }
    // Compare against the AUTHORITATIVE state, not the remembered flag —
    // they can disagree after a reconnect, and acting on the stale flag
    // is how the button got stuck looking pressed.
    if (isMuted == muted) return;

    final previous = isMuted;
    final operationEpoch = ++_microphoneOperationEpoch;
    _desiredMicrophoneEnabled = !muted;
    _muteChangeInProgress = true;
    _isMuted = muted;
    notifyListeners();
    try {
      await localParticipant.setMicrophoneEnabled(!muted);
      if (!_isMicrophoneOperationCurrent(
        operationEpoch,
        operationRoom,
        desiredEnabled: !muted,
      )) {
        if (!muted && operationRoom != null) {
          await _disableStaleMicrophone(localParticipant, operationRoom);
        }
        return;
      }
      unawaited(
        _sounds.play(
          muted ? UiSound.microphoneMuted : UiSound.microphoneUnmuted,
        ),
      );
    } catch (_) {
      if (_microphoneOperationEpoch == operationEpoch &&
          identical(_room, operationRoom)) {
        _desiredMicrophoneEnabled = !previous;
        _isMuted = previous;
      }
      rethrow;
    } finally {
      if (_microphoneOperationEpoch == operationEpoch &&
          identical(_room, operationRoom)) {
        _muteChangeInProgress = false;
        notifyListeners();
      }
    }
  }

  Future<void> _muteCurrentRoomForSafeReentry(String sessionRoomId) async {
    final operationRoom = _room;
    final localParticipant = operationRoom?.localParticipant;
    final operationEpoch = _sessionEpoch;
    if (operationRoom == null || localParticipant == null) {
      await disconnect(playSound: false);
      throw StateError('The current microphone session could not be secured.');
    }

    final microphoneEpoch = ++_microphoneOperationEpoch;
    _desiredMicrophoneEnabled = false;
    _muteChangeInProgress = true;
    _isMuted = true;
    notifyListeners();
    try {
      await localParticipant.setMicrophoneEnabled(false);
      if (_sessionEpoch != operationEpoch ||
          _microphoneOperationEpoch != microphoneEpoch ||
          _roomId != sessionRoomId ||
          !identical(_room, operationRoom)) {
        return;
      }
    } catch (_) {
      if (_sessionEpoch == operationEpoch &&
          _microphoneOperationEpoch == microphoneEpoch &&
          identical(_room, operationRoom)) {
        await disconnect(playSound: false);
      }
      rethrow;
    } finally {
      if (_sessionEpoch == operationEpoch &&
          _microphoneOperationEpoch == microphoneEpoch &&
          identical(_room, operationRoom)) {
        _muteChangeInProgress = false;
        notifyListeners();
      }
    }
  }

  Future<void> toggleMute() async {
    final operationRoom = _room;
    final localParticipant = operationRoom?.localParticipant;
    if (localParticipant == null || !isConnected || _muteChangeInProgress) {
      return;
    }

    final previous = isMuted;
    final next = !previous;
    final operationEpoch = ++_microphoneOperationEpoch;
    _desiredMicrophoneEnabled = !next;

    _muteChangeInProgress = true;
    _isMuted = next;
    notifyListeners();

    try {
      await localParticipant.setMicrophoneEnabled(!next);
      if (!_isMicrophoneOperationCurrent(
        operationEpoch,
        operationRoom,
        desiredEnabled: !next,
      )) {
        if (!next && operationRoom != null) {
          await _disableStaleMicrophone(localParticipant, operationRoom);
        }
        return;
      }
      unawaited(
        _sounds.play(
          next ? UiSound.microphoneMuted : UiSound.microphoneUnmuted,
        ),
      );
    } catch (_) {
      if (_microphoneOperationEpoch == operationEpoch &&
          identical(_room, operationRoom)) {
        _desiredMicrophoneEnabled = !previous;
        _isMuted = previous;
      }
      rethrow;
    } finally {
      if (_microphoneOperationEpoch == operationEpoch &&
          identical(_room, operationRoom)) {
        _muteChangeInProgress = false;
        notifyListeners();
      }
    }
  }

  Future<void> setCameraEnabled(bool enabled) async {
    final localParticipant = _room?.localParticipant;
    final operationRoom = _room;
    if (!isVideoCall ||
        localParticipant == null ||
        !isConnected ||
        _cameraChangeInProgress ||
        isCameraEnabled == enabled) {
      return;
    }
    if (enabled && !_appIsForeground) {
      _cameraIssue = 'Return to the app before turning on the camera.';
      notifyListeners();
      return;
    }

    final operationEpoch = ++_cameraOperationEpoch;
    _desiredCameraEnabled = enabled;
    _cameraChangeInProgress = true;
    _cameraIssue = null;
    notifyListeners();
    try {
      if (enabled && !await _cameraPermissionAvailable()) {
        _cameraPermissionDenied = true;
        throw StateError('Camera permission is required to turn on video.');
      }
      if (!_isCameraOperationCurrent(
        operationEpoch,
        operationRoom,
        desiredEnabled: enabled,
      )) {
        return;
      }
      if (enabled) {
        await _enableCameraSafely(
          localParticipant: localParticipant,
          room: operationRoom!,
          operationEpoch: operationEpoch,
          position: _cameraPosition,
        );
      } else {
        await localParticipant.setCameraEnabled(false);
      }
      if (!_isCameraOperationCurrent(
        operationEpoch,
        operationRoom,
        desiredEnabled: enabled,
      )) {
        if (enabled && !_desiredCameraEnabled) {
          await _disableCameraOrCloseSession(
            localParticipant,
            operationRoom!,
            identical(_room, operationRoom) ? _events : null,
          );
        }
        return;
      }
      _cameraPermissionDenied = false;
    } catch (error) {
      // A camera API may fail after partially changing capture state. Force a
      // known-off state; if that also fails, the helper disposes the room.
      if (operationRoom != null) {
        await _disableCameraOrCloseSession(
          localParticipant,
          operationRoom,
          identical(_room, operationRoom) ? _events : null,
        );
      }
      if (_cameraOperationEpoch != operationEpoch) return;
      _cameraIssue = enabled
          ? 'Camera could not be started. Continue with audio or retry.'
          : 'Camera could not be turned off. Try again.';
      rethrow;
    } finally {
      if (_cameraOperationEpoch == operationEpoch) {
        _cameraChangeInProgress = false;
      }
      notifyListeners();
    }
  }

  /// Cancels every in-flight camera-on operation when the app leaves the
  /// foreground. The camera remains off after resume until the user turns it
  /// on again.
  Future<void> pauseCameraForBackground() async {
    // This flag is set even if a video join has not populated its local state
    // yet. A lifecycle event that races the first permission request must
    // still prevent the late Future from starting capture in the background.
    _appIsForeground = false;
    final operationEpoch = ++_cameraOperationEpoch;
    _desiredCameraEnabled = false;
    if (!isVideoCall) return;
    final operationRoom = _room;
    final localParticipant = operationRoom?.localParticipant;
    _cameraChangeInProgress = true;
    notifyListeners();
    try {
      if (localParticipant != null) {
        await _disableCameraOrCloseSession(
          localParticipant,
          operationRoom!,
          identical(_room, operationRoom) ? _events : null,
        );
      }
    } finally {
      if (_cameraOperationEpoch == operationEpoch) {
        _cameraChangeInProgress = false;
      }
      notifyListeners();
    }
  }

  /// Marks the app visible again without restoring capture. Camera restart is
  /// always a fresh, explicit user action after returning to the foreground.
  void resumeAfterBackground() {
    _appIsForeground = true;
  }

  Future<void> toggleCamera() => setCameraEnabled(!isCameraEnabled);

  Future<void> toggleSpeaker() async {
    if (!isDirectCall ||
        !isConnected ||
        !canSwitchSpeakerphone ||
        _speakerChangeInProgress) {
      return;
    }
    final operationEpoch = ++_speakerOperationEpoch;
    final preferred = !isSpeakerPreferred;
    _desiredSpeakerPreferred = preferred;
    _speakerChangeInProgress = true;
    notifyListeners();
    try {
      await _enqueueSpeakerPreference(
        operationEpoch: operationEpoch,
        preferred: preferred,
      );
    } finally {
      if (_speakerOperationEpoch == operationEpoch) {
        _speakerChangeInProgress = false;
        notifyListeners();
      }
    }
  }

  Future<void> flipCamera() async {
    final operationRoom = _room;
    final localParticipant = operationRoom?.localParticipant;
    if (!isVideoCall ||
        !_appIsForeground ||
        !isConnected ||
        localCameraTrack is! LocalVideoTrack ||
        operationRoom == null ||
        localParticipant == null ||
        _cameraChangeInProgress) {
      return;
    }
    final operationEpoch = ++_cameraOperationEpoch;
    _cameraChangeInProgress = true;
    _cameraIssue = null;
    notifyListeners();
    try {
      final nextPosition = _cameraPosition.switched();
      await _enableCameraSafely(
        localParticipant: localParticipant,
        room: operationRoom,
        operationEpoch: operationEpoch,
        position: nextPosition,
      );
      if (!_isCameraOperationCurrent(
        operationEpoch,
        operationRoom,
        desiredEnabled: true,
      )) {
        await _disableCameraOrCloseSession(
          localParticipant,
          operationRoom,
          identical(_room, operationRoom) ? _events : null,
        );
        return;
      }
      _cameraPosition = nextPosition;
    } catch (_) {
      if (_cameraOperationEpoch == operationEpoch) {
        _cameraIssue = 'Camera could not be switched. Try again.';
      }
      rethrow;
    } finally {
      if (_cameraOperationEpoch == operationEpoch) {
        _cameraChangeInProgress = false;
      }
      notifyListeners();
    }
  }

  Future<void> disconnect({bool playSound = true}) async {
    await _disconnectCurrentSession(
      playSound: playSound,
      invalidateOperations: true,
    );
  }

  Future<void> _disconnectCurrentSession({
    required bool playSound,
    required bool invalidateOperations,
    bool requireCleanupComplete = false,
  }) async {
    // Invalidate permission, token and media awaits before clearing any local
    // state. A late Future must never reconnect or republish after logout,
    // hang-up, account switch or a newer join.
    if (invalidateOperations) {
      _sessionEpoch++;
      _microphoneOperationEpoch++;
      _cameraOperationEpoch++;
      _speakerOperationEpoch++;
    }
    _desiredMicrophoneEnabled = false;
    _desiredSpeakerPreferred = false;
    if (canSwitchSpeakerphone) {
      // Do not let an older session's delayed speaker toggle become the last
      // process-global route write after hang-up or replacement join.
      unawaited(
        _enqueueSpeakerPreference(
          operationEpoch: _speakerOperationEpoch,
          preferred: false,
        ).catchError((_) {}),
      );
    }
    final wasConnected = isConnected;
    _status = VoiceCallStatus.disconnected;
    _errorMessage = null;
    _isMuted = false;
    _muteChangeInProgress = false;
    _roomId = null;
    _roomName = null;
    _sessionKind = null;
    _directCallId = null;
    _videoRequested = false;
    _desiredCameraEnabled = false;
    _speakerChangeInProgress = false;
    _cameraChangeInProgress = false;
    _cameraPermissionDenied = false;
    _cameraIssue = null;
    _cameraPosition = CameraPosition.front;
    notifyListeners();

    try {
      await _disposeRoom();
    } on VoiceCleanupInProgressException {
      // End remains local-first and finishes in bounded time. Cleanup keeps
      // running behind the safety barrier; new joins explicitly wait/reject.
      if (requireCleanupComplete) rethrow;
    }
    if (playSound && wasConnected) {
      unawaited(_sounds.play(UiSound.roomLeft));
    }
  }

  void _startAudioMeter() {
    _audioMeterTimer?.cancel();
    _audioMeterTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_room == null || !isConnected) return;
      notifyListeners();
    });
  }

  Future<void> _disposeRoom() async {
    _audioMeterTimer?.cancel();
    _audioMeterTimer = null;
    final room = _room;
    _room = null;

    final events = _events;
    events?.dispose();
    _events = null;

    if (room != null) {
      await _disposeRoomInstance(room, events, listenerDisposed: true);
    }
    await _waitForRoomTeardown();
  }

  Future<void> _waitForRoomTeardown() =>
      _awaitCleanup(_waitForRoomTeardownUnbounded());

  Future<void> _waitForRoomTeardownUnbounded() async {
    while (true) {
      final pending = _roomTeardownTail;
      await pending;
      if (identical(pending, _roomTeardownTail)) return;
    }
  }

  Future<void> _awaitCleanup(Future<void> cleanup) => cleanup.timeout(
    _cleanupWaitTimeout,
    onTimeout: () => throw const VoiceCleanupInProgressException(),
  );

  Future<void> _disposeStaleRoomInstance(
    Room room,
    EventsListener<RoomEvent>? events,
  ) async {
    try {
      await _disposeRoomInstance(room, events);
    } on VoiceCleanupInProgressException {
      // This superseded attempt must finish without mutating the newer UI.
      // The raw cleanup remains observed and blocks replacement native audio.
    }
  }

  bool _isJoinCurrent(int epoch, String sessionRoomId) =>
      _sessionEpoch == epoch && _roomId == sessionRoomId;

  bool _isCameraOperationCurrent(
    int epoch,
    Room? room, {
    required bool desiredEnabled,
  }) =>
      _cameraOperationEpoch == epoch &&
      _desiredCameraEnabled == desiredEnabled &&
      (!desiredEnabled || _appIsForeground) &&
      room != null &&
      identical(_room, room);

  bool _isMicrophoneOperationCurrent(
    int epoch,
    Room? room, {
    required bool desiredEnabled,
  }) =>
      _microphoneOperationEpoch == epoch &&
      _desiredMicrophoneEnabled == desiredEnabled &&
      room != null &&
      identical(_room, room);

  Future<void> _disableStaleMicrophone(
    LocalParticipant localParticipant,
    Room room,
  ) async {
    try {
      // LiveKit serializes source changes. This disable is therefore queued
      // behind a late unmute/restartTrack and wins after any newly-created
      // getUserMedia track appears.
      await localParticipant.setMicrophoneEnabled(false);
    } catch (_) {
      // Fall through to hard-stop every track visible after the failed SDK
      // reconciliation. The owning room is also disposed by the caller.
    }
    await _stopLocalCaptureImmediately(room);
  }

  Future<void> _enqueueSpeakerPreference({
    required int operationEpoch,
    required bool preferred,
  }) {
    final previous = _speakerRouteTail;
    final operation = () async {
      try {
        await previous;
      } catch (_) {
        // A failed route write must not poison the process-global queue.
      }
      if (_speakerOperationEpoch != operationEpoch ||
          _desiredSpeakerPreferred != preferred) {
        return;
      }
      await AudioManager.instance.setSpeakerOutputPreferred(preferred);
    }();
    _speakerRouteTail = operation;
    return operation;
  }

  /// Publishes camera capture with explicit ownership of the candidate track.
  /// LiveKit 2.10 does not stop a newly-created video track when signaling or
  /// negotiation fails before a publication is registered, so using
  /// `setCameraEnabled(true)` directly can leave an invisible orphan capture.
  Future<void> _enableCameraSafely({
    required LocalParticipant localParticipant,
    required Room room,
    required int operationEpoch,
    required CameraPosition position,
  }) async {
    LocalVideoTrack? candidate;
    try {
      final existing = localParticipant.getTrackPublicationBySource(
        TrackSource.camera,
      );
      if (existing != null) {
        await localParticipant.removePublishedTrack(existing.sid);
      }
      if (!_isCameraOperationCurrent(
        operationEpoch,
        room,
        desiredEnabled: true,
      )) {
        return;
      }

      final captureOptions = CameraCaptureOptions(cameraPosition: position);
      candidate =
          await (_cameraTrackFactoryOverride?.call(captureOptions) ??
              LocalVideoTrack.createCameraTrack(captureOptions));
      // Capture starts before LiveKit exposes a publication. Keep ownership
      // discoverable by End while publishVideoTrack is still awaiting the SDK.
      (_cameraCandidates[room] ??= <LocalVideoTrack>{}).add(candidate);
      if (!_isCameraOperationCurrent(
        operationEpoch,
        room,
        desiredEnabled: true,
      )) {
        return;
      }

      await localParticipant.publishVideoTrack(candidate);
      if (_isCameraOperationCurrent(
        operationEpoch,
        room,
        desiredEnabled: true,
      )) {
        // Ownership transferred to the participant publication.
        _cameraCandidates[room]?.remove(candidate);
        candidate = null;
      }
    } finally {
      // Publication can succeed after End already disposed the Room. Only a
      // current operation transfers ownership; every other path must stop its
      // candidate directly, independent of idempotent Room cleanup.
      if (candidate != null) {
        _cameraCandidates[room]?.remove(candidate);
        await _stopLocalTrack(candidate);
      }
    }
  }

  Future<void> _stopLocalTrack(LocalTrack track) async {
    try {
      track.mediaStreamTrack.enabled = false;
    } catch (_) {
      // The awaited hard stop below is authoritative.
    }
    try {
      await track.stop();
    } catch (_) {
      try {
        await track.mediaStreamTrack.stop();
      } catch (_) {
        // The owning Room disposal remains the final native cleanup.
      }
    }
  }

  /// Camera shutdown is fail-closed. If LiveKit cannot mute the video track,
  /// dispose the entire affected room so capture cannot continue invisibly.
  Future<void> _disableCameraOrCloseSession(
    LocalParticipant localParticipant,
    Room room,
    EventsListener<RoomEvent>? events,
  ) async {
    try {
      await localParticipant.setCameraEnabled(false);
    } catch (_) {
      if (identical(_room, room)) {
        await disconnect(playSound: false);
      } else {
        await _disposeRoomInstance(room, events);
      }
    }
  }

  Future<void> _disposeRoomInstance(
    Room room,
    EventsListener<RoomEvent>? events, {
    bool listenerDisposed = false,
  }) {
    // A late mic/camera/connect continuation can reach cleanup again after a
    // replacement is already connected. Never repeat old Room.disconnect(),
    // which would stop the replacement's process-wide Android audio session.
    final existing = _roomDisposals[room];
    if (existing != null) return _awaitCleanup(existing);
    final completion = Completer<void>();
    _roomDisposals[room] = completion.future;
    _pendingRoomTeardowns++;
    final previousTeardown = _roomTeardownTail;
    // Observe errors on the barrier without losing the error returned to the
    // cleanup owner, or poisoning later joins after best-effort SDK disposal.
    _roomTeardownTail = Future.wait<void>([
      previousTeardown,
      completion.future.catchError((Object _) {}),
    ]).then((_) {});
    unawaited(
      _tearDownRoomInstance(
        room,
        events,
        previousTeardown: previousTeardown,
        listenerDisposed: listenerDisposed,
      ).then(
        (_) {
          _pendingRoomTeardowns--;
          completion.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          _pendingRoomTeardowns--;
          completion.completeError(error, stackTrace);
        },
      ),
    );
    return _awaitCleanup(completion.future);
  }

  Future<void> _tearDownRoomInstance(
    Room room,
    EventsListener<RoomEvent>? events, {
    required Future<void> previousTeardown,
    required bool listenerDisposed,
  }) async {
    // `Room.disconnect()` can wait up to ten seconds for a signaling event.
    // Stop physical capture first so End/logout/background is local-first in
    // fact, not only in UI state.
    // Keep the actual LocalTrack objects, not only their publications. A
    // delayed LiveKit `restartTrack()` mutates the same object after
    // getUserMedia returns. Room cleanup can remove its publication while that
    // Future is pending, so a later scan of the participant alone would miss
    // the restarted native microphone.
    final localParticipant = room.localParticipant;
    final capturedTracks = _snapshotLocalTracks(room);
    await _stopLocalCaptureImmediately(room);
    if (localParticipant != null) {
      // Queue a final mic-off behind any in-flight LiveKit unmute. Attach a
      // late hard stop even if the bounded wait expires, so a delayed
      // getUserMedia result can never become a detached live track.
      final microphoneOff = localParticipant
          .setMicrophoneEnabled(false)
          .catchError((_) => null);
      await _guardDeferredCaptureTeardown<LocalTrack>(
        pendingDisable: microphoneOff,
        capturedTracks: capturedTracks,
        stopCapturedTrack: _stopLocalTrack,
        stopCurrentCapture: () => _stopLocalCaptureImmediately(room),
      );
    }
    if (identical(_room, room)) {
      _room = null;
      if (identical(_events, events)) _events = null;
    }
    if (!listenerDisposed) events?.dispose();
    room.removeListener(_handleRoomChanged);
    await previousTeardown;
    try {
      await room.disconnect();
    } catch (_) {
      // Cleanup is best-effort; dispose still needs to run.
    }
    try {
      await room.dispose();
    } finally {
      // Disposal cancels the transport, but its connect Future may settle
      // later. Wait for the SDK's process-global audio finally before any
      // replacement Room can start, including when disposal itself fails.
      await _roomConnections[room];
    }
  }

  Future<void> _stopLocalCaptureImmediately(Room room) async {
    final tracks = _snapshotLocalTracks(room);

    // Disable synchronously before awaiting any SDK/network operation.
    for (final track in tracks) {
      try {
        track.mediaStreamTrack.enabled = false;
      } catch (_) {
        // The hard stop below is the fallback.
      }
    }
    await Future.wait(tracks.map(_stopLocalTrack));
  }

  List<LocalTrack> _snapshotLocalTracks(Room room) {
    final localParticipant = room.localParticipant;
    return <LocalTrack>{
      ...?_cameraCandidates[room],
      ...?localParticipant?.audioTrackPublications
          .map((publication) => publication.track)
          .whereType<LocalTrack>(),
      ...?localParticipant?.videoTrackPublications
          .map((publication) => publication.track)
          .whereType<LocalTrack>(),
    }.toList(growable: false);
  }

  Future<void> _guardDeferredCaptureTeardown<T>({
    required Future<void> pendingDisable,
    required List<T> capturedTracks,
    required Future<void> Function(T track) stopCapturedTrack,
    required Future<void> Function() stopCurrentCapture,
  }) async {
    final guardedDisable = pendingDisable.whenComplete(() async {
      // These references remain valid even if Room._cleanUp has already
      // removed every publication. LiveKit restartTrack replaces the native
      // media on the same LocalTrack instance, so stopping it here also catches
      // a getUserMedia result that arrives after room disposal.
      await Future.wait(capturedTracks.map(stopCapturedTrack));
      await stopCurrentCapture();
    });
    final completedBeforeTimeout = await _captureDisableWaiter(
      guardedDisable,
      _microphoneTeardownTimeout,
    );
    if (!completedBeforeTimeout) {
      // Future.timeout does not cancel its source. Keep the captured-reference
      // guard attached and consume any late cleanup error.
      unawaited(guardedDisable.catchError((_) {}));
    }
    await stopCurrentCapture();
  }

  @visibleForTesting
  Future<void> guardDeferredCaptureTeardownForTesting<T>({
    required Future<void> pendingDisable,
    required List<T> capturedTracks,
    required Future<void> Function(T track) stopCapturedTrack,
    required Future<void> Function() stopCurrentCapture,
  }) => _guardDeferredCaptureTeardown<T>(
    pendingDisable: pendingDisable,
    capturedTracks: capturedTracks,
    stopCapturedTrack: stopCapturedTrack,
    stopCurrentCapture: stopCurrentCapture,
  );

  Future<bool> _checkPermissions({
    required bool requireMicrophone,
    required bool requireCamera,
  }) async {
    if (!requireMicrophone && !requireCamera) return true;
    final snapshot = await _permissionReadiness.mediaSnapshot(
      includeCamera: requireCamera,
    );
    if (requireMicrophone) {
      final microphone = snapshot[AppPermissionKind.microphone];
      if (!microphone.isUsable) {
        throw VoicePermissionRequiredException(
          AppPermissionKind.microphone,
          microphone,
        );
      }
    }
    if (!requireCamera) return true;
    final camera = snapshot[AppPermissionKind.camera];
    _cameraPermissionDenied = !camera.isUsable;
    if (!camera.isUsable) {
      _cameraIssue =
          'Camera access is off. The call will continue with audio only.';
    }
    return camera.isUsable;
  }

  Future<bool> _cameraPermissionAvailable() async {
    final camera = await _permissionReadiness.status(AppPermissionKind.camera);
    final granted = camera.isUsable;
    _cameraPermissionDenied = !granted;
    if (!granted) {
      _cameraIssue =
          'Camera access is off. The call will continue with audio only.';
    }
    return granted;
  }

  void _handleRoomChanged() {
    notifyListeners();
  }

  void _setStatus(VoiceCallStatus value) {
    _status = value;
    notifyListeners();
  }

  String _displayName(String? name, String identity) {
    final cleanName = name?.trim();
    if (cleanName != null && cleanName.isNotEmpty) return cleanName;
    return identity;
  }

  @visibleForTesting
  String friendlyErrorForTesting(Object error) => _friendlyError(error);

  String _friendlyError(Object error) {
    if (error is VoiceCleanupInProgressException) {
      return 'The previous call is still closing. Wait a moment before trying again.';
    }
    if (error is VoicePermissionRequiredException) {
      return switch (error.permission) {
        AppPermissionKind.microphone =>
          'Microphone access is needed to speak. Enable it and try again.',
        AppPermissionKind.camera =>
          'Camera access is off. The call can continue with audio only.',
        AppPermissionKind.notifications =>
          'A required permission is unavailable. Check Settings and try again.',
      };
    }
    return friendlyErrorMessage(
      error,
      fallback: 'Live audio is unavailable right now. Try again.',
    );
  }

  @override
  void dispose() {
    unawaited(_disposeRoom().catchError((_) {}));
    super.dispose();
  }
}

class VoiceParticipantViewData {
  const VoiceParticipantViewData({
    required this.identity,
    required this.displayName,
    required this.isLocal,
    required this.isSpeaking,
    required this.audioLevel,
    required this.isMuted,
  });

  final String identity;
  final String displayName;
  final bool isLocal;
  final bool isSpeaking;
  final double audioLevel;
  final bool isMuted;

  bool get isShouting => isSpeaking && audioLevel >= .58;
}
