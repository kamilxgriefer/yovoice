import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_content_flow.dart';
import 'package:yovoice/features/moments/data/models/moment_chain.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_discovery_service.dart';
import 'package:yovoice/features/moments/data/services/moment_expiry_scheduler.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_detail_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_sheet.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_viewer.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_time_labels.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Which slice of the Moments corpus the feed is showing.
enum MomentsFilter {
  /// The default composed page: story strip, featured cards (top
  /// engagement via [MomentDiscoveryService.rankByEngagement]) and the
  /// recent list — the engagement-ranked discovery pool.
  discover,

  /// Only the people this account follows (plus friends and itself) —
  /// the personal feed, fed by the existing [HomeFeedService] stream.
  following,

  /// The same pool in pure engagement order, most-engaged first.
  mostEngaged,

  /// The same pool ordered by `createdAt` descending, nothing else.
  recent,
}

/// The width at which the right detail panel appears. Measured on the
/// space this view receives (the desktop shell already took its rail), so
/// the panel responds to the room it has, not to a device label.
const double _detailWidth = 1100;
const double _tabletWidth = 600;

/// The modern Voice Moments feed: filter chips, a story strip of author
/// chains with viewed/unviewed rings, featured cards, a recent list, and
/// — on wide surfaces — a right detail panel with player, actions and the
/// inline comment thread.
///
/// Every number rendered is a document's real counter, every timestamp
/// label is derived from a real timestamp, and every Moment shown is
/// live — either inside its chosen availability window (`expiresAt` in
/// the future) or permanent (no `expiresAt` at all, the author's
/// "keep until deleted" choice). There are no view counts anywhere: no
/// server-side counter exists, so none is printed.
class MomentsFeedView extends StatefulWidget {
  const MomentsFeedView({
    required this.onRecord,
    this.initialFilter = MomentsFilter.discover,
    this.discoveryService,
    this.feedService,
    this.momentService,
    this.viewsService,
    this.contentReportService,
    this.auth,
    this.isVisible,
    this.onOpenDetail,
    this.playerFactory,
    this.expiryClock,
    this.expiryTimerFactory,
    super.key,
  });

  final VoidCallback onRecord;
  final MomentsFilter initialFilter;
  final MomentDiscoveryService? discoveryService;
  final HomeFeedService? feedService;
  final MomentService? momentService;
  final MomentViewsService? viewsService;
  final ContentReportService? contentReportService;
  final FirebaseAuth? auth;

  /// False while the shell shows another tab: playback must stop rather
  /// than continue from an invisible IndexedStack child.
  final ValueListenable<bool>? isVisible;

  /// How this surface opens a Moment's full detail page. The shell passes
  /// a route that keeps the bottom navigation visible (Moments stays the
  /// active tab); when nothing is passed the feed pushes the plain
  /// [MomentDetailScreen] route, which carries its own Back control.
  final void Function(VoiceMoment moment)? onOpenDetail;

  @visibleForTesting
  final AudioPlayer Function()? playerFactory;

  @visibleForTesting
  final MomentExpiryClock? expiryClock;

  @visibleForTesting
  final MomentExpiryTimerFactory? expiryTimerFactory;

  @override
  State<MomentsFeedView> createState() => _MomentsFeedViewState();
}

enum _Phase { loading, error, ready }

class _MomentsFeedViewState extends State<MomentsFeedView> {
  late final MomentDiscoveryService _discovery;
  HomeFeedService? _feed;
  MomentService? _moments;
  MomentViewsService? _views;

  late MomentsFilter _filter = widget.initialFilter;

  _Phase _phase = _Phase.loading;
  Object? _error;
  MomentDiscoveryFeed? _result;

  // The personal slice is subscribed EAGERLY in initState and cached
  // here, not read through a StreamBuilder mounted on filter switch:
  // [HomeFeedService.watchSocialMoments] is a broadcast stream whose
  // underlying listeners start at construction, so its initial emissions
  // are dropped for any listener that arrives later — a StreamBuilder
  // mounted when the user taps Following would wait on a skeleton
  // forever.
  StreamSubscription<List<VoiceMoment>>? _socialSubscription;
  List<VoiceMoment>? _socialData;
  Object? _socialError;

  StreamSubscription<List<VoiceMoment>>? _mineSubscription;
  List<VoiceMoment> _mineData = const <VoiceMoment>[];

  Map<String, MomentEngagement> _engagement =
      const <String, MomentEngagement>{};
  StreamSubscription<Map<String, MomentEngagement>>? _engagementSubscription;

  Set<String> _viewedIds = const <String>{};
  StreamSubscription<Set<String>>? _viewedSubscription;

  /// Which Moment the wide detail panel shows; null falls back to the
  /// first of the current list.
  String? _selectedId;

  // ---- detail-panel playback (wide layouts only) ----
  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _playerSubscriptions =
      <StreamSubscription<dynamic>>[];
  String? _playingId;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  String? _playbackError;

