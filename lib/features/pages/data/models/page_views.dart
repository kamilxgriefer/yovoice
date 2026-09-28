/// The Premium Pages read views (spec premium-pages §2.5, §2.7): PostView,
/// MediaView, PageCard and the feed / Find responses.
///
/// Parsing rule (§2.5): the server's output is exact, so the client
/// **requires every known key** (a missing key or a wrong type is a
/// [FormatException]) and **ignores unknown keys**, so a v1.1 key never
/// breaks a v1 client. An item whose enum value this client does not know (a
/// future post kind, media type or Page kind) is skipped, not guessed.
/// Counters that are negative or not integers read as 0 (§1.7).
library;

import 'package:yovoice/shared/identity/public_identity.dart';

part 'page_post_views.dart';
part 'page_profile_views.dart';

/// `pp_` + 40 lowercase hex, always server-allocated (§1.1).
final RegExp pagePostIdPattern = RegExp(r'^pp_[a-f0-9]{40}$');

/// `pm_` + 40 lowercase hex (§1.1).
final RegExp pageMediaIdPattern = RegExp(r'^pm_[a-f0-9]{40}$');

enum PagePostKind {
  text('text'),
  photo('photo'),
  voice('voice');

  const PagePostKind(this.wire);
  final String wire;

  static PagePostKind? fromWire(Object? raw) {
    for (final kind in values) {
      if (kind.wire == raw) return kind;
    }
    return null;
  }
}

enum PageMediaType {
  image('image'),
  audio('audio');

  const PageMediaType(this.wire);
  final String wire;

  static PageMediaType? fromWire(Object? raw) {
    for (final type in values) {
      if (type.wire == raw) return type;
    }
    return null;
  }
}

/// A post's visibility for this viewer: readers only ever get `published`;
/// `held` reaches the owner (and staff) with a notice.
enum PagePostState {
  published('published'),
  held('held');

  const PagePostState(this.wire);
  final String wire;

  static PagePostState? fromWire(Object? raw) {
    for (final state in values) {
      if (state.wire == raw) return state;
    }
    return null;
  }
}

/// Thrown by the parsers when a known key is missing or has the wrong type.
class PagesContractException extends FormatException {
  const PagesContractException(super.message);
}

Map<String, Object?> _object(Object? raw, String what) {
  if (raw is! Map) throw PagesContractException('$what is not an object.');
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) throw PagesContractException('$what has a bad key.');
    result[key] = entry.value;
  }
  return result;
}

Object? _required(Map<String, Object?> map, String key, String what) {
  if (!map.containsKey(key)) {
    throw PagesContractException('$what is missing "$key".');
  }
  return map[key];
}

String _string(Map<String, Object?> map, String key, String what) {
  final value = _required(map, key, what);
  if (value is! String) throw PagesContractException('$what.$key: string.');
  return value;
}

String? _nullableString(Map<String, Object?> map, String key, String what) {
  final value = _required(map, key, what);
  if (value == null) return null;
  if (value is! String) throw PagesContractException('$what.$key: string?');
  return value;
}

bool _bool(Map<String, Object?> map, String key, String what) {
  final value = _required(map, key, what);
  if (value is! bool) throw PagesContractException('$what.$key: bool.');
  return value;
}

int? _nullableInt(Map<String, Object?> map, String key, String what) {
  final value = _required(map, key, what);
  if (value == null) return null;
  if (value is int) return value;
  if (value is double && value == value.truncateToDouble()) {
    return value.toInt();
  }
  throw PagesContractException('$what.$key: int?');
}

int _int(Map<String, Object?> map, String key, String what) {
  final value = _nullableInt(map, key, what);
  if (value == null) throw PagesContractException('$what.$key: int.');
  return value;
}

/// A counter (§1.7): present, but negative / non-integer values read as 0.
int _count(Map<String, Object?> map, String key, String what) {
  final value = _required(map, key, what);
  if (value is int) return value < 0 ? 0 : value;
  if (value is double &&
      value.isFinite &&
      value >= 0 &&
      value == value.truncateToDouble()) {
    return value.toInt();
  }
  return 0;
}

List<Object?> _list(Map<String, Object?> map, String key, String what) {
  final value = _required(map, key, what);
  if (value is! List) throw PagesContractException('$what.$key: list.');
  return value;
}

/// One media entry of a post; bytes come only through
/// `getPagePostMediaAccessV1` grants.
class PageMediaView {
  const PageMediaView({
    required this.mediaId,
    required this.type,
    required this.contentType,
    this.width,
    this.height,
    this.durationMs,
  });

  final String mediaId;
  final PageMediaType type;
  final String contentType;

  /// Client-declared layout size (images only, §1.3).
  final int? width;
  final int? height;

  /// From the trusted probe (audio only).
  final int? durationMs;

