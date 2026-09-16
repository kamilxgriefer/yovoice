import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// What the provider link is doing right now. `connected` is reported only
/// from the provider's own connection state — never from a token having
/// been issued — so the dock's "połączono" is true when it is shown.
enum ServerMediaLinkState { connecting, connected, reconnecting, disconnected }

/// Immutable authority carried by a LiveKit participant token.
///
/// `canUpdateOwnMetadata` is disabled by the backend, so a parsed binding is a
/// provider-authenticated statement about the sender rather than client input.
/// Consumers must still compare every field with the room/session they expect.
@immutable
class ServerMediaSessionBinding {
  const ServerMediaSessionBinding({
    required this.serverId,
    required this.channelId,
    required this.roomId,
    required this.sessionId,
    required this.participantIdentity,
    required this.sessionRole,
  });

  final String serverId;
  final String channelId;
  final String roomId;
  final String sessionId;
  final String participantIdentity;
  final String sessionRole;

  bool matchesGeneration(ServerMediaSessionBinding other) =>
      serverId == other.serverId &&
      channelId == other.channelId &&
      roomId == other.roomId &&
      sessionId == other.sessionId;
}

/// One provider-authenticated data-channel packet. The sender binding is read
/// from server-signed participant metadata, never from the payload itself.
@immutable
class ServerMediaDataPacket {
  ServerMediaDataPacket({
    required this.topic,
    required List<int> data,
    required this.sender,
    required this.senderConnectionId,
  }) : data = Uint8List.fromList(data);

  final String topic;
  final Uint8List data;
  final ServerMediaSessionBinding sender;

  /// LiveKit's server-assigned participant SID. It changes when the same
  /// account reconnects as a new participant and safely scopes packet order.
  final String senderConnectionId;
}

/// Optional data-channel capability of a media link. Keeping it separate from
/// [ServerMediaLink] lets audio/video-only test doubles and future providers
/// fail closed instead of pretending realtime collaboration exists.
abstract interface class ServerMediaDataLink {
  ServerMediaSessionBinding? get localSessionBinding;
  Stream<ServerMediaDataPacket> get dataPackets;

  Future<void> publishData(
    List<int> data, {
    required String topic,
    required bool reliable,
  });
}

/// Somebody the provider says is in the session. This is the only honest
/// in-session presence source (contract G3): it exists after joining and
/// nowhere before.
@immutable
class ServerMediaParticipant {
  const ServerMediaParticipant({
    required this.identity,
    required this.name,
    required this.isLocal,
    this.isSpeaking = false,
    this.isMicrophoneEnabled = false,
    this.sessionRole,
    this.cameraTrack,
    this.screenShareTrack,
  });

  /// The Firebase uid, which the server signs as the token identity.
  final String identity;
  final String name;
  final bool isLocal;
  final bool isSpeaking;
  final bool isMicrophoneEnabled;

  /// `host | guest | listener` for this generation, or null when the provider
  /// reports nothing usable.
  ///
  /// This is **not** the participant document of contract gap G3, which stays
  /// unreadable. It is the role the server itself signed into this person's
  /// access token — `session_livekit.js mintToken()` writes
  /// `metadata: {uid, role, serverId, channelId, roomId, sessionId}` and the
  /// same grant sets `canUpdateOwnMetadata: false`, so no client can alter or
  /// forge it. It exists only inside a joined generation and creates no
  /// pre-join presence of any kind.
  final String? sessionRole;

  /// Board 05 separates the stage from the audience. A podcast stage is
  /// `broadcast/audio`, where `deriveSessionGrant` gives a publisher the
  /// microphone source and a listener none, so the signed role is exactly
  /// that separation — never a guess from whether somebody is talking.
  bool get isStageRole => sessionRole == 'host' || sessionRole == 'guest';

  /// This person's camera track, present only while the provider reports it
  /// published, subscribed and unmuted. Null otherwise — a stage with no
  /// camera shows that it has none; nothing stands in for a picture that is
  /// not being sent (board 02's 16:9 scene).
  final lk.VideoTrack? cameraTrack;

  bool get hasCamera => cameraTrack != null;

  /// The screen this person is actually sending right now, read exactly like
  /// [cameraTrack] — published, subscribed and unmuted, or null.
  ///
  /// Receiving a share is an ordinary remote video track and works on every
  /// platform (contract §3); *starting* one does not, which is why
  /// [ServerMediaLink.setScreenShareEnabled] is gated by a platform
  /// capability query (contract decision D) while this is not gated at all.
  final lk.VideoTrack? screenShareTrack;

