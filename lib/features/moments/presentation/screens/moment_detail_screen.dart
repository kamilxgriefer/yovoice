import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/home/data/services/home_feed_service.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_content_flow.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_expiry_scheduler.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/data/services/moment_views_service.dart';
import 'package:yovoice/features/moments/presentation/screens/moment_comments_screen.dart';
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_conversation_thread.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_mention_composer.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_mentions.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_progress_ring.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_viewer.dart'
    show StoryWaveform;
import 'package:yovoice/features/moments/presentation/widgets/moment_time_labels.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_transport_controls.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_queue_list.dart';
import 'package:yovoice/features/moments/presentation/widgets/reply_playback_arbiter.dart';
import 'package:yovoice/features/moments/presentation/widgets/yo_moments_chrome.dart'
    show YoMomentsLayout, YoMomentsLayoutTier;
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

enum _MomentDetailRefreshTrigger {
  initial,
  appResume,
  routeReturn,
  mutation,
  retry,
}

bool _momentDetailIsGoneError(Object error) =>
    error is FirebaseFunctionsException &&
    const <String>{
      'permission-denied',
      'not-found',
      'gone',
    }.contains(error.code);

/// One Voice Moment, expanded: the author's avatar inside a listening-progress
/// ring, the caption as the heading, one dominant transport (slider, ±15 s,
/// play/pause), engagement, and the "Rozmowa" thread with its voice replies
/// and composer.
///
/// Every fact rendered is a document's fact. Moments carry no separate title,
/// no tags and no cover, so the caption IS the heading, no tag chips exist and
/// the waveform-and-ring hero is the production design rather than a
/// placeholder image; there is no play counter in the schema, so none is
/// printed, and the ring means listening PROGRESS — never presence, never
/// "live". The "Top reactions" avatars come from the same privacy-filtered v2
/// projection as the Moment, best-effort.
///
/// Pushed as a plain route it carries its own Back control; the shell hosts it
/// inside the persistent bottom navigation (Moments active) on mobile. The
/// author additionally sees the availability line — a real countdown, or
/// "Stays until deleted" for a permanent Moment — and the Delete action.
///
/// Nothing here starts audio on its own: arriving allocates no player, the
/// thread's replies wait for a tap, the microphone only ever starts inside
/// [RecordVoiceMomentScreen], and reaching the end of a recording starts
/// nothing else.
class MomentDetailScreen extends StatefulWidget {
  const MomentDetailScreen({
    required this.moment,
    this.momentService,
    this.feedService,
    this.viewsService,
    this.contentReportService,
    this.auth,
    this.friendService,
    this.mentionFriendsStream,
    this.neighbours,
    this.neighbourQueue,
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

  /// Backs the composer's `@` suggestions with the caller's own friends.
  /// Injection seams only — production passes nothing and the screen
  /// resolves the live [FriendService], failing quiet when it cannot.
  final FriendService? friendService;
  final Stream<List<FriendUser>>? mentionFriendsStream;

  /// The already-loaded neighbours of this Moment, newest-first, for the
  /// widest layout's hand-off list. Given explicitly they win; otherwise the
  /// screen reads whatever the feed last published for THIS account.
  final List<VoiceMoment>? neighbours;
  final MomentNeighbourQueue? neighbourQueue;

  @visibleForTesting
  final AudioPlayer Function()? playerFactory;

  @visibleForTesting
  final MomentExpiryClock? expiryClock;

  @visibleForTesting
  final MomentExpiryTimerFactory? expiryTimerFactory;

  @override
  State<MomentDetailScreen> createState() => _MomentDetailScreenState();
}

class _MomentDetailScreenState extends State<MomentDetailScreen>
    with RouteAware, WidgetsBindingObserver {
  MomentService? _moments;
  HomeFeedService? _feed;
  MomentViewsService? _views;

  late VoiceMoment _moment = widget.moment;

  /// The document disappeared. Either it never loaded (opened from a
  /// stale reference) or it was deleted while open — both render the
  /// graceful gone-state; the author's own delete pops instead.
  bool _missing = false;
  bool _selfDeleted = false;
  bool _deleting = false;
  bool _liking = false;
  late final MomentExpiryScheduler _expiry;
  DateTime? _expiredThrough;
  bool _expiredByDeadline = false;

  Future<List<MomentReactor>>? _reactions;

  /// The first page of the thread from the SAME view read that produced
  /// the Moment — never a second fetch just to show a preview.
  List<MomentComment>? _comments;
  bool _commentsTruncated = false;
  String? _nextCommentCursor;
  bool _loadingMore = false;
  Object? _commentsError;
  ModalRoute<void>? _observedRoute;
  final Set<_MomentDetailRefreshTrigger> _canonicalRefreshesInFlight =
      <_MomentDetailRefreshTrigger>{};
  int _viewLoadGeneration = 0;

  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _playerSubscriptions =
      <StreamSubscription<dynamic>>[];
  bool _isPlaying = false;
  bool _everPlayed = false;
  bool _playbackBusy = false;
  bool _openingNeighbour = false;

  /// The ONE position this screen owns. The ring, the waveform, the slider
  /// and the clock all read it, and a position tick repaints exactly those
  /// four — it must never rebuild the route (the thread used to rebuild on
  /// every tick, which is why this is a notifier and not `setState`).
  final ValueNotifier<Duration> _position = ValueNotifier<Duration>(
    Duration.zero,
  );
  final ValueNotifier<Duration?> _duration = ValueNotifier<Duration?>(null);
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  String? _playbackError;

  late final ReplyPlaybackArbiter _arbiter = ReplyPlaybackArbiter(
    onPauseMainPlayback: _pauseForReply,
  );
  late final MomentNeighbourQueue _neighbourQueue =
      widget.neighbourQueue ?? MomentNeighbourQueue.shared;

  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode(debugLabel: 'Moment comment');
  final FocusNode _goneBackFocus = FocusNode(debugLabel: 'Expired Moment back');
  final MomentExpiryAnnouncer _expiryAnnouncer = MomentExpiryAnnouncer();
  late final MentionFriendsSource _mentionFriends;
  bool _sending = false;

  AppLocalizations get _copy => AppLocalizations.of(context);

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
    WidgetsBinding.instance.addObserver(this);
    _expiry = MomentExpiryScheduler(
      onDeadline: _handleExpiryDeadline,
      clock: widget.expiryClock,
      timerFactory: widget.expiryTimerFactory,
    );
    _expiredByDeadline = !_moment.isActiveAt(_effectiveNow());
    if (!_expiredByDeadline) _rescheduleExpiry();
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
    _mentionFriends = MentionFriendsSource(
      friendsStream: widget.mentionFriendsStream,
      friendService: widget.friendService,
    )..addListener(_handleMentionFriends);
    _neighbourQueue.addListener(_handleNeighbours);

    final moments = _moments;
    if (moments != null) {
      unawaited(_loadView(trigger: _MomentDetailRefreshTrigger.initial));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (identical(route, _observedRoute)) return;
    if (_observedRoute != null) appRouteObserver.unsubscribe(this);
    _observedRoute = route;
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  @override
  void didPopNext() {
    unawaited(_loadView(trigger: _MomentDetailRefreshTrigger.routeReturn));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_loadView(trigger: _MomentDetailRefreshTrigger.appResume));
  }

  Future<void> _loadView({
    _MomentDetailRefreshTrigger trigger = _MomentDetailRefreshTrigger.retry,
  }) async {
    final service = _moments;
    if (service == null) return;
    if (!_canonicalRefreshesInFlight.add(trigger)) return;
    final requestGeneration = ++_viewLoadGeneration;
    final momentId = _moment.id;
    try {
      final view = await service.loadMomentView(momentId);
      if (!mounted || requestGeneration != _viewLoadGeneration) return;
      final expired = !view.moment.isActiveAt(_effectiveNow());
      setState(() {
        _missing = false;
        _moment = view.moment;
        _expiredByDeadline = expired;
        _comments = view.comments;
        _commentsTruncated = view.commentsTruncated;
        _nextCommentCursor = view.nextCommentCursor;
        _commentsError = null;
        _reactions = Future<List<MomentReactor>>.value(view.topReactions);
      });
      if (expired) {
        _expiry.schedule(const <VoiceMoment>[]);
        _stopPlaybackForGone();
        _announceGone(previousFocus: null);
      } else {
        _rescheduleExpiry();
      }
    } catch (error) {
      if (!mounted || requestGeneration != _viewLoadGeneration) return;
      if (_momentDetailIsGoneError(error)) {
        _clearProjectionAndShowGone();
      } else {
        setState(() => _commentsError = error);
      }
    } finally {
      _canonicalRefreshesInFlight.remove(trigger);
    }
  }

  /// Appends the next page of the thread in place. The server pages the
  /// conversation OLDEST first, so this cursor returns the more recent
  /// replies — which is what the button's copy promises.
  Future<void> _loadMoreComments() async {
    final service = _moments;
    final cursor = _nextCommentCursor;
    if (service == null || cursor == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    final generation = _viewLoadGeneration;
    try {
      final view = await service.loadMomentView(
        _moment.id,
        commentCursor: cursor,
      );
      if (!mounted || generation != _viewLoadGeneration) return;
      final byId = <String, MomentComment>{
        for (final comment in _comments ?? const <MomentComment>[])
          comment.id: comment,
        for (final comment in view.comments) comment.id: comment,
      };
      setState(() {
        _comments = byId.values.toList(growable: false);
        _commentsTruncated = view.commentsTruncated;
        _nextCommentCursor = view.nextCommentCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || generation != _viewLoadGeneration) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              _copy.text(
                'Could not load more replies. Try again.',
                'Nie udało się wczytać kolejnych odpowiedzi. Spróbuj ponownie.',
              ),
            ),
          ),
        );
    }
  }

  void _clearProjectionAndShowGone() {
    final previousFocus = FocusManager.instance.primaryFocus;
    final recoverFocus = momentExpiryFocusIsWithin(context, previousFocus);
    _expiry.schedule(const <VoiceMoment>[]);
    _stopPlaybackForGone(notify: false);
    setState(() {
      _missing = true;
      _comments = null;
      _commentsTruncated = false;
      _nextCommentCursor = null;
      _commentsError = null;
      _reactions = null;
      _playbackError = null;
    });
    _announceGone(previousFocus: recoverFocus ? previousFocus : null);
  }

  void _handleMentionFriends() {
    if (mounted) setState(() {});
  }

  /// A new pool arrived from the feed (a refresh, a filter change, a
  /// signed-in account change). The hand-off list is derived at paint time,
  /// so simply rebuilding is enough — and rescheduling expiry keeps a
  /// neighbour from outliving its own deadline in the list.
  void _handleNeighbours() {
    if (!mounted) return;
    setState(() {});
    if (!_gone) _rescheduleExpiry();
  }

  /// The full thread, with its voice playback, reporting and pagination.
  ///
  /// Returning here re-reads the view through [didPopNext], so a comment
  /// posted there shows up on this page.
  Future<void> _openAllComments() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MomentCommentsScreen(
          moment: _moment,
          momentService: _moments,
          auth: widget.auth,
          contentReportService: widget.contentReportService,
          friendService: widget.friendService,
          mentionFriendsStream: widget.mentionFriendsStream,
          expiryClock: widget.expiryClock,
          expiryTimerFactory: widget.expiryTimerFactory,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _viewLoadGeneration += 1;
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _neighbourQueue.removeListener(_handleNeighbours);
    _mentionFriends
      ..removeListener(_handleMentionFriends)
      ..dispose();
    _expiry.dispose();
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
    _player?.dispose();
    _arbiter.dispose();
    _position.dispose();
    _duration.dispose();
    _progress.dispose();
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

  bool get _gone =>
      (_missing && !_selfDeleted) ||
      _expiredByDeadline ||
      !_moment.isActiveAt(_effectiveNow());

  void _rescheduleExpiry() =>
      _expiry.schedule(<VoiceMoment>[_moment, ..._neighbourPool()]);

  /// The recording's length: the player's confirmed duration once it is
  /// known, the document's own `durationSeconds` before that.
  Duration get _totalDuration =>
      _duration.value ?? Duration(seconds: _moment.durationSeconds);

  void _publishProgress() {
    final total = _totalDuration.inMilliseconds;
    _progress.value = total > 0
        ? (_position.value.inMilliseconds / total).clamp(0.0, 1.0)
        : 0.0;
  }

  void _stopPlaybackForGone({bool notify = true}) {
    final player = _player;
    if (player != null) {
      unawaited(player.stop().catchError((Object _) {}));
    }
    if (!mounted) return;
    void clearPlaybackState() {
      _isPlaying = false;
      _playbackBusy = false;
    }

    _position.value = Duration.zero;
    _duration.value = null;
    _publishProgress();
    if (notify) {
      setState(clearPlaybackState);
    } else {
      clearPlaybackState();
    }
  }

  void _handleExpiryDeadline(DateTime deadline) {
    if (!mounted) return;
    if (_expiredThrough == null || deadline.isAfter(_expiredThrough!)) {
      _expiredThrough = deadline;
    }
    if (_moment.isActiveAt(_effectiveNow())) {
      // A neighbour in the hand-off list reached ITS deadline: it drops out
      // of the list on this rebuild, and the rest keep their timers.
      setState(() {});
      _rescheduleExpiry();
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
      transition: 'detail-gone-${_moment.id}',
      message: _copy.text(
        'Voice Moment is no longer available.',
        'Ten Voice Moment nie jest już dostępny.',
      ),
    );
    // The composer stays MOUNTED after the recording is gone — disabled,
    // with the reason under it — so the node that held focus is still in
    // the tree and would quietly keep it. Focus is moved off it explicitly
    // and forced onto the one control that still does something.
    if (previousFocus != null && previousFocus.hasFocus) {
      previousFocus.unfocus();
    }
    recoverMomentExpiryFocusAfterFrame(
      context: context,
      fallback: _goneBackFocus,
      previousFocus: previousFocus,
      force: previousFocus != null,
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
          _position.value = position;
          _publishProgress();
          // Clearing an error is a state transition, not a tick: only then
          // does the route rebuild.
          if (_playbackError != null) {
            setState(() => _playbackError = null);
          }
        }),
      )
      ..add(
        player.onDurationChanged.listen((duration) {
          if (!mounted) return;
          _duration.value = duration;
          _publishProgress();
        }),
      )
      ..add(
        player.onPlayerComplete.listen((_) {
          if (!mounted) return;
          // The end of a recording ends playback and starts nothing else:
          // no auto-advance, no neighbour, no queue.
          _position.value = _duration.value ?? _position.value;
          _publishProgress();
          setState(() {
            _isPlaying = false;
            _playbackBusy = false;
          });
        }),
      );
    return player;
  }

