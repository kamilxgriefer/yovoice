import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/servers/data/models/server_member_role.dart';
import 'package:yovoice/features/servers/data/models/server_podcast_episode.dart';
import 'package:yovoice/features/servers/data/services/server_service.dart';
import 'package:yovoice/features/servers/presentation/widgets/server_podcast_episodes_board.dart';

import 'server_podcast_test.dart' show podcastChannels, podcastServer;
import 'server_test_support.dart';

const media = ServerPodcastEpisodeMedia(
  storagePath: 'server_podcast_episodes/s/episodes/episode-1.mp3',
  generation: '501',
  contentType: 'audio/mpeg',
  size: 4096,
  duration: Duration(minutes: 1),
);

ServerPodcastEpisode episode({
  ServerPodcastEpisodeStatus status = ServerPodcastEpisodeStatus.published,
  int revision = 4,
}) => ServerPodcastEpisode(
  id: 'episode-1',
  serverId: 's',
  channelId: 'episodes',
  studioChannelId: 'studio',
  sessionId: 'session-1',
  title: 'Pierwszy odcinek',
  status: status,
  providerStatus: status == ServerPodcastEpisodeStatus.error
      ? ServerPodcastProviderStatus.failed
      : status == ServerPodcastEpisodeStatus.recording
      ? ServerPodcastProviderStatus.active
      : status == ServerPodcastEpisodeStatus.processing
      ? ServerPodcastProviderStatus.ending
      : ServerPodcastProviderStatus.complete,
  revision: revision,
  createdById: 'owner',
  createdByName: 'Kasia',
  createdAt: DateTime.utc(2026, 9, 13, 10),
  updatedAt: DateTime.utc(2026, 9, 13, 11),
  media:
      status == ServerPodcastEpisodeStatus.ready ||
          status == ServerPodcastEpisodeStatus.published
      ? media
      : null,
  failureCode: status == ServerPodcastEpisodeStatus.error
      ? 'provider-failed'
      : null,
  stoppedAt: status == ServerPodcastEpisodeStatus.recording
      ? null
      : DateTime.utc(2026, 9, 13, 10, 30),
  readyAt:
      status == ServerPodcastEpisodeStatus.ready ||
          status == ServerPodcastEpisodeStatus.published
      ? DateTime.utc(2026, 9, 13, 11)
      : null,
  publishedAt: status == ServerPodcastEpisodeStatus.published
      ? DateTime.utc(2026, 9, 13, 11, 5)
      : null,
);

class FakePodcastPlayer implements ServerPodcastAudioPlayer {
  final controller = StreamController<ServerPodcastPlaybackState>.broadcast(
    sync: true,
  );
  final played = <Uri>[];
  var pauses = 0;
  var stops = 0;

  @override
  Stream<ServerPodcastPlaybackState> get states => controller.stream;

  @override
  Future<void> play(Uri url) async {
    played.add(url);
    controller.add(ServerPodcastPlaybackState.playing);
  }

  @override
  Future<void> pause() async {
    pauses++;
    controller.add(ServerPodcastPlaybackState.paused);
  }

  @override
  Future<void> stop() async {
    stops++;
    controller.add(ServerPodcastPlaybackState.idle);
  }

  @override
  Future<void> dispose() => controller.close();
}

