import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Widths this surface designs for. The shell's own desktop breakpoint
/// is 1100 on the WINDOW; these are measured on the space this view
/// actually receives (the window minus the 264 pt rail on desktop), so
/// the layout responds to the room it has rather than to the window.
const double _tabletWidth = 600;
const double _stageWidth = 980;

/// A discovery stack of published Voice Moments from every user: one
/// Moment per viewport, swipe (or Previous/Next, or the arrow keys) to
/// move through it.
///
/// The gesture is never the only way through — a pager that can only be
/// swiped is unusable with a keyboard, a screen reader, or a trackpad on
/// desktop.
class MomentDiscoveryView extends StatefulWidget {
  const MomentDiscoveryView({
    required this.onOpenComments,
    required this.onRecord,
    this.discoveryService,
    this.feedService,
    this.isVisible,
    this.playerFactory,
    super.key,
  });

  final ValueChanged<VoiceMoment> onOpenComments;
  final VoidCallback onRecord;
  final MomentDiscoveryService? discoveryService;
  final HomeFeedService? feedService;

  /// False while the shell is showing another tab. The desktop shell
  /// keeps every slot mounted in an IndexedStack — hidden children stay
  /// built and are never notified — so without this the audio would keep
  /// playing from an invisible tab.
  final ValueListenable<bool>? isVisible;

  @visibleForTesting
  final AudioPlayer Function()? playerFactory;

  @override
  State<MomentDiscoveryView> createState() => _MomentDiscoveryViewState();
}

enum _Phase { loading, error, ready }

class _MomentDiscoveryViewState extends State<MomentDiscoveryView> {
  late final MomentDiscoveryService _discovery;
  HomeFeedService? _feed;
  AudioPlayer? _player;
  final PageController _pages = PageController();

  _Phase _phase = _Phase.loading;
  Object? _error;
  MomentDiscoveryFeed? _result;
  int _index = 0;

  /// Real, counted, local. Never displayed unless it was measured.
  final Set<String> _listenedTo = <String>{};

  String? _playingId;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  String? _playbackError;

  /// Guards the "started but produced nothing" case — the family the web
  /// MissingPluginException belonged to. A play() that neither throws
  /// nor advances is a silent failure, and silence is the one outcome
  /// this screen may not show.
  Timer? _playWatchdog;
  Timer? _loadWatchdog;
  bool _loadIsSlow = false;

  final List<StreamSubscription<dynamic>> _playerSubscriptions =
      <StreamSubscription<dynamic>>[];

  /// Guarded — see the note on MomentsScreen: `FirebaseAuth.instance`
  /// throws outright when no Firebase app exists.
  String get _uid {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _discovery = widget.discoveryService ?? MomentDiscoveryService();
    try {
      _feed = widget.feedService ?? HomeFeedService();
    } catch (_) {
      // No session yet, or a preview harness: the stack still renders
      // and reads; only the like control disables itself.
      _feed = null;
    }
    widget.isVisible?.addListener(_handleVisibility);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.isVisible?.removeListener(_handleVisibility);
    _playWatchdog?.cancel();
    _loadWatchdog?.cancel();
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
    _pages.dispose();
    _player?.dispose();
    super.dispose();
  }

