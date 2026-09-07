import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/reel_engagement_copy.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_comment_report_sheet.dart';
import 'package:yovoice/features/reels/presentation/widgets/reel_engagement_bar.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';
import 'package:yovoice/shared/widgets/states/yo_empty_state.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

/// One loaded page of a Reel thread, kept with the cursor that produced it.
///
/// Retaining the cursor is what lets a freshly posted comment be re-read from
/// the server in place, instead of the client inventing an author name and a
/// timestamp for a document only the backend actually wrote.
@immutable
class _CommentPage {
  const _CommentPage({required this.cursor, required this.comments});

  final String? cursor;
  final List<ReelComment> comments;
}

/// One report this viewer decided to send, held across retries.
///
/// The server binds one request id to one exact input, so the id may be
/// reused only while the target, the reason and the note are all unchanged.
/// Keeping the decision beside the id is what makes that checkable — and it
/// is also what lets a retry re-open the sheet with the reporter's own words
/// still in it instead of asking them to type the note again.
@immutable
class _ReportAttempt {
  const _ReportAttempt({
    required this.commentId,
    required this.request,
    required this.requestId,
  });

  final String commentId;
  final ReelCommentReportRequest request;
  final String requestId;

  bool matches(String commentId, ReelCommentReportRequest request) =>
      this.commentId == commentId && this.request == request;
}

/// The Reel comment thread: oldest first, paginated, with a composer.
///
/// One widget serves both presentations — a modal sheet on narrow and medium
/// widths, and an inline column in the wide layout's context panel — so the
/// two can never drift apart in behaviour. Only spacing adapts, and it adapts
/// to the width it is actually given rather than to a device label.
///
/// THREE DIFFERENT AUTHORITIES LIVE ON A COMMENT ROW, and the row offers at
/// most one of them because they are not interchangeable:
///
///  - **Delete** — your own words, `deleteReelComment`.
///  - **Report** — somebody else's words, `createReelCommentReport`. Filing
///    one changes nothing that is visible: the reporter is not the person who
///    decides, so the comment stays exactly where it was.
///  - **Remove** — somebody else's words on a Reel THIS ACCOUNT AUTHORED,
///    `removeReelComment`. Destructive and irreversible, so it confirms.
///
/// The server is the only authority on all three. Everything decided here is
/// about which control to *offer*; a control that should not have been shown
/// meets a refusal, and the refusal is what the viewer is told.
class ReelCommentsView extends StatefulWidget {
  const ReelCommentsView({
    required this.reel,
    required this.service,
    required this.onReelUpdated,
    this.commentLimit = ReelView.maxCommentLimit,
    this.autofocusComposer = false,
    this.gutter,
    super.key,
  });

  final Reel reel;
  final ReelService service;

  /// Reports server-authoritative engagement back to the feed so the card,
  /// the wide panel and this thread always show the same counts.
  final ValueChanged<Reel> onReelUpdated;
  final int commentLimit;
  final bool autofocusComposer;

  /// Overrides the horizontal gutter this view derives from its own width.
  ///
  /// The wide context panel sets it so the thread lines up with the header
  /// printed above it; the sheet lets the available width decide.
  final double? gutter;

  @override
  State<ReelCommentsView> createState() => _ReelCommentsViewState();
}

class _ReelCommentsViewState extends State<ReelCommentsView> {
  /// Bounds the follow-up reads after a post. One request covers the common
  /// case; the second exists only for a page that filled exactly.
  static const int _maxTailRequests = 2;

  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final List<_CommentPage> _pages = <_CommentPage>[];
  final Set<String> _deleting = <String>{};

  /// Comment ids with a moderation call in flight. Both sets exist so a row
  /// shows the operation that is actually running on it, and so a second tap
  /// cannot start a duplicate of either.
  final Set<String> _reporting = <String>{};
  final Set<String> _removing = <String>{};

  /// Comments this viewer has reported, kept for as long as the thread is
  /// open. Reporting is invisible by design — the comment does not move —
  /// so without this the only feedback is a snackbar that scrolls away, and
  /// the reporter is left wondering whether it went through. It is a local
  /// record of what THIS session sent, never a claim about the report's
  /// outcome.
  final Set<String> _reported = <String>{};

  /// The report currently being retried, if any. At most one: a person files
  /// one report at a time, and holding more would mean holding request ids
  /// for attempts nobody is going to make.
  _ReportAttempt? _reportAttempt;

