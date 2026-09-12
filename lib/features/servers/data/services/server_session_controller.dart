import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yovoice/features/calls/data/services/voice_call_service.dart';

import '../models/server.dart';
import '../models/server_channel.dart';
import '../models/server_session.dart';
import 'server_media_connector.dart';
import 'server_screen_share_capability.dart';
import 'server_service.dart';
import 'server_voice_device.dart';

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
class ServerSessionController extends ChangeNotifier {
  ServerSessionController({
    required ServerRepository repository,
    ServerMediaConnector? connector,
    bool Function()? anotherVoiceSessionActive,
    ServerScreenShareCapability? screenShare,
    ServerVoiceDevice? device,
    Listenable? otherVoiceOwner,
  }) : _otherVoiceOwnerOverride = otherVoiceOwner,
       _repository = repository,
       _connector = connector ?? const LiveKitServerMediaConnector(),
       _anotherVoiceSessionActive =
           anotherVoiceSessionActive ?? _legacyVoiceSessionActive,
       _device = device ?? serverVoiceDevice(),
       screenShare = screenShare ?? serverScreenShareCapability();

  final ServerRepository _repository;
  final ServerMediaConnector _connector;
  final bool Function() _anotherVoiceSessionActive;

  /// The speaker route and the Android keep-alive service. Neither is owned by
  /// this slice; both have to be asked for, per session, or a conversation
  /// plays out of the earpiece and dies when the app is backgrounded.
  final ServerVoiceDevice _device;

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
  Object? _error;
  bool _microphoneBusy = false;
  bool _headphonesBusy = false;
  bool _screenShareBusy = false;
  Object? _screenShareError;

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

  /// The camera half of the meeting grant. The token really does permit it
  /// (`mediaMode ∈ {video, meeting}`), but no publishing lifecycle exists on
  /// this side yet — permission, requested vs. actual state and cleanup per
  /// source (contract §3) — so no surface offers to turn a camera on.
  /// Receiving other people's video is unaffected and real.
  bool get canPublishCamera => _connection?.canPublishCamera ?? false;

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

  bool isIn(String channelId) => isActive && _channel?.id == channelId;

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
    _screenShareError = null;
    _privacyError = null;
    if (_anotherVoiceSessionActive()) {
      _set(ServerSessionPhase.blocked);
      return;
    }
    _set(ServerSessionPhase.starting);
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
        await link.disconnect();
        link.dispose();
        return;
      }
      _link = link..addListener(_onLinkChanged);
      _onLinkChanged();
    } catch (error) {
      if (!_current(epoch)) return;
      _error = error;
      _set(ServerSessionPhase.failed);
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
        _onConnected();
        _set(ServerSessionPhase.connected);
      case ServerMediaLinkState.reconnecting:
        _set(ServerSessionPhase.reconnecting);
      case ServerMediaLinkState.connecting:
        _set(ServerSessionPhase.connecting);
      case ServerMediaLinkState.disconnected:
        if (_phase == ServerSessionPhase.leaving) return;
        // The provider ended the link (host ended the session, network
        // gone, token revoked). Release it and say so.
        _epoch++;
        _releaseDevice();
        link.removeListener(_onLinkChanged);
        unawaited(link.disconnect().catchError((_) {}));
        _link = null;
        _error = const ServerSessionDisconnected();
        _set(ServerSessionPhase.failed);
    }
  }

  /// Done once per established link, from the foreground, in this order: the
  /// output route first (the provider has just re-applied the process-global
  /// preference on connect), then the keep-alive, which Android 12 and later
  /// refuse to start from the background.
  bool _deviceClaimed = false;

  void _onConnected() {
    if (_deviceClaimed) return;
    _deviceClaimed = true;
    // The guard before the join is one-way: the legacy coordinator does not
    // ask this side anything, and a call started on top of a live server
    // conversation would run two capture owners and one shared native audio
    // session, whose teardown is process-global either way. While this
    // session is up it watches the other owner and yields to it — the whole
    // guard, from both directions, still belongs in a process-level voice
    // lease that neither side owns today.
    _otherVoiceOwner.addListener(_onOtherVoiceOwnerChanged);
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

  /// Leaves the conversation; the server, the channel and any live
  /// generation stay exactly as they are.
  Future<void> leave() async {
    if (!isActive) return;
    _releaseDevice();
    _epoch++;
    final link = _link;
    _link = null;
    if (link != null) {
      _set(ServerSessionPhase.leaving);
      link.removeListener(_onLinkChanged);
      try {
        await link.disconnect();
      } catch (_) {
        // The link is released either way; nothing else can be done.
      }
      link.dispose();
    }
    _connection = null;
    _error = null;
    _screenShareError = null;
    _privacyError = null;
    _set(ServerSessionPhase.idle);
  }

  /// Clears a failed or blocked outcome once it has been read.
  void dismiss() {
    if (!_isTerminal) return;
    _epoch++;
    _error = null;
    _screenShareError = null;
    _privacyError = null;
    _connection = null;
    _set(ServerSessionPhase.idle);
  }

  void _set(ServerSessionPhase phase) {
    if (_disposed) return;
    _phase = phase;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _releaseDevice();
    _epoch++;
    final link = _link;
    _link = null;
    if (link != null) {
      link.removeListener(_onLinkChanged);
      unawaited(
        link.disconnect().catchError((_) {}).whenComplete(link.dispose),
      );
    }
    super.dispose();
  }
}
