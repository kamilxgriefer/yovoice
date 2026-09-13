import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:flutter/material.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';

import '../../data/models/server.dart';
import '../../data/models/server_channel.dart';
import '../../data/models/server_member_role.dart';
import '../../data/models/server_podcast_episode.dart';
import '../../data/services/server_podcast_episode_repository.dart';
import '../server_action_failure.dart';
import '../server_localized_copy.dart';
import '../theme/server_identity.dart';

enum ServerPodcastPlaybackState { idle, playing, paused }

abstract interface class ServerPodcastAudioPlayer {
  Stream<ServerPodcastPlaybackState> get states;
  Future<void> play(Uri url);
  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();
}

class _AudioPlayerAdapter implements ServerPodcastAudioPlayer {
  _AudioPlayerAdapter() : _player = audio.AudioPlayer();

  final audio.AudioPlayer _player;

  @override
  Stream<ServerPodcastPlaybackState> get states =>
      _player.onPlayerStateChanged.map(
        (state) => switch (state) {
          audio.PlayerState.playing => ServerPodcastPlaybackState.playing,
          audio.PlayerState.paused => ServerPodcastPlaybackState.paused,
          _ => ServerPodcastPlaybackState.idle,
        },
      );

  @override
  Future<void> play(Uri url) => _player.play(audio.UrlSource(url.toString()));

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// The podcast server's durable archive. Listeners only receive published
/// rows; moderators also see recording, processing, ready and error states.
class ServerPodcastEpisodesBoard extends StatefulWidget {
  const ServerPodcastEpisodesBoard({
    required this.server,
    required this.channel,
    required this.repository,
    required this.role,
    this.compact = false,
    this.playerFactory,
    super.key,
  });

  final Server server;
  final ServerChannel channel;
  final ServerPodcastEpisodeRepository repository;
  final ServerMemberRole? role;
  final bool compact;
  final ServerPodcastAudioPlayer Function()? playerFactory;

