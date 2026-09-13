import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum ServerPodcastEpisodeStatus {
  recording,
  processing,
  ready,
  published,
  error;

  static ServerPodcastEpisodeStatus? tryParse(Object? value) => switch (value) {
    'recording' => recording,
    'processing' => processing,
    'ready' => ready,
    'published' => published,
    'error' => error,
    _ => null,
  };
}

enum ServerPodcastProviderStatus {
  pending,
  starting,
  active,
  ending,
  complete,
  failed,
  aborted,
  limitReached,
  unavailable;

  static ServerPodcastProviderStatus? tryParse(Object? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

@immutable
class ServerPodcastEpisodeMedia {
  const ServerPodcastEpisodeMedia({
    required this.storagePath,
    required this.generation,
    required this.contentType,
    required this.size,
    required this.duration,
  });

  final String storagePath;
  final String generation;
  final String contentType;
  final int size;
  final Duration duration;

  static ServerPodcastEpisodeMedia? tryParse(Object? value) {
    if (value is! Map) return null;
    final path = _text(value['storagePath'], maxLength: 512);
    final generation = _text(value['generation'], maxLength: 30);
    final size = value['size'];
    final durationMillis = value['durationMillis'];
    if (path == null ||
        !path.startsWith('server_podcast_episodes/') ||
        generation == null ||
        !RegExp(r'^[0-9]{1,30}$').hasMatch(generation) ||
        value['contentType'] != 'audio/mpeg' ||
        size is! int ||
        size < 1 ||
        size > 2 * 1024 * 1024 * 1024 ||
        durationMillis is! int ||
        durationMillis < 1 ||
        durationMillis > 12 * 60 * 60 * 1000) {
      return null;
    }
    return ServerPodcastEpisodeMedia(
      storagePath: path,
      generation: generation,
      contentType: 'audio/mpeg',
      size: size,
      duration: Duration(milliseconds: durationMillis),
    );
  }
}

@immutable
class ServerPodcastEpisode {
  const ServerPodcastEpisode({
    required this.id,
    required this.serverId,
    required this.channelId,
    required this.studioChannelId,
    required this.sessionId,
    required this.title,
    required this.status,
    required this.providerStatus,
    required this.revision,
    required this.createdById,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
    this.media,
    this.failureCode,
    this.stoppedAt,
    this.readyAt,
    this.publishedAt,
  });

  final String id;
  final String serverId;
  final String channelId;
  final String studioChannelId;
  final String sessionId;
  final String title;
  final ServerPodcastEpisodeStatus status;
  final ServerPodcastProviderStatus providerStatus;
  final int revision;
  final String createdById;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ServerPodcastEpisodeMedia? media;
  final String? failureCode;
  final DateTime? stoppedAt;
  final DateTime? readyAt;
  final DateTime? publishedAt;

  bool get isPlayable =>
      (status == ServerPodcastEpisodeStatus.ready ||
          status == ServerPodcastEpisodeStatus.published) &&
      media != null;

  factory ServerPodcastEpisode.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required String serverId,
    required String channelId,
  }) {
    final data = document.data();
    if (data == null ||
        data['schemaVersion'] != 1 ||
        data['episodeKind'] != 'podcastEpisode' ||
        data['serverId'] != serverId ||
        data['clubId'] != serverId ||
        data['channelId'] != channelId ||
        data['episodeId'] != document.id) {
      throw const FormatException('Unsupported podcast episode.');
    }
    final studioChannelId = _id(data['studioChannelId']);
    final sessionId = _id(data['sessionId']);
    final title = _text(data['title'], maxLength: 120);
    final status = ServerPodcastEpisodeStatus.tryParse(data['status']);
    final provider = ServerPodcastProviderStatus.tryParse(
      data['providerStatus'],
    );
    final revision = data['revision'];
    final createdById = _id(data['createdById']);
    final createdByName = _text(data['createdByName'], maxLength: 120);
    final outputPath = _text(data['outputPath'], maxLength: 512);
    final expectedPath =
        'server_podcast_episodes/$serverId/$channelId/${document.id}.mp3';
    final createdAt = _date(data['createdAt']);
    final updatedAt = _date(data['updatedAt']);
    final stoppedAt = _nullableDate(data['stoppedAt']);
    final readyAt = _nullableDate(data['readyAt']);
    final publishedAt = _nullableDate(data['publishedAt']);
    final failureCode = data['failureCode'] == null
        ? null
        : _text(data['failureCode'], maxLength: 120);
    final media = data['media'] == null
        ? null
        : ServerPodcastEpisodeMedia.tryParse(data['media']);
    final validLifecycle = switch (status) {
      ServerPodcastEpisodeStatus.recording =>
        const {
              ServerPodcastProviderStatus.pending,
              ServerPodcastProviderStatus.starting,
              ServerPodcastProviderStatus.active,
            }.contains(provider) &&
            media == null &&
            failureCode == null &&
            stoppedAt == null &&
            readyAt == null &&
            publishedAt == null,
      ServerPodcastEpisodeStatus.processing =>
        const {
              ServerPodcastProviderStatus.ending,
              ServerPodcastProviderStatus.complete,
            }.contains(provider) &&
            media == null &&
            failureCode == null &&
            stoppedAt != null &&
            readyAt == null &&
            publishedAt == null,
      ServerPodcastEpisodeStatus.ready =>
        provider == ServerPodcastProviderStatus.complete &&
            media != null &&
            failureCode == null &&
            stoppedAt != null &&
            readyAt != null &&
            publishedAt == null,
      ServerPodcastEpisodeStatus.published =>
        provider == ServerPodcastProviderStatus.complete &&
            media != null &&
            failureCode == null &&
            stoppedAt != null &&
            readyAt != null &&
            publishedAt != null,
      ServerPodcastEpisodeStatus.error =>
        const {
              ServerPodcastProviderStatus.failed,
              ServerPodcastProviderStatus.aborted,
              ServerPodcastProviderStatus.limitReached,
              ServerPodcastProviderStatus.unavailable,
            }.contains(provider) &&
            media == null &&
            failureCode != null &&
            readyAt == null &&
            publishedAt == null,
      null => false,
    };
    if (studioChannelId == null ||
        sessionId == null ||
        title == null ||
        provider == null ||
        revision is! int ||
        revision < 1 ||
        createdById == null ||
        createdByName == null ||
        outputPath != expectedPath ||
        createdAt == null ||
        updatedAt == null ||
        (data['media'] != null && media == null) ||
        (media != null && media.storagePath != outputPath) ||
        (data['failureCode'] != null && failureCode == null) ||
        !validLifecycle) {
      throw const FormatException('Unsupported podcast episode.');
    }
    return ServerPodcastEpisode(
      id: document.id,
      serverId: serverId,
      channelId: channelId,
      studioChannelId: studioChannelId,
      sessionId: sessionId,
      title: title,
      status: status!,
      providerStatus: provider,
      revision: revision,
      createdById: createdById,
      createdByName: createdByName,
      createdAt: createdAt,
      updatedAt: updatedAt,
      media: media,
      failureCode: failureCode,
      stoppedAt: stoppedAt,
      readyAt: readyAt,
      publishedAt: publishedAt,
    );
  }
}

