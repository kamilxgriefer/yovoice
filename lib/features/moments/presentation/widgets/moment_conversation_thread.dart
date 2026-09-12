import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_mentions.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_time_labels.dart';
import 'package:yovoice/features/moments/presentation/widgets/reply_playback_arbiter.dart';
import 'package:yovoice/features/moments/presentation/widgets/voice_reply_mini_player.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// One row of the "Rozmowa" thread: who replied, when, what they said —
/// as text, or as a voice reply with its own mini-player.
///
/// There is no heart on a reply: Voice Moment comments carry no like edge
/// on the server, and a control that cannot record anything is worse than
/// no control. "Reply" is honest too: the thread is flat (the callable
/// accepts `momentId`, `requestId` and `text` and nothing else), so the
/// button prefills the composer with `@name ` instead of pretending a
/// nested reply exists.
class MomentCommentRow extends StatelessWidget {
  const MomentCommentRow({
    required this.comment,
    required this.momentId,
    required this.isOwn,
    required this.mentions,
    this.arbiter,
    this.resolveReplyMedia,
    this.onReplyTo,
    this.onReport,
    this.onMentionTap,
    this.playerFactory,
    super.key,
  });

  final MomentComment comment;
  final String momentId;
  final bool isOwn;
  final MentionDirectory mentions;

  /// Keeps a voice reply from sounding over the main recording, or over
  /// another reply.
  final ReplyPlaybackArbiter? arbiter;

  /// Mints the comment-scoped media grant. Absent, a voice reply renders
  /// its row without a player rather than a control that cannot work.
  final Future<Uri> Function(String commentId)? resolveReplyMedia;

  /// Prefills the composer with `@name `.
  final ValueChanged<MomentComment>? onReplyTo;

  /// Opens the existing report flow for this comment.
  final ValueChanged<MomentComment>? onReport;

  final void Function(MentionCandidate candidate)? onMentionTap;

  @visibleForTesting
  final AudioPlayer Function()? playerFactory;

  bool get _canReport =>
      onReport != null && !isOwn && comment.id.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final resolve = resolveReplyMedia;
    final reply = onReplyTo;
    final age = momentRelativeAge(comment.createdAt, copy: copy);

