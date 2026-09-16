import 'package:cloud_firestore/cloud_firestore.dart';

enum ServerWhiteboardColor { ink, red, orange, green, blue, purple, white }

class ServerWhiteboardPoint {
  const ServerWhiteboardPoint(this.x, this.y);

  final double x;
  final double y;

  Map<String, double> toMap() => {'x': x, 'y': y};
}

/// Reduces a pointer-rate path to the callable's bounded polyline contract
/// without ever mutating the path that is still under the user's finger.
///
/// The selector repeatedly keeps the point with the largest geometric error
/// inside every remaining segment. Corners therefore survive before points on
/// an already-straight run, unlike replacing the last slot of a fixed buffer.
List<ServerWhiteboardPoint> simplifyServerWhiteboardPoints(
  List<ServerWhiteboardPoint> points, {
  int maximumPoints = 64,
}) {
  if (maximumPoints < 2) {
    throw ArgumentError.value(maximumPoints, 'maximumPoints');
  }
  if (points.length <= maximumPoints) {
    return List<ServerWhiteboardPoint>.unmodifiable(points);
  }
  final selected = <int>{0, points.length - 1};
  final segments = <_WhiteboardSimplificationSegment>[
    _WhiteboardSimplificationSegment.between(points, 0, points.length - 1),
  ];
  while (selected.length < maximumPoints && segments.isNotEmpty) {
    var bestPosition = 0;
    for (var index = 1; index < segments.length; index++) {
      final candidate = segments[index];
      final best = segments[bestPosition];
      if (candidate.errorSquared > best.errorSquared ||
          (candidate.errorSquared == best.errorSquared &&
              candidate.span > best.span)) {
        bestPosition = index;
      }
    }
    final segment = segments.removeAt(bestPosition);
    final pivot = segment.pivot;
    if (pivot <= segment.start ||
        pivot >= segment.end ||
        !selected.add(pivot)) {
      continue;
    }
    if (pivot - segment.start > 1) {
      segments.add(
        _WhiteboardSimplificationSegment.between(points, segment.start, pivot),
      );
    }
    if (segment.end - pivot > 1) {
      segments.add(
        _WhiteboardSimplificationSegment.between(points, pivot, segment.end),
      );
    }
  }
  final indices = selected.toList()..sort();
  return List<ServerWhiteboardPoint>.unmodifiable([
    for (final index in indices) points[index],
  ]);
}

class _WhiteboardSimplificationSegment {
  const _WhiteboardSimplificationSegment({
    required this.start,
    required this.end,
    required this.pivot,
    required this.errorSquared,
  });

  final int start;
  final int end;
  final int pivot;
  final double errorSquared;

  int get span => end - start;

  factory _WhiteboardSimplificationSegment.between(
    List<ServerWhiteboardPoint> points,
    int start,
    int end,
  ) {
    final first = points[start];
    final last = points[end];
    var pivot = start + (end - start) ~/ 2;
    var largestError = -1.0;
    for (var index = start + 1; index < end; index++) {
      final error = _distanceToSegmentSquared(points[index], first, last);
      if (error > largestError) {
        largestError = error;
        pivot = index;
      }
    }
    return _WhiteboardSimplificationSegment(
      start: start,
      end: end,
      pivot: pivot,
      errorSquared: largestError,
    );
  }
}

double _distanceToSegmentSquared(
  ServerWhiteboardPoint point,
  ServerWhiteboardPoint first,
  ServerWhiteboardPoint last,
) {
  final dx = last.x - first.x;
  final dy = last.y - first.y;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) {
    final px = point.x - first.x;
    final py = point.y - first.y;
    return px * px + py * py;
  }
  final projection =
      (((point.x - first.x) * dx + (point.y - first.y) * dy) / lengthSquared)
          .clamp(0.0, 1.0);
  final closestX = first.x + projection * dx;
  final closestY = first.y + projection * dy;
  final px = point.x - closestX;
  final py = point.y - closestY;
  return px * px + py * py;
}

/// One short-lived preview received through the active meeting's encrypted
/// LiveKit data channel. Completed history still lives exclusively in
/// [ServerWhiteboardStroke].
class ServerWhiteboardLiveDraft {
  ServerWhiteboardLiveDraft({
    required this.draftId,
    required this.serverId,
    required this.channelId,
    required this.mediaChannelId,
    required this.roomId,
    required this.sessionId,
    required this.authorId,
    required this.generation,
    required this.sequence,
    required List<ServerWhiteboardPoint> points,
    required this.color,
    required this.lineWidth,
    required this.receivedAt,
    required this.expiresAt,
  }) : points = List.unmodifiable(points);

  final String draftId;
  final String serverId;

  /// The persistent whiteboard channel this preview belongs to.
  final String channelId;

  /// The active Company meeting channel carrying this preview.
  final String mediaChannelId;
  final String roomId;
  final String sessionId;
  final String authorId;
  final int generation;
  final int sequence;
  final List<ServerWhiteboardPoint> points;
  final ServerWhiteboardColor color;
  final int lineWidth;
  final DateTime receivedAt;
  final DateTime expiresAt;

