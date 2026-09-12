import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/helpers/error_messages.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/navigation/app_route_observer.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_content_flow.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_expiry_scheduler.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_conversation_thread.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_boundary.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_mention_composer.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_mentions.dart';
import 'package:yovoice/features/moments/presentation/widgets/reply_playback_arbiter.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

enum _MomentCommentsRefreshTrigger {
  initial,
  appResume,
  routeReturn,
  mutation,
  retry,
}

bool _momentCommentsIsGoneError(Object error) =>
    error is FirebaseFunctionsException &&
    const <String>{
      'permission-denied',
      'not-found',
      'gone',
    }.contains(error.code);

class MomentCommentsScreen extends StatefulWidget {
  const MomentCommentsScreen({
    required this.moment,
    this.firestore,
    this.auth,
    this.momentService,
    this.contentReportService,
    this.friendService,
    this.mentionFriendsStream,
    this.expiryClock,
    this.expiryTimerFactory,
    super.key,
  });

  final VoiceMoment moment;

  /// Injection seams, matching the pattern on ChatScreen and
  /// MomentsScreen: production passes nothing and gets the live
  /// singletons, tests pass fakes. Added with the report action because
  /// a safety path that cannot be exercised in a test is a safety path
  /// nobody can prove still works after the next change.
  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final MomentService? momentService;
  final ContentReportService? contentReportService;

  /// Backs the composer's `@` suggestions with the caller's own friends.
  /// Production passes nothing; the screen resolves the live
  /// [FriendService] and fails quiet when it cannot.
  final FriendService? friendService;
  final Stream<List<FriendUser>>? mentionFriendsStream;
  final MomentExpiryClock? expiryClock;
  final MomentExpiryTimerFactory? expiryTimerFactory;

  @override
  State<MomentCommentsScreen> createState() => _MomentCommentsScreenState();
}

