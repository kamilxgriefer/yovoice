import 'package:flutter/foundation.dart';

import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/services/page_post_events.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';

enum PagePostDetailStatus { loading, ready, error, unavailable }

/// Why the comment composer is replaced by an explanatory line (§4.5).
enum PageCommentsClosed {
  /// The Page is read-only (D14): nobody but the owner may comment.
  readOnly,

  /// The owner turned comments off for this post.
  byPage,
}

/// The post detail A "karta + wątek" (spec premium-pages §2.5
/// `getPagePostV1`, §2.6, §4.5): the post, its comments 20 per page
/// (newest first), the like, the comment composer and the owner's comment
/// deletion. Every accepted change is broadcast through [PagePostEvents] so
/// the wall and the profile under it stay in step.
class PagePostDetailController extends ChangeNotifier {
  PagePostDetailController({
    required PagesService service,
    required this.postId,
    required this.viewerId,
    PagePostView? initial,
    bool pageReadOnly = false,
    PagePostEvents? events,
  }) : _service = service,
       _post = initial,
       _pageReadOnly = pageReadOnly,
       _events = events ?? PagePostEvents.instance,
       _status = PagePostDetailStatus.loading;

  final PagesService _service;
  final String postId;
  final String viewerId;
  final PagePostEvents _events;

  PagePostDetailStatus _status;
  PagePostView? _post;
  List<PageCommentView> _comments = const <PageCommentView>[];
  bool _commentsLoaded = false;
  String? _cursor;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  bool _likeBusy = false;
  bool _sending = false;
  bool _togglingComments = false;
  bool _pageReadOnly;
  final Set<String> _deleting = <String>{};
  String? _commentRequestId;
  String? _commentRequestText;
  int _generation = 0;
  bool _disposed = false;

  PagePostDetailStatus get status => _status;
  PagePostView? get post => _post;
  List<PageCommentView> get comments => _comments;
  bool get commentsLoaded => _commentsLoaded;
  bool get hasMore => _hasMore;
  bool get loadingMore => _loadingMore;
  bool get loadMoreFailed => _loadMoreFailed;
  bool get likeBusy => _likeBusy;
  bool get sending => _sending;
  bool get togglingComments => _togglingComments;
  bool isDeleting(String commentId) => _deleting.contains(commentId);

  /// The viewer owns the Page the post is on.
  bool get isOwner => _post != null && _post!.pageId == viewerId;

  /// Null while the viewer may comment.
  PageCommentsClosed? get closed {
    final post = _post;
    if (post == null) return null;
    if (!post.commentsEnabled) return PageCommentsClosed.byPage;
    if (_pageReadOnly && !isOwner) return PageCommentsClosed.readOnly;
    return null;
  }