@immutable
class ServerPodcastRecordingState {
  const ServerPodcastRecordingState({
    required this.serverId,
    required this.studioChannelId,
    required this.channelId,
    required this.episodeId,
    required this.sessionId,
    required this.title,
    required this.status,
    required this.providerStatus,
    required this.episodeRevision,
    required this.updatedAt,
  });

  final String serverId;
  final String studioChannelId;
  final String channelId;
  final String episodeId;
  final String sessionId;
  final String title;
  final ServerPodcastEpisodeStatus status;
  final ServerPodcastProviderStatus providerStatus;
  final int episodeRevision;
  final DateTime updatedAt;

  bool get isActive =>
      status == ServerPodcastEpisodeStatus.recording ||
      status == ServerPodcastEpisodeStatus.processing;

  factory ServerPodcastRecordingState.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required String serverId,
    required String studioChannelId,
  }) {
    final data = document.data();
    final channelId = _id(data?['channelId']);
    final episodeId = _id(data?['episodeId']);
    final sessionId = _id(data?['sessionId']);
    final title = _text(data?['title'], maxLength: 120);
    final status = ServerPodcastEpisodeStatus.tryParse(data?['status']);
    final provider = ServerPodcastProviderStatus.tryParse(
      data?['providerStatus'],
    );
    final revision = data?['episodeRevision'];
    final updatedAt = _date(data?['updatedAt']);
    if (document.id != 'main' ||
        data?['schemaVersion'] != 1 ||
        data?['kind'] != 'podcastRecordingState' ||
        data?['serverId'] != serverId ||
        data?['studioChannelId'] != studioChannelId ||
        channelId == null ||
        episodeId == null ||
        sessionId == null ||
        title == null ||
        status == null ||
        provider == null ||
        revision is! int ||
        revision < 1 ||
        updatedAt == null) {
      throw const FormatException('Unsupported podcast recording state.');
    }
    return ServerPodcastRecordingState(
      serverId: serverId,
      studioChannelId: studioChannelId,
      channelId: channelId,
      episodeId: episodeId,
      sessionId: sessionId,
      title: title,
      status: status,
      providerStatus: provider,
      episodeRevision: revision,
      updatedAt: updatedAt,
    );
  }
}

