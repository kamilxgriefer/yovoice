/// Canonical public links into the Servers product surface.
library;

const serverLinkHost = 'app.yovoice.app';

final RegExp _serverLinkId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

const Set<String> _legacyServerLinkHosts = <String>{
  'yovoice.app',
  'www.yovoice.app',
  serverLinkHost,
};

bool isSafeServerLinkId(String value) => _serverLinkId.hasMatch(value);

class ServerLinkTarget {
  const ServerLinkTarget({required this.serverId, this.channelId});

  final String serverId;
  final String? channelId;

  @override
  bool operator ==(Object other) =>
      other is ServerLinkTarget &&
      other.serverId == serverId &&
      other.channelId == channelId;

  @override
  int get hashCode => Object.hash(serverId, channelId);
}

/// Builds the only Server link shape emitted by the current application.
///
/// A channel is optional because sharing a server header should open its
/// normal default surface, while sharing from a channel can retain context.
Uri buildServerLink(String serverId, {String? channelId}) {
  if (!isSafeServerLinkId(serverId)) {
    throw ArgumentError.value(
      serverId,
      'serverId',
      'Invalid Server identifier.',
    );
  }
  if (channelId != null && !isSafeServerLinkId(channelId)) {
    throw ArgumentError.value(
      channelId,
      'channelId',
      'Invalid Server channel identifier.',
    );
  }
  return Uri.https(serverLinkHost, '/', <String, String>{
    'server': serverId,
    'channel': ?channelId,
  });
}

/// Parses exactly the public Server link contract.
///
/// Credentials, ports, fragments, duplicate values, unknown parameters and
/// malformed identifiers fail closed. Legacy links are handled separately so
/// accepting an old contract can never weaken this canonical parser.
ServerLinkTarget? parseServerLink(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.host.toLowerCase() != serverLinkHost ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.path != '/' ||
      uri.hasFragment ||
      uri.toString().length > 512) {
    return null;
  }

  Map<String, List<String>> parameters;
  try {
    parameters = uri.queryParametersAll;
  } on FormatException {
    return null;
  }
  if (parameters.isEmpty || parameters.length > 2) return null;

  final serverIds = parameters['server'];
  if (serverIds == null ||
      serverIds.length != 1 ||
      !isSafeServerLinkId(serverIds.single)) {
    return null;
  }

  final channelIds = parameters['channel'];
  if (channelIds != null &&
      (channelIds.length != 1 || !isSafeServerLinkId(channelIds.single))) {
    return null;
  }
  if (parameters.keys.any((key) => key != 'server' && key != 'channel')) {
    return null;
  }

  return ServerLinkTarget(
    serverId: serverIds.single,
    channelId: channelIds?.single,
  );
}

/// Reads the historic `?club=` contract without generating it.
///
/// Existing invitations keep working, but always resolve into the Server
/// facade. The legacy parser intentionally stays exact and accepts no extra
/// parameters, path, credentials, port or fragment.
String? parseLegacyClubServerLink(Uri uri) {
  if (uri.scheme != 'https' ||
      !_legacyServerLinkHosts.contains(uri.host.toLowerCase()) ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.path != '/' ||
      uri.hasFragment ||
      uri.toString().length > 512) {
    return null;
  }
  Map<String, List<String>> parameters;
  try {
    parameters = uri.queryParametersAll;
  } on FormatException {
    return null;
  }
  if (parameters.length != 1) return null;
  final ids = parameters['club'];
  if (ids == null || ids.length != 1 || !isSafeServerLinkId(ids.single)) {
    return null;
  }
  return ids.single;
}
