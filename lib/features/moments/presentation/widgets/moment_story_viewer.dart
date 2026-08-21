import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_content_flow.dart';
import 'package:yovoice/features/moments/data/models/moment_chain.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_time_labels.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Opens one author's chain in the story viewer.
///
/// Desktop (a window 1100 pt or wider) gets a centred overlay dialog so
/// the feed stays visible behind it; anything narrower gets a full-screen
/// route — a stories surface pretending to be a phone sheet on a desktop,
/// or a floating card on a phone, is the exact stretched-layout failure
/// the responsive rules exist to prevent. Both carry a visible close
/// control; the route additionally pops on the system Back.
Future<void> showMomentStoryViewer(
  BuildContext context, {
  required MomentChain chain,
  int? initialIndex,
  HomeFeedService? feedService,
  MomentService? momentService,
  MomentViewsService? viewsService,
  ContentReportService? contentReportService,
  FirebaseAuth? auth,
  AudioPlayer Function()? playerFactory,
}) async {
  final viewer = MomentStoryViewer(
    chain: chain,
    initialIndex: initialIndex ?? 0,
    feedService: feedService,
    momentService: momentService,
    viewsService: viewsService,
    contentReportService: contentReportService,
    auth: auth,
    playerFactory: playerFactory,
  );

  final wide = MediaQuery.sizeOf(context).width >= 1100;
  if (wide) {
    await showDialog<void>(
      context: context,
      barrierColor: AppColors.black.withValues(alpha: .72),
      builder: (dialogContext) {
        final viewport = MediaQuery.sizeOf(dialogContext);
        return Dialog(
          backgroundColor: AppColors.background,
          insetPadding: const EdgeInsets.symmetric(vertical: 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: AppColors.border.withValues(alpha: .6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 420,
            height: (viewport.height - 56).clamp(420.0, 780.0),
            child: viewer,
          ),
        );
      },
    );
    return;
  }

  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) =>
          Scaffold(backgroundColor: AppColors.background, body: viewer),
    ),
  );
}

/// The stories surface: one author's Moments, oldest → newest, with a
/// thin progress bar per Moment, "1 of 3", previous/next everywhere a
/// hand or a keyboard can reach, and auto-advance when a Moment finishes
/// playing.
///
/// Everything rendered is something the data can prove: the elapsed fill
/// comes from the player's reported position, the counts are the
/// document's counters, the age and expiry copy come from the real
/// timestamps. The one write this surface makes is the caller's own
/// viewed-mark (`users/{uid}/momentViews/{momentId}`), recorded when
/// playback of a Moment starts.
class MomentStoryViewer extends StatefulWidget {
  const MomentStoryViewer({
    required this.chain,
    this.initialIndex = 0,
    this.feedService,
    this.momentService,
    this.viewsService,
    this.contentReportService,
    this.auth,
    this.playerFactory,
    this.autoPlay = true,
    super.key,
  });

  final MomentChain chain;
  final int initialIndex;

  /// Backs the like control; when it cannot be constructed the heart is
  /// an inert indicator, never a control that silently fails.
  final HomeFeedService? feedService;

  /// Re-reads the Moment on screen so a like made inside the viewer moves
  /// its own counter.
  final MomentService? momentService;

  /// Records the caller's viewed-mark when playback starts.
  final MomentViewsService? viewsService;

  /// Injection seam for the report flow; production passes nothing.
  final ContentReportService? contentReportService;

  /// Injection seam for the viewer's identity — report is hidden on your
  /// own Moment and for a signed-out viewer.
  final FirebaseAuth? auth;

  @visibleForTesting
  final AudioPlayer Function()? playerFactory;

  /// True in production: tapping a chain means "play this person".
  /// Tests turn it off to drive playback explicitly.
  final bool autoPlay;

  @override
  State<MomentStoryViewer> createState() => _MomentStoryViewerState();
}

class _MomentStoryViewerState extends State<MomentStoryViewer> {
  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  MomentViewsService? _views;
  MomentService? _moments;
  HomeFeedService? _feed;

  late int _index = widget.initialIndex.clamp(0, widget.chain.length - 1);
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  String? _playbackError;

