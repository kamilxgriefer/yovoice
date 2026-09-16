import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/server_whiteboard.dart';
import 'server_media_connector.dart';

/// LiveKit topic reserved for in-progress Company whiteboard gestures.
/// Completed strokes never use this path; they remain server-authoritative
/// callable mutations followed by Firestore reads.
const serverWhiteboardLiveTopic = 'yo.whiteboard.live.v1';

/// UI-facing realtime seam. A transport is available only while this client
/// has an established, generation-bound Company meeting media link.
abstract interface class ServerWhiteboardLiveTransport implements Listenable {
  bool isAvailableFor(String serverId);

  Stream<List<ServerWhiteboardLiveDraft>> get whiteboardLiveDrafts;

  /// Returns false when no exact active media binding exists. The caller keeps
  /// drawing locally and persists the completed stroke; it must not report a
  /// remote preview as sent in that case.
  Future<bool> publishWhiteboardLiveDraft({
    required String serverId,
    required String channelId,
    required String draftId,
    required int generation,
    required List<ServerWhiteboardPoint> points,
    required ServerWhiteboardColor color,
    required int lineWidth,
  });

  Future<bool> clearWhiteboardLiveDraft({
    required String serverId,
    required String channelId,
    required String draftId,
    required int generation,
  });
}

@immutable
sealed class ServerWhiteboardLiveMessage {
  const ServerWhiteboardLiveMessage({
    required this.serverId,
    required this.boardChannelId,
    required this.mediaChannelId,
    required this.roomId,
    required this.sessionId,
    required this.authorId,
    required this.generation,
    required this.draftId,
    required this.sequence,
  });

  final String serverId;
  final String boardChannelId;
  final String mediaChannelId;
  final String roomId;
  final String sessionId;
  final String authorId;
  final int generation;
  final String draftId;
  final int sequence;
}

final class ServerWhiteboardLiveUpdate extends ServerWhiteboardLiveMessage {
  const ServerWhiteboardLiveUpdate({
    required super.serverId,
    required super.boardChannelId,
    required super.mediaChannelId,
    required super.roomId,
    required super.sessionId,
    required super.authorId,
    required super.generation,
    required super.draftId,
    required super.sequence,
    required this.points,
    required this.color,
    required this.lineWidth,
  });

  final List<ServerWhiteboardPoint> points;
  final ServerWhiteboardColor color;
  final int lineWidth;
}

final class ServerWhiteboardLiveClear extends ServerWhiteboardLiveMessage {
  const ServerWhiteboardLiveClear({
    required super.serverId,
    required super.boardChannelId,
    required super.mediaChannelId,
    required super.roomId,
    required super.sessionId,
    required super.authorId,
    required super.generation,
    required super.draftId,
    required super.sequence,
  });
}

/// Exact, bounded codec for the encrypted WebRTC data-channel payload.
///
/// Provider-authenticated participant metadata supplies [sender]. The author
/// field inside the payload is accepted only when it equals that identity and
/// every media-generation field equals [expectedMediaBinding].
@visibleForTesting
final class ServerWhiteboardLiveCodec {
  const ServerWhiteboardLiveCodec._();

  static const schemaVersion = 1;
  static const maximumPacketBytes = 2048;

  static List<int> encodeUpdate({
    required ServerMediaSessionBinding mediaBinding,
    required String boardChannelId,
    required String draftId,
    required int generation,
    required int sequence,
    required List<ServerWhiteboardPoint> points,
    required ServerWhiteboardColor color,
    required int lineWidth,
  }) {
    final encodedPoints = encodeServerWhiteboardPoints(points);
    return _encode({
      'v': schemaVersion,
      'type': 'draft',
      ..._bindingMap(mediaBinding, boardChannelId),
      'generation': generation,
      'draftId': draftId,
      'sequence': sequence,
      'points': encodedPoints,
      'color': color.name,
      'lineWidth': lineWidth,
    });
  }

