import 'package:flutter/foundation.dart';

/// What a service has learned about the DEPLOYED comment-like contract
/// (spec §3.6, §5.6).
///
/// `getVoiceMomentViewV2` and `getReelViewV2` accept the opt-in request flag
/// `includeCommentLikes` only once the comment-like backend is deployed; an
/// older deployment refuses the unknown key with `invalid-argument`. The
/// client therefore *probes*: it sends the flag, and only when the identical
/// request succeeds without it does it record the feature as undeployed.
///
/// While the answer is [unknown] or [unsupported] a comment row shows no
/// heart and no count: a control that cannot record anything is worse than
/// no control, so there is no "Coming soon" heart either.
enum CommentLikeSupport {
  /// No flagged view has been answered yet.
  unknown,

  /// A view answered the flag with its `commentLikes` map.
  supported,

  /// The deployed view refused the flag and answered without it.
  unsupported,
}

/// One comment's public like count and the caller's own like, exactly as a
/// flagged view projects it: `{likeCount: int >= 0, callerLiked: bool}`.
@immutable
class CommentLikeState {
  const CommentLikeState({required this.likeCount, required this.callerLiked});

  final int likeCount;
  final bool callerLiked;

  factory CommentLikeState.parse(Object? value) {
    if (value is! Map) {
      throw const FormatException('Comment like state must be an object.');
    }
    final keys = value.keys.toSet();
    if (keys.length != 2 ||
        !keys.contains('likeCount') ||
        !keys.contains('callerLiked')) {
      throw const FormatException('Comment like state has an unknown shape.');
    }
    final count = value['likeCount'];
    final liked = value['callerLiked'];
    if (count is! int || count < 0 || liked is! bool) {
      throw const FormatException('Malformed comment like state.');
    }
    return CommentLikeState(likeCount: count, callerLiked: liked);
  }

  @override
  bool operator ==(Object other) =>
      other is CommentLikeState &&
      other.likeCount == likeCount &&
      other.callerLiked == callerLiked;

  @override
  int get hashCode => Object.hash(likeCount, callerLiked);

  @override
  String toString() =>
      'CommentLikeState(likeCount: $likeCount, callerLiked: $callerLiked)';
}

/// Parses a flagged view's `commentLikes` object (spec §3.6): one entry per
/// projected comment and nothing else, so its key set must EQUAL
/// [commentIds]. A missing or an extra entry is a contract break, not an
/// upgrade, and the whole view is refused like any other malformed key.
Map<String, CommentLikeState> parseCommentLikes(
  Object? value,
  Iterable<String> commentIds,
) {
  if (value is! Map) {
    throw const FormatException('Comment likes must be an object.');
  }
  final expected = commentIds.toSet();
  final parsed = <String, CommentLikeState>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String || !expected.contains(key)) {
      throw const FormatException('Comment likes name an unknown comment.');
    }
    parsed[key] = CommentLikeState.parse(entry.value);
  }
  if (parsed.length != expected.length) {
    throw const FormatException('Comment likes miss a projected comment.');
  }
  return Map<String, CommentLikeState>.unmodifiable(parsed);
}

/// The authoritative answer of `setMomentCommentLikeV1` /
/// `setReelCommentLikeV1` (spec §3.4, §3.5), with the parent id already
/// checked by the service that parsed it.
@immutable
class CommentLikeResult {
  const CommentLikeResult({
    required this.commentId,
    required this.liked,
    required this.changed,
    required this.likeCount,
  });

  final String commentId;
  final bool liked;

  /// False when the server already held this state: a successful no-op.
  final bool changed;
  final int likeCount;

  CommentLikeState get state =>
      CommentLikeState(likeCount: likeCount, callerLiked: liked);

  /// Parses the exact response `{parentKey, commentId, liked, changed,
  /// likeCount}`, where [parentKey] is `momentId` or `reelId` and must equal
  /// [parentId], and `commentId` must equal [commentId].
  factory CommentLikeResult.parse(
    Object? value, {
    required String parentKey,
    required String parentId,
    required String commentId,
    required bool liked,
  }) {
    if (value is! Map) {
      throw const FormatException('Comment like result must be an object.');
    }
    final keys = value.keys.toSet();
    const required = <String>{'commentId', 'liked', 'changed', 'likeCount'};
    if (keys.length != required.length + 1 ||
        !keys.contains(parentKey) ||
        !keys.containsAll(required)) {
      throw const FormatException('Comment like result has an unknown shape.');
    }
    final resultLiked = value['liked'];
    final changed = value['changed'];
    final count = value['likeCount'];
    if (value[parentKey] != parentId ||
        value['commentId'] != commentId ||
        resultLiked is! bool ||
        resultLiked != liked ||
        changed is! bool ||
        count is! int ||
        count < 0) {
      throw const FormatException('Malformed comment like result.');
    }
    return CommentLikeResult(
      commentId: commentId,
      liked: resultLiked,
      changed: changed,
      likeCount: count,
    );
  }
}