void main() {
  test(
    'episode parser keeps UTC and rejects a mismatched private media path',
    () async {
      final firestore = FakeFirebaseFirestore();
      final reference = firestore
          .collection('clubs')
          .doc('s')
          .collection('channels')
          .doc('episodes')
          .collection('episodes')
          .doc('episode-1');
      Map<String, Object?> data({String? path}) => {
        'schemaVersion': 1,
        'episodeKind': 'podcastEpisode',
        'serverId': 's',
        'clubId': 's',
        'channelId': 'episodes',
        'studioChannelId': 'studio',
        'episodeId': 'episode-1',
        'sessionId': 'session-1',
        'livekitRoomName': 'lk',
        'title': 'Pierwszy odcinek',
        'status': 'published',
        'revision': 4,
        'createdById': 'owner',
        'createdByName': 'Kasia',
        'egressId': 'egress-1',
        'outputPath': path ?? media.storagePath,
        'providerStatus': 'complete',
        'media': {
          'storagePath': path ?? media.storagePath,
          'generation': '501',
          'contentType': 'audio/mpeg',
          'size': 4096,
          'durationMillis': 60000,
        },
        'failureCode': null,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 13, 10)),
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 9, 13, 11)),
        'stoppedAt': Timestamp.fromDate(DateTime.utc(2026, 9, 13, 10, 30)),
        'readyAt': Timestamp.fromDate(DateTime.utc(2026, 9, 13, 11)),
        'publishedAt': Timestamp.fromDate(DateTime.utc(2026, 9, 13, 11, 5)),
        'publishedById': 'owner',
      };
      await reference.set(data());
      final parsed = ServerPodcastEpisode.fromFirestore(
        await reference.get(),
        serverId: 's',
        channelId: 'episodes',
      );
      expect(parsed.createdAt.isUtc, isTrue);
      expect(parsed.media?.duration, const Duration(minutes: 1));

      await reference.set(data(path: 'server_podcast_episodes/other/file.mp3'));
      final mismatched = await reference.get();
      expect(
        () => ServerPodcastEpisode.fromFirestore(
          mismatched,
          serverId: 's',
          channelId: 'episodes',
        ),
        throwsFormatException,
      );
    },
  );

  test('service sends exact podcast callable payloads', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final service = ServerService(
      call: (name, data) async {
        calls.add((name, data));
        if (name == 'getServerPodcastEpisodeAccessV1') {
          return {
            'schemaVersion': 1,
            'serverId': 's',
            'channelId': 'episodes',
            'episodeId': 'episode-1',
            'title': 'Pierwszy odcinek',
            'expiresAtMillis': DateTime.now().millisecondsSinceEpoch + 60000,
            'media': {
              'url': 'https://storage.googleapis.com/private/episode.mp3',
              'storagePath': media.storagePath,
              'generation': '501',
              'contentType': 'audio/mpeg',
              'size': 4096,
              'durationMillis': 60000,
            },
          };
        }
        return {
          'schemaVersion': 1,
          'serverId': 's',
          'channelId': 'episodes',
          'studioChannelId': 'studio',
          'episodeId': 'episode-1',
          'sessionId': 'session-1',
          'status': 'recording',
          'providerStatus': 'active',
          'revision': 2,
        };
      },
    );
    await service.startPodcastRecording(
      serverId: 's',
      channelId: 'episodes',
      studioChannelId: 'studio',
      sessionId: 'session-1',
      title: 'Pierwszy odcinek',
      requestId: 'request-1',
    );
    await service.getPodcastEpisodeAccess(episode: episode());
    expect(calls.first.$1, 'startServerPodcastRecordingV1');
    expect(calls.first.$2.keys, {
      'serverId',
      'channelId',
      'studioChannelId',
      'sessionId',
      'title',
      'requestId',
    });
    expect(calls.last.$1, 'getServerPodcastEpisodeAccessV1');
    expect(calls.last.$2.keys, {'serverId', 'channelId', 'episodeId'});
  });

  testWidgets(
    'published episode gets signed access and real playback controls',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = TestServerRepository()
        ..myRole = ServerMemberRole.member
        ..podcastEpisodes = [episode()];
      final player = FakePodcastPlayer();
      final channel = podcastChannels().firstWhere(
        (channel) => channel.id == 'episodes',
      );
      await pumpServers(
        tester,
        ServerPodcastEpisodesBoard(
          server: podcastServer(),
          channel: channel,
          repository: repository,
          role: ServerMemberRole.member,
          playerFactory: () => player,
        ),
        size: const Size(390, 844),
      );
      expect(
        find.byKey(const ValueKey('server-podcast-episodes-board')),
        findsOneWidget,
      );
      expect(find.text('Pierwszy odcinek'), findsOneWidget);
      expect(find.text('Opublikowany'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('server-podcast-play-episode-1')),
      );
      await tester.pumpAndSettle();
      expect(repository.calls.last.$1, 'getServerPodcastEpisodeAccessV1');
      expect(player.played.single.host, 'storage.googleapis.com');
      expect(find.text('Pauza'), findsOneWidget);
    },
  );

  testWidgets('only a moderator sees the publish action for a ready episode', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = TestServerRepository()
      ..myRole = ServerMemberRole.moderator
      ..podcastEpisodes = [episode(status: ServerPodcastEpisodeStatus.ready)];
    final channel = podcastChannels().firstWhere(
      (channel) => channel.id == 'episodes',
    );
    await pumpServers(
      tester,
      ServerPodcastEpisodesBoard(
        server: podcastServer(),
        channel: channel,
        repository: repository,
        role: ServerMemberRole.moderator,
        playerFactory: FakePodcastPlayer.new,
      ),
      size: const Size(768, 900),
    );
    final action = find.byKey(
      const ValueKey('server-podcast-action-episode-1'),
    );
    expect(action, findsOneWidget);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(repository.calls.last.$1, 'publishServerPodcastEpisodeV1');
    expect(repository.calls.last.$2['expectedRevision'], 4);
  });
}
