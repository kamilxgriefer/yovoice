import '../models/server_podcast_episode.dart';

/// Persistent podcast recording and episode archive contract.
///
/// Firestore streams are projections only. Every state change and every
/// playback grant is re-authorized by a callable.
abstract interface class ServerPodcastEpisodeRepository {
  String newRequestId();

  Stream<ServerPodcastRecordingState?> watchPodcastRecording(
    String serverId,
    String studioChannelId,
  );

  Stream<List<ServerPodcastEpisode>> watchPodcastEpisodes(
    String serverId,
    String channelId, {
    required bool canModerate,
  });

  Future<ServerPodcastEpisodeReceipt> startPodcastRecording({
    required String serverId,
    required String channelId,
    required String studioChannelId,
    required String sessionId,
    required String title,
    required String requestId,
  });

  Future<ServerPodcastEpisodeReceipt> stopPodcastRecording({
    required ServerPodcastRecordingState recording,
    required String requestId,
  });

  Future<ServerPodcastEpisodeReceipt> finalizePodcastEpisode({
    required ServerPodcastEpisode episode,
    required String requestId,
  });

  Future<ServerPodcastEpisodeReceipt> retryPodcastRecording({
    required ServerPodcastEpisode episode,
    required String requestId,
  });

  Future<ServerPodcastEpisodeReceipt> publishPodcastEpisode({
    required ServerPodcastEpisode episode,
    required String requestId,
  });

  Future<ServerPodcastEpisodeAccess> getPodcastEpisodeAccess({
    required ServerPodcastEpisode episode,
  });
}
