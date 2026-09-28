import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/page_post_events.dart';
import 'package:yovoice/features/pages/data/services/pages_local_store.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';

/// Follow state the viewer changed in this session, shared by the feed's
/// suggestions, Find Pages and the desktop panel so one tap shows the same
/// "Obserwujesz" everywhere without refetching.
class PagesFollowRegistry extends ChangeNotifier {
  PagesFollowRegistry(this._service);

  final PagesService _service;
  final Map<String, bool> _overrides = <String, bool>{};
  final Set<String> _inFlight = <String>{};

  /// The viewer's follow state for [card]: this session's change, else the
  /// server's `viewerFollows`.
  bool follows(PageCard card) => _overrides[card.pageId] ?? card.viewerFollows;

  bool isBusy(String pageId) => _inFlight.contains(pageId);

  /// Follows or unfollows. Returns null on success, else the failure; the
  /// state is only changed after the server accepted it.
  Future<PagesFailure?> setFollowing(String pageId, bool following) async {
    if (_inFlight.contains(pageId)) return null;
    _inFlight.add(pageId);
    notifyListeners();
    try {
      await _service.setFollow(pageId, following: following);
      _overrides[pageId] = following;
      return null;
    } on PagesException catch (error) {
      return error.failure;
    } finally {
      _inFlight.remove(pageId);
      notifyListeners();
    }
  }
}

enum PagesFeedStatus { loading, ready, error, notEnabled }

/// Which empty state the wall shows when the first page has no posts
/// (spec §4.2, R4).
enum PagesFeedEmptyKind {
  /// E1: the viewer follows no Pages (suggestions below).
  noFollows,

  /// E3: nothing to follow at all (empty directory).
  noPages,

  /// E4: followed Pages have not posted.
  noNewPosts,
}

/// The Treści wall's state: `getPagesFeedV1` pages, the suggestions of the
/// first page, likes and pagination. Shared by the phone, tablet and
/// desktop presentations.
class PagesFeedController extends ChangeNotifier {
  PagesFeedController({
    required PagesService service,
    required PagesFollowRegistry follows,
    DateTime Function()? clock,
    PagePostEvents? events,
  }) : _service = service,
       _follows = follows,
       _clock = clock ?? DateTime.now {
    _follows.addListener(_onFollowsChanged);
    _eventsSub = (events ?? PagePostEvents.instance).changes.listen(_onChange);
  }

  late final StreamSubscription<PagePostChange> _eventsSub;

  /// A post the post detail changed or removed.
  void _onChange(PagePostChange change) {
    if (_disposed || !_posts.any((p) => p.postId == change.postId)) return;
    switch (change) {
      case PagePostUpdated(:final post):
        _replace(post);
      case PagePostRemoved(:final postId):
        _posts = List.unmodifiable(_posts.where((p) => p.postId != postId));
    }
    _notify();
  }

  /// A reload inside this window keeps the suggestion rail as it was, so a
  /// re-tap does not reshuffle it (§2.5).
  static const Duration suggestionsTtl = Duration(minutes: 5);

  final PagesService _service;
  final PagesFollowRegistry _follows;
  final DateTime Function() _clock;

  PagesFeedStatus _status = PagesFeedStatus.loading;
  List<PagePostView> _posts = const <PagePostView>[];
  List<PageCard> _suggestions = const <PageCard>[];
  DateTime? _suggestionsAt;
  String? _nextCursor;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  bool _refreshing = false;
  PagesFeedEmptyKind? _emptyKind;
  int _generation = 0;
  final Set<String> _likesInFlight = <String>{};
  bool _disposed = false;

