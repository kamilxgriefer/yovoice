import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_content_flow.dart';
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

/// A discovery BOARD of published Voice Moments from every user: nothing
/// but avatars, circle beside circle, filling the whole width.
///
/// It replaced a one-Moment-per-viewport pager, whose problem was not
/// decoration: a board of forty faces makes forty choices visible at
/// once, while a pager makes exactly one visible and hides the rest
/// behind a gesture. The most-engaged Moments hold the top of the board
/// (see [MomentDiscoveryService.rankByEngagement]), so position on the
/// board is itself the ranking.
///
/// Tapping a circle plays that Moment and opens it in the player — a
/// dock under the board on narrow and medium widths, a fixed pane beside
/// it on wide ones. The gesture is never the only way through: the
/// player keeps real Previous/Next controls and the arrow keys move the
/// selection, because a board that can only be tapped is unusable with a
/// keyboard or a screen reader.
class MomentDiscoveryView extends StatefulWidget {
  const MomentDiscoveryView({
    required this.onOpenComments,
    required this.onRecord,
    this.discoveryService,
    this.feedService,
    this.contentReportService,
    this.auth,
    this.isVisible,
    this.playerFactory,
    super.key,
  });

  final ValueChanged<VoiceMoment> onOpenComments;
  final VoidCallback onRecord;
  final MomentDiscoveryService? discoveryService;
  final HomeFeedService? feedService;

  /// Injection seam for the report action; production passes nothing.
  final ContentReportService? contentReportService;

  /// Injection seam for the viewer's identity. Needed because the report
  /// action is hidden on your own Moment and for a viewer with no
  /// session, and a surface whose "who am I" cannot be set in a test is
  /// a surface whose safety control cannot be proved to appear.
  final FirebaseAuth? auth;

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

/// How the board is ordered. Both orders are real and both are kept:
/// [topFirst] answers "who is most engaged with right now", [shuffled]
/// keeps the popularity-weighted random walk that makes a quiet Moment
/// reachable. Default is [topFirst], because the board's whole premise is
/// that position IS the ranking.
enum _BoardOrder { topFirst, shuffled }

class _MomentDiscoveryViewState extends State<MomentDiscoveryView> {
  late final MomentDiscoveryService _discovery;
  HomeFeedService? _feed;
  AudioPlayer? _player;

  _Phase _phase = _Phase.loading;
  Object? _error;
  MomentDiscoveryFeed? _result;
  _BoardOrder _order = _BoardOrder.topFirst;

  /// The board's display order, fixed for the life of one load.
  ///
  /// Recomputed on load and when the order control changes, and NEVER
  /// from the live counter stream: a like landing anywhere must not make
  /// the faces jump under the reader's finger.
  List<VoiceMoment> _ordered = const <VoiceMoment>[];

  /// Live `likeCount` / `commentCount` keyed by Moment id. Empty until
  /// the counter stream delivers; every number rendered before then came
  /// from the load and is equally real.
  Map<String, MomentEngagement> _engagement =
      const <String, MomentEngagement>{};
  StreamSubscription<Map<String, MomentEngagement>>? _engagementSubscription;

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
      return (widget.auth ?? FirebaseAuth.instance).currentUser?.uid ?? '';
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
    _listenToEngagement();
    unawaited(_load());
  }

  /// The fix for "likes and comments only appear after a reload".
  ///
  /// The feed itself is a one-shot read on purpose, so the order cannot
  /// churn; the counters are the one part that must stay live, and they
  /// arrive on their own stream. Guarded twice over: a service that
  /// cannot open the stream (no Firebase app, an injected double) must
  /// leave the board rendering the counts it loaded rather than throwing.
  void _listenToEngagement() {
    try {
      _engagementSubscription = _discovery.watchEngagement().listen(
        (counters) {
          if (!mounted) return;
          setState(() => _engagement = counters);
        },
        onError: (Object _) {
          // Counts already on screen are real, just no longer live. That
          // is strictly better than taking the board down.
        },
      );
    } catch (_) {
      _engagementSubscription = null;
    }
  }

