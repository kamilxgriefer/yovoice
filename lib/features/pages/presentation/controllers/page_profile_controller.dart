import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/page_post_events.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';

enum PageProfileStatus {
  loading,
  ready,
  error,

  /// `pageUnavailable` (uniform refusal): blocked, paused, hidden,
  /// suspended or no Page at all (§2.5).
  unavailable,

  /// `pagesNotEnabled`: the kill switch or the cohort (§2.1).
  notEnabled,
}

/// One list of a Page's posts (`getPageV1` wall or photos), paged by the
/// server's cursor.
class PagePostList {
  const PagePostList({
    this.posts = const <PagePostView>[],
    this.nextCursor,
    this.hasMore = false,
    this.loaded = false,
    this.loading = false,
    this.loadingMore = false,
    this.failed = false,
    this.loadMoreFailed = false,
  });

  final List<PagePostView> posts;
  final String? nextCursor;
  final bool hasMore;
  final bool loaded;
  final bool loading;
  final bool loadingMore;
  final bool failed;
  final bool loadMoreFailed;

  PagePostList copyWith({
    List<PagePostView>? posts,
    Object? nextCursor = _keep,
    bool? hasMore,
    bool? loaded,
    bool? loading,
    bool? loadingMore,
    bool? failed,
    bool? loadMoreFailed,
  }) => PagePostList(
    posts: posts ?? this.posts,
    nextCursor: identical(nextCursor, _keep)
        ? this.nextCursor
        : nextCursor as String?,
    hasMore: hasMore ?? this.hasMore,
    loaded: loaded ?? this.loaded,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    failed: failed ?? this.failed,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
  );
}

const Object _keep = Object();

/// The Page profile B's state (spec premium-pages §2.5 `getPageV1`, §4.3),
/// shared by the phone, tablet and desktop presentations: the header, the
/// viewer's relation, the pinned post, the wall and (on demand) the photos
/// tab, follow, likes and the owner's post operations.
class PageProfileController extends ChangeNotifier {
  PageProfileController({
    required PagesService service,
    required this.pageId,
    PagePostEvents? events,
  }) : _service = service {
    _eventsSub = (events ?? PagePostEvents.instance).changes.listen(_onChange);
  }

  late final StreamSubscription<PagePostChange> _eventsSub;

  final PagesService _service;
  final String pageId;

  PageProfileStatus _status = PageProfileStatus.loading;
  PageHeader? _header;
  PageViewerView? _viewer;
  PagePostView? _pinned;
  PagePostList _wall = const PagePostList();
  PagePostList _photos = const PagePostList();
  bool _followBusy = false;
  final Set<String> _likesInFlight = <String>{};
  final Set<String> _postOpsInFlight = <String>{};
  int _generation = 0;
  bool _disposed = false;

  PageProfileStatus get status => _status;
  PageHeader? get header => _header;
  PageViewerView? get viewer => _viewer;
  PagePostView? get pinned => _pinned;
  PagePostList get wall => _wall;
  PagePostList get photos => _photos;
  bool get followBusy => _followBusy;
  bool get isOwner => _viewer?.isOwner ?? false;

  /// The wall in display order: the pinned post first.
  List<PagePostView> get wallPosts => [?_pinned, ..._wall.posts];