  PagesFeedStatus get status => _status;
  List<PagePostView> get posts => _posts;
  List<PageCard> get suggestions => _suggestions;
  bool get hasMore => _hasMore;
  bool get loadingMore => _loadingMore;
  bool get loadMoreFailed => _loadMoreFailed;
  bool get refreshing => _refreshing;
  PagesFeedEmptyKind? get emptyKind =>
      _status == PagesFeedStatus.ready && _posts.isEmpty ? _emptyKind : null;
  PagesFollowRegistry get followRegistry => _follows;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// First page. With content already on screen this is a refresh: the
  /// posts stay until the new page arrives, and a failed refresh keeps them.
  Future<void> load() async {
    final generation = ++_generation;
    // A page request in flight belongs to the old generation and will be
    // dropped; without this reset "Wczytaj więcej" would spin forever.
    _loadingMore = false;
    _loadMoreFailed = false;
    final hadContent = _status == PagesFeedStatus.ready;
    if (hadContent) {
      _refreshing = true;
    } else {
      _status = PagesFeedStatus.loading;
    }
    _notify();
    try {
      final page = await _service.getFeed();
      if (generation != _generation || _disposed) return;
      var emptyKind = _emptyKind;
      final fresh = page.suggestions ?? const <PageCard>[];
      final now = _clock();
      final keepRail =
          _suggestionsAt != null &&
          now.difference(_suggestionsAt!) < suggestionsTtl &&
          _suggestions.isNotEmpty &&
          page.posts.isNotEmpty;
      if (!keepRail) {
        _suggestions = fresh;
        _suggestionsAt = now;
      }
      if (page.posts.isEmpty) {
        emptyKind = await _classifyEmpty(fresh);
        if (generation != _generation || _disposed) return;
      }
      _posts = page.posts;
      _nextCursor = page.nextCursor;
      _hasMore = page.hasMore;
      _loadMoreFailed = false;
      _emptyKind = emptyKind;
      _status = PagesFeedStatus.ready;
    } on PagesException catch (error) {
      if (generation != _generation || _disposed) return;
      if (error.failure == PagesFailure.notEnabled) {
        _status = PagesFeedStatus.notEnabled;
        _posts = const <PagePostView>[];
      } else if (!hadContent) {
        _status = PagesFeedStatus.error;
      }
    } finally {
      if (generation == _generation) {
        _refreshing = false;
        _notify();
      }
    }
  }

  /// E1 / E3 / E4. The feed does not say whether the viewer follows any
  /// Page, so an empty first page asks `findPagesV1 following` once.
  Future<PagesFeedEmptyKind> _classifyEmpty(List<PageCard> suggestions) async {
    var followsAny = false;
    try {
      final followed = await _service.findPages(mode: FindPagesMode.following);
      followsAny = followed.pages.isNotEmpty;
    } on PagesException {
      followsAny = false;
    }
    if (followsAny) return PagesFeedEmptyKind.noNewPosts;
    return suggestions.isEmpty
        ? PagesFeedEmptyKind.noPages
        : PagesFeedEmptyKind.noFollows;
  }

  Future<void> loadMore() async {
    final cursor = _nextCursor;
    if (_loadingMore || !_hasMore || cursor == null) return;
    final generation = _generation;
    _loadingMore = true;
    _loadMoreFailed = false;
    _notify();
    try {
      final page = await _service.getFeed(cursor: cursor);
      if (generation != _generation || _disposed) return;
      final seen = {for (final post in _posts) post.postId};
      _posts = List.unmodifiable([
        ..._posts,
        for (final post in page.posts)
          if (!seen.contains(post.postId)) post,
      ]);
      _nextCursor = page.nextCursor;
      _hasMore = page.hasMore;
    } on PagesException catch (error) {
      if (generation != _generation || _disposed) return;
      if (error.failure == PagesFailure.notEnabled) {
        _status = PagesFeedStatus.notEnabled;
      } else {
        _loadMoreFailed = true;
      }
    } finally {
      if (generation == _generation) {
        _loadingMore = false;
        _notify();
      }
    }
  }

  bool isLikeBusy(String postId) => _likesInFlight.contains(postId);

  /// Likes or unlikes [postId]. The heart and count move at once and roll
  /// back if the server refuses; returns the failure, if any.
  Future<PagesFailure?> toggleLike(String postId) async {
    if (_likesInFlight.contains(postId)) return null;
    final index = _posts.indexWhere((post) => post.postId == postId);
    if (index < 0) return null;
    final before = _posts[index];
    final liked = !before.callerLiked;
    _replace(
      before.copyWith(
        callerLiked: liked,
        likeCount: (before.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 31),
      ),
    );
    _likesInFlight.add(postId);
    _notify();
    try {
      await _service.setLiked(postId, liked: liked);
      return null;
    } on PagesException catch (error) {
      final current = _posts.where((p) => p.postId == postId).firstOrNull;
      if (current != null) {
        _replace(
          current.copyWith(
            callerLiked: before.callerLiked,
            likeCount: before.likeCount,
          ),
        );
      }
      return error.failure;
    } finally {
      _likesInFlight.remove(postId);
      _notify();
    }
  }

