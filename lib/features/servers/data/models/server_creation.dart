import 'package:cloud_functions/cloud_functions.dart';

import 'server_type.dart';

/// Why a creation attempt produced no server, in terms a person can act on.
///
/// A flow that answers every failure with one sentence teaches people that
/// creating a server does not work. Each value below has a different honest
/// next step, so each gets its own state — and none of them is ever presented
/// as a success.
///
/// The reviewed `functions/servers/creation.js` raises exactly five codes of
/// its own: `invalid-argument`, `permission-denied`, `failed-precondition`,
/// `resource-exhausted` and `data-loss`. Every one of them has a named state
/// here, because a refusal that fell through to a generic "try again" would
/// offer a retry that can never succeed while every field stays locked.
enum ServerCreationFailure {
  /// The V1 callables are not registered in this environment.
  ///
  /// `YOVOICE_SERVERS_V1` is absent from `functions/.env`, so `index.js`
  /// exports no `createServerV1` and the call reaches no endpoint (ADR-176).
  /// The reviewed factory never raises `not-found` itself, so these three
  /// codes unambiguously mean "there is no such endpoint here".
  /// **Nothing was created.** Retrying the identical request is safe but
  /// cannot succeed until the gate is opened server-side.
  unavailable,

  /// The attempt did not complete: offline, timed out, or the backend was
  /// unreachable. The server may or may not have committed, which is exactly
  /// why the identical `requestId` must be resent rather than a fresh one.
  offline,

  /// This owner already holds their whole free server allowance.
  capacityReached,

  /// Signed out, or the session is no longer valid.
  signedOut,

  /// `invalid-argument`: the payload itself was refused before anything was
  /// written. This is the one code where editing helps, so the form unlocks
  /// and the pending submission is discarded — a corrected payload is a new
  /// request and gets a fresh `requestId`; changing the payload under the old
  /// id would never have been a retry.
  rejected,

  /// `failed-precondition`: something that already exists forbids this
  /// server — a second family server, for one (`FAMILY_SERVER_LIMIT` is 1).
  /// Nothing was created and no resend of this payload can succeed.
  precondition,

  /// `permission-denied`: this account may not create servers right now.
  /// Nothing was created; resending cannot change the answer.
  denied,

  /// `data-loss`: the saved server data the backend found is incomplete and
  /// cannot be built on. Nothing new was created; this needs a fix on the
  /// server side, not another attempt from here.
  lost,

  /// Anything else. The generic message plus a retry is the honest answer.
  unknown;

  /// Whether resending the identical request could still succeed.
  bool get isRetryable => switch (this) {
    unavailable || offline || unknown => true,
    capacityReached ||
    signedOut ||
    rejected ||
    precondition ||
    denied ||
    lost => false,
  };

  /// Whether the person can fix the payload and submit a corrected, brand-new
  /// request. True only for [rejected]: the backend refused the arguments
  /// themselves, so nothing was committed under the old identity.
  bool get isCorrectable => this == rejected;

  /// Whether no resend of this payload can ever succeed. The submit action is
  /// disarmed and the message names the real next step instead.
  bool get isTerminal => switch (this) {
    capacityReached || signedOut || precondition || denied || lost => true,
    unavailable || offline || rejected || unknown => false,
  };

  /// Whether the backend has definitely answered for this `requestId`, so the
  /// pending record no longer needs to survive the screen.
  ///
  /// `offline`, `unknown` and `signedOut` keep it: the server may have
  /// committed, or may still accept the identical request once the person is
  /// back online or signed in. Everything else was refused before any write.
  bool get resolvesRequest => switch (this) {
    unavailable ||
    capacityReached ||
    rejected ||
    precondition ||
    denied ||
    lost => true,
    offline || unknown || signedOut => false,
  };

  /// Whether this is a missing backend rather than a failed attempt.
  bool get isBackendMissing => this == unavailable;
}

