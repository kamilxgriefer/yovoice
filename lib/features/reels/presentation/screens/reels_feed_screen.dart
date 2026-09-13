import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/creator/data/services/creator_audience_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/reply_playback_arbiter.dart';
import 'package:yovoice/features/moments/presentation/widgets/yo_moments_chrome.dart';
import 'package:yovoice/features/profile/data/services/follow_service.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/models/reel_composition.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/reel_engagement_copy.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card_skeleton.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comments_view.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_engagement_bar.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_progress_row.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_overlay_measure.dart';
import 'package:yovoice/features/reels/presentation/widgets/reels_toolbar.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_feed_chrome.dart';
import 'package:yovoice/shared/widgets/overlays/immersive_overlay_atoms.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

typedef ReelExpiryTimerFactory =
    Timer Function(Duration duration, void Function() callback);

class ReelsFeedScreen extends StatefulWidget {
  const ReelsFeedScreen({
    this.service,
    this.videoBuilder,
    this.audioPlaybackFactory,
    this.videoPlaybackFactory,
    this.onCreate,
    this.isVisible,
    this.now,
    this.expiryTimerFactory,
    this.onOpenAuthor,
    this.followService,
    this.creatorAudienceService,
    this.embedded = false,
    this.immersive = false,
    this.immersiveHeader,
    super.key,
  });

  final ReelService? service;
  final ReelVideoBuilder? videoBuilder;
  final ReelAudioPlaybackFactory? audioPlaybackFactory;

  /// Supplies the video engine instead of the built-in decoder, so the
  /// autoplay policy can be exercised without a platform decoder.
  final ReelVideoPlaybackFactory? videoPlaybackFactory;

  /// Opens the composer and completes when it closes. The feed reloads after
  /// completion so a newly published Reel appears without reopening the tab.
  final Future<void> Function()? onCreate;

  /// False while the host shell or the YO Moments format switch is showing a
  /// different surface. The selected Reel remains mounted, but its player is
  /// inactive so video and audio cannot continue behind another destination.
  final ValueListenable<bool>? isVisible;
  final DateTime Function()? now;
  final ReelExpiryTimerFactory? expiryTimerFactory;

  /// What a tap on a Reel's author does. Production leaves it null and the
  /// card opens the shared profile preview; tests inject a seam so widget
  /// coverage never reaches Firestore.
  final void Function(Reel reel)? onOpenAuthor;

  /// The follow graph behind the footer's "Obserwuj". Production leaves it
  /// null and the feed resolves the real service once; widget coverage
  /// injects a double, and a host with no Firebase app gets no control at
  /// all rather than a button that cannot answer.
  final FollowService? followService;

  /// Public, server-written Creator audience projection used by every Reel
  /// card. Tests may inject a deterministic source; production resolves the
  /// real publicProfiles stream once for the feed.
  final CreatorAudienceService? creatorAudienceService;
  final bool embedded;

  /// Fill a narrow host's available viewport, while its bottom navigation
  /// remains owned by the shell. Wide hosts retain the portrait review frame.
  final bool immersive;

  /// Row-1 pieces the HOST owns (the format switch, Back, Create). Named
  /// slots rather than one opaque widget, so the chrome can place them on
  /// its own measured row.
  final ImmersiveFeedHeaderSlots? immersiveHeader;

  @override
  State<ReelsFeedScreen> createState() => _ReelsFeedScreenState();
}

