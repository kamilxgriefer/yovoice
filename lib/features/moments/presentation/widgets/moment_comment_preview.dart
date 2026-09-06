import 'dart:async';

import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moments/data/services/voice_moment_read_service.dart';
import 'package:yovoice/features/moments/presentation/widgets/moment_mentions.dart';
import 'package:yovoice/shared/widgets/profile/profile_preview_sheet.dart';
import 'package:yovoice/shared/widgets/profile/user_avatar.dart';

/// How many comments a preview shows before deferring to the thread.
const int kMomentCommentPreviewLimit = 3;

/// The last few comments on a Moment, inline.
///
/// Built entirely from comments the Moment view callable **already
/// returned** — no second read, no new callable, no comment count that
/// disagrees with the Moment document. The thread itself (voice replies,
/// reporting, pagination) stays on [MomentCommentsScreen], one tap away
/// through the "see all" row.
///
/// The server pages comments oldest-first, so this shows the newest of
/// what is loaded rather than claiming to be the newest of the thread —
/// the copy never says "newest" for that reason.
class MomentCommentPreview extends StatelessWidget {
  const MomentCommentPreview({
    required this.comments,
    required this.totalCommentCount,
    required this.onSeeAll,
    this.onCompose,
    this.friends = const <MentionCandidate>[],
    this.momentAuthor,
    this.limit = kMomentCommentPreviewLimit,
    this.onMentionTap,
    super.key,
  });

  /// Comments already loaded for this Moment, oldest first.
  final List<MomentComment> comments;

  /// The Moment document's own count — the honest total.
  final int totalCommentCount;

  /// Opens the full comment thread.
  final VoidCallback onSeeAll;

  /// Offered only when there is nothing to preview yet. Null renders the
  /// empty line as a plain statement instead of an affordance (an
  /// expired Moment accepts no new comments).
  final VoidCallback? onCompose;

  /// Extra people an `@mention` in these comments may resolve to. Thread
  /// participants are always included.
  final List<MentionCandidate> friends;

  /// The Moment's author, who is a participant even without a comment.
  final MentionCandidate? momentAuthor;

  final int limit;

  /// Test seam; production opens the shared profile preview sheet.
  final void Function(MentionCandidate candidate)? onMentionTap;

  /// The comments actually rendered: the newest [limit] of what is
  /// loaded, still in reading order.
  List<MomentComment> get visibleComments {
    if (comments.length <= limit) return comments;
    return comments.sublist(comments.length - limit);
  }

  MentionDirectory _directory() => MentionDirectory(<MentionCandidate>[
    ?momentAuthor,
    for (final comment in comments)
      if (comment.authorId.isNotEmpty && comment.authorName.trim().isNotEmpty)
        MentionCandidate(
          userId: comment.authorId,
          displayName: comment.authorName,
        ),
    ...friends,
  ]);

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final visible = visibleComments;

    if (visible.isEmpty) {
      final compose = onCompose;
      if (compose == null) {
        return Text(
          copy.text('No comments yet', 'Brak komentarzy'),
          key: const ValueKey('moment-comment-preview-empty'),
          style: TextStyle(color: palette.textTertiary, fontSize: 12.5),
        );
      }
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey('moment-comment-preview-empty'),
          onPressed: compose,
          style: TextButton.styleFrom(
            foregroundColor: palette.interactiveForeground,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 44),
          ),
          icon: const Icon(Icons.mode_comment_outlined, size: 17),
          label: Text(
            copy.text('Be the first to comment', 'Skomentuj jako pierwszy'),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    final total = totalCommentCount < comments.length
        ? comments.length
        : totalCommentCount;
    final directory = _directory();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Adapts to the space the preview actually gets — a feed card
        // column, a 640 px detail measure or a desktop content slot —
        // never to a device label.
        final compact = constraints.maxWidth < 420;
        return Column(
          key: const ValueKey('moment-comment-preview'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final comment in visible)
              _PreviewRow(
                comment: comment,
                directory: directory,
                compact: compact,
                onMentionTap: onMentionTap,
              ),
            const SizedBox(height: 2),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const ValueKey('moment-comment-preview-see-all'),
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  foregroundColor: palette.interactiveForeground,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 44),
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
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.comment,
    required this.directory,
    required this.compact,
    this.onMentionTap,
  });

  final MomentComment comment;
  final MentionDirectory directory;
  final bool compact;
  final void Function(MentionCandidate candidate)? onMentionTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final nameStyle = TextStyle(
      color: palette.textPrimary,
      fontSize: compact ? 12.5 : 13,
      fontWeight: FontWeight.w800,
    );
    final bodyStyle = TextStyle(
      color: palette.textSecondary,
      fontSize: compact ? 12.5 : 13,
      height: 1.3,
    );

    return Padding(
      key: ValueKey('moment-comment-preview-row-${comment.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: UserAvatar(
              radius: compact ? 11 : 12.5,
              userId: comment.authorId,
              photoUrl: comment.authorPhotoUrl,
              displayName: comment.authorName,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: comment.isVoice
                ? _VoiceLine(
                    comment: comment,
                    nameStyle: nameStyle,
                    compact: compact,
                  )
                // One line, ellipsised: a preview, not the thread. The
                // name is capped at a share of the line so a very long
                // display name can never eat the comment it belongs to.
                : LayoutBuilder(
                    builder: (context, constraints) => Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * .45,
                          ),
                          child: Text(
                            comment.authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: nameStyle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: MentionText(
                            text: comment.text,
                            directory: directory,
                            style: bodyStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            onMentionTap: onMentionTap,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

String _clockLabel(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}

/// A voice reply has no text to preview, so the preview states what it
/// is and how long it runs — never a transcript nobody produced.
class _VoiceLine extends StatelessWidget {
  const _VoiceLine({
    required this.comment,
    required this.nameStyle,
    required this.compact,
  });

  final MomentComment comment;
  final TextStyle nameStyle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final copy = AppLocalizations.of(context);
    final duration = _clockLabel(comment.durationSeconds);
    return Row(
      children: [
        Flexible(
          child: Text(
            comment.authorName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: nameStyle,
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          label: copy.template(
            'Voice reply {duration}',
            'Odpowiedź głosowa {duration}',
            values: <String, Object>{'duration': duration},
          ),
          child: ExcludeSemantics(
            child: Container(
              key: ValueKey('moment-comment-preview-voice-${comment.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: palette.surfaceSunken,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    // A mic, not an equalizer: `graphic_eq`'s thin bars
                    // merge into an unreadable blob at 12-13 px, and this
                    // chip states that the reply IS voice — the play
                    // control belongs to the thread, not to a preview.
                    Icons.mic_rounded,
                    size: 13,
                    color: palette.interactiveForeground,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    duration,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: compact ? 11 : 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Opens the shared profile preview for a resolved mention.
void openMentionProfile(BuildContext context, MentionCandidate candidate) {
  unawaited(
    showProfilePreview(
      context,
      userId: candidate.userId,
      displayName: candidate.displayName,
    ),
  );
}