  void _replace(PagePostView post) {
    _posts = List.unmodifiable([
      for (final existing in _posts)
        existing.postId == post.postId ? post : existing,
    ]);
  }

  void _onFollowsChanged() {
    // An empty wall is waiting for exactly this: the first follow brings its
    // posts in. A populated wall keeps its place; re-tap refreshes it.
    if (_status == PagesFeedStatus.ready &&
        _posts.isEmpty &&
        !_refreshing &&
        _follows._inFlight.isEmpty) {
      unawaited(load());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _follows.removeListener(_onFollowsChanged);
    unawaited(_eventsSub.cancel());
    super.dispose();
  }
}

enum PagesListStatus { idle, loading, ready, error }

/// Find Pages (spec §4.7, R4): suggestions until 2 characters are typed,
/// then a prefix search. No filter chips in v1.
class FindPagesController extends ChangeNotifier {
  FindPagesController({
    required PagesService service,
    this.debounce = const Duration(milliseconds: 300),
  }) : _service = service;

  final PagesService _service;
  final Duration debounce;

  String _query = '';
  FindPagesMode _mode = FindPagesMode.suggest;
  PagesListStatus _status = PagesListStatus.idle;
  List<PageCard> _pages = const <PageCard>[];
  String? _cursor;
  bool _hasMore = false;
  bool _loadingMore = false;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  String get query => _query;
  FindPagesMode get mode => _mode;
  PagesListStatus get status => _status;
  List<PageCard> get pages => _pages;
  bool get hasMore => _hasMore;
  bool get loadingMore => _loadingMore;