  static List<int> encodeClear({
    required ServerMediaSessionBinding mediaBinding,
    required String boardChannelId,
    required String draftId,
    required int generation,
    required int sequence,
  }) => _encode({
    'v': schemaVersion,
    'type': 'clear',
    ..._bindingMap(mediaBinding, boardChannelId),
    'generation': generation,
    'draftId': draftId,
    'sequence': sequence,
  });

  static ServerWhiteboardLiveMessage? decode({
    required List<int> bytes,
    required ServerMediaSessionBinding sender,
    required ServerMediaSessionBinding expectedMediaBinding,
  }) {
    if (bytes.isEmpty || bytes.length > maximumPacketBytes) return null;
    if (!sender.matchesGeneration(expectedMediaBinding)) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final payload = decoded;
    final type = payload['type'];
    final expectedKeys = type == 'draft'
        ? _draftKeys
        : type == 'clear'
        ? _clearKeys
        : null;
    if (expectedKeys == null ||
        !setEquals(payload.keys.toSet(), expectedKeys)) {
      return null;
    }
    final serverId = _safeResourceId(payload['serverId']);
    final boardChannelId = _safeResourceId(payload['boardChannelId']);
    final mediaChannelId = _safeResourceId(payload['mediaChannelId']);
    final roomId = _safeResourceId(payload['roomId']);
    final sessionId = _safeResourceId(payload['sessionId']);
    final authorId = _safeParticipantIdentity(payload['authorId']);
    final draftId = _safeResourceId(payload['draftId']);
    final generation = payload['generation'];
    final sequence = payload['sequence'];
    if (payload['v'] != schemaVersion ||
        serverId != expectedMediaBinding.serverId ||
        mediaChannelId != expectedMediaBinding.channelId ||
        roomId != expectedMediaBinding.roomId ||
        sessionId != expectedMediaBinding.sessionId ||
        authorId != sender.participantIdentity ||
        boardChannelId == null ||
        draftId == null ||
        generation is! int ||
        generation < 1 ||
        generation > 0x7fffffff ||
        sequence is! int ||
        sequence < 1 ||
        sequence > 0x7fffffff) {
      return null;
    }
    final common = (
      serverId: serverId!,
      boardChannelId: boardChannelId,
      mediaChannelId: mediaChannelId!,
      roomId: roomId!,
      sessionId: sessionId!,
      authorId: authorId!,
      generation: generation,
      draftId: draftId,
      sequence: sequence,
    );
    if (type == 'clear') {
      return ServerWhiteboardLiveClear(
        serverId: common.serverId,
        boardChannelId: common.boardChannelId,
        mediaChannelId: common.mediaChannelId,
        roomId: common.roomId,
        sessionId: common.sessionId,
        authorId: common.authorId,
        generation: common.generation,
        draftId: common.draftId,
        sequence: common.sequence,
      );
    }
    final color = ServerWhiteboardColor.values
        .where((candidate) => candidate.name == payload['color'])
        .firstOrNull;
    final lineWidth = payload['lineWidth'];
    final rawPoints = payload['points'];
    final points = rawPoints is String
        ? decodeServerWhiteboardPoints(rawPoints)
        : null;
    if (color == null ||
        lineWidth is! int ||
        lineWidth < 1 ||
        lineWidth > 16 ||
        points == null) {
      return null;
    }
    return ServerWhiteboardLiveUpdate(
      serverId: common.serverId,
      boardChannelId: common.boardChannelId,
      mediaChannelId: common.mediaChannelId,
      roomId: common.roomId,
      sessionId: common.sessionId,
      authorId: common.authorId,
      generation: common.generation,
      draftId: common.draftId,
      sequence: common.sequence,
      points: points,
      color: color,
      lineWidth: lineWidth,
    );
  }

  static Map<String, Object> _bindingMap(
    ServerMediaSessionBinding binding,
    String boardChannelId,
  ) => {
    'serverId': _requireResourceId(binding.serverId, 'serverId'),
    'boardChannelId': _requireResourceId(
      boardChannelId,
      'boardChannelId',
    ),
    'mediaChannelId': _requireResourceId(binding.channelId, 'mediaChannelId'),
    'roomId': _requireResourceId(binding.roomId, 'roomId'),
    'sessionId': _requireResourceId(binding.sessionId, 'sessionId'),
    'authorId': _requireParticipantIdentity(
      binding.participantIdentity,
      'participantIdentity',
    ),
  };

