import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:yovoice/core/audio/ui_sound.dart';
import 'package:yovoice/core/audio/ui_sound_service.dart';

import '../models/voice_connection_info.dart';
import 'direct_call_service.dart';
import 'voice_token_service.dart';

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

class VoiceCallService extends ChangeNotifier {
  VoiceCallService._();

  /// Test seam. The production service is a singleton behind a private
  /// constructor, which left no way for a widget test to observe whether a
  /// screen asked for a LiveKit token — the single most important assertion
  /// about the room entry path, since requesting one against a dormant room
  /// is the failure this whole path exists to prevent. A subclass may now
  /// stand in for it and record the calls.
  @visibleForTesting
  VoiceCallService.forTesting();

  static final VoiceCallService instance = VoiceCallService._();

  // Lazy: VoiceTokenService touches FirebaseFunctions at construction,
  // and this singleton is now reachable from always-mounted UI (the
  // shell's RoomMiniBar) — including in widget tests with no Firebase
  // app. Nothing needs the token service until an actual join().
  late final VoiceTokenService _tokenService = VoiceTokenService();
  late final DirectCallService _directCallService = DirectCallService();
  final UiSoundService _sounds = UiSoundService.instance;

  Room? _room;
  EventsListener<RoomEvent>? _events;
  Timer? _audioMeterTimer;

  VoiceCallStatus _status = VoiceCallStatus.disconnected;
  String? _roomId;
  String? _roomName;
  String? _errorMessage;
  VoiceSessionKind? _sessionKind;
  String? _directCallId;
  bool _isMuted = false;
  bool _muteChangeInProgress = false;

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

  double get roomEnergy {
    final values = participants
        .where((participant) => participant.isSpeaking)
        .map((participant) => participant.audioLevel)
        .toList(growable: false);

    if (values.isEmpty) return 0;
    final sum = values.fold<double>(0, (total, value) => total + value);
    return (sum / values.length).clamp(0, 1).toDouble();
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

  Future<void> join({
    required String roomId,
    required String roomName,
    required String participantName,
    bool playSound = true,
  }) async {
    return _joinWithToken(
      sessionRoomId: roomId,
      roomName: roomName,
      kind: VoiceSessionKind.room,
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
    bool playSound = true,
  }) {
    return _joinWithToken(
      sessionRoomId: 'call_$callId',
      roomName: contactName,
      kind: VoiceSessionKind.directCall,
      directCallId: callId,
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
    bool playSound = true,
  }) async {
    if (_roomId == sessionRoomId && isConnected) return;

    if (_room != null) {
      await disconnect();
    }

    _roomId = sessionRoomId;
    _roomName = roomName;
    _sessionKind = kind;
    _directCallId = directCallId;
    _errorMessage = null;
    _isMuted = false;
    _setStatus(VoiceCallStatus.connecting);

    try {
      await _requestPermissions();

      final connectionInfo = await tokenLoader();

      final room = Room(
        roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
      );

      _room = room;
      room.addListener(_handleRoomChanged);

      _events = room.createListener()
        ..on<RoomReconnectingEvent>((_) {
          _setStatus(VoiceCallStatus.reconnecting);
        })
        ..on<RoomReconnectedEvent>((_) {
          _setStatus(VoiceCallStatus.connected);
        })
        ..on<RoomDisconnectedEvent>((_) {
          _status = VoiceCallStatus.disconnected;
          _isMuted = false;
          notifyListeners();
        })
        ..on<ParticipantConnectedEvent>((_) {
          unawaited(_sounds.play(UiSound.participantJoined));
        })
        ..on<ParticipantDisconnectedEvent>((_) {
          unawaited(_sounds.play(UiSound.participantLeft));
        });

      await room.connect(
        connectionInfo.serverUrl,
        connectionInfo.participantToken,
      );

      final localParticipant = room.localParticipant;
      if (localParticipant == null) {
        throw StateError('Local voice participant was not created.');
      }

      try {
        await localParticipant.setMicrophoneEnabled(true);
        _isMuted = false;
      } catch (_) {
        // Listen-only token: broadcast audience members can't publish
        // (canPublish is computed server-side from their role). That's
        // a working join, not a failure — they're here to listen, and
        // a later promotion re-grants the mic via a fresh token.
        _isMuted = true;
      }
      _startAudioMeter();
      _setStatus(VoiceCallStatus.connected);
      if (playSound) {
        unawaited(_sounds.play(UiSound.roomJoined));
      }
    } catch (error) {
      _errorMessage = _friendlyError(error);
      _setStatus(VoiceCallStatus.failed);
      await _disposeRoom();
      rethrow;
    }
  }

  Future<void> setMuted(bool muted) async {
    final localParticipant = _room?.localParticipant;
    if (localParticipant == null || !isConnected || _muteChangeInProgress) {
      return;
    }
    // Compare against the AUTHORITATIVE state, not the remembered flag —
    // they can disagree after a reconnect, and acting on the stale flag
    // is how the button got stuck looking pressed.
    if (isMuted == muted) return;

    final previous = isMuted;
    _muteChangeInProgress = true;
    _isMuted = muted;
    notifyListeners();
    try {
      await localParticipant.setMicrophoneEnabled(!muted);
      unawaited(
        _sounds.play(
          muted ? UiSound.microphoneMuted : UiSound.microphoneUnmuted,
        ),
      );
    } catch (_) {
      _isMuted = previous;
      rethrow;
    } finally {
      _muteChangeInProgress = false;
      notifyListeners();
    }
  }

  Future<void> toggleMute() async {
    final localParticipant = _room?.localParticipant;
    if (localParticipant == null || !isConnected || _muteChangeInProgress) {
      return;
    }

    final previous = isMuted;
    final next = !previous;

    _muteChangeInProgress = true;
    _isMuted = next;
    notifyListeners();

    try {
      await localParticipant.setMicrophoneEnabled(!next);
      unawaited(
        _sounds.play(
          next ? UiSound.microphoneMuted : UiSound.microphoneUnmuted,
        ),
      );
    } catch (_) {
      _isMuted = previous;
      rethrow;
    } finally {
      _muteChangeInProgress = false;
      notifyListeners();
    }
  }

  Future<void> disconnect({bool playSound = true}) async {
    final wasConnected = isConnected;
    _status = VoiceCallStatus.disconnected;
    _errorMessage = null;
    _isMuted = false;
    _muteChangeInProgress = false;
    _roomId = null;
    _roomName = null;
    _sessionKind = null;
    _directCallId = null;
    notifyListeners();

    await _disposeRoom();
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

    _events?.dispose();
    _events = null;

    if (room != null) {
      room.removeListener(_handleRoomChanged);
      await room.disconnect();
      await room.dispose();
    }
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;

    final microphone = await Permission.microphone.request();
    if (!microphone.isGranted) {
      throw StateError('Microphone permission is required to join voice chat.');
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      await Permission.bluetoothConnect.request();
    }
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

  String _friendlyError(Object error) {
    // A callable refusal carries product copy in .message ("This room is
    // not currently live."); the code prefix ("[firebase_functions/…]")
    // is developer noise and must never reach a SnackBar.
    if (error is FirebaseFunctionsException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) return message;
      return 'Live audio is unavailable right now. Try again.';
    }
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  @override
  void dispose() {
    unawaited(_disposeRoom());
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
