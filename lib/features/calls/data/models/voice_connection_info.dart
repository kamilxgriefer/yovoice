class VoiceConnectionInfo {
  const VoiceConnectionInfo({
    required this.serverUrl,
    required this.participantToken,
  });

  final String serverUrl;
  final String participantToken;

  factory VoiceConnectionInfo.fromMap(Map<String, dynamic> map) {
    final serverUrl = map['serverUrl'] as String?;
    final participantToken = map['participantToken'] as String?;

    if (serverUrl == null ||
        serverUrl.isEmpty ||
        participantToken == null ||
        participantToken.isEmpty) {
      throw const FormatException('The voice server returned invalid data.');
    }

    return VoiceConnectionInfo(
      serverUrl: serverUrl,
      participantToken: participantToken,
    );
  }
}
