import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_motion.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/reel_engagement_copy.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_card_skeleton.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comments_view.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_engagement_bar.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_playback_coordinator.dart';
import 'package:yovoice/features/reels/presentation/widgets/reels_toolbar.dart';
import 'package:yovoice/shared/widgets/backgrounds/yo_page_background.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
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
    this.onCreate,
    this.isVisible,
    this.now,
    this.expiryTimerFactory,
    this.onOpenAuthor,
    this.embedded = false,
    super.key,
  });

  final ReelService? service;
  final ReelVideoBuilder? videoBuilder;
  final ReelAudioPlaybackFactory? audioPlaybackFactory;

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
  final bool embedded;

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
  Timer? _expiryTimer;
  StreamSubscription<String?>? _identitySubscription;
  String? _viewerId;
  int _loadGeneration = 0;
  int _identityRevision = 0;
  bool _ownOnly = false;

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
    setState(() => _ownOnly = ownOnly);
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
    if (_isHostVisible) _revalidateAvailability();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _identitySubscription?.cancel();
    _expiryTimer?.cancel();
    widget.isVisible?.removeListener(_handleHostVisibilityChanged);
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
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
        final page = await _service.fetchFeed(cursor: requestCursor, limit: 10);
        if (!_isCurrentRequest(generation, viewer)) return;
        loaded.addAll(
          page.items.where((item) => !ownOnly || item.authorId == viewer),
        );
        final nextCursor = page.nextCursor;
        requestCursor = nextCursor;
        if (loaded.isNotEmpty || nextCursor == null) break;
        if (!seenCursors.add(nextCursor)) {
          throw const FormatException('Reel feed cursor did not advance.');
        }
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
        _error = loaded.isEmpty && requestCursor != null
            ? const _ReelFeedScanPaused()
            : null;
      });
      _revalidateAvailability();
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
                'Thanks. The Reel was sent for review.',
                'Dziękujemy. Reel został wysłany do sprawdzenia.',
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
        title: Text(copy.text('Delete Reel?', 'Usunąć Reel?')),
        content: Text(
          copy.text(
            'This removes the Reel from the feed. This action cannot be undone.',
            'Reel zniknie z kanału. Tej operacji nie można cofnąć.',
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
            content: Text(copy.text('Reel deleted.', 'Reel został usunięty.')),
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
                'The Reel could not be deleted. Try again.',
                'Nie udało się usunąć Reela. Spróbuj ponownie.',
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
              message: copy.text('Loading Reels', 'Ładowanie Reels'),
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
          title: copy.text('No Reels yet', 'Nie ma jeszcze Reels'),
          subtitle: copy.text(
            'More Reels are available to check.',
            'Możesz sprawdzić kolejne Reels.',
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
                  'No Reels of your own yet',
                  'Nie masz jeszcze własnych Reels',
                )
              : copy.text('No Reels yet', 'Nie ma jeszcze Reels'),
          subtitle: copy.text(
            'Published photos and short videos will appear here.',
            'Opublikowane zdjęcia i krótkie filmy pojawią się tutaj.',
          ),
          actionLabel: widget.onCreate == null
              ? null
              : copy.text('Create Reel', 'Utwórz Reel'),
          onAction: _creating ? null : _create,
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
            // Wide already carries the author and the caption in the docked
            // panel; burning them over the video a second time is noise.
            showIdentity: !wide,
            videoBuilder: widget.videoBuilder,
            audioPlaybackFactory: widget.audioPlaybackFactory,
            onReport: _report,
            onDelete: _delete,
            onOpenAuthor: widget.onOpenAuthor,
            likePending: _likePending,
            commentsOpenIndex: wide && _commentsPanelOpen ? _selected : null,
            onLike: _viewerId == null ? null : _toggleLike,
            onComments: (reel) => _openComments(reel, wide: wide),
            onChanged: (index) {
              setState(() => _selected = index);
              if (index >= _items.length - 3) _load(reset: false);
            },
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
            final metrics = _StageMetrics.of(constraints.maxWidth);
            // The layout, not a device label, decides where a thread can be
            // hosted: beside the feed when there is room for a panel, in a
            // sheet over it when there is not.
            final wide = constraints.maxWidth >= _panelBreakpoint;
            final showPanel = wide && _items.isNotEmpty;
            final stage = LayoutBuilder(
              builder: (context, stage) =>
                  _buildStage(context, stage, metrics, wide: wide),
            );
            Widget below = stage;
            if (showPanel) {
              final selected = _items[_selected.clamp(0, _items.length - 1)];
              below = Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: stage),
                  SizedBox(
                    width: _panelWidth,
                    child: _WideContextPanel(
                      reel: selected,
                      service: _service,
                      commentsOpen: _commentsPanelOpen,
                      likePending: _likePending.contains(selected.id),
                      onReelUpdated: _applyEngagement,
                      onLike: _viewerId == null
                          ? null
                          : () => _toggleLike(selected),
                      onComments: () => _openComments(selected, wide: true),
                      onOpenAuthor: widget.onOpenAuthor,
                    ),
                  ),
                ],
              );
            }
            // The same composition the Voice half uses: one chrome row across
            // the whole destination, then the content and its docked panel
            // beneath it. Switching format must not move the chrome.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ReelsToolbar(
                  gutter: metrics.toolbarGutter,
                  ownOnly: _ownOnly,
                  onAudienceSelected: _selectAudience,
                  onRefresh: _loading ? null : () => _load(reset: true),
                  showCreate: widget.onCreate != null,
                  onCreate: _creating ? null : _create,
                ),
                Expanded(child: below),
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
        title: Text(copy.text('Reels', 'Reels')),
        actions: widget.onCreate == null
            ? null
            : <Widget>[
                IconButton(
                  tooltip: copy.text('Create Reel', 'Utwórz Reel'),
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
/// covering it, and the width that column then takes.
const double _panelBreakpoint = 1100;
const double _panelWidth = 400;

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
  });

  factory _StageMetrics.of(double width) {
    if (width >= _panelBreakpoint) {
      return const _StageMetrics(
        // The chrome row matches the Voice half's filter row, so the two
        // formats of one destination share a rhythm instead of each having
        // their own.
        toolbarGutter: 24,
        gutter: 24,
        padTop: 8,
        padBottom: 24,
        cardRadius: 28,
      );
    }
    if (width >= 600) {
      return const _StageMetrics(
        toolbarGutter: 24,
        gutter: 24,
        padTop: 8,
        padBottom: 16,
        cardRadius: 24,
      );
    }
    return const _StageMetrics(
      toolbarGutter: 16,
      gutter: 16,
      padTop: 4,
      padBottom: 10,
      cardRadius: 24,
    );
  }

  final double toolbarGutter;
  final double gutter;
  final double padTop;
  final double padBottom;
  final double cardRadius;
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
    this.onLike,
    this.onOpenAuthor,
    this.commentsOpenIndex,
    this.videoBuilder,
    this.audioPlaybackFactory,
  });

  /// The widest a Reel stage ever gets. Past this the 9:16 frame stops being
  /// a phone-shaped object and starts being a poster.
  static const double maxCardWidth = 520;

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

  /// Null when there is no viewer to like as.
  final Future<void> Function(Reel reel)? onLike;
  final void Function(Reel reel)? onOpenAuthor;
  final Set<String> likePending;

  /// The page whose thread the wide layout is already showing beside the
  /// feed, so its control reads as a selected toggle. Null at every width
  /// that opens a sheet instead.
  final int? commentsOpenIndex;
  final ReelVideoBuilder? videoBuilder;
  final ReelAudioPlaybackFactory? audioPlaybackFactory;

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
              constraints: const BoxConstraints(maxWidth: maxCardWidth),
              child: ReelCard(
                key: ValueKey<String>(reel.id),
                reel: reel,
                service: service,
                isActive: isVisible && index == selectedIndex,
                videoBuilder: videoBuilder,
                audioPlaybackFactory: audioPlaybackFactory,
                borderRadius: cardRadius,
                showIdentity: showIdentity,
                onOpenAuthor: onOpenAuthor,
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
            'More Reels are available to check.',
            'Możesz sprawdzić kolejne Reels.',
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
    final sheetLabel = copy.text('Report Reel', 'Zgłoś Reel');
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
                        'Why are you reporting {author}\'s Reel?',
                        'Dlaczego zgłaszasz Reel użytkownika {author}?',
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

/// Height the closed thread block needs before it starts clipping the control
/// that opens the conversation, at the reader's own text size.
///
/// The block is a divider, its 16/8 padding, and a [Wrap] that folds the
/// "Comments" label and the "Open thread" button onto separate runs once the
/// text is enlarged. Measured with a generous hand: it is a floor the docked
/// panel keeps free for the thread, and over-reserving costs the header a few
/// pixels it can scroll, while under-reserving would cost the control.
double _closedThreadFloor(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  final text = Theme.of(context).textTheme;
  final label = scaler.scale(text.titleMedium?.fontSize ?? 16) * 1.5;
  final button = math.max(
    // The button never gives up its accessible target.
    48.0,
    scaler.scale(text.labelLarge?.fontSize ?? 14) * 1.4 + 16,
  );
  return 1 + 16 + 8 + label + 4 + button;
}

/// Height the OPEN thread needs before the header may take the rest, at the
/// reader's own text size.
///
/// The open thread is not the closed block wearing a different label: it is a
/// composer pinned to the bottom of the region with the conversation above
/// it. Reserving the closed block's height for it leaves the composer alone
/// filling the region and the comment the reader deliberately opened the
/// thread for clipped, so the two states get their own floors:
///
///  - the composer — its 10/24 padding around a field whose hint folds onto a
///    second line once the text is enlarged, beside a send target that never
///    drops under 48 px;
///  - one whole comment — its 8/8 padding around an author name that wraps at
///    an accessibility text size, the timestamp that follows it, and a line of
///    body text, never under the 48 px action target that sets the row's
///    height at ordinary sizes.
///
/// Generous with the same hand as the closed floor, and for the same reason:
/// over-reserving costs the header a few pixels it can scroll, while
/// under-reserving costs the reader the conversation itself.
double _openThreadFloor(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  final text = Theme.of(context).textTheme;
  final body = scaler.scale(text.bodyMedium?.fontSize ?? 14) * 1.5;
  final author = scaler.scale(text.labelLarge?.fontSize ?? 14) * 1.4;
  final timestamp = scaler.scale(text.bodySmall?.fontSize ?? 12) * 1.4;
  final double composer = 10 + 24 + math.max(48.0, body * 2 + 32);
  final double comment =
      8 + 8 + math.max(48.0, author * 2 + timestamp + 2 + body);
  return 1 + composer + comment;
}

/// The docked context column of the wide layout.
///
/// It is the only place the wide layout says who published the Reel and what
/// they wrote, so the frame beside it can stay artwork with a rail. Full
/// height, edge to edge against the slot's right side — a panel, not a card
/// floating in a gutter.
class _WideContextPanel extends StatelessWidget {
  const _WideContextPanel({
    required this.reel,
    required this.service,
    required this.commentsOpen,
    required this.likePending,
    required this.onReelUpdated,
    this.onLike,
    this.onComments,
    this.onOpenAuthor,
  });

  final Reel reel;
  final ReelService service;
  final bool commentsOpen;
  final bool likePending;
  final ValueChanged<Reel> onReelUpdated;
  final VoidCallback? onLike;
  final VoidCallback? onComments;
  final void Function(Reel reel)? onOpenAuthor;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final attribution = reel.composition.audioAttribution;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(left: BorderSide(color: palette.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A caption is user content and can be any length. It yields the
          // column to the conversation when one is open, and stays inside the
          // panel when it is not, instead of pushing the stats off the bottom.
          // What a caption block costs is measured in text, not in pixels: at
          // an accessibility text size six lines are twice as tall, so the
          // room a column has to have for them grows with the reader's size.
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final captionLines =
              commentsOpen || constraints.maxHeight < 520 * textScale ? 3 : 6;
          final header = Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, commentsOpen ? 16 : 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ReelAuthorRow(
                  reel: reel,
                  variant: ReelAuthorRowVariant.panel,
                  secondaryLine: copy.relativeCompactTime(reel.publishedAt),
                  onTap: () => _openAuthor(context),
                ),
                if (reel.composition.caption.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 14),
                  Text(
                    reel.composition.caption,
                    maxLines: captionLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                ],
                if (attribution.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.music_note_rounded,
                        size: 16,
                        color: palette.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          attribution,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                ReelEngagementBar(
                  likeCount: reel.likeCount,
                  commentCount: reel.commentCount,
                  liked: reel.callerLiked,
                  likePending: likePending,
                  commentsOpen: commentsOpen,
                  variant: ReelEngagementBarVariant.panel,
                  onLike: onLike,
                  onComments: onComments,
                ),
              ],
            ),
          );
          // The header is user content and grows without a ceiling — a long
          // caption at an accessibility text size can want the whole column.
          // The thread region below it holds the only way into the
          // conversation on this layout, so the header is the part that
          // yields: it keeps its natural height while there is room and
          // scrolls once the column is short, instead of pushing the control
          // that opens the thread out of the panel. What is reserved depends
          // on what is down there: the control that opens the conversation
          // while it is closed, and the conversation itself once it is open —
          // reserving for the closed block either way would open a thread
          // with no room to read it in.
          final threadFloor = commentsOpen
              ? _openThreadFloor(context)
              : _closedThreadFloor(context);
          final headerBox = constraints.hasBoundedHeight
              ? ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.max(
                      0,
                      constraints.maxHeight -
                          // A column too short to hold both still keeps a
                          // sliver of identity above the thread instead of
                          // becoming a control on its own.
                          math.min(threadFloor, constraints.maxHeight * .75),
                    ),
                  ),
                  child: SingleChildScrollView(primary: false, child: header),
                )
              : header;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              headerBox,
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
                                // Aligned with the header above rather than
                                // with the width the thread happens to get.
                                gutter: 24,
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
                                    24,
                                    16,
                                    24,
                                    8,
                                  ),
                                  child: Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 12,
                                    runSpacing: 4,
                                    children: <Widget>[
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Text(
                                            copy.text('Comments', 'Komentarze'),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  color: palette.textPrimary,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            reelCompactCount(reel.commentCount),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: palette.textTertiary,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ],
                                      ),
                                      TextButton(
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
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openAuthor(BuildContext context) {
    final seam = onOpenAuthor;
    if (seam != null) {
      seam(reel);
      return;
    }
    unawaited(
      showProfilePreview(
        context,
        userId: reel.authorId,
        displayName: reel.authorName,
      ),
    );
  }
}
