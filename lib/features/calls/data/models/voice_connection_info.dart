class VoiceConnectionInfo {
  const VoiceConnectionInfo({
    required this.serverUrl,
    required this.participantToken,
    required this.canPublish,
  });

  final String serverUrl;
  final String participantToken;
  final bool canPublish;

  static const allowedServerHosts = <String>{'yovoice-3f7j9fb7.livekit.cloud'};

  factory VoiceConnectionInfo.fromMap(Map<String, dynamic> map) {
    final serverUrl = map['serverUrl'] as String?;
    final participantToken = map['participantToken'] as String?;
    final permissions = map['permissions'];
    final canPublishValue = permissions is Map
        ? permissions['canPublish']
        : null;
    final canPublish = canPublishValue is bool ? canPublishValue : false;

    final normalizedUrl = serverUrl?.trim();
    final normalizedToken = participantToken?.trim();
    final uri = normalizedUrl == null ? null : Uri.tryParse(normalizedUrl);

    if (normalizedUrl == null ||
        normalizedUrl.isEmpty ||
        participantToken == null ||
        normalizedToken == null ||
        normalizedToken.isEmpty ||
        permissions is! Map ||
        canPublishValue is! bool ||
        uri == null ||
        uri.scheme != 'wss' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.host.isEmpty ||
        !allowedServerHosts.contains(uri.host.toLowerCase()) ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException('The voice server returned invalid data.');
    }

    return VoiceConnectionInfo(
      serverUrl: normalizedUrl,
      participantToken: normalizedToken,
      canPublish: canPublish,
    );
  }
}
