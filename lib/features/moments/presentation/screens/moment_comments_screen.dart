import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moderation/data/services/content_report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_content_flow.dart';
import 'package:yovoice/features/moments/data/models/voice_moment.dart';
import 'package:yovoice/features/moments/data/services/moment_expiry_scheduler.dart';
import 'package:yovoice/features/moments/data/services/moment_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_accessibility.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_expiry_boundary.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

class MomentCommentsScreen extends StatefulWidget {
  const MomentCommentsScreen({
    required this.moment,
    this.firestore,
    this.auth,
    this.momentService,
    this.contentReportService,
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
  final MomentExpiryClock? expiryClock;
  final MomentExpiryTimerFactory? expiryTimerFactory;

  @override
  State<MomentCommentsScreen> createState() => _MomentCommentsScreenState();
}

class _MomentCommentsScreenState extends State<MomentCommentsScreen> {
  final TextEditingController _controller = TextEditingController();
  late final FirebaseFirestore _firestore =
      widget.firestore ?? FirebaseFirestore.instance;
  late final FirebaseAuth? _auth = _resolveAuth();
  late final MomentService? _momentService = _resolveMomentService();
  final FocusNode _goneBackFocus = FocusNode(
    debugLabel: 'Expired Moment comments back',
  );
  final MomentExpiryAnnouncer _expiryAnnouncer = MomentExpiryAnnouncer();
  bool _sending = false;

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

  CollectionReference<Map<String, dynamic>> get _comments => _firestore
      .collection('voiceMoments')
      .doc(widget.moment.id)
      .collection('comments');

  @override
  void dispose() {
    _controller.dispose();
    _goneBackFocus.dispose();
    super.dispose();
  }

  void _handleExpired() {
    final previousFocus = FocusManager.instance.primaryFocus;
    final recoverFocus = momentExpiryFocusIsWithin(context, previousFocus);
    _expiryAnnouncer.announce(
      context,
      transition: 'comments-gone-${widget.moment.id}',
      message: 'Voice Moment expired. Comments are now unavailable.',
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
        !widget.moment.isActiveAt(now)) {
      return;
    }

    setState(() => _sending = true);
    try {
      await service.createTextComment(momentId: widget.moment.id, text: text);
      _controller.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not post comment: $error')),
        );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      key: const ValueKey('moment-comments-screen'),
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        title: const Text('Comments'),
      ),
      body: SafeArea(
        child: MomentExpiryBoundary(
          moment: widget.moment,
          clock: widget.expiryClock,
          timerFactory: widget.expiryTimerFactory,
          onExpired: _handleExpired,
          expired: Center(
            key: const ValueKey('moment-comments-gone'),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'This Voice Moment is no longer available.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('moment-comments-gone-back'),
                    focusNode: _goneBackFocus,
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Back to Moments'),
                  ),
                ],
              ),
            ),
          ),
          child: ResponsiveContentFrame(
            width: ResponsiveContentWidth.form,
            child: Column(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _comments
                        .orderBy('createdAt', descending: false)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Could not load comments.',
                            style: TextStyle(color: palette.textSecondary),
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: colors.primary,
                          ),
                        );
                      }
                      final comments = snapshot.data!.docs;
                      if (comments.isEmpty) {
                        return Center(
                          child: Text(
                            'Be the first to comment.',
                            style: TextStyle(color: palette.textSecondary),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: comments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final data = comments[index].data();
                          final name =
                              data['authorName'] as String? ?? 'YO Voice user';
                          final photo = data['authorPhotoUrl'] as String?;
                          final type = data['type'] as String? ?? 'text';
                          final authorId = data['authorId'] as String? ?? '';
                          return _CommentCard(
                            name: name,
                            authorId: authorId,
                            photo: photo,
                            data: data,
                            isVoice: type == 'voice',
                            momentId: widget.moment.id,
                            commentId: comments[index].id,
                            isOwn:
                                authorId.isNotEmpty && authorId == _currentUid,
                            contentReportService: widget.contentReportService,
                          );
                        },
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised,
                    border: Border(top: BorderSide(color: palette.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendComment(),
                          style: TextStyle(color: palette.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Write a comment...',
                            hintStyle: TextStyle(color: palette.textTertiary),
                            filled: true,
                            fillColor: palette.surfaceSunken,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        onPressed: _sending ? null : _sendComment,
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
}

class _CommentCard extends StatefulWidget {
  const _CommentCard({
    required this.name,
    required this.authorId,
    required this.photo,
    required this.data,
    required this.isVoice,
    required this.momentId,
    required this.commentId,
    required this.isOwn,
    this.contentReportService,
  });
  final String name;
  final String authorId;
  final String? photo;
  final Map<String, dynamic> data;
  final bool isVoice;
  final String momentId;
  final String commentId;
  final bool isOwn;
  final ContentReportService? contentReportService;

  @override
  State<_CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<_CommentCard> {
  AudioPlayer? _player;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isVoice) return;
    final player = AudioPlayer();
    _player = player;
    player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final player = _player;
    if (player == null) return;
    final url = widget.data['audioUrl'] as String?;
    if (url == null || url.isEmpty) return;
    if (_playing) {
      await player.pause();
    } else {
      await player.play(UrlSource(url));
    }
    if (mounted) setState(() => _playing = !_playing);
  }

  /// Reports this comment.
  ///
  /// A voice reply is the one place in Moments where the abuse can be in
  /// audio nobody has transcribed, so the report has to carry the exact
  /// comment id — "report the person" would leave a moderator hunting
  /// through a thread for which clip was meant.
  Future<void> _report() async {
    await reportContent(
      context: context,
      service: widget.contentReportService,
      content: ReportedContent.voiceMomentComment(
        momentId: widget.momentId,
        commentId: widget.commentId,
      ),
      title: 'Report this comment',
      subtitle:
          'Your report goes to the YO Voice moderation team with this '
          'comment attached. ${widget.name} is not told who reported it.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.data['text'] as String? ?? '';
    final duration = widget.data['durationSeconds'] as int? ?? 0;
    final palette = context.appPalette;
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('moment-comment-card-${widget.commentId}'),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            backgroundImage: widget.photo?.isNotEmpty == true
                ? NetworkImage(widget.photo!)
                : null,
            child: widget.photo?.isNotEmpty == true
                ? null
                : Text(
                    widget.name.isNotEmpty ? widget.name[0].toUpperCase() : 'Y',
                  ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      widget.name,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (widget.authorId.isNotEmpty)
                      UserIdentityBadges(uid: widget.authorId),
                  ],
                ),
                if (widget.isVoice) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _toggle,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: colors.onSecondaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Voice reply',
                              style: TextStyle(
                                color: colors.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '0:${duration.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              color: colors.onSecondaryContainer.withValues(
                                alpha: .75,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (text.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(text, style: TextStyle(color: palette.textSecondary)),
                  ],
                ] else ...[
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: TextStyle(color: palette.textPrimary, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          // Fixed width beside an Expanded body, so it cannot be pushed
          // off the card by a long comment or a large text scale. Hidden
          // on your own comment for the same reason as elsewhere:
          // self-reports are queue noise, not signal.
          if (!widget.isOwn && widget.commentId.isNotEmpty)
            IconButton(
              key: ValueKey('report-comment-${widget.commentId}'),
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              padding: EdgeInsets.zero,
              tooltip: 'Report this comment',
              onPressed: _report,
              icon: Icon(
                Icons.flag_outlined,
                size: 18,
                color: palette.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