@immutable
class ServerPodcastEpisodeReceipt {
  const ServerPodcastEpisodeReceipt({
    required this.serverId,
    required this.channelId,
    required this.studioChannelId,
    required this.episodeId,
    required this.sessionId,
    required this.status,
    required this.providerStatus,
    required this.revision,
  });

  final String serverId;
  final String channelId;
  final String studioChannelId;
  final String episodeId;
  final String sessionId;
  final ServerPodcastEpisodeStatus status;
  final ServerPodcastProviderStatus providerStatus;
  final int revision;

  factory ServerPodcastEpisodeReceipt.fromMap(Map<Object?, Object?> data) {
    final serverId = _id(data['serverId']);
    final channelId = _id(data['channelId']);
    final studioChannelId = _id(data['studioChannelId']);
    final episodeId = _id(data['episodeId']);
    final sessionId = _id(data['sessionId']);
    final status = ServerPodcastEpisodeStatus.tryParse(data['status']);
    final provider = ServerPodcastProviderStatus.tryParse(
      data['providerStatus'],
    );
    final revision = data['revision'];
    if (data['schemaVersion'] != 1 ||
        serverId == null ||
        channelId == null ||
        studioChannelId == null ||
        episodeId == null ||
        sessionId == null ||
        status == null ||
        provider == null ||
        revision is! int ||
        revision < 1) {
      throw const FormatException('Incomplete podcast episode receipt.');
    }
    return ServerPodcastEpisodeReceipt(
      serverId: serverId,
      channelId: channelId,
      studioChannelId: studioChannelId,
      episodeId: episodeId,
      sessionId: sessionId,
      status: status,
      providerStatus: provider,
      revision: revision,
    );
  }
}

@immutable
class ServerPodcastEpisodeAccess {
  const ServerPodcastEpisodeAccess({
    required this.serverId,
    required this.channelId,
    required this.episodeId,
    required this.title,
    required this.url,
    required this.expiresAt,
    required this.media,
  });

  final String serverId;
  final String channelId;
  final String episodeId;
  final String title;
  final Uri url;
  final DateTime expiresAt;
  final ServerPodcastEpisodeMedia media;

  factory ServerPodcastEpisodeAccess.fromMap(Map<Object?, Object?> data) {
    final serverId = _id(data['serverId']);
    final channelId = _id(data['channelId']);
    final episodeId = _id(data['episodeId']);
    final title = _text(data['title'], maxLength: 120);
    final expires = data['expiresAtMillis'];
    final rawMedia = data['media'];
    final media = ServerPodcastEpisodeMedia.tryParse(rawMedia);
    final rawUrl = rawMedia is Map ? rawMedia['url'] : null;
    final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    if (data['schemaVersion'] != 1 ||
        serverId == null ||
        channelId == null ||
        episodeId == null ||
        title == null ||
        expires is! int ||
        expires <= 0 ||
        media == null ||
        url == null ||
        url.scheme != 'https' ||
        url.host != 'storage.googleapis.com' ||
        url.userInfo.isNotEmpty ||
        url.hasPort) {
      throw const FormatException('Incomplete podcast episode access.');
    }
    return ServerPodcastEpisodeAccess(
      serverId: serverId,
      channelId: channelId,
      episodeId: episodeId,
      title: title,
      url: url,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expires, isUtc: true),
      media: media,
    );
  }
}

String? _id(Object? value) {
  final parsed = _text(value, maxLength: 128);
  return parsed != null && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(parsed)
      ? parsed
      : null;
}

String? _text(Object? value, {required int maxLength}) {
  if (value is! String ||
      value.trim() != value ||
      value.isEmpty ||
      value.length > maxLength) {
    return null;
  }
  return value;
}

DateTime? _date(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate().toUtc(),
  DateTime date => date.toUtc(),
  _ => null,
};

DateTime? _nullableDate(Object? value) => value == null ? null : _date(value);
