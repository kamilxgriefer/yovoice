import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/core/helpers/callable_failure_reporter.dart';
import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_finish.dart';
import 'package:yovoice/core/theme/app_gradients.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
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
import 'package:yovoice/features/moments/presentation/screens/record_voice_moment_screen.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_circles_strip.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_compact_row.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_pill.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_sheet.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_tile.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_queue_list.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_story_viewer.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_time_labels.dart';
import 'package:yovoice/features/moments/presentation/widgets/moments_follow_panel.dart';
import 'package:yovoice/features/moments/presentation/widgets/voice_feed_filter_tabs.dart';
import 'package:yovoice/features/moments/presentation/widgets/yo_moments_chrome.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/shared/widgets/buttons/yo_gradient_filled_button.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_feed_chrome.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/voice/voice_player_row.dart'
    show VoiceBeadButton, VoicePourWaveform;

/// Which slice of the Moments corpus the feed is showing.
enum MomentsFilter {
  /// The current discovery pool, newest first. Engagement ordering remains
  /// an explicit filter, rather than a second copy of the same recordings.
  discover,

  /// Only the people this account follows (plus friends and itself) —
  /// the personal feed, fed by the existing [HomeFeedService] stream.
  following,

  /// The same pool in pure engagement order, most-engaged first — the
  /// "Popularne" / "Popular" tab.
  mostEngaged,

  /// The same pool ordered by `createdAt` descending, nothing else.
  ///
  /// NOT offered in the UI (G4): it produced exactly the list [discover]
  /// produces (both are `createdAt` descending over the same pool), so two
  /// tabs showed one list. The value and its code path stay for the entry
  /// seams and saved state that may still name it; the feed shows it as
  /// [discover] ([momentsShownFilter]).
  recent,
}

/// The tabs the Głos feed offers, in order.
const List<MomentsFilter> momentsVisibleFilters = <MomentsFilter>[
  MomentsFilter.discover,
  MomentsFilter.following,
  MomentsFilter.mostEngaged,
];