  /// Null for an unknown media type: the whole post is then skipped.
  static PageMediaView? fromWire(Object? raw) {
    const what = 'MediaView';
    final map = _object(raw, what);
    final mediaId = _string(map, 'mediaId', what);
    final typeRaw = _required(map, 'type', what);
    final contentType = _string(map, 'contentType', what);
    final width = _nullableInt(map, 'width', what);
    final height = _nullableInt(map, 'height', what);
    final durationMs = _nullableInt(map, 'durationMs', what);
    final type = PageMediaType.fromWire(typeRaw);
    if (type == null) return null;
    return PageMediaView(
      mediaId: mediaId,
      type: type,
      contentType: contentType,
      width: width,
      height: height,
      durationMs: durationMs,
    );
  }

  /// Width ÷ height when both are declared and sane, else null.
  double? get aspectRatio {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }
}

/// PostView (§2.5).
class PagePostView {
  const PagePostView({
    required this.postId,
    required this.pageId,
    required this.pageName,
    required this.pageKind,
    required this.kind,
    required this.text,
    required this.media,
    required this.createdAtMs,
    required this.likeCount,
    required this.commentCount,
    required this.callerLiked,
    required this.commentsEnabled,
    required this.state,
    required this.pinned,
  });

  final String postId;
  final String pageId;
  final String pageName;
  final PageKind pageKind;
  final PagePostKind kind;
  final String text;
  final List<PageMediaView> media;
  final int createdAtMs;
  final int likeCount;
  final int commentCount;
  final bool callerLiked;
  final bool commentsEnabled;
  final PagePostState state;
  final bool pinned;

  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true);

  List<PageMediaView> get images => [
    for (final entry in media)
      if (entry.type == PageMediaType.image) entry,
  ];

  PageMediaView? get voice {
    for (final entry in media) {
      if (entry.type == PageMediaType.audio) return entry;
    }
    return null;
  }

  /// Null when this client cannot render the post (an unknown enum value, or
  /// media that does not match the post kind); the caller skips it.
  static PagePostView? fromWire(Object? raw) {
    const what = 'PostView';
    final map = _object(raw, what);
    final postId = _string(map, 'postId', what);
    final pageId = _string(map, 'pageId', what);
    final pageName = _string(map, 'pageName', what);
    final pageKindRaw = _required(map, 'pageKind', what);
    final kindRaw = _required(map, 'kind', what);
    final text = _string(map, 'text', what);
    final mediaRaw = _list(map, 'media', what);
    final createdAtMs = _int(map, 'createdAtMs', what);
    final likeCount = _count(map, 'likeCount', what);
    final commentCount = _count(map, 'commentCount', what);
    final callerLiked = _bool(map, 'callerLiked', what);
    final commentsEnabled = _bool(map, 'commentsEnabled', what);
    final stateRaw = _required(map, 'state', what);
    final pinned = _bool(map, 'pinned', what);

    final media = <PageMediaView>[];
    for (final entry in mediaRaw) {
      final parsed = PageMediaView.fromWire(entry);
      if (parsed == null) return null;
      media.add(parsed);
    }
    final pageKind = PageKind.fromWire(pageKindRaw);
    final kind = PagePostKind.fromWire(kindRaw);
    final state = PagePostState.fromWire(stateRaw);
    if (pageKind == null || kind == null || state == null) return null;
    if (!pagePostIdPattern.hasMatch(postId) || pageId.isEmpty) return null;
    final shapeOk = switch (kind) {
      PagePostKind.text => media.isEmpty,
      PagePostKind.photo =>
        media.isNotEmpty &&
            media.length <= 10 &&
            media.every((m) => m.type == PageMediaType.image),
      PagePostKind.voice =>
        media.length == 1 && media.single.type == PageMediaType.audio,
    };
    if (!shapeOk) return null;
    return PagePostView(
      postId: postId,
      pageId: pageId,
      pageName: pageName,
      pageKind: pageKind,
      kind: kind,
      text: text,
      media: List.unmodifiable(media),
      createdAtMs: createdAtMs,
      likeCount: likeCount,
      commentCount: commentCount,
      callerLiked: callerLiked,
      commentsEnabled: commentsEnabled,
      state: state,
      pinned: pinned,
    );
  }

  PagePostView copyWith({
    bool? callerLiked,
    int? likeCount,
    int? commentCount,
    bool? commentsEnabled,
    bool? pinned,
  }) => PagePostView(
    postId: postId,
    pageId: pageId,
    pageName: pageName,
    pageKind: pageKind,
    kind: kind,
    text: text,
    media: media,
    createdAtMs: createdAtMs,
    likeCount: likeCount ?? this.likeCount,
    commentCount: commentCount ?? this.commentCount,
    callerLiked: callerLiked ?? this.callerLiked,
    commentsEnabled: commentsEnabled ?? this.commentsEnabled,
    state: state,
    pinned: pinned ?? this.pinned,
  );
}

/// PageCard (§2.7): one row of Find Pages, the feed's suggestions and the
/// desktop panel's followed list.
class PageCard {
  const PageCard({
    required this.pageId,
    required this.displayName,
    required this.kind,
    required this.category,
    required this.followerCount,
    required this.onYoVoiceSinceMs,
    required this.viewerFollows,
    required this.lastPostAtMs,
  });

  final String pageId;
  final String displayName;
  final PageKind kind;
  final String category;
  final int followerCount;
  final int? onYoVoiceSinceMs;
  final bool viewerFollows;
  final int? lastPostAtMs;

