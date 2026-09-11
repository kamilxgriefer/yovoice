import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
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
import 'package:yovoice/features/moments/presentation/widgets/moment_discover_tiles.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_sheet.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_viewer.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_time_labels.dart';
import 'package:yovoice/shared/widgets/identity/official_role_badge.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Which slice of the Moments corpus the feed is showing.
enum MomentsFilter {
  /// The current discovery pool, newest first. Engagement ordering remains
  /// an explicit filter, rather than a second copy of the same recordings.
  discover,

  /// Only the people this account follows (plus friends and itself) —
  /// the personal feed, fed by the existing [HomeFeedService] stream.
  following,

  /// The same pool in pure engagement order, most-engaged first.
  mostEngaged,

  /// The same pool ordered by `createdAt` descending, nothing else.
  recent,
}

/// One readable, lazy Voice Moments list with one shared audio transport.
/// Author chains, details and full comment threads remain explicit actions;
/// arriving on the feed never creates a player or starts audio.
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

class _MomentsFeedViewState extends State<MomentsFeedView>
    with WidgetsBindingObserver, RouteAware {
  late final MomentDiscoveryService _discovery;
  HomeFeedService? _feed;
  MomentService? _moments;
  MomentViewsService? _views;

  late MomentsFilter _filter = widget.initialFilter;

  _Phase _phase = _Phase.loading;
  Object? _error;
  MomentDiscoveryFeed? _result;
  bool _loadingMore = false;
  Object? _loadMoreError;

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

  FirebaseAuth? _auth;
  bool _authFailed = false;
  int _authSourceEpoch = 0;
  StreamSubscription<User?>? _authSubscription;
  String _viewerUid = '';
  int _accountEpoch = 0;
  int _loadEpoch = 0;
  int _socialEpoch = 0;
  ModalRoute<void>? _observedRoute;
  bool _routeIsCurrent = true;
  bool _foreground = true;
  late bool _wasVisible;
  bool _openingDestination = false;
  final _likeOverrides = <String, ({bool liked, int count})>{};
  final _pendingLikes = <String>{};
  // Immutable IDs deleted successfully by this account on this surface.
  // A read/page captured before its delete ACK may finish afterwards.
  final _confirmedDeletedIds = <String>{};

  // One source owns native audio. A superseded grant never enters this
  // transport queue; a superseded native attempt completes cleanup before
  // its successor may use the player.
  AudioPlayer? _player;
  Future<void> _transportTail = Future<void>.value();
  int _playEpoch = 0;
  String? _loadedId;
  Uri? _loadedUri;
  bool _playbackBusy = false;
  bool _transportBlocked = false;
  final _playback = ValueNotifier<_FeedPlayback>(const _FeedPlayback());
  final _cardContexts = <String, BuildContext>{};
  final List<StreamSubscription<dynamic>> _playerSubscriptions =
      <StreamSubscription<dynamic>>[];
  String? _playingId;
  VoiceMoment? _playingMoment;
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

  AppLocalizations get _copy => AppLocalizations.of(context);

  String get _uid {
    if (_authFailed) return '';
    try {
      return (_auth ?? widget.auth ?? FirebaseAuth.instance).currentUser?.uid ??
          '';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _wasVisible = _foreground && widget.isVisible?.value != false;
    _expiry = MomentExpiryScheduler(
      onDeadline: _expireAt,
      clock: widget.expiryClock,
      timerFactory: widget.expiryTimerFactory,
    );
    try {
      _auth = widget.auth ?? FirebaseAuth.instance;
    } catch (_) {
      _auth = null;
    }
    _viewerUid = _uid;
    _discovery = widget.discoveryService ?? MomentDiscoveryService();
    try {
      _feed = widget.feedService ?? HomeFeedService(auth: _auth);
    } catch (_) {
      _feed = null;
    }
    try {
      _moments = widget.momentService ?? MomentService(auth: _auth);
    } catch (_) {
      _moments = null;
    }
    try {
      _views = widget.viewsService ?? MomentViewsService(auth: _auth);
    } catch (_) {
      _views = null;
    }
    _subscribeAccountStreams();
    _bindAuth();
    widget.isVisible?.addListener(_handleVisibility);
    unawaited(_load());
  }

  bool _accountIsCurrent(int epoch, String uid) =>
      mounted && epoch == _accountEpoch && uid == _viewerUid && uid == _uid;

  void _bindAuth() {
    final source = ++_authSourceEpoch;
    unawaited(_authSubscription?.cancel());
    bool current() => mounted && source == _authSourceEpoch;
    _authSubscription = _auth?.authStateChanges().listen(
      (user) {
        if (current()) _handleAccount(user?.uid);
      },
      onError: (Object _) {
        if (current()) _handleAccount(null, failed: true);
      },
      onDone: () {
        if (current()) _handleAccount(null, failed: true);
      },
    );
  }

  void _handleAccount(
    String? observedUid, {
    bool failed = false,
    bool force = false,
  }) {
    final nextUid = observedUid ?? '';
    if (!mounted ||
        (!force && _viewerUid == nextUid && _authFailed == failed)) {
      return;
    }
    // Consume every auth event, including an already queued A -> null -> A.
    // Reading only currentUser here would collapse those into the final A.
    _authFailed = failed;
    _accountEpoch += 1;
    _loadEpoch += 1;
    _socialEpoch += 1;
    _viewerUid = nextUid;
    unawaited(_stopPanelPlayback(release: true));
    setState(() {
      _result = null;
      _phase = _Phase.loading;
      _error = null;
      _loadMoreError = null;
      _loadingMore = false;
      _socialData = null;
      _socialError = null;
      _mineData = const [];
      _viewedIds = const {};
      _engagement = const {};
      _likeOverrides.clear();
      _pendingLikes.clear();
      _confirmedDeletedIds.clear();
      _openingDestination = false;
    });
    _expiry.schedule(const []);
    _subscribeAccountStreams();
    unawaited(_load());
  }

  void _subscribeAccountStreams() {
    final epoch = _accountEpoch;
    final uid = _viewerUid;
    unawaited(_mineSubscription?.cancel());
    unawaited(_viewedSubscription?.cancel());
    unawaited(_engagementSubscription?.cancel());
    if (uid.isEmpty) {
      unawaited(_socialSubscription?.cancel());
      _socialData = null;
      _socialError = FirebaseAuthException(code: 'unauthenticated');
      return;
    }
    _subscribeSocial();
    try {
      _mineSubscription = _moments?.watchMyMoments().listen(
        (moments) {
          if (!_accountIsCurrent(epoch, uid)) return;
          final now = _expiry.now();
          _expireAt(now);
          if (!mounted) return;
          setState(() {
            final visible = moments
                .where((moment) => !_confirmedDeletedIds.contains(moment.id))
                .toList(growable: false);
            final surviving = visible.map((moment) => moment.id).toSet();
            final removed = _mineData
                .where((moment) => !surviving.contains(moment.id))
                .map((moment) => moment.id)
                .toSet();
            _mineData = visible;
            if (removed.isNotEmpty) _pruneFromPool(removed);
          });
          _expireAt(now);
          _stopIfProjectionChanged();
        },
        onError: (Object error) {
          if (!_accountIsCurrent(epoch, uid)) return;
          if (_voiceAccessWasDenied(error)) {
            final removed = _mineData.map((moment) => moment.id).toSet();
            setState(() {
              _mineData = const [];
              _pruneFromPool(removed);
            });
            unawaited(_stopPanelPlayback(release: true));
          }
        },
      );
    } catch (_) {
      _mineSubscription = null;
    }
    try {
      _viewedSubscription = _views?.watchViewedMomentIds().listen(
        (ids) {
          if (_accountIsCurrent(epoch, uid)) setState(() => _viewedIds = ids);
        },
        onError: (Object _) {
          if (_accountIsCurrent(epoch, uid)) {
            setState(() => _viewedIds = const {});
          }
        },
      );
    } catch (_) {
      _viewedSubscription = null;
    }
    try {
      _engagementSubscription = _discovery.watchEngagement().listen((counters) {
        if (_accountIsCurrent(epoch, uid)) {
          setState(() => _engagement = counters);
        }
      }, onError: (Object _) {});
    } catch (_) {
      _engagementSubscription = null;
    }
  }

  void _subscribeSocial() {
    final epoch = _accountEpoch;
    final uid = _viewerUid;
    final generation = ++_socialEpoch;
    unawaited(_socialSubscription?.cancel());
    if (uid.isEmpty) {
      _socialError = FirebaseAuthException(code: 'unauthenticated');
      return;
    }
    final feed = _feed;
    if (feed == null) {
      _socialError = StateError('unavailable');
      return;
    }
    _socialSubscription = feed.watchSocialMoments().listen(
      (moments) {
        if (!_accountIsCurrent(epoch, uid) || generation != _socialEpoch) {
          return;
        }
        final now = _expiry.now();
        _expireAt(now);
        setState(() {
          _socialData = moments
              .where((moment) => !_confirmedDeletedIds.contains(moment.id))
              .toList(growable: false);
          _socialError = null;
        });
        _expireAt(now);
        _stopIfProjectionChanged();
        if (_filter == MomentsFilter.following &&
            _playingId != null &&
            !_currentList().any((moment) => moment.id == _playingId)) {
          unawaited(_stopPanelPlayback(release: true));
        }
      },
      onError: (Object error) {
        if (!_accountIsCurrent(epoch, uid) || generation != _socialEpoch) {
          return;
        }
        setState(() {
          _socialData = null;
          _socialError = error;
        });
        if (_filter == MomentsFilter.following) {
          unawaited(_stopPanelPlayback(release: true));
          _announceReadError(error, 'social-$generation');
        }
      },
    );
  }

  void _retrySocial() {
    if (!mounted) return;
    setState(() {
      _socialError = null;
      // A normal refresh keeps keyed cards mounted until the replacement
      // arrives. Denial has already cleared the cache in onError; retaining
      // a valid snapshot here also preserves popup-return action ownership.
    });
    _subscribeSocial();
  }

  @override
  void didUpdateWidget(covariant MomentsFeedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible) {
      oldWidget.isVisible?.removeListener(_handleVisibility);
      widget.isVisible?.addListener(_handleVisibility);
    }
    if (oldWidget.auth != widget.auth) {
      try {
        _auth = widget.auth ?? FirebaseAuth.instance;
      } catch (_) {
        _auth = null;
      }
      _handleAccount(_auth?.currentUser?.uid, force: true);
      _bindAuth();
    }
    _handleVisibility();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (!identical(route, _observedRoute)) {
      appRouteObserver.unsubscribe(this);
      _observedRoute = route;
      if (route != null) appRouteObserver.subscribe(this, route);
    }
    _routeIsCurrent = route?.isCurrent ?? true;
    _handleVisibility();
  }

  @override
  void didPushNext() => _setRouteCurrent(false);
  @override
  void didPopNext() => _setRouteCurrent(true);
  @override
  void didPop() => _setRouteCurrent(false);

  void _setRouteCurrent(bool value) {
    _routeIsCurrent = value;
    _handleVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _handleVisibility();
  }

  void _handleVisibility() {
    if (!mounted) return;
    final visible =
        _foreground && _routeIsCurrent && widget.isVisible?.value != false;
    if (visible == _wasVisible) return;
    _wasVisible = visible;
    if (!visible) {
      unawaited(_stopPanelPlayback(release: true));
    } else {
      unawaited(_refreshAll());
    }
  }

  @override
  void dispose() {
    _authSourceEpoch += 1;
    _accountEpoch += 1;
    _loadEpoch += 1;
    _socialEpoch += 1;
    widget.isVisible?.removeListener(_handleVisibility);
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _expiry.dispose();
    unawaited(_authSubscription?.cancel());
    unawaited(_engagementSubscription?.cancel());
    unawaited(_viewedSubscription?.cancel());
    unawaited(_socialSubscription?.cancel());
    unawaited(_mineSubscription?.cancel());
    unawaited(_stopPanelPlayback(release: true, notify: false));
    _playback.dispose();
    _expiryRecoveryFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_loadEpoch;
    final account = _accountEpoch;
    final uid = _viewerUid;
    final hasContent = _result != null && _phase == _Phase.ready;
    setState(() {
      if (!hasContent) _phase = _Phase.loading;
      _error = null;
      _loadMoreError = null;
      _loadingMore = false;
    });
    unawaited(_stopPanelPlayback());
    try {
      if (uid.isEmpty) throw FirebaseAuthException(code: 'unauthenticated');
      final result = await _discovery.loadDiscoveryFeed();
      if (!_accountIsCurrent(account, uid) || generation != _loadEpoch) return;
      setState(() {
        _result = result;
        _pruneFromPool(_confirmedDeletedIds);
        _phase = _Phase.ready;
        _likeOverrides.removeWhere(
          (id, value) => result.moments.any(
            (moment) => moment.id == id && moment.callerLiked == value.liked,
          ),
        );
      });
      _expireAt(_expiry.now());
    } catch (error) {
      if (!_accountIsCurrent(account, uid) || generation != _loadEpoch) return;
      if (hasContent && !_voiceAccessWasDenied(error)) {
        setState(() => _loadMoreError = error);
      } else {
        setState(() {
          _result = null;
          _error = error;
          _phase = _Phase.error;
        });
      }
      _announceReadError(error, 'load-$generation');
    }
  }

  Future<void> _refreshAll() async {
    _retrySocial();
    await _load();
  }

  Future<void> _loadMore() async {
    final current = _result;
    final loadMore = current?.loadMore;
    if (current == null || loadMore == null || _loadingMore) return;
    final generation = _loadEpoch;
    final account = _accountEpoch;
    final uid = _viewerUid;
    bool currentRequest() =>
        _accountIsCurrent(account, uid) && generation == _loadEpoch;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final next = await loadMore();
      if (!currentRequest()) return;
      setState(() {
        _result = next;
        _pruneFromPool(_confirmedDeletedIds);
      });
      _expireAt(_expiry.now());
      _stopIfProjectionChanged();
    } catch (error) {
      if (!currentRequest()) return;
      if (_voiceAccessWasDenied(error)) {
        unawaited(_stopPanelPlayback(release: true));
        setState(() {
          _result = null;
          _error = error;
          _phase = _Phase.error;
        });
      } else {
        setState(() => _loadMoreError = error);
      }
      _announceReadError(error, 'page-$generation');
    } finally {
      if (currentRequest()) setState(() => _loadingMore = false);
    }
  }

  void _announceReadError(Object error, String transition) {
    if (widget.isVisible?.value == false) return;
    final account = _accountEpoch;
    final uid = _viewerUid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_accountIsCurrent(account, uid) || !_surfaceAllowsPlayback) return;
      final stillCurrent = transition.startsWith('social-')
          ? _filter == MomentsFilter.following && identical(_socialError, error)
          : _filter != MomentsFilter.following &&
                (identical(_error, error) || identical(_loadMoreError, error));
      if (!stillCurrent) return;
      _expiryAnnouncer.announce(
        context,
        transition: '$transition-$account',
        message: friendlyErrorMessage(error, copy: _copy),
        assertiveness: Assertiveness.assertive,
      );
    });
  }

  // ------------------------------------------------------------- playback

  bool get _surfaceAllowsPlayback =>
      mounted &&
      _foreground &&
      _routeIsCurrent &&
      widget.isVisible?.value != false &&
      momentExpirySurfaceIsVisible(context);

  VoiceMoment? _currentSnapshot(VoiceMoment moment, {bool allowDraft = false}) {
    if (_viewerUid.isEmpty || _viewerUid != _uid) return null;
    for (final current in _currentList()) {
      if (current.id != moment.id || current.authorId != moment.authorId) {
        continue;
      }
      if (current.isDeleted ||
          (!current.isActiveAt(_effectiveNow()) &&
              !(allowDraft &&
                  !current.isPublished &&
                  current.authorId == _uid))) {
        return null;
      }
      return _withLive(current);
    }
    return null;
  }

  bool _containsCurrentMoment(VoiceMoment moment, {bool allowDraft = false}) =>
      _currentSnapshot(moment, allowDraft: allowDraft) != null;

  bool _currentMediaMatches(VoiceMoment moment) {
    final current = _currentSnapshot(moment);
    return current != null &&
        current.hasMediaReference &&
        (!moment.hasAuthorizedMedia || current.hasAuthorizedMedia) &&
        current.mediaGeneration == moment.mediaGeneration &&
        current.audioUrl == moment.audioUrl;
  }

  void _stopIfProjectionChanged() {
    final moment = _playingMoment;
    if (moment != null && !_currentMediaMatches(moment)) {
      unawaited(_stopPanelPlayback(release: true));
    }
  }

  bool _playIsCurrent(
    VoiceMoment moment,
    int generation,
    int account,
    String uid,
  ) =>
      _accountIsCurrent(account, uid) &&
      generation == _playEpoch &&
      _playingId == moment.id &&
      _surfaceAllowsPlayback &&
      _currentMediaMatches(moment) &&
      _cardIsVisible(moment.id);

  bool _cardIsVisible(String id) {
    final cardContext = _cardContexts[id];
    if (cardContext == null || !cardContext.mounted) return false;
    final card = cardContext.findRenderObject();
    final scrollable = Scrollable.maybeOf(cardContext);
    final viewport = scrollable?.context.findRenderObject();
    if (card is! RenderBox ||
        viewport is! RenderBox ||
        !card.hasSize ||
        !viewport.hasSize ||
        !card.attached ||
        !viewport.attached) {
      return false;
    }
    return (card.localToGlobal(Offset.zero) & card.size).overlaps(
      viewport.localToGlobal(Offset.zero) & viewport.size,
    );
  }

  void _rememberCard(String id, BuildContext context) =>
      _cardContexts[id] = context;

  void _forgetCard(String id, BuildContext context) {
    if (identical(_cardContexts[id], context)) _cardContexts.remove(id);
    _checkVisiblePlaybackAfterFrame();
  }

  void _checkVisiblePlaybackAfterFrame() {
    final generation = _playEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _playEpoch || _playingId == null) return;
      if (!_cardIsVisible(_playingId!) || !_surfaceAllowsPlayback) {
        unawaited(_stopPanelPlayback(release: true));
      }
    });
  }

  void _publishPlayback() {
    if (!mounted) return;
    _playback.value = _FeedPlayback(
      id: _playingId,
      playing: _isPlaying,
      busy: _playbackBusy,
      elapsed: _position,
      duration: _duration,
      error: _playbackError,
    );
  }

  Future<void> _queueTransport(Future<void> Function() command) {
    final operation = _transportTail.then((_) => command());
    _transportTail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _interruptBeforeSwitch(AudioPlayer player) {
    // Stop invalidates the plugin's desired state immediately, but its native
    // effect can acknowledge later. Register that barrier NOW, not after a
    // grant, so even C cannot pass a pending A -> B interruption.
    final interrupted = () async {
      try {
        await player.stop();
        return true;
      } catch (_) {
        return false;
      }
    }();
    return _queueTransport(() async {
      if (!await interrupted) {
        _transportBlocked = true;
        throw StateError('native-stop-unconfirmed');
      }
    });
  }

  AudioPlayer _ensurePlayer() =>
      _player ??= (widget.playerFactory ?? AudioPlayer.new)();

  void _bindPlayer(
    AudioPlayer player,
    VoiceMoment moment,
    int generation,
    int account,
    String uid,
  ) {
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
    _playerSubscriptions.clear();
    bool current() =>
        identical(_player, player) &&
        _playIsCurrent(moment, generation, account, uid);
    _playerSubscriptions
      ..add(
        player.onPositionChanged.listen((position) {
          if (!current() || _playbackBusy) return;
          _position = position.isNegative ? Duration.zero : position;
          _publishPlayback();
        }),
      )
      ..add(
        player.onDurationChanged.listen((duration) {
          if (!current() || duration <= Duration.zero) return;
          _duration = duration;
          _publishPlayback();
        }),
      )
      ..add(
        player.onPlayerComplete.listen((_) {
          if (!current() || _playbackBusy) return;
          _isPlaying = false;
          _position = _duration ?? Duration(seconds: moment.durationSeconds);
          _publishPlayback();
        }),
      );
  }

  Future<void> _stopPanelPlayback({bool release = false, bool notify = true}) {
    _playEpoch += 1;
    _playingId = null;
    _playingMoment = null;
    _isPlaying = false;
    _playbackBusy = false;
    _position = Duration.zero;
    _duration = null;
    _playbackError = null;
    _loadedId = null;
    _loadedUri = null;
    if (notify) _publishPlayback();
    final player = _player;
    if (player == null) return _transportTail;
    // audioplayers invalidates desiredState synchronously in stop(). This
    // prevents its pending setSource from resuming after the surface left.
    final interrupted = player.stop().catchError((Object _) {});
    return _queueTransport(() async {
      try {
        await interrupted;
        // A previous queued release may already have disposed this instance.
        // Never dispose twice or touch a newer transport owner.
        if (!identical(_player, player)) return;
        try {
          await player.stop();
        } finally {
          if (release) {
            for (final subscription in _playerSubscriptions) {
              unawaited(subscription.cancel());
            }
            _playerSubscriptions.clear();
            await player.dispose();
            if (identical(_player, player)) _player = null;
          }
        }
      } catch (_) {
        // Set the fence inside the serialized command, before any queued
        // successor can observe a completed tail with an uncertain owner.
        _transportBlocked = true;
        rethrow;
      }
    }).catchError((Object _) {
      // Retain the old instance on uncertain cleanup: no new player is
      // allocated over an unresolved native owner.
      _transportBlocked = true;
    });
  }

  Future<void> _togglePanelPlay(VoiceMoment moment) async {
    final account = _accountEpoch;
    final uid = _viewerUid;
    if (!_surfaceAllowsPlayback ||
        !_containsCurrentMoment(moment) ||
        !_cardIsVisible(moment.id) ||
        _moments == null ||
        !moment.hasMediaReference) {
      return;
    }
    if (_transportBlocked) {
      final recovery = _stopPanelPlayback(release: true);
      // Our stop increments the generation synchronously. Retain that exact
      // intent across its native ACK; auth/visibility changes or a newer tap
      // must not let this retired handler adopt a fresh account or request.
      final recoveryGeneration = _playEpoch;
      await recovery;
      if (!_accountIsCurrent(account, uid) ||
          recoveryGeneration != _playEpoch ||
          !_surfaceAllowsPlayback ||
          !_currentMediaMatches(moment) ||
          !_cardIsVisible(moment.id) ||
          _player != null) {
        return;
      }
      _transportBlocked = false;
    }
    if (_playingId == moment.id && _playbackBusy) return;
    final generation = ++_playEpoch;
    final pause = _playingId == moment.id && _isPlaying;
    final total = _duration ?? Duration(seconds: moment.durationSeconds);
    final resuming =
        _loadedId == moment.id &&
        _position > Duration.zero &&
        (total <= Duration.zero || _position < total);
    final resumeAt = resuming ? _position : Duration.zero;
    _playingId = moment.id;
    _playingMoment = moment;
    _isPlaying = false;
    _playbackBusy = !pause;
    _playbackError = null;
    if (!resuming) {
      _position = Duration.zero;
      _duration = null;
    }
    _publishPlayback();
    bool current() => _playIsCurrent(moment, generation, account, uid);
    try {
      if (pause) {
        await _queueTransport(() async {
          if (!current()) return;
          final player = _player;
          if (player == null) return;
          try {
            await player.pause();
          } catch (_) {
            try {
              await player.stop();
            } catch (_) {
              _transportBlocked = true;
            }
            rethrow;
          }
          if (current()) _bindPlayer(player, moment, generation, account, uid);
        });
        return;
      }

      // Do not let the previous recording continue while the next grant waits.
      // Grants are outside the queue; a slow A cannot delay B's authorization.
      Future<void>? interrupted;
      if (_loadedId != moment.id) {
        final previous = _player;
        if (previous != null) {
          interrupted = _interruptBeforeSwitch(previous);
        }
      }
      final uri = await _moments!.resolveMediaUri(momentId: moment.id);
      if (!current()) return;
      await interrupted;
      if (!current()) return;
      await _queueTransport(() async {
        if (!current()) return;
        if (_transportBlocked) throw StateError('transport-cleanup-pending');
        final player = _ensurePlayer();
        _bindPlayer(player, moment, generation, account, uid);
        try {
          if (resuming && _loadedId == moment.id && _loadedUri == uri) {
            await player.resume();
          } else {
            await player.stop();
            if (!current()) return;
            await player.play(UrlSource(uri.toString()), position: resumeAt);
          }
          if (!current()) {
            await player.stop();
            return;
          }
          _loadedId = moment.id;
          _loadedUri = uri;
          _playbackBusy = false;
          _isPlaying = true;
          _publishPlayback();
          // A successful CURRENT transport command is the seam's start signal,
          // not a claim of physically audible audio on a device.
          if (!resuming) {
            unawaited(_views?.markViewed(moment.id).catchError((Object _) {}));
          }
        } catch (_) {
          // This cleanup runs inside the queue, before any successor's play.
          try {
            await player.stop();
          } catch (_) {
            _transportBlocked = true;
          }
          rethrow;
        }
      });
    } catch (_) {
      if (!mounted || !current()) return;
      _playbackBusy = false;
      _isPlaying = false;
      _playbackError = _copy.text(
        'This Moment could not be played. Try again.',
        'Nie udało się odtworzyć tego Momentu. Spróbuj ponownie.',
      );
      _publishPlayback();
      _expiryAnnouncer.announce(
        context,
        transition: 'play-$account-$generation',
        message: _playbackError!,
        assertiveness: Assertiveness.assertive,
      );
    }
  }

  Future<void> _seekPanel(VoiceMoment moment, Duration target) async {
    final generation = _playEpoch;
    final account = _accountEpoch;
    final uid = _viewerUid;
    if (_playbackBusy || _loadedId != moment.id) return;
    final total = _duration ?? Duration(seconds: moment.durationSeconds);
    final bounded = Duration(
      milliseconds: target.inMilliseconds.clamp(0, total.inMilliseconds),
    );
    try {
      await _queueTransport(() async {
        if (!_playIsCurrent(moment, generation, account, uid)) return;
        await _player?.seek(bounded);
        if (_playIsCurrent(moment, generation, account, uid)) {
          _position = bounded;
          _publishPlayback();
        }
      });
    } catch (_) {
      // A failed seek leaves the confirmed transport position intact.
    }
  }

  // ------------------------------------------------------------ interact

  VoiceMoment _withLive(VoiceMoment moment) {
    final live = _engagement[moment.id];
    final local = _likeOverrides[moment.id];
    return moment.copyWith(
      callerLiked: local?.liked,
      likeCount: local?.count ?? live?.likeCount,
      commentCount: live?.commentCount,
    );
  }

  Future<void> _toggleLike(VoiceMoment moment) async {
    final service = _feed;
    if (service == null ||
        !_containsCurrentMoment(moment) ||
        !_surfaceAllowsPlayback ||
        !_pendingLikes.add(moment.id)) {
      return;
    }
    final account = _accountEpoch;
    final uid = _viewerUid;
    final previous = _likeOverrides[moment.id];
    final liked = !moment.callerLiked;
    setState(
      () => _likeOverrides[moment.id] = (
        liked: liked,
        count: (moment.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 31),
      ),
    );
    try {
      await service.setLike(moment.id, liked: liked);
    } catch (_) {
      if (!mounted ||
          !_accountIsCurrent(account, uid) ||
          !_containsCurrentMoment(moment)) {
        return;
      }
      setState(() {
        if (previous == null) {
          _likeOverrides.remove(moment.id);
        } else {
          _likeOverrides[moment.id] = previous;
        }
      });
      if (_surfaceAllowsPlayback) {
        final message = _copy.text(
          'Your like could not be saved. Try again.',
          'Nie udało się zapisać polubienia. Spróbuj ponownie.',
        );
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(message)));
        _expiryAnnouncer.announce(
          context,
          transition: Object(),
          message: message,
          assertiveness: Assertiveness.assertive,
        );
      }
    } finally {
      if (_accountIsCurrent(account, uid)) {
        setState(() => _pendingLikes.remove(moment.id));
      }
    }
  }

  Future<void> _openDestination(
    VoiceMoment moment,
    Future<void> Function(VoiceMoment current) open,
  ) async {
    if (_openingDestination ||
        !_surfaceAllowsPlayback ||
        !_containsCurrentMoment(moment)) {
      return;
    }
    final account = _accountEpoch;
    final uid = _viewerUid;
    _openingDestination = true;
    try {
      await _stopPanelPlayback(release: true);
      if (!_accountIsCurrent(account, uid) ||
          !_containsCurrentMoment(moment) ||
          !_surfaceAllowsPlayback ||
          _player != null) {
        return;
      }
      final snapshot = _currentSnapshot(moment);
      if (snapshot == null) return;
      await open(snapshot);
    } finally {
      if (_accountIsCurrent(account, uid)) _openingDestination = false;
    }
  }

  /// Only a successful local delete (including the viewer's callback) is
  /// monotonic. Ordinary stream removal or denial must remain reversible.
  void _rememberConfirmedDeletion(VoiceMoment moment) {
    if (!mounted) return;
    setState(() {
      _confirmedDeletedIds.add(moment.id);
      _pruneFromPool({moment.id});
      _mineData = _mineData
          .where((mine) => mine.id != moment.id)
          .toList(growable: false);
      _socialData = _socialData
          ?.where((social) => social.id != moment.id)
          .toList(growable: false);
      _likeOverrides.remove(moment.id);
      _pendingLikes.remove(moment.id);
    });
    _scheduleExpiry();
  }

  Future<void> _openAuthorChain(VoiceMoment moment) async {
    final account = _accountEpoch;
    final uid = _viewerUid;
    VoiceMoment? requestedDetail;
    await _openDestination(moment, (current) async {
      final chains = _chainsFor(
        _currentList()
            .where((item) => item.isActiveAt(_effectiveNow()))
            .toList(),
      );
      final found = chains.where((chain) => chain.authorId == current.authorId);
      if (found.isEmpty) return;
      final chain = found.first;
      await showMomentStoryViewer(
        context,
        chain: chain,
        initialIndex: chain.firstUnviewedIndex(_viewedIds),
        feedService: _feed,
        momentService: _moments,
        viewsService: _views,
        contentReportService: widget.contentReportService,
        auth: widget.auth,
        // The viewer closes first. Wait for the enclosing navigation flight
        // to finish before handing the current projection to another route.
        onOpenDetail: (detail) => requestedDetail = detail,
        onDeleted: (deleted) {
          if (_accountIsCurrent(account, uid)) {
            _rememberConfirmedDeletion(deleted);
          }
        },
        playerFactory: widget.playerFactory,
        expiryClock: widget.expiryClock,
        expiryTimerFactory: widget.expiryTimerFactory,
      );
    });
    final detail = requestedDetail;
    if (detail != null && _accountIsCurrent(account, uid)) _openDetail(detail);
  }

  Future<void> _openSheet(VoiceMoment moment) => _openDestination(
    moment,
    (moment) => showMomentSheet(
      context,
      moment: moment,
      isOwn: moment.authorId == _uid,
      canReport: moment.authorId != _uid,
      feedService: _feed,
      momentService: _moments,
      contentReportService: widget.contentReportService,
      playerFactory: widget.playerFactory,
      expiryClock: widget.expiryClock,
      expiryTimerFactory: widget.expiryTimerFactory,
    ),
  );

  Future<void> _openComments(VoiceMoment moment) =>
      _openDestination(moment, (moment) async {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => MomentCommentsScreen(
              moment: moment,
              momentService: _moments,
              auth: widget.auth,
              contentReportService: widget.contentReportService,
              expiryClock: widget.expiryClock,
              expiryTimerFactory: widget.expiryTimerFactory,
            ),
          ),
        );
      });

  Future<void> _openProfile(VoiceMoment moment) => _openDestination(
    moment,
    (moment) => showProfilePreview(
      context,
      userId: moment.authorId,
      displayName: moment.authorName,
      photoUrl: moment.authorPhotoUrl,
    ),
  );

  Future<void> _report(VoiceMoment moment) => _openDestination(moment, (
    moment,
  ) async {
    if (moment.authorId == _uid) return;
    final copy = _copy;
    await reportContent(
      context: context,
      service: widget.contentReportService,
      content: ReportedContent.voiceMoment(
        momentId: moment.id,
        reportReceipt: moment.reportReceipt,
      ),
      title: copy.text('Report this Voice Moment', 'Zgłoś ten Voice Moment'),
      subtitle: copy.text(
        'Your report goes to the YO Voice moderation team with this '
            'Moment attached. ${moment.authorName} is not told who reported '
            'it.',
        'Zgłoszenie wraz z tym Momentem trafi do zespołu moderacji YO Voice. '
            '${moment.authorName} nie dowie się, kto je wysłał.',
      ),
    );
  });

  Future<void> _share(VoiceMoment moment) =>
      _openDestination(moment, (moment) => _shareVoiceMoment(moment, _copy));

  /// Removes [ids] from the one-shot discovery pool so a deleted Moment
  /// disappears immediately instead of surviving until the next reload.
  /// `fetchedCount` shrinks with it, so the empty-state copy stays honest
  /// when the last Moment goes.
  void _pruneFromPool(Set<String> ids) {
    final result = _result;
    if (result == null || ids.isEmpty) return;
    final removed = {
      for (final moment in result.moments)
        if (ids.contains(moment.id)) moment.id,
      for (final id in result.drops.keys)
        if (ids.contains(id)) id,
    };
    if (removed.isEmpty) return;
    final kept = result.moments
        .where((moment) => !ids.contains(moment.id))
        .toList(growable: false);
    _result = MomentDiscoveryFeed(
      moments: kept,
      fetchedCount: (result.fetchedCount - removed.length).clamp(
        0,
        result.fetchedCount,
      ),
      drops: {
        for (final entry in result.drops.entries)
          if (!ids.contains(entry.key)) entry.key: entry.value,
      },
      seed: result.seed,
      poolExhausted: result.poolExhausted,
      nextCursor: result.nextCursor,
      loadMore: result.loadMore,
    );
    if (_playingId != null && ids.contains(_playingId)) {
      unawaited(_stopPanelPlayback(release: true));
    }
  }

  /// Opens the full detail page for [moment]. The shell's route keeps the
  /// bottom navigation visible with Moments active; the fallback plain
  /// route carries its own Back control.
  void _openDetail(VoiceMoment moment) {
    unawaited(
      _openDestination(moment, (moment) async {
        final open = widget.onOpenDetail;
        if (open != null) {
          open(moment);
          return;
        }
        await Navigator.of(context).push<void>(
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
        );
      }),
    );
  }

  /// The author's exit — the ONLY exit a permanent Moment has. Destructive
  /// confirmation, the existing [MomentService.deleteMoment], immediate
  /// local removal on success, an honest error and an unchanged feed on
  /// failure.
  Future<void> _confirmDelete(VoiceMoment moment) async {
    final service = _moments;
    if (service == null ||
        !_surfaceAllowsPlayback ||
        !_containsCurrentMoment(moment, allowDraft: true) ||
        moment.authorId != _uid) {
      return;
    }
    final account = _accountEpoch;
    final uid = _viewerUid;
    await _stopPanelPlayback(release: true);
    if (!mounted || !_accountIsCurrent(account, uid)) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
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
              key: const ValueKey('moment-delete-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(copy.text('Cancel', 'Anuluj')),
            ),
            FilledButton(
              key: const ValueKey('moment-delete-confirm'),
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
    if (confirmed != true ||
        !_accountIsCurrent(account, uid) ||
        !_containsCurrentMoment(moment, allowDraft: true) ||
        moment.authorId != _uid) {
      return;
    }

    try {
      await service.deleteMoment(moment);
    } catch (_) {
      if (!_accountIsCurrent(account, uid)) return;
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
    if (!_accountIsCurrent(account, uid)) return;
    _rememberConfirmedDeletion(moment);
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
        unawaited(_stopPanelPlayback(release: true));
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
            nextCursor: result.nextCursor,
            loadMore: result.loadMore,
          );
        }
        _mineData = nextMine;
        if (social != null) _socialData = nextSocial;
        _likeOverrides.removeWhere((id, _) => removedIds.contains(id));
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
              ? _copy.text(
                  'One Voice Moment expired and was removed.',
                  'Jeden Voice Moment wygasł i został usunięty z listy.',
                )
              : _copy.text(
                  '$count Voice Moments expired and were removed.',
                  'Wygasłe Voice Momenty zostały usunięte z listy. '
                      'Liczba: $count.',
                ),
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
        .where(
          (moment) =>
              !_confirmedDeletedIds.contains(moment.id) &&
              moment.isActiveAt(now),
        )
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
      MomentsFilter.following => _followingList(now),
    };
  }

  List<VoiceMoment> _followingList(DateTime now) {
    final mine = _mineData
        .where(
          (moment) =>
              !_confirmedDeletedIds.contains(moment.id) &&
              moment.authorId == _uid &&
              (moment.isActiveAt(now) ||
                  (!moment.isPublished &&
                      !moment.isDeleted &&
                      moment.status != 'expired')),
        )
        .toList();
    final seen = mine.map((moment) => moment.id).toSet();
    return [
      ...mine,
      for (final moment in _socialData ?? const <VoiceMoment>[])
        if (!_confirmedDeletedIds.contains(moment.id) &&
            moment.authorId != _uid &&
            moment.isActiveAt(now) &&
            seen.add(moment.id))
          moment,
    ];
  }

  List<MomentChain> _chainsFor(List<VoiceMoment> moments) =>
      buildMomentChains(moments);

  void _setFilter(MomentsFilter filter) {
    if (filter == _filter) return;
    unawaited(_stopPanelPlayback());
    setState(() {
      _filter = filter;
    });
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = ResponsiveContentFrame.adaptivePagePadding(
          constraints.maxWidth,
        ).left;
        return YoPageBackground(
          section: YoPageSection.moments,
          key: const ValueKey('moments-feed-view'),
          child: ResponsiveContentFrame(
            width: ResponsiveContentWidth.list,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FilterChips(
                  filter: _filter,
                  onFilter: _setFilter,
                  onRefresh: _refreshAll,
                  side: side,
                  recoveryFocusNode: _expiryRecoveryFocus,
                ),
                Expanded(
                  child: _filter == MomentsFilter.following
                      ? _buildFollowing(side)
                      : _buildPool(side),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPool(double side) {
    switch (_phase) {
      case _Phase.loading:
        return const _LoadingState();
      case _Phase.error:
        return _ErrorState(error: _error, onRetry: _load);
      case _Phase.ready:
        break;
    }

    final result = _result!;
    // A filtered server page can be empty while its opaque cursor still has
    // work. Do not call that an empty corpus or strand its load-more action.
    if (result.moments.isEmpty && result.canLoadMore) {
      return _buildList(
        const [],
        side: side,
        footer: _PoolFooter(
          total: 0,
          moreExists: true,
          canLoadMore: true,
          loading: _loadingMore,
          hasError: _loadMoreError != null,
          error: _loadMoreError,
          onLoadMore: _loadMore,
        ),
      );
    }
    if (result.corpusIsEmpty) {
      return _EmptyState(
        icon: Icons.mic_none_rounded,
        title: _copy.text(
          'No Voice Moments yet',
          'Nie ma jeszcze Voice Momentów',
        ),
        body: _copy.text(
          'Nobody has published one. Be the first — record up to 60 '
              'seconds and choose how long it stays.',
          'Nikt jeszcze niczego nie opublikował. Nagraj maksymalnie 60 sekund '
              'i wybierz czas dostępności.',
        ),
        actionLabel: _copy.text('Record a Moment', 'Nagraj Moment'),
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
            ? _copy.text('Nothing live right now', 'Teraz nic nie jest aktywne')
            : _copy.text(
                'Nothing playable right now',
                'Teraz nie ma nic do odtworzenia',
              ),
        body: expiredOnly
            ? _copy.text(
                '${result.fetchedCount} published '
                '${result.fetchedCount == 1 ? 'Moment has' : 'Moments have'} '
                'reached the end of ${result.fetchedCount == 1 ? 'its' : 'their'} '
                'chosen availability. Record a new one to bring the feed '
                'back.',
                result.fetchedCount == 1
                    ? 'Opublikowany Moment zakończył okres dostępności. Nagraj '
                          'nowy, aby ponownie wypełnić kanał.'
                    : 'Okres dostępności zakończył się dla '
                          '${result.fetchedCount} opublikowanych Voice Momentów. '
                          'Nagraj nowy, aby ponownie wypełnić kanał.',
              )
            : _copy.text(
                '${result.fetchedCount} published '
                '${result.fetchedCount == 1 ? 'Moment' : 'Moments'} could '
                'not be played back. This is usually temporary.',
                result.fetchedCount == 1
                    ? 'Nie można teraz odtworzyć opublikowanego Momentu. To '
                          'zwykle problem przejściowy.'
                    : 'Nie można teraz odtworzyć ${result.fetchedCount} '
                          'opublikowanych Momentów. To zwykle problem przejściowy.',
              ),
        actionLabel: expiredOnly
            ? _copy.text('Record a Moment', 'Nagraj Moment')
            : _copy.text('Try again', 'Spróbuj ponownie'),
        onAction: expiredOnly ? widget.onRecord : _load,
      );
    }

    // Order first on the frozen list, THEN merge live counters for display
    // (ADR-095: numbers move, layout does not).
    final ordered = _currentList();
    final list = ordered.map(_withLive).toList(growable: false);
    return _buildList(
      list,
      side: side,
      footer: _PoolFooter(
        total: list.length,
        moreExists: result.poolExhausted,
        canLoadMore: result.canLoadMore,
        loading: _loadingMore,
        hasError: _loadMoreError != null,
        error: _loadMoreError,
        onLoadMore: _loadMoreError != null && !result.canLoadMore
            ? _load
            : _loadMore,
      ),
    );
  }

  Widget _buildFollowing(double side) {
    if (_socialError != null) {
      return _ErrorState(error: _socialError, onRetry: _retrySocial);
    }
    if (_socialData == null && _feed != null) return const _LoadingState();
    final list = _followingList(
      _effectiveNow(),
    ).map(_withLive).toList(growable: false);
    if (list.isEmpty) {
      return _EmptyState(
        key: const ValueKey('moments-following-empty'),
        icon: Icons.graphic_eq_rounded,
        title: _copy.text('Nothing here yet', 'Jeszcze nic tu nie ma'),
        body: _copy.text(
          'Moments from friends and people you follow show up '
              'here — and so do your own.',
          'Tutaj pojawią się Momenty znajomych, obserwowanych osób oraz Twoje.',
        ),
        actionLabel: _copy.text('Record a Moment', 'Nagraj Moment'),
        onAction: widget.onRecord,
      );
    }
    return _buildList(list, side: side);
  }

  Widget _buildList(
    List<VoiceMoment> list, {
    required double side,
    Widget? footer,
  }) {
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _checkVisiblePlaybackAfterFrame();
        return false;
      },
      child: _FeedColumn(
        key: ValueKey('voice-feed-account-$_accountEpoch'),
        moments: list,
        side: side,
        viewedIds: _viewedIds,
        currentUserId: _uid,
        playback: _playback,
        pendingLikes: _pendingLikes,
        canLike: _feed != null,
        footer: footer,
        onCardBuild: _rememberCard,
        onCardDispose: _forgetCard,
        onTapMoment: (moment) => unawaited(_openSheet(moment)),
        onPlayMoment: (moment) => unawaited(_togglePanelPlay(moment)),
        onSeek: (moment, target) => unawaited(_seekPanel(moment, target)),
        onLike: (moment) => unawaited(_toggleLike(moment)),
        onComments: (moment) => unawaited(_openComments(moment)),
        onOpenChain: (moment) => unawaited(_openAuthorChain(moment)),
        onOpenProfile: (moment) => unawaited(_openProfile(moment)),
        onOpenDetail: _openDetail,
        onShare: (moment) => unawaited(_share(moment)),
        onReport: (moment) => unawaited(_report(moment)),
        onDelete: (moment) => unawaited(_confirmDelete(moment)),
      ),
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
    required this.side,
    required this.recoveryFocusNode,
  });

  final MomentsFilter filter;
  final ValueChanged<MomentsFilter> onFilter;
  final VoidCallback onRefresh;
  final double side;
  final FocusNode recoveryFocusNode;

  static const _icons = <MomentsFilter, IconData>{
    MomentsFilter.discover: Icons.explore_outlined,
    MomentsFilter.following: Icons.people_outline_rounded,
    MomentsFilter.mostEngaged: Icons.trending_up_rounded,
    MomentsFilter.recent: Icons.schedule_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    String labelFor(MomentsFilter value) => switch (value) {
      MomentsFilter.discover => copy.text('Discover', 'Odkrywaj'),
      MomentsFilter.following => copy.text('Following', 'Obserwowani'),
      MomentsFilter.mostEngaged => copy.text(
        'Most engaged',
        'Najpopularniejsze',
      ),
      MomentsFilter.recent => copy.text('Recent', 'Najnowsze'),
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(side, AppRhythm.tight, side, AppRhythm.item),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in _icons.entries) ...[
                    if (entry.key != MomentsFilter.discover)
                      const SizedBox(width: 8),
                    _FilterChip(
                      key: ValueKey('moments-filter-${entry.key.name}'),
                      label: labelFor(entry.key),
                      icon: entry.value,
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
            tooltip: copy.text('Reload Moments', 'Odśwież Momenty'),
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
      selected: selected,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(
            selected ? colors.primary : palette.surfaceMuted,
          ),
          foregroundColor: WidgetStatePropertyAll(
            selected ? colors.onPrimary : palette.textSecondary,
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppRhythm.title),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.pill),
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              width: 3,
              color: states.contains(WidgetState.focused)
                  ? (selected ? colors.onPrimary : palette.focus)
                  : Colors.transparent,
            ),
          ),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

/// Only mounted cards listen to the shared transport. Playback ticks never
/// reorder the feed or recreate an audio player for an offscreen item.
class _FeedPlayback {
  const _FeedPlayback({
    this.id,
    this.playing = false,
    this.busy = false,
    this.elapsed = Duration.zero,
    this.duration,
    this.error,
  });

  final String? id;
  final bool playing;
  final bool busy;
  final Duration elapsed;
  final Duration? duration;
  final String? error;
}

class _FeedColumn extends StatelessWidget {
  const _FeedColumn({
    required this.moments,
    required this.side,
    required this.viewedIds,
    required this.currentUserId,
    required this.playback,
    required this.pendingLikes,
    required this.canLike,
    required this.onCardBuild,
    required this.onCardDispose,
    required this.onTapMoment,
    required this.onPlayMoment,
    required this.onSeek,
    required this.onLike,
    required this.onComments,
    required this.onOpenChain,
    required this.onOpenProfile,
    required this.onOpenDetail,
    required this.onShare,
    required this.onReport,
    required this.onDelete,
    this.footer,
    super.key,
  });

  final List<VoiceMoment> moments;
  final double side;
  final Set<String> viewedIds;
  final String currentUserId;
  final ValueListenable<_FeedPlayback> playback;
  final Set<String> pendingLikes;
  final bool canLike;
  final Widget? footer;
  final void Function(String, BuildContext) onCardBuild;
  final void Function(String, BuildContext) onCardDispose;
  final ValueChanged<VoiceMoment> onTapMoment;
  final ValueChanged<VoiceMoment> onPlayMoment;
  final void Function(VoiceMoment, Duration) onSeek;
  final ValueChanged<VoiceMoment> onLike;
  final ValueChanged<VoiceMoment> onComments;
  final ValueChanged<VoiceMoment> onOpenChain;
  final ValueChanged<VoiceMoment> onOpenProfile;
  final ValueChanged<VoiceMoment> onOpenDetail;
  final ValueChanged<VoiceMoment> onShare;
  final ValueChanged<VoiceMoment> onReport;
  final ValueChanged<VoiceMoment> onDelete;

  @override
  Widget build(BuildContext context) {
    final indices = <Key, int>{
      for (var index = 0; index < moments.length; index++)
        ValueKey('moment-row-${moments[index].id}'): index,
    };
    return ListView.builder(
      key: const ValueKey('moments-feed-scroll'),
      padding: EdgeInsets.fromLTRB(side, AppRhythm.tight, side, AppRhythm.page),
      itemCount: moments.length + (footer == null ? 0 : 1),
      findChildIndexCallback: (key) => indices[key],
      itemBuilder: (context, index) {
        if (index == moments.length) {
          return Padding(
            padding: const EdgeInsets.only(top: AppRhythm.title),
            child: footer,
          );
        }
        final moment = moments[index];
        return _MomentFeedCard(
          key: ValueKey('moment-row-${moment.id}'),
          moment: moment,
          seen: viewedIds.contains(moment.id),
          isOwn: currentUserId.isNotEmpty && moment.authorId == currentUserId,
          canInteract: currentUserId.isNotEmpty,
          canLike: canLike,
          likePending: pendingLikes.contains(moment.id),
          playback: playback,
          onCardBuild: onCardBuild,
          onCardDispose: onCardDispose,
          onTap: () => onTapMoment(moment),
          onPlay: () => onPlayMoment(moment),
          onSeek: (position) => onSeek(moment, position),
          onLike: () => onLike(moment),
          onComments: () => onComments(moment),
          onOpenChain: () => onOpenChain(moment),
          onOpenProfile: () => onOpenProfile(moment),
          onOpenDetail: () => onOpenDetail(moment),
          onShare: () => onShare(moment),
          onReport: () => onReport(moment),
          onDelete: () => onDelete(moment),
        );
      },
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
    final copy = AppLocalizations.of(context);
    return SizedBox(
      height: MomentStoryTile.heightFor(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chains.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final chain = chains[index];
          final seen = !chain.hasUnviewed(viewedIds);
          return MomentStoryTile(
            key: ValueKey('moments-chain-${chain.authorId}'),
            name: chain.authorName,
            seen: seen,
            count: chain.length,
            userId: chain.authorId,
            photoUrl: chain.authorPhotoUrl,
            displayName: chain.authorName,
            semanticLabel: chain.length > 1
                ? copy.template(
                    'Open the story chain by {name}, {count} Moments',
                    'Otwórz relację użytkownika {name}, Momenty: {count}',
                    values: {'name': chain.authorName, 'count': chain.length},
                  )
                : copy.template(
                    'Open the story chain by {name}',
                    'Otwórz relację użytkownika {name}',
                    values: {'name': chain.authorName},
                  ),
            onTap: () => onOpenChain(chain),
          );
        },
      ),
    );
  }
}

/// One complete, readable recording. The progress track is transport data;
/// this model has no recorded waveform, so the card does not invent one.
class _MomentFeedCard extends StatefulWidget {
  const _MomentFeedCard({
    required this.moment,
    required this.seen,
    required this.isOwn,
    required this.canInteract,
    required this.canLike,
    required this.likePending,
    required this.playback,
    required this.onCardBuild,
    required this.onCardDispose,
    required this.onTap,
    required this.onPlay,
    required this.onSeek,
    required this.onLike,
    required this.onComments,
    required this.onOpenChain,
    required this.onOpenProfile,
    required this.onOpenDetail,
    required this.onShare,
    required this.onReport,
    required this.onDelete,
    super.key,
  });

  final VoiceMoment moment;
  final bool seen;
  final bool isOwn;
  final bool canInteract;
  final bool canLike;
  final bool likePending;
  final ValueListenable<_FeedPlayback> playback;
  final void Function(String, BuildContext) onCardBuild;
  final void Function(String, BuildContext) onCardDispose;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onLike;
  final VoidCallback onComments;
  final VoidCallback onOpenChain;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenDetail;
  final VoidCallback onShare;
  final VoidCallback onReport;
  final VoidCallback onDelete;

  @override
  State<_MomentFeedCard> createState() => _MomentFeedCardState();
}

class _MomentFeedCardState extends State<_MomentFeedCard> {
  void _afterMenu(VoidCallback action) {
    // PopupMenu returns its selection before the route's inherited current
    // state has rebuilt. Dispatch after that frame, retaining all destination
    // guards. The account-keyed list disposes this card on every auth epoch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  @override
  void dispose() {
    widget.onCardDispose(widget.moment.id, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moment = widget.moment;
    widget.onCardBuild(moment.id, context);
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final uploading = !moment.isPublished;
    final enabled = widget.canInteract && !uploading;
    final availability = uploading
        ? copy.text('Uploading…', 'Przesyłanie…')
        : widget.isOwn
        ? momentAvailabilityLabel(moment.expiresAt, copy: copy)
        : momentExpiryLabel(moment.expiresAt, copy: copy);
    final age = momentRelativeAge(moment.createdAt, copy: copy);
    final caption = moment.caption.trim().isEmpty
        ? copy.text('Voice Moment', 'Voice Moment')
        : moment.caption;

    Widget avatar() => AccessibleTapRegion(
      key: ValueKey('moment-row-chain-${moment.id}'),
      circular: true,
      onTap: enabled ? widget.onOpenChain : null,
      semanticLabel:
          '${copy.template('Open the story chain by {name}', 'Otwórz relację użytkownika {name}', values: {'name': moment.authorName})}, ${MomentSeenAvatar.stateLabel(context, seen: widget.seen)}',
      child: MomentSeenAvatar(
        seen: widget.seen,
        diameter: 48,
        userId: moment.authorId,
        photoUrl: moment.authorPhotoUrl,
        displayName: moment.authorName,
      ),
    );

    Widget identity() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AccessibleTapRegion(
          key: ValueKey('moment-row-author-${moment.id}'),
          onTap: enabled ? widget.onOpenProfile : null,
          semanticLabel: moment.authorName,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  moment.authorName,
                  style: AppTypography.titleMedium.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppRhythm.hairline),
              UserIdentityBadges(
                uid: moment.authorId,
                variant: IdentityBadgeVariant.icon,
              ),
            ],
          ),
        ),
        if (age.isNotEmpty && !uploading)
          Text(
            age,
            style: AppTypography.bodySmall.copyWith(
              color: palette.textSecondary,
            ),
          ),
      ],
    );

    Widget menu() => MomentOverflowMenu(
      moment: moment,
      isOwn: widget.isOwn,
      uploading: uploading,
      keyPrefix: 'moment-row',
      onOpenDetail: () => _afterMenu(widget.onOpenDetail),
      onReport: () => _afterMenu(widget.onReport),
      onDelete: () => _afterMenu(widget.onDelete),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppRhythm.item),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Material(
          color: palette.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.lg,
            side: BorderSide(color: palette.border),
          ),
          child: InkWell(
            onTap: widget.canInteract ? widget.onTap : null,
            borderRadius: AppRadius.lg,
            child: Padding(
              padding: const EdgeInsets.all(AppRhythm.title),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final scale =
                          MediaQuery.textScalerOf(context).scale(16) / 16;
                      if (constraints.maxWidth < 240 * scale) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [avatar(), const Spacer(), menu()]),
                            const SizedBox(height: AppRhythm.tight),
                            identity(),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          avatar(),
                          const SizedBox(width: AppRhythm.item),
                          Expanded(child: identity()),
                          menu(),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppRhythm.tight),
                  AccessibleTapRegion(
                    key: ValueKey('moment-row-title-${moment.id}'),
                    onTap: enabled ? widget.onOpenDetail : null,
                    semanticLabel: copy.template(
                      'Open details of the Moment by {name}',
                      'Otwórz szczegóły Momentu użytkownika {name}',
                      values: {'name': moment.authorName},
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        caption,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyLarge.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  if (availability != null) ...[
                    const SizedBox(height: AppRhythm.tight),
                    Text(
                      availability,
                      style: AppTypography.bodySmall.copyWith(
                        color: moment.isPermanent || uploading
                            ? palette.textSecondary
                            : palette.warningForeground,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppRhythm.item),
                  ValueListenableBuilder<_FeedPlayback>(
                    valueListenable: widget.playback,
                    builder: (context, playback, _) {
                      final active = playback.id == moment.id;
                      return _VoiceMomentTransport(
                        moment: moment,
                        state: active ? playback : const _FeedPlayback(),
                        active: active,
                        enabled: enabled && moment.hasMediaReference,
                        onPlay: widget.onPlay,
                        onSeek: widget.onSeek,
                      );
                    },
                  ),
                  const SizedBox(height: AppRhythm.tight),
                  Wrap(
                    spacing: AppRhythm.tight,
                    runSpacing: AppRhythm.hairline,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        key: ValueKey('moment-row-like-${moment.id}'),
                        onPressed:
                            enabled && widget.canLike && !widget.likePending
                            ? widget.onLike
                            : null,
                        style: TextButton.styleFrom(
                          foregroundColor: moment.callerLiked
                              ? palette.interactiveForeground
                              : palette.textSecondary,
                        ),
                        icon: Icon(
                          moment.callerLiked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 20,
                        ),
                        label: Text(
                          moment.likeCount > 0
                              ? copy.template(
                                  'Likes: {count}',
                                  'Polubienia: {count}',
                                  values: {'count': moment.likeCount},
                                )
                              : copy.text('Like', 'Lubię to'),
                        ),
                      ),
                      TextButton.icon(
                        key: ValueKey('moment-row-comments-${moment.id}'),
                        onPressed: enabled ? widget.onComments : null,
                        style: TextButton.styleFrom(
                          foregroundColor: palette.textSecondary,
                        ),
                        icon: const Icon(Icons.mode_comment_outlined, size: 20),
                        label: Text(
                          moment.commentCount > 0
                              ? copy.template(
                                  'Comments: {count}',
                                  'Komentarze: {count}',
                                  values: {'count': moment.commentCount},
                                )
                              : copy.text('Comments', 'Komentarze'),
                        ),
                      ),
                      TextButton.icon(
                        key: ValueKey('moment-row-share-${moment.id}'),
                        onPressed: enabled ? widget.onShare : null,
                        style: TextButton.styleFrom(
                          foregroundColor: palette.textSecondary,
                        ),
                        icon: const Icon(Icons.ios_share_rounded, size: 20),
                        label: Text(copy.text('Share', 'Udostępnij')),
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

class _VoiceMomentTransport extends StatelessWidget {
  const _VoiceMomentTransport({
    required this.moment,
    required this.state,
    required this.active,
    required this.enabled,
    required this.onPlay,
    required this.onSeek,
  });

  final VoiceMoment moment;
  final _FeedPlayback state;
  final bool active;
  final bool enabled;
  final VoidCallback onPlay;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final total = state.duration ?? Duration(seconds: moment.durationSeconds);
    final maxMs = total.inMilliseconds;
    final position = state.elapsed.inMilliseconds.clamp(
      0,
      maxMs > 0 ? maxMs : 0,
    );
    final label = state.playing
        ? copy.text('Pause', 'Pauza')
        : copy.text('Play', 'Odtwórz');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton.filled(
              key: ValueKey('moment-row-play-${moment.id}'),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.disabled)
                      ? palette.surfaceMuted
                      : Theme.of(context).colorScheme.primary,
                ),
                foregroundColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.onPrimary,
                ),
                side: WidgetStateProperty.resolveWith(
                  (states) => BorderSide(
                    width: 3,
                    color: states.contains(WidgetState.focused)
                        ? Theme.of(context).colorScheme.onPrimary
                        : Colors.transparent,
                  ),
                ),
              ),
              onPressed: enabled && !state.busy ? onPlay : null,
              tooltip: label,
              icon: state.busy
                  ? SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.interactiveForeground,
                      ),
                    )
                  : Icon(
                      state.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
            ),
            const SizedBox(width: AppRhythm.tight),
            Expanded(
              child: Semantics(
                label: copy.text('Voice Moment', 'Voice Moment'),
                child: Slider(
                  key: ValueKey('moment-row-progress-${moment.id}'),
                  value: position.toDouble(),
                  max: maxMs > 0 ? maxMs.toDouble() : 1,
                  onChanged:
                      enabled &&
                          active &&
                          !state.busy &&
                          state.error == null &&
                          maxMs > 0
                      ? (value) => onSeek(Duration(milliseconds: value.round()))
                      : null,
                  semanticFormatterCallback: (value) => _clock(value ~/ 1000),
                ),
              ),
            ),
          ],
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            active
                ? '${_clock(position ~/ 1000)} / ${_clock(total.inSeconds)}'
                : _clock(total.inSeconds),
            style: AppTypography.bodySmall.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ),
        if (state.error != null) ...[
          const SizedBox(height: AppRhythm.tight),
          Text(
            state.error!,
            style: AppTypography.bodyMedium.copyWith(
              color: palette.dangerForeground,
            ),
          ),
          TextButton.icon(
            key: ValueKey('moment-row-play-retry-${moment.id}'),
            onPressed: enabled && !state.busy ? onPlay : null,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(copy.text('Try again', 'Spróbuj ponownie')),
          ),
        ],
      ],
    );
  }
}