/// The filter the feed actually shows for a requested [filter]: a request
/// for the retired "Recent" (a legacy seam, saved state) lands on
/// Discover, which is the same list.
MomentsFilter momentsShownFilter(MomentsFilter filter) =>
    filter == MomentsFilter.recent ? MomentsFilter.discover : filter;

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
    this.headerBuilder,
    this.immersiveHeader,
    this.onCreate,
    this.onOpenFindCreators,
    this.friendService,
    this.followService,
    this.neighbourQueue,
    this.refreshRequests,
    super.key,
  });

  final VoidCallback onRecord;
  final MomentsFilter initialFilter;

  /// The YO Moments header (title + format switch) the host wants drawn at
  /// the top of the main column, built for the layout THIS view resolves
  /// from its slot so the header and the columns can never disagree.
  final Widget Function(BuildContext context, YoMomentsLayout layout)?
  headerBuilder;

  /// Reels-style compact chrome supplied by the YO Moments host. On phone
  /// and tablet it keeps Voice and Reels in the same two-row visual shell
  /// while the Voice cards, playback and filters keep their own behaviour.
  final ImmersiveFeedHeaderSlots? immersiveHeader;

  /// The create chooser, for the local panel's "Utwórz" at ≥ 1100. Absent,
  /// the panel draws no create action.
  final VoidCallback? onCreate;

  /// "Find people" on the Following empty state. Absent, no such action is
  /// drawn — never a dead button.
  final VoidCallback? onOpenFindCreators;

  /// Injection seams for the calm panel's real pool (friends the viewer
  /// does not follow yet); production passes nothing.
  final FriendService? friendService;
  final FollowService? followService;

  /// Where this feed publishes the pool the expanded player may hand off
  /// to. Production shares one instance; tests pass their own.
  final MomentNeighbourQueue? neighbourQueue;

  /// Fires when the host asks for the list to be read again — YO Moments
  /// fires it when the already selected "Głos" format tab is activated a
  /// second time (as [ReelsFeedScreen.refreshRequests] does for "Yeels").
  /// The same path as re-tapping the active filter tab: back to the top,
  /// the pull-to-refresh spinner, a polite announcement, and a no-op while
  /// a reload is already running.
  final Listenable? refreshRequests;
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

  late MomentsFilter _filter = momentsShownFilter(widget.initialFilter);

  /// The feed list's scroll position: re-tapping the active tab returns it
  /// to the top before the refresh.
  final ScrollController _feedScroll = ScrollController();

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

  /// The load whose total server drop has already been reported, so a
  /// rebuild of the same failed page does not report it again.
  int? _reportedDropEpoch;
  int _socialEpoch = 0;
  ModalRoute<void>? _observedRoute;
  bool _routeIsCurrent = true;

  /// A transient popup — a menu — sits directly above the feed's route. It
  /// covers a few rows, not the feed: playback continues, the open row
  /// stays open (its ⋯ answers from it and gets focus back), and closing it
  /// reloads nothing (a reload would drop every "Wczytaj więcej" page).
  bool _transientPopupAbove = false;
  bool _foreground = true;
  late bool _wasVisible;
  bool _openingDestination = false;
  final _likeOverrides = <String, ({bool liked, int count})>{};
  final _pendingLikes = <String>{};
  // Reported by the calm panel; the third column exists only while true.
  bool _calmPanelHasPeople = false;

  // What the expanded player may hand off to. Published at the hand-off,
  // refreshed while it is live, cleared with the account.
  late final MomentNeighbourQueue _neighbourQueue =
      widget.neighbourQueue ?? MomentNeighbourQueue.shared;
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
  final _playback = ValueNotifier<MomentFeedPlayback>(
    const MomentFeedPlayback(),
  );

  /// The controller's current clip (playing, paused, loading or failed), or
  /// null: the ONE row that is open. It changes on play, a switch or a stop
  /// and never on a position tick, so the rows that listen to it never
  /// rebuild per tick.
  final _current = ValueNotifier<String?>(null);

  /// The row being pressed while the current clip switches, so the list
  /// keeps it where the reader pressed it ([_AnchoredRows]).
  final _scrollAnchor = _ScrollAnchor();

  /// W3's energy: the id of the ONE row whose clip is actually playing
  /// (never while its grant resolves), or null. It changes only on play,
  /// pause or a switch of clip — a position tick leaves it alone — and
  /// exactly one row in the feed is ever lit.
  final _lit = ValueNotifier<String?>(null);

  /// Bumped by every COMPLETED seek, together with the sought position, so
  /// the poured waveform snaps to it instead of flowing to it.
  int _seekGeneration = 0;
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

  /// The one pull-to-refresh indicator mounted at a time (the list's, or an
  /// empty state's), so a requested reload can show its spinner.
  final GlobalKey<RefreshIndicatorState> _refreshIndicator =
      GlobalKey<RefreshIndicatorState>(debugLabel: 'Głos refresh');

  /// The reload in flight: a second request joins it instead of starting
  /// another read.
  Future<void>? _refreshInFlight;

  /// A requested reload whose spinner is still snapping in (the indicator
  /// starts the read once it has): a second request then is the same one.
  bool _reloadStarting = false;
  Timer? _reloadStartGuard;
  int _reloadRequests = 0;
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
    widget.refreshRequests?.addListener(_requestRefresh);
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
    // A hand-off list belongs to the account that loaded it; the next
    // account starts from nothing rather than from the previous pool.
    _neighbourQueue.clear();
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
    if (!identical(oldWidget.refreshRequests, widget.refreshRequests)) {
      oldWidget.refreshRequests?.removeListener(_requestRefresh);
      widget.refreshRequests?.addListener(_requestRefresh);
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
    final isCurrent = route?.isCurrent ?? true;
    if (isCurrent) {
      _transientPopupAbove = false;
    } else if (_routeIsCurrent &&
        !_transientPopupAbove &&
        _isTransientPopup(_topRoute())) {
      // Just covered, and by a popup — told here too, for a host whose
      // navigator carries no route observer: the route directly above ours
      // is the one that was just pushed.
      _transientPopupAbove = true;
    }
    _routeIsCurrent = isCurrent || _transientPopupAbove;
    _handleVisibility();
  }

  @override
  void didPushNext() {
    if (_isTransientPopup(_topRoute())) {
      _transientPopupAbove = true;
      return;
    }
    _transientPopupAbove = false;
    _setRouteCurrent(false);
  }

  @override
  void didPopNext() {
    // The menu that just closed covered nothing: no stop happened, so no
    // reload follows either.
    _transientPopupAbove = false;
    _setRouteCurrent(true);
  }

  @override
  void didPop() {
    _transientPopupAbove = false;
    _setRouteCurrent(false);
  }

  /// The navigator's topmost route. `popUntil` hands its predicate the
  /// topmost route first, and answering `true` at once pops nothing; the
  /// navigator offers no other public read of it.
  Route<dynamic>? _topRoute() {
    final navigator = _observedRoute?.navigator;
    if (navigator == null) return null;
    Route<dynamic>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    return top;
  }

  /// A popup that lays a few entries over the feed (a menu, a dropdown) —
  /// not a dialog or a bottom sheet, which host content of their own (the
  /// Moment sheet plays its own audio) and do cover the feed.
  static bool _isTransientPopup(Route<dynamic>? route) =>
      route is PopupRoute &&
      route is! RawDialogRoute &&
      route is! ModalBottomSheetRoute;

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
    widget.refreshRequests?.removeListener(_requestRefresh);
    _reloadStartGuard?.cancel();
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
    _current.dispose();
    _lit.dispose();
    _feedScroll.dispose();
    _expiryRecoveryFocus.dispose();
    if (_neighbourQueue.value.belongsTo(_viewerUid)) _neighbourQueue.clear();
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
        // A refresh failure never replaces content already shown: the cards
        // stay, the footer keeps its retry, and the failure is announced
        // once as a SnackBar.
        if (mounted && _surfaceAllowsPlayback) {
          ScaffoldMessenger.maybeOf(context)
            ?..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(friendlyErrorMessage(error, copy: _copy)),
              ),
            );
        }
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

  /// Raises a Crashlytics signal for a feed page the server emptied.
  ///
  /// The server cannot say this on the wire: `VoiceMomentFeedPageV2.parse`
  /// requires an EXACT five-key response, so adding a `droppedCount` field
  /// would break every installed client at once (ADR-B in the Build 31
  /// design). The count is derived from what the wire already carries, and
  /// the alarm is raised from here instead — the previous outage produced
  /// HTTP 200s and no error line anywhere for 2.2 days.
  void _reportServerDroppedFeed() {
    if (_reportedDropEpoch == _loadEpoch) return;
    _reportedDropEpoch = _loadEpoch;
    recordCallableRefusal(
      callable: 'getVoiceMomentsFeedV2',
      code: 'server-dropped-all',
    );
  }

  /// Reads the list again. A reload already running is joined, not
  /// doubled: two quick requests are one read.
  Future<void> _refreshAll() {
    _reloadStarting = false;
    _reloadStartGuard?.cancel();
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    late final Future<void> reload;
    reload = () async {
      try {
        _retrySocial();
        await _load();
      } finally {
        if (identical(_refreshInFlight, reload)) _refreshInFlight = null;
      }
    }();
    _refreshInFlight = reload;
    return reload;
  }

  /// A reload the READER asked for — the active tab tapped again, the
  /// host's reselect ([MomentsFeedView.refreshRequests]), the desktop
  /// "Odśwież Momenty": back to the top, the pull-to-refresh spinner as its
  /// visible progress, and a polite announcement. Ignored while a reload is
  /// starting or running.
  void _requestRefresh() {
    if (!mounted || _reloadStarting || _refreshInFlight != null) return;
    if (_feedScroll.hasClients && _feedScroll.offset > 0) {
      final duration = AppMotion.resolve(context, AppMotion.entrance);
      if (duration == Duration.zero) {
        _feedScroll.jumpTo(0);
      } else {
        unawaited(
          _feedScroll.animateTo(
            0,
            duration: duration,
            curve: AppMotion.entranceCurve,
          ),
        );
      }
    }
    _expiryAnnouncer.announce(
      context,
      transition: 'reload-request-${++_reloadRequests}',
      message: _copy.text('Reloading Moments…', 'Odświeżanie Momentów…'),
    );
    final indicator = _refreshIndicator.currentState;
    if (indicator == null || !indicator.mounted) {
      unawaited(_refreshAll());
      return;
    }
    // The spinner snaps in and then calls its onRefresh ([_refreshAll]);
    // should it be torn down first (the list replaced mid-snap), the guard
    // still reads the list.
    _reloadStarting = true;
    _reloadStartGuard?.cancel();
    _reloadStartGuard = Timer(const Duration(seconds: 1), () {
      if (!mounted || !_reloadStarting) return;
      unawaited(_refreshAll());
    });
    unawaited(indicator.show());
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
      // The route half is [_routeIsCurrent]'s, which knows that a transient
      // popup over the feed does not hide it.
      momentExpirySurfaceIsVisible(context, requireCurrentRoute: false);

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
    _playback.value = MomentFeedPlayback(
      id: _playingId,
      playing: _isPlaying,
      busy: _playbackBusy,
      elapsed: _position,
      duration: _duration,
      error: _playbackError,
      seek: _seekGeneration,
    );
    _current.value = _playingId;
    _lit.value = _isPlaying && !_playbackBusy ? _playingId : null;
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
    if (_playingId != moment.id) {
      // Opening this row closes the open one; if that one is above it, the
      // list keeps THIS row — the control just pressed — where it is.
      _scrollAnchor.pressedId = moment.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollAnchor.pressedId == moment.id) {
          _scrollAnchor.pressedId = null;
        }
      });
    }
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
          // Bumped only now, in the same publish as the sought position: a
          // tick that lands while the seek is in flight still carries the
          // OLD generation (and pours), so the sought position always
          // arrives with a new one and snaps.
          _seekGeneration += 1;
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

  /// "Odpowiedz głosem" on a card: the existing recorder in reply mode.
  /// The feed player is released first (as for every destination) and the
  /// microphone starts only on the recorder's own deliberate control. A
  /// published reply (`true`) is acknowledged; the feed itself reloads on
  /// the route's return (`didPopNext` → `_handleVisibility` → `_refreshAll`),
  /// exactly as after every other pushed destination, so the live comment
  /// count lands without a second load.
  Future<void> _replyWithVoice(VoiceMoment moment) =>
      _openDestination(moment, (current) async {
        final created = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => RecordVoiceMomentScreen(
              replyToMomentId: current.id,
              replyToAuthorName: current.authorName,
              momentService: widget.momentService,
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
    _republishNeighbours();
  }

  /// Keeps a LIVE hand-off list honest: a Moment that was deleted, expired
  /// or dropped here must not stay offered on the expanded player. Silent
  /// when nothing was ever handed off for this account.
  void _republishNeighbours() {
    if (!_neighbourQueue.value.belongsTo(_viewerUid)) return;
    _neighbourQueue.publish(
      viewerUid: _viewerUid,
      moments: _currentList().map(_withLive).toList(growable: false),
    );
  }

  /// Opens the full detail page for [moment]. The shell's route keeps the
  /// bottom navigation visible with Moments active; the fallback plain
  /// route carries its own Back control.
  void _openDetail(VoiceMoment moment) {
    unawaited(
      _openDestination(moment, (moment) async {
        // The expanded player's hand-off list: exactly the pool this feed
        // has already loaded and filtered for THIS account. Nothing is
        // fetched for it and no media grant is minted for it.
        _neighbourQueue.publish(
          viewerUid: _viewerUid,
          moments: _currentList().map(_withLive).toList(growable: false),
        );
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
      _republishNeighbours();
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

  void _setFilter(MomentsFilter requested) {
    final filter = momentsShownFilter(requested);
    if (filter == _filter) return;
    unawaited(_stopPanelPlayback());
    setState(() {
      _filter = filter;
    });
  }

  /// A tap on a tab. The ACTIVE tab tapped again takes the list back to its
  /// top and reloads it — the phone's refresh now that the refresh button
  /// is gone (pull-to-refresh is the other way).
  void _selectTab(MomentsFilter filter) {
    if (momentsShownFilter(filter) != _filter) {
      _setFilter(filter);
      return;
    }
    _requestRefresh();
  }

  // ---------------------------------------------------------------- build

  static const _filterIcons = <MomentsFilter, IconData>{
    MomentsFilter.discover: Icons.explore_outlined,
    MomentsFilter.following: Icons.people_outline_rounded,
    MomentsFilter.mostEngaged: Icons.trending_up_rounded,
    MomentsFilter.recent: Icons.schedule_rounded,
  };

  static String filterLabel(AppLocalizations copy, MomentsFilter value) =>
      switch (value) {
        MomentsFilter.discover => copy.text('Discover', 'Odkrywaj'),
        MomentsFilter.following => copy.text('Following', 'Obserwowani'),
        // "Najbardziej angażujące" became "Popularne": the same engagement
        // order behind a word that fits a tab.
        MomentsFilter.mostEngaged => copy.contextualText(
          'yoMoments.popular',
          'Popular',
          'Popularne',
        ),
        MomentsFilter.recent => copy.text('Recent', 'Najnowsze'),
      };

  List<YoMomentsFilterOption> _filterOptions(AppLocalizations copy) =>
      <YoMomentsFilterOption>[
        for (final value in momentsVisibleFilters)
          YoMomentsFilterOption(
            key: ValueKey('moments-filter-${value.name}'),
            label: filterLabel(copy, value),
            icon: _filterIcons[value]!,
          ),
      ];

  /// Whether the column is still waiting for its first page: the author
  /// strip and the calm panel stay ABSENT then (they would fake authors).
  bool get _isLoadingFirstPage => _filter == MomentsFilter.following
      ? _socialError == null && _socialData == null && _feed != null
      : _phase == _Phase.loading;

  void _setCalmPanel(bool hasPeople) {
    if (!mounted || _calmPanelHasPeople == hasPeople) return;
    setState(() => _calmPanelHasPeople = hasPeople);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = YoMomentsLayout.of(
          constraints.maxWidth,
          textScale: MediaQuery.textScalerOf(context).scale(1),
        );
        final copy = _copy;
        final palette = context.appPalette;
        final options = _filterOptions(copy);
        final selectedIndex = momentsVisibleFilters.indexOf(_filter);
        final groupLabel = copy.contextualText(
          'yoMoments.voiceFilters',
          'Voice Moment filters',
          'Filtry Voice Momentów',
        );
        final header = widget.headerBuilder?.call(context, layout);
        final immersiveHeader = widget.immersiveHeader;
        final usesImmersiveChrome =
            !layout.showsLocalPanel && immersiveHeader != null;
        final body = _filter == MomentsFilter.following
            ? _buildFollowing(layout)
            : _buildPool(layout);
        // Level 2 below 1100: three trackless text tabs. The active one is
        // also the focus-recovery target after an expiry removal (it took
        // over from the refresh button), and tapping it again scrolls to the
        // top and reloads.
        final tabs = VoiceFeedFilterTabs(
          key: const ValueKey<String>('voice-filter-tabs'),
          groupLabel: groupLabel,
          selectedIndex: selectedIndex,
          selectedFocusNode: _expiryRecoveryFocus,
          selectedHint: voiceFeedTabRefreshHint(copy),
          onSelected: (index) => _selectTab(momentsVisibleFilters[index]),
          tabs: <ImmersiveChromeOption>[
            for (final option in options)
              ImmersiveChromeOption(key: option.key, label: option.label),
          ],
        );

        Widget mainColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (usesImmersiveChrome)
              ImmersiveFeedChrome(
                key: const ValueKey<String>('voice-immersive-chrome'),
                // Głos is a list on the page canvas, not footage: the same
                // compact chrome, drawn in palette roles, with the text tabs
                // as its level 2.
                onCanvas: true,
                gutter: layout.gutter,
                formatSwitch: immersiveHeader.formatSwitch,
                leading: immersiveHeader.leading,
                trailing: immersiveHeader.trailing,
                filterBar: tabs,
                filterGroupLabel: groupLabel,
              )
            else
              ?header,
            if (!layout.showsLocalPanel && !usesImmersiveChrome)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  layout.gutter,
                  AppRhythm.tight,
                  layout.gutter,
                  0,
                ),
                child: tabs,
              ),
            // The chrome ends on a hairline; the list scrolls under it.
            if (!layout.showsLocalPanel)
              Divider(
                key: const ValueKey<String>('voice-chrome-divider'),
                height: 1,
                thickness: 1,
                color: MediaQuery.highContrastOf(context)
                    ? palette.borderStrong
                    : palette.hairline,
              ),
            Expanded(child: body),
          ],
        );
        mainColumn = Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.mainColumnOuterWidth),
            child: mainColumn,
          ),
        );

        Widget content = mainColumn;
        if (layout.showsLocalPanel) {
          final calmVisible =
              layout.showsCalmPanel &&
              _calmPanelHasPeople &&
              !_isLoadingFirstPage;
          // One traversal group per column. Without them the reading-order
          // policy interleaves the three columns — Tab crossed between them
          // seven times inside a single card — and a keyboard or switch user
          // reaches the calm panel between two controls of the same Moment.
          content = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FocusTraversalGroup(
                child: YoMomentsLocalPanel(
                  options: options,
                  selectedIndex: selectedIndex,
                  onSelected: (index) =>
                      _setFilter(momentsVisibleFilters[index]),
                  groupLabel: groupLabel,
                  width: layout.localPanelWidth,
                  onCreate: widget.onCreate,
                  // The desktop refresh: an IconButton with the feed's
                  // refresh key, tooltip and focus-recovery node, given its
                  // label as a row so it reads like the panel's rows.
                  trailing: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: IconButton(
                      key: const ValueKey('moments-discovery-refresh'),
                      focusNode: _expiryRecoveryFocus,
                      onPressed: _requestRefresh,
                      tooltip: copy.text('Reload Moments', 'Odśwież Momenty'),
                      style: IconButton.styleFrom(
                        foregroundColor: palette.textSecondary,
                        minimumSize: const Size(
                          AppSizing.minimumTouchTarget,
                          AppSizing.standardControlHeight,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppRhythm.item,
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.md,
                        ),
                      ),
                      icon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.refresh_rounded, size: 20),
                          const SizedBox(width: AppRhythm.item),
                          Flexible(
                            // Spoken once, through the tooltip.
                            child: ExcludeSemantics(
                              child: Text(
                                copy.text('Reload Moments', 'Odśwież Momenty'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.titleSmall.copyWith(
                                  color: palette.textSecondary,
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
              SizedBox(width: layout.gutter),
              Expanded(child: FocusTraversalGroup(child: mainColumn)),
              if (layout.showsCalmPanel) ...[
                // Mounted whenever the third column CAN exist, so the pool
                // is known before the column is shown; it takes no width
                // until the pool has someone in it.
                FocusTraversalGroup(
                  child: Visibility(
                    visible: calmVisible,
                    maintainState: true,
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: layout.gutter,
                        end: layout.gutter,
                      ),
                      child: SizedBox(
                        width: YoMomentsLayout.calmPanelWidth,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(
                            top: AppRhythm.title,
                            bottom: AppRhythm.page,
                          ),
                          child: MomentsFollowPanel(
                            key: ValueKey('moments-follow-panel-$_viewerUid'),
                            friendService: widget.friendService,
                            followService: widget.followService,
                            auth: widget.auth,
                            onRecord: widget.onRecord,
                            onPoolChanged: _setCalmPanel,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        }

        // Padding rather than an Align: the columns stretch to the full
        // height, and an Align would hand them loose height constraints.
        final sideInset = layout.workspaceSideInset;
        if (layout.showsLocalPanel && sideInset > 0) {
          content = Padding(
            padding: EdgeInsets.symmetric(horizontal: sideInset),
            child: content,
          );
        }

        return YoPageBackground(
          section: YoPageSection.moments,
          key: const ValueKey('moments-feed-view'),
          child: content,
        );
      },
    );
  }

  Widget _buildPool(YoMomentsLayout layout) {
    switch (_phase) {
      case _Phase.loading:
        return _LoadingState(layout: layout);
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
        layout: layout,
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
        onPull: _refreshAll,
        refreshKey: _refreshIndicator,
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
    if (result.serverDroppedEverything) {
      // The server scanned candidates and returned none. This client
      // filtered nothing — it was handed nothing to filter — so it knows
      // only that the failure was upstream, and must say exactly that.
      // Before this branch existed the code below ran with an EMPTY drops
      // map, and `Iterable.every` on an empty iterable is `true`, so the
      // screen asserted that N Moments had expired: a fabricated
      // explanation for Moments it never saw.
      _reportServerDroppedFeed();
      return _EmptyState(
        onPull: _refreshAll,
        refreshKey: _refreshIndicator,
        icon: Icons.cloud_off_rounded,
        title: _copy.text(
          'These Moments could not be loaded',
          'Nie udało się wczytać tych Momentów',
        ),
        body: _copy.template(
          'The server returned {count} Moments and none of them could be '
              'prepared. This is a problem on our side.',
          'Serwer zwrócił {count} Momentów i żadnego nie udało się '
              'przygotować. To problem po naszej stronie.',
          values: <String, Object>{'count': result.fetchedCount},
        ),
        actionLabel: _copy.text('Try again', 'Spróbuj ponownie'),
        onAction: _load,
      );
    }
    if (result.moments.isEmpty) {
      // Published Moments exist and none are live. Expiry is the normal
      // reason now; a corpus where something was dropped for
      // unplayability instead is still called out as the pipeline
      // failure it is.
      //
      // `drops.isNotEmpty` is load-bearing: `every` answers true for an
      // empty iterable, so without it an all-server-dropped page would
      // claim expiry it cannot know about.
      final expiredOnly =
          result.drops.isNotEmpty &&
          result.drops.values.every(
            (reason) =>
                reason == MomentDropReason.expired ||
                reason == MomentDropReason.blockedAuthor,
          );
      return _EmptyState(
        onPull: _refreshAll,
        refreshKey: _refreshIndicator,
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
      layout: layout,
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

  Widget _buildFollowing(YoMomentsLayout layout) {
    if (_socialError != null) {
      return _ErrorState(error: _socialError, onRetry: _retrySocial);
    }
    if (_socialData == null && _feed != null) {
      return _LoadingState(layout: layout);
    }
    final list = _followingList(
      _effectiveNow(),
    ).map(_withLive).toList(growable: false);
    if (list.isEmpty) {
      final findPeople = widget.onOpenFindCreators;
      return _EmptyState(
        onPull: _refreshAll,
        refreshKey: _refreshIndicator,
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
        secondaryActionKey: const ValueKey('moments-following-find-people'),
        secondaryActionLabel: findPeople == null
            ? null
            : _copy.text('Find people', 'Znajdź osoby'),
        onSecondaryAction: findPeople,
      );
    }
    return _buildList(list, layout: layout);
  }

  Widget _buildList(
    List<VoiceMoment> list, {
    required YoMomentsLayout layout,
    Widget? footer,
  }) {
    // The author strip lists EXACTLY the authors of the list being shown —
    // loaded, active, unblocked, playable — and nothing else.
    final chains = _chainsFor(list);
    String? viewerName;
    try {
      viewerName = _auth?.currentUser?.displayName;
    } catch (_) {
      viewerName = null;
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _checkVisiblePlaybackAfterFrame();
        return false;
      },
      child: _FeedColumn(
        key: ValueKey('voice-feed-account-$_accountEpoch'),
        moments: list,
        chains: chains,
        gutter: layout.gutter,
        block: layout.showsLocalPanel,
        controller: _feedScroll,
        anchor: _scrollAnchor,
        viewedIds: _viewedIds,
        currentUserId: _uid,
        viewerName: viewerName,
        playback: _playback,
        current: _current,
        lit: _lit,
        pendingLikes: _pendingLikes,
        canLike: _feed != null,
        footer: footer,
        refreshKey: _refreshIndicator,
        onRefresh: _refreshAll,
        onRecord: widget.onRecord,
        onRowBuild: _rememberCard,
        onRowDispose: _forgetCard,
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
        onReplyVoice: (moment) => unawaited(_replyWithVoice(moment)),
      ),
    );
  }
}

/// The Głos list (G4): the author circles, then one compact row per Moment,
/// then the pool footer — one lazy scroll view that pulls to refresh.
///
/// Below 1100 the rows sit on the canvas, full-bleed, a hairline between
/// them. At 1100 and wider (the local panel exists) the rows are ONE R2
/// block — radius 20, a flat `surface` fill, the hairline edge (Pearl's
/// lift outside) — with the dividers inside it; the strip stays above it on
/// the canvas. The block is painted behind the lazy list as a sliver
/// decoration, so it is one shape however long the list grows.
class _FeedColumn extends StatelessWidget {
  const _FeedColumn({
    required this.moments,
    required this.chains,
    required this.gutter,
    required this.block,
    required this.controller,
    required this.anchor,
    required this.viewedIds,
    required this.currentUserId,
    required this.viewerName,
    required this.playback,
    required this.current,
    required this.lit,
    required this.pendingLikes,
    required this.canLike,
    required this.refreshKey,
    required this.onRefresh,
    required this.onRecord,
    required this.onRowBuild,
    required this.onRowDispose,
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
    required this.onReplyVoice,
    this.footer,
    super.key,
  });

  final List<VoiceMoment> moments;
  final List<MomentChain> chains;
  final double gutter;

  /// The rows are one R2 block (≥ 1100).
  final bool block;
  final ScrollController controller;
  final _ScrollAnchor anchor;
  final Set<String> viewedIds;
  final String currentUserId;
  final String? viewerName;
  final ValueListenable<MomentFeedPlayback> playback;
  final ValueListenable<String?> current;

  /// The id of the one playing row (W3's energy notifier).
  final ValueListenable<String?> lit;
  final Set<String> pendingLikes;
  final bool canLike;
  final Widget? footer;
  final GlobalKey<RefreshIndicatorState> refreshKey;
  final Future<void> Function() onRefresh;
  final VoidCallback onRecord;
  final void Function(String, BuildContext) onRowBuild;
  final void Function(String, BuildContext) onRowDispose;
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
  final ValueChanged<VoiceMoment> onReplyVoice;

  /// The rows' inner gutter inside the desktop block (the board's 20).
  static const double blockInset = 20;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final highContrast = MediaQuery.highContrastOf(context);
    final hasStrip = chains.isNotEmpty;
    final indices = <Key, int>{
      for (var index = 0; index < moments.length; index++)
        ValueKey('moment-row-${moments[index].id}'): index,
    };
    final last = moments.length - 1;

    Widget row(BuildContext context, int index) {
      final moment = moments[index];
      final BorderRadius? clip;
      if (!block) {
        clip = null;
      } else if (index == 0 && index == last) {
        clip = AppRadius.block;
      } else if (index == 0) {
        clip = const BorderRadius.vertical(top: Radius.circular(20));
      } else if (index == last) {
        clip = const BorderRadius.vertical(bottom: Radius.circular(20));
      } else {
        clip = null;
      }
      return MomentCompactRow(
        key: ValueKey('moment-row-${moment.id}'),
        moment: moment,
        seen: viewedIds.contains(moment.id),
        isOwn: currentUserId.isNotEmpty && moment.authorId == currentUserId,
        canInteract: currentUserId.isNotEmpty,
        canLike: canLike,
        likePending: pendingLikes.contains(moment.id),
        current: current,
        playback: playback,
        lit: lit,
        inset: block ? blockInset : gutter,
        onCanvas: !block,
        divider: index != last,
        clip: clip,
        onRowBuild: onRowBuild,
        onRowDispose: onRowDispose,
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
        onReplyVoice: () => onReplyVoice(moment),
      );
    }

    Widget rows = _AnchoredRows(
      ids: <String>[for (final moment in moments) moment.id],
      anchor: anchor,
      controller: controller,
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          row,
          childCount: moments.length,
          findChildIndexCallback: (key) => indices[key],
        ),
      ),
    );
    if (block && moments.isNotEmpty) {
      rows = SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        sliver: DecoratedSliver(
          key: const ValueKey<String>('moments-feed-block'),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: AppRadius.block,
            boxShadow: AppFinish.blockShadows(
              palette,
              highContrast: highContrast,
            ),
          ),
          sliver: DecoratedSliver(
            // The edge over the rows, so a row's ink never covers it.
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: AppRadius.block,
              border: AppFinish.blockEdge(palette, highContrast: highContrast),
            ),
            sliver: rows,
          ),
        ),
      );
    }

    return KeyedSubtree(
      key: const ValueKey<String>('moments-feed-refresh'),
      child: RefreshIndicator(
        key: refreshKey,
        onRefresh: onRefresh,
        color: palette.interactiveForeground,
        backgroundColor: palette.surfaceRaised,
        child: CustomScrollView(
          key: const ValueKey('moments-feed-scroll'),
          controller: controller,
          // Pull-to-refresh must work on a short list too.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            if (hasStrip)
              SliverToBoxAdapter(
                key: const ValueKey('moments-author-circles-item'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    MomentCirclesStrip(
                      chains: chains,
                      viewedIds: viewedIds,
                      gutter: gutter,
                      onRecord: onRecord,
                      viewerUid: currentUserId.isEmpty ? null : currentUserId,
                      viewerName: viewerName,
                      onOpenChain: (chain) => onOpenChain(chain.moments.last),
                    ),
                    if (block)
                      const SizedBox(height: AppRhythm.tight)
                    else
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: highContrast
                            ? palette.borderStrong
                            : palette.hairline,
                      ),
                  ],
                ),
              )
            else if (block)
              const SliverToBoxAdapter(
                child: SizedBox(height: AppRhythm.title),
              ),
            rows,
            if (footer != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    AppRhythm.title,
                    gutter,
                    0,
                  ),
                  child: footer,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: AppRhythm.page)),
          ],
        ),
      ),
    );
  }
}