  bool isLikeBusy(String postId) => _likesInFlight.contains(postId);
  bool isPostBusy(String postId) => _postOpsInFlight.contains(postId);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// First page of the wall with the header. A refresh keeps what is on
  /// screen until the answer arrives; a failed refresh keeps it too.
  Future<void> load() async {
    final generation = ++_generation;
    // Pages requested by the old generation are dropped when they arrive,
    // so their busy flags must not outlive this refresh.
    _wall = _wall.copyWith(loadingMore: false);
    _photos = _photos.copyWith(loading: false, loadingMore: false);
    final hadContent = _status == PageProfileStatus.ready;
    if (!hadContent) {
      _status = PageProfileStatus.loading;
      _notify();
    }
    try {
      final page = await _service.getPage(pageId: pageId);
      if (generation != _generation || _disposed) return;
      final header = page.header;
      final viewer = page.viewer;
      if (header == null || viewer == null) {
        throw const PagesException(PagesFailure.unknown, 'header');
      }
      _header = header;
      _viewer = viewer;
      _pinned = page.pinned;
      _wall = PagePostList(
        posts: page.posts,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        loaded: true,
      );
      // The photos tab reloads on its next visit.
      _photos = const PagePostList();
      _status = PageProfileStatus.ready;
    } on PagesException catch (error) {
      if (generation != _generation || _disposed) return;
      switch (error.failure) {
        case PagesFailure.notEnabled:
          _status = PageProfileStatus.notEnabled;
        case PagesFailure.unavailable:
          _status = PageProfileStatus.unavailable;
        default:
          if (!hadContent) _status = PageProfileStatus.error;
      }
    } finally {
      if (generation == _generation) _notify();
    }
  }

  Future<void> loadMoreWall() async {
    final cursor = _wall.nextCursor;
    if (_wall.loadingMore || !_wall.hasMore || cursor == null) return;
    final generation = _generation;
    _wall = _wall.copyWith(loadingMore: true, loadMoreFailed: false);
    _notify();
    try {
      final page = await _service.getPage(pageId: pageId, cursor: cursor);
      if (generation != _generation || _disposed) return;
      final seen = {for (final post in wallPosts) post.postId};
      _wall = _wall.copyWith(
        posts: List.unmodifiable([
          ..._wall.posts,
          for (final post in page.posts)
            if (!seen.contains(post.postId)) post,
        ]),
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        loadingMore: false,
      );
    } on PagesException {
      if (generation != _generation || _disposed) return;
      _wall = _wall.copyWith(loadingMore: false, loadMoreFailed: true);
    } finally {
      _notify();
    }
  }

  /// The "Zdjęcia" tab: photo posts, loaded the first time it is shown.
  Future<void> loadPhotos({bool more = false}) async {
    if (_photos.loading || _photos.loadingMore) return;
    if (!more && _photos.loaded) return;
    final cursor = more ? _photos.nextCursor : null;
    if (more && (cursor == null || !_photos.hasMore)) return;
    final generation = _generation;
    _photos = more
        ? _photos.copyWith(loadingMore: true, loadMoreFailed: false)
        : _photos.copyWith(loading: true, failed: false);
    _notify();
    try {
      final page = await _service.getPage(
        pageId: pageId,
        tab: PageWallTab.photos,
        cursor: cursor,
      );
      if (generation != _generation || _disposed) return;
      final photoPosts = [
        for (final post in page.posts)
          if (post.images.isNotEmpty) post,
      ];
      _photos = PagePostList(
        posts: List.unmodifiable([if (more) ..._photos.posts, ...photoPosts]),
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        loaded: true,
      );
    } on PagesException {
      if (generation != _generation || _disposed) return;
      _photos = more
          ? _photos.copyWith(loadingMore: false, loadMoreFailed: true)
          : _photos.copyWith(loading: false, failed: true, loaded: false);
    } finally {
      _notify();
    }
  }

  /// Follows or unfollows the Page through `setFollow`. The header's count
  /// moves with the server's acceptance. Returns the failure, if any.
  Future<PagesFailure?> setFollowing(bool following) async {
    final viewer = _viewer;
    final header = _header;
    if (_followBusy || viewer == null || header == null || viewer.isOwner) {
      return null;
    }
    _followBusy = true;
    _notify();
    try {
      await _service.setFollow(pageId, following: following);
      if (_disposed) return null;
      final delta = following == viewer.following ? 0 : (following ? 1 : -1);
      _viewer = viewer.copyWith(following: following, canFollow: !following);
      _header = header.copyWith(
        followerCount: (header.followerCount + delta).clamp(0, 1 << 31),
      );
      return null;
    } on PagesException catch (error) {
      return error.failure;
    } finally {
      _followBusy = false;
      _notify();
    }
  }

