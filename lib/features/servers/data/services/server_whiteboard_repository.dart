import '../models/server_whiteboard.dart';

/// Realtime Company whiteboard reads and its three callable-only mutations.
abstract interface class ServerWhiteboardRepository {
  String get currentUserId;
  String newRequestId();

  Stream<ServerWhiteboardSnapshot> watchWhiteboard(
    String serverId,
    String channelId,
  );

  Future<void> createWhiteboardStroke({
    required String serverId,
    required String channelId,
    required List<ServerWhiteboardPoint> points,
    required ServerWhiteboardColor color,
    required int lineWidth,
    required String requestId,
  });

  Future<void> undoWhiteboardStroke({
    required ServerWhiteboardStroke stroke,
    required String requestId,
  });

  Future<void> clearWhiteboard({
    required String serverId,
    required String channelId,
    required int expectedRevision,
    required String requestId,
  });
}
