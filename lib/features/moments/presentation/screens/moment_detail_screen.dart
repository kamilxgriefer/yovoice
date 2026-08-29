import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_content_flow.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_expiry_scheduler.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_viewer.dart'
    show StoryWaveform;
import 'package:yovoice/features/moments/presentation/widgets/moment_time_labels.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// One Voice Moment, full page: author identity, the caption as the
/// heading, a real player with a position-fed waveform, engagement,
/// the likers' avatar row, and the comment thread with its composer.
///
/// Every fact rendered is a document's fact. Moments carry no separate
/// title and no tags, so the caption IS the heading and no tag chips
/// exist; there is no play counter in the schema, so none is printed;
/// the "Top reactions" avatars are the real `likes/{uid}` documents
/// resolved through the public profile projection, best-effort.
///
/// Pushed as a plain route it carries its own Back control; the shell
/// hosts it inside the persistent bottom navigation (Moments active) on
/// mobile. The author additionally sees the availability line — a real
/// countdown, or "Stays until deleted" for a permanent Moment — and the
/// Delete action.
class MomentDetailScreen extends StatefulWidget {
  const MomentDetailScreen({
    required this.moment,
    this.momentService,
    this.feedService,
    this.viewsService,
    this.contentReportService,
    this.auth,
    this.playerFactory,
    this.expiryClock,
    this.expiryTimerFactory,
    super.key,
  });

  final VoiceMoment moment;
  final MomentService? momentService;
  final HomeFeedService? feedService;
  final MomentViewsService? viewsService;
  final ContentReportService? contentReportService;
  final FirebaseAuth? auth;

  @visibleForTesting
  final AudioPlayer Function()? playerFactory;

  @visibleForTesting
  final MomentExpiryClock? expiryClock;

  @visibleForTesting
  final MomentExpiryTimerFactory? expiryTimerFactory;

  @override
  State<MomentDetailScreen> createState() => _MomentDetailScreenState();
}

class _MomentDetailScreenState extends State<MomentDetailScreen> {
  MomentService? _moments;
  HomeFeedService? _feed;
  MomentViewsService? _views;

  late VoiceMoment _moment = widget.moment;
  StreamSubscription<VoiceMoment?>? _liveSubscription;

  /// The document disappeared. Either it never loaded (opened from a
  /// stale reference) or it was deleted while open — both render the
  /// graceful gone-state; the author's own delete pops instead.
  bool _missing = false;
  bool _selfDeleted = false;
  bool _deleting = false;
  late final MomentExpiryScheduler _expiry;
  DateTime? _expiredThrough;
  bool _expiredByDeadline = false;

  Future<List<MomentReactor>>? _reactions;

  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _playerSubscriptions =
      <StreamSubscription<dynamic>>[];
  bool _isPlaying = false;
  bool _everPlayed = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  String? _playbackError;

  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode(debugLabel: 'Moment comment');
  final FocusNode _goneBackFocus = FocusNode(debugLabel: 'Expired Moment back');
  final MomentExpiryAnnouncer _expiryAnnouncer = MomentExpiryAnnouncer();
  bool _sending = false;