  void _handleVisibility() {
    if (widget.isVisible?.value == false) {
      unawaited(_stop());
    }
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = (widget.playerFactory ?? AudioPlayer.new)();
    _player = player;
    _playerSubscriptions
      ..add(
        player.onPositionChanged.listen((position) {
          _playWatchdog?.cancel();
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

  Future<void> _load({int? seed}) async {
    _loadWatchdog?.cancel();
    setState(() {
      _phase = _Phase.loading;
      _error = null;
      _loadIsSlow = false;
    });
    // An indefinite skeleton is how a broken load disguises itself as a
    // slow one.
    _loadWatchdog = Timer(const Duration(seconds: 8), () {
      if (mounted && _phase == _Phase.loading) {
        setState(() => _loadIsSlow = true);
      }
    });
    await _stop();
    try {
      final result = await _discovery.loadDiscoveryFeed(seed: seed);
      _loadWatchdog?.cancel();
      if (!mounted) return;
      setState(() {
        _result = result;
        _index = 0;
        _phase = _Phase.ready;
      });
      if (_pages.hasClients) _pages.jumpToPage(0);
    } catch (error) {
      _loadWatchdog?.cancel();
      if (!mounted) return;
      setState(() {
        _error = error;
        _phase = _Phase.error;
      });
    }
  }

  Future<void> _stop() async {
    final player = _player;
    _playWatchdog?.cancel();
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {
        // Stopping a player that never started is not an error worth
        // surfacing.
      }
    }
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _playingId = null;
      _position = Duration.zero;
      _duration = null;
    });
  }

  Future<void> _togglePlay(VoiceMoment moment) async {
    final url = moment.audioUrl?.trim() ?? '';
    if (url.isEmpty) return;
    final player = _ensurePlayer();

    if (_playingId == moment.id && _isPlaying) {
      try {
        await player.pause();
      } catch (_) {
        // Nothing to pause.
      }
      if (mounted) setState(() => _isPlaying = false);
      return;
    }

    setState(() {
      _playbackError = null;
      if (_playingId != moment.id) {
        _position = Duration.zero;
        _duration = null;
      }
      _playingId = moment.id;
      _isPlaying = true;
    });
    _listenedTo.add(moment.id);

    try {
      if (_playingId == moment.id && _position > Duration.zero) {
        await player.resume();
      } else {
        await player.play(UrlSource(url));
      }
      _playWatchdog?.cancel();
      _playWatchdog = Timer(const Duration(milliseconds: 1500), () {
        if (!mounted || !_isPlaying || _position > Duration.zero) return;
        setState(() {
          _isPlaying = false;
          _playbackError =
              'This Moment did not start playing on this device. '
              'Tap play to try again.';
        });
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _playbackError = 'This Moment could not be played. ($error)';
      });
    }
  }

  void _goTo(int index) {
    final total = _result?.moments.length ?? 0;
    // The end card is one past the last Moment.
    if (index < 0 || index > total) return;
    unawaited(_stop());
    setState(() => _index = index);
    if (_pages.hasClients) {
      unawaited(
        _pages.animateToPage(
          index,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final body = switch (_phase) {
          _Phase.loading => _LoadingStack(isSlow: _loadIsSlow, onRetry: _load),
          _Phase.error => _ErrorStack(error: _error, onRetry: _load),
          _Phase.ready => _buildReady(width),
        };
        return Container(color: AppColors.background, child: body);
      },
    );
  }

  Widget _buildReady(double width) {
    final result = _result!;
    if (result.corpusIsEmpty) {
      return _EmptyStack(
        icon: Icons.mic_none_rounded,
        title: 'No Voice Moments yet',
        body:
            'Nobody has published one. Be the first — record up to '
            '60 seconds and it appears here for everyone.',
        actionLabel: 'Record a Moment',
        onAction: widget.onRecord,
      );
    }
    if (result.everythingFiltered) {
      // Deliberately NOT the same message as an empty corpus. Published
      // Moments exist and none of them can be played — that is an upload
      // pipeline failure, not a quiet launch week, and collapsing the two
      // is how such a failure stays invisible.
      return _EmptyStack(
        icon: Icons.error_outline_rounded,
        title: 'Nothing playable right now',
        body:
            '${result.fetchedCount} published '
            '${result.fetchedCount == 1 ? 'Moment' : 'Moments'} could not be '
            'played back. This is usually temporary.',
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    final moments = result.moments;
    final stage = Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pages,
            scrollDirection: Axis.vertical,
            onPageChanged: (index) {
              unawaited(_stop());
              setState(() => _index = index);
            },
            itemCount: moments.length + 1,
            itemBuilder: (context, index) {
              if (index == moments.length) {
                return _EndOfStack(
                  listenedCount: _listenedTo.length,
                  total: moments.length,
                  moreExists: result.poolExhausted,
                  onShuffleAgain: () => _load(),
                  onRecord: widget.onRecord,
                  onBackToStart: () => _goTo(0),
                );
              }
              final moment = moments[index];
              return _MomentStagePane(
                moment: moment,
                position: index,
                total: moments.length,
                compact: width < _tabletWidth,
                isCurrent: index == _index,
                isPlaying: _playingId == moment.id && _isPlaying,
                elapsed: _playingId == moment.id ? _position : Duration.zero,
                duration: _playingId == moment.id ? _duration : null,
                playbackError: _playingId == moment.id ? _playbackError : null,
                feedService: _feed,
                currentUserId: _uid,
                onTogglePlay: () => _togglePlay(moment),
                onComments: () => widget.onOpenComments(moment),
                onSeek: (target) async {
                  final player = _player;
                  if (player == null || _playingId != moment.id) return;
                  try {
                    await player.seek(target);
                  } catch (_) {
                    // Seeking an unloaded source is a no-op, not a fault.
                  }
                },
              );
            },
          ),
        ),
        _PagerControls(
          index: _index,
          total: moments.length,
          onPrevious: _index > 0 ? () => _goTo(_index - 1) : null,
          onNext: _index < moments.length ? () => _goTo(_index + 1) : null,
          onShuffle: () => _load(),
        ),
      ],
    );

    // Desktop: stage plus a real queue, so the shuffled order has a
    // visible shape and any entry can be jumped to directly.
    if (width >= _stageWidth) {
      // A real key handler, not a `Shortcuts` map with no `Actions` to
      // dispatch into — that compiles, reads as keyboard support, and
      // does nothing.
      return Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _goTo(_index + 1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _goTo(_index - 1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.space &&
              _index < moments.length) {
            unawaited(_togglePlay(moments[_index]));
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: stage),
            _QueuePane(moments: moments, index: _index, onSelect: _goTo),
          ],
        ),
      );
    }

    // Tablet: the pager is centred at a readable measure rather than a
    // phone card stretched across 1024 pt.
    if (width >= _tabletWidth) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: stage,
        ),
      );
    }
    return stage;
  }
}

