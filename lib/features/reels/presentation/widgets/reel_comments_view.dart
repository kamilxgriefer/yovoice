import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/reels/data/models/reel.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/features/reels/presentation/reel_engagement_copy.dart';
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

/// The Reel comment thread: oldest first, paginated, with a composer.
///
/// One widget serves both presentations — a modal sheet on narrow and medium
/// widths, and an inline column in the wide layout's context panel — so the
/// two can never drift apart in behaviour. Only spacing adapts, and it adapts
/// to the width it is actually given rather than to a device label.
///
/// There is no report control and no moderator removal here on purpose: Reel
/// comments have neither yet. Showing a control that goes nowhere would be
/// worse than showing none.
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
      setState(() {
        for (var index = 0; index < _pages.length; index++) {
          final page = _pages[index];
          if (!page.comments.any((entry) => entry.id == comment.id)) continue;
          _pages[index] = _CommentPage(
            cursor: page.cursor,
            comments: page.comments
                .where((entry) => entry.id != comment.id)
                .toList(growable: false),
          );
        }
      });
      widget.onReelUpdated(
        widget.reel.copyWithEngagement(commentCount: result.commentCount),
      );
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
        return _CommentTile(
          comment: comment,
          dense: gutter < 16,
          deleting: _deleting.contains(comment.id),
          onDelete: comment.authorId == viewerId
              ? () => _delete(comment)
              : null,
        );
      },
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.dense,
    required this.deleting,
    required this.onDelete,
  });

  final ReelComment comment;
  final bool dense;
  final bool deleting;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final theme = Theme.of(context);
    final timestamp = copy.relativeCompactTime(comment.createdAt.toLocal());
    return Semantics(
      container: true,
      label: copy.template(
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
                ],
              ),
            ),
            // Delete only, and only your own. Reel comments have no report
            // path and no moderator removal yet; an overflow menu whose only
            // real entry is this one would just hide it behind a tap.
            if (onDelete != null)
              IconButton(
                key: ValueKey<String>('reel-comment-delete-${comment.id}'),
                tooltip: copy.text('Delete comment', 'Usuń komentarz'),
                color: palette.dangerForeground,
                onPressed: deleting ? null : onDelete,
                icon: deleting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline_rounded, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

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
