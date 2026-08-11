import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';

/// User-facing label for each reason firestore.rules accepts. The enum is
/// the contract; this is only how it reads.
String reportReasonLabel(ReportReason reason) => switch (reason) {
  ReportReason.spam => 'Spam or scam',
  ReportReason.harassment => 'Harassment or bullying',
  ReportReason.hate => 'Hate speech',
  ReportReason.sexual => 'Sexual content',
  ReportReason.violence => 'Violence or threats',
  ReportReason.selfHarm => 'Self-harm',
  ReportReason.impersonation => 'Impersonation',
  ReportReason.other => 'Something else',
};

/// What the reporter chose, or null if they backed out.
class ReportSubmission {
  const ReportSubmission({required this.reason, required this.note});

  final ReportReason reason;
  final String note;
}

/// The compact reason picker behind a Global Chat message's "Report".
///
/// Deliberately a dialog rather than a screen: reporting happens from a
/// hover menu inside a Home module, and yanking someone out of Home to
/// fill in a form is how reports stop getting filed. A reason is
/// REQUIRED — a report with no reason is close to useless in triage, and
/// the previous version silently sent `other` for everything.
///
/// The note is optional and bounded to [ReportService.maxNoteLength],
/// the same number firestore.rules enforces, with the remaining count
/// shown as it fills. No status, assignee or resolution field is offered
/// here or accepted by rules on create.
Future<ReportSubmission?> showReportMessageSheet(
  BuildContext context, {
  required String senderName,
}) {
  return showDialog<ReportSubmission>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .6),
    builder: (_) => _ReportDialog(senderName: senderName),
  );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.senderName});

  final String senderName;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  ReportReason? _reason;
  final TextEditingController _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _note.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining =
        ReportService.maxNoteLength - _note.text.characters.length;

    return Dialog(
      backgroundColor: const Color(0xFF120C1D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF2E2140)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Report ${widget.senderName}’s message',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Our team reviews reports. Pick the closest reason.',
                style: TextStyle(color: Color(0xFF9A90AC), fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final reason in ReportReason.values)
                    _ReasonChip(
                      label: reportReasonLabel(reason),
                      selected: _reason == reason,
                      onTap: () => setState(() => _reason = reason),
                    ),
                ],
              ),
              // The note only earns its space once a reason is chosen —
              // it is context for that reason, not a second question.
              if (_reason != null) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _note,
                  maxLength: ReportService.maxNoteLength,
                  maxLines: 3,
                  minLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Anything else we should know? (optional)',
                    hintStyle: const TextStyle(
                      color: Color(0xFF7E7895),
                      fontSize: 12.5,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: .03),
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF2E2140)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF2E2140)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: AppColors.primary.withValues(alpha: .6),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$remaining left',
                    style: TextStyle(
                      color: remaining < 40
                          ? const Color(0xFFFF7A93)
                          : const Color(0xFF7E7895),
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Color(0xFF9A90AC),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    // Disabled until a reason is picked — the dialog
                    // cannot return an unreasoned report.
                    onPressed: _reason == null
                        ? null
                        : () => Navigator.of(context).pop(
                            ReportSubmission(
                              reason: _reason!,
                              note: _note.text.trim(),
                            ),
                          ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: Colors.white.withValues(
                        alpha: .06,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Send report',
                      style: TextStyle(
                        color: _reason == null
                            ? const Color(0xFF564C63)
                            : Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected
                ? AppColors.primary.withValues(alpha: .22)
                : Colors.white.withValues(alpha: .03),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: .6)
                  : const Color(0xFF2E2140),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFFB3A8C4),
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