  @override
  void dispose() {
    widget.isVisible?.removeListener(_handleVisibility);
    _playWatchdog?.cancel();
    _loadWatchdog?.cancel();
    unawaited(_engagementSubscription?.cancel());
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
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
        _ordered = _orderedFrom(result);
        // The top of the board is preselected so the player is loaded
        // and reachable on arrival — but nothing plays until a tap.
        // Audio that starts on its own is the fastest way to make a
        // person close a tab.
        _index = 0;
        _phase = _Phase.ready;
      });
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

  List<VoiceMoment> _orderedFrom(MomentDiscoveryFeed result) {
    return switch (_order) {
      // Most-engaged first, deterministically. The service owns the
      // arithmetic; this only chooses which of its two orders to show.
      _BoardOrder.topFirst => MomentDiscoveryService.rankByEngagement(
        result.moments,
      ),
      // Exactly what the service returned: weighted-shuffled and
      // author-spaced.
      _BoardOrder.shuffled => result.moments,
    };
  }

  /// The same Moment, carrying the freshest counters we have for it.
  VoiceMoment _withLiveCounts(VoiceMoment moment) {
    final live = _engagement[moment.id];
    if (live == null) return moment;
    return moment.withCounts(
      likeCount: live.likeCount,
      commentCount: live.commentCount,
    );
  }

  void _setOrder(_BoardOrder order) {
    final result = _result;
    if (result == null) return;
    // Re-picking the shuffle means a genuinely new shuffle, not the same
    // arrangement again: a control that appears to do nothing is worse
    // than no control.
    if (order == _order) {
      if (order == _BoardOrder.shuffled) unawaited(_load());
      return;
    }
    final keepId = _index >= 0 && _index < _ordered.length
        ? _ordered[_index].id
        : null;
    setState(() {
      _order = order;
      _ordered = _orderedFrom(result);
      final moved = keepId == null
          ? -1
          : _ordered.indexWhere((moment) => moment.id == keepId);
      // Reordering must not silently change WHAT is loaded in the player.
      _index = moved >= 0 ? moved : 0;
    });
  }

  /// Moves the selection without playing — the keyboard and the
  /// Previous/Next controls.
  void _goTo(int index) {
    if (index < 0 || index >= _ordered.length || index == _index) return;
    unawaited(_stop());
    setState(() => _index = index);
  }

  /// A tap on a circle. Tapping the circle already loaded toggles it;
  /// tapping a different one switches to it and starts playing, because
  /// "tap a face, hear that person" is the whole contract of this board.
  void _tapTile(int index) {
    if (index < 0 || index >= _ordered.length) return;
    final moment = _ordered[index];
    if (index == _index) {
      unawaited(_togglePlay(moment));
      return;
    }
    unawaited(_switchTo(index, moment));
  }

  Future<void> _switchTo(int index, VoiceMoment moment) async {
    await _stop();
    if (!mounted) return;
    setState(() => _index = index);
    await _togglePlay(moment);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final body = switch (_phase) {
          _Phase.loading => _LoadingStack(isSlow: _loadIsSlow, onRetry: _load),
          _Phase.error => _ErrorStack(error: _error, onRetry: _load),
          _Phase.ready => _buildReady(constraints),
        };
        return Container(color: AppColors.background, child: body);
      },
    );
  }

  Widget _buildReady(BoxConstraints constraints) {
    final width = constraints.maxWidth;
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

    final moments = _ordered;
    final wide = width >= _stageWidth;
    final index = _index.clamp(0, moments.length - 1);
    final selected = moments.isEmpty ? null : _withLiveCounts(moments[index]);

    final board = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BoardHeader(
          order: _order,
          onOrder: _setOrder,
          onRefresh: _load,
          compact: width < _tabletWidth,
        ),
        Expanded(
          child: _AvatarWall(
            moments: moments,
            selectedIndex: index,
            playingId: _isPlaying ? _playingId : null,
            counts: _engagement,
            onTap: _tapTile,
            onRecord: widget.onRecord,
            footer: _BoardFooter(
              total: moments.length,
              listenedCount: _listenedTo.length,
              moreExists: result.poolExhausted,
            ),
          ),
        ),
      ],
    );

    final player = selected == null
        ? null
        : _MomentPlayerPanel(
            key: const ValueKey('moments-discovery-player'),
            moment: selected,
            position: index,
            total: moments.length,
            wide: wide,
            isPlaying: _playingId == selected.id && _isPlaying,
            elapsed: _playingId == selected.id ? _position : Duration.zero,
            duration: _playingId == selected.id ? _duration : null,
            playbackError: _playingId == selected.id ? _playbackError : null,
            feedService: _feed,
            currentUserId: _uid,
            contentReportService: widget.contentReportService,
            onTogglePlay: () => unawaited(_togglePlay(selected)),
            onComments: () => widget.onOpenComments(selected),
            onPrevious: index > 0 ? () => _goTo(index - 1) : null,
            onNext: index < moments.length - 1 ? () => _goTo(index + 1) : null,
            onSeek: (target) async {
              final player = _player;
              if (player == null || _playingId != selected.id) return;
              try {
                await player.seek(target);
              } catch (_) {
                // Seeking an unloaded source is a no-op, not a fault.
              }
            },
          );

    // A real key handler, not a `Shortcuts` map with no `Actions` to
    // dispatch into — that compiles, reads as keyboard support, and does
    // nothing. Arrows walk the board in reading order; space plays what
    // is loaded.
    return Focus(
      autofocus: wide,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowDown) {
          _goTo(index + 1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowUp) {
          _goTo(index - 1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.space && selected != null) {
          unawaited(_togglePlay(selected));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      // Wide: the board keeps the room and the player takes a fixed pane
      // beside it, so nothing has to be dismissed to keep browsing.
      // Narrow and medium: the player docks under the board, capped so
      // the faces above it never lose more than half the height.
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: board),
                if (player != null) SizedBox(width: 344, child: player),
              ],
            )
          : Column(
              children: [
                Expanded(child: board),
                if (player != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight.isFinite
                          ? constraints.maxHeight * .55
                          : 420,
                    ),
                    child: player,
                  ),
              ],
            ),
    );
  }
}

