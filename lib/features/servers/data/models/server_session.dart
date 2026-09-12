import 'package:flutter/foundation.dart';

import 'server.dart';
import 'server_channel.dart';

/// `startServerChannelSessionV1` → `{roomId, sessionId}`: the generation the
/// caller may now request a token for, whether it was just started or was
/// already live and compatible.
@immutable
class ServerSessionStart {
  const ServerSessionStart({required this.roomId, required this.sessionId});

  final String roomId;
  final String sessionId;

  factory ServerSessionStart.fromMap(Map<Object?, Object?> data) {
    final roomId = serverString(data['roomId']);
    final sessionId = serverString(data['sessionId']);
    if (roomId == null || sessionId == null) {
      throw const FormatException('Incomplete session start receipt.');
    }
    return ServerSessionStart(roomId: roomId, sessionId: sessionId);
  }
}

/// `createServerChannelTokenV1`'s connection receipt: the provider URL, the
/// signed participant token, the exact grant and the binding it was issued
/// for. Parsed strictly — a token without its permission map is refused
/// rather than treated as a listener grant.
@immutable
class ServerSessionConnection {
  const ServerSessionConnection({
    required this.serverUrl,
    required this.participantToken,
    required this.roomName,
    required this.participantIdentity,
    required this.participantName,
    required this.expiresAtMillis,
    required this.canPublish,
    required this.canSubscribe,
    required this.permittedTrackSources,
    required this.sessionRole,
    required this.roomId,
    required this.sessionId,
  });

  final String serverUrl;
  final String participantToken;
  final String roomName;
  final String participantIdentity;
  final String participantName;
  final int expiresAtMillis;
  final bool canPublish;
  final bool canSubscribe;
  final List<String> permittedTrackSources;

  /// `host | guest | listener`, assigned once by the server.
  final String sessionRole;
  final String roomId;
  final String sessionId;

  bool get canPublishMicrophone =>
      canPublish && permittedTrackSources.contains('microphone');

  /// `deriveSessionGrant` adds `camera` for `mediaMode ∈ {video, meeting}`.
  bool get canPublishCamera =>
      canPublish && permittedTrackSources.contains('camera');

  /// `deriveSessionGrant` adds `screen_share` only for a meeting's host. It is
  /// half of what a share needs: the other half is the platform capability of
  /// contract decision D.
  bool get canPublishScreenShare =>
      canPublish && permittedTrackSources.contains('screen_share');

  factory ServerSessionConnection.fromMap(Map<Object?, Object?> data) {
    String required(String key) =>
        serverString(data[key]) ??
        (throw FormatException('Incomplete media connection: $key.'));
    final permissions = data['permissions'];
    if (permissions is! Map) {
      throw const FormatException('Media connection has no permissions.');
    }
    bool flag(Object? value) => value == true;
    final sources = data['permittedTrackSources'];
    final expires = data['expiresAtMillis'];
    return ServerSessionConnection(
      serverUrl: required('serverUrl'),
      participantToken: required('participantToken'),
      roomName: required('roomName'),
      participantIdentity: required('participantIdentity'),
      participantName: required('participantName'),
      expiresAtMillis: expires is int ? expires : 0,
      canPublish: flag(permissions['canPublish']),
      canSubscribe: flag(permissions['canSubscribe']),
      permittedTrackSources: sources is List
          ? sources.whereType<String>().toList(growable: false)
          : const [],
      sessionRole: serverString(data['sessionRole']) ?? 'listener',
      roomId: required('roomId'),
      sessionId: required('sessionId'),
    );
  }
}

/// `setServerSessionHandV1`'s receipt.
///
/// A raised hand is a request, not authority: the callable writes
/// `isHandRaised` on the participant document and bumps nothing, and that
/// document is not client-readable (contract gap G3). So this receipt is the
/// only honest source for "your request is in" — the UI reflects the answer
/// to its own call and never guesses at a queue it cannot see.
@immutable
class ServerSessionHandResult {
  const ServerSessionHandResult({
    required this.sessionId,
    required this.raised,
    required this.changed,
    required this.sessionRole,
  });