  Future<void> _togglePlay() async {
    final moments = _moments;
    if (moments == null || !_moment.hasMediaReference) {
      setState(
        () => _playbackError = _copy.text(
          'This Moment has no audio to play.',
          'Ten Moment nie zawiera nagrania do odtworzenia.',
        ),
      );
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

    // The main recording takes the floor: any voice reply that is sounding
    // stops before this one starts.
    _arbiter.mainPlaybackStarted();

    final resuming = _everPlayed && _position.value > Duration.zero;
    setState(() {
      _isPlaying = true;
      _playbackBusy = !resuming;
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
        final uri = await moments.resolveMediaUri(momentId: _moment.id);
        if (!mounted || _missing) return;
        await player.play(UrlSource(uri.toString()));
      }
      if (mounted) setState(() => _playbackBusy = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _playbackBusy = false;
        _playbackError = _copy.text(
          'This Moment could not be played. Try again.',
          'Nie udało się odtworzyć tego Momentu. Spróbuj ponownie.',
        );
      });
    }
  }

  /// Pauses the main recording so a voice reply can be heard. A deliberate
  /// pause is never manufactured: this is a no-op unless audio is running.
  void _pauseForReply() {
    if (!_isPlaying) return;
    final player = _player;
    if (player != null) {
      unawaited(player.pause().catchError((Object _) {}));
    }
    if (mounted) setState(() => _isPlaying = false);
  }