  String? _nextCursor;
  Object? _error;
  Object? _composerError;
  bool _loading = true;
  bool _loadingMore = false;
  bool _posting = false;
  bool _posted = false;

  /// Held across retries so a lost acknowledgement replays to the same server
  /// comment instead of posting the same words twice. Cleared on success.
  String? _postRequestId;

  int _generation = 0;

  List<ReelComment> get _comments => <ReelComment>[
    for (final page in _pages) ...page.comments,
  ];

  String? get _viewerId => widget.service.currentUserId;

  @override
  void initState() {
    super.initState();
    _composer.addListener(_onComposerChanged);
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant ReelCommentsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reel.id != widget.reel.id ||
        !identical(oldWidget.service, widget.service)) {
      _composer.clear();
      _postRequestId = null;
      // A request id is bound to one target. Carrying one across a Reel
      // change would replay an old attempt against a new thread.
      _reportAttempt = null;
      _reported.clear();
      _load(reset: true);
    }
  }

  @override
  void dispose() {
    _generation++;
    _composer
      ..removeListener(_onComposerChanged)
      ..dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _onComposerChanged() {
    if (!mounted) return;
    // Only the Post button's enabled state depends on this, so rebuild
    // exactly when that boundary is crossed rather than on every keystroke.
    setState(() {});
  }

  bool _isCurrent(int generation) => mounted && generation == _generation;

  Future<void> _load({required bool reset}) async {
    if (!reset && (_loadingMore || _nextCursor == null)) return;
    final generation = reset ? ++_generation : _generation;
    setState(() {
      if (reset) {
        _loading = true;
        _pages.clear();
        _nextCursor = null;
        _deleting.clear();
        _reporting.clear();
        _removing.clear();
      } else {
        _loadingMore = true;
      }
      _error = null;
    });
    final cursor = reset ? null : _nextCursor;
    try {
      final view = await widget.service.loadView(
        widget.reel.id,
        commentLimit: widget.commentLimit,
        commentCursor: cursor,
      );
      if (!_isCurrent(generation)) return;
      setState(() {
        _pages.add(_CommentPage(cursor: cursor, comments: view.comments));
        _nextCursor = view.nextCommentCursor;
      });
      widget.onReelUpdated(view.reel);
    } catch (error) {
      if (_isCurrent(generation)) setState(() => _error = error);
    } finally {
      if (_isCurrent(generation)) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _post() async {
    final text = _composer.text.trim();
    if (_posting || text.isEmpty || !widget.service.isEmailVerified) return;
    final generation = _generation;
    final requestId = _postRequestId ??= ReelPublishSession.newRequestId();
    setState(() {
      _posting = true;
      _composerError = null;
      _posted = false;
    });
    try {
      final result = await widget.service.createComment(
        widget.reel.id,
        text: text,
        requestId: requestId,
      );
      if (!_isCurrent(generation)) return;
      _postRequestId = null;
      _composer.clear();
      setState(() => _posted = true);
      widget.onReelUpdated(
        widget.reel.copyWithEngagement(commentCount: result.commentCount),
      );
      // The comment belongs at the end of the thread, and only the server
      // knows the display name it captured. Re-read the tail rather than
      // guessing either.
      if (_nextCursor == null) await _reloadTail(generation);
    } catch (error) {
      if (_isCurrent(generation)) setState(() => _composerError = error);
    } finally {
      if (_isCurrent(generation)) setState(() => _posting = false);
    }
  }

  Future<void> _reloadTail(int generation) async {
    if (_pages.isEmpty) return _load(reset: true);
    final restored = List<_CommentPage>.of(_pages);
    var cursor = _pages.last.cursor;
    final reloaded = <_CommentPage>[];
    var nextCursor = _nextCursor;
    try {
      for (var request = 0; request < _maxTailRequests; request++) {
        final view = await widget.service.loadView(
          widget.reel.id,
          commentLimit: widget.commentLimit,
          commentCursor: cursor,
        );
        if (!_isCurrent(generation)) return;
        reloaded.add(_CommentPage(cursor: cursor, comments: view.comments));
        nextCursor = view.nextCommentCursor;
        widget.onReelUpdated(view.reel);
        if (nextCursor == null) break;
        cursor = nextCursor;
      }
      if (!_isCurrent(generation)) return;
      setState(() {
        _pages
          ..removeLast()
          ..addAll(reloaded);
        _nextCursor = nextCursor;
      });
    } catch (_) {
      // The comment is posted and the count is already right. A failed
      // re-read leaves the thread exactly as it was, with Load more still
      // able to reach the new comment, rather than emptying it.
      if (_isCurrent(generation)) {
        setState(() {
          _pages
            ..clear()
            ..addAll(restored);
        });
      }
    }
  }

  Future<void> _delete(ReelComment comment) async {
    if (_deleting.contains(comment.id) || comment.authorId != _viewerId) return;
    final generation = _generation;
    final copy = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.text('Delete comment?', 'Usunąć komentarz?')),
        content: Text(
          copy.text(
            'Your comment will be removed for everyone. This cannot be undone.',
            'Twój komentarz zniknie dla wszystkich. Tej operacji nie można cofnąć.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(copy.text('Cancel', 'Anuluj')),
          ),
          FilledButton(
            key: const ValueKey<String>('reel-comment-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(copy.text('Delete', 'Usuń')),
          ),
        ],
      ),
    );
    if (confirmed != true || !_isCurrent(generation)) return;
    setState(() => _deleting.add(comment.id));
    try {
      final result = await widget.service.deleteComment(
        widget.reel.id,
        commentId: comment.id,
      );
      if (!_isCurrent(generation)) return;
      _dropComment(comment.id, commentCount: result.commentCount);
      _announce(copy.text('Comment deleted.', 'Komentarz został usunięty.'));
    } catch (error) {
      // `_isCurrent` already implies `mounted`; the explicit check is what
      // makes the context use after the await provably safe to the analyzer.
      if (!mounted || !_isCurrent(generation)) return;
      _announce(
        reelEngagementMessage(
          context,
          error,
          action: ReelEngagementAction.deleteComment,
        ),
      );
    } finally {
      if (_isCurrent(generation)) {
        setState(() => _deleting.remove(comment.id));
      }
    }
  }

  /// Files a safety report against somebody else's comment.
  ///
  /// Nothing about the thread changes on success. The person reporting is not
  /// the person who decides, and a client that hid the comment the moment it
  /// was reported would be answering that question on a moderator's behalf —
  /// and would hand anybody a one-tap way to make words they dislike vanish
  /// from their own view while the report sits unreviewed.
  Future<void> _report(ReelComment comment) async {
    if (_reporting.contains(comment.id) ||
        _removing.contains(comment.id) ||
        comment.authorId == _viewerId) {
      return;
    }
    final generation = _generation;
    final copy = AppLocalizations.of(context);
    // A previous attempt on THIS comment pre-fills the sheet, so a retry
    // after a refusal costs one tap and stays byte-identical.
    final previous = _reportAttempt?.commentId == comment.id
        ? _reportAttempt
        : null;
    final request = await showReelCommentReportSheet(
      context,
      authorName: comment.authorName,
      commentText: comment.text,
      initialReason: previous?.request.reason,
      initialNote: previous?.request.note ?? '',
    );
    if (request == null || !_isCurrent(generation)) return;
    // The id is reused only for the identical attempt. A different reason or
    // a different note is a different operation at the server's ledger, and
    // replaying the old id against it would answer `already-exists` on a
    // safety path.
    final attempt = previous != null && previous.matches(comment.id, request)
        ? previous
        : _ReportAttempt(
            commentId: comment.id,
            request: request,
            requestId: ReelPublishSession.newRequestId(),
          );
    setState(() {
      _reportAttempt = attempt;
      _reporting.add(comment.id);
    });
    try {
      final result = await widget.service.reportComment(
        widget.reel.id,
        commentId: comment.id,
        reason: request.wireReason,
        note: request.note,
        requestId: attempt.requestId,
      );
      if (!mounted || !_isCurrent(generation)) return;
      setState(() {
        _reportAttempt = null;
        _reported.add(comment.id);
      });
      // `created: false` means this reporter had already reported this
      // comment and the backend deduplicated. Saying "thanks, sent" would
      // claim a second report that was never filed.
      _announce(
        result.created
            ? copy.text(
                'Thanks. This comment was sent for review.',
                'Dziękujemy. Komentarz został wysłany do sprawdzenia.',
              )
            : copy.text(
                'You already reported this comment. It is still with our '
                    'team.',
                'Ten komentarz został już przez Ciebie zgłoszony. Nadal '
                    'zajmuje się nim nasz zespół.',
              ),
      );
    } catch (error) {
      if (!mounted || !_isCurrent(generation)) return;
      _announce(
        reelEngagementMessage(
          context,
          error,
          action: ReelEngagementAction.reportComment,
        ),
      );
    } finally {
      if (_isCurrent(generation)) {
        setState(() => _reporting.remove(comment.id));
      }
    }
  }

  /// The Reel's author clearing somebody else's comment off their own thread.
  ///
  /// Confirmed first, and worded to say plainly whose words are being
  /// destroyed and that nothing brings them back. This is the one control
  /// here that acts on another person's content with no review, so the
  /// dialog is the whole due process it gets.
  Future<void> _remove(ReelComment comment) async {
    if (_removing.contains(comment.id) || _reporting.contains(comment.id)) {
      return;
    }
    final generation = _generation;
    final copy = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.text('Remove this comment?', 'Usunąć komentarz?')),
        content: Text(
          copy.template(
            "{author}'s comment will be removed from your Reel for "
                'everyone. This cannot be undone. To have it reviewed '
                'instead, report it.',
            'Komentarz od {author} zniknie z Twojego Reela dla wszystkich. '
                'Tej operacji nie można cofnąć. Jeśli wolisz, aby ocenił go '
                'nasz zespół, zgłoś go zamiast usuwać.',
            values: <String, Object>{'author': comment.authorName},
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('reel-comment-remove-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(copy.text('Cancel', 'Anuluj')),
          ),
          FilledButton(
            key: const ValueKey<String>('reel-comment-remove-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(copy.text('Remove', 'Usuń')),
          ),
        ],
      ),
    );
    if (confirmed != true || !_isCurrent(generation)) return;
    setState(() => _removing.add(comment.id));
    try {
      final result = await widget.service.removeComment(
        widget.reel.id,
        commentId: comment.id,
      );
      if (!mounted || !_isCurrent(generation)) return;
      // The server's count is the authority, exactly as it is for a like or
      // a deletion; the client never decrements its own copy.
      _dropComment(comment.id, commentCount: result.commentCount);
      _announce(copy.text('Comment removed.', 'Komentarz został usunięty.'));
    } catch (error) {
      if (!mounted || !_isCurrent(generation)) return;
      _announce(
        reelEngagementMessage(
          context,
          error,
          action: ReelEngagementAction.removeComment,
        ),
      );
    } finally {
      if (_isCurrent(generation)) {
        setState(() => _removing.remove(comment.id));
      }
    }
  }

  /// Drops one comment from the loaded pages and adopts the server's count.
  ///
  /// Shared by deletion and author removal so the two can never disagree
  /// about what a thread looks like afterwards. Must be called while current.
  void _dropComment(String commentId, {required int commentCount}) {
    setState(() {
      for (var index = 0; index < _pages.length; index++) {
        final page = _pages[index];
        if (!page.comments.any((entry) => entry.id == commentId)) continue;
        _pages[index] = _CommentPage(
          cursor: page.cursor,
          comments: page.comments
              .where((entry) => entry.id != commentId)
              .toList(growable: false),
        );
      }
      _reported.remove(commentId);
    });
    widget.onReelUpdated(
      widget.reel.copyWithEngagement(commentCount: commentCount),
    );
  }

  void _announce(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter =
            widget.gutter ?? (constraints.maxWidth < 380 ? 12.0 : 16.0);
        // A host that hands this view a fixed height (the wide context panel)
        // wants the composer pinned to the bottom with the thread filling
        // what is left. A host that lets it choose (the sheet) wants it as
        // short as its content. The incoming constraints already say which.
        final fill =
            constraints.hasBoundedHeight &&
            constraints.minHeight == constraints.maxHeight;
        final thread = _thread(gutter);
        return Column(
          mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (fill) Expanded(child: thread) else Flexible(child: thread),
            _Composer(
              key: const ValueKey<String>('reel-comment-composer'),
              controller: _composer,
              focusNode: _composerFocus,
              autofocus: widget.autofocusComposer,
              gutter: gutter,
              posting: _posting,
              posted: _posted,
              verified: widget.service.isEmailVerified,
              error: _composerError,
              onSubmit: _post,
            ),
          ],
        );
      },
    );
  }

  Widget _thread(double gutter) {
    final copy = AppLocalizations.of(context);
    if (_loading) {
      // Scrollable like the other two placeholder states: a short window (a
      // wide layout in a shallow browser window) can leave this region only a
      // few dozen pixels tall, and a fixed-height indicator would overflow it.
      return SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: gutter),
          child: YoLoadingIndicator(
            message: copy.text('Loading comments', 'Ładowanie komentarzy'),
          ),
        ),
      );
    }
    if (_error != null && _comments.isEmpty) {
      return SingleChildScrollView(
        child: YoErrorState(
          key: const ValueKey<String>('reel-comments-error'),
          message: reelEngagementMessage(
            context,
            _error!,
            action: ReelEngagementAction.loadComments,
          ),
          onRetry: () => _load(reset: true),
          compact: true,
        ),
      );
    }
    final comments = _comments;
    if (comments.isEmpty) {
      return SingleChildScrollView(
        child: YoEmptyState(
          key: const ValueKey<String>('reel-comments-empty'),
          icon: Icons.mode_comment_outlined,
          title: copy.text('No comments yet', 'Brak komentarzy'),
          subtitle: copy.text(
            'Be the first to comment.',
            'Skomentuj jako pierwszy.',
          ),
          compact: true,
        ),
      );
    }
    final viewerId = _viewerId;
    // A presentation hint, never an authority: `removeReelComment` checks the
    // Reel's author itself, before it even reads the comment.
    final viewerOwnsReel = viewerId != null && viewerId == widget.reel.authorId;
    return ListView.separated(
      key: const ValueKey<String>('reel-comment-thread'),
      shrinkWrap: true,
      padding: EdgeInsets.fromLTRB(gutter, 4, gutter, gutter),
      itemCount: comments.length + (_nextCursor == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        if (index == comments.length) {
          return _LoadMore(
            loading: _loadingMore,
            failed: _error != null,
            onLoad: () => _load(reset: false),
          );
        }
        final comment = comments[index];
        final own = comment.authorId == viewerId;
        return _CommentTile(
          comment: comment,
          dense: gutter < 16,
          busy:
              _deleting.contains(comment.id) ||
              _reporting.contains(comment.id) ||
              _removing.contains(comment.id),
          reported: _reported.contains(comment.id),
          onDelete: own ? () => _delete(comment) : null,
          // Never on your own comment: `createReelCommentReport` refuses it
          // outright, and offering a control whose only outcome is a refusal
          // is worse than offering none.
          onReport: own ? null : () => _report(comment),
          // Only the Reel's author, and never on their own words — those are
          // a Delete, which is the narrower authority and the honest label.
          // The backend would accept either, but the two leave different
          // accountability traces and an author clearing their own comment
          // is not a moderation event.
          onRemove: !own && viewerOwnsReel ? () => _remove(comment) : null,
        );
      },
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.dense,
    required this.busy,
    required this.reported,
    required this.onDelete,
    required this.onReport,
    required this.onRemove,
  });

  final ReelComment comment;
  final bool dense;

  /// A call is in flight on this row. One flag rather than three, because the
  /// row shows one spinner and refuses every action while it spins.
  final bool busy;

  /// This viewer reported this comment in this session.
  final bool reported;

  final VoidCallback? onDelete;
  final VoidCallback? onReport;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final theme = Theme.of(context);
    final timestamp = copy.relativeCompactTime(comment.createdAt.toLocal());
    return Semantics(
      container: true,
      label: reported
          ? copy.template(
              'Comment by {author}, reported by you',
              'Komentarz od: {author}, zgłoszony przez Ciebie',
              values: <String, Object>{'author': comment.authorName},
            )
          : copy.template(
              'Comment by {author}',
              'Komentarz od: {author}',
              values: <String, Object>{'author': comment.authorName},
            ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 6 : 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: <Widget>[
                      Text(
                        comment.authorName,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        timestamp,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    comment.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  // The comment is deliberately still here. This says the
                  // report was sent, not that anything was decided — the
                  // reporter is not the person who decides.
                  if (reported) ...<Widget>[
                    const SizedBox(height: 6),
                    Row(
                      key: ValueKey<String>(
                        'reel-comment-reported-${comment.id}',
                      ),
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.flag_rounded,
                          size: 14,
                          color: palette.warningForeground,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            copy.text(
                              'Reported — with our team',
                              'Zgłoszone — u naszego zespołu',
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: palette.warningForeground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _actions(context, copy, palette),
          ],
        ),
      ),
    );
  }

  /// ONE trailing control per row, always.
  ///
  /// A single available action stays an icon button, so the common cases —
  /// Delete on your own comment, Report on somebody else's — are one tap and
  /// visibly present. Only the Reel's author ever has two, and there the menu
  /// is what keeps a dense thread readable at 320 px and stops a destructive
  /// Remove from sitting one mis-tap away from Report.
  Widget _actions(
    BuildContext context,
    AppLocalizations copy,
    AppPalette palette,
  ) {
    if (busy) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (onDelete != null) {
      return IconButton(
        key: ValueKey<String>('reel-comment-delete-${comment.id}'),
        tooltip: copy.text('Delete comment', 'Usuń komentarz'),
        color: palette.dangerForeground,
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline_rounded, size: 20),
      );
    }
    if (onRemove == null) {
      if (onReport == null) return const SizedBox.shrink();
      return IconButton(
        key: ValueKey<String>('reel-comment-report-${comment.id}'),
        tooltip: reported
            ? copy.text('Report again', 'Zgłoś ponownie')
            : copy.text('Report comment', 'Zgłoś komentarz'),
        // textSecondary, not textTertiary: at tertiary the flag was legible
        // in Pearl and nearly invisible in the dark theme, and a safety
        // control that only one theme's users can find is not a control.
        color: reported ? palette.warningForeground : palette.textSecondary,
        onPressed: onReport,
        icon: Icon(
          reported ? Icons.flag_rounded : Icons.outlined_flag_rounded,
          size: 20,
        ),
      );
    }
    return PopupMenuButton<_CommentAction>(
      key: ValueKey<String>('reel-comment-actions-${comment.id}'),
      tooltip: copy.text('Comment options', 'Opcje komentarza'),
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: palette.textSecondary,
      ),
      onSelected: (action) => switch (action) {
        _CommentAction.report => onReport?.call(),
        _CommentAction.remove => onRemove?.call(),
      },
      itemBuilder: (context) => <PopupMenuEntry<_CommentAction>>[
        if (onReport != null)
          PopupMenuItem<_CommentAction>(
            key: ValueKey<String>('reel-comment-report-${comment.id}'),
            value: _CommentAction.report,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                reported ? Icons.flag_rounded : Icons.outlined_flag_rounded,
                color: reported
                    ? palette.warningForeground
                    : palette.textSecondary,
              ),
              title: Text(
                reported
                    ? copy.text('Report again', 'Zgłoś ponownie')
                    : copy.text('Report comment', 'Zgłoś komentarz'),
              ),
            ),
          ),
        PopupMenuItem<_CommentAction>(
          key: ValueKey<String>('reel-comment-remove-${comment.id}'),
          value: _CommentAction.remove,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.delete_outline_rounded,
              color: palette.dangerForeground,
            ),
            title: Text(
              copy.text('Remove from my Reel', 'Usuń z mojego Reela'),
              style: TextStyle(color: palette.dangerForeground),
            ),
          ),
        ),
      ],
    );
  }
}