  static List<int> _encode(Map<String, Object> payload) {
    final bytes = utf8.encode(jsonEncode(payload));
    if (bytes.length > maximumPacketBytes) {
      throw const FormatException('Whiteboard live packet exceeds its limit.');
    }
    return bytes;
  }
}

/// Per-link bounded state machine for whiteboard pointer previews.
///
/// The map is capped to one preview per authenticated participant. Malformed
/// packets are rejected before JSON work once that participant exhausts a
/// small rolling budget; old or reordered sequences never resurrect ink.
final class ServerWhiteboardLiveDataPlane {
  ServerWhiteboardLiveDataPlane({
    required ServerMediaDataLink link,
    required this.expectedMediaBinding,
    DateTime Function()? clock,
    this.previewLifetime = const Duration(seconds: 2),
  }) : _link = link,
       _clock = clock ?? DateTime.now {
    final local = link.localSessionBinding;
    if (local == null ||
        !local.matchesGeneration(expectedMediaBinding) ||
        local.participantIdentity != expectedMediaBinding.participantIdentity ||
        local.sessionRole != expectedMediaBinding.sessionRole) {
      throw StateError('The local media generation binding is invalid.');
    }
    _subscription = link.dataPackets.listen(_accept);
  }

  static const maximumRemoteAuthors = 64;
  static const maximumInboundEventsPerWindow = 60;
  static const maximumRetiredConnectionsPerAuthor = 4;
  static const inboundWindow = Duration(seconds: 5);
  static const inactiveAuthorStateLifetime = Duration(seconds: 30);

  final ServerMediaDataLink _link;
  final ServerMediaSessionBinding expectedMediaBinding;
  final DateTime Function() _clock;
  final Duration previewLifetime;
  final StreamController<List<ServerWhiteboardLiveDraft>> _drafts =
      StreamController<List<ServerWhiteboardLiveDraft>>.broadcast(sync: true);
  final Map<String, ServerWhiteboardLiveDraft> _byAuthor = {};
  final Map<String, String> _currentConnectionByAuthor = {};
  final Map<String, Set<String>> _retiredConnectionsByAuthor = {};
  final Map<String, int> _lastSequenceByConnection = {};
  final Map<String, _InboundWindow> _inboundWindows = {};
  late final StreamSubscription<ServerMediaDataPacket> _subscription;
  Timer? _expiryTimer;
  int _outboundSequence = 0;
  bool _active = true;
  bool _disposed = false;

  bool get isActive => _active && !_disposed;
  Stream<List<ServerWhiteboardLiveDraft>> get drafts => _drafts.stream;

