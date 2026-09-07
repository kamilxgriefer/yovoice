import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_reason_labels.dart';
import 'package:yovoice/features/reels/data/services/reel_service.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

/// What a reporter decided, before anything has been sent.
///
/// The sheet collects intent and returns it; the call belongs to the thread
/// that owns the request id, so a retry of the same intent is provably the
/// same attempt rather than a second report.
@immutable
class ReelCommentReportRequest {
  const ReelCommentReportRequest({required this.reason, this.note = ''});

  final ReportReason reason;

  /// Already trimmed and already bounded to [maxReelReportNoteLength].
  final String note;

  /// The value `createReelCommentReport` validates. [ReportReason]'s names
  /// are the contract's names — the enum exists precisely so this is a
  /// lookup rather than a hand-maintained second list that can drift.
  String get wireReason => reason.name;

  @override
  bool operator ==(Object other) =>
      other is ReelCommentReportRequest &&
      other.reason == reason &&
      other.note == note;

  @override
  int get hashCode => Object.hash(reason, note);
}

/// Asks why this comment is being reported, and confirms before sending.
///
/// WHY THIS IS NOT THE ONE-TAP [showReportReasonSheet] USED ELSEWHERE.
/// That sheet files the moment a reason is tapped, which is right when the
/// target is a whole Reel or an account and a mis-tap is cheap. A comment
/// sits in a dense scrolling list where the rows are small and adjacent, so
/// the mis-tap is not cheap: it names a specific person in a staff queue
/// over words they may not have written. One deliberate Send is the
/// confirmation, and it is also what makes an optional note possible — the
/// backend accepts 300 characters of context and a moderator judging
/// `other`, or an impersonation claim, usually cannot decide without it.
///
/// The friction is bounded on purpose: the reason list is still one tap, the
/// note is genuinely optional, nothing is required after Send, and the sheet
/// is dismissible throughout.
///
/// [initialReason] and [initialNote] restore a previous attempt so a retry
/// after a refusal is one tap rather than a re-typed note — which is also
/// what keeps the retry byte-identical, and therefore free at the server's
/// operation ledger.
///
/// Returns null if the reporter backed out. Returning a request is a
/// decision to send, not a sent report: the caller still has to succeed.
Future<ReelCommentReportRequest?> showReelCommentReportSheet(
  BuildContext context, {
  required String authorName,
  required String commentText,
  ReportReason? initialReason,
  String initialNote = '',
}) {
  return showModalBottomSheet<ReelCommentReportRequest>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    showDragHandle: false,
    useSafeArea: true,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(
      context,
      maxWidth: 520,
    ),
    builder: (context) => ReelCommentReportSheet(
      authorName: authorName,
      commentText: commentText,
      initialReason: initialReason,
      initialNote: initialNote,
    ),
  );
}

/// The picker itself, separated from [showReelCommentReportSheet] so it can
/// be pumped directly in a widget test without a route.
class ReelCommentReportSheet extends StatefulWidget {
  const ReelCommentReportSheet({
    required this.authorName,
    required this.commentText,
    this.initialReason,
    this.initialNote = '',
    super.key,
  });

  final String authorName;
  final String commentText;
  final ReportReason? initialReason;
  final String initialNote;

  @override
  State<ReelCommentReportSheet> createState() => _ReelCommentReportSheetState();
}

