import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_content_flow.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/offline_voice_moment_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_comment_preview.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_mentions.dart';
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
    this.commentPreview,
    this.mentionFriends = const <MentionCandidate>[],
    this.offlineService,
    this.momentService,
    this.mediaUriResolver,
    this.feedService,
    this.contentReportService,
    this.playerFactory,
    super.key,
  });

  final VoiceMoment moment;
  final VoidCallback onComments;
  final bool isOwn;

  /// Comments a HOST already loaded for this Moment, oldest first.
  ///
  /// Null — the default, and what every current caller passes — renders
  /// exactly the card that shipped before: the card never fetches
  /// comments itself, because a feed of cards each opening its own read
  /// is precisely the cost the server-owned view exists to avoid. A host
  /// that already holds a `VoiceMomentViewV2` can hand its comments here
  /// and get the inline preview for free.
  final List<MomentComment>? commentPreview;

  /// Extra people an `@mention` inside [commentPreview] may resolve to.
  final List<MentionCandidate> mentionFriends;

  /// True only when the viewer is known AND is not the author. Kept
  /// separate from [isOwn], which is false for a signed-out viewer too —
  /// offering "report" to someone with no session is a control that can
  /// only ever fail.
  final bool canReport;
  final OfflineVoiceMomentService? offlineService;
  final MomentService? momentService;

  @visibleForTesting
  final Future<Uri> Function(String momentId)? mediaUriResolver;

  /// Injection seam for the report action, matching [offlineService] and
  /// [feedService]: production passes nothing, tests pass a fake so the
  /// success and failure paths can be exercised without a Firebase app.
  final ContentReportService? contentReportService;

  /// Backs the like control. When null the heart renders as a disabled
  /// indicator rather than a button that silently does nothing.
  final HomeFeedService? feedService;

  /// Injection seam for playback, matching [offlineService] and
  /// [feedService]. Constructing a real [AudioPlayer] reaches for a
  /// platform channel that does not exist off-device, and it reports
  /// the failure asynchronously — after any frame a test could inspect.
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
  MomentService? _moments;
  bool _playing = false;
  bool _downloaded = false;
  bool _downloading = false;
  int _downloadLookupGeneration = 0;
  late bool _liked;
  late int _likeCount;
  bool _likePending = false;
  bool _hasLocalLikeOverride = false;

  AppLocalizations get _copy => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    _liked = widget.moment.callerLiked;
    _likeCount = widget.moment.likeCount;
    if (widget.mediaUriResolver == null) {
      try {
        _moments = widget.momentService ?? MomentService();
      } catch (_) {
        _moments = null;
      }
    }
    _refreshDownloadState();
  }

  @override
  void didUpdateWidget(covariant MomentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moment.id != widget.moment.id) {
      _downloaded = false;
      _liked = widget.moment.callerLiked;
      _likeCount = widget.moment.likeCount;
      _likePending = false;
      _hasLocalLikeOverride = false;
      _refreshDownloadState();
    } else if (!_likePending &&
        (!_hasLocalLikeOverride || widget.moment.callerLiked == _liked)) {
      _liked = widget.moment.callerLiked;
      _likeCount = widget.moment.likeCount;
      _hasLocalLikeOverride = false;
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
    try {
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
            : await _remoteSource();
        if (source == null) return;
        await _player.play(source);
      }
      if (mounted) setState(() => _playing = !_playing);
    } catch (_) {
      if (!mounted) return;
      setState(() => _playing = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              _copy.text(
                'This Voice Moment is unavailable right now.',
                'Ten Voice Moment jest teraz niedostępny.',
              ),
            ),
          ),
        );
    }
  }

  Future<Source?> _remoteSource() async {
    if (!widget.moment.hasMediaReference) return null;
    final momentId = widget.moment.id;
    final uri = await _remoteUri(momentId);
    if (!mounted || widget.moment.id != momentId) return null;
    return UrlSource(uri.toString());
  }

  Future<Uri> _remoteUri(String momentId) {
    final resolver = widget.mediaUriResolver;
    if (resolver != null) return resolver(momentId);
    final moments = _moments;
    if (moments == null) {
      throw StateError('The YO Voice media service is unavailable.');
    }
    return moments.resolveMediaUri(momentId: momentId);
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
        final uri = await _remoteUri(momentId);
        await _offline.download(widget.moment, authorizedUri: uri);
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
                  ? _copy.text(
                      'Voice Moment downloaded for offline listening.',
                      'Voice Moment pobrany do słuchania offline.',
                    )
                  : _copy.text(
                      'Offline download removed.',
                      'Usunięto pobrane nagranie.',
                    ),
            ),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            content: Text(
              _copy.text(
                'The Voice Moment could not be downloaded. Try again.',
                'Nie udało się pobrać Voice Momentu. Spróbuj ponownie.',
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _toggleLike() async {
    final service = widget.feedService;
    if (service == null || _likePending) return;
    final previousLiked = _liked;
    final previousCount = _likeCount;
    final desiredLiked = !previousLiked;
    setState(() {
      _liked = desiredLiked;
      _likeCount = (previousCount + (desiredLiked ? 1 : -1)).clamp(0, 1 << 31);
      _likePending = true;
      _hasLocalLikeOverride = true;
    });
    try {
      await service.setLike(widget.moment.id, liked: desiredLiked);
      if (!mounted) return;
      setState(() => _likePending = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = previousLiked;
        _likeCount = previousCount;
        _likePending = false;
        _hasLocalLikeOverride = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              _copy.text(
                'Your like could not be saved. Try again.',
                'Nie udało się zapisać polubienia. Spróbuj ponownie.',
              ),
            ),
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
    final copy = _copy;
    await reportContent(
      context: context,
      service: widget.contentReportService,
      content: ReportedContent.voiceMoment(
        momentId: widget.moment.id,
        reportReceipt: widget.moment.reportReceipt,
      ),
      title: copy.text('Report this Voice Moment', 'Zgłoś ten Voice Moment'),
      subtitle: copy.text(
        'Your report goes to the YO Voice moderation team with this '
            'Moment attached. ${widget.moment.authorName} is not told who '
            'reported it.',
        'Zgłoszenie wraz z tym Momentem trafi do zespołu moderacji YO Voice. '
            '${widget.moment.authorName} nie dowie się, kto je wysłał.',
      ),
    );
  }

  String _age(DateTime? createdAt) {
    if (createdAt == null) return '';
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return _copy.text('now', 'teraz');
    if (diff.inMinutes < 60) {
      return _copy.text('${diff.inMinutes}m', '${diff.inMinutes} min');
    }
    if (diff.inHours < 24) {
      return _copy.text('${diff.inHours}h', '${diff.inHours} godz.');
    }
    final days = diff.inDays;
    return _copy.text('${days}d', days == 1 ? '1 dzień' : '$days dni');
  }

  @override
  Widget build(BuildContext context) {
    final moment = widget.moment;
    final playable = moment.hasMediaReference;
    final palette = context.appPalette;
    final copy = _copy;

    return Container(
      key: ValueKey('moment-card-${moment.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: palette.surface,
        border: Border.all(color: palette.border),
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
                semanticLabel: copy.text(
                  'Open profile for ${moment.authorName}',
                  'Otwórz profil: ${moment.authorName}',
                ),
                tooltip: copy.text(
                  'Open ${moment.authorName}\'s profile',
                  'Otwórz profil ${moment.authorName}',
                ),
                circular: true,
                child: UserAvatar(
                  radius: 18,
                  userId: moment.authorId,
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
                            style: TextStyle(
                              color: palette.textPrimary,
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
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (!moment.isPublished)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    copy.text('Uploading…', 'Przesyłanie…'),
                    style: TextStyle(color: palette.textTertiary, fontSize: 11),
                  ),
                ),
            ],
          ),
          if (moment.caption.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              moment.caption,
              style: TextStyle(
                color: palette.textPrimary,
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
                  style: TextStyle(
                    color: palette.textTertiary,
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
                liked: _liked,
                likeCount: _likeCount,
                feedService: widget.feedService,
                onToggle: _likePending ? null : _toggleLike,
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: widget.onComments,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 44),
                ),
                icon: Icon(
                  Icons.mode_comment_outlined,
                  size: 17,
                  color: palette.textSecondary,
                ),
                label: Text(
                  moment.commentCount == 0
                      ? copy.text('Comment', 'Komentarz')
                      : '${moment.commentCount}',
                  style: TextStyle(
                    color: palette.textSecondary,
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
                  tooltip: copy.text(
                    'Report this Voice Moment',
                    'Zgłoś ten Voice Moment',
                  ),
                  onPressed: _report,
                  icon: Icon(Icons.flag_outlined, color: palette.textSecondary),
                ),
              if (playable && moment.isPublished && !moment.isDeleted)
                IconButton(
                  key: ValueKey('download-moment-${moment.id}'),
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  tooltip: _downloaded
                      ? copy.text(
                          'Remove offline download',
                          'Usuń pobrane nagranie',
                        )
                      : copy.text(
                          'Download for offline listening',
                          'Pobierz do słuchania offline',
                        ),
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
                              : palette.textSecondary,
                        ),
                ),
            ],
          ),
          if (widget.commentPreview case final preview?) ...[
            const SizedBox(height: 4),
            Divider(color: palette.border, height: 1),
            const SizedBox(height: 10),
            MomentCommentPreview(
              comments: preview,
              totalCommentCount: moment.commentCount,
              momentAuthor: MentionCandidate(
                userId: moment.authorId,
                displayName: moment.authorName,
              ),
              friends: widget.mentionFriends,
              onSeeAll: widget.onComments,
              onCompose: moment.isDeleted ? null : widget.onComments,
            ),
          ],
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
    required this.liked,
    required this.likeCount,
    required this.feedService,
    required this.onToggle,
  });

  final bool liked;
  final int likeCount;
  final HomeFeedService? feedService;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final service = feedService;
    final copy = AppLocalizations.of(context);
    // Zero reads as a verb, not a number — no invented social proof, and
    // no hiding the control either.
    final label = likeCount == 0 ? copy.text('Like', 'Lubię to') : '$likeCount';

    return _LikeButton(
      liked: liked,
      label: label,
      onTap: service == null ? null : onToggle,
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
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Semantics(
      button: onTap != null,
      label: liked
          ? copy.text('Unlike this Moment', 'Usuń polubienie tego Momentu')
          : copy.text('Like this Moment', 'Polub ten Moment'),
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
          color: liked ? AppColors.secondary : palette.textSecondary,
        ),
        label: Text(
          label,
          style: TextStyle(
            color: palette.textSecondary,
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
    final colors = Theme.of(context).colorScheme;
    final copy = AppLocalizations.of(context);
    return Semantics(
      button: enabled,
      label: playing
          ? copy.text('Pause this Moment', 'Wstrzymaj ten Moment')
          : copy.text('Play this Moment', 'Odtwórz ten Moment'),
      child: Material(
        color: enabled ? colors.primary : colors.primary.withValues(alpha: .25),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: colors.onPrimary,
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