  Future<bool> publishDraft({
    required String serverId,
    required String channelId,
    required String draftId,
    required int generation,
    required List<ServerWhiteboardPoint> points,
    required ServerWhiteboardColor color,
    required int lineWidth,
  }) async {
    if (!isActive || serverId != expectedMediaBinding.serverId) return false;
    final sequence = _nextSequence();
    final bytes = ServerWhiteboardLiveCodec.encodeUpdate(
      mediaBinding: expectedMediaBinding,
      boardChannelId: channelId,
      draftId: _requireResourceId(draftId, 'draftId'),
      generation: generation,
      sequence: sequence,
      points: points,
      color: color,
      lineWidth: lineWidth,
    );
    try {
      await _link.publishData(
        bytes,
        topic: serverWhiteboardLiveTopic,
        reliable: false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> clearDraft({
    required String serverId,
    required String channelId,
    required String draftId,
    required int generation,
  }) async {
    if (!isActive || serverId != expectedMediaBinding.serverId) return false;
    final bytes = ServerWhiteboardLiveCodec.encodeClear(
      mediaBinding: expectedMediaBinding,
      boardChannelId: channelId,
      draftId: _requireResourceId(draftId, 'draftId'),
      generation: generation,
      sequence: _nextSequence(),
    );
    try {
      await _link.publishData(
        bytes,
        topic: serverWhiteboardLiveTopic,
        reliable: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void suspend() {
    if (_disposed || !_active) return;
    _active = false;
    _clearRemote();
  }

  void resume() {
    if (_disposed || _active) return;
    _active = true;
  }

  void _accept(ServerMediaDataPacket packet) {
    if (!isActive || packet.topic != serverWhiteboardLiveTopic) return;
    final sender = packet.sender;
    if (sender.participantIdentity ==
            expectedMediaBinding.participantIdentity ||
        sender.sessionRole == 'listener' ||
        !isValidOpaqueServerParticipantIdentity(sender.participantIdentity) ||
        !sender.matchesGeneration(expectedMediaBinding)) {
      return;
    }
    final senderConnectionId = _safeResourceId(packet.senderConnectionId);
    if (senderConnectionId == null) return;
    final now = _clock().toUtc();
    if (!_consumeInboundBudget(sender.participantIdentity, now)) return;
    final message = ServerWhiteboardLiveCodec.decode(
      bytes: packet.data,
      sender: sender,
      expectedMediaBinding: expectedMediaBinding,
    );
    if (message == null) return;
    if (!_acceptSenderConnection(message.authorId, senderConnectionId)) {
      return;
    }
    final sequenceKey = '${message.authorId}/$senderConnectionId';
    final previousSequence = _lastSequenceByConnection[sequenceKey] ?? 0;
    if (message.sequence <= previousSequence) return;
    _lastSequenceByConnection[sequenceKey] = message.sequence;
    if (message is ServerWhiteboardLiveClear) {
      final current = _byAuthor[message.authorId];
      if (current?.draftId == message.draftId) {
        _byAuthor.remove(message.authorId);
        _emit();
      }
      return;
    }
    final update = message as ServerWhiteboardLiveUpdate;
    if (!_byAuthor.containsKey(update.authorId) &&
        _byAuthor.length >= maximumRemoteAuthors) {
      return;
    }
    _byAuthor[update.authorId] = ServerWhiteboardLiveDraft(
      draftId: update.draftId,
      serverId: update.serverId,
      channelId: update.boardChannelId,
      mediaChannelId: update.mediaChannelId,
      roomId: update.roomId,
      sessionId: update.sessionId,
      authorId: update.authorId,
      generation: update.generation,
      sequence: update.sequence,
      points: update.points,
      color: update.color,
      lineWidth: update.lineWidth,
      receivedAt: now,
      expiresAt: now.add(previewLifetime),
    );
    _emit();
    _scheduleExpiry();
  }

  bool _consumeInboundBudget(String authorId, DateTime now) {
    var window = _inboundWindows[authorId];
    if (window == null) {
      if (_inboundWindows.length >= maximumRemoteAuthors) {
        _pruneInactiveAuthorState(now);
        if (_inboundWindows.length >= maximumRemoteAuthors) return false;
      }
      window = _InboundWindow(startedAt: now, lastSeenAt: now, count: 0);
    } else if (now.difference(window.startedAt) >= inboundWindow ||
        now.isBefore(window.startedAt)) {
      window = _InboundWindow(startedAt: now, lastSeenAt: now, count: 0);
    }
    if (window.count >= maximumInboundEventsPerWindow) return false;
    _inboundWindows[authorId] = window.incremented(now);
    return true;
  }

  void _pruneInactiveAuthorState(DateTime now) {
    var removedDraft = false;
    final staleAuthors = <String>[];
    for (final entry in _inboundWindows.entries) {
      final lastSeenAt = entry.value.lastSeenAt;
      if (now.isBefore(lastSeenAt) ||
          now.difference(lastSeenAt) < inactiveAuthorStateLifetime) {
        continue;
      }
      final draft = _byAuthor[entry.key];
      if (draft != null && draft.expiresAt.isAfter(now)) continue;
      staleAuthors.add(entry.key);
    }
    for (final authorId in staleAuthors) {
      removedDraft = _byAuthor.remove(authorId) != null || removedDraft;
      _inboundWindows.remove(authorId);
      final current = _currentConnectionByAuthor.remove(authorId);
      if (current != null) {
        _lastSequenceByConnection.remove('$authorId/$current');
      }
      final retired = _retiredConnectionsByAuthor.remove(authorId);
      if (retired != null) {
        for (final connectionId in retired) {
          _lastSequenceByConnection.remove('$authorId/$connectionId');
        }
      }
    }
    if (removedDraft) {
      _emit();
      _scheduleExpiry();
    }
  }

  bool _acceptSenderConnection(String authorId, String connectionId) {
    final current = _currentConnectionByAuthor[authorId];
    if (current == connectionId) return true;
    final retired = _retiredConnectionsByAuthor[authorId];
    if (retired?.contains(connectionId) ?? false) return false;
    if (current != null) {
      final nextRetired = {...?retired};
      if (nextRetired.length >= maximumRetiredConnectionsPerAuthor) {
        // After the bounded reconnect history fills, fail closed for this
        // author until the link is rebuilt. Evicting an old SID would allow a
        // delayed packet from that retired connection to become current again.
        return false;
      }
      nextRetired.add(current);
      _retiredConnectionsByAuthor[authorId] = nextRetired;
      _lastSequenceByConnection.remove('$authorId/$current');
      if (_byAuthor.remove(authorId) != null) _emit();
    }
    _currentConnectionByAuthor[authorId] = connectionId;
    return true;
  }

  int _nextSequence() {
    if (_outboundSequence >= 0x7fffffff) _outboundSequence = 0;
    return ++_outboundSequence;
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    if (_byAuthor.isEmpty || _disposed) return;
    final now = _clock().toUtc();
    final next = _byAuthor.values
        .map((draft) => draft.expiresAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final delay = next.difference(now);
    _expiryTimer = Timer(delay.isNegative ? Duration.zero : delay, _expire);
  }

  void _expire() {
    if (_disposed) return;
    final now = _clock().toUtc();
    final before = _byAuthor.length;
    _byAuthor.removeWhere((_, draft) => !draft.expiresAt.isAfter(now));
    if (_byAuthor.length != before) _emit();
    _scheduleExpiry();
  }

  @visibleForTesting
  void expireNow() => _expire();

  void _emit() {
    if (_drafts.isClosed) return;
    _drafts.add(List<ServerWhiteboardLiveDraft>.unmodifiable(_byAuthor.values));
  }

  void _clearRemote() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _byAuthor.clear();
    _currentConnectionByAuthor.clear();
    _retiredConnectionsByAuthor.clear();
    _lastSequenceByConnection.clear();
    _inboundWindows.clear();
    _emit();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _active = false;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _byAuthor.clear();
    _currentConnectionByAuthor.clear();
    _retiredConnectionsByAuthor.clear();
    _lastSequenceByConnection.clear();
    _inboundWindows.clear();
    await _subscription.cancel();
    await _drafts.close();
  }
}

@immutable
class _InboundWindow {
  const _InboundWindow({
    required this.startedAt,
    required this.lastSeenAt,
    required this.count,
  });

  final DateTime startedAt;
  final DateTime lastSeenAt;
  final int count;

  _InboundWindow incremented(DateTime now) => _InboundWindow(
    startedAt: startedAt,
    lastSeenAt: now,
    count: count + 1,
  );
}

const _baseKeys = <String>{
  'v',
  'type',
  'serverId',
  'boardChannelId',
  'mediaChannelId',
  'roomId',
  'sessionId',
  'authorId',
  'generation',
  'draftId',
  'sequence',
};
const _draftKeys = <String>{..._baseKeys, 'points', 'color', 'lineWidth'};
const _clearKeys = _baseKeys;

final _safeResourceIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

String? _safeResourceId(Object? value) =>
    value is String && _safeResourceIdPattern.hasMatch(value) ? value : null;

String? _safeParticipantIdentity(Object? value) =>
    isValidOpaqueServerParticipantIdentity(value) ? value! as String : null;

String _requireResourceId(Object? value, String name) =>
    _safeResourceId(value) ?? (throw ArgumentError.value(value, name));

String _requireParticipantIdentity(Object? value, String name) =>
    _safeParticipantIdentity(value) ??
    (throw ArgumentError.value(value, name));