  /// Seeks the MAIN player only, clamped to the recording — the ±15 s
  /// controls, the slider and the waveform all arrive here. A seek never
  /// starts playback, and seeking to the end lets completion fire the way
  /// it always does.
  Future<void> _seek(Duration target) async {
    final player = _player;
    if (player == null || !_everPlayed) return;
    final total = _totalDuration.inMilliseconds;
    final bounded = Duration(
      milliseconds: total > 0 ? target.inMilliseconds.clamp(0, total) : 0,
    );
    try {
      await player.seek(bounded);
      if (!mounted) return;
      _position.value = bounded;
      _publishProgress();
    } catch (_) {
      // Seeking an unloaded source is a no-op, not a fault.
    }
  }

  // ------------------------------------------------------------ neighbours

  /// The loaded, active, authorised neighbours this viewer may hand off to.
  List<VoiceMoment> _neighbourPool() {
    final explicit = widget.neighbours;
    final pool = explicit ??
        (_neighbourQueue.value.belongsTo(_uid)
            ? _neighbourQueue.value.moments
            : const <VoiceMoment>[]);
    if (pool.isEmpty) return const <VoiceMoment>[];
    final now = _effectiveNow();
    return pool
        .where((moment) => moment.id != _moment.id && moment.isActiveAt(now))
        .toList(growable: false);
  }