/// What the feed actually holds, counted rather than estimated. Build 20 uses
/// the server's opaque cursor; the UI never invents a next page or decodes the
/// privacy boundary.
class _PoolFooter extends StatelessWidget {
  const _PoolFooter({
    required this.total,
    required this.moreExists,
    required this.canLoadMore,
    required this.loading,
    required this.hasError,
    required this.onLoadMore,
    this.error,
  });

  final int total;
  final bool moreExists;
  final bool canLoadMore;
  final bool loading;
  final bool hasError;
  final Object? error;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final summary = moreExists
        ? (total == 1
              ? copy.template(
                  '{count} live Moment loaded.',
                  'Wczytano aktywne Momenty: {count}.',
                  values: {'count': total},
                )
              : copy.template(
                  '{count} live Moments loaded.',
                  'Wczytano aktywne Momenty: {count}.',
                  values: {'count': total},
                ))
        : total == 1
        ? copy.text(
            'That is the only live Moment right now.',
            'To jedyny aktywny Moment w tej chwili.',
          )
        : copy.template(
            'That is all {count} live Moments right now.',
            'To wszystkie aktywne Momenty w tej chwili: {count}.',
            values: {'count': total},
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          summary,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.textTertiary,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        if (hasError && error != null) ...[
          const SizedBox(height: AppRhythm.tight),
          Text(
            friendlyErrorMessage(error!, copy: copy),
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: palette.dangerForeground,
            ),
          ),
        ],
        if (canLoadMore || loading || hasError) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('moments-load-more'),
            onPressed: loading ? null : onLoadMore,
            icon: loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    hasError ? Icons.refresh_rounded : Icons.expand_more,
                    size: 18,
                  ),
            label: Text(
              hasError
                  ? copy.text('Try again', 'Spróbuj ponownie')
                  : copy.text('Load more', 'Wczytaj więcej'),
            ),
          ),
        ],
      ],
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
  final GlobalKey<MomentCommentsInlineState> _commentsKey =
      GlobalKey<MomentCommentsInlineState>();
  bool _sending = false;

  AppLocalizations get _copy => AppLocalizations.of(context);

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
      _commentsKey.currentState?.refresh();
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

  Future<void> _share() => _shareVoiceMoment(widget.moment, _copy);
  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    final moment = widget.moment;
    final copy = _copy;
    final age = momentRelativeAge(moment.createdAt, copy: copy);
    // The author sees the availability fact even for a permanent Moment
    // ("Stays until deleted"); everyone else only sees a real countdown.
    final expiry = widget.isOwn
        ? momentAvailabilityLabel(moment.expiresAt, copy: copy)
        : momentExpiryLabel(moment.expiresAt, copy: copy);
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
                          radius: 22,
                          userId: moment.authorId,
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
                                          : palette.warningForeground,
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
                            ? copy.text(
                                'Pause this Moment',
                                'Wstrzymaj ten Moment',
                              )
                            : copy.text(
                                'Play this Moment',
                                'Odtwórz ten Moment',
                              ),
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
                          copy.text('Comments', 'Komentarze'),
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
                          child: Text(
                            copy.text('Open thread', 'Otwórz wątek'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                  MomentCommentsInline(
                    key: _commentsKey,
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
                      hintText: copy.text(
                        'Write a comment...',
                        'Napisz komentarz…',
                      ),
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
                  tooltip: copy.text('Post comment', 'Dodaj komentarz'),
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

class _DetailActions extends StatefulWidget {
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
  State<_DetailActions> createState() => _DetailActionsState();
}

class _DetailActionsState extends State<_DetailActions> {
  late bool _liked = widget.moment.callerLiked;
  late int _likeCount = widget.moment.likeCount;
  bool _pending = false;
  bool _hasLocalOverride = false;

  @override
  void didUpdateWidget(covariant _DetailActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moment.id != widget.moment.id) {
      _liked = widget.moment.callerLiked;
      _likeCount = widget.moment.likeCount;
      _pending = false;
      _hasLocalOverride = false;
    } else if (!_pending &&
        (!_hasLocalOverride || widget.moment.callerLiked == _liked)) {
      _liked = widget.moment.callerLiked;
      _likeCount = widget.moment.likeCount;
      _hasLocalOverride = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.feedService;
    final copy = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (service == null)
          _SmallChip(
            icon: Icons.favorite_border_rounded,
            label: _likeCount == 0
                ? copy.text('Like', 'Lubię to')
                : '$_likeCount',
            active: false,
            onTap: null,
          )
        else
          _SmallChip(
            key: const ValueKey('detail-like'),
            icon: _liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: _likeCount == 0
                ? copy.text('Like', 'Lubię to')
                : '$_likeCount',
            active: _liked,
            semanticLabel: _liked
                ? copy.text(
                    'Unlike this Moment',
                    'Usuń polubienie tego Momentu',
                  )
                : copy.text('Like this Moment', 'Polub ten Moment'),
            onTap: _pending ? null : () => unawaited(_toggle(service)),
          ),
        _SmallChip(
          key: const ValueKey('detail-share'),
          icon: Icons.share_outlined,
          label: copy.text('Share', 'Udostępnij'),
          active: false,
          semanticLabel: copy.text(
            'Share this Moment',
            'Udostępnij ten Moment',
          ),
          onTap: widget.onShare,
        ),
        if (widget.canReport)
          _SmallChip(
            key: ValueKey('detail-report-${widget.moment.id}'),
            icon: Icons.flag_outlined,
            label: copy.text('Report', 'Zgłoś'),
            active: false,
            semanticLabel: copy.text(
              'Report this Voice Moment',
              'Zgłoś ten Voice Moment',
            ),
            onTap: widget.onReport,
          ),
        if (widget.canDelete)
          _SmallChip(
            key: ValueKey('detail-delete-${widget.moment.id}'),
            icon: Icons.delete_outline_rounded,
            label: copy.text('Delete', 'Usuń'),
            active: false,
            destructive: true,
            semanticLabel: copy.text(
              'Delete this Voice Moment',
              'Usuń ten Voice Moment',
            ),
            onTap: widget.onDelete,
          ),
      ],
    );
  }

  Future<void> _toggle(HomeFeedService service) async {
    if (_pending) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final copy = AppLocalizations.of(context);
    final previousLiked = _liked;
    final previousCount = _likeCount;
    final desiredLiked = !previousLiked;
    setState(() {
      _liked = desiredLiked;
      _likeCount = (previousCount + (desiredLiked ? 1 : -1)).clamp(0, 1 << 31);
      _pending = true;
      _hasLocalOverride = true;
    });
    try {
      await service.setLike(widget.moment.id, liked: desiredLiked);
      if (!mounted) return;
      setState(() => _pending = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked = previousLiked;
          _likeCount = previousCount;
          _pending = false;
          _hasLocalOverride = false;
        });
      }
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              copy.text(
                'Your like could not be saved. Try again.',
                'Nie udało się zapisać polubienia. Spróbuj ponownie.',
              ),
            ),
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
class MomentCommentsInline extends StatefulWidget {
  const MomentCommentsInline({
    required this.momentId,
    required this.momentService,
    super.key,
  });

  final String momentId;
  final MomentService? momentService;

  @override
  State<MomentCommentsInline> createState() => MomentCommentsInlineState();
}

class MomentCommentsInlineState extends State<MomentCommentsInline> {
  Stream<List<MomentComment>>? _comments;

  @override
  void initState() {
    super.initState();
    _comments = _load();
  }

  @override
  void didUpdateWidget(covariant MomentCommentsInline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.momentId != widget.momentId ||
        !identical(oldWidget.momentService, widget.momentService)) {
      _comments = _load();
    }
  }

  Stream<List<MomentComment>>? _load() =>
      widget.momentService?.watchComments(widget.momentId);

  void refresh() {
    if (!mounted) return;
    setState(() => _comments = _load());
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final service = widget.momentService;
    if (service == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          copy.text(
            'Comments are unavailable right now.',
            'Komentarze są teraz niedostępne.',
          ),
          style: TextStyle(color: palette.textTertiary, fontSize: 12.5),
        ),
      );
    }
    return StreamBuilder<List<MomentComment>>(
      stream: _comments,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              copy.text(
                'Could not load comments.',
                'Nie udało się wczytać komentarzy.',
              ),
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
              copy.text(
                'Be the first to comment.',
                'Napisz pierwszy komentarz.',
              ),
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
                      userId: comment.authorId,
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
                                momentRelativeAge(
                                  comment.createdAt,
                                  copy: copy,
                                ),
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
                              copy.text(
                                'Voice reply · ${comment.durationSeconds}s'
                                    '${comment.text.isNotEmpty ? ' — ${comment.text}' : ''}',
                                'Odpowiedź głosowa · ${comment.durationSeconds} s'
                                    '${comment.text.isNotEmpty ? ' — ${comment.text}' : ''}',
                              ),
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
    final copy = AppLocalizations.of(context);
    Widget bone(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: AppRadius.sm,
      ),
    );
    return Semantics(
      liveRegion: true,
      label: copy.text('Loading Moments', 'Wczytywanie Momentów'),
      child: ExcludeSemantics(
        child: ListView.builder(
          key: const ValueKey('moments-discovery-loading'),
          padding: const EdgeInsets.all(AppRhythm.title),
          itemCount: 3,
          itemBuilder: (context, index) => Container(
            margin: const EdgeInsets.only(bottom: AppRhythm.item),
            padding: const EdgeInsets.all(AppRhythm.title),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              border: Border.all(color: palette.border),
              borderRadius: AppRadius.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    bone(48, 48),
                    const SizedBox(width: AppRhythm.item),
                    Expanded(child: bone(double.infinity, 16)),
                  ],
                ),
                const SizedBox(height: AppRhythm.title),
                bone(double.infinity, 16),
                const SizedBox(height: AppRhythm.tight),
                bone(double.infinity, 16),
                const SizedBox(height: AppRhythm.title),
                bone(double.infinity, 44),
              ],
            ),
          ),
        ),
      ),
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
    final copy = AppLocalizations.of(context);
    return Center(
      key: const ValueKey('moments-discovery-error'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppRhythm.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 32,
              color: palette.dangerForeground,
            ),
            const SizedBox(height: AppRhythm.title),
            Text(
              copy.text(
                'Moments could not load',
                'Nie udało się wczytać Momentów',
              ),
              textAlign: TextAlign.center,
              style: AppTypography.titleLarge.copyWith(
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: AppRhythm.tight),
            Text(
              friendlyErrorMessage(
                error ?? StateError('unavailable'),
                copy: copy,
                fallback: copy.text(
                  'Something went wrong reaching the Voice Moments feed.',
                  'Nie udało się połączyć z kanałem Voice Moments.',
                ),
              ),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: AppRhythm.section),
            FilledButton(
              onPressed: onRetry,
              child: Text(copy.text('Try again', 'Spróbuj ponownie')),
            ),
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

bool _voiceAccessWasDenied(Object error) {
  if (error is FirebaseException) {
    return const {
      'permission-denied',
      'unauthenticated',
      'not-found',
    }.contains(error.code);
  }
  final code = error.toString().toLowerCase();
  return code.contains('permission-denied') ||
      code.contains('permission_denied') ||
      code.contains('unauthenticated') ||
      code.contains('not-found');
}

Future<void> _shareVoiceMoment(
  VoiceMoment moment,
  AppLocalizations copy,
) async {
  // Preserve the existing public-link mechanism. The destination performs
  // its own current-identity and availability checks; no media URL is shared.
  final link = Uri.https('yovoice.app', '/', {'moment': moment.id});
  await SharePlus.instance.share(
    ShareParams(
      text: copy.text(
        'Listen to ${moment.authorName} on YO Voice: $link',
        'Posłuchaj ${moment.authorName} w YO Voice: $link',
      ),
    ),
  );
}

String _clock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}