class _MomentCommentsScreenState extends State<MomentCommentsScreen>
    with RouteAware, WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  late final FirebaseAuth? _auth = _resolveAuth();
  late final MomentService? _momentService = _resolveMomentService();
  late VoiceMoment _moment = widget.moment;
  final FocusNode _goneBackFocus = FocusNode(
    debugLabel: 'Expired Moment comments back',
  );
  final MomentExpiryAnnouncer _expiryAnnouncer = MomentExpiryAnnouncer();
  final FocusNode _composerFocus = FocusNode(debugLabel: 'Moment comment');

  /// This page has no main recording of its own, but two voice replies must
  /// still never overlap each other.
  final ReplyPlaybackArbiter _arbiter = ReplyPlaybackArbiter();
  late final MentionFriendsSource _mentionFriends;
  bool _sending = false;
  List<MomentComment>? _comments;
  bool _commentsTruncated = false;
  String? _nextCommentCursor;
  Object? _loadError;
  bool _loadingMore = false;
  bool _unavailable = false;
  ModalRoute<void>? _observedRoute;
  final Set<_MomentCommentsRefreshTrigger> _canonicalRefreshesInFlight =
      <_MomentCommentsRefreshTrigger>{};
  int _viewLoadGeneration = 0;

  /// Both guarded the way MomentsScreen guards its services: without a
  /// Firebase app these throw, and the screen must still render its
  /// states rather than crash.
  FirebaseAuth? _resolveAuth() {
    if (widget.auth != null) return widget.auth;
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  MomentService? _resolveMomentService() {
    if (widget.momentService != null) return widget.momentService;
    try {
      return MomentService();
    } catch (_) {
      return null;
    }
  }

  String get _currentUid => _auth?.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mentionFriends = MentionFriendsSource(
      friendsStream: widget.mentionFriendsStream,
      friendService: widget.friendService,
    )..addListener(_handleMentionFriends);
    unawaited(_loadComments(trigger: _MomentCommentsRefreshTrigger.initial));
  }

  void _handleMentionFriends() {
    if (mounted) setState(() {});
  }

  /// Everyone this viewer's mentions may resolve to when READ: the
  /// thread's own participants plus the viewer's friends.
  MentionDirectory _readDirectory() => MentionDirectory(<MentionCandidate>[
    MentionCandidate(userId: _moment.authorId, displayName: _moment.authorName),
    for (final comment in _comments ?? const <MomentComment>[])
      if (comment.authorId.isNotEmpty && comment.authorName.trim().isNotEmpty)
        MentionCandidate(
          userId: comment.authorId,
          displayName: comment.authorName,
        ),
    ..._mentionFriends.candidates,
  ]);

  /// Who the composer may SUGGEST: only the caller's own friends.
  MentionDirectory _composerDirectory() =>
      MentionDirectory(_mentionFriends.candidates);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (identical(route, _observedRoute)) return;
    if (_observedRoute != null) appRouteObserver.unsubscribe(this);
    _observedRoute = route;
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  @override
  void didPopNext() {
    unawaited(
      _loadComments(trigger: _MomentCommentsRefreshTrigger.routeReturn),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_loadComments(trigger: _MomentCommentsRefreshTrigger.appResume));
  }

  Future<void> _loadComments({
    String? cursor,
    bool append = false,
    _MomentCommentsRefreshTrigger trigger = _MomentCommentsRefreshTrigger.retry,
  }) async {
    final service = _momentService;
    if (service == null || (append && _loadingMore)) return;
    if (!append && !_canonicalRefreshesInFlight.add(trigger)) return;
    final requestGeneration = append
        ? _viewLoadGeneration
        : ++_viewLoadGeneration;
    if (append && mounted) setState(() => _loadingMore = true);
    try {
      final view = await service.loadMomentView(
        _moment.id,
        commentCursor: cursor,
      );
      if (!mounted || requestGeneration != _viewLoadGeneration) return;
      final byId = <String, MomentComment>{
        if (append)
          for (final comment in _comments ?? const <MomentComment>[])
            comment.id: comment,
        for (final comment in view.comments) comment.id: comment,
      };
      setState(() {
        _moment = view.moment;
        _unavailable = false;
        _comments = byId.values.toList(growable: false);
        _commentsTruncated = view.commentsTruncated;
        _nextCommentCursor = view.nextCommentCursor;
        _loadError = null;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || requestGeneration != _viewLoadGeneration) return;
      if (_momentCommentsIsGoneError(error)) {
        _clearCommentsAndShowGone();
      } else {
        setState(() => _loadError = error);
      }
    } finally {
      if (!append) _canonicalRefreshesInFlight.remove(trigger);
      if (mounted && append && _loadingMore) {
        setState(() => _loadingMore = false);
      }
    }
  }

  @override
  void dispose() {
    _viewLoadGeneration += 1;
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _mentionFriends
      ..removeListener(_handleMentionFriends)
      ..dispose();
    _arbiter.dispose();
    _controller.dispose();
    _composerFocus.dispose();
    _goneBackFocus.dispose();
    super.dispose();
  }

  void _handleExpired() {
    _clearCommentsAndShowGone(announce: false);
    _announceGone();
  }

  void _clearCommentsAndShowGone({bool announce = true}) {
    if (!mounted) return;
    setState(() {
      _unavailable = true;
      _comments = null;
      _commentsTruncated = false;
      _nextCommentCursor = null;
      _loadError = null;
      _loadingMore = false;
    });
    if (announce) _announceGone();
  }

  void _announceGone() {
    final copy = AppLocalizations.of(context);
    final previousFocus = FocusManager.instance.primaryFocus;
    final recoverFocus = momentExpiryFocusIsWithin(context, previousFocus);
    _expiryAnnouncer.announce(
      context,
      transition: 'comments-gone-${_moment.id}',
      message: copy.text(
        'Voice Moment expired. Comments are now unavailable.',
        'Voice Moment wygasł. Komentarze nie są już dostępne.',
      ),
    );
    recoverMomentExpiryFocusAfterFrame(
      context: context,
      fallback: _goneBackFocus,
      previousFocus: recoverFocus ? previousFocus : null,
    );
  }

  Future<void> _sendComment() async {
    final text = _controller.text.trim();
    final user = _auth?.currentUser;
    final service = _momentService;
    final now = (widget.expiryClock ?? DateTime.now)();
    if (text.isEmpty ||
        user == null ||
        service == null ||
        _sending ||
        _unavailable ||
        !_moment.isActiveAt(now)) {
      return;
    }

    setState(() => _sending = true);
    try {
      await service.createTextComment(momentId: _moment.id, text: text);
      _controller.clear();
      await _loadComments(trigger: _MomentCommentsRefreshTrigger.mutation);
    } catch (error) {
      if (!mounted) return;
      final copy = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorMessage(
                error,
                fallback: copy.text(
                  'Could not post the comment. Please try again.',
                  'Nie udało się opublikować komentarza. Spróbuj ponownie.',
                ),
                copy: copy,
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// "Reply" under a comment. Threads are flat on the server, so this
  /// prefills the composer with `@name ` rather than pretending a nested
  /// reply exists.
  void _prefillReply(MomentComment comment) {
    final mention = '@${comment.authorName} ';
    final current = _controller.text;
    if (!current.startsWith(mention)) {
      _controller.text = '$mention${current.trimLeft()}';
    }
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _composerFocus.requestFocus();
  }

  /// Reports one comment.
  ///
  /// A voice reply is the one place in Moments where the abuse can be in
  /// audio nobody has transcribed, so the report carries the exact comment
  /// id — "report the person" would leave a moderator hunting through a
  /// thread for which clip was meant.
  Future<void> _reportComment(MomentComment comment) async {
    final copy = AppLocalizations.of(context);
    await reportContent(
      context: context,
      service: widget.contentReportService,
      content: ReportedContent.voiceMomentComment(
        momentId: _moment.id,
        commentId: comment.id,
        reportReceipt: comment.reportReceipt,
      ),
      title: copy.text('Report this comment', 'Zgłoś ten komentarz'),
      subtitle: copy.text(
        'Your report goes to the YO Voice moderation team with this '
            'comment attached. ${comment.authorName} is not told who reported it.',
        'Zgłoszenie wraz z komentarzem trafi do zespołu moderacji YO Voice. '
            '${comment.authorName} nie dowie się, kto dokonał zgłoszenia.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      key: const ValueKey('moment-comments-screen'),
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        title: Text(copy.text('Comments', 'Komentarze')),
      ),
      body: SafeArea(
        child: _unavailable
            ? _commentsGoneState(copy, palette)
            : MomentExpiryBoundary(
                moment: _moment,
                clock: widget.expiryClock,
                timerFactory: widget.expiryTimerFactory,
                onExpired: _handleExpired,
                expired: _commentsGoneState(copy, palette),
                child: ResponsiveContentFrame(
                  width: ResponsiveContentWidth.form,
                  child: Column(
                    children: [
                      Expanded(
                        child: _loadError != null && _comments == null
                            ? Center(
                                child: TextButton.icon(
                                  key: const ValueKey(
                                    'moment-comments-page-retry',
                                  ),
                                  onPressed: () => _loadComments(
                                    trigger:
                                        _MomentCommentsRefreshTrigger.retry,
                                  ),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: Text(
                                    copy.text(
                                      'Could not load comments. Try again.',
                                      'Nie udało się wczytać komentarzy. Spróbuj ponownie.',
                                    ),
                                  ),
                                ),
                              )
                            : _comments == null
                            ? Center(
                                child: CircularProgressIndicator(
                                  color: colors.primary,
                                ),
                              )
                            : _comments!.isEmpty
                            ? Center(
                                child: Text(
                                  copy.text(
                                    'Be the first to comment.',
                                    'Napisz pierwszy komentarz.',
                                  ),
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount:
                                    _comments!.length +
                                    ((_commentsTruncated || _loadingMore)
                                        ? 1
                                        : 0),
                                separatorBuilder: (_, __) =>
                                    const SizedBox.shrink(),
                                itemBuilder: (context, index) {
                                  if (index == _comments!.length) {
                                    return Center(
                                      child: TextButton.icon(
                                        key: const ValueKey(
                                          'moment-comments-page-load-more',
                                        ),
                                        onPressed: _loadingMore
                                            ? null
                                            : () => _loadComments(
                                                cursor: _nextCommentCursor,
                                                append: true,
                                              ),
                                        icon: _loadingMore
                                            ? const SizedBox.square(
                                                dimension: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.expand_more_rounded,
                                              ),
                                        label: Text(
                                          copy.text(
                                            'Load more',
                                            'Wczytaj więcej',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  final comment = _comments![index];
                                  final service = _momentService;
                                  return MomentCommentRow(
                                    comment: comment,
                                    momentId: _moment.id,
                                    isOwn:
                                        comment.authorId.isNotEmpty &&
                                        comment.authorId == _currentUid,
                                    mentions: _readDirectory(),
                                    arbiter: _arbiter,
                                    resolveReplyMedia: service == null
                                        ? null
                                        : (commentId) =>
                                              service.resolveMediaUri(
                                                momentId: _moment.id,
                                                commentId: commentId,
                                              ),
                                    onReplyTo: _prefillReply,
                                    onReport: (target) =>
                                        unawaited(_reportComment(target)),
                                  );
                                },
                              ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                        decoration: BoxDecoration(
                          color: palette.surfaceRaised,
                          border: Border(
                            top: BorderSide(color: palette.border),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: MentionComposerField(
                                fieldKey: const ValueKey(
                                  'moment-comments-field',
                                ),
                                controller: _controller,
                                focusNode: _composerFocus,
                                directory: _composerDirectory(),
                                maxLines: 4,
                                hintText: copy.text(
                                  'Write a comment...',
                                  'Napisz komentarz…',
                                ),
                                onSubmitted: (_) => _sendComment(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: IconButton.filled(
                                onPressed: _sending ? null : _sendComment,
                                tooltip: copy.text(
                                  'Post comment',
                                  'Opublikuj komentarz',
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: colors.primary,
                                  foregroundColor: colors.onPrimary,
                                ),
                                icon: _sending
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: colors.onPrimary,
                                        ),
                                      )
                                    : const Icon(Icons.send_rounded),
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
    );
  }

  Widget _commentsGoneState(AppLocalizations copy, AppPalette palette) {
    return Center(
      key: const ValueKey('moment-comments-gone'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              copy.text(
                'This Voice Moment is no longer available.',
                'Ten Voice Moment nie jest już dostępny.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('moment-comments-gone-back'),
              focusNode: _goneBackFocus,
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(copy.text('Back to Moments', 'Wróć do Momentów')),
            ),
          ],
        ),
      ),
    );
  }
}