  final String sessionId;
  final bool raised;

  /// False when the hand already stood exactly as asked.
  final bool changed;

  /// `host | guest | listener` as the server holds it for this generation.
  final String sessionRole;

  factory ServerSessionHandResult.fromMap(Map<Object?, Object?> data) {
    final sessionId = serverString(data['sessionId']);
    if (sessionId == null) {
      throw const FormatException('Incomplete hand receipt.');
    }
    return ServerSessionHandResult(
      sessionId: sessionId,
      raised: data['raised'] == true,
      changed: data['changed'] == true,
      sessionRole: serverString(data['role']) ?? 'listener',
    );
  }
}

/// `createServerInviteV1`'s receipt.
@immutable
class ServerInviteResult {
  const ServerInviteResult({
    required this.serverId,
    required this.inviteeId,
    required this.generation,
    required this.status,
    required this.alreadyExisted,
    this.expiresAtMillis,
  });

  final String serverId;
  final String inviteeId;
  final int generation;
  final String status;
  final bool alreadyExisted;
  final int? expiresAtMillis;

  factory ServerInviteResult.fromMap(Map<Object?, Object?> data) {
    final generation = data['generation'];
    final expires = data['expiresAtMillis'];
    return ServerInviteResult(
      serverId: serverString(data['serverId']) ?? '',
      inviteeId: serverString(data['inviteeId']) ?? '',
      generation: generation is int ? generation : 0,
      status: serverString(data['status']) ?? 'pending',
      alreadyExisted: data['alreadyExisted'] == true,
      expiresAtMillis: expires is int ? expires : null,
    );
  }
}

/// Somebody the viewer may invite: a canonical friend. The callable
/// re-proves the friendship, so this is a candidate list, never authority.
@immutable
class ServerInviteCandidate {
  const ServerInviteCandidate({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

/// The exact `createServerChannelV1` payload. `experience` and `mediaMode`
/// are present only for media kinds, exactly as `channelCreationInput`
/// requires, and `experience` is derived from the kind because
/// `mediaConfiguration()` accepts no other pairing.
@immutable
class ServerChannelCreationRequest {
  const ServerChannelCreationRequest({
    required this.serverId,
    required this.requestId,
    required this.kind,
    required this.name,
    this.restricted = false,
    this.mediaMode,
  });

  final String serverId;
  final String requestId;
  final ServerChannelKind kind;
  final String name;
  final bool restricted;
  final ServerMediaMode? mediaMode;

  Map<String, Object?> toCallableData() {
    final mode = kind.isMedia
        ? switch (kind) {
            ServerChannelKind.voice => ServerMediaMode.audio,
            ServerChannelKind.meeting => ServerMediaMode.meeting,
            _ => mediaMode ?? ServerMediaMode.audio,
          }
        : null;
    return {
      'serverId': serverId,
      'requestId': requestId,
      'kind': kind.name,
      'name': name.trim(),
      // A required key that must be null while no category callable exists
      // (contract gap G4).
      'categoryId': null,
      'accessMode': restricted ? 'restricted' : 'members',
      if (mode != null)
        'experience': kind == ServerChannelKind.stage
            ? 'broadcast'
            : 'community',
      if (mode != null) 'mediaMode': mode.name,
    };
  }
}

@immutable
class ServerChannelCreationResult {
  const ServerChannelCreationResult({
    required this.serverId,
    required this.channelId,
    this.roomId,
  });

  final String serverId;
  final String channelId;
  final String? roomId;

  factory ServerChannelCreationResult.fromMap(Map<Object?, Object?> data) {
    final channelId = serverString(data['channelId']);
    if (channelId == null) {
      throw const FormatException('Incomplete channel creation receipt.');
    }
    return ServerChannelCreationResult(
      serverId: serverString(data['serverId']) ?? '',
      channelId: channelId,
      roomId: serverString(data['roomId']),
    );
  }
}
