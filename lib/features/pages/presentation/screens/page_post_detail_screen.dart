import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_radius.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/likers/data/models/likers_target.dart';
import 'package:yovoice/features/likers/presentation/likers_launcher.dart';
import 'package:yovoice/features/messages/presentation/widgets/direct_media_fullscreen_viewer.dart';
import 'package:yovoice/features/moderation/presentation/widgets/report_reason_sheet.dart';
import 'package:yovoice/features/pages/data/models/page_views.dart';
import 'package:yovoice/features/pages/data/page_links.dart';
import 'package:yovoice/features/pages/data/services/page_voice_player.dart';
import 'package:yovoice/features/pages/data/services/pages_service.dart';
import 'package:yovoice/features/pages/presentation/controllers/page_post_detail_controller.dart';
import 'package:yovoice/features/pages/presentation/page_post_copy.dart';
import 'package:yovoice/features/pages/presentation/page_profile_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_face.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_menus.dart';
import 'package:yovoice/features/pages/presentation/widgets/page_post_card.dart';
import 'package:yovoice/features/pages/presentation/widgets/pages_state_views.dart';
import 'package:yovoice/shared/widgets/badges/yo_metric_pill.dart';
import 'package:yovoice/shared/widgets/buttons/yo_icon_button.dart';
import 'package:yovoice/shared/widgets/identity/yo_vip_rosette.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';
import 'package:yovoice/shared/widgets/states/yo_error_state.dart';
import 'package:yovoice/shared/widgets/states/yo_loading_indicator.dart';

/// Opens an account from a comment author (the §4.3 resolver in the app).
typedef PageAccountOpener =
    Future<void> Function(
      BuildContext context, {
      required String uid,
      String? displayName,
    });

/// Opens the Page the post belongs to.
typedef PageOpener =
    Future<void> Function(
      BuildContext context, {
      required String pageId,
      String? displayName,
    });

/// The post detail A "karta + wątek" (approved R3 render, §12): the full
/// post card, then "Komentarze" with the thread (oldest first as rendered;
/// the newest 20 load first and "Wcześniejsze komentarze" above them loads
/// the page before), and the comment composer docked at the bottom,
/// or the line that says why comments are closed (D14, the owner's switch).
/// No comment hearts in v1 (D15).
///
/// * Narrow (< 600): one column with a 16 px gutter.
/// * Medium (600-999): one centred 640 column; the composer bar spans the
///   column.
/// * Wide (≥ 1000): the post (≤ 600) and the thread in a 360 px column
///   beside it, the pair centred, with its composer at the column's foot.
///
/// It is always a pushed route with its own Back row: on phones and tablets
/// it covers the dock (the render's "the dock yields to it"); on desktop it
/// opens inside Treści's main column beside the wall-A panel.
class PagePostDetailScreen extends StatefulWidget {
  const PagePostDetailScreen({
    required this.postId,
    this.pageId,
    this.initial,
    this.focusComposer = false,
    this.pageReadOnly = false,
    this.service,
    this.player,
    this.likers,
    this.onOpenAccount,
    this.onOpenPage,
    this.viewerId,
    this.viewerName,
    this.shareLink,
    this.clock,
    super.key,
  });

  final String postId;
  final String? pageId;
  final PagePostView? initial;

  /// Comment tapped on a card: the composer takes focus once the post is in.
  final bool focusComposer;

  /// The Page is read-only for visitors (known by an opener that read its
  /// header); otherwise learned from a refused comment.
  final bool pageReadOnly;

  final PagesService? service;
  final PageVoicePlayer? player;
  final LikersLauncher? likers;
  final PageAccountOpener? onOpenAccount;
  final PageOpener? onOpenPage;
  final String? viewerId;
  final String? viewerName;
  final Future<void> Function(Uri link)? shareLink;
  final DateTime Function()? clock;

  static const double columnWidth = 640;
  static const double threadWidth = 360;
  static const double wideBreakpoint = 1000;

  @override
  State<PagePostDetailScreen> createState() => _PagePostDetailScreenState();
}

class _PagePostDetailScreenState extends State<PagePostDetailScreen> {
  late final PagesService _service = widget.service ?? PagesService.instance;
  late final PageVoicePlayer _player =
      widget.player ?? PageVoicePlayer.instance;
  late final String _viewerId = widget.viewerId ?? _currentUserId();
  late final PagePostDetailController _controller = PagePostDetailController(
    service: _service,
    postId: widget.postId,
    viewerId: _viewerId,
    initial: widget.initial,
    pageReadOnly: widget.pageReadOnly,
  );
  final TextEditingController _comment = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  bool _focusedOnce = false;
  String? _commentError;