/// The Moment whose row the reader is pressing (a play that switches the
/// current clip), for the next layout of [_AnchoredRows]; null otherwise.
class _ScrollAnchor {
  String? pressedId;
}

/// Keeps what the reader is looking at — or pressing — still when a row
/// above it changes height, in the frame the change happens (scroll
/// anchoring, as a browser does it).
///
/// Only one row is ever open, so opening a clip closes another one, and a
/// clip whose row scrolls off stops and closes its row. Without this the
/// rows below a closing row jumped by its player's height (~90 px): under
/// the reader's eyes when it had scrolled away above them, and under the
/// finger or the keyboard focus that had just pressed Play on a row below
/// it. The anchor is the pressed row when there is one, otherwise the first
/// row that reached into the viewport; its top keeps its place on screen
/// through a `scrollOffsetCorrection` the viewport applies before it
/// paints.
///
/// The list's first pixel is a hard edge: at the very top of the list there
/// is no scroll to give back, so a row closing above the anchor there still
/// moves it up by the part the offset cannot absorb.
///
/// It anchors only while the list is the same list (same ids, same order):
/// a reload, a filter switch, a deletion or an expiry lays the new list out
/// as it always did.
class _AnchoredRows extends SingleChildRenderObjectWidget {
  const _AnchoredRows({
    required this.ids,
    required this.anchor,
    required this.controller,
    required Widget sliver,
  }) : super(child: sliver);