  @override
  State<ServerPodcastEpisodesBoard> createState() =>
      _ServerPodcastEpisodesBoardState();
}

class _ServerPodcastEpisodesBoardState
    extends State<ServerPodcastEpisodesBoard> {
  late final ServerPodcastAudioPlayer _player;
  StreamSubscription<ServerPodcastPlaybackState>? _playbackSubscription;
  ServerPodcastPlaybackState _playback = ServerPodcastPlaybackState.idle;
  String? _playingId;
  String? _busyId;
  String? _error;

  bool get _canModerate => widget.role?.canModerate ?? false;

  @override
  void initState() {
    super.initState();
    _player = widget.playerFactory?.call() ?? _AudioPlayerAdapter();
    _playbackSubscription = _player.states.listen((state) {
      if (!mounted) return;
      setState(() {
        _playback = state;
        if (state == ServerPodcastPlaybackState.idle) _playingId = null;
      });
    });
  }

  @override
  void dispose() {
    _playbackSubscription?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    if (_busyId != null) return;
    setState(() {
      _busyId = id;
      _error = null;
    });
    try {
      await action();
      if (mounted) setState(() => _busyId = null);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busyId = null;
        _error = serverActionFailureCopy(error, AppLocalizations.of(context));
      });
    }
  }

  Future<void> _togglePlayback(ServerPodcastEpisode episode) async {
    await _run('play-${episode.id}', () async {
      if (_playingId == episode.id &&
          _playback == ServerPodcastPlaybackState.playing) {
        await _player.pause();
        return;
      }
      await _player.stop();
      final access = await widget.repository.getPodcastEpisodeAccess(
        episode: episode,
      );
      if (!access.expiresAt.isAfter(DateTime.now().toUtc())) {
        throw StateError('The episode access grant expired.');
      }
      _playingId = episode.id;
      await _player.play(access.url);
    });
  }

  Future<void> _episodeAction(ServerPodcastEpisode episode) async {
    await _run(episode.id, () async {
      switch (episode.status) {
        case ServerPodcastEpisodeStatus.processing:
          await widget.repository.finalizePodcastEpisode(
            episode: episode,
            requestId: widget.repository.newRequestId(),
          );
          return;
        case ServerPodcastEpisodeStatus.error:
          await widget.repository.retryPodcastRecording(
            episode: episode,
            requestId: widget.repository.newRequestId(),
          );
          return;
        case ServerPodcastEpisodeStatus.ready:
          await widget.repository.publishPodcastEpisode(
            episode: episode,
            requestId: widget.repository.newRequestId(),
          );
          return;
        case ServerPodcastEpisodeStatus.recording:
        case ServerPodcastEpisodeStatus.published:
          return;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    return StreamBuilder<List<ServerPodcastEpisode>>(
      stream: widget.repository.watchPodcastEpisodes(
        widget.server.id,
        widget.channel.id,
        canModerate: _canModerate,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return YoErrorState(
            error: snapshot.error,
            compact: widget.compact,
            onRetry: () => setState(() {}),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final episodes = snapshot.data!;
        if (episodes.isEmpty) {
          return YoEmptyState(
            icon: Icons.podcasts_rounded,
            title: copy.channelEmptyTitle(ServerChannelKind.episodes),
            subtitle: copy.serverPodcastEpisodesEmpty,
            compact: widget.compact,
          );
        }
        return CustomScrollView(
          key: const ValueKey('server-podcast-episodes-board'),
          slivers: [
            SliverToBoxAdapter(
              child: _EpisodesHeader(
                server: widget.server,
                compact: widget.compact,
              ),
            ),
            if (_error != null)
              SliverToBoxAdapter(
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    key: const ValueKey('server-podcast-episode-error'),
                    margin: EdgeInsets.fromLTRB(
                      widget.compact ? 12 : 20,
                      0,
                      widget.compact ? 12 : 20,
                      12,
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.appPalette.dangerSurface,
                      borderRadius: AppRadius.md,
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: context.appPalette.dangerForeground,
                      ),
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                widget.compact ? 12 : 20,
                0,
                widget.compact ? 12 : 20,
                28,
              ),
              sliver: SliverList.separated(
                itemCount: episodes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final episode = episodes[index];
                  return _EpisodeCard(
                    episode: episode,
                    canModerate: _canModerate,
                    busy:
                        _busyId == episode.id ||
                        _busyId == 'play-${episode.id}',
                    playing:
                        _playingId == episode.id &&
                        _playback == ServerPodcastPlaybackState.playing,
                    onPlay: episode.isPlayable
                        ? () => _togglePlayback(episode)
                        : null,
                    onAction: () => _episodeAction(episode),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EpisodesHeader extends StatelessWidget {
  const _EpisodesHeader({required this.server, required this.compact});

  final Server server;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = ServerIdentity.of(
      server.type,
    ).resolve(Theme.of(context).brightness);
    return Container(
      margin: EdgeInsets.all(compact ? 12 : 20),
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        color: colors.cardWash,
        borderRadius: AppRadius.lg,
        border: Border.all(color: colors.iconBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.podcasts_rounded, size: 32, color: colors.foreground),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    copy.serverPodcastEpisodesTitle,
                    style: AppTypography.titleLarge.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  copy.serverPodcastEpisodesBody,
                  style: AppTypography.bodyMedium.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.episode,
    required this.canModerate,
    required this.busy,
    required this.playing,
    required this.onPlay,
    required this.onAction,
  });

  final ServerPodcastEpisode episode;
  final bool canModerate;
  final bool busy;
  final bool playing;
  final VoidCallback? onPlay;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final localizations = MaterialLocalizations.of(context);
    final date = episode.publishedAt ?? episode.readyAt ?? episode.createdAt;
    final duration = episode.media?.duration;
    return Semantics(
      container: true,
      label: '${episode.title}. ${_status(copy)}',
      child: Container(
        key: ValueKey('server-podcast-episode-${episode.id}'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: AppRadius.lg,
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: palette.infoSurface,
                    borderRadius: AppRadius.md,
                  ),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    color: palette.audioAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        episode.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleMedium.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${localizations.formatShortDate(date.toLocal())} · '
                        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date.toLocal()))}'
                        '${duration == null ? '' : ' · ${_duration(duration)}'}',
                        style: AppTypography.bodySmall.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusPill(label: _status(copy), status: episode.status),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (onPlay != null)
                  FilledButton.icon(
                    key: ValueKey('server-podcast-play-${episode.id}'),
                    onPressed: busy ? null : onPlay,
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                    label: Text(
                      playing
                          ? copy.serverEpisodePause
                          : copy.serverEpisodePlay,
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                  ),
                if (canModerate && _actionLabel(copy) != null)
                  OutlinedButton.icon(
                    key: ValueKey('server-podcast-action-${episode.id}'),
                    onPressed: busy ? null : onAction,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_actionIcon),
                    label: Text(_actionLabel(copy)!),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _status(AppLocalizations copy) => switch (episode.status) {
    ServerPodcastEpisodeStatus.recording => copy.serverPodcastRecordingActive,
    ServerPodcastEpisodeStatus.processing =>
      copy.serverPodcastRecordingProcessing,
    ServerPodcastEpisodeStatus.ready => copy.serverPodcastEpisodeReady,
    ServerPodcastEpisodeStatus.published => copy.serverPodcastEpisodePublished,
    ServerPodcastEpisodeStatus.error => copy.serverPodcastRecordingError,
  };

  String? _actionLabel(AppLocalizations copy) => switch (episode.status) {
    ServerPodcastEpisodeStatus.processing => copy.serverPodcastFinalize,
    ServerPodcastEpisodeStatus.error => copy.serverPodcastRetryRecording,
    ServerPodcastEpisodeStatus.ready => copy.serverPodcastPublishEpisode,
    _ => null,
  };

  IconData get _actionIcon => switch (episode.status) {
    ServerPodcastEpisodeStatus.processing => Icons.sync_rounded,
    ServerPodcastEpisodeStatus.error => Icons.refresh_rounded,
    ServerPodcastEpisodeStatus.ready => Icons.publish_rounded,
    _ => Icons.more_horiz_rounded,
  };

  static String _duration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.status});

  final String label;
  final ServerPodcastEpisodeStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final (background, foreground) = switch (status) {
      ServerPodcastEpisodeStatus.published ||
      ServerPodcastEpisodeStatus.ready => (
        palette.successSurface,
        palette.successForeground,
      ),
      ServerPodcastEpisodeStatus.error => (
        palette.dangerSurface,
        palette.dangerForeground,
      ),
      ServerPodcastEpisodeStatus.recording => (
        palette.dangerSurface,
        palette.dangerForeground,
      ),
      ServerPodcastEpisodeStatus.processing => (
        palette.warningSurface,
        palette.warningForeground,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(color: foreground),
      ),
    );
  }
}