  /// What the hand-off list shows: the neighbours that come AFTER the open
  /// Moment in the pool the feed loaded, capped by the list itself.
  List<VoiceMoment> _upcomingNeighbours() {
    final explicit = widget.neighbours;
    final pool = explicit ??
        (_neighbourQueue.value.belongsTo(_uid)
            ? _neighbourQueue.value.moments
            : const <VoiceMoment>[]);
    if (pool.isEmpty) return const <VoiceMoment>[];
    final now = _effectiveNow();
    final index = pool.indexWhere((moment) => moment.id == _moment.id);
    final ordered = index >= 0
        ? <VoiceMoment>[...pool.skip(index + 1), ...pool.take(index)]
        : pool;
    return ordered
        .where((moment) => moment.id != _moment.id && moment.isActiveAt(now))
        .take(MomentsQueueList.maxItems)
        .toList(growable: false);
  }

  /// The hand-off itself: this surface owns exactly one player, so the
  /// recording is released BEFORE the next Moment opens, and the next
  /// Moment waits for a deliberate play. Nothing auto-advances.
  Future<void> _openNeighbour(VoiceMoment next) async {
    if (_openingNeighbour || next.id == _moment.id) return;
    _openingNeighbour = true;
    try {
      final player = _player;
      if (player != null) {
        try {
          await player.stop();
        } catch (_) {
          // Nothing was playing.
        }
      }
      if (!mounted) return;
      _arbiter.mainPlaybackStarted();
      _canonicalRefreshesInFlight.clear();
      _viewLoadGeneration += 1;
      _position.value = Duration.zero;
      _duration.value = null;
      _publishProgress();
      setState(() {
        _moment = next;
        _missing = false;
        _selfDeleted = false;
        _expiredByDeadline = !next.isActiveAt(_effectiveNow());
        _comments = null;
        _commentsTruncated = false;
        _nextCommentCursor = null;
        _commentsError = null;
        _reactions = null;
        _isPlaying = false;
        _everPlayed = false;
        _playbackBusy = false;
        _playbackError = null;
      });
      _rescheduleExpiry();
      unawaited(_loadView(trigger: _MomentDetailRefreshTrigger.initial));
    } finally {
      _openingNeighbour = false;
    }
  }

  // ------------------------------------------------------------- actions

  Future<void> _share() async {
    // The same real link mechanism every other Moment surface uses: the
    // website resolves ?moment= on yovoice.app.
    await SharePlus.instance.share(
      ShareParams(
        text: _copy.text(
          'Listen to ${_moment.authorName} on YO Voice: '
              'https://yovoice.app/?moment=${_moment.id}',
          'Posłuchaj ${_moment.authorName} w YO Voice: '
              'https://yovoice.app/?moment=${_moment.id}',
        ),
      ),
    );
  }

  Future<void> _report() async {
    final copy = _copy;
    await reportContent(
      context: context,
      service: widget.contentReportService,
      content: ReportedContent.voiceMoment(
        momentId: _moment.id,
        reportReceipt: _moment.reportReceipt,
      ),
      title: copy.text('Report this Voice Moment', 'Zgłoś ten Voice Moment'),
      subtitle: copy.text(
        'Your report goes to the YO Voice moderation team with this '
            'Moment attached. ${_moment.authorName} is not told who reported '
            'it.',
        'Zgłoszenie wraz z tym Momentem trafi do zespołu moderacji YO Voice. '
            '${_moment.authorName} nie dowie się, kto je wysłał.',
      ),
    );
  }