class _ReelCommentReportSheetState extends State<ReelCommentReportSheet> {
  late final TextEditingController _note = TextEditingController(
    text: widget.initialNote,
  );
  late ReportReason? _reason = widget.initialReason;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _send() {
    final reason = _reason;
    if (reason == null) return;
    Navigator.of(context).pop(
      ReelCommentReportRequest(
        reason: reason,
        // Trimmed here so the value hashed into the server's idempotency
        // identity is byte-identical across retries of the same attempt.
        note: _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    // Accessibility text scaling, read from the platform rather than from a
    // device label. Past roughly 130% the header has to give up room so the
    // reason list is not pushed off screen — see the block that uses it.
    final bigType = media.textScaler.scale(1) > 1.3;
    return Container(
      key: const ValueKey<String>('reel-comment-report-sheet'),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: palette.border)),
      ),
      // The ceiling is a share of the space left ABOVE the keyboard, not of
      // the whole screen: the note field can raise one, and a sheet sized to
      // the full height would push its own Send button under it.
      constraints: BoxConstraints(
        maxHeight:
            (media.size.height - media.viewInsets.bottom).clamp(
              240.0,
              media.size.height,
            ) *
            .9,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              YoModalSheetChrome(
                sheetLabel: copy.text('Report comment', 'Zgłoś komentarz'),
                surfaceColor: palette.surfaceRaised,
                handleColor: palette.borderStrong,
                closeColor: palette.textSecondary,
              ),
              // EVERYTHING except the action bar scrolls. At 200% text scale
              // on a 320 px screen the eight reasons are taller than the
              // window on their own, so a non-scrolling list would put the
              // last reasons — including self-harm — out of reach.
              //
              // A Column in a scroll view rather than a lazy ListView, on
              // purpose: the reasons are a fixed set of eight and the note
              // must keep its text while it is scrolled off screen. A lazy
              // list would dispose the field the reporter was typing in.
              Flexible(
                child: SingleChildScrollView(
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // A SHORT, FIXED TITLE. The author's name belongs to
                      // the quote below, not to the heading: at 200% text
                      // scale on a 320 px window, "Report <long name>'s
                      // comment" wraps to three lines and — with the
                      // confidentiality paragraph that used to sit under it
                      // — pushed every one of the eight reasons below the
                      // fold. A reporter opening this sheet must see a
                      // reason without scrolling first.
                      Text(
                        copy.text('Report this comment', 'Zgłoś ten komentarz'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // The exact words being reported, and whose they are. A
                      // dense thread makes the wrong row easy to hit, and a
                      // report names a real person in a staff queue, so the
                      // reporter gets to see what they are about to send.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.surfaceSunken,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: palette.border),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                widget.authorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                key: const ValueKey<String>(
                                  'reel-comment-report-target',
                                ),
                                widget.commentText,
                                // Fewer lines as the type grows: this block
                                // confirms WHICH comment, and the full text
                                // is still on the row behind the sheet.
                                maxLines: bigType ? 2 : 4,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // A real radio group, not eight independent tiles: it
                      // carries mutual exclusion to assistive technology and
                      // gives the desktop layout arrow-key traversal for free.
                      RadioGroup<ReportReason>(
                        groupValue: _reason,
                        onChanged: (value) => setState(() => _reason = value),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            for (final reason in ReportReason.values)
                              RadioListTile<ReportReason>(
                                key: ValueKey<String>(
                                  'reel-comment-report-reason-${reason.name}',
                                ),
                                value: reason,
                                contentPadding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                controlAffinity:
                                    ListTileControlAffinity.trailing,
                                // Self-harm is the one entry that can be a
                                // welfare emergency rather than a rule
                                // violation. Marking it is how a distressed
                                // reporter finds it without reading all eight.
                                secondary: Icon(
                                  _iconFor(reason),
                                  color: reason == ReportReason.selfHarm
                                      ? palette.dangerForeground
                                      : palette.textSecondary,
                                ),
                                title: Text(
                                  reportReasonLabel(reason, copy: copy),
                                  style: TextStyle(color: palette.textPrimary),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey<String>('reel-comment-report-note'),
                        controller: _note,
                        minLines: 2,
                        maxLines: 4,
                        maxLength: maxReelReportNoteLength,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        inputFormatters: <TextInputFormatter>[
                          // The server bounds this at 300 and answers
                          // `invalid-argument` past it. Spending one of ten
                          // reports per ten minutes to learn that would be a
                          // bad trade on a safety path, so the limit binds
                          // before the call rather than after it.
                          LengthLimitingTextInputFormatter(
                            maxReelReportNoteLength,
                          ),
                        ],
                        decoration: InputDecoration(
                          labelText: copy.text(
                            'Anything else? (optional)',
                            'Coś jeszcze? (opcjonalnie)',
                          ),
                          helperText: copy.text(
                            'Context helps our team decide faster.',
                            'Kontekst pomoże nam szybciej ocenić zgłoszenie.',
                          ),
                          helperMaxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Below the reasons on purpose. It is reassurance, not
                      // an input to the decision, and above the list it cost
                      // a whole screen of height at large text sizes — which
                      // is exactly the reader least able to afford it.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 16,
                            color: palette.textTertiary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              copy.text(
                                'Your report is confidential. Our team '
                                    'reviews it — the comment stays up until '
                                    'they decide.',
                                'Twoje zgłoszenie jest poufne. Sprawdzi je '
                                    'nasz zespół — do tego czasu komentarz '
                                    'pozostaje widoczny.',
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: palette.textTertiary,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // A real edge, not just space. The list scrolls underneath this
              // bar, and at large text sizes a half-clipped reason sitting
              // directly against "Cancel" read as one broken row — the
              // captures showed it before this border existed.
              DecoratedBox(
                decoration: BoxDecoration(
                  // borderStrong, not border: this bar sits on `surfaceRaised`
                  // rather than the page background, and at that contrast the
                  // lighter token disappeared entirely in the dark theme.
                  border: Border(top: BorderSide(color: palette.borderStrong)),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    12 + media.padding.bottom,
                  ),
                  // OverflowBar stacks rather than clipping when the two
                  // labels no longer fit side by side, which is exactly what
                  // happens at 200% text scale on the narrowest phone.
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    overflowAlignment: OverflowBarAlignment.center,
                    spacing: 8,
                    overflowSpacing: 8,
                    children: <Widget>[
                      TextButton(
                        key: const ValueKey<String>(
                          'reel-comment-report-cancel',
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(copy.text('Cancel', 'Anuluj')),
                      ),
                      FilledButton.icon(
                        key: const ValueKey<String>(
                          'reel-comment-report-submit',
                        ),
                        // Disabled until a reason is chosen, because the field
                        // is a closed set the queue filters on: a report with
                        // a guessed reason is worse than no report, and there
                        // is no honest default to pre-select.
                        onPressed: _reason == null ? null : _send,
                        icon: const Icon(Icons.outlined_flag_rounded),
                        label: Text(
                          copy.text('Send report', 'Wyślij zgłoszenie'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(ReportReason reason) => switch (reason) {
    ReportReason.spam => Icons.link_off_rounded,
    ReportReason.harassment => Icons.mood_bad_rounded,
    ReportReason.hate => Icons.do_not_disturb_on_outlined,
    ReportReason.sexual => Icons.no_adult_content_rounded,
    ReportReason.violence => Icons.warning_amber_rounded,
    ReportReason.selfHarm => Icons.favorite_outline_rounded,
    ReportReason.impersonation => Icons.person_off_outlined,
    ReportReason.other => Icons.more_horiz_rounded,
  };
}