  /// Likes or unlikes a post on this wall, optimistically (as the feed).
  Future<PagesFailure?> toggleLike(String postId) async {
    if (_likesInFlight.contains(postId)) return null;
    final before = _find(postId);
    if (before == null) return null;
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
      final current = _find(postId);
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

  /// The owner's delete / pin / unpin. Delete removes the post on success;
  /// pin moves it to the top. Returns the failure, if any.
  Future<PagesFailure?> managePost(String postId, PagePostOp op) async {
    if (_postOpsInFlight.contains(postId)) return null;
    _postOpsInFlight.add(postId);
    _notify();
    try {
      final result = await _service.managePost(postId, op);
      if (_disposed) return null;
      if (op == PagePostOp.delete || result.deleted) {
        if (_pinned?.postId == postId) _pinned = null;
        _wall = _wall.copyWith(
          posts: List.unmodifiable(
            _wall.posts.where((p) => p.postId != postId),
          ),
        );
        _photos = _photos.copyWith(
          posts: List.unmodifiable(
            _photos.posts.where((p) => p.postId != postId),
          ),
        );
      } else if (result.pinned) {
        final post = _find(postId);
        final previous = _pinned;
        if (post != null) {
          _pinned = post.copyWith(pinned: true);
          _wall = _wall.copyWith(
            posts: List.unmodifiable([
              if (previous != null && previous.postId != postId)
                previous.copyWith(pinned: false),
              for (final existing in _wall.posts)
                if (existing.postId != postId) existing,
            ]),
          );
        }
      } else if (_pinned?.postId == postId) {
        final post = _pinned!.copyWith(pinned: false);
        _pinned = null;
        _wall = _wall.copyWith(
          posts: List.unmodifiable(
            [post, ..._wall.posts]
              ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs)),
          ),
        );
      }
      return null;
    } on PagesException catch (error) {
      return error.failure;
    } finally {
      _postOpsInFlight.remove(postId);
      _notify();
    }
  }

  PagePostView? _find(String postId) {
    if (_pinned?.postId == postId) return _pinned;
    for (final post in _wall.posts) {
      if (post.postId == postId) return post;
    }
    for (final post in _photos.posts) {
      if (post.postId == postId) return post;
    }
    return null;
  }

  /// Posts of this wall created since UTC midnight of [now]: the owner's
  /// known part of today's publish budget (§1.1).
  int postedSince(DateTime now) {
    final utc = now.toUtc();
    final midnight = DateTime.utc(utc.year, utc.month, utc.day);
    return wallPosts.where((post) => !post.createdAt.isBefore(midnight)).length;
  }

  /// A post the post detail changed (like, comment count, comments switch)
  /// or removed.
  void _onChange(PagePostChange change) {
    if (_disposed) return;
    final existing = _find(change.postId);
    if (existing == null) return;
    switch (change) {
      case PagePostUpdated(:final post):
        _replace(post.copyWith(pinned: existing.pinned));
      case PagePostRemoved(:final postId):
        if (_pinned?.postId == postId) _pinned = null;
        _wall = _wall.copyWith(
          posts: List.unmodifiable(
            _wall.posts.where((p) => p.postId != postId),
          ),
        );
        _photos = _photos.copyWith(
          posts: List.unmodifiable(
            _photos.posts.where((p) => p.postId != postId),
          ),
        );
    }
    _notify();
  }

  void _replace(PagePostView post) {
    if (_pinned?.postId == post.postId) _pinned = post;
    List<PagePostView> swap(List<PagePostView> list) => List.unmodifiable([
      for (final existing in list)
        existing.postId == post.postId ? post : existing,
    ]);
    _wall = _wall.copyWith(posts: swap(_wall.posts));
    _photos = _photos.copyWith(posts: swap(_photos.posts));
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_eventsSub.cancel());
    super.dispose();
  }
}