/// The two actions a Reel's author has over somebody else's comment.
enum _CommentAction { report, remove }

class _LoadMore extends StatelessWidget {
  const _LoadMore({
    required this.loading,
    required this.failed,
    required this.onLoad,
  });

  final bool loading;
  final bool failed;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final label = failed
        ? copy.text('Try again', 'Spróbuj ponownie')
        : copy.text('Load more comments', 'Wczytaj więcej komentarzy');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey<String>('reel-comments-load-more'),
          onPressed: loading ? null : onLoad,
          style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
          icon: loading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  failed ? Icons.refresh_rounded : Icons.expand_more_rounded,
                ),
          label: Text(label),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.autofocus,
    required this.gutter,
    required this.posting,
    required this.posted,
    required this.verified,
    required this.error,
    required this.onSubmit,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final double gutter;
  final bool posting;
  final bool posted;
  final bool verified;
  final Object? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, 10, gutter, gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!verified)
              // Not a disabled control: the account is told what unlocks it.
              Semantics(
                container: true,
                liveRegion: true,
                child: Row(
                  key: const ValueKey<String>('reel-comment-verify-notice'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.mark_email_unread_outlined,
                      size: 20,
                      color: palette.warningForeground,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        reelVerificationNotice(context),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...<Widget>[
              if (error != null || posted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Semantics(
                    container: true,
                    liveRegion: true,
                    child: Text(
                      key: const ValueKey<String>('reel-comment-composer-note'),
                      error != null
                          ? reelEngagementMessage(
                              context,
                              error!,
                              action: ReelEngagementAction.comment,
                            )
                          : copy.text(
                              'Comment posted.',
                              'Komentarz został opublikowany.',
                            ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: error != null
                            ? palette.dangerForeground
                            : palette.successForeground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('reel-comment-field'),
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: autofocus,
                      enabled: !posting,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: ReelComment.maxTextLength,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      inputFormatters: <TextInputFormatter>[
                        LengthLimitingTextInputFormatter(
                          ReelComment.maxTextLength,
                        ),
                      ],
                      decoration: InputDecoration(
                        // A counter on every keystroke is noise; the limit
                        // still binds through the formatter above.
                        counterText: '',
                        isDense: true,
                        hintText: copy.text('Add a comment', 'Dodaj komentarz'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const ValueKey<String>('reel-comment-post'),
                    tooltip: copy.text('Post comment', 'Opublikuj komentarz'),
                    onPressed: posting || controller.text.trim().isEmpty
                        ? null
                        : onSubmit,
                    icon: posting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens one Reel's thread as a modal sheet.
///
/// Narrow and medium widths get this sheet; the wide layout embeds the very
/// same [ReelCommentsView] in its context panel instead. The difference
/// between them is presentation only — identical loading, paging, posting,
/// deletion and refusal behaviour, because both host one widget.
Future<void> showReelCommentsSheet(
  BuildContext context, {
  required Reel reel,
  required ReelService service,
  required ValueChanged<Reel> onReelUpdated,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: false,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(context),
    backgroundColor: Colors.transparent,
    builder: (context) => _ReelCommentsSheet(
      reel: reel,
      service: service,
      onReelUpdated: onReelUpdated,
    ),
  );
}

class _ReelCommentsSheet extends StatefulWidget {
  const _ReelCommentsSheet({
    required this.reel,
    required this.service,
    required this.onReelUpdated,
  });

  final Reel reel;
  final ReelService service;
  final ValueChanged<Reel> onReelUpdated;

  @override
  State<_ReelCommentsSheet> createState() => _ReelCommentsSheetState();
}

class _ReelCommentsSheetState extends State<_ReelCommentsSheet> {
  /// The sheet outlives the feed rebuild that its own callbacks cause, so it
  /// keeps the latest server-authoritative engagement itself rather than
  /// rendering the counts frozen at the moment it opened.
  late Reel _reel = widget.reel;

  void _updated(Reel reel) {
    if (mounted) {
      setState(() {
        _reel = _reel.copyWithEngagement(
          likeCount: reel.likeCount,
          commentCount: reel.commentCount,
          callerLiked: reel.callerLiked,
        );
      });
    }
    widget.onReelUpdated(reel);
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final gutter = media.size.width < 380 ? 12.0 : 16.0;
    final title = copy.text('Comments', 'Komentarze');
    return Material(
      color: palette.surfaceRaised,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: Padding(
          // The composer must stay above the software keyboard; the sheet is
          // scroll-controlled, so nothing else insets it.
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: ConstrainedBox(
            // The ceiling is a share of the space left above the keyboard, not
            // of the whole screen: a long thread plus an open keyboard would
            // otherwise ask for more height than the window has.
            constraints: BoxConstraints(
              maxHeight:
                  (media.size.height - media.viewInsets.bottom).clamp(
                    240.0,
                    media.size.height,
                  ) *
                  .86,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                YoModalSheetChrome(
                  sheetLabel: title,
                  surfaceColor: palette.surfaceRaised,
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 4),
                  child: Semantics(
                    container: true,
                    label: copy.template(
                      'Comments: {count}',
                      'Komentarze: {count}',
                      values: <String, Object>{'count': _reel.commentCount},
                    ),
                    child: Row(
                      children: <Widget>[
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          reelCompactCount(_reel.commentCount),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: palette.textTertiary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Flexible(
                  child: ReelCommentsView(
                    key: const ValueKey<String>('reel-comments-sheet-view'),
                    reel: _reel,
                    service: widget.service,
                    onReelUpdated: _updated,
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