class _ReelsFeedScreenState extends State<ReelsFeedScreen>
    with WidgetsBindingObserver {
  static const int _maxEmptyPagesPerLoad = 4;
  // Browsers clamp timer delays to a signed 32-bit millisecond value. Reels
  // can remain available for 30 days, so arming the whole remaining duration
  // on web can overflow and wake immediately in a tight reschedule loop.
  static const Duration _maximumExpiryTimerDelay = Duration(
    milliseconds: 0x7fffffff,
  );

  late final ReelService _service = widget.service ?? ReelService();
  final PageController _pageController = PageController();

  /// One sound preference for the whole feed, so it is turned on once instead
  /// of on every Reel. It starts off because the first Reel starts itself, and
  /// an ungestured start must not be audible.
  final ValueNotifier<bool> _soundOn = ValueNotifier<bool>(false);
  List<Reel> _items = const <Reel>[];
  String? _cursor;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _creating = false;
  int _selected = 0;
  final Set<String> _reporting = <String>{};
  final Set<String> _deleting = <String>{};
  final Map<String, String> _deleteRequestIds = <String, String>{};

  /// Reels whose like call has not answered yet. The optimistic state is on
  /// the item itself; this only keeps a second tap from racing the first and
  /// tells a late comment read whose engagement wins.
  final Set<String> _likePending = <String>{};

  /// Wide layout only: whether the context panel is currently showing the
  /// selected Reel's thread. Narrow and medium widths open a sheet instead,
  /// which owns its own lifetime.
  bool _commentsPanelOpen = false;

  /// The playback floor shared by the docked thread and the Reel beside it.
  ///
  /// It exists only for the WIDE layout, because that is the only place a
  /// Reel deliberately keeps playing while its conversation is open (D5).
  /// The phone sheet covers the media and the card already suspends on route
  /// currency, so the sheet's thread arbitrates its replies against each
  /// other and needs nothing from here.
  late final ReplyPlaybackArbiter _panelArbiter = ReplyPlaybackArbiter()
    ..addListener(_onVoiceCommentFloorChanged);

  /// True while a voice comment is sounding in the docked thread, which is
  /// exactly when the Reel must be silent.
  bool _voiceCommentSounding = false;
  Timer? _expiryTimer;
  StreamSubscription<String?>? _identitySubscription;
  String? _viewerId;
  int _loadGeneration = 0;
  int _identityRevision = 0;
  bool _ownOnly = false;
  bool _includeSeen = false;
  bool _hasWatchedReels = false;
  double _chromeHeight = 0;
  bool _followServiceResolved = false;
  FollowService? _followService;
  late final CreatorAudienceService _defaultCreatorAudienceService =
      CreatorAudienceService();

  CreatorAudienceService get _creatorAudiences =>
      widget.creatorAudienceService ?? _defaultCreatorAudienceService;

  /// The follow graph for every card in this feed, resolved once.
  ///
  /// A host without a Firebase app — every widget test that pumps this feed —
  /// cannot construct one at all. That is not an error here: it means the
  /// graph is genuinely unavailable, so the footer draws no follow control
  /// instead of a button whose only possible answer is a crash.
  FollowService? get _follows {
    final injected = widget.followService;
    if (injected != null) return injected;
    if (_followServiceResolved) return _followService;
    _followServiceResolved = true;
    try {
      _followService = FollowService();
    } catch (_) {
      _followService = null;
    }
    return _followService;
  }

  DateTime get _now => (widget.now ?? DateTime.now)().toUtc();
  ReelExpiryTimerFactory get _timerFactory =>
      widget.expiryTimerFactory ?? Timer.new;
  bool get _isHostVisible => widget.isVisible?.value ?? true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.isVisible?.addListener(_handleHostVisibilityChanged);
    _viewerId = _service.currentUserId;
    _identitySubscription = _service.identityChanges.listen(
      _identityChanged,
      onError: (Object error, StackTrace stack) {
        if (!mounted) return;
        _loadGeneration++;
        _identityRevision++;
        _expiryTimer?.cancel();
        setState(() {
          _items = const [];
          _cursor = null;
          _loading = false;
          _loadingMore = false;
          _creating = false;
          _error = error;
        });
      },
    );
    _load(reset: true);
  }

  void _identityChanged(String? uid) {
    if (!mounted || uid == _viewerId) return;
    _loadGeneration++;
    _identityRevision++;
    _expiryTimer?.cancel();
    setState(() {
      _viewerId = uid;
      _items = const [];
      _cursor = null;
      _selected = 0;
      _hasMore = true;
      _loadingMore = false;
      _creating = false;
      _error = null;
      _reporting.clear();
      _deleting.clear();
      _deleteRequestIds.clear();
      // Engagement belongs to the account that produced it. A pending like
      // and an open thread from the previous sign-in are both discarded.
      _likePending.clear();
      _commentsPanelOpen = false;
    });
    _load(reset: true);
  }

  bool _isCurrentRequest(int generation, String? uid) =>
      mounted &&
      generation == _loadGeneration &&
      uid == _viewerId &&
      uid == _service.currentUserId;

  void _selectAudience(bool ownOnly) {
    if (_ownOnly == ownOnly) return;
    setState(() {
      _ownOnly = ownOnly;
      _includeSeen = false;
      _hasWatchedReels = false;
    });
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant ReelsFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.isVisible, widget.isVisible)) {
      oldWidget.isVisible?.removeListener(_handleHostVisibilityChanged);
      widget.isVisible?.addListener(_handleHostVisibilityChanged);
      if (_isHostVisible) _revalidateAvailability();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isHostVisible) {
      _revalidateAvailability();
    }
  }

  void _handleHostVisibilityChanged() {
    if (_isHostVisible) {
      _revalidateAvailability();
      _prefetchNeighbor();
    }
  }

  void _prefetchNeighbor() {
    if (!_isHostVisible || _selected + 1 >= _items.length) return;
    unawaited(_service.prefetchMediaUri(_items[_selected + 1].id));
  }

  @override
  void dispose() {
    _loadGeneration++;
    _identitySubscription?.cancel();
    _expiryTimer?.cancel();
    widget.isVisible?.removeListener(_handleHostVisibilityChanged);
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _soundOn.dispose();
    _panelArbiter
      ..removeListener(_onVoiceCommentFloorChanged)
      ..dispose();
    super.dispose();
  }

  /// A voice comment took the floor, or gave it back.
  ///
  /// Deferred out of the current frame when it arrives mid-frame: a
  /// mini-player releases the floor from its own `dispose`, which runs while
  /// the tree is being rebuilt, and calling `setState` there would throw.
  void _onVoiceCommentFloorChanged() {
    if (!mounted) return;
    final sounding = _panelArbiter.activeReplyId != null;
    if (sounding == _voiceCommentSounding) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onVoiceCommentFloorChanged();
      });
      return;
    }
    setState(() => _voiceCommentSounding = sounding);
  }

  void _revalidateAvailability() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (!mounted) return;
    final now = _now;
    final available = _items
        .where((item) => item.availability.isAvailableAt(now))
        .toList(growable: false);
    final changed = available.length != _items.length;
    if (changed) {
      final selected = available.isEmpty
          ? 0
          : _selected.clamp(0, available.length - 1);
      setState(() {
        _items = available;
        _selected = selected;
      });
      if (available.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_pageController.hasClients) return;
          final current = _pageController.page?.round();
          if (current != selected) _pageController.jumpToPage(selected);
        });
      }
    }
    DateTime? nearest;
    for (final item in available) {
      final deadline = item.availability.contentExpiresAt;
      if (deadline != null && (nearest == null || deadline.isBefore(nearest))) {
        nearest = deadline;
      }
    }
    if (nearest == null) return;
    final remaining = nearest.difference(now);
    final delay = remaining > _maximumExpiryTimerDelay
        ? _maximumExpiryTimerDelay
        : remaining.isNegative
        ? Duration.zero
        : remaining;
    _expiryTimer = _timerFactory(delay, () {
      _expiryTimer = null;
      // A long availability window is deliberately split into browser-safe
      // chunks. Re-read the wall clock after each chunk; only the exact
      // deadline removes content.
      _revalidateAvailability();
    });
  }

  Future<void> _load({required bool reset}) async {
    if ((!reset && (_loadingMore || !_hasMore))) return;
    final generation = reset ? ++_loadGeneration : _loadGeneration;
    final viewer = _viewerId;
    final ownOnly = _ownOnly;
    setState(() {
      if (reset) {
        _loading = true;
        _loadingMore = false;
        _items = const [];
        _selected = 0;
        _cursor = null;
        _hasMore = true;
        _hasWatchedReels = false;
        _reporting.clear();
        _deleting.clear();
        _likePending.clear();
        _expiryTimer?.cancel();
      } else {
        _loadingMore = true;
      }
      _error = null;
    });
    try {
      var requestCursor = reset ? null : _cursor;
      final loaded = <Reel>[];
      final seenCursors = <String>{};
      for (var request = 0; request < _maxEmptyPagesPerLoad; request++) {
        final page = await _service.fetchFeed(
          cursor: requestCursor,
          limit: 10,
          scope: ownOnly ? ReelFeedScope.own : ReelFeedScope.discover,
          includeSeen: !ownOnly && _includeSeen,
        );
        if (!_isCurrentRequest(generation, viewer)) return;
        loaded.addAll(
          page.items.where((item) => !ownOnly || item.authorId == viewer),
        );
        final nextCursor = page.nextCursor;
        requestCursor = nextCursor;
        if (loaded.isNotEmpty || nextCursor == null) break;
        if (!seenCursors.add(nextCursor)) {
          throw const FormatException('Yeel feed cursor did not advance.');
        }
      }
      // A drained unseen feed is different from an empty catalogue. The
      // existing response shape is frozen, so verify with the authorized
      // includeSeen query before offering a replay action.
      var hasWatched = false;
      if (loaded.isEmpty &&
          (reset || _items.isEmpty) &&
          requestCursor == null &&
          !ownOnly &&
          !_includeSeen) {
        final seen = await _service.fetchFeed(
          limit: 1,
          includeSeen: true,
          warmLeadingMedia: false,
        );
        if (!_isCurrentRequest(generation, viewer)) return;
        hasWatched = seen.items.isNotEmpty;
      }
      if (!mounted || !_isCurrentRequest(generation, viewer)) return;
      setState(() {
        final combined = reset ? loaded : <Reel>[..._items, ...loaded];
        _items = <Reel>[
          for (final entry in {
            for (final item in combined) item.id: item,
          }.values)
            entry,
        ];
        _cursor = requestCursor;
        _hasMore = requestCursor != null;
        _hasWatchedReels = hasWatched;
        _error = loaded.isEmpty && requestCursor != null
            ? const _ReelFeedScanPaused()
            : null;
      });
      _revalidateAvailability();
      _prefetchNeighbor();
    } catch (error) {
      if (_isCurrentRequest(generation, viewer)) setState(() => _error = error);
    } finally {
      if (_isCurrentRequest(generation, viewer)) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _report(Reel reel) async {
    if (_reporting.contains(reel.id)) return;
    final generation = _loadGeneration;
    final viewer = _viewerId;
    final copy = AppLocalizations.of(context);
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: false,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
      backgroundColor: Colors.transparent,
      builder: (context) => _ReelReportSheet(authorName: reel.authorName),
    );
    if (reason == null || !_isCurrentRequest(generation, viewer)) return;
    setState(() => _reporting.add(reel.id));
    try {
      await _service.reportReel(reel.id, reason: reason);
      if (!mounted || !_isCurrentRequest(generation, viewer)) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              copy.text(
                'Thanks. The Yeel was sent for review.',
                'Dziękujemy. Yeel został wysłany do sprawdzenia.',
              ),
            ),
          ),
        );
    } catch (_) {
      if (!mounted || !_isCurrentRequest(generation, viewer)) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              copy.text(
                'The report could not be sent. Try again.',
                'Nie udało się wysłać zgłoszenia. Spróbuj ponownie.',
              ),
            ),
          ),
        );
    } finally {
      if (_isCurrentRequest(generation, viewer)) {
        setState(() => _reporting.remove(reel.id));
      }
    }
  }

  /// Replaces one Reel in place, preserving feed order and identity.
  ///
  /// Must be called inside a [setState]; `_items` is replaced rather than
  /// mutated because an empty feed is a `const` list.
  void _replaceReel(String id, Reel Function(Reel item) update) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    _items = <Reel>[..._items]..[index] = update(_items[index]);
  }

  /// Adopts server-authoritative engagement reported by an open thread.
  void _applyEngagement(Reel updated) {
    if (!mounted) return;
    setState(() {
      _replaceReel(updated.id, (item) {
        // A like is still in flight for this Reel, so its own result — not a
        // comment read that started before it — is the authority on the like
        // fields. Adopting them here would undo the optimistic toggle and
        // make the heart flicker back and forth.
        if (_likePending.contains(updated.id)) {
          return item.copyWithEngagement(commentCount: updated.commentCount);
        }
        return item.copyWithEngagement(
          likeCount: updated.likeCount,
          commentCount: updated.commentCount,
          callerLiked: updated.callerLiked,
        );
      });
    });
  }

  void _announce(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }

  /// Toggles this viewer's like optimistically and reconciles with the server.
  ///
  /// The optimistic count moves by exactly one and is replaced by the returned
  /// aggregate on success, or restored to the pre-tap values on any refusal.
  /// The client never keeps a count it computed itself.
  Future<void> _toggleLike(Reel reel) async {
    if (_likePending.contains(reel.id)) return;
    final generation = _loadGeneration;
    final viewer = _viewerId;
    if (viewer == null) return;
    if (!_service.isEmailVerified) {
      // A live control that explains its gate, rather than a call the backend
      // is certain to refuse and a budget spent on the refusal.
      _announce(reelVerificationNotice(context));
      return;
    }
    final liked = !reel.callerLiked;
    final restoredLiked = reel.callerLiked;
    final restoredCount = reel.likeCount;
    setState(() {
      _likePending.add(reel.id);
      _replaceReel(
        reel.id,
        (item) => item.copyWithEngagement(
          callerLiked: liked,
          likeCount: liked
              ? item.likeCount + 1
              : (item.likeCount > 0 ? item.likeCount - 1 : 0),
        ),
      );
    });
    try {
      final result = await _service.setLike(reel.id, liked: liked);
      if (!mounted || !_isCurrentRequest(generation, viewer)) return;
      setState(() {
        _replaceReel(
          reel.id,
          (item) => item.copyWithEngagement(
            callerLiked: result.liked,
            likeCount: result.likeCount,
          ),
        );
      });
    } catch (error) {
      if (!mounted || !_isCurrentRequest(generation, viewer)) return;
      setState(() {
        _replaceReel(
          reel.id,
          (item) => item.copyWithEngagement(
            callerLiked: restoredLiked,
            likeCount: restoredCount,
          ),
        );
      });
      _announce(
        reelEngagementMessage(
          context,
          error,
          action: ReelEngagementAction.like,
        ),
      );
    } finally {
      if (_isCurrentRequest(generation, viewer)) {
        setState(() => _likePending.remove(reel.id));
      }
    }
  }

  /// Opens the thread the way this width can host it.
  ///
  /// Wide toggles the context panel that is already on screen; anything
  /// narrower opens the sheet. Both host the same [ReelCommentsView].
  void _openComments(Reel reel, {required bool wide}) {
    if (wide) {
      // D5 (ADR-170 amendment): the docked panel stands BESIDE the Reel, not
      // in front of it, so opening it neither hides the media nor suspends
      // playback. The phone sheet does cover the Reel and still suspends —
      // through the card's own route currency, one line below.
      setState(() => _commentsPanelOpen = !_commentsPanelOpen);
      return;
    }
    unawaited(
      showReelCommentsSheet(
        context,
        reel: reel,
        service: _service,
        onReelUpdated: _applyEngagement,
      ),
    );
  }

  /// Moves to the next loaded Reel, exactly as a swipe does.
  ///
  /// The pager owns the page change, so the new Reel then follows the
  /// existing autoplay policy on its own: a video starts silent, a photo
  /// waits for a tap (ADR-170). Nothing here starts anything.
  void _showNext() {
    if (_selected + 1 >= _items.length || !_pageController.hasClients) return;
    unawaited(
      _pageController.nextPage(
        duration: AppMotion.resolve(context, AppMotion.standard),
        curve: AppMotion.standardCurve,
      ),
    );
  }

  Future<void> _create() async {
    final action = widget.onCreate;
    if (action == null || _creating) return;
    setState(() => _creating = true);
    final viewer = _viewerId;
    final identityRevision = _identityRevision;
    try {
      await action();
      if (mounted &&
          identityRevision == _identityRevision &&
          viewer == _viewerId &&
          viewer == _service.currentUserId) {
        await _load(reset: true);
      }
    } finally {
      if (mounted &&
          identityRevision == _identityRevision &&
          viewer == _viewerId) {
        setState(() => _creating = false);
      }
    }
  }

  Future<void> _delete(Reel reel) async {
    if (_deleting.contains(reel.id)) return;
    final generation = _loadGeneration;
    final viewer = _viewerId;
    final copy = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.text('Delete Yeel?', 'Usunąć Yeel?')),
        content: Text(
          copy.text(
            'This removes the Yeel from the feed. This action cannot be undone.',
            'Yeel zniknie z kanału. Tej operacji nie można cofnąć.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(copy.text('Cancel', 'Anuluj')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(copy.text('Delete', 'Usuń')),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !_isCurrentRequest(generation, viewer) ||
        !_service.isCurrentUserAuthor(reel)) {
      return;
    }
    final requestId = _deleteRequestIds.putIfAbsent(
      reel.id,
      ReelPublishSession.newRequestId,
    );
    setState(() => _deleting.add(reel.id));
    try {
      await _service.deleteReel(reel.id, requestId: requestId);
      if (!mounted || !_isCurrentRequest(generation, viewer)) return;
      _deleteRequestIds.remove(reel.id);
      setState(() {
        _items = _items.where((item) => item.id != reel.id).toList();
        _selected = _items.isEmpty ? 0 : _selected.clamp(0, _items.length - 1);
      });
      _revalidateAvailability();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(copy.text('Yeel deleted.', 'Yeel został usunięty.')),
          ),
        );
    } catch (_) {
      if (!mounted || !_isCurrentRequest(generation, viewer)) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              copy.text(
                'The Yeel could not be deleted. Try again.',
                'Nie udało się usunąć Yeela. Spróbuj ponownie.',
              ),
            ),
          ),
        );
    } finally {
      if (_isCurrentRequest(generation, viewer)) {
        setState(() => _deleting.remove(reel.id));
      }
    }
  }

  /// Everything below the toolbar: the states, the pager, and the transient
  /// load-more surfaces that sit over it.
  ///
  /// [stage] is the box the feed actually got — after the wide panel took its
  /// column — so the card geometry is derived from real space, never from a
  /// device label.
  Widget _buildStage(
    BuildContext context,
    BoxConstraints stage,
    _StageMetrics metrics, {
    required bool wide,
  }) {
    final copy = AppLocalizations.of(context);
    final pagerPadding = EdgeInsets.fromLTRB(
      metrics.gutter,
      metrics.padTop,
      metrics.gutter,
      metrics.padBottom,
    );

    // Every state stands in the middle of the stage and scrolls rather than
    // overflowing when the text is large and the window is short.
    Widget scrollableState(Widget child) {
      return SingleChildScrollView(
        primary: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: stage.hasBoundedHeight ? stage.maxHeight : 0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[child],
          ),
        ),
      );
    }

    if (_loading || (_items.isEmpty && _loadingMore)) {
      // The skeleton holds the exact card geometry so nothing jumps when the
      // first page lands; the indicator above it owns the live region.
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Padding(
            padding: pagerPadding,
            child: ReelCardSkeleton(borderRadius: metrics.cardRadius),
          ),
          scrollableState(
            YoLoadingIndicator(
              message: copy.text('Loading Yeels', 'Ładowanie Yeels'),
            ),
          ),
        ],
      );
    }
    if (_error is _ReelFeedScanPaused && _items.isEmpty) {
      // Nothing is loading here: the first batch simply held nothing this
      // viewer can see. Saying "Loading Reels" would have been a lie.
      return scrollableState(
        YoEmptyState(
          icon: Icons.travel_explore_rounded,
          title: copy.text('No Yeels yet', 'Nie ma jeszcze Yeels'),
          subtitle: copy.text(
            'More Yeels are available to check.',
            'Możesz sprawdzić kolejne Yeels.',
          ),
          actionLabel: copy.text('Load more', 'Wczytaj więcej'),
          onAction: () => _load(reset: false),
        ),
      );
    }
    if (_error != null && _items.isEmpty) {
      return scrollableState(
        YoErrorState(
          error: _error,
          // Without a Reels-specific fallback the body falls back to the
          // generic sentence, which is word for word the headline the state
          // already draws above it. Board 06 passes one; so does this.
          message: friendlyErrorMessage(
            _error!,
            copy: copy,
            fallback: copy.contextualText(
              'reels.feedUnavailable',
              'Yeels could not be loaded. Try again.',
              'Nie udało się wczytać Yeels. Spróbuj ponownie.',
            ),
          ),
          onRetry: () => _load(reset: _cursor == null),
        ),
      );
    }
    if (_items.isEmpty) {
      return scrollableState(
        YoEmptyState(
          icon: Icons.smart_display_rounded,
          title: _ownOnly
              ? copy.text(
                  'No Yeels of your own yet',
                  'Nie masz jeszcze własnych Yeels',
                )
              : _hasWatchedReels
              ? copy.text('You’re all caught up', 'Wszystko obejrzane')
              : copy.text('No Yeels yet', 'Nie ma jeszcze Yeels'),
          subtitle: _hasWatchedReels
              ? copy.text(
                  'Watch Yeels again or come back later.',
                  'Obejrzyj Yeels ponownie lub wróć później.',
                )
              : copy.text(
                  'Published photos and short videos will appear here.',
                  'Opublikowane zdjęcia i krótkie filmy pojawią się tutaj.',
                ),
          actionLabel: _hasWatchedReels
              ? copy.text('Watch again', 'Obejrzyj ponownie')
              : widget.onCreate == null
              ? null
              : copy.text('Create Yeel', 'Utwórz Yeel'),
          onAction: _hasWatchedReels
              ? () {
                  setState(() => _includeSeen = true);
                  _load(reset: true);
                }
              : _creating
              ? null
              : _create,
        ),
      );
    }

    // The transient surfaces align with the card, not with the window.
    final mediaWidth = math.min(
      math.min(520.0, math.max(0.0, stage.maxWidth - 2 * metrics.gutter)),
      stage.hasBoundedHeight
          ? math.max(
                  0.0,
                  stage.maxHeight - metrics.padTop - metrics.padBottom,
                ) *
                9 /
                16
          : 520.0,
    );

    // The width the card — and so the media frame — will really take, read
    // from the footer bar's own derivation rather than guessed. The `›`
    // plate is anchored to THAT, not to the stage column: a height-bound
    // frame is far narrower than its column, and a plate measured from the
    // column lands in open background beside the Reel it advances.
    final cardViewport = BoxConstraints(
      maxWidth: math.min(
        _FeedPager.maxCardWidth,
        math.max(0.0, stage.maxWidth - 2 * metrics.gutter),
      ),
      maxHeight: stage.hasBoundedHeight
          ? math.max(0.0, stage.maxHeight - metrics.padTop - metrics.padBottom)
          : double.infinity,
    );
    final selectedReel = _selected >= 0 && _selected < _items.length
        ? _items[_selected]
        : _items.first;
    final frameWidth = ReelStageFooterBar.frameWidthFor(
      context,
      cardViewport,
      hasCaption: selectedReel.composition.caption.isNotEmpty,
    );
    // Below its own floor the card gives way to the overlay composition and
    // fills the column; then the column edge IS the frame edge.
    final nextPlateInset = frameWidth < ReelStageFooterBar.minimumFrameWidth
        ? metrics.gutter + AppRhythm.title
        : math.max(
            metrics.gutter,
            (stage.maxWidth - frameWidth) / 2 + AppRhythm.title,
          );
    final noticeWidth = math.max(
      240.0,
      math.min(mediaWidth + 32, math.max(0.0, stage.maxWidth - 32)),
    );

    Widget buildFeed({required bool visible}) => Stack(
      children: <Widget>[
        Positioned.fill(
          child: _FeedPager(
            items: _items,
            controller: _pageController,
            service: _service,
            selectedIndex: _selected,
            isVisible: visible,
            padding: pagerPadding,
            cardRadius: metrics.cardRadius,
            immersive: metrics.immersive,
            mediaTopInset: metrics.immersive ? _chromeHeight : 0,
            // Wide already carries the author and the caption in the docked
            // panel; burning them over the video a second time is noise.
            // Board 08 gives every non-immersive width a real footer bar
            // under the media, so identity lives on the card at every width
            // and the docked panel is the conversation alone.
            showIdentity: true,
            followService: _follows,
            creatorAudienceService: _creatorAudiences,
            videoBuilder: widget.videoBuilder,
            audioPlaybackFactory: widget.audioPlaybackFactory,
            videoPlaybackFactory: widget.videoPlaybackFactory,
            soundOn: _soundOn,
            onReport: _report,
            onDelete: _delete,
            onOpenAuthor: widget.onOpenAuthor,
            likePending: _likePending,
            commentsOpenIndex: wide && _commentsPanelOpen ? _selected : null,
            // A voice comment never plays over the Reel it answers. Only the
            // selected page can be sounding, and only the wide layout keeps
            // the Reel running beside an open thread at all.
            suspendPlaybackIndex: wide && _voiceCommentSounding
                ? _selected
                : null,
            onLike: _viewerId == null ? null : _toggleLike,
            onComments: (reel) => _openComments(reel, wide: wide),
            onChanged: (index) {
              setState(() => _selected = index);
              _prefetchNeighbor();
              if (index >= _items.length - 3) _load(reset: false);
            },
          ),
        ),
        // › next: pointer widths have no swipe, so the way to the next Reel
        // has to be on screen. Absent below 600 (touch paging is the phone's
        // primary path) and absent on the last loaded item, because a
        // control that cannot act is worse than none.
        if (!metrics.immersive && _selected + 1 < _items.length)
          PositionedDirectional(
            end: nextPlateInset,
            top: 0,
            bottom: metrics.padBottom,
            child: Center(
              child: OverlayPlateButton(
                key: const ValueKey<String>('reel-next-action'),
                icon: Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                semanticLabel: copy.text('Next Yeel', 'Następny Yeel'),
                onTap: _showNext,
              ),
            ),
          ),
        if (_error != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: noticeWidth),
                child: _FeedLoadMoreError(
                  scanPaused: _error is _ReelFeedScanPaused,
                  onRetry: () => _load(reset: false),
                ),
              ),
            ),
          )
        else if (_loadingMore)
          PositionedDirectional(
            end: metrics.gutter,
            bottom: 16,
            child: const YoLoadingIndicator(),
          ),
      ],
    );

    final visibility = widget.isVisible;
    return visibility == null
        ? buildFeed(visible: true)
        : ValueListenableBuilder<bool>(
            valueListenable: visibility,
            builder: (context, visible, child) => buildFeed(visible: visible),
          );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final discoverLabel = copy.text('Discover', 'Odkrywaj');
    final ownLabel = copy.text('Your Yeels', 'Twoje Yeels');
    final createLabel = copy.text('Create Yeel', 'Utwórz Yeel');
    final refreshLabel = copy.text('Refresh', 'Odśwież');
    final filtersLabel = copy.text('Filters', 'Filtry');
    final palette = context.appPalette;
    final body = Material(
      key: const ValueKey<String>('reels-stage'),
      // Deliberately transparent: the moments-studio canvas the destination
      // already paints must show around the card, exactly as it does on the
      // Voice half. The card is the only surface on the stage.
      type: MaterialType.transparency,
      child: SafeArea(
        top: widget.embedded,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final layout = YoMomentsLayout.of(
              constraints.maxWidth,
              textScale: MediaQuery.textScalerOf(context).scale(1),
            );
            final compactChrome = widget.immersive && !layout.showsLocalPanel;
            final immersive = widget.immersive && layout.isNarrow;
            final metrics = _StageMetrics.of(
              constraints.maxWidth,
              immersive: immersive,
            );
            // The layout, not a device label, decides where a thread can be
            // hosted: beside the feed when there is room for a panel, in a
            // sheet over it when there is not.
            final wide = constraints.maxWidth >= _panelBreakpoint;
            final showPanel = wide && _items.isNotEmpty;
            // The pool filters move into a local panel only where the third
            // column fits BESIDE the docked conversation — the Voice half
            // takes its panel one step earlier (wide-2) because it has no
            // thread column to make room for.
            final showLocalPanel =
                layout.tier == YoMomentsLayoutTier.wide3 && !immersive;
            final stage = LayoutBuilder(
              builder: (context, stage) =>
                  _buildStage(context, stage, metrics, wide: wide),
            );
            final selected = _items.isEmpty
                ? null
                : _items[_selected.clamp(0, _items.length - 1)];
            final next = _items.isEmpty || _selected + 1 >= _items.length
                ? null
                : _items[_selected + 1];
            // Keep the stage's ancestry stable across width changes. A key
            // on ReelCard cannot retain its player if an ancestor is replaced.
            final below = Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Three KEYED slots, always in this order. Without the keys
                // a panel appearing beside the stage would be matched by
                // position, the stage's element would be discarded with it,
                // and the card would rebuild — taking a second decoder and
                // the viewer's playback position with it
                // (`reels_immersive_redesign_test.dart` "one decoder survives
                // responsive reflow").
                KeyedSubtree(
                  key: const ValueKey<String>('reels-local-slot'),
                  child: showLocalPanel
                      ? _ReelsLocalPanel(
                          width: layout.localPanelWidth,
                          ownOnly: _ownOnly,
                          onAudienceSelected: _selectAudience,
                          onRefresh: _loading ? null : () => _load(reset: true),
                          showCreate: widget.onCreate != null,
                          onCreate: _creating ? null : _create,
                        )
                      : const SizedBox.shrink(),
                ),
                Expanded(
                  key: const ValueKey<String>('reels-stage-slot'),
                  child: stage,
                ),
                KeyedSubtree(
                  key: const ValueKey<String>('reels-thread-slot'),
                  child: showPanel && selected != null
                      ? SizedBox(
                          width: _panelWidthFor(constraints.maxWidth),
                          child: _WideContextPanel(
                            reel: selected,
                            next: next,
                            service: _service,
                            commentsOpen: _commentsPanelOpen,
                            arbiter: _panelArbiter,
                            onReelUpdated: _applyEngagement,
                            onComments: () =>
                                _openComments(selected, wide: true),
                            onOpenNext: _showNext,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            );
            return CustomMultiChildLayout(
              delegate: _ReelsViewportLayout(
                overlayChrome: immersive && _items.isNotEmpty,
              ),
              children: [
                LayoutId(id: _ReelsViewportSlot.content, child: below),
                LayoutId(
                  id: _ReelsViewportSlot.chrome,
                  child: ReelOverlayMeasure(
                    key: const ValueKey('reels-chrome'),
                    onSize: (size) {
                      if (mounted && (size.height - _chromeHeight).abs() > .5) {
                        setState(() => _chromeHeight = size.height);
                      }
                    },
                    child: compactChrome
                        ? ImmersiveFeedChrome(
                            gutter: metrics.toolbarGutter,
                            formatSwitch: widget.immersiveHeader?.formatSwitch,
                            leading: widget.immersiveHeader?.leading,
                            // The host header owns CREATE when there is one;
                            // a standalone immersive feed keeps its own, so
                            // creation is never silently unreachable.
                            trailing:
                                widget.immersiveHeader?.trailing ??
                                (widget.onCreate == null
                                    ? null
                                    : OverlayPlateButton(
                                        key: const ValueKey(
                                          'reels-create-persistent',
                                        ),
                                        icon: Icons.add_rounded,
                                        semanticLabel: createLabel,
                                        onTap: _creating ? null : _create,
                                      )),
                            filters: <ImmersiveChromeOption>[
                              ImmersiveChromeOption(
                                key: const ValueKey<String>(
                                  'reels-discover-filter',
                                ),
                                label: discoverLabel,
                              ),
                              ImmersiveChromeOption(
                                key: const ValueKey<String>('reels-own-filter'),
                                label: ownLabel,
                              ),
                            ],
                            selectedFilterIndex: _ownOnly ? 1 : 0,
                            onFilterSelected: (index) =>
                                _selectAudience(index == 1),
                            filterGroupLabel: filtersLabel,
                            filterTrailing: OverlayPlateButton(
                              key: const ValueKey('reels-refresh'),
                              icon: Icons.refresh_rounded,
                              semanticLabel: refreshLabel,
                              onTap: _loading ? null : () => _load(reset: true),
                            ),
                          )
                        : DecoratedBox(
                            decoration: const BoxDecoration(),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // At wide-3 the same three controls live in
                                // the local panel beside the stage; drawing
                                // both would be two filter rows for one pool.
                                if (!showLocalPanel)
                                  ReelsToolbar(
                                    gutter: metrics.toolbarGutter,
                                    ownOnly: _ownOnly,
                                    onAudienceSelected: _selectAudience,
                                    onRefresh: _loading
                                        ? null
                                        : () => _load(reset: true),
                                    showCreate: widget.onCreate != null,
                                    onCreate: _creating ? null : _create,
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    // Nested inside YO Moments this resolves to the child untouched; opened
    // on its own the feed still stands on the destination's own canvas.
    final page = YoPageBackground(section: YoPageSection.moments, child: body);
    if (widget.embedded) return page;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(copy.text('Yeels', 'Yeels')),
        actions: widget.onCreate == null
            ? null
            : <Widget>[
                IconButton(
                  tooltip: copy.text('Create Yeel', 'Utwórz Yeel'),
                  onPressed: _creating ? null : _create,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
      ),
      body: page,
    );
  }
}

/// Slot width at which a thread can be docked beside the stage instead of
/// covering it — `YoMomentsLayout`'s own wide-2 step, so the two formats of
/// one destination change shape at the same width.
const double _panelBreakpoint = YoMomentsLayout.mediumMax;

/// The docked conversation is 360 wide, and 400 once the slot is roomy
/// enough that the extra 40 costs the stage nothing — the same rule and the
/// same numbers as the expanded Voice Moment (board 07).
double _panelWidthFor(double slotWidth) => slotWidth >= 1440 ? 400 : 360;

/// `AppRadius.lg` as a number, for the corner the card, the skeleton and the
/// clip all have to agree on.
const double _cardRadius = 20;

enum _ReelsViewportSlot { content, chrome }

/// Measure the real, localized chrome first. Empty/error content is placed
/// below it; a populated immersive pager occupies the whole viewport beneath
/// it. No guessed header height or post-frame resize is needed.
class _ReelsViewportLayout extends MultiChildLayoutDelegate {
  _ReelsViewportLayout({required this.overlayChrome});
  final bool overlayChrome;

  @override
  void performLayout(Size size) {
    final chrome = layoutChild(
      _ReelsViewportSlot.chrome,
      BoxConstraints(
        maxWidth: size.width,
        minWidth: size.width,
        maxHeight: size.height,
      ),
    );
    final top = overlayChrome ? 0.0 : chrome.height;
    layoutChild(
      _ReelsViewportSlot.content,
      BoxConstraints.tight(Size(size.width, math.max(0, size.height - top))),
    );
    positionChild(_ReelsViewportSlot.content, Offset(0, top));
    positionChild(_ReelsViewportSlot.chrome, Offset.zero);
  }

  @override
  bool shouldRelayout(_ReelsViewportLayout oldDelegate) =>
      oldDelegate.overlayChrome != overlayChrome;
}

/// Stage geometry for the width the feed was given.
///
/// One card, three densities: the gutters and the corner grow with the room
/// available, and the card itself is always the 9:16 media inscribed in what
/// is left.
@immutable
class _StageMetrics {
  const _StageMetrics({
    required this.toolbarGutter,
    required this.gutter,
    required this.padTop,
    required this.padBottom,
    required this.cardRadius,
    required this.immersive,
  });

  factory _StageMetrics.of(double width, {bool immersive = false}) {
    if (immersive) {
      return const _StageMetrics(
        toolbarGutter: 12,
        gutter: 0,
        padTop: 0,
        padBottom: 0,
        cardRadius: 0,
        immersive: true,
      );
    }
    if (width >= _panelBreakpoint) {
      return const _StageMetrics(
        // The chrome row matches the Voice half's filter row, so the two
        // formats of one destination share a rhythm instead of each having
        // their own.
        toolbarGutter: YoMomentsLayout.gutterInside,
        gutter: YoMomentsLayout.gutterInside,
        padTop: 8,
        padBottom: 24,
        // One radius with the Voice card (board 08 §5.1): a destination that
        // switches format must not switch corner language with it.
        cardRadius: _cardRadius,
        immersive: false,
      );
    }
    if (width >= YoMomentsLayout.narrowMax) {
      return const _StageMetrics(
        toolbarGutter: YoMomentsLayout.gutterInside,
        gutter: YoMomentsLayout.gutterInside,
        padTop: 8,
        padBottom: 16,
        cardRadius: _cardRadius,
        immersive: false,
      );
    }
    return const _StageMetrics(
      toolbarGutter: YoMomentsLayout.narrowGutter,
      gutter: YoMomentsLayout.narrowGutter,
      padTop: 4,
      padBottom: 10,
      cardRadius: _cardRadius,
      immersive: false,
    );
  }

  final double toolbarGutter;
  final double gutter;
  final double padTop;
  final double padBottom;
  final double cardRadius;

  /// True only for the phone stage that IS the viewport: gutter 0, radius 0,
  /// chrome overlaid instead of stacked above.
  final bool immersive;
}

class _FeedPager extends StatelessWidget {
  const _FeedPager({
    required this.items,
    required this.controller,
    required this.service,
    required this.selectedIndex,
    required this.isVisible,
    required this.onChanged,
    required this.onReport,
    required this.onDelete,
    required this.onComments,
    required this.likePending,
    required this.padding,
    required this.cardRadius,
    required this.showIdentity,
    required this.immersive,
    required this.mediaTopInset,
    this.onLike,
    this.onOpenAuthor,
    this.followService,
    this.creatorAudienceService,
    this.commentsOpenIndex,
    this.suspendPlaybackIndex,
    this.videoBuilder,
    this.audioPlaybackFactory,
    this.videoPlaybackFactory,
    this.soundOn,
  });

  /// The widest a Reel stage ever gets. Past this the 9:16 frame stops being
  /// a phone-shaped object and starts being a poster. Board 08 measures the
  /// card at 600, which is also the Voice column's own measure less its
  /// gutters, so the two formats sit on one grid.
  static const double maxCardWidth = 600;

  final List<Reel> items;
  final PageController controller;
  final ReelService service;
  final int selectedIndex;
  final bool isVisible;
  final ValueChanged<int> onChanged;
  final Future<void> Function(Reel reel) onReport;
  final Future<void> Function(Reel reel) onDelete;
  final void Function(Reel reel) onComments;
  final EdgeInsets padding;
  final double cardRadius;
  final bool showIdentity;
  final bool immersive;
  final double mediaTopInset;

  /// Null when there is no viewer to like as.
  final Future<void> Function(Reel reel)? onLike;
  final void Function(Reel reel)? onOpenAuthor;

  /// Null where the follow graph is unavailable, which hides the control.
  final FollowService? followService;
  final CreatorAudienceService? creatorAudienceService;
  final Set<String> likePending;

  /// The page whose thread the wide layout is already showing beside the
  /// feed, so its control reads as a selected toggle. Null at every width
  /// that opens a sheet instead.
  final int? commentsOpenIndex;

  /// The page whose playback must stay silent while something else in the
  /// host is sounding — a voice comment in the docked thread. Null when
  /// nothing is.
  final int? suspendPlaybackIndex;
  final ReelVideoBuilder? videoBuilder;
  final ReelAudioPlaybackFactory? audioPlaybackFactory;
  final ReelVideoPlaybackFactory? videoPlaybackFactory;

  /// Shared by every page so turning sound on carries to the next Reel.
  final ValueNotifier<bool>? soundOn;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: controller,
      scrollDirection: Axis.vertical,
      itemCount: items.length,
      onPageChanged: onChanged,
      itemBuilder: (context, index) {
        final reel = items[index];
        final like = onLike;
        return Padding(
          padding: padding,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: immersive ? double.infinity : maxCardWidth,
              ),
              child: ReelCard(
                key: ValueKey<String>(reel.id),
                reel: reel,
                service: service,
                isActive: index == selectedIndex,
                isHostVisible: isVisible,
                suspendPlayback: suspendPlaybackIndex == index,
                videoBuilder: videoBuilder,
                audioPlaybackFactory: audioPlaybackFactory,
                videoPlaybackFactory: videoPlaybackFactory,
                soundOn: soundOn,
                borderRadius: cardRadius,
                fillViewport: immersive,
                mediaTopInset: mediaTopInset,
                showIdentity: showIdentity,
                onOpenAuthor: onOpenAuthor,
                followService: followService,
                creatorAudienceService: creatorAudienceService,
                onReport: service.isCurrentUserAuthor(reel)
                    ? null
                    : () => onReport(reel),
                onDelete: service.isCurrentUserAuthor(reel)
                    ? () => onDelete(reel)
                    : null,
                onLike: like == null ? null : () => like(reel),
                onComments: () => onComments(reel),
                likePending: likePending.contains(reel.id),
                commentsOpen: commentsOpenIndex == index,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReelFeedScanPaused implements Exception {
  const _ReelFeedScanPaused();
}

class _FeedLoadMoreError extends StatelessWidget {
  const _FeedLoadMoreError({required this.scanPaused, required this.onRetry});

  final bool scanPaused;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    // A paused scan is not a failure and nothing is loading: the batch we
    // read held nothing for this viewer, and there is more to check.
    final message = scanPaused
        ? copy.text(
            'More Yeels are available to check.',
            'Możesz sprawdzić kolejne Yeels.',
          )
        : copy.text(
            'Something went wrong. Please try again.',
            'Coś poszło nie tak. Spróbuj ponownie.',
          );
    final action = scanPaused
        ? copy.text('Load more', 'Wczytaj więcej')
        : copy.text('Try again', 'Spróbuj ponownie');
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: Material(
        key: const ValueKey<String>('reels-load-more-error'),
        color: palette.surfaceRaised,
        elevation: 8,
        shadowColor: palette.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: scanPaused ? palette.border : palette.dangerForeground,
          ),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 8, 10),
          child: Row(
            children: <Widget>[
              Icon(
                scanPaused ? Icons.travel_explore_rounded : Icons.sync_problem,
                color: scanPaused
                    ? palette.interactiveForeground
                    : palette.dangerForeground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                key: const ValueKey<String>('reels-load-more-retry'),
                onPressed: onRetry,
                icon: Icon(
                  scanPaused
                      ? Icons.expand_more_rounded
                      : Icons.refresh_rounded,
                ),
                label: Text(action),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReelReportSheet extends StatelessWidget {
  const _ReelReportSheet({required this.authorName});

  final String authorName;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final reasons = <(String, String, IconData)>[
      (
        'spam',
        copy.text('Spam or scam', 'Spam lub oszustwo'),
        Icons.report_gmailerrorred_rounded,
      ),
      (
        'harassment',
        copy.text('Harassment or bullying', 'Nękanie lub prześladowanie'),
        Icons.person_off_outlined,
      ),
      (
        'hate',
        copy.text('Hate or abusive content', 'Treści szerzące nienawiść'),
        Icons.block_rounded,
      ),
      (
        'sexual',
        copy.text('Sexual content', 'Treści seksualne'),
        Icons.visibility_off_outlined,
      ),
      (
        'violence',
        copy.text(
          'Violence or dangerous acts',
          'Przemoc lub niebezpieczne zachowania',
        ),
        Icons.warning_amber_rounded,
      ),
      (
        'selfHarm',
        copy.text('Self-harm or suicide', 'Samookaleczenia lub samobójstwo'),
        Icons.health_and_safety_outlined,
      ),
      (
        'impersonation',
        copy.text('Impersonation', 'Podszywanie się'),
        Icons.badge_outlined,
      ),
      (
        'other',
        copy.text('Something else', 'Inny powód'),
        Icons.more_horiz_rounded,
      ),
    ];
    final sheetLabel = copy.text('Report Yeel', 'Zgłoś Yeel');
    return Material(
      color: palette.surfaceRaised,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .86,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              YoModalSheetChrome(
                sheetLabel: sheetLabel,
                surfaceColor: palette.surfaceRaised,
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: <Widget>[
                    Text(
                      copy.template(
                        'Why are you reporting {author}\'s Yeel?',
                        'Dlaczego zgłaszasz Yeel użytkownika {author}?',
                        values: <String, Object>{'author': authorName},
                      ),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      copy.text(
                        'Your report is confidential.',
                        'Twoje zgłoszenie jest poufne.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final reason in reasons)
                      ListTile(
                        leading: Icon(reason.$3),
                        title: Text(reason.$2),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).pop(reason.$1),
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

/// The docked "Rozmowa" column of the wide layout.
///
/// Board 08 moved identity onto the card's own footer bar, so this column is
/// the conversation and nothing else: a heading that counts it, the thread
/// itself, and — under it — the next Reel as a real preview of loaded data.
/// Repeating the author and the caption beside a card that already carries
/// both would be the same fact twice in one view.
///
/// It stands BESIDE the Reel and covers none of it, which is why opening it
/// no longer suspends playback (D5, the ADR-170 amendment). The phone sheet
/// covers the media and still does.
class _WideContextPanel extends StatelessWidget {
  const _WideContextPanel({
    required this.reel,
    required this.service,
    required this.commentsOpen,
    required this.onReelUpdated,
    required this.arbiter,
    this.next,
    this.onComments,
    this.onOpenNext,
  });

  final Reel reel;

  /// The next loaded Reel, or null at the end of what has been loaded.
  final Reel? next;
  final ReelService service;
  final bool commentsOpen;
  final ValueChanged<Reel> onReelUpdated;

  /// The floor a voice comment in this thread takes from the Reel beside it.
  /// Owned by the feed, because the feed is what has to go quiet.
  final ReplyPlaybackArbiter arbiter;
  final VoidCallback? onComments;
  final VoidCallback? onOpenNext;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final heading = copy.contextualText(
      'yoMoments.conversation',
      'Conversation',
      'Rozmowa',
    );
    final upcoming = next;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(left: BorderSide(color: palette.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final header = Padding(
            padding: const EdgeInsets.fromLTRB(
              AppRhythm.section,
              AppRhythm.section,
              AppRhythm.section,
              AppRhythm.title,
            ),
            child: Semantics(
              container: true,
              header: true,
              label: copy.template(
                'Comments: {count}',
                'Komentarze: {count}',
                values: <String, Object>{'count': reel.commentCount},
              ),
              child: Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      heading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleLarge.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppRhythm.tight),
                  Text(
                    reelCompactCount(reel.commentCount),
                    style: AppTypography.bodyMedium.copyWith(
                      color: palette.textTertiary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              header,
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppMotion.resolve(context, AppMotion.standard),
                  switchInCurve: AppMotion.standardCurve,
                  switchOutCurve: AppMotion.standardCurve,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, .02),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: commentsOpen
                      ? Column(
                          key: const ValueKey<String>('reel-panel-thread-open'),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: palette.border,
                            ),
                            Expanded(
                              child: ReelCommentsView(
                                key: const ValueKey<String>(
                                  'reel-comments-panel-view',
                                ),
                                reel: reel,
                                service: service,
                                onReelUpdated: onReelUpdated,
                                arbiter: arbiter,
                                // Aligned with the heading above rather than
                                // with the width the thread happens to get.
                                gutter: AppRhythm.section,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          key: const ValueKey<String>(
                            'reel-panel-thread-closed',
                          ),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: palette.border,
                            ),
                            // A pointer-first column that is simply blank
                            // until something is clicked teaches nothing.
                            // This says what lives here and offers the way in.
                            // It scrolls rather than overflowing if the panel
                            // is ever shorter than this row itself needs.
                            Flexible(
                              child: SingleChildScrollView(
                                primary: false,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppRhythm.section,
                                    AppRhythm.title,
                                    AppRhythm.section,
                                    AppRhythm.tight,
                                  ),
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: TextButton(
                                      key: const ValueKey<String>(
                                        'reel-panel-thread-toggle',
                                      ),
                                      onPressed: onComments,
                                      child: Text(
                                        copy.text(
                                          'Open thread',
                                          'Otwórz wątek',
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              if (upcoming != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppRhythm.section,
                    AppRhythm.title,
                    AppRhythm.section,
                    AppRhythm.section,
                  ),
                  child: _NextReelCard(
                    reel: upcoming,
                    service: service,
                    onOpen: onOpenNext,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// "Następny moment": the Reel the pager will show next, from data that is
/// already loaded.
///
/// Text first, on purpose. The projection carries no poster or thumbnail
/// field (`reel.dart:132-145`), so a picture exists only where the media
/// itself IS the picture — an image Reel, through the neighbour grant the
/// prefetch already minted. A video gets a tile and a play glyph rather than
/// a second decoder spun up to steal one frame (D13).
class _NextReelCard extends StatelessWidget {
  const _NextReelCard({required this.reel, required this.service, this.onOpen});

  final Reel reel;
  final ReelService service;
  final VoidCallback? onOpen;

  static const double _thumbExtent = 96;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final caption = reel.composition.caption;
    final duration = Duration(milliseconds: reel.media.durationMs);
    final durationLabel = reelClockLabel(duration);
    // A Reel without a caption is not given an invented one: the existing
    // "Reel by {author}" phrasing is the honest name for it.
    final title = caption.isEmpty
        ? copy.template(
            'Yeel by {author}',
            'Yeel użytkownika {author}',
            values: <String, Object>{'author': reel.authorName},
          )
        : caption;
    return Semantics(
      container: true,
      button: true,
      label: copy.template(
        'Next Yeel: {caption}, {author}',
        'Następny Yeel: {caption}, {author}',
        values: <String, Object>{'caption': title, 'author': reel.authorName},
      ),
      onTap: onOpen,
      excludeSemantics: true,
      child: Material(
        color: palette.surface,
        borderRadius: AppRadius.lg,
        child: InkWell(
          key: const ValueKey<String>('reel-next-card'),
          onTap: onOpen,
          borderRadius: AppRadius.lg,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.lg,
              border: Border.all(color: palette.border),
            ),
            padding: const EdgeInsets.all(AppRhythm.title),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  copy.contextualText(
                    'reels.nextMoment',
                    'Next moment',
                    'Następny moment',
                  ),
                  style: AppTypography.titleLarge.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: AppRhythm.item),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _NextReelThumb(reel: reel, service: service),
                    const SizedBox(width: AppRhythm.item),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.titleSmall.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AppRhythm.hairline),
                          Text(
                            reel.authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmall.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                          if (duration > Duration.zero) ...<Widget>[
                            const SizedBox(height: AppRhythm.hairline),
                            Text(
                              durationLabel,
                              style: AppTypography.bodySmall.copyWith(
                                color: palette.textTertiary,
                                fontFeatures: const <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
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
    );
  }
}

/// 96×96: the next Reel's own picture when it HAS one, and an honest tile
/// when it does not.
class _NextReelThumb extends StatelessWidget {
  const _NextReelThumb({required this.reel, required this.service});

  final Reel reel;
  final ReelService service;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    const extent = _NextReelCard._thumbExtent;
    final placeholder = Container(
      width: extent,
      height: extent,
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: AppRadius.md,
      ),
      child: Icon(
        Icons.play_circle_outline_rounded,
        size: 32,
        color: palette.textSecondary,
      ),
    );
    if (reel.media.kind != ReelMediaKind.image) return placeholder;
    // Only the grant the neighbour prefetch already minted — never a new one
    // for an item nobody is about to play.
    final cached = service.cachedMediaUri(reel.id);
    if (cached == null) return placeholder;
    return ClipRRect(
      borderRadius: AppRadius.md,
      child: Image.network(
        cached.toString(),
        width: extent,
        height: extent,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}

/// The pool filters, refresh and create as a docked panel, at the one width
/// where a third column fits beside the stage and the conversation.
///
/// It reuses the destination's own chrome (`YoMomentsLocalPanel`) so the
/// Voice and Reels halves of YO Moments cannot drift into two panels, and it
/// keeps the toolbar's keys so a control is the same control at every width.
class _ReelsLocalPanel extends StatelessWidget {
  const _ReelsLocalPanel({
    required this.width,
    required this.ownOnly,
    required this.onAudienceSelected,
    required this.onRefresh,
    required this.showCreate,
    this.onCreate,
  });

  final double width;
  final bool ownOnly;
  final ValueChanged<bool> onAudienceSelected;
  final VoidCallback? onRefresh;
  final bool showCreate;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final refreshLabel = copy.text('Refresh', 'Odśwież');
    final createLabel = copy.text('Create Yeel', 'Utwórz Yeel');
    return YoMomentsLocalPanel(
      options: <YoMomentsFilterOption>[
        YoMomentsFilterOption(
          key: const ValueKey<String>('reels-discover-filter'),
          label: copy.text('Discover', 'Odkrywaj'),
          icon: Icons.explore_outlined,
        ),
        YoMomentsFilterOption(
          key: const ValueKey<String>('reels-own-filter'),
          label: copy.text('Your Yeels', 'Twoje Yeels'),
          icon: Icons.person_outline_rounded,
        ),
      ],
      selectedIndex: ownOnly ? 1 : 0,
      onSelected: (index) => onAudienceSelected(index == 1),
      groupLabel: copy.text('Filters', 'Filtry'),
      width: width,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              key: const ValueKey('reels-refresh'),
              tooltip: refreshLabel,
              onPressed: onRefresh,
              style: IconButton.styleFrom(
                foregroundColor: palette.textSecondary,
                minimumSize: const Size(
                  AppSizing.minimumTouchTarget,
                  AppSizing.standardControlHeight,
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppRhythm.item),
                shape: const RoundedRectangleBorder(borderRadius: AppRadius.md),
              ),
              icon: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.refresh_rounded, size: 20),
                  const SizedBox(width: AppRhythm.item),
                  Flexible(
                    // Spoken once, through the tooltip.
                    child: ExcludeSemantics(
                      child: Text(
                        refreshLabel,
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
          if (showCreate) ...<Widget>[
            const SizedBox(height: AppRhythm.section),
            FilledButton.tonalIcon(
              key: const ValueKey('reels-create-persistent'),
              onPressed: onCreate,
              style: FilledButton.styleFrom(
                minimumSize: const Size(
                  double.infinity,
                  AppSizing.standardControlHeight,
                ),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.video_call_rounded, size: 18),
              label: Text(
                createLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