  Future<void> _reportComment(MomentComment comment) async {
    final copy = _copy;
    await reportContent(
      context: context,
      service: widget.contentReportService,
      content: ReportedContent.voiceMomentComment(
        momentId: _moment.id,
        commentId: comment.id,
        reportReceipt: comment.reportReceipt,
      ),
      title: copy.text('Report this comment', 'Zgłoś ten komentarz'),
      subtitle: copy.text(
        'Your report goes to the YO Voice moderation team with this '
            'comment attached. ${comment.authorName} is not told who '
            'reported it.',
        'Zgłoszenie wraz z komentarzem trafi do zespołu moderacji YO Voice. '
            '${comment.authorName} nie dowie się, kto je wysłał.',
      ),
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
        final copy = AppLocalizations.of(dialogContext);
        final palette = dialogContext.appPalette;
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          backgroundColor: palette.surfaceRaised,
          title: Text(
            copy.text('Delete this moment?', 'Usunąć ten Moment?'),
            style: TextStyle(color: palette.textPrimary),
          ),
          content: Text(
            copy.text(
              'This cannot be undone.',
              'Tej operacji nie można cofnąć.',
            ),
            style: TextStyle(color: palette.textSecondary),
          ),
          actions: [
            TextButton(
              key: const ValueKey('moment-detail-delete-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              key: const ValueKey('moment-detail-delete-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(copy.text('Delete', 'Usuń')),
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
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              _copy.text(
                'The Moment could not be deleted. Try again.',
                'Nie udało się usunąć Momentu. Spróbuj ponownie.',
              ),
            ),
          ),
        );
      return;
    }
    if (!mounted) return;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _copy.text('Voice Moment deleted.', 'Voice Moment usunięty.'),
          ),
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
      await _loadView(trigger: _MomentDetailRefreshTrigger.mutation);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _copy.text(
                'Could not post your comment. Try again.',
                'Nie udało się dodać komentarza. Spróbuj ponownie.',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// The voice reply. This opens the recorder; the MICROPHONE starts only
  /// inside it, on its own control. The main recording pauses first, so the
  /// viewer never records over what they are answering.
  Future<void> _replyWithVoice() async {
    _pauseForReply();
    _arbiter.mainPlaybackStarted();
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RecordVoiceMomentScreen(
          replyToMomentId: _moment.id,
          replyToAuthorName: _moment.authorName,
          momentService: _moments,
        ),
      ),
    );
    if (created != true || !mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _copy.text(
              'Voice reply published.',
              'Odpowiedź głosowa opublikowana.',
            ),
          ),
        ),
      );
    await _loadView(trigger: _MomentDetailRefreshTrigger.mutation);
  }

  /// "Reply" under a comment. The thread is flat on the server, so this
  /// prefills the composer with `@name ` instead of pretending a nested
  /// reply exists.
  void _prefillReply(MomentComment comment) {
    final mention = '@${comment.authorName} ';
    final current = _composer.text;
    if (!current.startsWith(mention)) {
      _composer.text = '$mention${current.trimLeft()}';
    }
    _composer.selection = TextSelection.collapsed(
      offset: _composer.text.length,
    );
    _composerFocus.requestFocus();
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final gone = _gone;

    return Scaffold(
      key: const ValueKey('moment-detail-screen'),
      backgroundColor: palette.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final layout = YoMomentsLayout.of(
              constraints.maxWidth,
              textScale: textScale,
            );
            // A phone held sideways has the width of a tablet and the height
            // of nothing: the hero then takes its side-by-side form so the
            // transport stays above the fold.
            final shortHeight = constraints.maxHeight < 560;
            final compact = layout.isNarrow;
            final threadPanel = layout.tier == YoMomentsLayoutTier.wide2 ||
                layout.tier == YoMomentsLayoutTier.wide3;
            final threadWidth = layout.slotWidth >= 1440 ? 400.0 : 360.0;

            final body = gone
                ? _goneCard()
                : _playerCard(compact: compact, shortHeight: shortHeight);

            if (!threadPanel) {
              return Column(
                children: [
                  _Header(
                    onBack: () => Navigator.of(context).maybePop(),
                    onShare: () => unawaited(_share()),
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: YoMomentsLayout.mainMaxWidth,
                        ),
                        child: ListView(
                          key: const ValueKey('moment-detail-scroll'),
                          padding: EdgeInsets.fromLTRB(
                            layout.gutter,
                            AppRhythm.hairline,
                            layout.gutter,
                            AppRhythm.section,
                          ),
                          children: [
                            body,
                            const SizedBox(height: AppRhythm.section),
                            _threadSection(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _composerBar(),
                ],
              );
            }

            return Column(
              children: [
                _Header(
                  onBack: () => Navigator.of(context).maybePop(),
                  onShare: () => unawaited(_share()),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (layout.tier == YoMomentsLayoutTier.wide3) ...[
                        SizedBox(
                          width: layout.localPanelWidth,
                          child: SingleChildScrollView(
                            padding: EdgeInsets.only(
                              left: layout.gutter,
                              bottom: AppRhythm.page,
                            ),
                            child: MomentsQueueList(
                              current: _moment,
                              upcoming: _upcomingNeighbours(),
                              progress: _progress,
                              onOpen: (moment) =>
                                  unawaited(_openNeighbour(moment)),
                            ),
                          ),
                        ),
                        SizedBox(width: layout.gutter),
                      ],
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: YoMomentsLayout.mainMaxWidth,
                            ),
                            child: ListView(
                              key: const ValueKey('moment-detail-scroll'),
                              padding: EdgeInsets.fromLTRB(
                                layout.gutter,
                                AppRhythm.hairline,
                                layout.gutter,
                                AppRhythm.page,
                              ),
                              children: [body],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: threadWidth,
                        child: _threadPanel(),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The player card of board 07 — hero, waveform, transport, actions.
  Widget _playerCard({required bool compact, required bool shortHeight}) {
    final palette = context.appPalette;
    return Container(
      key: const ValueKey('moment-detail-player-card'),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      padding: EdgeInsets.all(compact ? AppRhythm.title : AppRhythm.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hero(sideBySide: !compact || shortHeight),
          SizedBox(height: compact ? AppRhythm.title : AppRhythm.section),
          _waveform(compact: compact),
          const SizedBox(height: AppRhythm.tight),
          ValueListenableBuilder<Duration>(
            valueListenable: _position,
            builder: (context, position, _) => ValueListenableBuilder<Duration?>(
              valueListenable: _duration,
              builder: (context, duration, __) => MomentTransportControls(
                position: position,
                total: duration ?? Duration(seconds: _moment.durationSeconds),
                isPlaying: _isPlaying,
                busy: _playbackBusy,
                canSeek: _everPlayed,
                compact: compact,
                onTogglePlay: () => unawaited(_togglePlay()),
                onSeek: (target) => unawaited(_seek(target)),
              ),
            ),
          ),
          if (_playbackError != null) ...[
            const SizedBox(height: AppRhythm.tight),
            Text(
              _playbackError!,
              key: const ValueKey('moment-detail-playback-error'),
              style: AppTypography.bodySmall.copyWith(
                color: palette.dangerForeground,
              ),
            ),
          ],
          const SizedBox(height: AppRhythm.title),
          Divider(color: palette.border, height: 1),
          const SizedBox(height: AppRhythm.title),
          _actions(compact: compact),
          _reactionsSection(),
        ],
      ),
    );
  }

  /// Ring + avatar + eyebrow + caption + author. There is no cover: a Voice
  /// Moment has no cover field, no stored image and no grant for one, and
  /// the ring-and-waveform hero is the shipped design rather than a
  /// placeholder pretending an image is missing.
  Widget _hero({required bool sideBySide}) {
    final palette = context.appPalette;
    final copy = _copy;
    final caption = _moment.caption.trim();
    final ring = ValueListenableBuilder<double>(
      valueListenable: _progress,
      builder: (context, progress, _) => MomentListeningProgress(
        progress: progress,
        compact: !sideBySide,
        avatar: UserAvatar(
          radius: (sideBySide
                  ? MomentProgressRing.expandedAvatar
                  : MomentProgressRing.compactAvatar) /
              2,
          userId: _moment.authorId,
          photoUrl: _moment.authorPhotoUrl,
          displayName: _moment.authorName,
        ),
      ),
    );

    final text = Column(
      crossAxisAlignment: sideBySide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          copy.text('Voice Moment', 'Voice Moment').toUpperCase(),
          key: const ValueKey('moment-detail-eyebrow'),
          textAlign: sideBySide ? TextAlign.start : TextAlign.center,
          style: AppTypography.eyebrow.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: AppRhythm.tight),
        Text(
          caption.isEmpty ? copy.text('Voice Moment', 'Voice Moment') : caption,
          key: const ValueKey('moment-detail-caption'),
          textAlign: sideBySide ? TextAlign.start : TextAlign.center,
          style: (sideBySide
                  ? AppTypography.headlineLarge
                  : AppTypography.headlineMedium)
              .copyWith(color: palette.textPrimary),
        ),
        const SizedBox(height: AppRhythm.tight),
        _authorLine(centred: !sideBySide),
      ],
    );

    if (!sideBySide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [ring, const SizedBox(height: AppRhythm.title), text],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ring,
        const SizedBox(width: AppRhythm.section),
        Expanded(child: text),
      ],
    );
  }

  Widget _authorLine({required bool centred}) {
    final moment = _moment;
    final palette = context.appPalette;
    final copy = _copy;
    final age = momentRelativeAge(moment.createdAt, copy: copy);
    // The author sees the availability fact even for a permanent Moment
    // ("Stays until deleted"); everyone else only a real countdown.
    final availability = _isOwn
        ? momentAvailabilityLabel(moment.expiresAt, copy: copy)
        : momentExpiryLabel(moment.expiresAt, copy: copy);
    return Column(
      crossAxisAlignment: centred
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  moment.authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleMedium.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppRhythm.hairline),
              UserIdentityBadges(uid: moment.authorId),
            ],
          ),
        ),
        Wrap(
          spacing: AppRhythm.tight,
          alignment: centred ? WrapAlignment.center : WrapAlignment.start,
          children: [
            if (age.isNotEmpty)
              Text(
                age,
                style: AppTypography.bodySmall.copyWith(
                  color: palette.textTertiary,
                ),
              ),
            if (availability != null)
              Text(
                availability,
                key: const ValueKey('moment-detail-availability'),
                style: AppTypography.bodySmall.copyWith(
                  // A permanent Moment's label is a calm fact, not a
                  // warning-coloured countdown.
                  color: moment.isPermanent
                      ? palette.textTertiary
                      : palette.warningForeground,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// The silhouette, filled to the real position. Dragging across it seeks
  /// (the accessible seek is the slider below it, which carries the value
  /// and the keyboard steps).
  Widget _waveform({required bool compact}) {
    final palette = context.appPalette;
    return ValueListenableBuilder<double>(
      valueListenable: _progress,
      builder: (context, progress, _) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final total = _totalDuration.inMilliseconds;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: total > 0 && width > 0
                ? (details) {
                    final fraction = (details.localPosition.dx / width).clamp(
                      0.0,
                      1.0,
                    );
                    unawaited(
                      _seek(Duration(milliseconds: (total * fraction).round())),
                    );
                  }
                : null,
            child: ExcludeSemantics(
              child: StoryWaveform(
                progress: progress,
                height: compact ? 56 : 64,
                barWidth: 4,
                barGap: 4,
                barRadius: 2,
                playedGradient: palette.audioProgressGradient,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _actions({required bool compact}) {
    final chips = _engagementRow();
    final cta = _replyCta(compact: compact);
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          chips,
          const SizedBox(height: AppRhythm.item),
          SizedBox(height: AppSizing.primaryControlHeight, child: cta),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: chips),
        const SizedBox(width: AppRhythm.item),
        ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 200,
            minHeight: AppSizing.standardControlHeight,
          ),
          child: cta,
        ),
      ],
    );
  }

  Widget _replyCta({required bool compact}) => FilledButton.icon(
    key: const ValueKey('moment-detail-reply-voice'),
    onPressed: _gone ? null : () => unawaited(_replyWithVoice()),
    icon: const Icon(Icons.mic_rounded, size: 18),
    label: Text(
      _copy.text('Reply with voice', 'Odpowiedz głosem'),
      maxLines: 2,
      textAlign: TextAlign.center,
    ),
    style: FilledButton.styleFrom(
      minimumSize: Size(
        0,
        compact
            ? AppSizing.primaryControlHeight
            : AppSizing.standardControlHeight,
      ),
    ),
  );

  Widget _engagementRow() {
    final moment = _moment;
    final feed = _feed;
    final canReport = _uid.isNotEmpty && !_isOwn;
    final copy = _copy;
    return Wrap(
      spacing: AppRhythm.tight,
      runSpacing: AppRhythm.tight,
      children: [
        if (feed == null)
          _ActionChip(
            icon: Icons.favorite_border_rounded,
            label: moment.likeCount == 0
                ? copy.text('Like', 'Lubię to')
                : '${moment.likeCount}',
            active: false,
            onTap: null,
          )
        else
          _ActionChip(
            key: const ValueKey('moment-detail-like'),
            icon: moment.callerLiked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: moment.likeCount == 0
                ? copy.text('Like', 'Lubię to')
                : '${moment.likeCount}',
            active: moment.callerLiked,
            semanticLabel: moment.callerLiked
                ? copy.text(
                    'Unlike this Moment',
                    'Usuń polubienie tego Momentu',
                  )
                : copy.text('Like this Moment', 'Polub ten Moment'),
            onTap: _liking ? null : () => unawaited(_toggleLike(feed)),
          ),
        _ActionChip(
          key: const ValueKey('moment-detail-comments'),
          icon: Icons.mode_comment_outlined,
          label: moment.commentCount == 0
              ? copy.text('Comment', 'Komentarz')
              : '${moment.commentCount}',
          active: false,
          semanticLabel: copy.text('Write a comment', 'Napisz komentarz'),
          onTap: _composerFocus.requestFocus,
        ),
        _ActionChip(
          key: const ValueKey('moment-detail-share'),
          icon: Icons.share_outlined,
          label: copy.text('Share', 'Udostępnij'),
          active: false,
          semanticLabel: copy.text(
            'Share this Moment',
            'Udostępnij ten Moment',
          ),
          onTap: () => unawaited(_share()),
        ),
        if (canReport)
          _ActionChip(
            key: ValueKey('moment-detail-report-${moment.id}'),
            icon: Icons.flag_outlined,
            label: copy.text('Report', 'Zgłoś'),
            active: false,
            semanticLabel: copy.text(
              'Report this Voice Moment',
              'Zgłoś ten Voice Moment',
            ),
            onTap: () => unawaited(_report()),
          ),
        if (_isOwn)
          _ActionChip(
            key: ValueKey('moment-detail-delete-${moment.id}'),
            icon: Icons.delete_outline_rounded,
            label: copy.text('Delete', 'Usuń'),
            active: false,
            destructive: true,
            semanticLabel: copy.text(
              'Delete this Voice Moment',
              'Usuń ten Voice Moment',
            ),
            onTap: _deleting ? null : () => unawaited(_confirmDelete()),
          ),
      ],
    );
  }

  Future<void> _toggleLike(HomeFeedService feed) async {
    if (_liking) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final previous = _moment;
    final desiredLiked = !previous.callerLiked;
    setState(() {
      _liking = true;
      _moment = previous.copyWith(
        callerLiked: desiredLiked,
        likeCount: (previous.likeCount + (desiredLiked ? 1 : -1)).clamp(
          0,
          1 << 31,
        ),
      );
    });
    try {
      await feed.setLike(previous.id, liked: desiredLiked);
      if (!mounted || _moment.id != previous.id) return;
      setState(() => _liking = false);
      await _loadView(trigger: _MomentDetailRefreshTrigger.mutation);
    } catch (_) {
      if (mounted && _moment.id == previous.id) {
        setState(() {
          _moment = previous;
          _liking = false;
        });
      }
      messenger
        ?..hideCurrentSnackBar()
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

  /// The likers' avatar row from the server-owned v2 projection. Absent while
  /// loading, absent when nobody has liked, absent when no identity could be
  /// safely projected — never a spinner, never an invented face.
  Widget _reactionsSection() {
    final reactions = _reactions;
    final likeCount = _moment.likeCount;
    if (reactions == null || likeCount <= 0) return const SizedBox.shrink();
    final copy = _copy;
    return FutureBuilder<List<MomentReactor>>(
      future: reactions,
      builder: (context, snapshot) {
        final palette = context.appPalette;
        final reactors = snapshot.data ?? const <MomentReactor>[];
        if (reactors.isEmpty) return const SizedBox.shrink();
        final remainder = likeCount - reactors.length;
        return Padding(
          padding: const EdgeInsets.only(top: AppRhythm.title),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy.text('Top reactions', 'Najpopularniejsze reakcje'),
                style: AppTypography.titleSmall.copyWith(
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: AppRhythm.tight),
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
                          userId: reactor.uid,
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
                        borderRadius: AppRadius.pill,
                        color: palette.surfaceRaised,
                        border: Border.all(color: palette.border),
                      ),
                      child: Text(
                        '+$remainder',
                        maxLines: 1,
                        style: AppTypography.labelSmall.copyWith(
                          color: palette.textSecondary,
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

  /// The wide layout's docked "Rozmowa": its own scroll with the composer
  /// pinned under it.
  Widget _threadPanel() {
    final palette = context.appPalette;
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
              key: const ValueKey('moment-detail-thread-scroll'),
              padding: const EdgeInsets.fromLTRB(
                AppRhythm.section,
                AppRhythm.section,
                AppRhythm.section,
                AppRhythm.item,
              ),
              child: _threadSection(),
            ),
          ),
          _composerBar(),
        ],
      ),
    );
  }

  Widget _threadSection() {
    final service = _moments;
    final palette = context.appPalette;
    final copy = _copy;
    if (service == null) {
      return Text(
        copy.text(
          'Comments are unavailable right now.',
          'Komentarze są teraz niedostępne.',
        ),
        style: AppTypography.bodyMedium.copyWith(color: palette.textTertiary),
      );
    }
    if (_commentsError != null && _comments == null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey('moment-comments-retry'),
          onPressed: () =>
              unawaited(_loadView(trigger: _MomentDetailRefreshTrigger.retry)),
          icon: const Icon(Icons.refresh_rounded),
          label: Text(
            copy.text(
              'Could not load comments. Try again.',
              'Nie udało się wczytać komentarzy. Spróbuj ponownie.',
            ),
          ),
        ),
      );
    }
    if (_comments == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppRhythm.title),
        child: Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return MomentConversationThread(
      momentId: _moment.id,
      comments: _comments!,
      commentCount: _moment.commentCount,
      currentUserId: _uid,
      mentions: _readDirectory(),
      arbiter: _arbiter,
      resolveReplyMedia: (commentId) =>
          service.resolveMediaUri(momentId: _moment.id, commentId: commentId),
      onReplyTo: _gone ? null : _prefillReply,
      onReport: (comment) => unawaited(_reportComment(comment)),
      onLoadMore: _commentsTruncated
          ? () => unawaited(_loadMoreComments())
          : null,
      loadingMore: _loadingMore,
      onCompose: _gone ? null : _composerFocus.requestFocus,
      onOpenFullThread: () => unawaited(_openAllComments()),
      playerFactory: widget.playerFactory,
    );
  }

  /// The gone-state: expired, deleted, or never loaded. A real explanation
  /// and a way back — the thread stays readable underneath it (comments
  /// outlive the recording) and the composer states why it is closed.
  Widget _goneCard() {
    final palette = context.appPalette;
    final copy = _copy;
    return Container(
      key: const ValueKey('moment-detail-gone'),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.all(AppRhythm.section),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            copy.text('Voice Moment', 'Voice Moment').toUpperCase(),
            style: AppTypography.eyebrow.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AppRhythm.item),
          Icon(
            Icons.timer_off_outlined,
            size: 34,
            color: palette.textSecondary,
          ),
          const SizedBox(height: AppRhythm.item),
          Text(
            copy.text(
              'This Moment is no longer available',
              'Ten Moment nie jest już dostępny',
            ),
            textAlign: TextAlign.center,
            style: AppTypography.titleLarge.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppRhythm.tight),
          Text(
            copy.text(
              'It reached the end of its availability or was deleted by '
                  'its author.',
              'Minął czas jego dostępności lub autor go usunął.',
            ),
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: palette.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppRhythm.title),
          FilledButton(
            key: const ValueKey('moment-detail-gone-back'),
            focusNode: _goneBackFocus,
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(copy.text('Back to Moments', 'Wróć do Momentów')),
          ),
        ],
      ),
    );
  }

  Widget _composerBar() {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final copy = _copy;
    final closed = _gone;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      // The bar's surface stays full-bleed chrome, but its controls hold
      // the SAME 640 measure as the page body: a desktop composer that
      // stretched to 1440 put the send button a screen away from the
      // text, and the `@` picker inherited that stretch.
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: YoMomentsLayout.mainMaxWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (closed)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppRhythm.tight),
                  child: Text(
                    copy.text(
                      'You can no longer reply.',
                      'Nie można już odpowiadać.',
                    ),
                    key: const ValueKey('moment-detail-composer-closed'),
                    style: AppTypography.bodySmall.copyWith(
                      color: palette.textTertiary,
                    ),
                  ),
                ),
              // The `@` picker sits inside the composer column so it pushes
              // the field down rather than covering the thread.
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: MentionComposerField(
                      fieldKey: const ValueKey('moment-detail-comment-field'),
                      controller: _composer,
                      focusNode: _composerFocus,
                      directory: _composerMentionDirectory(),
                      hintText: copy.text(
                        'Write a comment...',
                        'Napisz komentarz…',
                      ),
                      enabled: _moments != null && !closed,
                      onSubmitted: (_) => unawaited(_send()),
                    ),
                  ),
                  const SizedBox(width: AppRhythm.tight),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: IconButton.filled(
                      key: const ValueKey('moment-detail-comment-send'),
                      tooltip: copy.text('Post comment', 'Dodaj komentarz'),
                      onPressed: _sending || _moments == null || closed
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
                  ),
                  const SizedBox(width: AppRhythm.tight),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: IconButton.filled(
                      key: const ValueKey('moment-detail-composer-mic'),
                      tooltip: copy.text(
                        'Reply with voice',
                        'Odpowiedz głosem',
                      ),
                      onPressed: closed
                          ? null
                          : () => unawaited(_replyWithVoice()),
                      style: IconButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        minimumSize: const Size.square(
                          AppSizing.standardControlHeight,
                        ),
                      ),
                      icon: const Icon(Icons.mic_rounded, size: 19),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Everyone an `@name` in this thread may resolve to for this viewer: the
  /// Moment's author, the thread's own participants, and the viewer's
  /// friends.
  MentionDirectory _readDirectory() => MentionDirectory(<MentionCandidate>[
    MentionCandidate(
      userId: _moment.authorId,
      displayName: _moment.authorName,
    ),
    for (final comment in _comments ?? const <MomentComment>[])
      if (comment.authorId.isNotEmpty && comment.authorName.trim().isNotEmpty)
        MentionCandidate(
          userId: comment.authorId,
          displayName: comment.authorName,
        ),
    ..._mentionFriends.candidates,
  ]);

  /// Who the composer may suggest: the caller's own friends only. The
  /// thread's participants resolve when a mention is *read* — suggesting
  /// a stranger who happened to comment is not the caller's list.
  MentionDirectory _composerMentionDirectory() =>
      MentionDirectory(_mentionFriends.candidates);
}