  final List<String> ids;
  final _ScrollAnchor anchor;
  final ScrollController controller;

  @override
  _RenderAnchoredRows createRenderObject(BuildContext context) =>
      _RenderAnchoredRows(ids: ids, anchor: anchor, controller: controller);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAnchoredRows renderObject,
  ) {
    renderObject
      ..ids = ids
      ..anchor = anchor
      ..controller = controller;
  }
}

class _RenderAnchoredRows extends RenderProxySliver {
  _RenderAnchoredRows({
    required this.ids,
    required this.anchor,
    required this.controller,
  });

  List<String> ids;
  _ScrollAnchor anchor;
  ScrollController controller;

  List<String> _laidOutIds = const <String>[];
  double _laidOutScrollOffset = 0;

  /// Row id → layout offset of every row the list holds now, read against
  /// the ids of the layout that placed them. Offsets only: a row's size
  /// belongs to the list that lays it out.
  Map<String, double> _rows(List<String> idsAtLayout) {
    final list = child;
    final rows = <String, double>{};
    if (list is! RenderSliverMultiBoxAdaptor) return rows;
    for (var box = list.firstChild; box != null; box = list.childAfter(box)) {
      final data = box.parentData;
      if (data is! SliverMultiBoxAdaptorParentData) continue;
      final index = data.index;
      final offset = data.layoutOffset;
      if (index == null || offset == null || index >= idsAtLayout.length) {
        continue;
      }
      rows[idsAtLayout[index]] = offset;
    }
    return rows;
  }