  bool get isSharingScreen => screenShareTrack != null;
}

/// One connected media session. Listeners are notified on every state,
/// roster or speaking change.
abstract class ServerMediaLink extends ChangeNotifier {
  ServerMediaLinkState get state;
  List<ServerMediaParticipant> get participants;
  bool get isMicrophoneEnabled;

  /// True only while this device is publishing its own camera.
  bool get isCameraEnabled;

  /// True while this device is publishing its own screen.
  bool get isScreenShareEnabled;

  /// True while every audio track this device receives is silenced locally.
  ///
  /// This is the board's `Słuchawki` control and it is purely local: nothing
  /// is written, nobody else is told, and it is not the moderator mute of
  /// contract G5. Stage controls send that explicit server command without
  /// deriving its state from this local playback flag.
  bool get isDeafened;

  /// Explicit capture control. Never called by a connect; the person
  /// presses the microphone control themselves.
  Future<void> setMicrophoneEnabled(bool enabled);

  /// Starts or stops publishing this device's camera. Capture is requested
  /// only from this explicit action; connecting never enables it.
  Future<void> setCameraEnabled(bool enabled);

  /// Silences (or restores) every received audio track on this device only.
  Future<void> setDeafened(bool deafened);

  /// Starts or stops publishing this device's screen.
  ///
  /// Explicit, like the microphone: nothing here is called by a connect. The
  /// caller must have checked both halves of contract decision D first — the
  /// grant (`deriveSessionGrant` gives `screen_share` to the host of a meeting
  /// or Community video stage) and the platform capability — because a
  /// platform that cannot capture a screen fails inside the provider rather
  /// than here.
  Future<void> setScreenShareEnabled(bool enabled);

  /// Stops local capture, leaves the provider room and releases it. Safe to
  /// call twice.
  Future<void> disconnect();
}

/// Opens a provider room from a server-issued connection receipt. The
/// production implementation wraps `livekit_client`; tests substitute one
/// that never touches native audio.
abstract interface class ServerMediaConnector {
  Future<ServerMediaLink> connect({
    required String serverUrl,
    required String token,
  });
}

/// Completes an enable action only after the provider exposes a live local
/// screen publication. This guards the iOS SDK path where a request can
/// resolve after merely asking for a missing Broadcast Extension.
@visibleForTesting
Future<void> publishServerScreenShareAndVerify({
  required Future<void> Function() publish,
  required bool Function() publicationAvailable,
  required Future<void> Function() rollback,
}) async {
  await publish();
  if (publicationAvailable()) return;
  await rollback();
  throw StateError('LiveKit did not publish the screen-share track.');
}

typedef ServerAndroidScreenServiceInvoker = Future<bool> Function(bool active);

/// Serializes the Android foreground-service type with the provider's actual
/// screen publication. The provider can unpublish asynchronously when the
/// system revokes MediaProjection; in that case the `mediaProjection` type
/// must disappear even though the voice service itself stays alive.
@visibleForTesting
final class ServerAndroidScreenShareServiceState {
  ServerAndroidScreenShareServiceState({required this.invoke});

  final ServerAndroidScreenServiceInvoker invoke;
  Future<void> _tail = Future<void>.value();
  int _generation = 0;
  bool _possiblyActive = false;
  bool _retired = false;

  @visibleForTesting
  bool get possiblyActive => _possiblyActive;

  @visibleForTesting
  Future<void> get settled => _tail;

  Future<bool> activate() async {
    if (_retired) return false;
    final generation = ++_generation;
    _possiblyActive = true;
    final accepted = await _enqueue(true);
    if (generation != _generation) return false;
    if (!accepted) _possiblyActive = false;
    return accepted;
  }

  Future<void> deactivate() async {
    if (_retired || !_possiblyActive) return;
    _generation++;
    _possiblyActive = false;
    await _enqueue(false);
  }

  /// Permanently prevents this link from issuing another foreground-service
  /// update. The session controller owns the terminal service STOP; allowing
  /// a queued `false` update to run afterwards would start the Android service
  /// again just to remove a type from a session that no longer exists.
  Future<void> retire() async {
    if (!_retired) {
      _retired = true;
      _generation++;
      _possiblyActive = false;
    }
    await _tail;
  }

