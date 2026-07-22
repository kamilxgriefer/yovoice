import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import 'voice_token_service.dart';

enum VoiceCallStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

class VoiceCallService extends ChangeNotifier {
  VoiceCallService._();

  static final VoiceCallService instance = VoiceCallService._();

  final VoiceTokenService _tokenService = VoiceTokenService();

  Room? _room;
  EventsListener<RoomEvent>? _events;

  VoiceCallStatus _status = VoiceCallStatus.disconnected;
  String? _roomId;
  String? _roomName;
  String? _errorMessage;
  bool _isMuted = false;

  VoiceCallStatus get status => _status;
  String? get roomId => _roomId;
  String? get roomName => _roomName;
  String? get errorMessage => _errorMessage;
  bool get isMuted => _isMuted;
  bool get isConnected => _status == VoiceCallStatus.connected;
  bool get isBusy =>
      _status == VoiceCallStatus.connecting ||
      _status == VoiceCallStatus.reconnecting;

  List<VoiceParticipantViewData> get participants {
    final room = _room;
    if (room == null) return const [];

    final activeIdentities = room.activeSpeakers
        .map((participant) => participant.identity)
        .toSet();

    final result = <VoiceParticipantViewData>[];
    final local = room.localParticipant;

    if (local != null) {
      result.add(
        VoiceParticipantViewData(
          identity: local.identity,
          displayName: _displayName(local.name, local.identity),
          isLocal: true,
          isSpeaking: activeIdentities.contains(local.identity),
        ),
      );
    }

    for (final participant in room.remoteParticipants.values) {
      result.add(
        VoiceParticipantViewData(
          identity: participant.identity,
          displayName: _displayName(
            participant.name,
            participant.identity,
          ),
          isLocal: false,
          isSpeaking: activeIdentities.contains(participant.identity),
        ),
      );
    }

    result.sort((a, b) {
      if (a.isLocal != b.isLocal) return a.isLocal ? -1 : 1;
      if (a.isSpeaking != b.isSpeaking) return a.isSpeaking ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(
        b.displayName.toLowerCase(),
      );
    });

    return result;
  }

  Future<void> join({
    required String roomId,
    required String roomName,
    required String participantName,
  }) async {
    if (_roomId == roomId && isConnected) return;

    if (_room != null) {
      await disconnect();
    }

    _setStatus(VoiceCallStatus.connecting);
    _roomId = roomId;
    _roomName = roomName;
    _errorMessage = null;
    _isMuted = false;
    notifyListeners();

    try {
      await _requestPermissions();

      final connectionInfo = await _tokenService.createJoinToken(
        roomId: roomId,
        participantName: participantName,
      );

      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
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
        ..on<RoomDisconnectedEvent>((event) {
          _status = VoiceCallStatus.disconnected;
          _isMuted = false;
          notifyListeners();
        });

      await room.connect(
        connectionInfo.serverUrl,
        connectionInfo.participantToken,
      );

      final localParticipant = room.localParticipant;
      if (localParticipant == null) {
        throw StateError('Local voice participant was not created.');
      }

      await localParticipant.setMicrophoneEnabled(true);
      _setStatus(VoiceCallStatus.connected);
    } catch (error) {
      _errorMessage = _friendlyError(error);
      _setStatus(VoiceCallStatus.failed);
      await _disposeRoom();
      rethrow;
    }
  }

  Future<void> toggleMute() async {
    final localParticipant = _room?.localParticipant;
    if (localParticipant == null || !isConnected) return;

    final nextMuted = !_isMuted;
    await localParticipant.setMicrophoneEnabled(!nextMuted);
    _isMuted = nextMuted;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _status = VoiceCallStatus.disconnected;
    _errorMessage = null;
    _isMuted = false;
    _roomId = null;
    _roomName = null;
    notifyListeners();

    await _disposeRoom();
  }

  Future<void> _disposeRoom() async {
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
      throw StateError(
        'Microphone permission is required to join voice chat.',
      );
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
  });

  final String identity;
  final String displayName;
  final bool isLocal;
  final bool isSpeaking;
}