  @override
  void performLayout() {
    final sameList = listEquals(_laidOutIds, ids);
    final before = sameList ? _rows(_laidOutIds) : const <String, double>{};
    final previousScrollOffset = _laidOutScrollOffset;
    super.performLayout();
    _laidOutIds = ids;
    _laidOutScrollOffset = constraints.scrollOffset;
    if (before.isEmpty || geometry!.scrollOffsetCorrection != null) return;
    final after = _rows(ids);

    String? anchorId;
    final pressed = anchor.pressedId;
    if (pressed != null &&
        before.containsKey(pressed) &&
        after.containsKey(pressed)) {
      anchorId = pressed;
    } else {
      // The first row whose top was at or below the viewport's top edge:
      // what the reader sees first, whatever happens above it.
      var top = double.infinity;
      before.forEach((id, offset) {
        if (offset >= previousScrollOffset - precisionErrorTolerance &&
            offset < top &&
            after.containsKey(id)) {
          top = offset;
          anchorId = id;
        }
      });
    }
    final id = anchorId;
    if (id == null) return;
    var correction = after[id]! - before[id]!;
    if (correction.abs() < precisionErrorTolerance) return;
    // Never above the list's first pixel.
    if (controller.hasClients) {
      final position = controller.position;
      if (position.hasPixels && position.hasContentDimensions) {
        final room = position.pixels - position.minScrollExtent;
        if (correction < -room) correction = -room;
      }
    }
    if (correction.abs() < precisionErrorTolerance) return;
    geometry = SliverGeometry(scrollOffsetCorrection: correction);
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
        border: BorderDirectional(start: BorderSide(color: palette.hairline)),
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
                          finish: UserAvatarFinish.brand,
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
                                      fontWeight: FontWeight.w700,
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
                                  MomentExpiryPill(
                                    label: expiry,
                                    labelKey: const ValueKey(
                                      'detail-expiry-label',
                                    ),
                                    createdAt: moment.createdAt,
                                    expiresAt: moment.expiresAt,
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
                      // The panel's transport is the R14 bead at 54, lit
                      // while this Moment plays.
                      VoiceBeadButton(
                        buttonKey: const ValueKey('detail-play-toggle'),
                        size: 54,
                        playing: widget.isPlaying,
                        onPressed: widget.onTogglePlay,
                        tooltip: widget.isPlaying
                            ? copy.text(
                                'Pause this Moment',
                                'Wstrzymaj ten Moment',
                              )
                            : copy.text(
                                'Play this Moment',
                                'Odtwórz ten Moment',
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
                                  child: VoicePourWaveform(
                                    progress: progress,
                                    color: palette.waveUnplayed,
                                    playedGradient: AppGradients.voicePlayed(
                                      colors,
                                      palette,
                                    ),
                                    height: 30,
                                    barRadius: 2,
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
                  Divider(color: palette.hairline, height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          copy.text('Comments', 'Komentarze'),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
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
              border: Border(top: BorderSide(color: palette.hairline)),
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

/// Row silhouettes at the compact row's real geometry — a 44 px avatar
/// bone, the name and meta bones, the 44 px play outline — with the rows'
/// hairlines (inside the R2 block from 1100). A gentle pulse, static under
/// Reduce Motion. The author strip and the side panels are ABSENT here: a
/// skeleton of authors would fake authors.
class _LoadingState extends StatefulWidget {
  const _LoadingState({required this.layout});

  final YoMomentsLayout layout;

  static const int rows = 6;

  @override
  State<_LoadingState> createState() => _LoadingStateState();
}

class _LoadingStateState extends State<_LoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final layout = widget.layout;
    final block = layout.showsLocalPanel;
    final inset = block ? _FeedColumn.blockInset : layout.gutter;
    final hairline = highContrast ? palette.borderStrong : palette.hairline;
    Widget bone(double width, double height, {bool round = false}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        shape: round ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: round ? null : AppRadius.sm,
      ),
    );
    Widget row(int index) => Container(
      constraints: const BoxConstraints(minHeight: MomentCompactRow.minHeight),
      padding: EdgeInsets.symmetric(horizontal: inset, vertical: 10),
      decoration: BoxDecoration(
        border: index == _LoadingState.rows - 1
            ? null
            : Border(bottom: BorderSide(color: hairline)),
      ),
      child: Row(
        children: [
          bone(
            MomentCompactRow.avatarDiameter,
            MomentCompactRow.avatarDiameter,
            round: true,
          ),
          const SizedBox(width: AppRhythm.item),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                bone(index.isEven ? 132 : 104, 14),
                const SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: index.isEven ? .72 : .56,
                  child: bone(double.infinity, 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppRhythm.item),
          Container(
            width: MomentRowTransportButton.size,
            height: MomentRowTransportButton.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: palette.border),
            ),
          ),
        ],
      ),
    );
    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (var i = 0; i < _LoadingState.rows; i++) row(i)],
    );
    return Semantics(
      liveRegion: true,
      label: copy.text('Loading Moments', 'Wczytywanie Momentów'),
      child: ExcludeSemantics(
        child: FadeTransition(
          opacity: Tween<double>(begin: .55, end: 1).animate(_pulse),
          child: ListView(
            key: const ValueKey('moments-discovery-loading'),
            padding: EdgeInsets.fromLTRB(
              block ? layout.gutter : 0,
              block ? AppRhythm.title : 0,
              block ? layout.gutter : 0,
              AppRhythm.page,
            ),
            children: [
              if (block)
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: AppRadius.block,
                    border: AppFinish.blockEdge(
                      palette,
                      highContrast: highContrast,
                    ),
                    boxShadow: AppFinish.blockShadows(
                      palette,
                      highContrast: highContrast,
                    ),
                  ),
                  child: rows,
                )
              else
                rows,
            ],
          ),
        ),
      ),
    );
  }
}

