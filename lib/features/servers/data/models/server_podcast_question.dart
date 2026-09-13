import 'package:cloud_firestore/cloud_firestore.dart';

enum ServerPodcastQuestionStatus { queued, onAir }

/// One listener question in a podcast server's dedicated Questions channel.
///
/// Votes and on-air state are written only by callables. This parser fails
/// closed when the aggregate or its parent binding is not canonical.
class ServerPodcastQuestion {
  const ServerPodcastQuestion({
    required this.id,
    required this.serverId,
    required this.channelId,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.status,
    required this.voteCount,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
    this.onAirAt,
    this.onAirById,
  });

  final String id;
  final String serverId;
  final String channelId;
  final String authorId;
  final String authorName;
  final String body;
  final ServerPodcastQuestionStatus status;
  final int voteCount;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? onAirAt;
  final String? onAirById;

  bool get isOnAir => status == ServerPodcastQuestionStatus.onAir;

  factory ServerPodcastQuestion.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required String serverId,
    required String channelId,
  }) {
    final data = document.data();
    final id = document.id;
    final authorId = _text(data?['authorId'], maxLength: 128, safeId: true);
    final authorName = _text(data?['authorName'], maxLength: 120);
    final body = _text(data?['body'], maxLength: 500);
    final voteCount = data?['voteCount'];
    final revision = data?['revision'];
    final createdAt = _date(data?['createdAt']);
    final updatedAt = _date(data?['updatedAt']);
    final onAirAt = _date(data?['onAirAt']);
    final onAirById = _text(data?['onAirById'], maxLength: 128, safeId: true);
    final status = switch (data?['status']) {
      'queued' => ServerPodcastQuestionStatus.queued,
      'onAir' => ServerPodcastQuestionStatus.onAir,
      _ => null,
    };
    final onAirShape = status == ServerPodcastQuestionStatus.onAir
        ? onAirAt != null && onAirById != null
        : data?['onAirAt'] == null && data?['onAirById'] == null;
    if (data == null ||
        data['schemaVersion'] != 1 ||
        data['serverId'] != serverId ||
        data['channelId'] != channelId ||
        data['questionId'] != id ||
        data['questionKind'] != 'podcastQuestion' ||
        _text(id, maxLength: 128, safeId: true) == null ||
        authorId == null ||
        authorName == null ||
        body == null ||
        status == null ||
        !onAirShape ||
        voteCount is! int ||
        voteCount < 0 ||
        revision is! int ||
        revision < 1 ||
        createdAt == null ||
        updatedAt == null ||
        updatedAt.isBefore(createdAt)) {
      throw const FormatException('Unsupported podcast question.');
    }
    return ServerPodcastQuestion(
      id: id,
      serverId: serverId,
      channelId: channelId,
      authorId: authorId,
      authorName: authorName,
      body: body,
      status: status,
      voteCount: voteCount,
      revision: revision,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      onAirAt: onAirAt?.toUtc(),
      onAirById: onAirById,
    );
  }
}

DateTime? _date(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  _ => null,
};

String? _text(Object? value, {required int maxLength, bool safeId = false}) {
  if (value is! String || value != value.trim()) return null;
  if (value.isEmpty ||
      value.length > maxLength ||
      (safeId && value.contains('/'))) {
    return null;
  }
  if (RegExp(
    r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]',
  ).hasMatch(value)) {
    return null;
  }
  return value;
}
