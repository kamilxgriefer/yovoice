import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_content_flow.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/offline_voice_moment_service.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// An audio-first Moment card: identity, caption, a compact waveform with
/// play state and duration, and the real reaction/comment counts.
///
/// Shared with the creator pinned-Moment surfaces and mobile Home — its
/// constructor is deliberately backward compatible.
class MomentCard extends StatefulWidget {
  const MomentCard({
    required this.moment,
    required this.onComments,
    this.isOwn = false,
    this.canReport = false,
    this.offlineService,
    this.feedService,
    this.contentReportService,
    this.playerFactory,
    super.key,
  });

  final VoiceMoment moment;
  final VoidCallback onComments;
  final bool isOwn;

  /// True only when the viewer is known AND is not the author. Kept
  /// separate from [isOwn], which is false for a signed-out viewer too —
  /// offering "report" to someone with no session is a control that can
  /// only ever fail.
  final bool canReport;
  final OfflineVoiceMomentService? offlineService;

  /// Injection seam for the report action, matching [offlineService] and
  /// [feedService]: production passes nothing, tests pass a fake so the
  /// success and failure paths can be exercised without a Firebase app.
  final ContentReportService? contentReportService;

  /// Backs the like control. When null the heart renders as a disabled
  /// indicator rather than a button that silently does nothing.
  final HomeFeedService? feedService;

  /// Injection seam for playback, matching [MomentDiscoveryView]'s.
  /// Constructing a real [AudioPlayer] reaches for a platform channel
  /// that does not exist off-device, and it reports the failure
  /// asynchronously — after any frame a test could inspect.
  @visibleForTesting
  final AudioPlayer Function()? playerFactory;

  @override
  State<MomentCard> createState() => _MomentCardState();
}

class _MomentCardState extends State<MomentCard> {
  /// Created on the first play, not on mount. A feed of cards used to
  /// construct one platform-backed player each just to sit there, and
  /// `dispose` must not be the thing that finally creates one.
  AudioPlayer? _created;
  AudioPlayer get _player =>
      _created ??= (widget.playerFactory ?? AudioPlayer.new)();
  late final OfflineVoiceMomentService _offline =
      widget.offlineService ?? OfflineVoiceMomentService.instance;
  bool _playing = false;
  bool _downloaded = false;
  bool _downloading = false;
  int _downloadLookupGeneration = 0;

  @override
  void initState() {
    super.initState();
    _refreshDownloadState();
  }

