import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/core/theme/app_sizing.dart';
import 'package:yovoice/core/theme/app_spacing.dart';
import 'package:yovoice/core/theme/app_typography.dart';
import 'package:yovoice/features/likers/data/models/comment_like.dart';
import 'package:yovoice/features/likers/presentation/widgets/comment_like_controls.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_mentions.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_time_labels.dart';
import 'package:yovoice/features/moments/presentation/widgets/reply_playback_arbiter.dart';
import 'package:yovoice/features/moments/presentation/widgets/voice_reply_mini_player.dart';
import 'package:yovoice/shared/widgets/identity/user_identity_badges.dart';
import 'package:yovoice/shared/widgets/interactions/accessible_tap_region.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// Opens "See who liked" for [comment]; [returnFocus] is the count control
/// that asked, so closing the flow hands keyboard focus back to it.
typedef MomentCommentLikersOpener =
    void Function(MomentComment comment, FocusNode returnFocus);

/// One row of the "Rozmowa" thread: who replied, when, what they said —
/// as text, or as a voice reply with its own mini-player.
///
/// The action line reads "Odpowiedz · ♡ 3" (owner variant B, ADR-230): the
/// heart toggles the caller's like through `setMomentCommentLikeV1`, and the
/// count beside it opens "See who liked" (the list for Premium / VIP, the
/// upsell for everyone else; for a viewer who can see likers it also reads
/// "Kto polubił"). The heart is drawn ONLY when [likeState] is non-null,
/// i.e. when the view was answered with comment likes: until the deployed
/// backend proves it can record a comment like there is no heart and no
/// "Coming soon" either, because a control that cannot record anything is
/// worse than no control.
///
/// "Reply" is honest too: the thread is flat (the callable accepts
/// `momentId`, `requestId` and `text` and nothing else), so the button
/// prefills the composer with `@name ` instead of pretending a nested reply
/// exists.
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
    this.likeState,
    this.onToggleLike,
    this.onShowLikers,
    this.showWhoLiked = false,
    this.playerFactory,
    super.key,
  });

  /// This comment's like count and the caller's like. Null: no heart.
  final CommentLikeState? likeState;

  /// Toggles the caller's like. Null draws the heart disabled.
  final ValueChanged<MomentComment>? onToggleLike;

  /// Opens "See who liked" for this comment, handing it the count's focus
  /// node to return to. Null draws the count as text.
  final MomentCommentLikersOpener? onShowLikers;

  /// The viewer may open likers lists (client pre-gate): the count also
  /// reads "Kto polubił".
  final bool showWhoLiked;

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

  /// Opens a person's profile from this thread — a tapped `@mention` in a
  /// reply, or a tapped commenter avatar. Null uses the app-wide profile
  /// preview sheet, which is what production does.
  final void Function(MentionCandidate candidate)? onMentionTap;

  @visibleForTesting
  final AudioPlayer Function()? playerFactory;

  bool get _canReport => onReport != null && !isOwn && comment.id.isNotEmpty;

  void _openAuthor(BuildContext context) {
    final candidate = MentionCandidate(
      userId: comment.authorId,
      displayName: comment.authorName,
    );
    final handler = onMentionTap;
    if (handler != null) {
      handler(candidate);
      return;
    }
    unawaited(
      showProfilePreview(
        context,
        userId: candidate.userId,
        displayName: candidate.displayName,
      ),
    );
  }

  /// "Odpowiedz · ♡ 3 Kto polubił ⚑" on one row whenever it fits, if need
  /// be with Reply's side padding given up. When the width or the reader's
  /// text size does not allow it, the line breaks after "Reply" and the
  /// heart, count and report flag move down together: the separator dot is
  /// dropped (it would start the new line), and the flag never ends up alone
  /// on a line of its own. The dot is drawn exactly while Reply and the
  /// heart share a row.
  Widget _actionLine(
    BuildContext context, {
    required AppLocalizations copy,
    required AppPalette palette,
    required CommentLikeState? likes,
  }) {
    final reply = onReplyTo;
    final toggleLike = onToggleLike;
    final showLikers = onShowLikers;
    final replyLabel = copy.contextualText(
      'yoMoments.replyToComment',
      'Reply',
      'Odpowiedz',
    );
    TextButton? replyWith({double padding = AppRhythm.tight}) => reply == null
        ? null
        : TextButton(
            key: ValueKey('reply-to-comment-${comment.id}'),
            onPressed: () => reply(comment),
            style: TextButton.styleFrom(
              foregroundColor: palette.textSecondary,
              minimumSize: const Size(0, AppSizing.standardControlHeight),
              padding: EdgeInsets.symmetric(horizontal: padding),
            ),
            child: Text(replyLabel, style: AppTypography.labelLarge),
          );
    final replyButton = replyWith();
    final likeControls = likes == null
        ? null
        : CommentLikeControls(
            commentId: comment.id,
            keyPrefix: 'moment-comment',
            state: likes,
            onToggle: toggleLike == null ? null : () => toggleLike(comment),
            onShowLikers: showLikers == null
                ? null
                : (focus) => showLikers(comment, focus),
            showWhoLiked: showWhoLiked,
          );
    final tightFlag =
        likes != null &&
        likes.likeCount > 0 &&
        showLikers != null &&
        !showWhoLiked;
    final flag = !_canReport
        ? null
        : IconButton(
            key: ValueKey('report-comment-${comment.id}'),
            onPressed: () => onReport!(comment),
            tooltip: copy.text('Report this comment', 'Zgłoś ten komentarz'),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(AppSizing.standardControlHeight),
              tapTargetSize: MaterialTapTargetSize.padded,
              // A bare count ("3") keeps a 44 px target, most of it empty
              // after the digits; the flag's glyph moves to the start of
              // its own 48 px target so the gap reads as in owner render B
              // instead of doubling. Its target is unchanged.
              alignment: tightFlag ? AlignmentDirectional.centerStart : null,
              padding: tightFlag
                  ? const EdgeInsetsDirectional.only(start: 4, end: 8)
                  : null,
            ),
            icon: Icon(
              Icons.flag_outlined,
              size: 18,
              color: palette.textSecondary,
            ),
          );
    const dotText = '·';
    final dotStyle = AppTypography.labelLarge.copyWith(
      color: palette.textTertiary,
    );
    final dot = ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(dotText, style: dotStyle),
      ),
    );

    return LayoutBuilder(
      key: ValueKey('moment-comment-actions-${comment.id}'),
      builder: (context, constraints) {
        if (likeControls == null) {
          return Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [?replyButton, ?flag],
          );
        }
        var needed = CommentLikeControls.estimatedWidth(
          context,
          state: likes!,
          interactive: showLikers != null,
          showWhoLiked: showWhoLiked,
        );
        if (replyButton != null) {
          needed +=
              CommentLikeControls.measureLabel(
                context,
                replyLabel,
                AppTypography.labelLarge,
              ) +
              2 * AppRhythm.tight +
              CommentLikeControls.measureLabel(context, dotText, dotStyle) +
              4;
        }
        if (flag != null) needed += AppSizing.standardControlHeight;
        final overflow = needed - constraints.maxWidth;
        // Up to Reply's own side padding short: the line still fits on one
        // row with the dot once Reply gives up that padding (its label keeps
        // it well over the 44 px minimum). Without this, a band of widths
        // about one dot wide drew the whole line on one row WITHOUT the dot.
        if (overflow <= 0 ||
            (replyButton != null && overflow <= 2 * AppRhythm.tight)) {
          final trim = overflow <= 0 ? 0.0 : (overflow / 2).ceilToDouble();
          return Row(
            children: [
              ?replyWith(padding: AppRhythm.tight - trim),
              if (replyButton != null) dot,
              Flexible(child: likeControls),
              ?flag,
            ],
          );
        }
        // An explicit break, not a Wrap: a Wrap would still put everything
        // on one row whenever it fits without the dot, i.e. a row that
        // silently lost its separator.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ?replyButton,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: likeControls),
                ?flag,
              ],
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final resolve = resolveReplyMedia;
    final reply = onReplyTo;
    // An id-less row (a directly constructed model) cannot be liked.
    final likes = comment.id.isEmpty ? null : likeState;
    final age = momentRelativeAge(comment.createdAt, copy: copy);
    final avatar = UserAvatar(
      radius: 20,
      userId: comment.authorId,
      photoUrl: comment.authorPhotoUrl,
      displayName: comment.authorName,
    );
    final openLabel = copy.template(
      'Open profile of {name}',
      'Otwórz profil: {name}',
      values: <String, Object>{'name': comment.authorName},
    );

    return Padding(
      key: ValueKey('moment-comment-card-${comment.id}'),
      padding: const EdgeInsets.only(bottom: AppRhythm.title),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The moment's author is already a profile action one row above;
          // a commenter must be one too. An authorless row (a directly
          // constructed model) stays inert rather than opening a sheet that
          // would assert on an empty document id — the same guard the
          // identity badges below already apply.
          if (comment.authorId.isEmpty)
            avatar
          else
            AccessibleTapRegion(
              key: ValueKey('moment-comment-profile-${comment.id}'),
              onTap: () => _openAuthor(context),
              semanticLabel: openLabel,
              tooltip: openLabel,
              circular: true,
              child: ExcludeSemantics(child: avatar),
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
                if (reply != null || _canReport || likes != null)
                  _actionLine(
                    context,
                    copy: copy,
                    palette: palette,
                    likes: likes,
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
    this.likeStateOf,
    this.onToggleLike,
    this.onShowLikers,
    this.showWhoLiked = false,
    this.playerFactory,
    super.key,
  });

  final String momentId;
  final List<MomentComment> comments;

  /// Each row's comment-like state (see [MomentCommentRow.likeState]). Null,
  /// or null for a comment, draws no heart on it.
  final CommentLikeState? Function(String commentId)? likeStateOf;
  final ValueChanged<MomentComment>? onToggleLike;
  final MomentCommentLikersOpener? onShowLikers;
  final bool showWhoLiked;
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
    final total = commentCount < comments.length
        ? comments.length
        : commentCount;
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
              likeState: likeStateOf?.call(comment.id),
              onToggleLike: onToggleLike,
              onShowLikers: onShowLikers,
              showWhoLiked: showWhoLiked,
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