  String get _uid {
    try {
      return (widget.auth ?? FirebaseAuth.instance).currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  bool get _isOwn => _uid.isNotEmpty && _uid == _moment.authorId;

  @override
  void initState() {
    super.initState();
    _expiry = MomentExpiryScheduler(
      onDeadline: _handleExpiryDeadline,
      clock: widget.expiryClock,
      timerFactory: widget.expiryTimerFactory,
    );
    _expiredByDeadline = !_moment.isActiveAt(_effectiveNow());
    if (!_expiredByDeadline) _expiry.schedule([_moment]);
    // Each seam guarded separately, matching the other Moment surfaces:
    // one service that cannot be constructed must not take the others
    // down with it.
    try {
      _moments = widget.momentService ?? MomentService();
    } catch (_) {
      _moments = null;
    }
    try {
      _feed = widget.feedService ?? HomeFeedService();
    } catch (_) {
      _feed = null;
    }
    try {
      _views = widget.viewsService ?? MomentViewsService();
    } catch (_) {
      _views = null;
    }

    final moments = _moments;
    if (moments != null) {
      _liveSubscription = moments
          .watchMomentOrMissing(widget.moment.id)
          .listen(
            (moment) {
              if (!mounted) return;
              if (moment == null) {
                final previousFocus = FocusManager.instance.primaryFocus;
                final recoverFocus = momentExpiryFocusIsWithin(
                  context,
                  previousFocus,
                );
                _expiry.schedule(const <VoiceMoment>[]);
                _stopPlaybackForGone();
                setState(() => _missing = true);
                _announceGone(
                  previousFocus: recoverFocus ? previousFocus : null,
                );
                return;
              }
              final expired = !moment.isActiveAt(_effectiveNow());
              final previousFocus = expired
                  ? FocusManager.instance.primaryFocus
                  : null;
              final recoverFocus =
                  expired && momentExpiryFocusIsWithin(context, previousFocus);
              setState(() {
                _missing = false;
                _moment = moment;
                _expiredByDeadline = expired;
              });
              _expiry.schedule(expired ? const <VoiceMoment>[] : [moment]);
              if (expired) {
                _stopPlaybackForGone();
                _announceGone(
                  previousFocus: recoverFocus ? previousFocus : null,
                );
              }
            },
            onError: (Object _) {
              // A dead stream keeps the Moment the caller passed: real,
              // just not live.
            },
          );
      // One-shot on purpose: the row is a snapshot of who reacted, not a
      // live board, and each entry costs a profile read.
      _reactions = moments.topReactions(widget.moment.id);
    }
  }

  @override
  void dispose() {
    _expiry.dispose();
    unawaited(_liveSubscription?.cancel());
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
    _player?.dispose();
    _composer.dispose();
    _composerFocus.dispose();
    _goneBackFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- playback

  DateTime _effectiveNow() {
    final now = _expiry.now();
    final floor = _expiredThrough;
    return floor != null && floor.isAfter(now) ? floor : now;
  }

  void _stopPlaybackForGone() {
    final player = _player;
    if (player != null) {
      unawaited(player.stop().catchError((Object _) {}));
    }
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _position = Duration.zero;
      _duration = null;
    });
  }

  void _handleExpiryDeadline(DateTime deadline) {
    if (!mounted) return;
    if (_expiredThrough == null || deadline.isAfter(_expiredThrough!)) {
      _expiredThrough = deadline;
    }
    if (_moment.isActiveAt(_effectiveNow())) {
      _expiry.schedule([_moment]);
      return;
    }
    final previousFocus = FocusManager.instance.primaryFocus;
    final recoverFocus = momentExpiryFocusIsWithin(context, previousFocus);
    _stopPlaybackForGone();
    setState(() => _expiredByDeadline = true);
    _expiry.schedule(const <VoiceMoment>[]);
    _announceGone(previousFocus: recoverFocus ? previousFocus : null);
  }

  void _announceGone({required FocusNode? previousFocus}) {
    _expiryAnnouncer.announce(
      context,
      transition: 'detail-gone-${widget.moment.id}',
      message: 'Voice Moment is no longer available.',
    );
    recoverMomentExpiryFocusAfterFrame(
      context: context,
      fallback: _goneBackFocus,
      previousFocus: previousFocus,
    );
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = (widget.playerFactory ?? AudioPlayer.new)();
    _player = player;
    _playerSubscriptions
      ..add(
        player.onPositionChanged.listen((position) {
          if (!mounted) return;
          setState(() {
            _position = position;
            _playbackError = null;
          });
        }),
      )
      ..add(
        player.onDurationChanged.listen((duration) {
          if (!mounted) return;
          setState(() => _duration = duration);
        }),
      )
      ..add(
        player.onPlayerComplete.listen((_) {
          if (!mounted) return;
          setState(() {
            _isPlaying = false;
            _position = _duration ?? _position;
          });
        }),
      );
    return player;
  }

  Future<void> _togglePlay() async {
    final url = _moment.audioUrl?.trim() ?? '';
    if (url.isEmpty) {
      setState(() => _playbackError = 'This Moment has no audio to play.');
      return;
    }
    final player = _ensurePlayer();

    if (_isPlaying) {
      try {
        await player.pause();
      } catch (_) {
        // Nothing to pause.
      }
      if (mounted) setState(() => _isPlaying = false);
      return;
    }

    final resuming = _everPlayed && _position > Duration.zero;
    setState(() {
      _isPlaying = true;
      _playbackError = null;
    });

    // Playback starting IS the viewed event, wherever it starts.
    final views = _views;
    if (!resuming && views != null) {
      unawaited(views.markViewed(_moment.id).catchError((Object _) {}));
    }

    try {
      if (resuming) {
        await player.resume();
      } else {
        _everPlayed = true;
        await player.play(UrlSource(url));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _playbackError = 'This Moment could not be played. ($error)';
      });
    }
  }