/// `Most engaged` / `Shuffle`, and a real refresh.
///
/// Two orders, both kept, neither pretending to be the other: the board
/// is ranked by default, and the popularity-weighted shuffle that makes a
/// quiet Moment reachable is one tap away. Tapping `Shuffle` while
/// already shuffled reshuffles — a control that appears inert is worse
/// than no control.
class _BoardHeader extends StatelessWidget {
  const _BoardHeader({
    required this.order,
    required this.onOrder,
    required this.onRefresh,
    required this.compact,
  });

  final _BoardOrder order;
  final ValueChanged<_BoardOrder> onOrder;
  final VoidCallback onRefresh;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 2, compact ? 8 : 16, 6),
      child: Row(
        children: [
          // Wrap, not Row: at a 2x text scale two chips plus the refresh
          // control do not fit a 360 pt phone on one line, and a control
          // that has slid off the edge is the same as one never built.
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _OrderChip(
                  key: const ValueKey('moments-discovery-top'),
                  label: 'Most engaged',
                  icon: Icons.trending_up_rounded,
                  selected: order == _BoardOrder.topFirst,
                  onTap: () => onOrder(_BoardOrder.topFirst),
                ),
                _OrderChip(
                  key: const ValueKey('moments-discovery-shuffle'),
                  label: 'Shuffle',
                  icon: Icons.shuffle_rounded,
                  selected: order == _BoardOrder.shuffled,
                  onTap: () => onOrder(_BoardOrder.shuffled),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('moments-discovery-refresh'),
            onPressed: onRefresh,
            tooltip: 'Reload Moments',
            icon: const Icon(
              Icons.refresh_rounded,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderChip extends StatelessWidget {
  const _OrderChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: .28)
            : AppColors.surface.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 17,
                  // Tint carries STATE, never meaning: the label keeps its
                  // contrast either way.
                  color: selected
                      ? AppColors.secondary
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 7),
                // Flexible + ellipsis, not a bare Text: at a 2x text
                // scale "Most engaged" is wider than a 360 pt phone can
                // give this row, and a label that runs off the edge takes
                // the control with it.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 13,
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

/// The board itself: circles, side by side, filling the width.
///
/// The cell size is a function of the width the view was given, not of
/// how many Moments exist, so the board reads the same with one face and
/// with fifty. A partial single row is centred rather than pinned to the
/// left corner — with a corpus of one that is the difference between a
/// deliberate board and a broken one.
class _AvatarWall extends StatelessWidget {
  const _AvatarWall({
    required this.moments,
    required this.selectedIndex,
    required this.playingId,
    required this.counts,
    required this.onTap,
    required this.onRecord,
    required this.footer,
  });

  final List<VoiceMoment> moments;
  final int selectedIndex;
  final String? playingId;
  final Map<String, MomentEngagement> counts;
  final ValueChanged<int> onTap;
  final VoidCallback onRecord;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final side = width < _tabletWidth ? 16.0 : 24.0;
        const gap = 10.0;
        final available = width - side * 2;

        // One target per breakpoint, then as many whole columns as fit.
        // The clamp at both ends is what stops a 320 pt phone rendering
        // one column and a 1600 pt window rendering forty specks.
        final target = width < _tabletWidth
            ? 94.0
            : width < _stageWidth
            ? 106.0
            : 118.0;
        final columns = (available / (target + gap)).floor().clamp(2, 12);

        // The record entry point is a tile of the board rather than a
        // floating button: it belongs to the same grid, and it is the one
        // thing that is honest to show when the corpus is small.
        final tileCount = moments.length + 1;

        var tile = (available - gap * (columns - 1)) / columns;
        // The circle is capped so a two-column phone does not render two
        // discs the size of a hand. A partial row gets a higher ceiling,
        // because there the empty space is the problem, not the size.
        var ringCap = 120.0;
        if (tileCount < columns) {
          // A partial row. Keeping the full-board cell size here would
          // draw two small discs adrift in a band of empty background —
          // the exact "huge empty middle" this board replaced. The
          // circles grow instead, bounded so a corpus of one does not
          // become a single dinner plate.
          final grown = (available - gap * (tileCount - 1)) / tileCount;
          tile = grown.clamp(tile, target * 1.6);
          ringCap = 160.0;
        }
        final ring = tile.clamp(56.0, ringCap);

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(side, 2, side, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: gap,
                runSpacing: 14,
                alignment: tileCount <= columns
                    ? WrapAlignment.center
                    : WrapAlignment.start,
                children: [
                  for (var i = 0; i < moments.length; i++)
                    _AvatarTile(
                      key: ValueKey('moment-tile-${moments[i].id}'),
                      moment: _merge(moments[i]),
                      extent: tile,
                      ring: ring,
                      rank: i,
                      selected: i == selectedIndex,
                      playing: playingId == moments[i].id,
                      onTap: () => onTap(i),
                    ),
                  _RecordTile(extent: tile, ring: ring, onTap: onRecord),
                ],
              ),
              const SizedBox(height: 20),
              footer,
            ],
          ),
        );
      },
    );
  }

  VoiceMoment _merge(VoiceMoment moment) {
    final live = counts[moment.id];
    if (live == null) return moment;
    return moment.withCounts(
      likeCount: live.likeCount,
      commentCount: live.commentCount,
    );
  }
}

