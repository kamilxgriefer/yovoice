part of 'page_views.dart';

/// The post-level wire views (spec premium-pages §2.4-§2.6, §2.10): the
/// post detail with its comments, the upload reservation, and the results
/// of publish, like, comment, comment delete and report. Same parsing rule
/// as every Pages view: known keys required, unknown keys ignored.

/// `pc_` + 40 lowercase hex, always server-allocated (§1.1).
final RegExp pageCommentIdPattern = RegExp(r'^pc_[a-f0-9]{40}$');

/// CommentView (§2.5): `{commentId, authorId, authorName, text,
/// createdAtMs, isOwnPage}`. Identity is resolved by the server at read
/// time; [isOwnPage] marks a reply written by the Page itself ("Autor").
class PageCommentView {
  const PageCommentView({
    required this.commentId,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAtMs,
    required this.isOwnPage,
  });

  final String commentId;
  final String authorId;
  final String authorName;
  final String text;
  final int createdAtMs;
  final bool isOwnPage;

  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true);

  /// Null when the id is not a comment id (the item is skipped).
  static PageCommentView? fromWire(Object? raw) {
    const what = 'CommentView';
    final map = _object(raw, what);
    final commentId = _string(map, 'commentId', what);
    final authorId = _string(map, 'authorId', what);
    final authorName = _string(map, 'authorName', what);
    final text = _string(map, 'text', what);
    final createdAtMs = _int(map, 'createdAtMs', what);
    final isOwnPage = _bool(map, 'isOwnPage', what);
    if (!pageCommentIdPattern.hasMatch(commentId) || authorId.isEmpty) {
      return null;
    }
    return PageCommentView(
      commentId: commentId,
      authorId: authorId,
      authorName: authorName,
      text: text,
      createdAtMs: createdAtMs,
      isOwnPage: isOwnPage,
    );
  }
}

/// `getPagePostV1 {postId, commentCursor}` → `{schemaVersion, post,
/// comments, nextCommentCursor, hasMoreComments}`. Comments come newest
/// first, 20 per page.
class PagePostDetailPage {
  const PagePostDetailPage({
    required this.post,
    required this.comments,
    required this.nextCommentCursor,
    required this.hasMoreComments,
  });

  final PagePostView post;
  final List<PageCommentView> comments;
  final String? nextCommentCursor;
  final bool hasMoreComments;

  static PagePostDetailPage fromWire(Object? raw) {
    const what = 'PagePostDetail';
    final map = _object(raw, what);
    _int(map, 'schemaVersion', what);
    final post = PagePostView.fromWire(_required(map, 'post', what));
    final comments = _items(
      _list(map, 'comments', what),
      PageCommentView.fromWire,
    );
    final nextCursor = _nullableString(map, 'nextCommentCursor', what);
    final hasMore = _bool(map, 'hasMoreComments', what);
    if (post == null) {
      // A post this client cannot render (a future kind) cannot be shown
      // as a detail either; the screen treats it as unavailable.
      throw const PagesContractException('PagePostDetail.post: unknown.');
    }
    return PagePostDetailPage(
      post: post,
      comments: comments,
      nextCommentCursor: nextCursor,
      hasMoreComments: hasMore && nextCursor != null,
    );
  }
}

/// One reserved upload slot (§2.4): where to put the object and the exact
/// custom metadata Storage rules require.
class PageMediaSlot {
  const PageMediaSlot({
    required this.mediaId,
    required this.storagePath,
    required this.metadata,
    required this.expiresAtMs,
  });

  final String mediaId;
  final String storagePath;
  final Map<String, String> metadata;
  final int expiresAtMs;

  static const List<String> metadataKeys = <String>[
    'yovoiceMediaId',
    'yovoiceMediaType',
    'yovoicePageId',
    'yovoicePostId',
  ];

  static PageMediaSlot fromWire(Object? raw) {
    const what = 'MediaSlot';
    final map = _object(raw, what);
    final mediaId = _string(map, 'mediaId', what);
    final storagePath = _string(map, 'storagePath', what);
    final metadataRaw = _object(_required(map, 'metadata', what), what);
    final expiresAtMs = _int(map, 'expiresAt', what);
    final metadata = <String, String>{};
    for (final key in metadataKeys) {
      metadata[key] = _string(metadataRaw, key, '$what.metadata');
    }
    if (!pageMediaIdPattern.hasMatch(mediaId) ||
        !storagePath.startsWith('page_posts/') ||
        storagePath.contains('..')) {
      throw const PagesContractException('MediaSlot: bad id or path.');
    }
    return PageMediaSlot(
      mediaId: mediaId,
      storagePath: storagePath,
      metadata: Map.unmodifiable(metadata),
      expiresAtMs: expiresAtMs,
    );
  }
}

/// `reservePagePostMediaV1` → `{postId, items:[slot]}` (server-allocated
/// `postId`, reused only by a retry with the same `requestId`).
class PageMediaReservation {
  const PageMediaReservation({required this.postId, required this.slots});

  final String postId;
  final List<PageMediaSlot> slots;

  static PageMediaReservation fromWire(Object? raw) {
    const what = 'MediaReservation';
    final map = _object(raw, what);
    final postId = _string(map, 'postId', what);
    final slots = [
      for (final item in _list(map, 'items', what))
        PageMediaSlot.fromWire(item),
    ];
    if (!pagePostIdPattern.hasMatch(postId) || slots.isEmpty) {
      throw const PagesContractException('MediaReservation: bad postId.');
    }
    return PageMediaReservation(
      postId: postId,
      slots: List.unmodifiable(slots),
    );
  }
}

/// `pagePostEngagementV1 like|unlike` → `{schemaVersion, op, postId, liked,
/// changed, likeCount}`.
class PageLikeResult {
  const PageLikeResult({required this.liked, required this.likeCount});

  final bool liked;
  final int likeCount;

  static PageLikeResult fromWire(Object? raw) {
    const what = 'PageLike';
    final map = _object(raw, what);
    return PageLikeResult(
      liked: _bool(map, 'liked', what),
      likeCount: _count(map, 'likeCount', what),
    );
  }
}

/// `pagePostEngagementV1 comment` → `{schemaVersion, op, postId, comment,
/// commentCount}`.
class PageCommentResult {
  const PageCommentResult({required this.comment, required this.commentCount});

  final PageCommentView comment;
  final int commentCount;

  static PageCommentResult fromWire(Object? raw) {
    const what = 'PageComment';
    final map = _object(raw, what);
    final comment = PageCommentView.fromWire(_required(map, 'comment', what));
    final commentCount = _count(map, 'commentCount', what);
    if (comment == null) {
      throw const PagesContractException('PageComment.comment: bad id.');
    }
    return PageCommentResult(comment: comment, commentCount: commentCount);
  }
}

/// `createPageReportV1` targets (§2.10).
enum PageReportTarget {
  page('page'),
  post('pagePost'),
  comment('pagePostComment');

  const PageReportTarget(this.wire);
  final String wire;
}