  /// The comment just sent, scrolled into view once it is in the thread.
  String? _revealCommentId;
  final GlobalKey _revealKey = GlobalKey(debugLabel: 'page-comment-reveal');

  static String _currentUserId() {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  String? get _viewerName {
    if (widget.viewerName != null) return widget.viewerName;
    try {
      return FirebaseAuth.instance.currentUser?.displayName;
    } catch (_) {
      return null;
    }
  }

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _comment.addListener(_onChanged);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    // Back never leaves this post's clip sounding (the detail can be opened
    // from a chat, a notification or a room, outside Treści's own hook).
    final injected = widget.player;
    if (injected == null) {
      PageVoicePlayer.silenceSharedIf((id) => id == widget.postId);
    } else if (injected.activePostId == widget.postId) {
      unawaited(injected.pause());
    }
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    _comment
      ..removeListener(_onChanged)
      ..dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.focusComposer &&
        !_focusedOnce &&
        _controller.post != null &&
        _controller.closed == null) {
      _focusedOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _commentFocus.requestFocus();
      });
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------ actions

  Future<void> _toggleLike() async {
    final failure = await _controller.toggleLike();
    if (failure != null && mounted) {
      _snack(PagesCopy(AppLocalizations.of(context)).likeError(failure));
    }
  }

  Future<void> _send() async {
    final text = _comment.text;
    if (text.trim().isEmpty) return;
    setState(() => _commentError = null);
    final failure = await _controller.comment(text);
    if (!mounted) return;
    if (failure == null) {
      _comment.clear();
      final sent = _controller.comments.firstOrNull;
      if (sent != null) {
        setState(() => _revealCommentId = sent.commentId);
        WidgetsBinding.instance.addPostFrameCallback((_) => _revealSent());
      }
      return;
    }
    setState(
      () => _commentError = PagePostCopy(
        AppLocalizations.of(context),
      ).commentError(failure),
    );
  }

  /// New comments land at the bottom of the thread; bring the one just sent
  /// into view above the composer.
  void _revealSent() {
    final target = _revealKey.currentContext;
    if (!mounted || target == null) return;
    unawaited(
      Scrollable.ensureVisible(
        target,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _share(PagePostView post) async {
    final link = buildPageLink(post.pageId, postId: post.postId);
    final share = widget.shareLink;
    if (share != null) {
      await share(link);
      return;
    }
    await SharePlus.instance.share(ShareParams(text: link.toString()));
  }

  Future<void> _openLikers(PagePostView post) =>
      (widget.likers ?? const LikersLauncher()).open(
        context,
        PagePostLikersTarget(post.postId),
        totalCount: post.likeCount,
      );

  Future<void> _openPhoto(PagePostView post, int index) async {
    final images = post.images;
    if (index < 0 || index >= images.length) return;
    try {
      final grants = await _service.mediaAccess(post.postId, [
        images[index].mediaId,
      ]);
      final grant = grants[images[index].mediaId];
      if (grant == null || !mounted) return;
      await showDirectImageFullscreenViewer(
        context,
        imageProvider: NetworkImage(grant.url.toString()),
      );
    } on PagesException {
      if (mounted) {
        _snack(PagePostCopy(AppLocalizations.of(context)).loadPostError);
      }
    }
  }

  Future<void> _openPage(PagePostView post) async {
    final open = widget.onOpenPage;
    if (open == null) return;
    await open(context, pageId: post.pageId, displayName: post.pageName);
  }

  Future<void> _openAuthor(PageCommentView comment) async {
    final post = _controller.post;
    if (comment.isOwnPage && post != null) {
      await _openPage(post);
      return;
    }
    final open = widget.onOpenAccount;
    if (open == null) return;
    await open(context, uid: comment.authorId, displayName: comment.authorName);
  }

  Future<void> _report({
    required PageReportTarget target,
    required PagePostView post,
    String? commentId,
  }) async {
    final l10n = AppLocalizations.of(context);
    final copy = PagePostCopy(l10n);
    final pages = PagesCopy(l10n);
    final reason = await showReportReasonSheet(
      context: context,
      title: target == PageReportTarget.comment
          ? copy.reportCommentTitle
          : copy.reportPostTitle,
      subtitle: pages.reportSubtitle,
    );
    if (reason == null || !mounted) return;
    try {
      await _service.report(
        target: target,
        pageId: post.pageId,
        postId: post.postId,
        commentId: commentId,
        reason: reason.name,
      );
      if (mounted) _snack(pages.reported);
    } on PagesException {
      if (mounted) _snack(pages.reportFailed);
    }
  }

  Future<void> _showPostMenu(PagePostView post) async {
    final l10n = AppLocalizations.of(context);
    final copy = PagePostCopy(l10n);
    final pages = PagesCopy(l10n);
    final owner = _controller.isOwner;
    final action = await showPageMenuSheet<_PostAction>(
      context,
      sheetLabel: pages.moreOptions,
      pageId: post.pageId,
      pageName: post.pageName,
      kind: post.pageKind,
      meta: pages.kindLabel(post.pageKind),
      groups: [
        [
          PageMenuItem(
            value: _PostAction.share,
            icon: Icons.ios_share_rounded,
            label: pages.sharePost,
          ),
          if (widget.onOpenPage != null && !owner)
            PageMenuItem(
              value: _PostAction.openPage,
              icon: Icons.article_outlined,
              label: pages.goToPage,
            ),
          if (owner && post.state == PagePostState.published)
            PageMenuItem(
              key: const ValueKey('page-post-comments-switch'),
              value: _PostAction.comments,
              icon: post.commentsEnabled
                  ? Icons.comments_disabled_outlined
                  : Icons.chat_bubble_outline_rounded,
              label: post.commentsEnabled
                  ? copy.turnCommentsOff
                  : copy.turnCommentsOn,
            ),
        ],
        [
          if (owner)
            PageMenuItem(
              value: _PostAction.delete,
              icon: Icons.delete_outline_rounded,
              label: pages.deletePost,
              danger: true,
            )
          else
            PageMenuItem(
              key: const ValueKey('page-post-report'),
              value: _PostAction.report,
              icon: Icons.flag_outlined,
              label: copy.reportPost,
              danger: true,
            ),
        ],
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _PostAction.share:
        await _share(post);
      case _PostAction.openPage:
        await _openPage(post);
      case _PostAction.comments:
        final enabled = !post.commentsEnabled;
        final failure = await _controller.setCommentsEnabled(enabled);
        if (!mounted) return;
        _snack(
          failure != null
              ? pages.actionFailed
              : enabled
              ? copy.commentsNowOn
              : copy.commentsNowOff,
        );
      case _PostAction.delete:
        final confirmed = await confirmPageAction(
          context,
          title: pages.deletePostTitle,
          body: pages.deletePostBody,
          confirm: pages.delete,
          cancel: pages.cancel,
        );
        if (!confirmed || !mounted) return;
        final failure = await _controller.deletePost();
        if (!mounted) return;
        if (failure == null) {
          _snack(pages.postDeleted);
          await Navigator.of(context).maybePop();
        } else {
          _snack(pages.actionFailed);
        }
      case _PostAction.report:
        await _report(target: PageReportTarget.post, post: post);
    }
  }

  Future<void> _showCommentMenu(PageCommentView comment) async {
    final post = _controller.post;
    if (post == null) return;
    final l10n = AppLocalizations.of(context);
    final copy = PagePostCopy(l10n);
    final pages = PagesCopy(l10n);
    final canDelete = _controller.canDelete(comment);
    final action = await showPageMenuSheet<_CommentAction>(
      context,
      sheetLabel: copy.commentOptions(comment.authorName),
      pageId: post.pageId,
      pageName: post.pageName,
      kind: post.pageKind,
      meta: pages.kindLabel(post.pageKind),
      groups: [
        [
          if (canDelete)
            PageMenuItem(
              key: const ValueKey('page-comment-delete'),
              value: _CommentAction.delete,
              icon: Icons.delete_outline_rounded,
              label: copy.deleteComment,
              danger: true,
            ),
          if (comment.authorId != _viewerId)
            PageMenuItem(
              key: const ValueKey('page-comment-report'),
              value: _CommentAction.report,
              icon: Icons.flag_outlined,
              label: copy.reportComment,
              danger: true,
            ),
        ],
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _CommentAction.delete:
        final confirmed = await confirmPageAction(
          context,
          title: copy.deleteCommentTitle,
          body: copy.deleteCommentBody,
          confirm: pages.delete,
          cancel: pages.cancel,
        );
        if (!confirmed || !mounted) return;
        final failure = await _controller.deleteComment(comment.commentId);
        if (!mounted) return;
        _snack(failure == null ? copy.commentDeleted : copy.deleteCommentError);
      case _CommentAction.report:
        await _report(
          target: PageReportTarget.comment,
          post: post,
          commentId: comment.commentId,
        );
    }
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final l10n = AppLocalizations.of(context);
    final copy = PagePostCopy(l10n);
    final pages = PagesCopy(l10n);
    final top = MediaQuery.paddingOf(context).top;
    // Back stays its own button node; only the title is the route's header.
    final bar = Semantics(
      container: true,
      explicitChildNodes: true,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              YoIconButton(
                key: const ValueKey('page-post-back'),
                icon: Icons.arrow_back_rounded,
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: pages.back,
                size: 44,
                backgroundColor: Colors.transparent,
                borderColor: Colors.transparent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Semantics(
                  header: true,
                  namesRoute: true,
                  child: Text(
                    copy.postTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleMedium.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PagesCanvas(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: top),
            bar,
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    _content(context, constraints.maxWidth, copy),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, double width, PagePostCopy copy) {
    final pages = PagesCopy(AppLocalizations.of(context));
    final post = _controller.post;
    switch (_controller.status) {
      case PagePostDetailStatus.unavailable:
        return Center(
          child: SingleChildScrollView(
            child: PagesStateBlock(
              key: const ValueKey('page-post-unavailable'),
              icon: Icons.article_outlined,
              title: copy.postUnavailable,
              body: copy.postUnavailableBody,
            ),
          ),
        );
      case PagePostDetailStatus.error when post == null:
        return Center(
          child: YoErrorState(
            key: const ValueKey('page-post-error'),
            message: copy.loadPostError,
            onRetry: () => unawaited(_controller.load()),
          ),
        );
      case PagePostDetailStatus.loading when post == null:
        return Center(
          child: YoLoadingIndicator(semanticLabel: copy.loadingPost),
        );
      default:
        break;
    }
    final ready = post!;
    final card = PagePostCard(
      key: ValueKey('page-post-detail-${ready.postId}'),
      post: ready,
      now: _now(),
      service: _service,
      likeBusy: _controller.likeBusy,
      voicePlayer: _player,
      // Post detail A crops a single photo to a wide band on phones (about
      // 2.5:1) so the thread starts above the fold; the full photo opens in
      // the viewer.
      photoMaxHeight: width >= 600 ? 520 : (width - 32) / 2.5,
      showTypeChip: true,
      commentsClosedLabel: _controller.closed == PageCommentsClosed.readOnly
          ? copy.closedReadOnly
          : null,
      onOpenPage: () => unawaited(_openPage(ready)),
      onToggleLike: () => unawaited(_toggleLike()),
      onShare: () => unawaited(_share(ready)),
      onMore: () => unawaited(_showPostMenu(ready)),
      onComment: () => _commentFocus.requestFocus(),
      onOpenPhoto: (index) => unawaited(_openPhoto(ready, index)),
      onOpenLikers: () => unawaited(_openLikers(ready)),
      onPlayVoice: () => unawaited(_player.toggle(ready)),
    );
    final bar = _CommentBar(
      controller: _comment,
      focusNode: _commentFocus,
      closed: _controller.closed,
      sending: _controller.sending,
      error: _commentError,
      viewerId: _viewerId,
      viewerName: _viewerName,
      copy: copy,
      onSend: () => unawaited(_send()),
    );

    if (width >= PagePostDetailScreen.wideBreakpoint) {
      final side = (width - 32 - PagePostDetailScreen.threadWidth - 24).clamp(
        320.0,
        600.0,
      );
      // The pair is centred in whatever the shell gives Treści's main
      // area, so a wide window never leaves it hugging the start edge.
      // Keyboard order: the whole card, then the thread and its composer
      // (never interleaved by height).
      return FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: side + 32,
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: FocusTraversalGroup(
                  child: SingleChildScrollView(
                    key: const ValueKey('page-post-detail-scroll'),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    child: card,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: PagePostDetailScreen.threadWidth,
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(2),
                child: FocusTraversalGroup(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      right: 16,
                      bottom: 16,
                      top: 4,
                    ),
                    child: DecoratedBox(
                      key: const ValueKey('page-post-thread-column'),
                      decoration: BoxDecoration(
                        color: context.appPalette.surface,
                        borderRadius: AppRadius.lg,
                        border: Border.all(color: context.appPalette.border),
                      ),
                      child: ClipRRect(
                        borderRadius: AppRadius.lg,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: CustomScrollView(
                                slivers: [
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      16,
                                      8,
                                      16,
                                    ),
                                    sliver: SliverList.list(
                                      children: _thread(
                                        context,
                                        copy,
                                        pages,
                                        ready,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            bar,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final tablet = width >= 600;
    final column = tablet ? PagePostDetailScreen.columnWidth : width;
    final side = tablet ? ((width - column) / 2).clamp(0.0, width) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _controller.load,
            child: CustomScrollView(
              key: const ValueKey('page-post-detail-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    side + (tablet ? 0 : 16),
                    4,
                    side + (tablet ? 0 : 16),
                    24,
                  ),
                  sliver: SliverList.list(
                    children: [
                      card,
                      const SizedBox(height: AppRhythm.section),
                      ..._thread(context, copy, pages, ready),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: side),
          child: bar,
        ),
      ],
    );
  }

  List<Widget> _thread(
    BuildContext context,
    PagePostCopy copy,
    PagesCopy pages,
    PagePostView post,
  ) {
    final palette = context.appPalette;
    final comments = _controller.comments;
    final widgets = <Widget>[
      Row(
        children: [
          Flexible(
            child: Semantics(
              header: true,
              child: Text(
                copy.commentsTitle,
                style: AppTypography.sectionTitle.copyWith(
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          YoMetricPill(
            key: const ValueKey('page-post-comment-count'),
            value: '${post.commentCount}',
            tone: YoMetricPillTone.outlined,
            semanticLabel: pages.comments(post.commentCount),
          ),
        ],
      ),
      const SizedBox(height: 6),
    ];
    if (!_controller.commentsLoaded) {
      if (_controller.status == PagePostDetailStatus.error) {
        widgets.add(
          YoErrorState(
            compact: true,
            message: copy.loadCommentsError,
            onRetry: () => unawaited(_controller.load()),
          ),
        );
      } else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: YoLoadingIndicator(semanticLabel: copy.loadingComments),
            ),
          ),
        );
      }
      return widgets;
    }
    if (comments.isEmpty) {
      widgets.add(
        Padding(
          key: const ValueKey('page-post-no-comments'),
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Text(
                copy.noComments,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_controller.closed == null) ...[
                const SizedBox(height: 4),
                Text(
                  copy.noCommentsBody,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      return widgets;
    }
    // Earlier pages load above the thread, which reads oldest first.
    final showMore =
        _controller.hasMore ||
        _controller.loadingMore ||
        _controller.loadMoreFailed;
    widgets.add(
      Center(
        key: const ValueKey('page-post-load-more-slot'),
        child: PagesLoadMoreButton(
          key: const ValueKey('page-post-load-more'),
          visible: showMore,
          loading: _controller.loadingMore,
          failed: _controller.loadMoreFailed,
          itemCount: comments.length,
          height: 44,
          label: copy.earlierComments,
          onPressed: () => unawaited(_controller.loadMore()),
        ),
      ),
    );
    if (showMore) widgets.add(const SizedBox(height: 4));
    final now = _now();
    for (final comment in _controller.thread) {
      final row = _CommentRow(
        key: ValueKey('page-comment-${comment.commentId}'),
        comment: comment,
        post: post,
        age: pages.age(comment.createdAt, now),
        busy: _controller.isDeleting(comment.commentId),
        copy: copy,
        onOpenAuthor: () => unawaited(_openAuthor(comment)),
        onMore: () => unawaited(_showCommentMenu(comment)),
      );
      widgets.add(
        comment.commentId == _revealCommentId
            ? KeyedSubtree(key: _revealKey, child: row)
            : row,
      );
    }
    return widgets;
  }
}

enum _PostAction { share, openPage, comments, delete, report }

enum _CommentAction { delete, report }

/// One comment (the render's CommentRow): face 32, name + rosette, the
/// "Autor" chip on the Page's own replies, "· age", the text and a ⋯ with a
/// 44 px target.
class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.post,
    required this.age,
    required this.busy,
    required this.copy,
    required this.onOpenAuthor,
    required this.onMore,
    super.key,
  });

  final PageCommentView comment;
  final PagePostView post;
  final String age;
  final bool busy;
  final PagePostCopy copy;
  final VoidCallback onOpenAuthor;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final nameStyle = AppTypography.bodySmall.copyWith(
      color: palette.textPrimary,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    final face = comment.isOwnPage
        ? PageFace(
            pageId: post.pageId,
            name: post.pageName,
            kind: post.pageKind,
            size: 32,
          )
        : UserAvatar(
            radius: 16,
            userId: comment.authorId,
            displayName: comment.authorName,
            finish: UserAvatarFinish.brand,
          );
    final head = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        NameWithVipMark(
          uid: comment.authorId,
          name: comment.authorName,
          style: nameStyle,
          markSemantics: false,
        ),
        if (comment.isOwnPage)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .18),
              borderRadius: AppRadius.pill,
              border: Border.all(
                color: palette.interactiveForeground.withValues(alpha: .45),
              ),
            ),
            child: Text(
              copy.authorBadge,
              style: AppTypography.count.copyWith(
                color: palette.interactiveForeground,
                fontSize: 10.5,
              ),
            ),
          ),
        Text(
          '· $age',
          style: AppTypography.bodySmall.copyWith(color: palette.textTertiary),
        ),
      ],
    );
    return Opacity(
      opacity: busy ? .5 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: copy.commentLabel(
                  comment.authorName,
                  age,
                  author: comment.isOwnPage,
                ),
                value: comment.text,
                onTap: onOpenAuthor,
                excludeSemantics: true,
                child: InkWell(
                  onTap: onOpenAuthor,
                  borderRadius: AppRadius.md,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        face,
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              head,
                              const SizedBox(height: 3),
                              Text(
                                comment.text,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: palette.textPrimary,
                                  fontSize: 14,
                                  height: 1.42,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            YoIconButton(
              key: ValueKey('page-comment-more-${comment.commentId}'),
              icon: Icons.more_horiz_rounded,
              onPressed: busy ? null : onMore,
              tooltip: copy.commentOptions(comment.authorName),
              size: 44,
              iconSize: 20,
              backgroundColor: Colors.transparent,
              borderColor: Colors.transparent,
              foregroundColor: palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// The docked comment composer (render `_CommentBar`), or the closed line.
class _CommentBar extends StatelessWidget {
  const _CommentBar({
    required this.controller,
    required this.focusNode,
    required this.closed,
    required this.sending,
    required this.error,
    required this.viewerId,
    required this.viewerName,
    required this.copy,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final PageCommentsClosed? closed;
  final bool sending;
  final String? error;
  final String viewerId;
  final String? viewerName;
  final PagePostCopy copy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final closedReason = closed;
    final Widget child;
    if (closedReason != null) {
      child = ConstrainedBox(
        key: const ValueKey('page-comments-closed'),
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                closedReason == PageCommentsClosed.readOnly
                    ? copy.closedReadOnly
                    : copy.closedByPage,
                style: AppTypography.bodySmall.copyWith(
                  color: palette.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      final text = controller.text;
      final canSend =
          !sending &&
          text.trim().isNotEmpty &&
          text.length <= PagesService.maxCommentText;
      child = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                error!,
                key: const ValueKey('page-comment-error'),
                style: AppTypography.bodySmall.copyWith(
                  color: palette.dangerForeground,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ExcludeSemantics(
                  child: UserAvatar(
                    radius: 16,
                    userId: viewerId,
                    displayName: viewerName,
                    finish: UserAvatarFinish.brand,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey('page-comment-field'),
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !sending,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: PagesService.maxCommentText,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTypography.bodyMedium.copyWith(
                    color: palette.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: copy.writeComment,
                    hintStyle: AppTypography.bodyMedium.copyWith(
                      color: palette.textTertiary,
                    ),
                    counterText: '',
                    isDense: true,
                    filled: true,
                    fillColor: palette.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(
                        color: palette.interactiveForeground.withValues(
                          alpha: .7,
                        ),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                key: const ValueKey('page-comment-send'),
                onPressed: canSend ? onSend : null,
                tooltip: copy.sendComment,
                style: IconButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  minimumSize: const Size(44, 44),
                ),
                icon: sending
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
              ),
            ],
          ),
        ],
      );
    }
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        10,
        14,
        10 + (keyboardOpen ? 0 : bottom),
      ),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: child,
    );
  }
}