  static FindPagesMode modeFor(String query) {
    final length = query.trim().runes.length;
    return length >= PagesService.minSearchLength
        ? FindPagesMode.search
        : FindPagesMode.suggest;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// The first load (suggestions).
  Future<void> start() => _run(_query);

  void updateQuery(String value) {
    var next = value;
    if (next.runes.length > PagesService.maxSearchLength) {
      next = String.fromCharCodes(
        next.runes.take(PagesService.maxSearchLength),
      );
    }
    if (next.trim() == _query.trim()) {
      _query = next;
      return;
    }
    _query = next;
    _timer?.cancel();
    final mode = modeFor(next);
    if (mode == FindPagesMode.suggest && _mode == FindPagesMode.suggest) {
      return;
    }
    _timer = Timer(debounce, () => unawaited(_run(next)));
  }

  Future<void> retry() => _run(_query);

  Future<void> _run(String query) async {
    _timer?.cancel();
    final generation = ++_generation;
    _loadingMore = false;
    final mode = modeFor(query);
    _mode = mode;
    _status = PagesListStatus.loading;
    _pages = const <PageCard>[];
    _cursor = null;
    _hasMore = false;
    _notify();
    try {
      final page = await _service.findPages(
        mode: mode,
        query: mode == FindPagesMode.search ? query : null,
      );
      if (generation != _generation || _disposed) return;
      _pages = page.pages;
      _cursor = page.nextCursor;
      _hasMore = page.hasMore;
      _status = PagesListStatus.ready;
    } on PagesException {
      if (generation != _generation || _disposed) return;
      _status = PagesListStatus.error;
    }
    _notify();
  }

  Future<void> loadMore() async {
    final cursor = _cursor;
    if (_loadingMore || !_hasMore || cursor == null) return;
    final generation = _generation;
    _loadingMore = true;
    _notify();
    try {
      final page = await _service.findPages(
        mode: _mode,
        query: _mode == FindPagesMode.search ? _query : null,
        cursor: cursor,
      );
      if (generation != _generation || _disposed) return;
      final seen = {for (final card in _pages) card.pageId};
      _pages = List.unmodifiable([
        ..._pages,
        for (final card in page.pages)
          if (!seen.contains(card.pageId)) card,
      ]);
      _cursor = page.nextCursor;
      _hasMore = page.hasMore;
    } on PagesException {
      // The list stays; "Wczytaj więcej" stays offered.
    } finally {
      if (generation == _generation) {
        _loadingMore = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// The desktop panel's OBSERWOWANE list: `findPagesV1 following`, loaded
/// on scroll, with the D10 unseen dot.
class FollowedPagesController extends ChangeNotifier {
  FollowedPagesController({
    required PagesService service,
    required PagesFollowRegistry follows,
    required PagesLocalStore store,
    required String userId,
  }) : _service = service,
       _follows = follows,
       _store = store,
       _userId = userId {
    _follows.addListener(_onFollowsChanged);
  }

  final PagesService _service;
  final PagesFollowRegistry _follows;
  final PagesLocalStore _store;
  final String _userId;

  PagesListStatus _status = PagesListStatus.idle;
  List<PageCard> _pages = const <PageCard>[];
  String? _cursor;
  bool _hasMore = false;
  bool _loadingMore = false;
  Map<String, int> _seen = <String, int>{};
  int _generation = 0;
  bool _disposed = false;
  Timer? _followReload;

  PagesListStatus get status => _status;
  bool get hasMore => _hasMore;
  bool get loadingMore => _loadingMore;

  /// Followed Pages, minus any the viewer unfollowed in this session.
  List<PageCard> get pages => [
    for (final card in _pages)
      if (_follows.follows(card.copyWith(viewerFollows: true))) card,
  ];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// D10: a Page has new posts when its `lastPostAtMs` is newer than the
  /// last one this device saw. A Page seen for the first time takes its
  /// current post as the baseline, so a new device starts without dots.
  bool hasUnseen(PageCard card) {
    final last = card.lastPostAtMs;
    if (last == null) return false;
    final seen = _seen[card.pageId];
    return seen != null && last > seen;
  }

  Future<void> load() async {
    final generation = ++_generation;
    _loadingMore = false;
    if (_pages.isEmpty) {
      _status = PagesListStatus.loading;
      _notify();
    }
    try {
      final results = await Future.wait<Object>([
        _service.findPages(mode: FindPagesMode.following),
        _store.seenBaselines(_userId).catchError((Object _) => <String, int>{}),
      ]);
      if (generation != _generation || _disposed) return;
      final page = results[0] as FindPagesPage;
      _seen = results[1] as Map<String, int>;
      _pages = page.pages;
      _cursor = page.nextCursor;
      _hasMore = page.hasMore;
      _status = PagesListStatus.ready;
      _baseline(page.pages);
    } on PagesException {
      if (generation != _generation || _disposed) return;
      if (_pages.isEmpty) _status = PagesListStatus.error;
    }
    _notify();
  }

  Future<void> loadMore() async {
    final cursor = _cursor;
    if (_loadingMore || !_hasMore || cursor == null) return;
    final generation = _generation;
    _loadingMore = true;
    _notify();
    try {
      final page = await _service.findPages(
        mode: FindPagesMode.following,
        cursor: cursor,
      );
      if (generation != _generation || _disposed) return;
      final seenIds = {for (final card in _pages) card.pageId};
      _pages = List.unmodifiable([
        ..._pages,
        for (final card in page.pages)
          if (!seenIds.contains(card.pageId)) card,
      ]);
      _cursor = page.nextCursor;
      _hasMore = page.hasMore;
      _baseline(page.pages);
    } on PagesException {
      // Scrolling again retries.
    } finally {
      if (generation == _generation) {
        _loadingMore = false;
        _notify();
      }
    }
  }

  void _baseline(List<PageCard> cards) {
    var changed = false;
    for (final card in cards) {
      final last = card.lastPostAtMs;
      if (last != null && !_seen.containsKey(card.pageId)) {
        _seen[card.pageId] = last;
        changed = true;
      }
    }
    if (changed) _persist();
  }

  /// The viewer opened [pageId]: its current posts are seen.
  void markSeen(String pageId) {
    final card = _pages.where((c) => c.pageId == pageId).firstOrNull;
    final last = card?.lastPostAtMs;
    if (last == null) return;
    if ((_seen[pageId] ?? -1) >= last) return;
    _seen[pageId] = last;
    _persist();
    _notify();
  }

  void _persist() {
    unawaited(
      _store
          .writeSeenBaselines(_userId, Map<String, int>.of(_seen))
          .catchError((Object _) {}),
    );
  }

  void _onFollowsChanged() {
    _notify();
    // A new follow appears in the list after the server has it.
    _followReload?.cancel();
    _followReload = Timer(const Duration(milliseconds: 600), () {
      if (!_disposed) unawaited(load());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _followReload?.cancel();
    _follows.removeListener(_onFollowsChanged);
    super.dispose();
  }
}
