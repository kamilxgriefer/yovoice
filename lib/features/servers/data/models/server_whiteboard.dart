import 'package:cloud_firestore/cloud_firestore.dart';

enum ServerWhiteboardColor { ink, red, orange, green, blue, purple, white }

class ServerWhiteboardPoint {
  const ServerWhiteboardPoint(this.x, this.y);

  final double x;
  final double y;

  Map<String, double> toMap() => {'x': x, 'y': y};
}

/// Revision metadata used to clear the board atomically with its strokes.
/// An absent document is the canonical untouched board at revision zero.
class ServerWhiteboardState {
  const ServerWhiteboardState({
    required this.serverId,
    required this.channelId,
    required this.generation,
    required this.revision,
    required this.strokeCount,
    required this.nextSequence,
    this.clearedAt,
    this.clearedById,
  });

  final String serverId;
  final String channelId;
  final int generation;
  final int revision;
  final int strokeCount;
  final int nextSequence;
  final DateTime? clearedAt;
  final String? clearedById;

  bool get isEmpty => strokeCount == 0;

  factory ServerWhiteboardState.empty({
    required String serverId,
    required String channelId,
  }) => ServerWhiteboardState(
    serverId: serverId,
    channelId: channelId,
    generation: 1,
    revision: 0,
    strokeCount: 0,
    nextSequence: 1,
  );

  factory ServerWhiteboardState.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required String serverId,
    required String channelId,
  }) {
    final data = document.data();
    final generation = data?['generation'];
    final revision = data?['revision'];
    final strokeCount = data?['strokeCount'];
    final nextSequence = data?['nextSequence'];
    final clearedAt = _date(data?['clearedAt']);
    final clearedById = _safeId(data?['clearedById']);
    final clearedShape = (data?['clearedAt'] == null)
        ? (data?['clearedById'] == null)
        : clearedAt != null && clearedById != null;
    if (data == null ||
        document.id != 'main' ||
        data['schemaVersion'] != 1 ||
        data['serverId'] != serverId ||
        data['channelId'] != channelId ||
        data['stateId'] != 'main' ||
        generation is! int ||
        generation < 1 ||
        revision is! int ||
        revision < 1 ||
        strokeCount is! int ||
        strokeCount < 0 ||
        strokeCount > 180 ||
        nextSequence is! int ||
        nextSequence < 1 ||
        _date(data['updatedAt']) == null ||
        !clearedShape) {
      throw const FormatException('Unsupported company whiteboard state.');
    }
    return ServerWhiteboardState(
      serverId: serverId,
      channelId: channelId,
      generation: generation,
      revision: revision,
      strokeCount: strokeCount,
      nextSequence: nextSequence,
      clearedAt: clearedAt?.toUtc(),
      clearedById: clearedById,
    );
  }
}

class ServerWhiteboardStroke {
  const ServerWhiteboardStroke({
    required this.id,
    required this.serverId,
    required this.channelId,
    required this.authorId,
    required this.generation,
    required this.sequence,
    required this.revision,
    required this.color,
    required this.lineWidth,
    required this.points,
    required this.createdAt,
  });

  final String id;
  final String serverId;
  final String channelId;
  final String authorId;
  final int generation;
  final int sequence;
  final int revision;
  final ServerWhiteboardColor color;
  final int lineWidth;
  final List<ServerWhiteboardPoint> points;
  final DateTime createdAt;

  factory ServerWhiteboardStroke.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document, {
    required String serverId,
    required String channelId,
    required int generation,
  }) {
    final data = document.data();
    final id = _safeId(document.id);
    final authorId = _safeId(data?['authorId']);
    final sequence = data?['sequence'];
    final revision = data?['revision'];
    final lineWidth = data?['lineWidth'];
    final color = ServerWhiteboardColor.values
        .where((candidate) => candidate.name == data?['color'])
        .firstOrNull;
    final createdAt = _date(data?['createdAt']);
    final rawPoints = data?['points'];
    final points = rawPoints is List
        ? rawPoints.map(_point).whereType<ServerWhiteboardPoint>().toList()
        : const <ServerWhiteboardPoint>[];
    if (data == null ||
        id == null ||
        data['schemaVersion'] != 1 ||
        data['serverId'] != serverId ||
        data['channelId'] != channelId ||
        data['strokeId'] != document.id ||
        data['strokeKind'] != 'polyline' ||
        authorId == null ||
        data['generation'] != generation ||
        sequence is! int ||
        sequence < 1 ||
        revision != 1 ||
        color == null ||
        lineWidth is! int ||
        lineWidth < 1 ||
        lineWidth > 16 ||
        rawPoints is! List ||
        rawPoints.length < 2 ||
        rawPoints.length > 64 ||
        points.length != rawPoints.length ||
        createdAt == null) {
      throw const FormatException('Unsupported company whiteboard stroke.');
    }
    return ServerWhiteboardStroke(
      id: id,
      serverId: serverId,
      channelId: channelId,
      authorId: authorId,
      generation: generation,
      sequence: sequence,
      revision: revision as int,
      color: color,
      lineWidth: lineWidth,
      points: List.unmodifiable(points),
      createdAt: createdAt.toUtc(),
    );
  }
}

class ServerWhiteboardSnapshot {
  const ServerWhiteboardSnapshot({required this.state, required this.strokes});

  final ServerWhiteboardState state;
  final List<ServerWhiteboardStroke> strokes;

  ServerWhiteboardStroke? lastOwnedBy(String userId) {
    for (final stroke in strokes.reversed) {
      if (stroke.authorId == userId) return stroke;
    }
    return null;
  }
}

ServerWhiteboardPoint? _point(Object? value) {
  if (value is! Map ||
      value.length != 2 ||
      !value.containsKey('x') ||
      !value.containsKey('y')) {
    return null;
  }
  final x = value['x'];
  final y = value['y'];
  if (x is! num ||
      y is! num ||
      !x.isFinite ||
      !y.isFinite ||
      x < 0 ||
      x > 1 ||
      y < 0 ||
      y > 1) {
    return null;
  }
  return ServerWhiteboardPoint(x.toDouble(), y.toDouble());
}

DateTime? _date(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  _ => null,
};

String? _safeId(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 128 ||
      value.contains('/')) {
    return null;
  }
  return value;
}
