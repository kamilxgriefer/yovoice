import 'package:cloud_firestore/cloud_firestore.dart';

class ServerFamilyMemoryAsset {
  const ServerFamilyMemoryAsset({
    required this.storagePath,
    required this.generation,
    required this.contentType,
    required this.size,
    this.durationMs,
  });

  final String storagePath;
  final String generation;
  final String contentType;
  final int size;
  final int? durationMs;

  static ServerFamilyMemoryAsset parse(Object? raw, {required bool voice}) {
    if (raw is! Map) {
      throw const FormatException('Family Memory asset is malformed.');
    }
    final data = Map<String, dynamic>.from(raw);
    final path = (data['storagePath'] as String?)?.trim() ?? '';
    final generation = (data['generation'] as String?)?.trim() ?? '';
    final contentType = (data['contentType'] as String?)?.trim() ?? '';
    final size = data['size'];
    final durationMs = data['durationMs'];
    final typeAllowed = voice
        ? contentType == 'audio/mp4'
        : const {'image/jpeg', 'image/png', 'image/webp'}.contains(contentType);
    if (path.isEmpty ||
        path.contains('..') ||
        !RegExp(r'^[0-9]{1,30}$').hasMatch(generation) ||
        !typeAllowed ||
        size is! int ||
        size < (voice ? 1024 : 128) ||
        size > 8 * 1024 * 1024 ||
        (voice &&
            (durationMs is! int || durationMs < 1000 || durationMs > 30000))) {
      throw const FormatException('Family Memory asset is malformed.');
    }
    return ServerFamilyMemoryAsset(
      storagePath: path,
      generation: generation,
      contentType: contentType,
      size: size,
      durationMs: voice ? durationMs as int : null,
    );
  }
}

class ServerFamilyMemory {
  const ServerFamilyMemory({
    required this.id,
    required this.serverId,
    required this.channelId,
    required this.authorId,
    required this.authorDisplayName,
    required this.caption,
    required this.photo,
    required this.voice,
    required this.revision,
    required this.createdAt,
  });

  final String id;
  final String serverId;
  final String channelId;
  final String authorId;
  final String authorDisplayName;
  final String caption;
  final ServerFamilyMemoryAsset photo;
  final ServerFamilyMemoryAsset voice;
  final int revision;
  final DateTime createdAt;

  factory ServerFamilyMemory.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required String serverId,
    required String channelId,
  }) {
    final data = document.data();
    if (data == null) {
      throw const FormatException('Family Memory is unavailable.');
    }
    final memoryId = (data['memoryId'] as String?)?.trim() ?? '';
    final authorId = (data['authorId'] as String?)?.trim() ?? '';
    final authorName = (data['authorDisplayName'] as String?)?.trim() ?? '';
    final caption = (data['caption'] as String?)?.trim() ?? '';
    final revision = data['revision'];
    final createdAt = data['createdAt'];
    if (data['schemaVersion'] != 1 ||
        data['memoryKind'] != 'familyMemory' ||
        data['status'] != 'published' ||
        data['serverId'] != serverId ||
        data['clubId'] != serverId ||
        data['channelId'] != channelId ||
        memoryId != document.id ||
        memoryId.isEmpty ||
        memoryId.contains('/') ||
        authorId.isEmpty ||
        authorId.contains('/') ||
        authorName.isEmpty ||
        caption.length > 500 ||
        revision is! int ||
        revision < 1 ||
        createdAt is! Timestamp) {
      throw const FormatException('Family Memory is malformed.');
    }
    return ServerFamilyMemory(
      id: memoryId,
      serverId: serverId,
      channelId: channelId,
      authorId: authorId,
      authorDisplayName: authorName,
      caption: caption,
      photo: ServerFamilyMemoryAsset.parse(data['photo'], voice: false),
      voice: ServerFamilyMemoryAsset.parse(data['voice'], voice: true),
      revision: revision,
      createdAt: createdAt.toDate(),
    );
  }
}

class ServerFamilyMemoryMediaAsset {
  const ServerFamilyMemoryMediaAsset({
    required this.url,
    required this.generation,
    required this.contentType,
    required this.size,
    this.durationMs,
  });

  final Uri url;
  final String generation;
  final String contentType;
  final int size;
  final int? durationMs;
}

class ServerFamilyMemoryMediaAccess {
  const ServerFamilyMemoryMediaAccess({
    required this.serverId,
    required this.channelId,
    required this.memoryId,
    required this.expiresAt,
    required this.photo,
    required this.voice,
  });

  final String serverId;
  final String channelId;
  final String memoryId;
  final DateTime expiresAt;
  final ServerFamilyMemoryMediaAsset photo;
  final ServerFamilyMemoryMediaAsset voice;
}