  bool isVisibleAt(
    DateTime now, {
    required String expectedServerId,
    required String expectedChannelId,
    required int boardGeneration,
  }) =>
      serverId == expectedServerId &&
      channelId == expectedChannelId &&
      generation == boardGeneration &&
      expiresAt.isAfter(now.toUtc());
}

String encodeServerWhiteboardPoints(List<ServerWhiteboardPoint> points) {
  if (points.length < 2 || points.length > 64) {
    throw ArgumentError.value(points.length, 'points');
  }
  return points
      .map((point) {
        if (!point.x.isFinite ||
            !point.y.isFinite ||
            point.x < 0 ||
            point.x > 1 ||
            point.y < 0 ||
            point.y > 1) {
          throw ArgumentError.value(point.toMap(), 'points');
        }
        return '${(point.x * 10000).round()},${(point.y * 10000).round()}';
      })
      .join(';');
}

List<ServerWhiteboardPoint>? decodeServerWhiteboardPoints(String encoded) {
  if (encoded.length < 7 || encoded.length > 767) return null;
  final entries = encoded.split(';');
  if (entries.length < 2 || entries.length > 64) return null;
  final points = <ServerWhiteboardPoint>[];
  for (final entry in entries) {
    final coordinates = entry.split(',');
    if (coordinates.length != 2 ||
        !_encodedCoordinate.hasMatch(coordinates[0]) ||
        !_encodedCoordinate.hasMatch(coordinates[1])) {
      return null;
    }
    final x = int.parse(coordinates[0]);
    final y = int.parse(coordinates[1]);
    if (x > 10000 || y > 10000) return null;
    points.add(ServerWhiteboardPoint(x / 10000, y / 10000));
  }
  return List<ServerWhiteboardPoint>.unmodifiable(points);
}

final _encodedCoordinate = RegExp(r'^(?:0|[1-9][0-9]{0,3}|10000)$');

/// A stroke rendered locally while its callable mutation and Firestore echo
/// converge. It is deliberately separate from [ServerWhiteboardStroke]: local
/// ink has no server-owned sequence, revision or author metadata yet.
class ServerWhiteboardLocalStroke {
  ServerWhiteboardLocalStroke({
    required this.requestId,
    required this.observedGeneration,
    required this.minimumSequence,
    required List<ServerWhiteboardPoint> points,
    required this.color,
    required this.lineWidth,
  }) : points = List.unmodifiable(points);

  final String requestId;
  final int observedGeneration;
  final int minimumSequence;
  final List<ServerWhiteboardPoint> points;
  final ServerWhiteboardColor color;
  final int lineWidth;

  bool matches(ServerWhiteboardStroke stroke, {required String authorId}) {
    if (stroke.authorId != authorId ||
        stroke.generation < observedGeneration ||
        (stroke.generation == observedGeneration &&
            stroke.sequence < minimumSequence) ||
        stroke.color != color ||
        stroke.lineWidth != lineWidth ||
        stroke.points.length != points.length) {
      return false;
    }
    for (var index = 0; index < points.length; index++) {
      final local = points[index];
      final persisted = stroke.points[index];
      if ((local.x - persisted.x).abs() > 0.000000001 ||
          (local.y - persisted.y).abs() > 0.000000001) {
        return false;
      }
    }
    return true;
  }
}

class ServerWhiteboardReconciliation {
  const ServerWhiteboardReconciliation({
    required this.unmatchedLocal,
    required this.confirmedRequestIds,
    required this.confirmedStrokes,
  });

  final List<ServerWhiteboardLocalStroke> unmatchedLocal;
  final Set<String> confirmedRequestIds;
  final Map<String, ServerWhiteboardStroke> confirmedStrokes;
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

  /// Reconciles optimistic ink with distinct authoritative strokes. Matching
  /// is a multiset operation so two identical gestures require two separate
  /// Firestore strokes before both local copies disappear.
  ServerWhiteboardReconciliation reconcileLocal({
    required String userId,
    required List<ServerWhiteboardLocalStroke> localStrokes,
  }) {
    if (localStrokes.isEmpty) {
      return const ServerWhiteboardReconciliation(
        unmatchedLocal: [],
        confirmedRequestIds: {},
        confirmedStrokes: {},
      );
    }
    final available = List<bool>.filled(strokes.length, true);
    final unmatched = <ServerWhiteboardLocalStroke>[];
    final confirmed = <String>{};
    final confirmedStrokes = <String, ServerWhiteboardStroke>{};
    for (final local in localStrokes) {
      var matchIndex = -1;
      for (var index = 0; index < strokes.length; index++) {
        if (available[index] &&
            local.matches(strokes[index], authorId: userId)) {
          matchIndex = index;
          break;
        }
      }
      if (matchIndex < 0) {
        unmatched.add(local);
      } else {
        available[matchIndex] = false;
        confirmed.add(local.requestId);
        confirmedStrokes[local.requestId] = strokes[matchIndex];
      }
    }
    return ServerWhiteboardReconciliation(
      unmatchedLocal: List.unmodifiable(unmatched),
      confirmedRequestIds: Set.unmodifiable(confirmed),
      confirmedStrokes: Map.unmodifiable(confirmedStrokes),
    );
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
