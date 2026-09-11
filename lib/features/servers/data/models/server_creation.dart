import 'server_type.dart';

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