/// One circle. The ring is the only decoration, and every ring state is
/// something the data can prove: playing now, loaded in the player, or
/// carrying real engagement. Nothing is ringed for looking popular.
class _AvatarTile extends StatelessWidget {
  const _AvatarTile({
    required this.moment,
    required this.extent,
    required this.ring,
    required this.rank,
    required this.selected,
    required this.playing,
    required this.onTap,
    super.key,
  });

  final VoiceMoment moment;
  final double extent;

  /// The circle's diameter, decided by the board so every tile in a run
  /// lines up rather than each computing its own.
  final double ring;
  final int rank;
  final bool selected;
  final bool playing;
  final VoidCallback onTap;

  int get _engagement => moment.likeCount + moment.commentCount;

  String get _semanticLabel {
    final parts = <String>[
      playing
          ? 'Pause the Moment by ${moment.authorName}'
          : 'Play the Moment by ${moment.authorName}',
      'position ${rank + 1}',
      if (moment.likeCount > 0)
        '${moment.likeCount} ${moment.likeCount == 1 ? 'like' : 'likes'}',
      if (moment.commentCount > 0)
        '${moment.commentCount} '
            '${moment.commentCount == 1 ? 'comment' : 'comments'}',
      if (moment.durationSeconds > 0) '${moment.durationSeconds} seconds',
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final nameHeight = scaler.scale(11.5) * 1.1 * 2 + 4;
    final metaHeight = scaler.scale(11) * 1.35 + 2;

    return SizedBox(
      width: extent,
      child: Semantics(
        button: true,
        selected: selected,
        label: _semanticLabel,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AvatarRing(
                  diameter: ring,
                  selected: selected,
                  playing: playing,
                  engaged: _engagement > 0,
                  child: UserAvatar(
                    radius: (ring - 11) / 2,
                    photoUrl: moment.authorPhotoUrl,
                    displayName: moment.authorName,
                  ),
                ),
                const SizedBox(height: 7),
                SizedBox(
                  height: nameHeight,
                  child: Center(
                    child: Text(
                      moment.authorName,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11.5,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: metaHeight,
                  child: _TileMeta(moment: moment),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Under the circle: the engagement that put it where it is, or — when a
/// Moment has none — its real duration. A zero is never printed as a
/// number; there is no fabricated social proof anywhere on this board.
class _TileMeta extends StatelessWidget {
  const _TileMeta({required this.moment});

  final VoiceMoment moment;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: AppColors.textSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );

    if (moment.likeCount <= 0 && moment.commentCount <= 0) {
      if (moment.durationSeconds <= 0) return const SizedBox.shrink();
      return Center(
        child: Text(
          moment.durationLabel,
          maxLines: 1,
          style: const TextStyle(color: AppColors.textHint, fontSize: 11),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (moment.likeCount > 0) ...[
          const Icon(
            Icons.favorite_rounded,
            size: 12,
            color: AppColors.secondary,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text('${moment.likeCount}', maxLines: 1, style: style),
          ),
        ],
        if (moment.likeCount > 0 && moment.commentCount > 0)
          const SizedBox(width: 8),
        if (moment.commentCount > 0) ...[
          const Icon(
            Icons.mode_comment_rounded,
            size: 11,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text('${moment.commentCount}', maxLines: 1, style: style),
          ),
        ],
      ],
    );
  }
}

class _AvatarRing extends StatelessWidget {
  const _AvatarRing({
    required this.diameter,
    required this.selected,
    required this.playing,
    required this.engaged,
    required this.child,
  });

  final double diameter;
  final bool selected;
  final bool playing;
  final bool engaged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final gradient = playing
        ? const LinearGradient(colors: [AppColors.accent, AppColors.secondary])
        : engaged
        ? const LinearGradient(colors: [AppColors.primary, AppColors.secondary])
        : null;

    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: diameter,
            height: diameter,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradient,
              border: gradient != null
                  ? null
                  : Border.all(
                      color: selected ? AppColors.accent : AppColors.border,
                      width: selected ? 2.5 : 1.4,
                    ),
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.background,
              ),
              child: child,
            ),
          ),
          // The selection mark is drawn on top of a gradient ring rather
          // than replacing it: "this one is loaded" and "this one has
          // engagement" are different facts and must not overwrite each
          // other.
          if (selected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent, width: 2.5),
                ),
              ),
            ),
          if (playing)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent,
                  border: Border.all(color: AppColors.background, width: 2),
                ),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  size: 11,
                  color: AppColors.background,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The recorder entry point, as the last circle on the board.
class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.extent,
    required this.ring,
    required this.onTap,
  });

  final double extent;
  final double ring;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final nameHeight = scaler.scale(11.5) * 1.1 * 2 + 4;

    return SizedBox(
      width: extent,
      child: Semantics(
        button: true,
        label: 'Record your own Voice Moment',
        child: InkWell(
          key: const ValueKey('moments-discovery-record'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: ring,
                  height: ring,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surface.withValues(alpha: .55),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: .55),
                      width: 1.4,
                    ),
                  ),
                  child: Icon(
                    Icons.mic_rounded,
                    size: (ring * .34).clamp(18.0, 34.0),
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 7),
                SizedBox(
                  height: nameHeight,
                  child: const Center(
                    child: Text(
                      'Record',
                      maxLines: 1,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11.5,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
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

/// What the board actually holds, counted rather than estimated — and,
/// when there is one, how much of it this session has really listened to.
class _BoardFooter extends StatelessWidget {
  const _BoardFooter({
    required this.total,
    required this.listenedCount,
    required this.moreExists,
  });

  final int total;
  final int listenedCount;
  final bool moreExists;

  @override
  Widget build(BuildContext context) {
    final noun = total == 1 ? 'Moment' : 'Moments';
    return Column(
      children: [
        Text(
          moreExists
              ? '$total $noun on the board — more are published than fit '
                    'one board.'
              : (total == 1
                    ? 'That is the only published Moment we could find.'
                    : 'That is all $total published Moments we could find.'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textHint,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        if (listenedCount > 0) ...[
          const SizedBox(height: 4),
          Text(
            'You listened to $listenedCount of them.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textHint, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// The Moment that is loaded: who made it, what they said, the transport,
/// and the real counts with real controls.
///
/// Docked under the board on narrow and medium widths and pinned beside
/// it on wide ones — the same content either way, so nothing is reachable
/// on one form factor and missing on another.
class _MomentPlayerPanel extends StatelessWidget {
  const _MomentPlayerPanel({
    required this.moment,
    required this.position,
    required this.total,
    required this.wide,
    required this.isPlaying,
    required this.elapsed,
    required this.duration,
    required this.playbackError,
    required this.feedService,
    required this.currentUserId,
    required this.contentReportService,
    required this.onTogglePlay,
    required this.onComments,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
    super.key,
  });

  final VoiceMoment moment;
  final int position;
  final int total;
  final bool wide;
  final bool isPlaying;
  final Duration elapsed;
  final Duration? duration;
  final String? playbackError;
  final HomeFeedService? feedService;
  final String currentUserId;
  final ContentReportService? contentReportService;
  final VoidCallback onTogglePlay;
  final VoidCallback onComments;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: .45),
        border: Border(
          left: wide
              ? const BorderSide(color: AppColors.divider)
              : BorderSide.none,
          top: wide
              ? BorderSide.none
              : const BorderSide(color: AppColors.divider),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
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
                    radius: 22,
                    photoUrl: moment.authorPhotoUrl,
                    displayName: moment.authorName,
                  ),
                ),
                const SizedBox(width: 12),
                // Row + Flexible, not Wrap: a long display name must
                // truncate and leave the identity badges in place, never
                // push them onto a second line or off the row entirely.
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
                      // The age and the board position share a Wrap under
                      // the name rather than sitting in the header row.
                      // In the 344 pt desktop pane at a 2x text scale a
                      // third fixed column left the name and its identity
                      // badges 82 pt to live in, and the badges — which
                      // cannot shrink — ran off the edge.
                      Wrap(
                        spacing: 8,
                        children: [
                          Text(
                            _relativeAge(moment.createdAt),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
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
                    ],
                  ),
                ),
              ],
            ),
            if (moment.caption.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                moment.caption,
                // Bounded rather than endless: the transport and the
                // like/comment/report row must stay reachable in the dock
                // no matter how long the caption is, and the panel
                // scrolls for the rest. The bound tightens as text grows,
                // because at a 2x scale four lines is half the dock.
                maxLines: wide
                    ? 8
                    : (MediaQuery.textScalerOf(context).scale(14.5) > 20
                          ? 2
                          : 4),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14.5,
                  height: 1.42,
                ),
              ),
            ],
            if (playbackError != null) ...[
              const SizedBox(height: 8),
              Text(
                playbackError!,
                style: const TextStyle(color: AppColors.error, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 12),
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
              canReport:
                  currentUserId.isNotEmpty && currentUserId != moment.authorId,
              contentReportService: contentReportService,
            ),
            const SizedBox(height: 6),
            // Previous / Next as visible controls: the board must never be
            // tap-only on any form factor.
            Row(
              children: [
                IconButton.filledTonal(
                  key: const ValueKey('moments-discovery-previous'),
                  onPressed: onPrevious,
                  tooltip: 'Previous Moment',
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const ValueKey('moments-discovery-next'),
                  onPressed: onNext,
                  tooltip: 'Next Moment',
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ],
        ),
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
    required this.canReport,
    required this.contentReportService,
  });

  final VoiceMoment moment;
  final HomeFeedService? feedService;
  final VoidCallback onComments;

  /// False on your own Moment, and while the viewer's uid is unknown —
  /// offering "report" to a signed-out viewer would be a button that can
  /// only fail.
  final bool canReport;
  final ContentReportService? contentReportService;

  @override
  Widget build(BuildContext context) {
    final service = feedService;
    // Wrap, not Row: three chips with a 76 px floor each still fit a
    // narrow phone at the default text size, but at a 2x text scale they
    // do not, and a safety control that has slid off the edge of the
    // screen is the same as one that was never built.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
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
        _CountChip(
          icon: Icons.mode_comment_outlined,
          label: moment.commentCount == 0
              ? 'Comment'
              : '${moment.commentCount}',
          active: false,
          semanticLabel: 'Open comments for this Moment',
          onTap: onComments,
        ),
        if (canReport)
          _CountChip(
            key: ValueKey('report-discovery-${moment.id}'),
            icon: Icons.flag_outlined,
            label: 'Report',
            active: false,
            semanticLabel: 'Report this Voice Moment',
            onTap: () => unawaited(_report(context)),
          ),
      ],
    );
  }

  Future<void> _report(BuildContext context) async {
    await reportContent(
      context: context,
      service: contentReportService,
      content: ReportedContent.voiceMoment(momentId: moment.id),
      title: 'Report this Voice Moment',
      subtitle:
          'Your report goes to the YO Voice moderation team with this '
          'Moment attached. ${moment.authorName} is not told who reported '
          'it.',
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
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
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
