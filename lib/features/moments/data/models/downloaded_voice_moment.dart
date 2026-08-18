import 'dart:convert';

class DownloadedVoiceMoment {
  static const int maximumManifestItems = 250;
  static const int maximumManifestBytes = 512 * 1024;

  const DownloadedVoiceMoment({
    required this.momentId,
    required this.authorId,
    required this.authorName,
    required this.caption,
    required this.durationSeconds,
    required this.byteLength,
    required this.downloadedAt,
  });

  final String momentId;
  final String authorId;
  final String authorName;
  final String caption;
  final int durationSeconds;
  final int byteLength;
  final DateTime downloadedAt;

  String get durationLabel {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, Object> toJson() => <String, Object>{
    'schemaVersion': 1,
    'momentId': momentId,
    'authorId': authorId,
    'authorName': authorName,
    'caption': caption,
    'durationSeconds': durationSeconds,
    'byteLength': byteLength,
    'downloadedAt': downloadedAt.toUtc().toIso8601String(),
  };

  static DownloadedVoiceMoment? tryParse(Object? value) {
    if (value is! Map) return null;
    final data = Map<String, Object?>.from(value);
    if (data.length != 8 ||
        data['schemaVersion'] != 1 ||
        data['momentId'] is! String ||
        data['authorId'] is! String ||
        data['authorName'] is! String ||
        data['caption'] is! String ||
        data['durationSeconds'] is! int ||
        data['byteLength'] is! int ||
        data['downloadedAt'] is! String) {
      return null;
    }
    final momentId = data['momentId']! as String;
    final authorId = data['authorId']! as String;
    final authorName = (data['authorName']! as String).trim();
    final caption = data['caption']! as String;
    final durationSeconds = data['durationSeconds']! as int;
    final byteLength = data['byteLength']! as int;
    final downloadedAt = DateTime.tryParse(data['downloadedAt']! as String);
    if (momentId.trim().isEmpty ||
        momentId.contains('/') ||
        utf8.encode(momentId).length > 1500 ||
        authorId.trim().isEmpty ||
        utf8.encode(authorId).length > 1500 ||
        authorName.isEmpty ||
        authorName.length > 80 ||
        caption.length > 500 ||
        durationSeconds < 1 ||
        durationSeconds > 60 ||
        byteLength < 1024 ||
        byteLength > 12 * 1024 * 1024 ||
        downloadedAt == null) {
      return null;
    }
    return DownloadedVoiceMoment(
      momentId: momentId,
      authorId: authorId,
      authorName: authorName,
      caption: caption,
      durationSeconds: durationSeconds,
      byteLength: byteLength,
      downloadedAt: downloadedAt.toUtc(),
    );
  }

  static List<DownloadedVoiceMoment> decodeManifest(String source) {
    try {
      if (utf8.encode(source).length > maximumManifestBytes) {
        return const <DownloadedVoiceMoment>[];
      }
      final decoded = jsonDecode(source);
      if (decoded is! Map ||
          decoded.length != 2 ||
          decoded['schemaVersion'] != 1 ||
          decoded['items'] is! List ||
          (decoded['items']! as List).length > maximumManifestItems) {
        return const <DownloadedVoiceMoment>[];
      }
      return (decoded['items']! as List)
          .map(tryParse)
          .whereType<DownloadedVoiceMoment>()
          .toList(growable: false);
    } catch (_) {
      return const <DownloadedVoiceMoment>[];
    }
  }

  static String encodeManifest(List<DownloadedVoiceMoment> items) {
    if (items.length > maximumManifestItems) {
      throw const FormatException('Offline manifest has too many items.');
    }
    final encoded = jsonEncode(<String, Object>{
      'schemaVersion': 1,
      'items': items.map((item) => item.toJson()).toList(growable: false),
    });
    if (utf8.encode(encoded).length > maximumManifestBytes) {
      throw const FormatException('Offline manifest is too large.');
    }
    return encoded;
  }
}