  String get _uid {
    try {
      return (widget.auth ?? FirebaseAuth.instance).currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  VoiceMoment get _current => widget.chain.moments[_index];

  @override
  void initState() {
    super.initState();
    // Each seam guarded separately, matching MomentsScreen: one service
    // that cannot be constructed (no Firebase app, a preview harness)
    // must not take the others down with it.
    try {
      _views = widget.viewsService ?? MomentViewsService();
    } catch (_) {
      _views = null;
    }
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
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_play(_current));
      });
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _player?.dispose();
    super.dispose();
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = (widget.playerFactory ?? AudioPlayer.new)();
    _player = player;
    _subscriptions
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
          _advanceAfterCompletion();
        }),
      );
    return player;
  }

  /// Auto-advance: the finished Moment fills its bar and the next one
  /// starts. Finishing the LAST Moment closes the viewer — the chain has
  /// been told in full, and an inert surface pretending to still play is
  /// worse than returning to the feed.
  void _advanceAfterCompletion() {
    if (_index < widget.chain.length - 1) {
      unawaited(_goTo(_index + 1, play: true));
    } else {
      setState(() {
        _isPlaying = false;
        _position = _duration ?? _position;
      });
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _play(VoiceMoment moment) async {
    final url = moment.audioUrl?.trim() ?? '';
    if (url.isEmpty) {
      setState(() {
        _isPlaying = false;
        _playbackError = 'This Moment has no audio to play.';
      });
      return;
    }
    final player = _ensurePlayer();
    setState(() {
      _isPlaying = true;
      _playbackError = null;
    });
    // The viewed-mark is written when playback STARTS, not when it
    // finishes — matching the product contract — and never blocks or
    // fails playback.
    final views = _views;
    if (views != null) {
      unawaited(
        views.markViewed(moment.id).catchError((Object _) {
          // A failed viewed-write is invisible by design; the Moment
          // still plays and the chain simply stays "unviewed" until a
          // later listen succeeds.
        }),
      );
    }
    try {
      await player.play(UrlSource(url));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _playbackError = 'This Moment could not be played. ($error)';
      });
    }
  }

  Future<void> _togglePlay() async {
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
    if (_position > Duration.zero) {
      setState(() => _isPlaying = true);
      try {
        await player.resume();
      } catch (_) {
        if (mounted) setState(() => _isPlaying = false);
      }
      return;
    }
    await _play(_current);
  }

  Future<void> _goTo(int index, {required bool play}) async {
    if (index < 0 || index >= widget.chain.length) return;
    final player = _player;
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {
        // Stopping a player that never started is not a fault.
      }
    }
    if (!mounted) return;
    setState(() {
      _index = index;
      _isPlaying = false;
      _position = Duration.zero;
      _duration = null;
      _playbackError = null;
    });
    if (play) await _play(_current);
  }

  Future<void> _openComments(VoiceMoment moment) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MomentCommentsScreen(
          moment: moment,
          momentService: widget.momentService,
          auth: widget.auth,
          contentReportService: widget.contentReportService,
        ),
      ),
    );
  }

  Future<void> _report(VoiceMoment moment) async {
    await reportContent(
      context: context,
      service: widget.contentReportService,
      content: ReportedContent.voiceMoment(momentId: moment.id),
      title: 'Report this Voice Moment',
      subtitle:
          'Your report goes to the YO Voice moderation team with this '
          'Moment attached. ${moment.authorName} is not told who reported '
          'it.',
    );
  }

  double _fillFor(int barIndex, VoiceMoment current) {
    if (barIndex < _index) return 1;
    if (barIndex > _index) return 0;
    final totalSeconds = _duration?.inSeconds ?? current.durationSeconds;
    if (totalSeconds <= 0) return 0;
    return (_position.inMilliseconds / (totalSeconds * 1000)).clamp(0.0, 1.0);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(_goTo(_index + 1, play: widget.autoPlay));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      unawaited(_goTo(_index - 1, play: widget.autoPlay));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      unawaited(_togglePlay());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final chain = widget.chain;
    final loaded = _current;
    final uid = _uid;
    final live = _moments?.watchMoment(loaded.id);

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: StreamBuilder<VoiceMoment>(
        stream: live,
        initialData: loaded,
        builder: (context, snapshot) {
          // A failed or empty document stream keeps the Moment the chain
          // carried: real, just not live.
          final moment =
              (snapshot.hasData && snapshot.data!.id == loaded.id)
              ? snapshot.data!
              : loaded;
          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: _ProgressBars(
                    key: const ValueKey('story-progress-bars'),
                    count: chain.length,
                    fillFor: (i) => _fillFor(i, moment),
                  ),
                ),
                _StoryHeader(
                  moment: moment,
                  position: _index,
                  total: chain.length,
                  onClose: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: _StoryStage(
                    moment: moment,
                    isPlaying: _isPlaying,
                    position: _position,
                    duration: _duration,
                    playbackError: _playbackError,
                    onToggle: () => unawaited(_togglePlay()),
                    onPreviousZone: _index > 0
                        ? () => unawaited(
                            _goTo(_index - 1, play: widget.autoPlay),
                          )
                        : null,
                    onNextZone: _index < chain.length - 1
                        ? () => unawaited(
                            _goTo(_index + 1, play: widget.autoPlay),
                          )
                        : null,
                  ),
                ),
                _StoryActions(
                  moment: moment,
                  feedService: _feed,
                  canReport: uid.isNotEmpty && uid != moment.authorId,
                  onComments: () => unawaited(_openComments(moment)),
                  onReport: () => unawaited(_report(moment)),
                  onPrevious: _index > 0
                      ? () =>
                            unawaited(_goTo(_index - 1, play: widget.autoPlay))
                      : null,
                  onNext: _index < chain.length - 1
                      ? () =>
                            unawaited(_goTo(_index + 1, play: widget.autoPlay))
                      : null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One thin bar per Moment in the chain. The elapsed fill of the current
/// bar is the player's real position; bars before it are full, bars after
/// it empty — the standard stories grammar, drawn from measured playback
/// rather than an animation timer.
class _ProgressBars extends StatelessWidget {
  const _ProgressBars({required this.count, required this.fillFor, super.key});

  final int count;
  final double Function(int index) fillFor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 3.5,
                child: Stack(
                  children: [
                    Container(color: AppColors.surfaceLight),
                    FractionallySizedBox(
                      widthFactor: fillFor(i).clamp(0.0, 1.0),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primary, AppColors.secondary],
                          ),
                        ),
                        child: SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StoryHeader extends StatelessWidget {
  const _StoryHeader({
    required this.moment,
    required this.position,
    required this.total,
    required this.onClose,
  });

  final VoiceMoment moment;
  final int position;
  final int total;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final age = momentRelativeAge(moment.createdAt);
    final expiry = momentExpiryLabel(moment.expiresAt);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
      child: Row(
        children: [
          UserAvatar(
            radius: 20,
            photoUrl: moment.authorPhotoUrl,
            displayName: moment.authorName,
          ),
          const SizedBox(width: 10),
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
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    UserIdentityBadges(uid: moment.authorId),
                  ],
                ),
                const SizedBox(height: 1),
                Wrap(
                  spacing: 8,
                  children: [
                    if (age.isNotEmpty)
                      Text(
                        age,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    if (expiry != null)
                      Text(
                        expiry,
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${position + 1} of $total',
            key: const ValueKey('story-position-indicator'),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            key: const ValueKey('story-close'),
            onPressed: onClose,
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// The listening stage: caption, the waveform silhouette with the real
/// elapsed fill, the big play/pause, and the invisible previous/next tap
/// zones flanking it.
class _StoryStage extends StatelessWidget {
  const _StoryStage({
    required this.moment,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.playbackError,
    required this.onToggle,
    required this.onPreviousZone,
    required this.onNextZone,
  });

  final VoiceMoment moment;
  final bool isPlaying;
  final Duration position;
  final Duration? duration;
  final String? playbackError;
  final VoidCallback onToggle;
  final VoidCallback? onPreviousZone;
  final VoidCallback? onNextZone;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = duration?.inSeconds ?? moment.durationSeconds;
    final hasTotal = totalSeconds > 0;
    final progress = hasTotal
        ? (position.inMilliseconds / (totalSeconds * 1000)).clamp(0.0, 1.0)
        : 0.0;

    final center = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (moment.caption.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 0, 26, 22),
            child: Text(
              moment.caption,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34),
          child: StoryWaveform(progress: progress),
        ),
        const SizedBox(height: 22),
        Semantics(
          button: true,
          label: isPlaying ? 'Pause this Moment' : 'Play this Moment',
          child: Material(
            color: AppColors.primary,
            shape: const CircleBorder(),
            child: InkWell(
              key: const ValueKey('story-play-toggle'),
              customBorder: const CircleBorder(),
              onTap: onToggle,
              child: SizedBox(
                width: 64,
                height: 64,
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: AppColors.textPrimary,
                  size: 34,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          hasTotal
              ? '${_clock(position.inSeconds)} / ${_clock(totalSeconds)}'
              : '',
          style: const TextStyle(
            color: AppColors.textHint,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (playbackError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 10, 26, 0),
            child: Text(
              playbackError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.error, fontSize: 12.5),
            ),
          ),
      ],
    );

    // The tap zones are supplements, never the only way through: the
    // action row below carries visible previous/next buttons and the
    // whole surface answers the arrow keys.
    return Stack(
      children: [
        Positioned.fill(child: center),
        if (onPreviousZone != null)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 72,
            child: ExcludeSemantics(
              child: GestureDetector(
                key: const ValueKey('story-tap-previous'),
                behavior: HitTestBehavior.translucent,
                onTap: onPreviousZone,
              ),
            ),
          ),
        if (onNextZone != null)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 72,
            child: ExcludeSemantics(
              child: GestureDetector(
                key: const ValueKey('story-tap-next'),
                behavior: HitTestBehavior.translucent,
                onTap: onNextZone,
              ),
            ),
          ),
      ],
    );
  }
}

/// The ornament silhouette shared by the story stage. The bar shape is
/// decoration — no per-Moment amplitude data exists and inventing a shape
/// would be fabricated data — but the fill sweeping across it is real:
/// it is the player's reported position.
class StoryWaveform extends StatelessWidget {
  const StoryWaveform({required this.progress, this.height = 44, super.key});

  final double progress;
  final double height;

  static const bars = <double>[
    .3, .55, .4, .75, .5, .85, .45, .6, .35, .7,
    .5, .9, .4, .65, .3, .55, .8, .45, .6, .35,
    .5, .7, .4, .85, .55, .3, .65, .5, .75, .4,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < bars.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.3),
                child: Container(
                  height: height * bars[i],
                  decoration: BoxDecoration(
                    color: (i / bars.length) < progress
                        ? AppColors.secondary
                        : AppColors.primary.withValues(alpha: .32),
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

/// Like, comment, report — the existing services, real counts — plus the
/// visible previous/next controls that keep the chain reachable without
/// gestures or a keyboard.
class _StoryActions extends StatelessWidget {
  const _StoryActions({
    required this.moment,
    required this.feedService,
    required this.canReport,
    required this.onComments,
    required this.onReport,
    required this.onPrevious,
    required this.onNext,
  });

  final VoiceMoment moment;
  final HomeFeedService? feedService;
  final bool canReport;
  final VoidCallback onComments;
  final VoidCallback onReport;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final service = feedService;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Row(
        children: [
          IconButton.filledTonal(
            key: const ValueKey('story-previous'),
            onPressed: onPrevious,
            tooltip: 'Previous Moment',
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            key: const ValueKey('story-next'),
            onPressed: onNext,
            tooltip: 'Next Moment',
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          // One Expanded cluster aligned right — NOT a Spacer next to
          // Flexible chips. A Spacer is itself a flex child, so it takes
          // an equal share of the free space and starves the chips of
          // their counts even when the row has room; inside this cluster
          // the chips only squeeze (their labels ellipsize) when the
          // width genuinely runs out, and the report control never
          // leaves the screen.
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (service == null)
                  Flexible(
                    child: _ActionChip(
                      icon: Icons.favorite_border_rounded,
                      label: moment.likeCount == 0
                          ? 'Like'
                          : '${moment.likeCount}',
                      active: false,
                      onTap: null,
                    ),
                  )
                else
                  Flexible(
                    child: StreamBuilder<bool>(
                      stream: service.watchLiked(moment.id),
                      builder: (context, snapshot) {
                        final liked = snapshot.hasError
                            ? false
                            : (snapshot.data ?? false);
                        return _ActionChip(
                          key: const ValueKey('story-like'),
                          icon: liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          label: moment.likeCount == 0
                              ? 'Like'
                              : '${moment.likeCount}',
                          active: liked,
                          semanticLabel: liked
                              ? 'Unlike this Moment'
                              : 'Like this Moment',
                          onTap: () =>
                              unawaited(_toggleLike(context, service)),
                        );
                      },
                    ),
                  ),
                const SizedBox(width: 6),
                Flexible(
                  child: _ActionChip(
                    key: const ValueKey('story-comments'),
                    icon: Icons.mode_comment_outlined,
                    label: moment.commentCount == 0
                        ? 'Comment'
                        : '${moment.commentCount}',
                    active: false,
                    semanticLabel: 'Open comments for this Moment',
                    onTap: onComments,
                  ),
                ),
                if (canReport) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    key: ValueKey('story-report-${moment.id}'),
                    onPressed: onReport,
                    tooltip: 'Report this Voice Moment',
                    icon: const Icon(
                      Icons.flag_outlined,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLike(
    BuildContext context,
    HomeFeedService service,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await service.toggleLike(moment.id);
    } catch (error) {
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
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: semanticLabel ?? label,
      child: Material(
        color: AppColors.surface.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 60),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: active ? AppColors.secondary : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
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