    return Padding(
      key: ValueKey('moment-comment-card-${comment.id}'),
      padding: const EdgeInsets.only(bottom: AppRhythm.title),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            radius: 20,
            userId: comment.authorId,
            photoUrl: comment.authorPhotoUrl,
            displayName: comment.authorName,
          ),
          const SizedBox(width: AppRhythm.item),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppRhythm.tight,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      comment.authorName,
                      style: AppTypography.titleSmall.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    if (age.isNotEmpty)
                      Text(
                        age,
                        style: AppTypography.bodySmall.copyWith(
                          color: palette.textTertiary,
                        ),
                      ),
                    if (comment.authorId.isNotEmpty)
                      UserIdentityBadges(uid: comment.authorId),
                  ],
                ),
                const SizedBox(height: AppRhythm.tight),
                if (comment.isVoice) ...[
                  if (resolve != null)
                    VoiceReplyMiniPlayer(
                      commentId: comment.id,
                      authorName: comment.authorName,
                      durationSeconds: comment.durationSeconds,
                      resolveMediaUri: () => resolve(comment.id),
                      arbiter: arbiter,
                      playerFactory: playerFactory,
                    )
                  else
                    Text(
                      copy.template(
                        'Voice reply {duration}',
                        'Odpowiedź głosowa {duration}',
                        values: <String, Object>{
                          'duration': _clock(comment.durationSeconds),
                        },
                      ),
                      style: AppTypography.bodyMedium.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  if (comment.text.isNotEmpty) ...[
                    const SizedBox(height: AppRhythm.tight),
                    MentionText(
                      text: comment.text,
                      directory: mentions,
                      style: AppTypography.bodyMedium.copyWith(
                        color: palette.textSecondary,
                      ),
                      onMentionTap: onMentionTap,
                    ),
                  ],
                ] else
                  MentionText(
                    text: comment.text,
                    directory: mentions,
                    style: AppTypography.bodyMedium.copyWith(
                      color: palette.textPrimary,
                      height: 1.35,
                    ),
                    onMentionTap: onMentionTap,
                  ),
                if (reply != null || _canReport)
                  Row(
                    children: [
                      if (reply != null)
                        TextButton(
                          key: ValueKey('reply-to-comment-${comment.id}'),
                          onPressed: () => reply(comment),
                          style: TextButton.styleFrom(
                            foregroundColor: palette.textSecondary,
                            minimumSize: const Size(
                              0,
                              AppSizing.standardControlHeight,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppRhythm.tight,
                            ),
                          ),
                          child: Text(
                            copy.contextualText(
                              'yoMoments.replyToComment',
                              'Reply',
                              'Odpowiedz',
                            ),
                            style: AppTypography.labelLarge,
                          ),
                        ),
                      if (_canReport)
                        IconButton(
                          key: ValueKey('report-comment-${comment.id}'),
                          onPressed: () => onReport!(comment),
                          tooltip: copy.text(
                            'Report this comment',
                            'Zgłoś ten komentarz',
                          ),
                          style: IconButton.styleFrom(
                            minimumSize: const Size.square(
                              AppSizing.standardControlHeight,
                            ),
                            tapTargetSize: MaterialTapTargetSize.padded,
                          ),
                          icon: Icon(
                            Icons.flag_outlined,
                            size: 18,
                            color: palette.textSecondary,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The "Rozmowa" heading plus the loaded page of replies.
///
/// The count beside the heading is the Moment document's own
/// `commentCount`; the rows are the page the view callable already
/// returned. Older replies are fetched only when the viewer asks for them.
class MomentConversationThread extends StatelessWidget {
  const MomentConversationThread({
    required this.momentId,
    required this.comments,
    required this.commentCount,
    required this.currentUserId,
    required this.mentions,
    this.arbiter,
    this.resolveReplyMedia,
    this.onReplyTo,
    this.onReport,
    this.onMentionTap,
    this.onLoadMore,
    this.loadingMore = false,
    this.showHeading = true,
    this.emptyLabel,
    this.onCompose,
    this.onOpenFullThread,
    this.playerFactory,
    super.key,
  });

  final String momentId;
  final List<MomentComment> comments;
  final int commentCount;
  final String currentUserId;
  final MentionDirectory mentions;
  final ReplyPlaybackArbiter? arbiter;
  final Future<Uri> Function(String commentId)? resolveReplyMedia;
  final ValueChanged<MomentComment>? onReplyTo;
  final ValueChanged<MomentComment>? onReport;
  final void Function(MentionCandidate candidate)? onMentionTap;

  /// Present while the server says the conversation has another page.
  final VoidCallback? onLoadMore;
  final bool loadingMore;
  final bool showHeading;
  final String? emptyLabel;

  /// Offered only when the thread is empty and replies are still open: the
  /// one affordance that puts the caret in the composer. Absent (an expired
  /// Moment accepts nothing new) the empty line is a plain statement.
  final VoidCallback? onCompose;

  /// Opens the full-page thread. Present on the compact layouts, where the
  /// page and the thread share one scroll.
  final VoidCallback? onOpenFullThread;

  @visibleForTesting
  final AudioPlayer Function()? playerFactory;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final heading = copy.contextualText(
      'yoMoments.conversation',
      'Conversation',
      'Rozmowa',
    );
    final total = commentCount < comments.length ? comments.length : commentCount;
    return Column(
      key: const ValueKey('moment-conversation-thread'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeading) ...[
          Text(
            total > 0 ? '$heading · $total' : heading,
            key: const ValueKey('moment-conversation-heading'),
            style: AppTypography.titleLarge.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppRhythm.title),
        ],
        if (comments.isEmpty)
          if (onCompose != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('moment-comment-preview-empty'),
                onPressed: onCompose,
                style: TextButton.styleFrom(
                  foregroundColor: palette.interactiveForeground,
                  minimumSize: const Size(0, AppSizing.standardControlHeight),
                ),
                icon: const Icon(Icons.mode_comment_outlined, size: 18),
                label: Text(
                  copy.text(
                    'Be the first to comment',
                    'Skomentuj jako pierwszy',
                  ),
                  style: AppTypography.labelLarge,
                ),
              ),
            )
          else
            Text(
              emptyLabel ??
                  copy.text(
                    'Be the first to comment.',
                    'Napisz pierwszy komentarz.',
                  ),
              key: const ValueKey('moment-conversation-empty'),
              style: AppTypography.bodyMedium.copyWith(
                color: palette.textSecondary,
              ),
            )
        else
          for (final comment in comments)
            MomentCommentRow(
              comment: comment,
              momentId: momentId,
              isOwn:
                  comment.authorId.isNotEmpty &&
                  comment.authorId == currentUserId,
              mentions: mentions,
              arbiter: arbiter,
              resolveReplyMedia: resolveReplyMedia,
              onReplyTo: onReplyTo,
              onReport: onReport,
              onMentionTap: onMentionTap,
              playerFactory: playerFactory,
            ),
        // The server pages this conversation OLDEST first, so the next page
        // holds the more recent replies. The label says exactly that: a
        // button that promises "older" and delivers newer is a small lie.
        if (onLoadMore != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('moment-thread-load-more'),
              onPressed: loadingMore ? null : onLoadMore,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, AppSizing.standardControlHeight),
              ),
              icon: loadingMore
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text(
                copy.text('Show more replies', 'Pokaż więcej odpowiedzi'),
              ),
            ),
          ),
        if (onOpenFullThread != null && comments.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const ValueKey('moment-comment-preview-see-all'),
              onPressed: onOpenFullThread,
              style: TextButton.styleFrom(
                foregroundColor: palette.interactiveForeground,
                minimumSize: const Size(0, AppSizing.standardControlHeight),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      total == 1
                          ? copy.text('See the comment', 'Zobacz komentarz')
                          : copy.template(
                              'See all {count} comments',
                              'Zobacz wszystkie komentarze ({count})',
                              values: <String, Object>{'count': total},
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

String _clock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}