  void reconcile({
    required bool publicationAvailable,
    required bool transitionInFlight,
  }) {
    if (transitionInFlight || publicationAvailable || !_possiblyActive) return;
    unawaited(deactivate());
  }

  Future<bool> _enqueue(bool active) {
    final completion = Completer<bool>();
    _tail = _tail.then((_) async {
      if (_retired) {
        completion.complete(false);
        return;
      }
      try {
        completion.complete(await invoke(active));
      } catch (_) {
        completion.complete(false);
      }
    });
    return completion.future;
  }
}

/// LiveKit-backed link. Connects with no local tracks: microphone capture
/// starts only through [ServerMediaLink.setMicrophoneEnabled].
class LiveKitServerMediaConnector implements ServerMediaConnector {
  const LiveKitServerMediaConnector({
    this.connectionTimeout = const Duration(seconds: 20),
  });

  final Duration connectionTimeout;

  @override
  Future<ServerMediaLink> connect({
    required String serverUrl,
    required String token,
  }) async {
    final room = lk.Room(
      roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
    );
    final link = _LiveKitServerMediaLink(room);
    try {
      await room.connect(serverUrl, token).timeout(connectionTimeout);
    } catch (_) {
      await link.disconnect();
      rethrow;
    }
    link._sync();
    return link;
  }
}