/// Classifies a raw creation error without ever inventing a success.
ServerCreationFailure classifyServerCreationFailure(Object error) {
  if (error is FirebaseFunctionsException) {
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    return switch (error.code) {
      // No endpoint of that name is deployed in this environment.
      'not-found' ||
      'unimplemented' ||
      'no-app' => ServerCreationFailure.unavailable,
      'unavailable' || 'deadline-exceeded' => ServerCreationFailure.offline,
      'unauthenticated' => ServerCreationFailure.signedOut,
      'resource-exhausted' when reason == 'server-capacity-reached' =>
        ServerCreationFailure.capacityReached,
      'invalid-argument' => ServerCreationFailure.rejected,
      'failed-precondition' => ServerCreationFailure.precondition,
      'permission-denied' => ServerCreationFailure.denied,
      'data-loss' => ServerCreationFailure.lost,
      _ => ServerCreationFailure.unknown,
    };
  }
  final raw = error.toString().toLowerCase();
  if (raw.contains('socketexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('network') ||
      raw.contains('connection')) {
    return ServerCreationFailure.offline;
  }
  return ServerCreationFailure.unknown;
}

/// One immutable submission. The same request must survive an uncertain
/// callable response; changing the payload under its ID is never a retry.
class ServerCreationRequest {
  const ServerCreationRequest({
    required this.requestId,
    required this.serverType,
    required this.name,
    required this.description,
    required this.privacy,
    required this.defaultLanguage,
    this.templateVersion = 1,
  });

  final String requestId;
  final ServerType serverType;
  final int templateVersion;
  final String name;
  final String description;
  final ServerPrivacy privacy;
  final String defaultLanguage;

  Map<String, Object> toCallableData() => {
    'requestId': requestId,
    'serverType': serverType.name,
    'templateVersion': templateVersion,
    'name': name,
    'description': description,
    'privacy': privacy.name,
    'defaultLanguage': defaultLanguage,
  };

  /// The inverse of [toCallableData], for a request that outlived its screen.
  ///
  /// Returns null for anything malformed rather than throwing: a corrupt
  /// pending record must fall back to "nothing pending", never crash the
  /// configuration step.
  static ServerCreationRequest? fromCallableData(Object? value) {
    if (value is! Map) return null;
    final requestId = value['requestId'];
    final name = value['name'];
    final description = value['description'];
    final defaultLanguage = value['defaultLanguage'];
    final templateVersion = value['templateVersion'];
    if (requestId is! String ||
        requestId.isEmpty ||
        name is! String ||
        description is! String ||
        defaultLanguage is! String ||
        templateVersion is! int) {
      return null;
    }
    final ServerType serverType;
    final ServerPrivacy privacy;
    try {
      serverType = ServerType.parse(value['serverType']);
      privacy = ServerPrivacy.parse(value['privacy']);
    } on FormatException {
      return null;
    }
    return ServerCreationRequest(
      requestId: requestId,
      serverType: serverType,
      templateVersion: templateVersion,
      name: name,
      description: description,
      privacy: privacy,
      defaultLanguage: defaultLanguage,
    );
  }
}

class ServerCreationResult {
  const ServerCreationResult({
    required this.serverId,
    required this.defaultChannelId,
    required this.channelIds,
    required this.alreadyExisted,
  });

  final String serverId;
  final String defaultChannelId;
  final List<String> channelIds;
  final bool alreadyExisted;

  factory ServerCreationResult.fromMap(Map<Object?, Object?> data) {
    final serverId = data['serverId'];
    final defaultChannelId = data['defaultChannelId'];
    final channelIds = data['channelIds'];
    final existed = data['alreadyExisted'];
    if (serverId is! String ||
        serverId.isEmpty ||
        serverId.contains('/') ||
        defaultChannelId is! String ||
        defaultChannelId.isEmpty ||
        defaultChannelId.contains('/') ||
        channelIds is! List ||
        channelIds.isEmpty ||
        channelIds.any(
          (id) => id is! String || id.isEmpty || id.contains('/'),
        ) ||
        !channelIds.contains(defaultChannelId) ||
        existed is! bool) {
      throw const FormatException('Invalid server creation response.');
    }
    return ServerCreationResult(
      serverId: serverId,
      defaultChannelId: defaultChannelId,
      channelIds: List<String>.unmodifiable(channelIds.cast<String>()),
      alreadyExisted: existed,
    );
  }
}
