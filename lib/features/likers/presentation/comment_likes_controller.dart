import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:yovoice/features/likers/data/models/comment_like.dart';

/// Sets the caller's like on one comment to [liked] and returns the server's
/// authoritative state (`MomentService.setCommentLike`,
/// `ReelService.setCommentLike`).
typedef CommentLikeSetter =
    Future<CommentLikeResult> Function(String commentId, {required bool liked});

/// How one tap on a comment heart ended.
enum CommentLikeToggleOutcome {
  /// The server confirmed; its count and state are now shown.
  applied,

  /// The server refused or could not be reached; the optimistic change was
  /// taken back. The host tells the viewer ("Couldn't update your like.").
  reverted,

  /// Nothing happened: the comment has no like state (unsupported), or a
  /// toggle for it is already in flight (single-flight per comment).
  ignored,
}

/// The comment-like state of one open thread, shared by the Voice Moment
/// detail thread, the Voice comments page and the Yeel thread (spec §5.1,
/// §5.6).
///
/// - A page's `commentLikes` map is [adopt]ed as it loads. A view read
///   without the flag (a deployment that predates comment likes) adopts
///   `null`, which removes every heart: [stateOf] is then null for every
///   comment.
/// - [toggle] is optimistic, single-flight per comment, and adopts the
///   server's answer verbatim; a failure restores the state the tap started
///   from.
/// - A thread refresh landing while a toggle is in flight never overwrites
///   that comment's optimistic state; the toggle's own answer decides it.
/// - [canSeeLikers] mirrors the UX pre-gate for the VIP-only "Who liked"
///   link. It is watched only once the thread has hearts, so a thread on an
///   old deployment opens no extra listener.
class CommentLikesController extends ChangeNotifier {
  CommentLikesController({
    required CommentLikeSetter setLike,
    Stream<bool> Function()? watchCanSeeLikers,
  }) : _setLike = setLike,
       _watchCanSeeLikers = watchCanSeeLikers;

  final CommentLikeSetter _setLike;
  final Stream<bool> Function()? _watchCanSeeLikers;

  final Map<String, CommentLikeState> _states = <String, CommentLikeState>{};
  final Set<String> _pending = <String>{};
  StreamSubscription<bool>? _accessSubscription;
  bool _canSeeLikers = false;
  bool _disposed = false;

  /// The like state to draw for [commentId], or null for "no heart".
  CommentLikeState? stateOf(String commentId) => _states[commentId];

  /// A toggle for [commentId] is waiting for the server.
  bool isPending(String commentId) => _pending.contains(commentId);

  /// The viewer may open likers lists (paid Premium, staff preview or a
  /// canonical VIP grant), per the client pre-gate. Presentation only: the
  /// server decides, and a stale `false` still leads to the list through the
  /// count, whose flow re-checks.
  bool get canSeeLikers => _canSeeLikers;

  /// Takes one loaded page's `commentLikes`.
  ///
  /// [replace] drops every state the page does not name (a thread reload
  /// from its first page); otherwise the page merges into what is loaded (a
  /// next page, a re-read tail). `null` means the view was answered without
  /// comment likes: every heart goes, pending or not, because a control that
  /// cannot record anything is worse than none.
  void adopt(Map<String, CommentLikeState>? states, {required bool replace}) {
    if (_disposed) return;
    if (states == null) {
      if (_states.isEmpty) return;
      _states.clear();
      notifyListeners();
      return;
    }
    if (replace) {
      _states.removeWhere(
        (id, _) => !_pending.contains(id) && !states.containsKey(id),
      );
    }
    for (final entry in states.entries) {
      if (_pending.contains(entry.key)) continue;
      _states[entry.key] = entry.value;
    }
    _watchAccess();
    notifyListeners();
  }

  /// Forgets every state (the thread was closed or became unavailable).
  void clear() {
    if (_disposed || _states.isEmpty) return;
    _states.clear();
    notifyListeners();
  }

  /// Flips the caller's like on [commentId] optimistically and sends it.
  Future<CommentLikeToggleOutcome> toggle(String commentId) async {
    final before = _states[commentId];
    if (_disposed || before == null || !_pending.add(commentId)) {
      return CommentLikeToggleOutcome.ignored;
    }
    final liked = !before.callerLiked;
    final optimisticCount = before.likeCount + (liked ? 1 : -1);
    _states[commentId] = CommentLikeState(
      likeCount: optimisticCount < 0 ? 0 : optimisticCount,
      callerLiked: liked,
    );
    notifyListeners();
    var outcome = CommentLikeToggleOutcome.applied;
    try {
      final result = await _setLike(commentId, liked: liked);
      if (_disposed) return outcome;
      // The same rule as the failure path: `adopt(null)` or `clear()` while
      // the request was in flight removed this heart, and the answer must
      // not bring it back.
      if (_states.containsKey(commentId)) _states[commentId] = result.state;
    } catch (_) {
      outcome = CommentLikeToggleOutcome.reverted;
      if (_disposed) return outcome;
      // Restore only while the row is still loaded: a reload that dropped
      // the comment meanwhile must not resurrect a heart for it.
      if (_states.containsKey(commentId)) _states[commentId] = before;
    } finally {
      _pending.remove(commentId);
      if (!_disposed) notifyListeners();
    }
    return outcome;
  }

  void _watchAccess() {
    final watch = _watchCanSeeLikers;
    if (watch == null || _accessSubscription != null) return;
    try {
      _accessSubscription = watch().listen(
        (allowed) {
          if (_disposed || allowed == _canSeeLikers) return;
          _canSeeLikers = allowed;
          notifyListeners();
        },
        onError: (Object _, StackTrace _) {
          if (_disposed || !_canSeeLikers) return;
          _canSeeLikers = false;
          notifyListeners();
        },
      );
    } catch (_) {
      _canSeeLikers = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_accessSubscription?.cancel());
    super.dispose();
  }
}