/// Back, the section name and Share — the page's own chrome, present in both
/// hosting modes (the shell keeps the bottom navigation, a plain push keeps
/// only this). The route is ONE Moment, so it is titled as one; it carries
/// no format switch, because a pushed detail cannot switch format.
class _Header extends StatelessWidget {
  const _Header({required this.onBack, required this.onShare});

  final VoidCallback onBack;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('moment-detail-back'),
            onPressed: onBack,
            tooltip: copy.text('Back', 'Wstecz'),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(AppSizing.standardControlHeight),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            icon: Icon(Icons.arrow_back_rounded, color: palette.textPrimary),
          ),
          const SizedBox(width: AppRhythm.hairline),
          Expanded(
            child: Text(
              copy.text('Voice Moment', 'Voice Moment'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleLarge.copyWith(
                color: palette.textPrimary,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('moment-detail-share-top'),
            onPressed: onShare,
            tooltip: copy.text('Share this Moment', 'Udostępnij ten Moment'),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(AppSizing.standardControlHeight),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            icon: Icon(Icons.share_outlined, color: palette.textPrimary),
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
        color: destructive ? palette.dangerSurface : palette.surfaceRaised,
        borderRadius: AppRadius.md,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.md,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSizing.standardControlHeight,
              minWidth: 64,
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppRhythm.item),
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
                    style: AppTypography.labelLarge.copyWith(
                      color: destructive ? colors.error : palette.textSecondary,
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
