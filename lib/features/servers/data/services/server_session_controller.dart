import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yovoice/core/audio/realtime_audio_session_registry.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';

import '../models/server.dart';
import '../models/server_channel.dart';
import '../models/server_session.dart';
import '../models/server_type.dart';
import '../models/server_whiteboard.dart';
import 'server_media_connector.dart';
import 'server_screen_share_capability.dart';
import 'server_service.dart';
import 'server_voice_device.dart';
import 'server_whiteboard_live_transport.dart';

/// Where one explicit join stands. Only [connected] and [reconnecting] mean
/// a provider link exists; everything before them is the reviewed token
/// path, and [failed] / [blocked] are visible, dismissable outcomes.
enum ServerSessionPhase {
  idle,

  /// Another voice session (a 1:1 call or a legacy room) owns the device's
  /// audio; joining would start a second native session.
  blocked,
  starting,
  authorizing,
  connecting,
  connected,
  reconnecting,
  leaving,
  failed,
}

/// Thrown into [ServerSessionController.error] when the provider dropped an
/// established link, so the surface can say "połączenie przerwane" instead
/// of a generic failure.
class ServerSessionDisconnected implements Exception {
  const ServerSessionDisconnected();
}

/// One person's participation in one media channel of one server.
///
/// The join is explicit and goes through the reviewed path only:
/// `startServerChannelSessionV1` when the channel has no live generation,
/// `createServerChannelTokenV1` for the generation, then the provider link.
/// Nothing here opens the microphone: [setMicrophoneEnabled] is the only
/// capture call, and it is bound to a control the person presses.
class ServerSessionController extends ChangeNotifier
    implements ServerWhiteboardLiveTransport {
  ServerSessionController({
    required ServerRepository repository,
    ServerMediaConnector? connector,
    bool Function()? anotherVoiceSessionActive,
    ServerScreenShareCapability? screenShare,
    ServerVoiceDevice? device,
    Listenable? otherVoiceOwner,
    RealtimeAudioSessionRegistry? realtimeAudioSessions,
  }) : _otherVoiceOwnerOverride = otherVoiceOwner,
       _repository = repository,
       _connector = connector ?? const LiveKitServerMediaConnector(),
       _anotherVoiceSessionActive =
           anotherVoiceSessionActive ?? _legacyVoiceSessionActive,
       _device = device ?? serverVoiceDevice(),
       _realtimeAudioSessions =
           realtimeAudioSessions ?? RealtimeAudioSessionRegistry.instance,
       screenShare = screenShare ?? serverScreenShareCapability();

  final ServerRepository _repository;
  final ServerMediaConnector _connector;
  final bool Function() _anotherVoiceSessionActive;

  /// The speaker route and the Android keep-alive service. Neither is owned by
  /// this slice; both have to be asked for, per session, or a conversation
  /// plays out of the earpiece and dies when the app is backgrounded.
  final ServerVoiceDevice _device;
  final RealtimeAudioSessionRegistry _realtimeAudioSessions;
  final Object _realtimeAudioOwner = Object();
  RealtimeAudioSessionLease? _realtimeAudioLease;
  int _pendingJoinOperations = 0;
  int _pendingLinkCleanups = 0;

  /// The device's other voice owner as a *notifier*, resolved lazily so that
  /// merely constructing this controller never builds the legacy singleton.
  final Listenable? _otherVoiceOwnerOverride;
  Listenable get _otherVoiceOwner =>
      _otherVoiceOwnerOverride ?? VoiceCallService.instance;

  /// What this platform can do about publishing a screen (contract decision
  /// D). Read by the meeting surfaces so the control is labelled with the
  /// real reason instead of being hidden.
  final ServerScreenShareCapability screenShare;

  ServerSessionPhase _phase = ServerSessionPhase.idle;
  Server? _server;
  ServerChannel? _channel;
  ServerSessionConnection? _connection;
  ServerMediaLink? _link;
  ServerWhiteboardLiveDataPlane? _whiteboardDataPlane;
  StreamSubscription<List<ServerWhiteboardLiveDraft>>?
  _whiteboardDataSubscription;
  final StreamController<List<ServerWhiteboardLiveDraft>>
  _whiteboardLiveDraftController =
      StreamController<List<ServerWhiteboardLiveDraft>>.broadcast(sync: true);
  int _whiteboardDataEpoch = 0;
  Object? _error;
  bool _microphoneBusy = false;
  bool _headphonesBusy = false;
  bool _cameraBusy = false;
  Object? _cameraError;
  bool _screenShareBusy = false;
  Object? _screenShareError;
  Object? _endError;
  String? _endRequestId;
  bool _endBusy = false;

  /// The last failure a microphone or headphones press produced.
  ///
  /// These two controls stay reachable through a reconnect on purpose — a
  /// reconnect does not release the capture, so refusing a mute for the
  /// length of that window is the one moment the person most wants it. The
  /// provider link really can refuse in that window (it raises
  /// `StateError('The media session is not connected.')` once the link is
  /// released or the local participant is gone, and forwards a publish
  /// failure unchanged), and a rejected future that nobody catches is a
  /// control that looks live and silently does nothing. Cleared by the next
  /// attempt and by leaving.
  Object? _privacyError;
  int _epoch = 0;
  bool _disposed = false;

  /// The reviewed callable path this session was joined through. Surfaces
  /// that act on the *generation* (board 02's `Poproś o głos`) reach it from
  /// here rather than opening a second path of their own.
  ServerRepository get repository => _repository;

  ServerSessionPhase get phase => _phase;
  Server? get server => _server;
  ServerChannel? get channel => _channel;
  ServerSessionConnection? get connection => _connection;
  Object? get error => _error;
  bool get isActive => _phase != ServerSessionPhase.idle;

  /// True only while the provider reports an established link.
  bool get isConnected => _phase == ServerSessionPhase.connected;

  /// True while a provider link exists at all — established OR re-establishing
  /// itself.
  ///
  /// The distinction matters for exactly one class of control: the local
  /// privacy ones. A reconnect does not release the capture, so the person is
  /// still publishing while the transport is down; refusing a mute for the
  /// length of that window (and hiding the control in the dock while doing
  /// it) is the one moment they are most likely to want it. Everything that
  /// needs a working signalling channel — starting a screen share, acting on
  /// the generation — stays on [isConnected].
  bool get isLive =>
      _phase == ServerSessionPhase.connected ||
      _phase == ServerSessionPhase.reconnecting;
  bool get isJoining =>
      _phase == ServerSessionPhase.starting ||
      _phase == ServerSessionPhase.authorizing ||
      _phase == ServerSessionPhase.connecting;
  bool get canPublish => _connection?.canPublishMicrophone ?? false;
  bool get isMicrophoneEnabled => _link?.isMicrophoneEnabled ?? false;
  bool get microphoneBusy => _microphoneBusy;

  /// The board's `Słuchawki` state: local output only, never a moderator
  /// mute (G5 has no client contract, so no such control is drawn).
  bool get isDeafened => _link?.isDeafened ?? false;
  bool get headphonesBusy => _headphonesBusy;
  List<ServerMediaParticipant> get participants =>
      _link?.participants ?? const [];

  /// The camera half of the signed meeting grant.
  bool get canPublishCamera => _connection?.canPublishCamera ?? false;
  bool get isCameraEnabled => _link?.isCameraEnabled ?? false;
  bool get cameraBusy => _cameraBusy;
  Object? get cameraError => _cameraError;

  /// True only when both halves of contract decision D hold: the server
  /// signed `screen_share` into this token (meeting host only) and this
  /// platform can actually start a capture.
  bool get canShareScreen =>
      isConnected &&
      (_connection?.canPublishScreenShare ?? false) &&
      screenShare.canStartShare;

  bool get isScreenShareEnabled => _link?.isScreenShareEnabled ?? false;
  bool get screenShareBusy => _screenShareBusy;

  /// The last failure a share attempt produced, cleared by the next attempt.
  Object? get screenShareError => _screenShareError;

  /// The last failure a microphone or headphones press produced, cleared by
  /// the next attempt. The dock renders it in place of the phase line, so a
  /// refused mute is said out loud rather than reverting in silence.
  Object? get privacyError => _privacyError;

  /// The generation starter receives the signed `host` role. Moderators can
  /// also end a generation, but that extra server-role authority is supplied
  /// by the shell when it draws the action and is re-proved by the callable.
  bool get isSessionHost => _connection?.sessionRole == 'host';
  bool get endBusy => _endBusy;
  Object? get endError => _endError;

  bool isIn(String channelId) => isActive && _channel?.id == channelId;

  @override
  bool isAvailableFor(String serverId) =>
      isConnected &&
      _server?.id == serverId &&
      _whiteboardDataPlane?.isActive == true;

  @override
  Stream<List<ServerWhiteboardLiveDraft>> get whiteboardLiveDrafts =>
      _whiteboardLiveDraftController.stream;

  @override
  Future<bool> publishWhiteboardLiveDraft({
    required String serverId,
    required String channelId,
    required String draftId,
    required int generation,
    required List<ServerWhiteboardPoint> points,
    required ServerWhiteboardColor color,
    required int lineWidth,
  }) async {
    final plane = _whiteboardDataPlane;
    if (!isAvailableFor(serverId) || plane == null) return false;
    return plane.publishDraft(
      serverId: serverId,
      channelId: channelId,
      draftId: draftId,
      generation: generation,
      points: points,
      color: color,
      lineWidth: lineWidth,
    );
  }

  @override
  Future<bool> clearWhiteboardLiveDraft({
    required String serverId,
    required String channelId,
    required String draftId,
    required int generation,
  }) async {
    final plane = _whiteboardDataPlane;
    if (!isAvailableFor(serverId) || plane == null) return false;
    return plane.clearDraft(
      serverId: serverId,
      channelId: channelId,
      draftId: draftId,
      generation: generation,
    );
  }

  /// The legacy coordinator is the device's other voice owner. Joining while
  /// it is busy would run two native sessions; it is asked, never bypassed.
  static bool _legacyVoiceSessionActive() {
    final voice = VoiceCallService.instance;
    return voice.isBusy || voice.isConnected || voice.isCleanupInProgress;
  }

  Future<void> join(Server server, ServerChannel target) async {
    if (_disposed || !target.kind.isMedia) return;
    if (isActive && _channel?.id == target.id && !_isTerminal) return;
    if (isActive && !_isTerminal) {
      // Moving to another media channel ends the previous conversation
      // properly before anything new is requested.
      await leave();
    }
    final epoch = ++_epoch;
    _server = server;
    _channel = target;
    _connection = null;
    _error = null;
    _cameraError = null;
    _screenShareError = null;
    _privacyError = null;
    _endError = null;
    _endRequestId = null;
    _endBusy = false;
    if (_anotherVoiceSessionActive()) {
      _set(ServerSessionPhase.blocked);
      return;
    }
    _set(ServerSessionPhase.starting);
    _pendingJoinOperations++;
    try {
      _realtimeAudioLease ??= await _realtimeAudioSessions.acquire(
        owner: _realtimeAudioOwner,
        kind: RealtimeAudioSessionOwnerKind.serverConversation,
      );
      if (!_current(epoch)) return;
      try {
        var sessionId = target.activeSessionId;
        if (sessionId == null) {
          final start = await _repository.startChannelSession(
            serverId: server.id,
            channelId: target.id,
            requestId: _repository.newRequestId(),
          );
          sessionId = start.sessionId;
        }
        if (!_current(epoch)) return;
        _set(ServerSessionPhase.authorizing);
        final connection = await _repository.createChannelToken(
          serverId: server.id,
          channelId: target.id,
          sessionId: sessionId,
          requestId: _repository.newRequestId(),
        );
        if (!_current(epoch)) return;
        _connection = connection;
        _set(ServerSessionPhase.connecting);
        final link = await _connector.connect(
          serverUrl: connection.serverUrl,
          token: connection.participantToken,
        );
        if (!_current(epoch)) {
          await _cleanupLink(link);
          return;
        }
        _link = link..addListener(_onLinkChanged);
        _attachWhiteboardDataPlane(
          link: link,
          server: server,
          channel: target,
          connection: connection,
        );
        _onLinkChanged();
      } catch (error) {
        if (!_current(epoch)) return;
        _error = error;
        _set(ServerSessionPhase.failed);
      }
    } finally {
      _pendingJoinOperations--;
      _releaseRealtimeAudioIfIdle();
    }
  }

  bool get _isTerminal =>
      _phase == ServerSessionPhase.failed ||
      _phase == ServerSessionPhase.blocked;

  bool _current(int epoch) => !_disposed && epoch == _epoch;

  void _onLinkChanged() {
    final link = _link;
    if (link == null) return;
    switch (link.state) {
      case ServerMediaLinkState.connected:
        _whiteboardDataPlane?.resume();
        if (!_onConnected()) return;
        _set(ServerSessionPhase.connected);
      case ServerMediaLinkState.reconnecting:
        _whiteboardDataPlane?.suspend();
        _set(ServerSessionPhase.reconnecting);
      case ServerMediaLinkState.connecting:
        _whiteboardDataPlane?.suspend();
        _set(ServerSessionPhase.connecting);
      case ServerMediaLinkState.disconnected:
        if (_phase == ServerSessionPhase.leaving) return;
        // The provider ended the link (host ended the session, network
        // gone, token revoked). Release it and say so.
        _epoch++;
        _releaseDevice();
        link.removeListener(_onLinkChanged);
        _link = null;
        _detachWhiteboardDataPlane();
        unawaited(_cleanupLink(link));
        _error = const ServerSessionDisconnected();
        _set(ServerSessionPhase.failed);
    }
  }

  /// Done once per established link, from the foreground, in this order: the
  /// output route first (the provider has just re-applied the process-global
  /// preference on connect), then the keep-alive, which Android 12 and later
  /// refuse to start from the background.
  bool _deviceClaimed = false;

  bool _onConnected() {
    if (_deviceClaimed) return true;
    _deviceClaimed = true;
    // Private calls still have priority over a Server conversation, so this
    // side watches the legacy coordinator and yields when one begins. Both
    // sides also retain a process-wide registry lease; ordinary media cannot
    // change the shared route during the handoff or either native teardown.
    _otherVoiceOwner.addListener(_onOtherVoiceOwnerChanged);
    // The direct call may have started while the Server token or provider
    // connection was in flight, before this listener existed. Re-read the
    // owner after subscribing so that transition cannot be missed.
    if (_anotherVoiceSessionActive()) {
      unawaited(leave());
      return false;
    }
    unawaited(_device.preferSpeakerOutput());
    final channel = _channel;
    unawaited(
      _device.startKeepAlive(
        title: _server?.name.trim().isNotEmpty ?? false
            ? _server!.name.trim()
            : 'YO Voice',
        body: channel?.name ?? '',
        canPublish: canPublish,
      ),
    );
    return true;
  }

  void _releaseDevice() {
    if (!_deviceClaimed) return;
    _deviceClaimed = false;
    _otherVoiceOwner.removeListener(_onOtherVoiceOwnerChanged);
    unawaited(_device.stopKeepAlive());
  }

  void _onOtherVoiceOwnerChanged() {
    if (_disposed || !isActive) return;
    if (!_anotherVoiceSessionActive()) return;
    unawaited(leave());
  }

  /// Explicit capture control, bound to the microphone button only.
  Future<void> setMicrophoneEnabled(bool enabled) async {
    final link = _link;
    if (link == null || !isLive || _microphoneBusy) return;
    if (enabled && !canPublish) return;
    _microphoneBusy = true;
    _privacyError = null;
    notifyListeners();
    try {
      await link.setMicrophoneEnabled(enabled);
    } catch (error) {
      // The capture is whatever the link says it is; what changes here is
      // that the person is told the press did not take, instead of watching
      // the control quietly revert.
      _privacyError = error;
    } finally {
      _microphoneBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> toggleMicrophone() => setMicrophoneEnabled(!isMicrophoneEnabled);

  /// Silences the room on this device only. Nothing is published, written
  /// or signalled about the person; leaving restores the default.
  Future<void> setDeafened(bool deafened) async {
    final link = _link;
    // Local output only; a reconnect never makes it unavailable.
    if (link == null || !isLive || _headphonesBusy) return;
    _headphonesBusy = true;
    _privacyError = null;
    notifyListeners();
    try {
      await link.setDeafened(deafened);
    } catch (error) {
      _privacyError = error;
    } finally {
      _headphonesBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> toggleDeafened() => setDeafened(!isDeafened);

  /// Starts or stops this person's camera after an explicit press. The
  /// provider owns the permission prompt and the actual publication state;
  /// a cancelled or denied request is surfaced in the persistent dock.
  Future<void> setCameraEnabled(bool enabled) async {
    final link = _link;
    if (link == null || !isConnected || _cameraBusy) return;
    if (enabled && !canPublishCamera) return;
    _cameraBusy = true;
    _cameraError = null;
    notifyListeners();
    try {
      await link.setCameraEnabled(enabled);
    } catch (error) {
      _cameraError = error;
    } finally {
      _cameraBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> toggleCamera() => setCameraEnabled(!isCameraEnabled);

  /// Starts or stops publishing this device's screen.
  ///
  /// Explicit, like the microphone, and refused outright unless the grant and
  /// the platform both allow it — so a device that cannot capture never
  /// reaches the provider. A refusal by the browser (the person cancels the
  /// picker) is surfaced, not swallowed, and leaves the share off.
  Future<void> setScreenShareEnabled(bool enabled) async {
    final link = _link;
    if (link == null || !isConnected || _screenShareBusy) return;
    if (enabled && !canShareScreen) return;
    _screenShareBusy = true;
    _screenShareError = null;
    notifyListeners();
    try {
      await link.setScreenShareEnabled(enabled);
    } catch (error) {
      _screenShareError = error;
    } finally {
      _screenShareBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> toggleScreenShare() =>
      setScreenShareEnabled(!isScreenShareEnabled);

  /// Ends this generation for everybody through the durable backend
  /// lifecycle, then releases the local provider link. A failed or ambiguous
  /// request keeps the same request id for the visible retry and leaves the
  /// conversation connected until the backend accepts the operation.
  Future<void> endSession() async {
    final server = _server;
    final channel = _channel;
    final connection = _connection;
    if (_disposed ||
        _endBusy ||
        server == null ||
        channel == null ||
        connection == null ||
        !isLive) {
      return;
    }
    final epoch = _epoch;
    _endBusy = true;
    _endError = null;
    _endRequestId ??= _repository.newRequestId();
    notifyListeners();
    try {
      await _repository.endChannelSession(
        serverId: server.id,
        channelId: channel.id,
        sessionId: connection.sessionId,
        requestId: _endRequestId!,
      );
      if (!_current(epoch)) return;
      _endBusy = false;
      await leave();
    } catch (error) {
      if (!_current(epoch)) return;
      _endBusy = false;
      _endError = error;
      notifyListeners();
    }
  }

  /// Leaves the conversation; the server, the channel and any live
  /// generation stay exactly as they are.
  Future<void> leave() async {
    if (!isActive) return;
    _releaseDevice();
    _epoch++;
    final link = _link;
    _link = null;
    _detachWhiteboardDataPlane();
    if (link != null) {
      _set(ServerSessionPhase.leaving);
      link.removeListener(_onLinkChanged);
      await _cleanupLink(link);
    }
    _connection = null;
    _error = null;
    _cameraError = null;
    _screenShareError = null;
    _privacyError = null;
    _endError = null;
    _endRequestId = null;
    _endBusy = false;
    _set(ServerSessionPhase.idle);
    _releaseRealtimeAudioIfIdle();
  }

  /// Clears a failed or blocked outcome once it has been read.
  void dismiss() {
    if (!_isTerminal) return;
    _epoch++;
    _error = null;
    _cameraError = null;
    _screenShareError = null;
    _privacyError = null;
    _endError = null;
    _endRequestId = null;
    _endBusy = false;
    _connection = null;
    _set(ServerSessionPhase.idle);
    _releaseRealtimeAudioIfIdle();
  }

  Future<void> _cleanupLink(ServerMediaLink link) async {
    _pendingLinkCleanups++;
    try {
      try {
        await link.disconnect();
      } catch (_) {
        // Native capture ownership still ends through dispose below.
      }
      try {
        link.dispose();
      } catch (_) {
        // The registry still has to release after the native disconnect.
      }
    } finally {
      _pendingLinkCleanups--;
      _releaseRealtimeAudioIfIdle();
    }
  }

  void _attachWhiteboardDataPlane({
    required ServerMediaLink link,
    required Server server,
    required ServerChannel channel,
    required ServerSessionConnection connection,
  }) {
    _detachWhiteboardDataPlane();
    if (server.type != ServerType.company ||
        channel.kind != ServerChannelKind.meeting ||
        link is! ServerMediaDataLink) {
      return;
    }
    final dataLink = link as ServerMediaDataLink;
    final binding = ServerMediaSessionBinding(
      serverId: server.id,
      channelId: channel.id,
      roomId: connection.roomId,
      sessionId: connection.sessionId,
      participantIdentity: connection.participantIdentity,
      sessionRole: connection.sessionRole,
    );
    ServerWhiteboardLiveDataPlane plane;
    try {
      plane = ServerWhiteboardLiveDataPlane(
        link: dataLink,
        expectedMediaBinding: binding,
      );
    } catch (_) {
      // A provider without the exact signed local binding remains an ordinary
      // media link. The durable board still works; live previews stay honest.
      return;
    }
    final epoch = ++_whiteboardDataEpoch;
    _whiteboardDataPlane = plane;
    _whiteboardDataSubscription = plane.drafts.listen((drafts) {
      if (_disposed || epoch != _whiteboardDataEpoch) return;
      if (!_whiteboardLiveDraftController.isClosed) {
        _whiteboardLiveDraftController.add(drafts);
      }
    });
  }

  void _detachWhiteboardDataPlane() {
    _whiteboardDataEpoch++;
    final subscription = _whiteboardDataSubscription;
    _whiteboardDataSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final plane = _whiteboardDataPlane;
    _whiteboardDataPlane = null;
    if (plane != null) unawaited(plane.dispose());
    if (!_whiteboardLiveDraftController.isClosed) {
      _whiteboardLiveDraftController.add(const []);
    }
  }

  void _releaseRealtimeAudioIfIdle() {
    final lease = _realtimeAudioLease;
    if (lease == null) return;
    final holdsLivePhase =
        !_disposed && _phase != ServerSessionPhase.idle && !_isTerminal;
    if (_pendingJoinOperations > 0 ||
        _pendingLinkCleanups > 0 ||
        holdsLivePhase) {
      return;
    }
    _realtimeAudioLease = null;
    lease.release();
  }

  void _set(ServerSessionPhase phase) {
    if (_disposed) return;
    _phase = phase;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _releaseDevice();
    _epoch++;
    final link = _link;
    _link = null;
    _detachWhiteboardDataPlane();
    if (link != null) {
      link.removeListener(_onLinkChanged);
      unawaited(_cleanupLink(link));
    }
    _releaseRealtimeAudioIfIdle();
    unawaited(_whiteboardLiveDraftController.close());
    super.dispose();
  }
}