/// The R17 glyph disc of the Moments empty and error states: 64 px, a
/// primary @ .14 / .08 fill with a 1 px primary @ .30 edge and a 28 px
/// `interactiveForeground` glyph (a flat surface with `borderStrong` under
/// high contrast). The studio scenery already carries the neon YO, so the
/// Moments states never show the logo.
class _StateGlyph extends StatelessWidget {
  const _StateGlyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final primary = Theme.of(context).colorScheme.primary;
    final highContrast = MediaQuery.highContrastOf(context);
    return ExcludeSemantics(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: highContrast
              ? palette.surface
              : primary.withValues(alpha: palette.isDark ? .14 : .08),
          border: Border.all(
            color: highContrast
                ? palette.borderStrong
                : primary.withValues(alpha: .30),
          ),
        ),
        child: Icon(icon, size: 28, color: palette.interactiveForeground),
      ),
    );
  }
}

/// An inline card, never a red page: the existing copy, one retry.
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: DecoratedBox(
            decoration: AppFinish.block(
              palette,
              highContrast: MediaQuery.highContrastOf(context),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppRhythm.section),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _StateGlyph(icon: Icons.cloud_off_rounded),
                  const SizedBox(height: AppRhythm.title),
                  Text(
                    copy.text(
                      'Moments could not load',
                      'Nie udało się wczytać Momentów',
                    ),
                    textAlign: TextAlign.center,
                    style: AppTypography.titleMedium.copyWith(
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
                  // A retry is never the lifted CTA (R5): the same button
                  // in the R7 neutral finish.
                  YoGradientFilledButton(
                    onPressed: onRetry,
                    emphasis: YoActionEmphasis.neutral,
                    child: Text(copy.text('Try again', 'Spróbuj ponownie')),
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

/// Per-pool empty copy, centred at a 320 measure, with the recorder offered
/// and — where the host can open it — a second, real action.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.secondaryActionKey,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.onPull,
    this.refreshKey,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;
  final Key? secondaryActionKey;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  /// Pull-to-refresh on the empty feed too: the reader can reload a list
  /// that is empty right now at every width, and a requested reload (the
  /// active tab re-tapped) shows the same spinner here ([refreshKey]).
  final RefreshCallback? onPull;
  final GlobalKey<RefreshIndicatorState>? refreshKey;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final secondaryLabel = secondaryActionLabel;
    final secondary = onSecondaryAction;
    const padding = EdgeInsets.symmetric(
      horizontal: AppRhythm.section,
      vertical: AppRhythm.page,
    );
    final content = _content(context, palette, secondaryLabel, secondary);
    final pull = onPull;
    if (pull == null) {
      return Center(
        key: const ValueKey('moments-discovery-empty'),
        child: SingleChildScrollView(padding: padding, child: content),
      );
    }
    return KeyedSubtree(
      key: const ValueKey('moments-discovery-empty'),
      child: RefreshIndicator(
        key: refreshKey,
        onRefresh: pull,
        color: palette.interactiveForeground,
        backgroundColor: palette.surfaceRaised,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            key: const ValueKey('moments-empty-scroll'),
            // Scrollable at any content height, so the pull always works.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - padding.vertical).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: Center(child: content),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    AppPalette palette,
    String? secondaryLabel,
    VoidCallback? secondary,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StateGlyph(icon: icon),
          const SizedBox(height: AppRhythm.title),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.titleMedium.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppRhythm.tight),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: AppRhythm.section),
          // R5 gradient; flat, because the screen's lift belongs to the
          // create action ("+" / "Utwórz").
          YoGradientFilledButton(
            onPressed: onAction,
            emphasis: YoActionEmphasis.flat,
            child: Text(actionLabel),
          ),
          if (secondaryLabel != null && secondary != null) ...[
            const SizedBox(height: AppRhythm.tight),
            OutlinedButton(
              key: secondaryActionKey,
              onPressed: secondary,
              style: AppFinish.tonalNeutral(
                palette,
                highContrast: MediaQuery.highContrastOf(context),
              ),
              child: Text(secondaryLabel),
            ),
          ],
        ],
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