  @override
  void didUpdateWidget(covariant MomentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moment.id != widget.moment.id) {
      _downloaded = false;
      _refreshDownloadState();
    }
  }

  Future<void> _refreshDownloadState() async {
    final generation = ++_downloadLookupGeneration;
    final momentId = widget.moment.id;
    try {
      final downloaded = await _offline.isDownloaded(momentId);
      if (mounted &&
          generation == _downloadLookupGeneration &&
          widget.moment.id == momentId) {
        setState(() => _downloaded = downloaded);
      }
    } catch (_) {
      // The parent screen is authenticated, but a concurrent logout can race
      // this lightweight local lookup. It must not make the feed fail.
    }
  }

  @override
  void dispose() {
    _created?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = widget.moment.audioUrl?.trim() ?? '';
    if (url.isEmpty) return;
    if (_playing) {
      await _player.pause();
    } else {
      final offline = _downloaded
          ? await _offline.readPlayback(widget.moment.id)
          : null;
      if (_downloaded && offline == null && mounted) {
        setState(() => _downloaded = false);
      }
      final source = offline?.deviceFilePath != null
          ? DeviceFileSource(offline!.deviceFilePath!)
          : offline?.bytes != null
          ? BytesSource(offline!.bytes!)
          : UrlSource(url);
      await _player.play(source);
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  Future<void> _toggleDownload() async {
    if (_downloading) return;
    final momentId = widget.moment.id;
    final removing = _downloaded;
    setState(() => _downloading = true);
    try {
      if (removing) {
        await _offline.delete(momentId);
      } else {
        await _offline.download(widget.moment);
      }
      if (!mounted || widget.moment.id != momentId) return;
      setState(() => _downloaded = !removing);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              _downloaded
                  ? 'Voice Moment downloaded for offline listening.'
                  : 'Offline download removed.',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            content: Text(
              error is OfflineAudioException
                  ? error.message
                  : 'The Voice Moment could not be downloaded.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _toggleLike() async {
    final service = widget.feedService;
    if (service == null) return;
    try {
      await service.toggleLike(widget.moment.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Your like could not be saved.'),
          ),
        );
    }
  }

  /// Reports this Voice Moment to moderation.
  ///
  /// `voiceMoment` is one of the three targets `createContentReport`
  /// already accepts, and until now nothing in the app called it — the
  /// feed rendered other people's audio with no way to say anything was
  /// wrong with it.
  Future<void> _report() async {
    await reportContent(
      context: context,
      service: widget.contentReportService,
      content: ReportedContent.voiceMoment(momentId: widget.moment.id),
      title: 'Report this Voice Moment',
      subtitle:
          'Your report goes to the YO Voice moderation team with this '
          'Moment attached. ${widget.moment.authorName} is not told who '
          'reported it.',
    );
  }

  String _age(DateTime? createdAt) {
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final moment = widget.moment;
    final playable = (moment.audioUrl?.trim().isNotEmpty ?? false);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.surface.withValues(alpha: .5),
        border: Border.all(color: AppColors.border.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AccessibleTapRegion(
                onTap: () => showProfilePreview(
                  context,
                  userId: moment.authorId,
                  displayName: moment.authorName,
                  photoUrl: moment.authorPhotoUrl,
                ),
                semanticLabel: 'Open profile for ${moment.authorName}',
                tooltip: 'Open ${moment.authorName}\'s profile',
                circular: true,
                child: UserAvatar(
                  radius: 18,
                  photoUrl: moment.authorPhotoUrl,
                  displayName: moment.authorName,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row + Flexible, not Wrap: a long display name
                    // truncates and the identity badges stay on the line.
                    // A Wrap dropped the badges onto a second row.
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            moment.authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        UserIdentityBadges(uid: moment.authorId),
                      ],
                    ),
                    Text(
                      _age(moment.createdAt),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (!moment.isPublished)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text(
                    'Uploading…',
                    style: TextStyle(color: AppColors.textHint, fontSize: 11),
                  ),
                ),
            ],
          ),
          if (moment.caption.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              moment.caption,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _PlayButton(playing: _playing, enabled: playable, onTap: _toggle),
              const SizedBox(width: 12),
              const Expanded(child: _Waveform()),
              const SizedBox(width: 10),
              // Hidden rather than asserting "0:00": legacy documents
              // carry no duration and a fabricated zero is still fabricated.
              if (moment.durationSeconds > 0)
                Text(
                  moment.durationLabel,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _LikeControl(
                momentId: moment.id,
                likeCount: moment.likeCount,
                feedService: widget.feedService,
                onToggle: _toggleLike,
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: widget.onComments,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 44),
                ),
                icon: const Icon(
                  Icons.mode_comment_outlined,
                  size: 17,
                  color: AppColors.textSecondary,
                ),
                label: Text(
                  moment.commentCount == 0
                      ? 'Comment'
                      : '${moment.commentCount}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              // Not offered on your own Moment: reporting yourself is not
              // a real intent, and each such report is a row a moderator
              // opens before finding nothing to do. Deleting your own
              // Moment is the action that belongs there instead, and it
              // already exists elsewhere.
              if (widget.canReport && !moment.isDeleted)
                IconButton(
                  key: ValueKey('report-moment-${moment.id}'),
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  tooltip: 'Report this Voice Moment',
                  onPressed: _report,
                  icon: const Icon(
                    Icons.flag_outlined,
                    color: AppColors.textSecondary,
                  ),
                ),
              if (playable && moment.isPublished && !moment.isDeleted)
                IconButton(
                  key: ValueKey('download-moment-${moment.id}'),
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  tooltip: _downloaded
                      ? 'Remove offline download'
                      : 'Download for offline listening',
                  onPressed: _downloading ? null : _toggleDownload,
                  icon: _downloading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _downloaded
                              ? Icons.download_done_rounded
                              : Icons.download_for_offline_outlined,
                          color: _downloaded
                              ? AppColors.secondary
                              : AppColors.textSecondary,
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The heart, as a REAL control.
///
/// It previously rendered as an icon plus static text with no tap target:
/// the screen displayed engagement it gave no way to create, while
/// [HomeFeedService.toggleLike] / [HomeFeedService.watchLiked] and the
/// `setMomentLike` callable worked and Home already used them.
class _LikeControl extends StatelessWidget {
  const _LikeControl({
    required this.momentId,
    required this.likeCount,
    required this.feedService,
    required this.onToggle,
  });

  final String momentId;
  final int likeCount;
  final HomeFeedService? feedService;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final service = feedService;
    // Zero reads as a verb, not a number — no invented social proof, and
    // no hiding the control either.
    final label = likeCount == 0 ? 'Like' : '$likeCount';

    if (service == null) {
      return _LikeButton(liked: false, label: label, onTap: null);
    }
    return StreamBuilder<bool>(
      stream: service.watchLiked(momentId),
      builder: (context, snapshot) {
        final liked = snapshot.hasError ? false : (snapshot.data ?? false);
        return _LikeButton(liked: liked, label: label, onTap: onToggle);
      },
    );
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.liked,
    required this.label,
    required this.onTap,
  });

  final bool liked;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: liked ? 'Unlike this Moment' : 'Like this Moment',
      child: TextButton.icon(
        key: ValueKey('like-moment-$label-$liked'),
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 44),
        ),
        icon: Icon(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 17,
          // Tint carries STATE, never meaning. The count label stays
          // textSecondary: `secondary` on `background` is roughly 4:1,
          // fine for a glyph and not for 12 pt text.
          color: liked ? AppColors.secondary : AppColors.textSecondary,
        ),
        label: Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.enabled,
    required this.onTap,
  });

  final bool playing;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: enabled,
      label: playing ? 'Pause this Moment' : 'Play this Moment',
      child: Material(
        color: enabled
            ? AppColors.primary
            : AppColors.primary.withValues(alpha: .25),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: AppColors.textPrimary,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// A static waveform silhouette — deliberately decorative: the real
/// per-moment amplitude data is not recorded, and inventing a fake
/// waveform shape per moment would be fabricated data.
class _Waveform extends StatelessWidget {
  const _Waveform();

  static const _bars = <double>[
    .35,
    .6,
    .45,
    .8,
    .55,
    .3,
    .7,
    .5,
    .85,
    .4,
    .65,
    .3,
    .55,
    .75,
    .45,
    .6,
    .35,
    .5,
    .7,
    .4,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final bar in _bars)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.2),
                child: Container(
                  height: 26 * bar,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