  static PageCard? fromWire(Object? raw) {
    const what = 'PageCard';
    final map = _object(raw, what);
    final pageId = _string(map, 'pageId', what);
    final displayName = _string(map, 'displayName', what);
    final kindRaw = _required(map, 'kind', what);
    final category = _string(map, 'category', what);
    final followerCount = _count(map, 'followerCount', what);
    final since = _nullableInt(map, 'onYoVoiceSinceMs', what);
    final viewerFollows = _bool(map, 'viewerFollows', what);
    final lastPostAtMs = _nullableInt(map, 'lastPostAtMs', what);
    final kind = PageKind.fromWire(kindRaw);
    if (kind == null || pageId.isEmpty) return null;
    return PageCard(
      pageId: pageId,
      displayName: displayName,
      kind: kind,
      category: category,
      followerCount: followerCount,
      onYoVoiceSinceMs: since,
      viewerFollows: viewerFollows,
      lastPostAtMs: lastPostAtMs,
    );
  }

  PageCard copyWith({bool? viewerFollows, int? followerCount}) => PageCard(
    pageId: pageId,
    displayName: displayName,
    kind: kind,
    category: category,
    followerCount: followerCount ?? this.followerCount,
    onYoVoiceSinceMs: onYoVoiceSinceMs,
    viewerFollows: viewerFollows ?? this.viewerFollows,
    lastPostAtMs: lastPostAtMs,
  );
}

List<T> _items<T>(List<Object?> raw, T? Function(Object?) parse) {
  final result = <T>[];
  for (final entry in raw) {
    final parsed = parse(entry);
    if (parsed != null) result.add(parsed);
  }
  return List.unmodifiable(result);
}

/// `getPagesFeedV1` → `{schemaVersion, posts, nextCursor, hasMore,
/// suggestions}`.
class PagesFeedPage {
  const PagesFeedPage({
    required this.posts,
    required this.nextCursor,
    required this.hasMore,
    required this.suggestions,
  });

  final List<PagePostView> posts;
  final String? nextCursor;
  final bool hasMore;

  /// Only on the first page; null otherwise.
  final List<PageCard>? suggestions;

  static PagesFeedPage fromWire(Object? raw) {
    const what = 'PagesFeed';
    final map = _object(raw, what);
    _int(map, 'schemaVersion', what);
    final posts = _items(_list(map, 'posts', what), PagePostView.fromWire);
    final nextCursor = _nullableString(map, 'nextCursor', what);
    final hasMore = _bool(map, 'hasMore', what);
    final suggestionsRaw = _required(map, 'suggestions', what);
    List<PageCard>? suggestions;
    if (suggestionsRaw != null) {
      if (suggestionsRaw is! List) {
        throw const PagesContractException('PagesFeed.suggestions: list?');
      }
      suggestions = _items(suggestionsRaw, PageCard.fromWire);
    }
    return PagesFeedPage(
      posts: posts,
      nextCursor: nextCursor,
      // A page with no cursor cannot be continued, whatever the flag says.
      hasMore: hasMore && nextCursor != null,
      suggestions: suggestions,
    );
  }
}

/// `findPagesV1` modes (§2.7).
enum FindPagesMode {
  suggest('suggest'),
  search('search'),
  following('following');

  const FindPagesMode(this.wire);
  final String wire;
}

/// `findPagesV1` → `{schemaVersion, pages, nextCursor, hasMore}`.
class FindPagesPage {
  const FindPagesPage({
    required this.pages,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<PageCard> pages;
  final String? nextCursor;
  final bool hasMore;

  static FindPagesPage fromWire(Object? raw) {
    const what = 'FindPages';
    final map = _object(raw, what);
    _int(map, 'schemaVersion', what);
    final pages = _items(_list(map, 'pages', what), PageCard.fromWire);
    final nextCursor = _nullableString(map, 'nextCursor', what);
    final hasMore = _bool(map, 'hasMore', what);
    return FindPagesPage(
      pages: pages,
      nextCursor: nextCursor,
      hasMore: hasMore && nextCursor != null,
    );
  }
}

/// One `getPagePostMediaAccessV1` grant: a 90 s V4 URL.
class PageMediaGrant {
  const PageMediaGrant({
    required this.mediaId,
    required this.url,
    required this.expiresAtMs,
  });

  final String mediaId;
  final Uri url;
  final int expiresAtMs;

  static PageMediaGrant? fromWire(Object? raw) {
    const what = 'MediaGrant';
    final map = _object(raw, what);
    final mediaId = _string(map, 'mediaId', what);
    final url = Uri.tryParse(_string(map, 'url', what));
    final expiresAtMs = _int(map, 'expiresAtMs', what);
    if (url == null || url.scheme != 'https') return null;
    return PageMediaGrant(mediaId: mediaId, url: url, expiresAtMs: expiresAtMs);
  }

  static List<PageMediaGrant> listFromWire(Object? raw) {
    const what = 'MediaAccess';
    final map = _object(raw, what);
    return _items(_list(map, 'grants', what), PageMediaGrant.fromWire);
  }
}