  bool canDelete(PageCommentView comment) =>
      isOwner || comment.authorId == viewerId;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final generation = ++_generation;
    // The superseded comment page is dropped; never leave its spinner on.
    _loadingMore = false;
    if (_post == null) {
      _status = PagePostDetailStatus.loading;
    }
    _notify();
    try {
      final page = await _service.getPost(postId);
      if (generation != _generation || _disposed) return;
      _post = page.post;
      _comments = page.comments;
      _cursor = page.nextCommentCursor;
      _hasMore = page.hasMoreComments;
      _loadMoreFailed = false;
      _commentsLoaded = true;
      _status = PagePostDetailStatus.ready;
      _events.updated(page.post);
    } on PagesException catch (error) {
      if (generation != _generation || _disposed) return;
      if (error.failure == PagesFailure.unavailable ||
          error.failure == PagesFailure.notEnabled) {
        _status = PagePostDetailStatus.unavailable;
        _events.removed(postId);
      } else {
        _status = PagePostDetailStatus.error;
      }
    }
    _notify();
  }

  Future<void> loadMore() async {
    final cursor = _cursor;
    if (_loadingMore || !_hasMore || cursor == null) return;
    final generation = _generation;
    _loadingMore = true;
    _loadMoreFailed = false;
    _notify();
    try {
      final page = await _service.getPost(postId, commentCursor: cursor);
      if (generation != _generation || _disposed) return;
      final seen = {for (final comment in _comments) comment.commentId};
      _comments = List.unmodifiable([
        ..._comments,
        for (final comment in page.comments)
          if (!seen.contains(comment.commentId)) comment,
      ]);
      _cursor = page.nextCommentCursor;
      _hasMore = page.hasMoreComments;
    } on PagesException {
      if (generation != _generation || _disposed) return;
      _loadMoreFailed = true;
    } finally {
      if (generation == _generation) {
        _loadingMore = false;
        _notify();
      }
    }
  }

  /// Likes or unlikes the post: the heart moves at once and rolls back if
  /// the server refuses.
  Future<PagesFailure?> toggleLike() async {
    final before = _post;
    if (before == null || _likeBusy) return null;
    final liked = !before.callerLiked;
    _post = before.copyWith(
      callerLiked: liked,
      likeCount: (before.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 31),
    );
    _likeBusy = true;
    _notify();
    try {
      await _service.setLiked(postId, liked: liked);
      _events.updated(_post!);
      return null;
    } on PagesException catch (error) {
      _post = _post?.copyWith(
        callerLiked: before.callerLiked,
        likeCount: before.likeCount,
      );
      return error.failure;
    } finally {
      _likeBusy = false;
      _notify();
    }
  }

  /// Publishes [text] as a comment. A retry of the same text reuses its
  /// request id, so a lost answer never doubles the comment.
  Future<PagesFailure?> comment(String text) async {
    final trimmed = text.trim();
    if (_sending || trimmed.isEmpty) return null;
    if (_commentRequestText != trimmed) {
      _commentRequestText = trimmed;
      _commentRequestId = _service.newRequestId();
    }
    _sending = true;
    _notify();
    try {
      final result = await _service.comment(
        postId,
        trimmed,
        requestId: _commentRequestId,
      );
      if (_disposed) return null;
      _commentRequestText = null;
      _commentRequestId = null;
      _comments = List.unmodifiable([
        result.comment,
        for (final comment in _comments)
          if (comment.commentId != result.comment.commentId) comment,
      ]);
      final post = _post;
      if (post != null) {
        _post = post.copyWith(commentCount: result.commentCount);
        _events.updated(_post!);
      }
      return null;
    } on PagesException catch (error) {
      if (error.failure == PagesFailure.readOnly) _pageReadOnly = true;
      if (error.failure == PagesFailure.commentsOff) {
        _post = _post?.copyWith(commentsEnabled: false);
      }
      if (error.failure != PagesFailure.network) {
        // A refusal is final for this text: a retry is a new comment.
        _commentRequestText = null;
        _commentRequestId = null;
      }
      return error.failure;
    } finally {
      _sending = false;
      _notify();
    }
  }

  Future<PagesFailure?> deleteComment(String commentId) async {
    if (_deleting.contains(commentId)) return null;
    _deleting.add(commentId);
    _notify();
    try {
      await _service.deleteComment(commentId);
      if (_disposed) return null;
      final had = _comments.any((c) => c.commentId == commentId);
      _comments = List.unmodifiable(
        _comments.where((c) => c.commentId != commentId),
      );
      final post = _post;
      if (post != null && had) {
        _post = post.copyWith(
          commentCount: (post.commentCount - 1).clamp(0, 1 << 31),
        );
        _events.updated(_post!);
      }
      return null;
    } on PagesException catch (error) {
      return error.failure;
    } finally {
      _deleting.remove(commentId);
      _notify();
    }
  }

  /// The owner's comments switch (`managePagePostV1 setCommentsEnabled`).
  Future<PagesFailure?> setCommentsEnabled(bool enabled) async {
    final post = _post;
    if (post == null || _togglingComments) return null;
    _togglingComments = true;
    _notify();
    try {
      final result = await _service.setCommentsEnabled(
        postId,
        enabled: enabled,
      );
      if (_disposed) return null;
      _post = _post?.copyWith(commentsEnabled: result.commentsEnabled);
      if (_post != null) _events.updated(_post!);
      return null;
    } on PagesException catch (error) {
      return error.failure;
    } finally {
      _togglingComments = false;
      _notify();
    }
  }

  /// The owner's delete: the post leaves every list on success.
  Future<PagesFailure?> deletePost() async {
    try {
      await _service.managePost(postId, PagePostOp.delete);
      _events.removed(postId);
      return null;
    } on PagesException catch (error) {
      return error.failure;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