  late final MomentExpiryScheduler _expiry;
  DateTime? _expiredThrough;
  final FocusNode _expiryRecoveryFocus = FocusNode(
    debugLabel: 'Reload Moments after expiry',
  );
  final MomentExpiryAnnouncer _expiryAnnouncer = MomentExpiryAnnouncer();

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
    _expiry = MomentExpiryScheduler(
      onDeadline: _expireAt,
      clock: widget.expiryClock,
      timerFactory: widget.expiryTimerFactory,
    );
    _discovery = widget.discoveryService ?? MomentDiscoveryService();
    // Each seam guarded separately: one service that cannot be
    // constructed must not take the others down with it.
    try {
      _feed = widget.feedService ?? HomeFeedService();
      _subscribeSocial();
    } catch (_) {
      _feed = null;
    }
    try {
      _moments = widget.momentService ?? MomentService();
      _mineSubscription = _moments!.watchMyMoments().listen(
        (moments) {
          if (!mounted) return;
          final now = _expiry.now();
          // The exact timer can make the service emit a list with the dead
          // item already removed. Expire the previous cache first, while its
          // focused row and playback id are still identifiable.
          _expireAt(now);
          if (!mounted) return;
          setState(() {
            // A previously-seen own Moment that vanished from the stream
            // was deleted — from this feed's own controls, the story
            // viewer, or the detail screen. The Discover pool is a
            // one-shot load, so without this prune a deleted own Moment
            // would keep rendering until the next manual reload.
            final surviving = moments.map((m) => m.id).toSet();
            final removed = _mineData
                .map((m) => m.id)
                .where((id) => !surviving.contains(id))
                .toSet();
            _mineData = moments;
            if (removed.isNotEmpty) _pruneFromPool(removed);
          });
          // Validate and schedule the incoming snapshot as well; this also
          // protects against a stale backend emission at the boundary.
          _expireAt(now);
        },
        onError: (Object _) {
          // Own Moments are additive to the personal slice; when this
          // stream fails the slice still renders from the social one.
        },
      );
    } catch (_) {
      _moments = null;
    }
    try {
      _views = widget.viewsService ?? MomentViewsService();
      _viewedSubscription = _views!.watchViewedMomentIds().listen(
        (ids) {
          if (mounted) setState(() => _viewedIds = ids);
        },
        onError: (Object _) {
          // Unknown viewed-state renders as unviewed; strictly better
          // than taking the strip down.
        },
      );
    } catch (_) {
      _views = null;
    }
    try {
      _engagementSubscription = _discovery.watchEngagement().listen(
        (counters) {
          if (mounted) setState(() => _engagement = counters);
        },
        onError: (Object _) {
          // Counts already on screen are real, just no longer live.
        },
      );
    } catch (_) {
      _engagementSubscription = null;
    }
    widget.isVisible?.addListener(_handleVisibility);
    unawaited(_load());
  }

  void _subscribeSocial() {
    unawaited(_socialSubscription?.cancel());
    _socialSubscription = _feed!.watchSocialMoments().listen(
      (moments) {
        if (mounted) {
          final now = _expiry.now();
          // HomeFeedService's exact wake-up emits the already-pruned list.
          // Process the previous cache before replacing it so a social-only
          // focused row still participates in announcement/focus recovery.
          _expireAt(now);
          if (!mounted) return;
          setState(() {
            _socialData = moments;
            _socialError = null;
          });
          _expireAt(now);
        }
      },
      onError: (Object error) {
        if (mounted) setState(() => _socialError = error);
      },
    );
  }

  /// The error-state retry for the Following filter: a fresh
  /// subscription, because the old one is dead once it errored.
  void _retrySocial() {
    setState(() {
      _socialError = null;
      _socialData = null;
    });
    final feed = _feed;
    if (feed != null) {
      _subscribeSocial();
    }
  }

  @override
  void dispose() {
    widget.isVisible?.removeListener(_handleVisibility);
    _expiry.dispose();
    unawaited(_engagementSubscription?.cancel());
    unawaited(_viewedSubscription?.cancel());
    unawaited(_socialSubscription?.cancel());
    unawaited(_mineSubscription?.cancel());
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
    _player?.dispose();
    _expiryRecoveryFocus.dispose();
    super.dispose();
  }

  void _handleVisibility() {
    if (widget.isVisible?.value == false) unawaited(_stopPanelPlayback());
  }

  Future<void> _load() async {
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    await _stopPanelPlayback();
    try {
      final result = await _discovery.loadDiscoveryFeed();
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _Phase.ready;
      });
      _expireAt(_expiry.now());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _phase = _Phase.error;
      });
    }
  }

  // ------------------------------------------------------------- playback

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

  Future<void> _stopPanelPlayback() async {
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
      _isPlaying = false;
      _playingId = null;
      _position = Duration.zero;
      _duration = null;
    });
  }

  Future<void> _togglePanelPlay(VoiceMoment moment) async {
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

    final resuming = _playingId == moment.id && _position > Duration.zero;
    setState(() {
      _playbackError = null;
      if (_playingId != moment.id) {
        _position = Duration.zero;
        _duration = null;
      }
      _playingId = moment.id;
      _isPlaying = true;
    });

    // Playback starting IS the viewed event, wherever it starts.
    final views = _views;
    if (!resuming && views != null) {
      unawaited(views.markViewed(moment.id).catchError((Object _) {}));
    }

    try {
      if (resuming) {
        await player.resume();
      } else {
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

  Future<void> _seekPanel(VoiceMoment moment, Duration target) async {
    final player = _player;
    if (player == null || _playingId != moment.id) return;
    try {
      await player.seek(target);
    } catch (_) {
      // Seeking an unloaded source is a no-op, not a fault.
    }
  }

  // ------------------------------------------------------------ interact

  VoiceMoment _withLive(VoiceMoment moment) {
    final live = _engagement[moment.id];
    if (live == null) return moment;
    return moment.withCounts(
      likeCount: live.likeCount,
      commentCount: live.commentCount,
    );
  }

  /// What the story viewer reports after the author deletes a link of the
  /// chain in place: the feed drops it immediately.
  void _handleDeletedElsewhere(VoiceMoment moment) {
    if (!mounted) return;
    setState(() {
      _pruneFromPool({moment.id});
      _mineData = _mineData
          .where((mine) => mine.id != moment.id)
          .toList(growable: false);
    });
    _scheduleExpiry();
  }

  Future<void> _openChain(MomentChain chain) async {
    await _stopPanelPlayback();
    if (!mounted) return;
    await showMomentStoryViewer(
      context,
      chain: chain,
      initialIndex: chain.firstUnviewedIndex(_viewedIds),
      feedService: _feed,
      momentService: _moments,
      viewsService: _views,
      contentReportService: widget.contentReportService,
      auth: widget.auth,
      onOpenDetail: _openDetail,
      onDeleted: _handleDeletedElsewhere,
      playerFactory: widget.playerFactory,
      expiryClock: widget.expiryClock,
      expiryTimerFactory: widget.expiryTimerFactory,
    );
  }

  /// A row tap on a NARROW surface: the full existing card in the sheet —
  /// playback, like, comment, report and the offline download, none of it
  /// reimplemented.
  Future<void> _openSheet(VoiceMoment moment) async {
    final uid = _uid;
    await showMomentSheet(
      context,
      moment: moment,
      isOwn: uid.isNotEmpty && moment.authorId == uid,
      canReport: uid.isNotEmpty && moment.authorId != uid,
      feedService: _feed,
      momentService: _moments,
      contentReportService: widget.contentReportService,
      playerFactory: widget.playerFactory,
      expiryClock: widget.expiryClock,
      expiryTimerFactory: widget.expiryTimerFactory,
    );
  }

  void _select(VoiceMoment moment, {required bool wide, bool play = false}) {
    if (!wide) {
      if (play) {
        // The play affordance on a narrow row opens the author's chain in
        // the story viewer, positioned at this Moment, and really plays.
        final chains = _chainsFor(_currentList());
        final chain = chains
            .where((c) => c.authorId == moment.authorId)
            .toList(growable: false);
        if (chain.isNotEmpty) {
          final index = chain.first.moments.indexWhere(
            (m) => m.id == moment.id,
          );
          unawaited(
            showMomentStoryViewer(
              context,
              chain: chain.first,
              initialIndex: index < 0 ? 0 : index,
              feedService: _feed,
              momentService: _moments,
              viewsService: _views,
              contentReportService: widget.contentReportService,
              auth: widget.auth,
              onOpenDetail: _openDetail,
              onDeleted: _handleDeletedElsewhere,
              playerFactory: widget.playerFactory,
              expiryClock: widget.expiryClock,
              expiryTimerFactory: widget.expiryTimerFactory,
            ),
          );
          return;
        }
      }
      unawaited(_openSheet(moment));
      return;
    }
    setState(() => _selectedId = moment.id);
    if (play) {
      unawaited(_togglePanelPlay(moment));
    }
  }

  Future<void> _openComments(VoiceMoment moment) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MomentCommentsScreen(
          moment: moment,
          momentService: _moments,
          contentReportService: widget.contentReportService,
          expiryClock: widget.expiryClock,
          expiryTimerFactory: widget.expiryTimerFactory,
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

  /// Removes [ids] from the one-shot discovery pool so a deleted Moment
  /// disappears immediately instead of surviving until the next reload.
  /// `fetchedCount` shrinks with it, so the empty-state copy stays honest
  /// when the last Moment goes.
  void _pruneFromPool(Set<String> ids) {
    final result = _result;
    if (result == null) return;
    final before = result.moments.length;
    final kept = result.moments
        .where((moment) => !ids.contains(moment.id))
        .toList(growable: false);
    if (kept.length == before) return;
    _result = MomentDiscoveryFeed(
      moments: kept,
      fetchedCount: (result.fetchedCount - (before - kept.length)).clamp(
        0,
        result.fetchedCount,
      ),
      drops: result.drops,
      seed: result.seed,
      poolExhausted: result.poolExhausted,
    );
    if (_selectedId != null && ids.contains(_selectedId)) _selectedId = null;
    if (_playingId != null && ids.contains(_playingId)) {
      unawaited(_stopPanelPlayback());
    }
  }

  /// Opens the full detail page for [moment]. The shell's route keeps the
  /// bottom navigation visible with Moments active; the fallback plain
  /// route carries its own Back control.
  void _openDetail(VoiceMoment moment) {
    unawaited(_stopPanelPlayback());
    final open = widget.onOpenDetail;
    if (open != null) {
      open(moment);
      return;
    }
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MomentDetailScreen(
            moment: moment,
            momentService: _moments,
            feedService: _feed,
            viewsService: _views,
            contentReportService: widget.contentReportService,
            auth: widget.auth,
            playerFactory: widget.playerFactory,
            expiryClock: widget.expiryClock,
            expiryTimerFactory: widget.expiryTimerFactory,
          ),
        ),
      ),
    );
  }

  /// The author's exit — the ONLY exit a permanent Moment has. Destructive
  /// confirmation, the existing [MomentService.deleteMoment], immediate
  /// local removal on success, an honest error and an unchanged feed on
  /// failure.
  Future<void> _confirmDelete(VoiceMoment moment) async {
    final service = _moments;
    if (service == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
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
              key: const ValueKey('moment-delete-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('moment-delete-confirm'),
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

    try {
      await service.deleteMoment(moment);
    } catch (_) {
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
    setState(() {
      _pruneFromPool({moment.id});
      _mineData = _mineData
          .where((mine) => mine.id != moment.id)
          .toList(growable: false);
    });
    _scheduleExpiry();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Voice Moment deleted.'),
        ),
      );
  }

  // ------------------------------------------------------------- ordering

  DateTime _effectiveNow() {
    final now = _expiry.now();
    final floor = _expiredThrough;
    return floor != null && floor.isAfter(now) ? floor : now;
  }

  Iterable<VoiceMoment> get _expiryCandidates sync* {
    yield* _result?.moments ?? const <VoiceMoment>[];
    yield* _socialData ?? const <VoiceMoment>[];
    yield* _mineData;
  }

  void _scheduleExpiry() => _expiry.schedule(_expiryCandidates);

  /// Removes every Moment dead at [deadline] from the frozen discovery,
  /// own-Moment and cached social lists, then arms the next exact deadline.
  /// The discovery corpus count stays unchanged: expiry did not erase the
  /// published document, it only made it ineligible for this live surface.
  void _expireAt(DateTime deadline) {
    if (!mounted) return;
    if (_expiredThrough == null || deadline.isAfter(_expiredThrough!)) {
      _expiredThrough = deadline;
    }
    final now = _effectiveNow();
    final result = _result;
    final expiredPool = result == null
        ? const <VoiceMoment>[]
        : result.moments
              .where((moment) => !moment.isActiveAt(now))
              .toList(growable: false);
    final nextMine = _mineData
        .where(
          (moment) =>
              moment.isActiveAt(now) ||
              (!moment.isPublished &&
                  !moment.isDeleted &&
                  moment.status != 'expired'),
        )
        .toList(growable: false);
    final social = _socialData;
    final nextSocial = social
        ?.where((moment) => moment.isActiveAt(now))
        .toList(growable: false);
    final removedIds = <String>{
      ...expiredPool.map((moment) => moment.id),
      ..._mineData
          .where((moment) => !nextMine.any((kept) => kept.id == moment.id))
          .map((moment) => moment.id),
      if (social != null && nextSocial != null)
        ...social
            .where((moment) => !nextSocial.any((kept) => kept.id == moment.id))
            .map((moment) => moment.id),
    };
    final changed =
        expiredPool.isNotEmpty ||
        nextMine.length != _mineData.length ||
        nextSocial?.length != social?.length;

    if (changed) {
      final previousFocus = FocusManager.instance.primaryFocus;
      final recoverFocus = momentExpiryFocusIsWithin(context, previousFocus);
      final stopPlaying = _playingId != null && removedIds.contains(_playingId);
      if (stopPlaying) {
        final player = _player;
        if (player != null) {
          unawaited(player.stop().catchError((Object _) {}));
        }
      }
      setState(() {
        if (result != null && expiredPool.isNotEmpty) {
          final expiredIds = expiredPool.map((moment) => moment.id).toSet();
          _result = MomentDiscoveryFeed(
            moments: result.moments
                .where((moment) => !expiredIds.contains(moment.id))
                .toList(growable: false),
            fetchedCount: result.fetchedCount,
            drops: <String, MomentDropReason>{
              ...result.drops,
              for (final id in expiredIds) id: MomentDropReason.expired,
            },
            seed: result.seed,
            poolExhausted: result.poolExhausted,
          );
        }
        _mineData = nextMine;
        if (social != null) _socialData = nextSocial;
        if (_selectedId != null && removedIds.contains(_selectedId)) {
          _selectedId = null;
        }
        if (stopPlaying) {
          _isPlaying = false;
          _playingId = null;
          _position = Duration.zero;
          _duration = null;
        }
      });
      if (widget.isVisible?.value != false) {
        final count = removedIds.length;
        final transitionIds = removedIds.toList()..sort();
        _expiryAnnouncer.announce(
          context,
          transition:
              'feed-expiry-${deadline.microsecondsSinceEpoch}:'
              '${transitionIds.join(',')}',
          message: count == 1
              ? 'One Voice Moment expired and was removed.'
              : '$count Voice Moments expired and were removed.',
        );
        recoverMomentExpiryFocusAfterFrame(
          context: context,
          fallback: _expiryRecoveryFocus,
          previousFocus: recoverFocus ? previousFocus : null,
        );
      }
    }
    _scheduleExpiry();
  }

  List<VoiceMoment> _byCreatedDesc(List<VoiceMoment> moments) {
    final sorted = List<VoiceMoment>.of(moments);
    sorted.sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final byDate = bDate.compareTo(aDate);
      if (byDate != 0) return byDate;
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  /// The list the selected chip shows, before live-counter merging.
  List<VoiceMoment> _currentList() {
    final now = _effectiveNow();
    final pool = (_result?.moments ?? const <VoiceMoment>[])
        .where((moment) => moment.isActiveAt(now))
        .toList(growable: false);
    return switch (_filter) {
      MomentsFilter.discover => _byCreatedDesc(pool),
      MomentsFilter.recent => _byCreatedDesc(pool),
      // Ranked on the FROZEN loaded counts, per ADR-095: live counters
      // stream into the NUMBERS after ordering, never into the ORDER — a
      // list that jumps because someone liked something mid-scroll is the
      // exact failure that decision forbids. (Reviewed out: an earlier cut
      // ranked over _withLive and every remote like re-sorted the feed.)
      MomentsFilter.mostEngaged => MomentDiscoveryService.rankByEngagement(
        pool,
      ),
      // Following renders from the cached personal slice; this path is
      // only used for chain lookups after it has rendered.
      MomentsFilter.following => _byCreatedDesc(
        (_socialData ?? const <VoiceMoment>[])
            .where((moment) => moment.isActiveAt(now))
            .toList(growable: false),
      ),
    };
  }

  List<MomentChain> _chainsFor(List<VoiceMoment> moments) =>
      buildMomentChains(moments);

  void _setFilter(MomentsFilter filter) {
    if (filter == _filter) return;
    unawaited(_stopPanelPlayback());
    setState(() {
      _filter = filter;
      _selectedId = null;
    });
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= _detailWidth;
        final compact = width < _tabletWidth;

        return Container(
          key: const ValueKey('moments-feed-view'),
          color: palette.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FilterChips(
                filter: _filter,
                onFilter: _setFilter,
                onRefresh: _load,
                compact: compact,
                recoveryFocusNode: _expiryRecoveryFocus,
              ),
              Expanded(
                child: _filter == MomentsFilter.following
                    ? _buildFollowing(wide: wide, compact: compact)
                    : _buildPool(wide: wide, compact: compact),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPool({required bool wide, required bool compact}) {
    switch (_phase) {
      case _Phase.loading:
        return const _LoadingState();
      case _Phase.error:
        return _ErrorState(error: _error, onRetry: _load);
      case _Phase.ready:
        break;
    }

    final result = _result!;
    if (result.corpusIsEmpty) {
      return _EmptyState(
        icon: Icons.mic_none_rounded,
        title: 'No Voice Moments yet',
        body:
            'Nobody has published one. Be the first — record up to 60 '
            'seconds and choose how long it stays.',
        actionLabel: 'Record a Moment',
        onAction: widget.onRecord,
      );
    }
    if (result.moments.isEmpty) {
      // Published Moments exist and none are live. Expiry is the normal
      // reason now; a corpus where something was dropped for
      // unplayability instead is still called out as the pipeline
      // failure it is.
      final expiredOnly = result.drops.values.every(
        (reason) =>
            reason == MomentDropReason.expired ||
            reason == MomentDropReason.blockedAuthor,
      );
      return _EmptyState(
        icon: expiredOnly
            ? Icons.timer_off_outlined
            : Icons.error_outline_rounded,
        title: expiredOnly
            ? 'Nothing live right now'
            : 'Nothing playable right now',
        body: expiredOnly
            ? '${result.fetchedCount} published '
                  '${result.fetchedCount == 1 ? 'Moment has' : 'Moments have'} '
                  'reached the end of ${result.fetchedCount == 1 ? 'its' : 'their'} '
                  'chosen availability. Record a new one to bring the feed '
                  'back.'
            : '${result.fetchedCount} published '
                  '${result.fetchedCount == 1 ? 'Moment' : 'Moments'} could '
                  'not be played back. This is usually temporary.',
        actionLabel: expiredOnly ? 'Record a Moment' : 'Try again',
        onAction: expiredOnly ? widget.onRecord : _load,
      );
    }

    // Order first on the frozen list, THEN merge live counters for display
    // (ADR-095: numbers move, layout does not).
    final ordered = _currentList();
    final list = ordered.map(_withLive).toList(growable: false);
    final chains = _chainsFor(list);
    final featured = _filter == MomentsFilter.discover
        ? MomentDiscoveryService.rankByEngagement(
            ordered,
          ).take(4).map(_withLive).toList(growable: false)
        : const <VoiceMoment>[];

    final feed = _FeedColumn(
      compact: compact,
      wide: wide,
      chains: chains,
      viewedIds: _viewedIds,
      featured: featured,
      listTitle: switch (_filter) {
        MomentsFilter.mostEngaged => 'Most engaged',
        _ => 'Recent Moments',
      },
      moments: list,
      selectedId: wide ? (_selectedId ?? list.first.id) : null,
      currentUserId: _uid,
      footer: _PoolFooter(total: list.length, moreExists: result.poolExhausted),
      onOpenChain: (chain) => unawaited(_openChain(chain)),
      onTapMoment: (moment) => _select(moment, wide: wide),
      onPlayMoment: (moment) => _select(moment, wide: wide, play: true),
      onOpenDetail: _openDetail,
      onReport: (moment) => unawaited(_report(moment)),
      onDelete: (moment) => unawaited(_confirmDelete(moment)),
      // "View all" is a real destination: the same pool in pure
      // engagement order — the Most engaged chip.
      onViewAllFeatured: featured.isEmpty
          ? null
          : () => _setFilter(MomentsFilter.mostEngaged),
    );

    if (!wide) return feed;
    final selected = list.firstWhere(
      (moment) => moment.id == (_selectedId ?? list.first.id),
      orElse: () => list.first,
    );
    return _withDetail(feed, selected);
  }

  Widget _buildFollowing({required bool wide, required bool compact}) {
    if (_socialError != null) {
      return _ErrorState(error: _socialError, onRetry: _retrySocial);
    }
    // No feed service at all reads as an empty circle rather than an
    // eternal skeleton; with one, the skeleton holds only until the
    // first emission arrives.
    if (_socialData == null && _feed != null) {
      return const _LoadingState();
    }
    final social = _socialData ?? const <VoiceMoment>[];
    final uid = _uid;

    final now = _effectiveNow();
    // Own Moments: everything still alive, plus drafts that are still
    // uploading — losing sight of a stuck upload is how a broken
    // pipeline hides.
    final mine = <VoiceMoment>[
      for (final moment in _mineData)
        if (moment.isActiveAt(now) ||
            (!moment.isPublished &&
                !moment.isDeleted &&
                moment.status != 'expired'))
          moment,
    ];
    final theirs = social
        .where((moment) => moment.authorId != uid)
        .map(_withLive)
        .toList(growable: false);

    if (mine.isEmpty && theirs.isEmpty) {
      return _EmptyState(
        key: const ValueKey('moments-following-empty'),
        icon: Icons.graphic_eq_rounded,
        title: 'Nothing here yet',
        body:
            'Moments from friends and people you follow show up '
            'here — and so do your own.',
        actionLabel: 'Record a Moment',
        onAction: widget.onRecord,
      );
    }

    final list = <VoiceMoment>[...mine.map(_withLive), ...theirs];
    final chains = _chainsFor(
      list.where((m) => m.isActiveAt(now)).toList(growable: false),
    );

    final feed = _FeedColumn(
      compact: compact,
      wide: wide,
      chains: chains,
      viewedIds: _viewedIds,
      featured: const <VoiceMoment>[],
      listTitle: 'From your circle',
      moments: list,
      selectedId: wide && list.isNotEmpty
          ? (_selectedId ?? list.first.id)
          : null,
      currentUserId: uid,
      footer: null,
      onOpenChain: (chain) => unawaited(_openChain(chain)),
      onTapMoment: (moment) => _select(moment, wide: wide),
      onPlayMoment: (moment) => _select(moment, wide: wide, play: true),
      onOpenDetail: _openDetail,
      onReport: (moment) => unawaited(_report(moment)),
      onDelete: (moment) => unawaited(_confirmDelete(moment)),
      onViewAllFeatured: null,
    );

    if (!wide || list.isEmpty) return feed;
    final selected = list.firstWhere(
      (moment) => moment.id == (_selectedId ?? list.first.id),
      orElse: () => list.first,
    );
    return _withDetail(feed, selected);
  }

  Widget _withDetail(Widget feed, VoiceMoment selected) {
    final uid = _uid;
    final isOwn = uid.isNotEmpty && uid == selected.authorId;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: feed),
        SizedBox(
          width: 360,
          child: MomentDetailPanel(
            key: const ValueKey('moments-detail-panel'),
            moment: selected,
            isPlaying: _playingId == selected.id && _isPlaying,
            elapsed: _playingId == selected.id ? _position : Duration.zero,
            duration: _playingId == selected.id ? _duration : null,
            playbackError: _playingId == selected.id ? _playbackError : null,
            feedService: _feed,
            momentService: _moments,
            currentUserId: uid,
            canReport: uid.isNotEmpty && !isOwn,
            isOwn: isOwn,
            onTogglePlay: () => unawaited(_togglePanelPlay(selected)),
            onSeek: (target) => unawaited(_seekPanel(selected, target)),
            onReport: () => unawaited(_report(selected)),
            onDelete: () => unawaited(_confirmDelete(selected)),
            onOpenThread: () => unawaited(_openComments(selected)),
          ),
        ),
      ],
    );
  }
}

/// One selected chip, violet fill; the rest quiet. Horizontal scroll so a
/// 2x text scale slides instead of overflowing.
class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.filter,
    required this.onFilter,
    required this.onRefresh,
    required this.compact,
    required this.recoveryFocusNode,
  });

  final MomentsFilter filter;
  final ValueChanged<MomentsFilter> onFilter;
  final VoidCallback onRefresh;
  final bool compact;
  final FocusNode recoveryFocusNode;

  static const _labels = <MomentsFilter, (String, IconData)>{
    MomentsFilter.discover: ('Discover', Icons.explore_outlined),
    MomentsFilter.following: ('Following', Icons.people_outline_rounded),
    MomentsFilter.mostEngaged: ('Most engaged', Icons.trending_up_rounded),
    MomentsFilter.recent: ('Recent', Icons.schedule_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 2, compact ? 8 : 16, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in _labels.entries) ...[
                    if (entry.key != MomentsFilter.discover)
                      const SizedBox(width: 8),
                    _FilterChip(
                      key: ValueKey('moments-filter-${entry.key.name}'),
                      label: entry.value.$1,
                      icon: entry.value.$2,
                      selected: filter == entry.key,
                      onTap: () => onFilter(entry.key),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('moments-discovery-refresh'),
            focusNode: recoveryFocusNode,
            onPressed: onRefresh,
            tooltip: 'Reload Moments',
            icon: Icon(Icons.refresh_rounded, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? colors.primary : palette.surfaceMuted,
        // Full pills, matching the mockup's chip grammar.
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? colors.onPrimary : palette.textSecondary,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? colors.onPrimary : palette.textSecondary,
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

/// The scrolling feed column: strip, featured cards, section list.
class _FeedColumn extends StatelessWidget {
  const _FeedColumn({
    required this.compact,
    required this.wide,
    required this.chains,
    required this.viewedIds,
    required this.featured,
    required this.listTitle,
    required this.moments,
    required this.selectedId,
    required this.currentUserId,
    required this.footer,
    required this.onOpenChain,
    required this.onTapMoment,
    required this.onPlayMoment,
    required this.onOpenDetail,
    required this.onReport,
    required this.onDelete,
    required this.onViewAllFeatured,
  });

  final bool compact;
  final bool wide;
  final List<MomentChain> chains;
  final Set<String> viewedIds;
  final List<VoiceMoment> featured;
  final String listTitle;
  final List<VoiceMoment> moments;
  final String? selectedId;
  final String currentUserId;
  final Widget? footer;
  final ValueChanged<MomentChain> onOpenChain;
  final ValueChanged<VoiceMoment> onTapMoment;
  final ValueChanged<VoiceMoment> onPlayMoment;
  final ValueChanged<VoiceMoment> onOpenDetail;
  final ValueChanged<VoiceMoment> onReport;
  final ValueChanged<VoiceMoment> onDelete;
  final VoidCallback? onViewAllFeatured;

  @override
  Widget build(BuildContext context) {
    final side = compact ? 16.0 : 24.0;
    return ListView(
      padding: EdgeInsets.fromLTRB(side, 4, side, 32),
      children: [
        if (chains.isNotEmpty) ...[
          MomentStoryStrip(
            chains: chains,
            viewedIds: viewedIds,
            onOpenChain: onOpenChain,
          ),
          const SizedBox(height: 18),
        ],
        if (featured.isNotEmpty) ...[
          _SectionTitle(
            'Featured Moments',
            trailing: onViewAllFeatured == null
                ? null
                : TextButton(
                    key: const ValueKey('moments-featured-view-all'),
                    onPressed: onViewAllFeatured,
                    child: const Text(
                      'View all',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ),
          SizedBox(
            // 210 at 1x, grown with the text scale (capped at 1.6, the same
            // cap the dock captions use): at 2x a fixed height left the
            // caption's render box shorter than one line, so its second line
            // — the one carrying the ellipsis — was clipped away entirely
            // and the first line's descenders were cut mid-glyph.
            height:
                210 *
                MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.6).scale(14) /
                14,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: featured.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _FeaturedCard(
                key: ValueKey('moment-featured-${featured[index].id}'),
                moment: featured[index],
                onTap: () => onTapMoment(featured[index]),
                onPlay: () => onPlayMoment(featured[index]),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        _SectionTitle(listTitle),
        for (final moment in moments)
          _MomentRow(
            key: ValueKey('moment-row-${moment.id}'),
            moment: moment,
            selected: selectedId == moment.id,
            isOwn: currentUserId.isNotEmpty && moment.authorId == currentUserId,
            onTap: () => onTapMoment(moment),
            onPlay: () => onPlayMoment(moment),
            onOpenDetail: () => onOpenDetail(moment),
            onReport: () => onReport(moment),
            onDelete: () => onDelete(moment),
          ),
        if (footer != null) ...[const SizedBox(height: 14), footer!],
      ],
    );
  }
}

/// The horizontal strip of author chains. A gradient ring means the chain
/// still holds something this account has not heard; a dimmed ring means
/// every link was heard. Both facts come from the caller's own
/// `momentViews` docs — nothing is invented.
class MomentStoryStrip extends StatelessWidget {
  const MomentStoryStrip({
    required this.chains,
    required this.viewedIds,
    required this.onOpenChain,
    super.key,
  });

  final List<MomentChain> chains;
  final Set<String> viewedIds;
  final ValueChanged<MomentChain> onOpenChain;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chains.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final chain = chains[index];
          final unviewed = chain.hasUnviewed(viewedIds);
          return _ChainCircle(
            key: ValueKey('moments-chain-${chain.authorId}'),
            chain: chain,
            unviewed: unviewed,
            onTap: () => onOpenChain(chain),
          );
        },
      ),
    );
  }
}

class _ChainCircle extends StatelessWidget {
  const _ChainCircle({
    required this.chain,
    required this.unviewed,
    required this.onTap,
    super.key,
  });

  final MomentChain chain;
  final bool unviewed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final label = chain.length > 1
        ? '${chain.authorName}, ${chain.length} Moments'
        : chain.authorName;
    return Semantics(
      button: true,
      label:
          'Open the story chain by $label'
          '${unviewed ? ', has unheard Moments' : ', all heard'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 76,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: unviewed ? AppGradients.primary : null,
                      border: unviewed
                          ? null
                          : Border.all(color: palette.border, width: 1.4),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.background,
                      ),
                      child: Opacity(
                        opacity: unviewed ? 1 : .6,
                        child: UserAvatar(
                          radius: 27,
                          photoUrl: chain.authorPhotoUrl,
                          displayName: chain.authorName,
                        ),
                      ),
                    ),
                  ),
                  if (chain.length > 1)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: colors.primary,
                          border: Border.all(
                            color: palette.background,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          '${chain.length}',
                          style: TextStyle(
                            color: colors.onPrimary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                chain.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: unviewed ? palette.textPrimary : palette.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A featured card in the mockup's grammar: a big cover area with the
/// duration badge top-left and the violet play circle over it, then
/// title, author and the metrics row.
///
/// Audio-first on purpose — the cover is waveform art over a violet
/// gradient, never a stock image (Moments have no cover images), and the
/// metrics are the document's real like and comment counters only (no
/// play counter exists in the schema, so none is printed).
class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    required this.moment,
    required this.onTap,
    required this.onPlay,
    super.key,
  });

  final VoiceMoment moment;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final age = momentRelativeAge(moment.createdAt);
    final expiry = momentExpiryLabel(moment.expiresAt);
    return Semantics(
      button: true,
      label: 'Featured Moment by ${moment.authorName}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 236,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: palette.surface,
            border: Border.all(color: colors.primary.withValues(alpha: .35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The cover: gradient + waveform art, play circle centred,
              // duration badge top-left — the audio-first stand-in for
              // the mockup's image cover.
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(
                              palette.surface,
                              colors.primary,
                              isDark ? .55 : .16,
                            )!,
                            Color.lerp(
                              palette.surface,
                              colors.secondary,
                              isDark ? .3 : .1,
                            )!,
                            palette.surface,
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Center(
                        child: StoryWaveform(progress: 0, height: 34),
                      ),
                    ),
                    Center(
                      child: Semantics(
                        button: true,
                        label: 'Play this featured Moment',
                        child: Material(
                          color: colors.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            key: ValueKey('moment-featured-play-${moment.id}'),
                            onTap: onPlay,
                            customBorder: const CircleBorder(),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(
                                Icons.play_arrow_rounded,
                                size: 26,
                                color: colors.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (moment.durationSeconds > 0)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.black.withValues(alpha: .55),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            moment.durationLabel,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      moment.caption.trim().isEmpty
                          ? 'Voice Moment'
                          : moment.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      moment.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (moment.likeCount > 0) ...[
                          const Icon(
                            Icons.favorite_rounded,
                            size: 12,
                            color: AppColors.secondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${moment.likeCount}',
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (moment.commentCount > 0) ...[
                          Icon(
                            Icons.mode_comment_rounded,
                            size: 11,
                            color: palette.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${moment.commentCount}',
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // The trailing label is flexible: at a 2x text
                        // scale the fixed 210-pt card cannot carry it at
                        // natural width, and ellipsis beats an overflow
                        // stripe. Exactly ONE trailing fact renders — the
                        // expiry when a deadline exists (rendered whole,
                        // where age beside it truncated it to "Expires
                        // i…" even at 1x), otherwise the age. A permanent
                        // Moment has no deadline, so it shows its age.
                        Expanded(
                          child: Text(
                            expiry ?? age,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: expiry != null
                                  ? (isDark
                                        ? AppColors.warning
                                        : const Color(0xFF8A4B00))
                                  : palette.textTertiary,
                              fontSize: 11,
                              fontWeight: expiry != null
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One list row: avatar, play, waveform, caption (tap it for the detail
/// page), author, real counters, a right column with duration and age —
/// and the overflow menu carrying Details plus Report on others' Moments
/// or Delete on the caller's own.
class _MomentRow extends StatelessWidget {
  const _MomentRow({
    required this.moment,
    required this.selected,
    required this.isOwn,
    required this.onTap,
    required this.onPlay,
    required this.onOpenDetail,
    required this.onReport,
    required this.onDelete,
    super.key,
  });

  final VoiceMoment moment;
  final bool selected;
  final bool isOwn;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback onOpenDetail;
  final VoidCallback onReport;
  final VoidCallback onDelete;

  bool get _uploading => !moment.isPublished;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final age = momentRelativeAge(moment.createdAt);
    // The author sees their Moment's real availability — including
    // "Stays until deleted" for a permanent one. Everyone else sees a
    // countdown only when a deadline actually exists.
    final expiry = isOwn && moment.isPublished
        ? momentAvailabilityLabel(moment.expiresAt)
        : momentExpiryLabel(moment.expiresAt);
    final permanent = moment.isPermanent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label:
            'Open the Moment by ${moment.authorName}'
            '${_uploading ? ', still uploading' : ''}',
        child: Material(
          color: selected
              ? colors.primary.withValues(alpha: isDark ? .16 : .1)
              : palette.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected
                      ? colors.primary.withValues(alpha: .55)
                      : palette.border,
                ),
              ),
              child: Row(
                children: [
                  UserAvatar(
                    radius: 21,
                    photoUrl: moment.authorPhotoUrl,
                    displayName: moment.authorName,
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    key: ValueKey('moment-row-play-${moment.id}'),
                    onPressed: _uploading ? null : onPlay,
                    tooltip: _uploading
                        ? 'Still uploading'
                        : 'Play this Moment',
                    style: IconButton.styleFrom(
                      backgroundColor: colors.primary.withValues(
                        alpha: _uploading ? .25 : 1,
                      ),
                      foregroundColor: colors.onPrimary,
                    ),
                    icon: Icon(
                      Icons.play_arrow_rounded,
                      color: colors.onPrimary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The title is its own tap target: the row body
                        // still opens the quick sheet/panel, the title
                        // goes to the full detail page.
                        GestureDetector(
                          key: ValueKey('moment-row-title-${moment.id}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: _uploading ? null : onOpenDetail,
                          child: Semantics(
                            button: !_uploading,
                            label:
                                'Open details of the Moment by '
                                '${moment.authorName}',
                            child: Text(
                              moment.caption.trim().isEmpty
                                  ? 'Voice Moment'
                                  : moment.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        StoryWaveform(progress: 0, height: 16),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    moment.authorName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.textSecondary,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                UserIdentityBadges(
                                  uid: moment.authorId,
                                  variant: IdentityBadgeVariant.icon,
                                ),
                              ],
                            ),
                            if (_uploading)
                              Text(
                                'Uploading…',
                                style: TextStyle(
                                  color: palette.textTertiary,
                                  fontSize: 11.5,
                                ),
                              )
                            else if (expiry != null)
                              Text(
                                expiry,
                                style: TextStyle(
                                  // A permanent Moment's label is a calm
                                  // fact, not a warning-coloured countdown.
                                  color: permanent
                                      ? palette.textTertiary
                                      : (isDark
                                            ? AppColors.warning
                                            : const Color(0xFF8A4B00)),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Bounded, because every sibling of the Expanded centre
                  // is fixed-width: at a 2x text scale an unconstrained
                  // "0:45 · 2h ago" is wider than the slack a 390-pt
                  // phone has, and the row must squeeze (ellipsize)
                  // rather than overflow.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 96),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // The mockup's right column: duration, then age.
                        if (!_uploading && moment.durationSeconds > 0)
                          Text(
                            moment.durationLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        if (!_uploading && age.isNotEmpty)
                          Text(
                            age,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        if (moment.likeCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.favorite_rounded,
                                  size: 12,
                                  color: AppColors.secondary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${moment.likeCount}',
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (moment.commentCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.mode_comment_rounded,
                                  size: 11,
                                  color: palette.textSecondary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${moment.commentCount}',
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    key: ValueKey('moment-row-menu-${moment.id}'),
                    tooltip: 'More',
                    color: palette.surfaceRaised,
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: palette.textSecondary,
                    ),
                    onSelected: (value) {
                      if (value == 'details') onOpenDetail();
                      if (value == 'report') onReport();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      // No Details while the OWN draft is still uploading:
                      // the detail page's gone-check reads any unpublished
                      // doc as "reached the end of its availability", which
                      // would tell an author mid-upload their brand-new
                      // Moment was deleted.
                      if (!_uploading)
                        PopupMenuItem<String>(
                          value: 'details',
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: palette.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Details',
                                style: TextStyle(color: palette.textPrimary),
                              ),
                            ],
                          ),
                        ),
                      // Delete on OWN Moments only — the author's exit,
                      // and for a permanent Moment the only one. Report
                      // only on others': reporting yourself is not a real
                      // intent.
                      if (isOwn)
                        PopupMenuItem<String>(
                          key: ValueKey('moment-row-delete-${moment.id}'),
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: colors.error,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Delete',
                                style: TextStyle(color: colors.error),
                              ),
                            ],
                          ),
                        )
                      else
                        PopupMenuItem<String>(
                          key: ValueKey('moment-row-report-${moment.id}'),
                          value: 'report',
                          child: Row(
                            children: [
                              Icon(
                                Icons.flag_outlined,
                                size: 18,
                                color: palette.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Report',
                                style: TextStyle(color: palette.textPrimary),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the feed actually holds, counted rather than estimated. There is
/// no "Load more": the pool is a bounded one-shot load with no pagination
/// cursor, and a button that pretends otherwise would be a lie.
class _PoolFooter extends StatelessWidget {
  const _PoolFooter({required this.total, required this.moreExists});

  final int total;
  final bool moreExists;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final noun = total == 1 ? 'Moment' : 'Moments';
    return Text(
      moreExists
          ? '$total live $noun loaded — more are published than fit one '
                'load. Reload to draw again.'
          : (total == 1
                ? 'That is the only live Moment right now.'
                : 'That is all $total live Moments right now.'),
      textAlign: TextAlign.center,
      style: TextStyle(color: palette.textTertiary, fontSize: 12, height: 1.4),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});

  final String text;

  /// An optional action on the heading row — "View all" on the featured
  /// rail. Squeezes (ellipsis) before the title does at large text scales.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final title = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: palette.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: trailing == null
          ? title
          : Row(
              children: [
                Expanded(child: title),
                // NOT Flexible: a loose flex child next to an Expanded
                // SPLITS the free space, which parked "View all" in the
                // middle of a desktop row. Inflexible, it takes its
                // intrinsic width at the row's end and the title absorbs
                // (and ellipsizes over) everything else.
                trailing!,
              ],
            ),
    );
  }
}

/// The right detail panel (wide layouts): identity, caption, player,
/// like/comment/share/report, and the inline comment thread with its
/// composer — the existing comment service, not a new one.
class MomentDetailPanel extends StatefulWidget {
  const MomentDetailPanel({
    required this.moment,
    required this.isPlaying,
    required this.elapsed,
    required this.duration,
    required this.playbackError,
    required this.feedService,
    required this.momentService,
    required this.currentUserId,
    required this.canReport,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onReport,
    required this.onOpenThread,
    this.isOwn = false,
    this.onDelete,
    super.key,
  });

  final VoiceMoment moment;
  final bool isPlaying;
  final Duration elapsed;
  final Duration? duration;
  final String? playbackError;
  final HomeFeedService? feedService;
  final MomentService? momentService;
  final String currentUserId;
  final bool canReport;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onReport;
  final VoidCallback onOpenThread;

  /// True when the panel shows the caller's own Moment: the availability
  /// line appears ("Stays until deleted" for a permanent one) and the
  /// Delete action joins the row.
  final bool isOwn;
  final VoidCallback? onDelete;

  @override
  State<MomentDetailPanel> createState() => _MomentDetailPanelState();
}

class _MomentDetailPanelState extends State<MomentDetailPanel> {
  final TextEditingController _composer = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    final service = widget.momentService;
    if (text.isEmpty || service == null || _sending) return;
    setState(() => _sending = true);
    try {
      await service.createTextComment(momentId: widget.moment.id, text: text);
      _composer.clear();
    } catch (error) {
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

  Future<void> _share() async {
    // The same real link mechanism Home's feed already uses: the website
    // resolves ?moment= on yovoice.app. Nothing new is invented here.
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Listen to ${widget.moment.authorName} on YO Voice: '
            'https://yovoice.app/?moment=${widget.moment.id}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final moment = widget.moment;
    final age = momentRelativeAge(moment.createdAt);
    // The author sees the availability fact even for a permanent Moment
    // ("Stays until deleted"); everyone else only sees a real countdown.
    final expiry = widget.isOwn
        ? momentAvailabilityLabel(moment.expiresAt)
        : momentExpiryLabel(moment.expiresAt);
    final totalSeconds = widget.duration?.inSeconds ?? moment.durationSeconds;
    final hasTotal = totalSeconds > 0;
    final progress = hasTotal
        ? (widget.elapsed.inMilliseconds / (totalSeconds * 1000)).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(left: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
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
                                if (expiry != null)
                                  Text(
                                    expiry,
                                    key: const ValueKey('detail-expiry-label'),
                                    style: TextStyle(
                                      // A permanent Moment's label is a
                                      // calm fact, not a countdown.
                                      color: moment.isPermanent
                                          ? palette.textTertiary
                                          : (isDark
                                                ? AppColors.warning
                                                : const Color(0xFF8A4B00)),
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
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14.5,
                        height: 1.42,
                      ),
                    ),
                  ],
                  if (widget.playbackError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.playbackError!,
                      style: TextStyle(color: colors.error, fontSize: 12.5),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Semantics(
                        button: true,
                        label: widget.isPlaying
                            ? 'Pause this Moment'
                            : 'Play this Moment',
                        child: Material(
                          color: colors.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            key: const ValueKey('detail-play-toggle'),
                            customBorder: const CircleBorder(),
                            onTap: widget.onTogglePlay,
                            child: SizedBox(
                              width: 54,
                              height: 54,
                              child: Icon(
                                widget.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: colors.onPrimary,
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
                            LayoutBuilder(
                              builder: (context, waveConstraints) {
                                final waveWidth = waveConstraints.maxWidth;
                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapDown: hasTotal && waveWidth > 0
                                      ? (details) {
                                          final fraction =
                                              (details.localPosition.dx /
                                                      waveWidth)
                                                  .clamp(0.0, 1.0);
                                          widget.onSeek(
                                            Duration(
                                              milliseconds:
                                                  (totalSeconds *
                                                          1000 *
                                                          fraction)
                                                      .round(),
                                            ),
                                          );
                                        }
                                      : null,
                                  child: StoryWaveform(
                                    progress: progress,
                                    height: 30,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 6),
                            Text(
                              hasTotal
                                  ? '${_clock(widget.elapsed.inSeconds)} / '
                                        '${_clock(totalSeconds)}'
                                  : '',
                              style: TextStyle(
                                color: palette.textTertiary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _DetailActions(
                    moment: moment,
                    feedService: widget.feedService,
                    canReport: widget.canReport,
                    canDelete: widget.isOwn && widget.onDelete != null,
                    onShare: () => unawaited(_share()),
                    onReport: widget.onReport,
                    onDelete: widget.onDelete,
                  ),
                  const SizedBox(height: 16),
                  Divider(color: palette.border, height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Comments',
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      // Flexible + ellipsis: at a 2x text scale the
                      // button's label is wider than the whole panel
                      // column and must squeeze, not overflow.
                      Flexible(
                        child: TextButton(
                          key: const ValueKey('detail-open-thread'),
                          onPressed: widget.onOpenThread,
                          child: const Text(
                            'Open thread',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  MomentCommentsInline(
                    momentId: moment.id,
                    momentService: widget.momentService,
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              border: Border(top: BorderSide(color: palette.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('detail-comment-field'),
                    controller: _composer,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => unawaited(_send()),
                    enabled: widget.momentService != null,
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
                  key: const ValueKey('detail-comment-send'),
                  onPressed: _sending || widget.momentService == null
                      ? null
                      : _send,
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
          ),
        ],
      ),
    );
  }
}

class _DetailActions extends StatelessWidget {
  const _DetailActions({
    required this.moment,
    required this.feedService,
    required this.canReport,
    required this.canDelete,
    required this.onShare,
    required this.onReport,
    required this.onDelete,
  });

  final VoiceMoment moment;
  final HomeFeedService? feedService;
  final bool canReport;

  /// Own Moments only: the author's exit, and for a permanent Moment the
  /// only one.
  final bool canDelete;
  final VoidCallback onShare;
  final VoidCallback onReport;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final service = feedService;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (service == null)
          _SmallChip(
            icon: Icons.favorite_border_rounded,
            label: moment.likeCount == 0 ? 'Like' : '${moment.likeCount}',
            active: false,
            onTap: null,
          )
        else
          StreamBuilder<bool>(
            stream: service.watchLiked(moment.id),
            builder: (context, snapshot) {
              final liked = snapshot.hasError
                  ? false
                  : (snapshot.data ?? false);
              return _SmallChip(
                key: const ValueKey('detail-like'),
                icon: liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: moment.likeCount == 0 ? 'Like' : '${moment.likeCount}',
                active: liked,
                semanticLabel: liked
                    ? 'Unlike this Moment'
                    : 'Like this Moment',
                onTap: () => unawaited(_toggle(context, service)),
              );
            },
          ),
        _SmallChip(
          key: const ValueKey('detail-share'),
          icon: Icons.share_outlined,
          label: 'Share',
          active: false,
          semanticLabel: 'Share this Moment',
          onTap: onShare,
        ),
        if (canReport)
          _SmallChip(
            key: ValueKey('detail-report-${moment.id}'),
            icon: Icons.flag_outlined,
            label: 'Report',
            active: false,
            semanticLabel: 'Report this Voice Moment',
            onTap: onReport,
          ),
        if (canDelete)
          _SmallChip(
            key: ValueKey('detail-delete-${moment.id}'),
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            active: false,
            destructive: true,
            semanticLabel: 'Delete this Voice Moment',
            onTap: onDelete,
          ),
      ],
    );
  }

  Future<void> _toggle(BuildContext context, HomeFeedService service) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await service.toggleLike(moment.id);
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
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({
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
        : (active ? AppColors.secondary : palette.textSecondary);
    return Semantics(
      button: onTap != null,
      label: semanticLabel ?? label,
      child: Material(
        color: destructive ? palette.dangerSurface : palette.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 68),
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

/// The comment thread rendered inline in the detail panel — the same
/// documents, via [MomentService.watchComments].
class MomentCommentsInline extends StatelessWidget {
  const MomentCommentsInline({
    required this.momentId,
    required this.momentService,
    super.key,
  });

  final String momentId;
  final MomentService? momentService;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final service = momentService;
    if (service == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          'Comments are unavailable right now.',
          style: TextStyle(color: palette.textTertiary, fontSize: 12.5),
        ),
      );
    }
    return StreamBuilder<List<MomentComment>>(
      stream: service.watchComments(momentId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Could not load comments.',
              style: TextStyle(color: palette.textTertiary, fontSize: 12.5),
            ),
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
        if (comments.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Be the first to comment.',
              style: TextStyle(color: palette.textTertiary, fontSize: 12.5),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final comment in comments)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UserAvatar(
                      radius: 14,
                      photoUrl: comment.authorPhotoUrl,
                      displayName: comment.authorName,
                    ),
                    const SizedBox(width: 9),
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
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
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
                          if (comment.isVoice)
                            Text(
                              'Voice reply · ${comment.durationSeconds}s'
                              '${comment.text.isNotEmpty ? ' — ${comment.text}' : ''}',
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            )
                          else
                            Text(
                              comment.text,
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    Widget bone(double width, double height, [double radius = 10]) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    return ListView(
      key: const ValueKey('moments-discovery-loading'),
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
      children: [
        // The strip skeleton mirrors the real story strip's geometry: a
        // horizontal list, not a Row. Five fixed 80-pt bones in a Row
        // overflowed a 390-pt phone by 54 px (390 − 44 padding = 346 <
        // 400); a non-scrollable horizontal list clips gracefully at any
        // width instead.
        SizedBox(
          height: 92,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 5,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(right: 14),
              child: bone(66, 66, 33),
            ),
          ),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: bone(double.infinity, 74, 18),
          ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey('moments-discovery-error'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 34, color: colors.error),
            const SizedBox(height: 14),
            Text(
              'Moments could not load',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Something went wrong reaching the Voice Moments feed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            if (kDebugMode && error != null) ...[
              const SizedBox(height: 14),
              SelectableText(
                '$error',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textTertiary, fontSize: 11.5),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Center(
      key: const ValueKey('moments-discovery-empty'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: palette.textSecondary),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
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