/// One Moment, filling the viewport. The transport row is pinned to the
/// bottom of the pane so the play control never scrolls out of reach
/// behind a long caption.
class _MomentStagePane extends StatelessWidget {
  const _MomentStagePane({
    required this.moment,
    required this.position,
    required this.total,
    required this.compact,
    required this.isCurrent,
    required this.isPlaying,
    required this.elapsed,
    required this.duration,
    required this.playbackError,
    required this.feedService,
    required this.currentUserId,
    required this.onTogglePlay,
    required this.onComments,
    required this.onSeek,
  });

  final VoiceMoment moment;
  final int position;
  final int total;
  final bool compact;
  final bool isCurrent;
  final bool isPlaying;
  final Duration elapsed;
  final Duration? duration;
  final String? playbackError;
  final HomeFeedService? feedService;
  final String currentUserId;
  final VoidCallback onTogglePlay;
  final VoidCallback onComments;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final avatarRadius = compact ? 22.0 : 28.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 20 : 28, 18, compact ? 20 : 28, 8),
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
                  radius: avatarRadius,
                  photoUrl: moment.authorPhotoUrl,
                  displayName: moment.authorName,
                ),
              ),
              const SizedBox(width: 12),
              // Row, not Wrap: a long display name must truncate and
              // leave the identity badges in place, never push them onto
              // a second line or off the row entirely.
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
                              color: AppColors.textPrimary,
                              fontSize: compact ? 15 : 16.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        UserIdentityBadges(uid: moment.authorId),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _relativeAge(moment.createdAt),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${position + 1} of $total',
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (moment.caption.trim().isNotEmpty)
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  moment.caption,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: compact ? 16 : 18,
                    height: 1.45,
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          if (playbackError != null) ...[
            const SizedBox(height: 8),
            Text(
              playbackError!,
              style: const TextStyle(color: AppColors.error, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 14),
          _Transport(
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: duration,
            declaredSeconds: moment.durationSeconds,
            onTogglePlay: onTogglePlay,
            onSeek: onSeek,
          ),
          const SizedBox(height: 10),
          _ActionsRow(
            moment: moment,
            feedService: feedService,
            onComments: onComments,
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// Play control, a scrubber over the waveform silhouette, and the real
/// elapsed/total time.
class _Transport extends StatelessWidget {
  const _Transport({
    required this.isPlaying,
    required this.elapsed,
    required this.duration,
    required this.declaredSeconds,
    required this.onTogglePlay,
    required this.onSeek,
  });

  final bool isPlaying;
  final Duration elapsed;
  final Duration? duration;
  final int declaredSeconds;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    // The real, measured total: the player's duration when it has one,
    // otherwise the stored value. When neither is known the label is
    // hidden rather than asserting "0:00".
    final totalSeconds = duration?.inSeconds ?? declaredSeconds;
    final hasTotal = totalSeconds > 0;
    final progress = hasTotal
        ? (elapsed.inMilliseconds / (totalSeconds * 1000)).clamp(0.0, 1.0)
        : 0.0;

    return Row(
      children: [
        Semantics(
          button: true,
          label: isPlaying ? 'Pause this Moment' : 'Play this Moment',
          child: Material(
            color: AppColors.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTogglePlay,
              child: SizedBox(
                // 56 pt: comfortably over the 48 pt minimum, and this is
                // the single most important control on the surface.
                width: 56,
                height: 56,
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: AppColors.textPrimary,
                  size: 30,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProgressWaveform(
                progress: progress,
                enabled: hasTotal,
                onSeekFraction: (fraction) => onSeek(
                  Duration(
                    milliseconds: (totalSeconds * 1000 * fraction).round(),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                hasTotal
                    ? '${_clock(elapsed.inSeconds)} / ${_clock(totalSeconds)}'
                    : '',
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The bar silhouette is ORNAMENT — there is no recorded per-Moment
/// amplitude data and inventing a shape per Moment would be fabricated
/// data. The fill sweeping across it is real: it is driven by the
/// player's reported position.
class _ProgressWaveform extends StatelessWidget {
  const _ProgressWaveform({
    required this.progress,
    required this.enabled,
    required this.onSeekFraction,
  });

  final double progress;
  final bool enabled;
  final ValueChanged<double> onSeekFraction;

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Semantics(
          slider: true,
          label: 'Playback position',
          value: '${(progress * 100).round()} percent',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled
                ? (details) => onSeekFraction(
                    (details.localPosition.dx / width).clamp(0.0, 1.0),
                  )
                : null,
            onHorizontalDragUpdate: enabled
                ? (details) => onSeekFraction(
                    (details.localPosition.dx / width).clamp(0.0, 1.0),
                  )
                : null,
            child: SizedBox(
              // 48 pt of hit slop around a 30 pt visual.
              height: 48,
              child: Center(
                child: SizedBox(
                  height: 30,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _bars.length; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 1.4,
                            ),
                            child: Container(
                              height: 30 * _bars[i],
                              decoration: BoxDecoration(
                                color: (i / _bars.length) < progress
                                    ? AppColors.secondary
                                    : AppColors.primary.withValues(alpha: .32),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Like, comment, and the real counts.
///
/// The heart is a REAL button here. Before this change the Moments
/// screen rendered a heart and a like count as static text with no tap
/// target: it displayed engagement it gave you no way to create, while
/// the backing service (`HomeFeedService.toggleLike` / `watchLiked` and
/// the `setMomentLike` callable) worked and Home already used it.
class _ActionsRow extends StatelessWidget {
  const _ActionsRow({
    required this.moment,
    required this.feedService,
    required this.onComments,
  });

  final VoiceMoment moment;
  final HomeFeedService? feedService;
  final VoidCallback onComments;

  @override
  Widget build(BuildContext context) {
    final service = feedService;
    return Row(
      children: [
        if (service == null)
          const _CountChip(
            icon: Icons.favorite_border_rounded,
            label: 'Like',
            active: false,
            onTap: null,
          )
        else
          StreamBuilder<bool>(
            stream: service.watchLiked(moment.id),
            builder: (context, snapshot) {
              // No `snapshot.data ?? false` shortcut: an errored like
              // stream must read as "unknown", not as "not liked".
              final liked = snapshot.hasError
                  ? false
                  : (snapshot.data ?? false);
              return _CountChip(
                icon: liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                // Zero reads as a verb, not a number: no invented social
                // proof, and no hiding the control either.
                label: moment.likeCount == 0 ? 'Like' : '${moment.likeCount}',
                active: liked,
                semanticLabel: liked
                    ? 'Unlike this Moment'
                    : 'Like this Moment',
                onTap: () => unawaited(_toggle(context, service)),
              );
            },
          ),
        const SizedBox(width: 8),
        _CountChip(
          icon: Icons.mode_comment_outlined,
          label: moment.commentCount == 0
              ? 'Comment'
              : '${moment.commentCount}',
          active: false,
          semanticLabel: 'Open comments for this Moment',
          onTap: onComments,
        ),
      ],
    );
  }

  Future<void> _toggle(BuildContext context, HomeFeedService service) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await service.toggleLike(moment.id);
    } catch (error) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              error is FirebaseException
                  ? (error.message ?? 'Your like could not be saved.')
                  : 'Your like could not be saved.',
            ),
          ),
        );
    }
  }
}

/// Tint carries STATE, never meaning: only the icon changes colour when
/// active. The count label stays [AppColors.textSecondary], which clears
/// contrast at 12 pt — `secondary` on `background` is roughly 4:1 and is
/// only acceptable on a large glyph.
class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.semanticLabel,
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
            constraints: const BoxConstraints(minHeight: 48, minWidth: 76),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: active ? AppColors.secondary : AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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

/// Previous / Next as visible controls. The pager must never be
/// gesture-only on any form factor.
class _PagerControls extends StatelessWidget {
  const _PagerControls({
    required this.index,
    required this.total,
    required this.onPrevious,
    required this.onNext,
    required this.onShuffle,
  });

  final int index;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          IconButton.filledTonal(
            key: const ValueKey('moments-discovery-previous'),
            onPressed: onPrevious,
            tooltip: 'Previous Moment',
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            key: const ValueKey('moments-discovery-next'),
            onPressed: onNext,
            tooltip: 'Next Moment',
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          const Spacer(),
          TextButton.icon(
            key: const ValueKey('moments-discovery-shuffle'),
            onPressed: onShuffle,
            icon: const Icon(Icons.shuffle_rounded, size: 18),
            label: const Text('Shuffle again'),
          ),
        ],
      ),
    );
  }
}

/// The desktop queue: the shuffled order made visible and jumpable.
class _QueuePane extends StatelessWidget {
  const _QueuePane({
    required this.moments,
    required this.index,
    required this.onSelect,
  });

  final List<VoiceMoment> moments;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.divider)),
      ),
      // The Material is load-bearing, not decoration: a ListTile paints
      // its selected tile colour and its ink splash onto the nearest
      // Material ancestor. Without one here the pane's own opaque
      // background swallows both, and the queue would show no selection
      // and no tap feedback at all on desktop.
      child: Material(
        type: MaterialType.transparency,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: moments.length,
          itemBuilder: (context, i) {
            final moment = moments[i];
            final selected = i == index;
            return ListTile(
              selected: selected,
              selectedTileColor: AppColors.primary.withValues(alpha: .14),
              onTap: () => onSelect(i),
              leading: UserAvatar(
                radius: 18,
                photoUrl: moment.authorPhotoUrl,
                displayName: moment.authorName,
              ),
              title: Text(
                moment.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                moment.durationSeconds > 0
                    ? '${moment.durationLabel} · ${moment.likeCount == 0 ? 'No likes yet' : '${moment.likeCount} likes'}'
                    : (moment.likeCount == 0
                          ? 'No likes yet'
                          : '${moment.likeCount} likes'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The stack is finite by construction and never loops silently back to
/// the top — that would fabricate the impression of an endless feed.
class _EndOfStack extends StatelessWidget {
  const _EndOfStack({
    required this.listenedCount,
    required this.total,
    required this.moreExists,
    required this.onShuffleAgain,
    required this.onRecord,
    required this.onBackToStart,
  });

  final int listenedCount;
  final int total;
  final bool moreExists;
  final VoidCallback onShuffleAgain;
  final VoidCallback onRecord;
  final VoidCallback onBackToStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.done_all_rounded,
              size: 34,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 14),
            Text(
              moreExists
                  ? 'That\'s the end of this shuffle'
                  : 'That\'s every Moment we could find',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              // Both numbers are counted, never estimated.
              moreExists
                  ? 'You went through $total Moments, and there are more '
                        'published than fit in one shuffle. Shuffle again for '
                        'a different selection.'
                  : 'You went through all $total published '
                        '${total == 1 ? 'Moment' : 'Moments'}.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            if (listenedCount > 0) ...[
              const SizedBox(height: 6),
              Text(
                'You listened to $listenedCount of them.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onShuffleAgain,
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: const Text('Shuffle again'),
                ),
                OutlinedButton.icon(
                  onPressed: onRecord,
                  icon: const Icon(Icons.mic_rounded, size: 18),
                  label: const Text('Record a Moment'),
                ),
                TextButton(
                  onPressed: onBackToStart,
                  child: const Text('Back to the start'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A skeleton in the true shape of a Moment, not a spinner on a black
/// field — and one that admits when it has been waiting too long.
class _LoadingStack extends StatelessWidget {
  const _LoadingStack({required this.isSlow, required this.onRetry});

  final bool isSlow;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('moments-discovery-loading'),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _Bone(width: 48, height: 48, radius: 24),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _Bone(width: 140, height: 13),
                  SizedBox(height: 7),
                  _Bone(width: 72, height: 11),
                ],
              ),
            ],
          ),
          const SizedBox(height: 22),
          const _Bone(width: double.infinity, height: 13),
          const SizedBox(height: 8),
          const _Bone(width: 220, height: 13),
          const Spacer(),
          Row(
            children: const [
              _Bone(width: 56, height: 56, radius: 28),
              SizedBox(width: 14),
              Expanded(child: _Bone(width: double.infinity, height: 30)),
            ],
          ),
          const SizedBox(height: 18),
          if (isSlow)
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Still loading Moments…',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
        ],
      ),
    );
  }
}

class _Bone extends StatelessWidget {
  const _Bone({required this.width, required this.height, this.radius = 8});

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A REAL error state — the thing this screen did not have.
///
/// A `failed-precondition` here means a composite index is missing, and
/// its message carries the console URL that creates it. In debug that
/// line is shown verbatim: it is the difference between the club-invite
/// class of bug taking a day and taking a month.
class _ErrorStack extends StatelessWidget {
  const _ErrorStack({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final code = error is FirebaseException
        ? (error! as FirebaseException).code
        : '';
    final (String title, String body, bool offerRetry) = switch (code) {
      'permission-denied' || 'unauthenticated' => (
        'Sign in to hear Moments',
        'Voice Moments are available to signed-in accounts.',
        false,
      ),
      'unavailable' => (
        'You are offline',
        'Moments you downloaded still play from the Moments you follow.',
        true,
      ),
      _ => (
        'Moments could not load',
        'Something went wrong reaching the Voice Moments feed.',
        true,
      ),
    };

    return Center(
      key: const ValueKey('moments-discovery-error'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 34,
              color: AppColors.error,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            if (kDebugMode && error != null) ...[
              const SizedBox(height: 14),
              SelectableText(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 11.5,
                ),
              ),
            ],
            if (offerRetry) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyStack extends StatelessWidget {
  const _EmptyStack({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('moments-discovery-empty'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: AppColors.textSecondary),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

String _clock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}

String _relativeAge(DateTime? createdAt) {
  if (createdAt == null) return '';
  final diff = DateTime.now().difference(createdAt);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  return '${diff.inDays}d';
}