class _LiveKitServerMediaLink extends ServerMediaLink
    implements ServerMediaDataLink {
  _LiveKitServerMediaLink(this._room) {
    _events = _room.createListener()
      ..on<lk.RoomReconnectingEvent>((_) => _sync())
      ..on<lk.RoomReconnectedEvent>((_) => _sync())
      ..on<lk.RoomDisconnectedEvent>((_) => _sync())
      ..on<lk.ParticipantConnectedEvent>((_) => _sync())
      ..on<lk.ParticipantDisconnectedEvent>((_) => _sync())
      ..on<lk.ActiveSpeakersChangedEvent>((_) => _sync())
      ..on<lk.TrackMutedEvent>((_) => _sync())
      ..on<lk.TrackUnmutedEvent>((_) => _sync())
      ..on<lk.LocalTrackPublishedEvent>((_) => _sync())
      ..on<lk.LocalTrackUnpublishedEvent>((_) => _sync())
      ..on<lk.ParticipantNameUpdatedEvent>((_) => _sync())
      // The signed session role travels in the participant's metadata, so a
      // promotion or demotion the server applied has to reach the scene.
      ..on<lk.ParticipantMetadataUpdatedEvent>((_) => _sync())
      // Video publications change the scene without changing the roster, so
      // the stage has to be told about them too.
      ..on<lk.TrackPublishedEvent>((_) => _sync())
      ..on<lk.TrackUnpublishedEvent>((_) => _sync())
      ..on<lk.TrackUnsubscribedEvent>((_) => _sync())
      // A track that arrives while listening is off must arrive silent, not
      // play once and then be caught by the next toggle.
      ..on<lk.TrackSubscribedEvent>((_) {
        unawaited(_applyDeafened());
        _sync();
      })
      ..on<lk.DataReceivedEvent>(_onDataReceived);
  }

  final lk.Room _room;
  late final lk.EventsListener<lk.RoomEvent> _events;
  ServerMediaLinkState _state = ServerMediaLinkState.connecting;
  List<ServerMediaParticipant> _participants = const [];
  bool _released = false;
  bool _deafened = false;
  bool _screenShareTransitionInFlight = false;
  final StreamController<ServerMediaDataPacket> _dataPackets =
      StreamController<ServerMediaDataPacket>.broadcast(sync: true);
  static const _voiceSessionChannel = MethodChannel(
    'app.yo_voice/voice_session',
  );
  late final ServerAndroidScreenShareServiceState _androidScreenService =
      ServerAndroidScreenShareServiceState(invoke: _invokeAndroidScreenService);

  @override
  ServerMediaLinkState get state => _state;

  @override
  ServerMediaSessionBinding? get localSessionBinding {
    final local = _room.localParticipant;
    return local == null ? null : _sessionBinding(local);
  }

  @override
  Stream<ServerMediaDataPacket> get dataPackets => _dataPackets.stream;

  @override
  Future<void> publishData(
    List<int> data, {
    required String topic,
    required bool reliable,
  }) async {
    final local = _room.localParticipant;
    if (_released ||
        _state != ServerMediaLinkState.connected ||
        local == null ||
        localSessionBinding == null) {
      throw StateError('The media data session is not connected.');
    }
    await local.publishData(data, reliable: reliable, topic: topic);
  }

  void _onDataReceived(lk.DataReceivedEvent event) {
    if (_released || _dataPackets.isClosed) return;
    final participant = event.participant;
    final topic = event.topic;
    if (participant == null || topic == null || topic.isEmpty) return;
    final sender = _sessionBinding(participant);
    if (sender == null) return;
    final senderConnectionId = _safeMediaResourceId(participant.sid);
    if (senderConnectionId == null) return;
    _dataPackets.add(
      ServerMediaDataPacket(
        topic: topic,
        data: event.data,
        sender: sender,
        senderConnectionId: senderConnectionId,
      ),
    );
  }

  @override
  List<ServerMediaParticipant> get participants => _participants;

  @override
  bool get isMicrophoneEnabled {
    final local = _room.localParticipant;
    return local != null && !local.isMuted;
  }

  @override
  bool get isScreenShareEnabled {
    final local = _room.localParticipant;
    if (local == null) return false;
    final publication = local.getTrackPublicationBySource(
      lk.TrackSource.screenShareVideo,
    );
    return publication != null && !publication.muted;
  }

  @override
  bool get isCameraEnabled {
    final local = _room.localParticipant;
    if (local == null) return false;
    final publication = local.getTrackPublicationBySource(
      lk.TrackSource.camera,
    );
    return publication != null && !publication.muted;
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    final local = _room.localParticipant;
    if (_released || local == null) {
      throw StateError('The media session is not connected.');
    }
    await local.setCameraEnabled(enabled);
    _sync();
  }

  @override
  Future<void> setScreenShareEnabled(bool enabled) async {
    final local = _room.localParticipant;
    if (_released || local == null) {
      throw StateError('The media session is not connected.');
    }
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    lk.LocalVideoTrack? explicitlyCreatedTrack;
    if (android) _screenShareTransitionInFlight = true;
    try {
      if (enabled && android) {
        // Android separates consent from capture. LiveKit's documented order
        // is MediaProjection consent, a foreground service carrying the
        // `mediaProjection` type, then publication.
        // ignore: experimental_member_use
        final granted = await lk.Hardware.instance.requestCapturePermission();
        if (!granted) {
          throw StateError('Screen capture permission was not granted.');
        }
        if (!await _androidScreenService.activate()) {
          throw StateError('The Android screen-share service could not start.');
        }
      }
      try {
        if (enabled) {
          await publishServerScreenShareAndVerify(
            publish: () async {
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
                // YO Voice has no ReplayKit Broadcast Upload Extension, so
                // publish an explicit in-app capture track on iOS.
                final track = await lk.LocalVideoTrack.createScreenShareTrack(
                  const lk.ScreenShareCaptureOptions(
                    useiOSBroadcastExtension: false,
                  ),
                );
                explicitlyCreatedTrack = track;
                try {
                  await local.publishVideoTrack(track);
                } catch (_) {
                  await track.stop();
                  explicitlyCreatedTrack = null;
                  rethrow;
                }
              } else {
                await local.setScreenShareEnabled(
                  true,
                  captureScreenAudio: true,
                );
              }
            },
            publicationAvailable: () {
              final publication = local.getTrackPublicationBySource(
                lk.TrackSource.screenShareVideo,
              );
              return publication != null && !publication.muted;
            },
            rollback: () async {
              try {
                await local.setScreenShareEnabled(false);
              } catch (_) {}
              final track = explicitlyCreatedTrack;
              if (track != null) {
                try {
                  await track.stop();
                } catch (_) {}
              }
            },
          );
        } else {
          await local.setScreenShareEnabled(false);
        }
      } catch (_) {
        if (enabled && android) await _androidScreenService.deactivate();
        rethrow;
      }
      if (!enabled && android) await _androidScreenService.deactivate();
      _sync();
    } finally {
      if (android) {
        _screenShareTransitionInFlight = false;
        _androidScreenService.reconcile(
          publicationAvailable: isScreenShareEnabled,
          transitionInFlight: false,
        );
      }
    }
  }

  static Future<bool> _invokeAndroidScreenService(bool active) async {
    try {
      return await _voiceSessionChannel.invokeMethod<bool>(
            'setScreenShareActive',
            {'active': active},
          ) ==
          true;
    } catch (_) {
      // Stopping the LiveKit track is the privacy boundary. Restoring the
      // ongoing-service type is best effort and the service itself also ends
      // when the media session disconnects.
      return false;
    }
  }

  @override
  bool get isDeafened => _deafened;

  @override
  Future<void> setDeafened(bool deafened) async {
    if (_released || _deafened == deafened) return;
    _deafened = deafened;
    await _applyDeafened();
    _sync();
  }

  /// Local output only: `Track.disable()` sets `mediaStreamTrack.enabled`
  /// to false on this device, so the person stops hearing the room without
  /// anything being published, written or signalled about them.
  Future<void> _applyDeafened() async {
    if (_released) return;
    for (final participant in _room.remoteParticipants.values) {
      for (final publication in participant.audioTrackPublications) {
        final track = publication.track;
        if (track == null) continue;
        try {
          if (_deafened) {
            await track.disable();
          } else {
            await track.enable();
          }
        } catch (_) {
          // One track refusing must not leave the rest in a mixed state;
          // the remaining tracks are still applied.
        }
      }
    }
  }

  void _sync() {
    if (_released) return;
    _state = switch (_room.connectionState) {
      lk.ConnectionState.connected => ServerMediaLinkState.connected,
      lk.ConnectionState.reconnecting => ServerMediaLinkState.reconnecting,
      lk.ConnectionState.connecting => ServerMediaLinkState.connecting,
      lk.ConnectionState.disconnected => ServerMediaLinkState.disconnected,
    };
    final local = _room.localParticipant;
    _participants = [
      if (local != null) _describe(local, isLocal: true),
      for (final remote in _room.remoteParticipants.values)
        _describe(remote, isLocal: false),
    ];
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _androidScreenService.reconcile(
        publicationAvailable: isScreenShareEnabled,
        transitionInFlight: _screenShareTransitionInFlight,
      );
    }
    notifyListeners();
  }

  static ServerMediaParticipant _describe(
    lk.Participant<dynamic> participant, {
    required bool isLocal,
  }) => ServerMediaParticipant(
    identity: participant.identity,
    name: participant.name.isEmpty ? participant.identity : participant.name,
    isLocal: isLocal,
    isSpeaking: participant.isSpeaking,
    isMicrophoneEnabled: !participant.isMuted,
    sessionRole: _sessionRole(participant),
    cameraTrack: _videoTrack(participant, lk.TrackSource.camera),
    screenShareTrack: _videoTrack(participant, lk.TrackSource.screenShareVideo),
  );

  /// The role the server signed into this participant's own token.
  ///
  /// Read strictly: unparseable metadata, metadata signed for a different
  /// identity, or a role outside the three the backend assigns all resolve to
  /// null, and a null role is never treated as authority anywhere. Room
  /// membership already binds the generation — the `room` grant admits a
  /// token only to `canonicalLiveKitRoomName(serverId, channelId, sessionId)`
  /// — so the identity check is the only binding left to verify here.
  static String? _sessionRole(lk.Participant<dynamic> participant) {
    return _sessionBinding(participant)?.sessionRole;
  }

  static ServerMediaSessionBinding? _sessionBinding(
    lk.Participant<dynamic> participant,
  ) => decodeServerMediaSessionBinding(
    rawMetadata: participant.metadata,
    participantIdentity: participant.identity,
  );

  /// The picture this person is actually sending right now from [source].
  ///
  /// A publication that is muted, unsubscribed or carries no track yet is
  /// deliberately not a picture: the scene must be able to say "no camera"
  /// or "nobody is sharing" rather than draw an empty renderer. Camera and
  /// screen share are read identically and stay separate sources — board 04
  /// shows a shared screen and the people's cameras at the same time.
  static lk.VideoTrack? _videoTrack(
    lk.Participant<dynamic> participant,
    lk.TrackSource source,
  ) {
    for (final publication in participant.videoTrackPublications) {
      if (publication.source != source) continue;
      if (publication.muted) continue;
      final track = publication.track;
      if (track is lk.VideoTrack) return track;
    }
    return null;
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    final local = _room.localParticipant;
    if (_released || local == null) {
      throw StateError('The media session is not connected.');
    }
    await local.setMicrophoneEnabled(enabled);
    _sync();
  }

  @override
  Future<void> disconnect() async {
    if (_released) return;
    _released = true;
    await _events.dispose();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // The controller owns the terminal voice-service STOP. Suppress any
      // queued type-only update so it cannot restart that stopped service.
      await _androidScreenService.retire();
    }
    final local = _room.localParticipant;
    if (local != null && !local.isMuted) {
      // Capture stops first, so a slow signalling teardown can never keep a
      // microphone open behind a dock that already says "disconnected".
      try {
        await local.setMicrophoneEnabled(false);
      } catch (_) {
        // The room disposal below tears the track down regardless.
      }
    }
    if (local != null && isCameraEnabled) {
      // Camera capture can survive a slow signalling teardown just like
      // microphone capture, so release it before the dock disappears.
      try {
        await local.setCameraEnabled(false);
      } catch (_) {
        // The room disposal below tears the track down regardless.
      }
    }
    if (local != null && isScreenShareEnabled) {
      // A screen capture outlives its room on some platforms; it is released
      // for the same reason the microphone is, and before the room goes.
      try {
        await local.setScreenShareEnabled(false);
      } catch (_) {
        // The room disposal below tears the track down regardless.
      }
    }
    try {
      // Room.disconnect can wait on a signalling event; bound it so leaving
      // is never blocked by the provider.
      await _room.disconnect().timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      );
    } catch (_) {
      // Disposal below releases the native resources either way.
    }
    try {
      await _room.dispose();
    } catch (_) {
      // Nothing further can be released.
    }
    _state = ServerMediaLinkState.disconnected;
    _participants = const [];
    _deafened = false;
    await _dataPackets.close();
    notifyListeners();
  }
}