  Future<void> _seek(Duration target) async {
    final player = _player;
    if (player == null || !_everPlayed) return;
    try {
      await player.seek(target);
    } catch (_) {
      // Seeking an unloaded source is a no-op, not a fault.
    }
  }

  // ------------------------------------------------------------- actions

  Future<void> _share() async {
    // The same real link mechanism every other Moment surface uses: the
    // website resolves ?moment= on yovoice.app.
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Listen to ${_moment.authorName} on YO Voice: '
            'https://yovoice.app/?moment=${_moment.id}',
      ),
    );
  }

  Future<void> _report() async {
    await reportContent(
      context: context,
      service: widget.contentReportService,
      content: ReportedContent.voiceMoment(momentId: _moment.id),
      title: 'Report this Voice Moment',
      subtitle:
          'Your report goes to the YO Voice moderation team with this '
          'Moment attached. ${_moment.authorName} is not told who reported '
          'it.',
    );
  }

  /// The author's exit — for a permanent Moment the only one. On success
  /// the page pops back to the feed; the feed prunes the row through its
  /// own-Moments listener.
  Future<void> _confirmDelete() async {
    final service = _moments;
    if (service == null || _deleting) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final palette = dialogContext.appPalette;
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            'Delete this moment?',
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            'This cannot be undone.',
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              key: const ValueKey('moment-detail-delete-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('moment-detail-delete-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      final player = _player;
      if (player != null) {
        try {
          await player.stop();
        } catch (_) {
          // Nothing was playing.
        }
      }
      _selfDeleted = true;
      await service.deleteMoment(_moment);
    } catch (_) {
      _selfDeleted = false;
      if (!mounted) return;
      setState(() => _deleting = false);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('The Moment could not be deleted. Try again.'),
          ),
        );
      return;
    }
    if (!mounted) return;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Voice Moment deleted.'),
        ),
      );
    navigator.maybePop();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    final service = _moments;
    if (text.isEmpty || service == null || _sending) return;
    setState(() => _sending = true);
    try {
      await service.createTextComment(momentId: _moment.id, text: text);
      _composer.clear();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not post your comment.')),
        );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final gone =
        (_missing && !_selfDeleted) ||
        _expiredByDeadline ||
        !_moment.isActiveAt(_effectiveNow());

    return Scaffold(
      key: const ValueKey('moment-detail-screen'),
      backgroundColor: palette.background,
      body: SafeArea(
        child: gone
            ? _GoneState(
                backFocus: _goneBackFocus,
                onBack: () => Navigator.of(context).maybePop(),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  // One readable column at every width: the page is a
                  // mobile-first route, and on a wider window the content
                  // holds a comfortable measure instead of stretching.
                  final compact = constraints.maxWidth < 600;
                  final side = compact ? 16.0 : 24.0;
                  return Column(
                    children: [
                      _Header(
                        onBack: () => Navigator.of(context).maybePop(),
                        onShare: () => unawaited(_share()),
                      ),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: ListView(
                              padding: EdgeInsets.fromLTRB(side, 4, side, 24),
                              children: [
                                _authorBlock(),
                                const SizedBox(height: 14),
                                _captionHeading(),
                                const SizedBox(height: 16),
                                _playerPanel(),
                                if (_playbackError != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _playbackError!,
                                    style: TextStyle(
                                      color: colors.error,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                _engagementRow(),
                                _reactionsSection(),
                                const SizedBox(height: 16),
                                Divider(color: palette.border, height: 1),
                                const SizedBox(height: 14),
                                _commentsSection(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _composerBar(),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _authorBlock() {
    final moment = _moment;
    final palette = context.appPalette;
    final age = momentRelativeAge(moment.createdAt);
    // The author sees the availability fact even for a permanent Moment
    // ("Stays until deleted"); everyone else only a real countdown.
    final availability = _isOwn
        ? momentAvailabilityLabel(moment.expiresAt)
        : momentExpiryLabel(moment.expiresAt);
    return Row(
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
            radius: 23,
            photoUrl: moment.authorPhotoUrl,
            displayName: moment.authorName,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      moment.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  UserIdentityBadges(uid: moment.authorId),
                ],
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 8,
                children: [
                  if (age.isNotEmpty)
                    Text(
                      age,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  if (availability != null)
                    Text(
                      availability,
                      key: const ValueKey('moment-detail-availability'),
                      style: TextStyle(
                        // A permanent Moment's label is a calm fact, not
                        // a warning-coloured countdown.
                        color: moment.isPermanent
                            ? palette.textTertiary
                            : Theme.of(context).brightness == Brightness.dark
                            ? AppColors.warning
                            : const Color(0xFF8A4B00),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Moments carry a caption and nothing else — no separate title, no
  /// tags — so the caption IS the page heading and no tag chips exist.
  Widget _captionHeading() {
    final caption = _moment.caption.trim();
    return Text(
      caption.isEmpty ? 'Voice Moment' : caption,
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: context.appPalette.textPrimary,
        fontSize: 20,
        height: 1.35,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _playerPanel() {
    final moment = _moment;
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalSeconds = _duration?.inSeconds ?? moment.durationSeconds;
    final hasTotal = totalSeconds > 0;
    final progress = hasTotal
        ? (_position.inMilliseconds / (totalSeconds * 1000)).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(palette.surface, colors.primary, isDark ? .5 : .14)!,
            Color.lerp(palette.surface, colors.secondary, isDark ? .26 : .08)!,
            palette.surface,
          ],
        ),
        border: Border.all(color: colors.primary.withValues(alpha: .35)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, waveConstraints) {
              final waveWidth = waveConstraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: hasTotal && waveWidth > 0
                    ? (details) {
                        final fraction = (details.localPosition.dx / waveWidth)
                            .clamp(0.0, 1.0);
                        unawaited(
                          _seek(
                            Duration(
                              milliseconds: (totalSeconds * 1000 * fraction)
                                  .round(),
                            ),
                          ),
                        );
                      }
                    : null,
                child: StoryWaveform(progress: progress, height: 52),
              );
            },
          ),
          const SizedBox(height: 18),
          Semantics(
            button: true,
            label: _isPlaying ? 'Pause this Moment' : 'Play this Moment',
            child: Material(
              color: colors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                key: const ValueKey('moment-detail-play'),
                customBorder: const CircleBorder(),
                onTap: () => unawaited(_togglePlay()),
                child: SizedBox(
                  width: 62,
                  height: 62,
                  child: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: colors.onPrimary,
                    size: 34,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            hasTotal
                ? '${_clock(_position.inSeconds)} / ${_clock(totalSeconds)}'
                : '',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _engagementRow() {
    final moment = _moment;
    final feed = _feed;
    final canReport = _uid.isNotEmpty && !_isOwn;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (feed == null)
          _ActionChip(
            icon: Icons.favorite_border_rounded,
            label: moment.likeCount == 0 ? 'Like' : '${moment.likeCount}',
            active: false,
            onTap: null,
          )
        else
          StreamBuilder<bool>(
            stream: feed.watchLiked(moment.id),
            builder: (context, snapshot) {
              final liked = snapshot.hasError
                  ? false
                  : (snapshot.data ?? false);
              return _ActionChip(
                key: const ValueKey('moment-detail-like'),
                icon: liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: moment.likeCount == 0 ? 'Like' : '${moment.likeCount}',
                active: liked,
                semanticLabel: liked
                    ? 'Unlike this Moment'
                    : 'Like this Moment',
                onTap: () => unawaited(_toggleLike(feed)),
              );
            },
          ),
        _ActionChip(
          key: const ValueKey('moment-detail-comments'),
          icon: Icons.mode_comment_outlined,
          label: moment.commentCount == 0
              ? 'Comment'
              : '${moment.commentCount}',
          active: false,
          semanticLabel: 'Write a comment',
          onTap: _composerFocus.requestFocus,
        ),
        _ActionChip(
          key: const ValueKey('moment-detail-share'),
          icon: Icons.share_outlined,
          label: 'Share',
          active: false,
          semanticLabel: 'Share this Moment',
          onTap: () => unawaited(_share()),
        ),
        if (canReport)
          _ActionChip(
            key: ValueKey('moment-detail-report-${moment.id}'),
            icon: Icons.flag_outlined,
            label: 'Report',
            active: false,
            semanticLabel: 'Report this Voice Moment',
            onTap: () => unawaited(_report()),
          ),
        if (_isOwn)
          _ActionChip(
            key: ValueKey('moment-detail-delete-${moment.id}'),
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            active: false,
            destructive: true,
            semanticLabel: 'Delete this Voice Moment',
            onTap: _deleting ? null : () => unawaited(_confirmDelete()),
          ),
      ],
    );
  }

  Future<void> _toggleLike(HomeFeedService feed) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await feed.toggleLike(_moment.id);
    } catch (_) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Your like could not be saved.'),
          ),
        );
    }
  }

  /// The likers' avatar row: real `likes/{uid}` documents resolved
  /// through the public profile projection. Absent while loading, absent
  /// when nobody has liked, absent when no identity could be resolved —
  /// never a spinner, never an invented face.
  Widget _reactionsSection() {
    final reactions = _reactions;
    final likeCount = _moment.likeCount;
    if (reactions == null || likeCount <= 0) return const SizedBox.shrink();
    return FutureBuilder<List<MomentReactor>>(
      future: reactions,
      builder: (context, snapshot) {
        final palette = context.appPalette;
        final reactors = snapshot.data ?? const <MomentReactor>[];
        if (reactors.isEmpty) return const SizedBox.shrink();
        final remainder = likeCount - reactors.length;
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Top reactions',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                key: const ValueKey('moment-detail-reactions'),
                children: [
                  for (final reactor in reactors)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Tooltip(
                        message: reactor.displayName,
                        child: UserAvatar(
                          radius: 15,
                          photoUrl: reactor.photoUrl,
                          displayName: reactor.displayName,
                        ),
                      ),
                    ),
                  if (remainder > 0)
                    Container(
                      // Content-sized, not a fixed circle: "+409" is a
                      // real value here and must widen the pill instead
                      // of wrapping and clipping inside 30 px.
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: palette.surfaceRaised,
                        border: Border.all(color: palette.border),
                      ),
                      child: Text(
                        '+$remainder',
                        maxLines: 1,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  int? _loadedCommentCount;

  Widget _commentsSection() {
    final service = _moments;
    final palette = context.appPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // The header counts what the STREAM shows once it has loaded
          // (falling back to the doc counter only while loading), so a
          // drifted counter can never render "Comments (1)" directly above
          // "Be the first to comment." — the contradiction the review
          // photographed.
          _loadedCommentCount == null
              ? (_moment.commentCount > 0
                    ? 'Comments (${_moment.commentCount})'
                    : 'Comments')
              : (_loadedCommentCount! > 0
                    ? 'Comments ($_loadedCommentCount)'
                    : 'Comments'),
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        if (service == null)
          Text(
            'Comments are unavailable right now.',
            style: TextStyle(color: palette.textTertiary, fontSize: 12.5),
          )
        else
          StreamBuilder<List<MomentComment>>(
            stream: service.watchComments(_moment.id),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  'Could not load comments.',
                  style: TextStyle(color: palette.textTertiary, fontSize: 12.5),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final comments = snapshot.data!;
              if (_loadedCommentCount != comments.length) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() => _loadedCommentCount = comments.length);
                  }
                });
              }
              if (comments.isEmpty) {
                return Text(
                  'Be the first to comment.',
                  style: TextStyle(color: palette.textTertiary, fontSize: 12.5),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final comment in comments) _CommentRow(comment: comment),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _composerBar() {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('moment-detail-comment-field'),
              controller: _composer,
              focusNode: _composerFocus,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => unawaited(_send()),
              enabled: _moments != null,
              style: TextStyle(color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: 'Write a comment...',
                hintStyle: TextStyle(color: palette.textTertiary),
                filled: true,
                fillColor: palette.surfaceSunken,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            key: const ValueKey('moment-detail-comment-send'),
            onPressed: _sending || _moments == null
                ? null
                : () => unawaited(_send()),
            style: IconButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
            ),
            icon: _sending
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onPrimary,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

/// Back and Share — the page's own chrome, present in both hosting modes
/// (the shell keeps the bottom navigation, a plain push keeps only this).
class _Header extends StatelessWidget {
  const _Header({required this.onBack, required this.onShare});

  final VoidCallback onBack;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('moment-detail-back'),
            onPressed: onBack,
            tooltip: 'Back',
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            icon: Icon(Icons.arrow_back_rounded, color: palette.textPrimary),
          ),
          Expanded(
            child: Text(
              'Moment',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('moment-detail-share-top'),
            onPressed: onShare,
            tooltip: 'Share this Moment',
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            icon: Icon(Icons.share_outlined, color: palette.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// The graceful gone-state: the Moment expired, was deleted, or never
/// loaded. A real explanation and a way back — never a spinner that spins
/// forever and never a stale page pretending the audio still exists.
class _GoneState extends StatelessWidget {
  const _GoneState({required this.backFocus, required this.onBack});

  final FocusNode backFocus;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Center(
      key: const ValueKey('moment-detail-gone'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer_off_outlined,
              size: 34,
              color: palette.textSecondary,
            ),
            const SizedBox(height: 14),
            Text(
              'This Moment is no longer available',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'It reached the end of its availability or was deleted by '
              'its author.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('moment-detail-gone-back'),
              focusNode: backFocus,
              onPressed: onBack,
              child: const Text('Back to Moments'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});

  final MomentComment comment;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            radius: 15,
            photoUrl: comment.authorPhotoUrl,
            displayName: comment.authorName,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      comment.authorName,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    UserIdentityBadges(
                      uid: comment.authorId,
                      variant: IdentityBadgeVariant.icon,
                    ),
                    Text(
                      momentRelativeAge(comment.createdAt),
                      style: TextStyle(
                        color: palette.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // No like counts on comments: comment documents carry
                // none in the schema, so none are printed.
                if (comment.isVoice)
                  Text(
                    'Voice reply · ${comment.durationSeconds}s'
                    '${comment.text.isNotEmpty ? ' — ${comment.text}' : ''}',
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  )
                else
                  Text(
                    comment.text,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                      height: 1.4,
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

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.destructive = false,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool active;

  /// Delete wears the error tint so a destructive action never looks
  /// like one more neutral chip.
  final bool destructive;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final tint = destructive
        ? colors.error
        : (active ? colors.secondary : palette.textSecondary);
    return Semantics(
      button: onTap != null,
      label: semanticLabel ?? label,
      child: Material(
        color: destructive ? palette.dangerSurface : palette.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: tint),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: destructive ? colors.error : palette.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _clock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}
