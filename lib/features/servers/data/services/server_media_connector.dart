import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// What the provider link is doing right now. `connected` is reported only
/// from the provider's own connection state — never from a token having
/// been issued — so the dock's "połączono" is true when it is shown.
enum ServerMediaLinkState { connecting, connected, reconnecting, disconnected }

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

  /// True while this device is publishing its own screen.
  bool get isScreenShareEnabled;

  /// True while every audio track this device receives is silenced locally.
  ///
  /// This is the board's `Słuchawki` control and it is purely local: nothing
  /// is written, nobody else is told, and it is not the moderator mute of
  /// contract G5 (which has no readable state and is therefore not drawn).
  bool get isDeafened;

  /// Explicit capture control. Never called by a connect; the person
  /// presses the microphone control themselves.
  Future<void> setMicrophoneEnabled(bool enabled);

  /// Silences (or restores) every received audio track on this device only.
  Future<void> setDeafened(bool deafened);

  /// Starts or stops publishing this device's screen.
  ///
  /// Explicit, like the microphone: nothing here is called by a connect. The
  /// caller must have checked both halves of contract decision D first — the
  /// grant (`deriveSessionGrant` gives `screen_share` only to a meeting's
  /// host) and the platform capability — because a platform that cannot
  /// capture a screen fails inside the provider rather than here.
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

class _LiveKitServerMediaLink extends ServerMediaLink {
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
      });
  }

  final lk.Room _room;
  late final lk.EventsListener<lk.RoomEvent> _events;
  ServerMediaLinkState _state = ServerMediaLinkState.connecting;
  List<ServerMediaParticipant> _participants = const [];
  bool _released = false;
  bool _deafened = false;

  @override
  ServerMediaLinkState get state => _state;

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
  Future<void> setScreenShareEnabled(bool enabled) async {
    final local = _room.localParticipant;
    if (_released || local == null) {
      throw StateError('The media session is not connected.');
    }
    await local.setScreenShareEnabled(enabled);
    _sync();
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
    screenShareTrack: _videoTrack(
      participant,
      lk.TrackSource.screenShareVideo,
    ),
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
    final raw = participant.metadata;
    if (raw == null || raw.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['uid'] != participant.identity) return null;
    final role = decoded['role'];
    return role == 'host' || role == 'guest' || role == 'listener'
        ? role as String
        : null;
  }

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
    notifyListeners();
  }
}