const _sessionMetadataKeys = <String>{
  'uid',
  'role',
  'serverId',
  'channelId',
  'roomId',
  'sessionId',
};

/// Decodes the exact authority metadata signed into a LiveKit token.
///
/// Firebase UIDs are opaque: unlike server/channel/session resource IDs they
/// may contain spaces and Unicode, and must never be trimmed, normalized or
/// case-folded. This deliberately mirrors `isValidOpaqueUid` in the backend.
@visibleForTesting
ServerMediaSessionBinding? decodeServerMediaSessionBinding({
  required String? rawMetadata,
  required String participantIdentity,
}) {
  final raw = rawMetadata;
  if (raw == null || raw.isEmpty || raw.length > 1024) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! Map ||
      decoded.keys.any((key) => key is! String) ||
      !setEquals(decoded.keys.toSet(), _sessionMetadataKeys)) {
    return null;
  }
  final uid = _opaqueServerParticipantIdentity(decoded['uid']);
  final serverId = _safeMediaResourceId(decoded['serverId']);
  final channelId = _safeMediaResourceId(decoded['channelId']);
  final roomId = _safeMediaResourceId(decoded['roomId']);
  final sessionId = _safeMediaResourceId(decoded['sessionId']);
  final role = decoded['role'];
  if (uid == null ||
      uid != participantIdentity ||
      serverId == null ||
      channelId == null ||
      roomId == null ||
      sessionId == null ||
      (role != 'host' && role != 'guest' && role != 'listener')) {
    return null;
  }
  return ServerMediaSessionBinding(
    serverId: serverId,
    channelId: channelId,
    roomId: roomId,
    sessionId: sessionId,
    participantIdentity: uid,
    sessionRole: role as String,
  );
}

const _firebaseUidMaximumLength = 128;
final _safeMediaResourceIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// Production validator for a provider participant identity: it mirrors the
/// backend's opaque Firebase uid check and also guards whiteboard live-packet
/// senders, so it is shared library API rather than a test-only seam.
bool isValidOpaqueServerParticipantIdentity(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.length > _firebaseUidMaximumLength ||
      value.contains('/')) {
    return false;
  }
  for (final codeUnit in value.codeUnits) {
    if (codeUnit <= 0x1f || (codeUnit >= 0x7f && codeUnit <= 0x9f)) {
      return false;
    }
  }
  return true;
}

String? _opaqueServerParticipantIdentity(Object? value) =>
    isValidOpaqueServerParticipantIdentity(value) ? value! as String : null;

String? _safeMediaResourceId(Object? value) =>
    value is String && _safeMediaResourceIdPattern.hasMatch(value)
    ? value
    : null;
