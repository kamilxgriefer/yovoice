import 'package:flutter/material.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_palette.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_reason_labels.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';
import 'package:yovoice/shared/widgets/overlays/yo_modal_sheet_chrome.dart';

/// Asks the reporter which of the eight reasons applies, and returns it.
///
/// WHY A PICKER AND NOT A FIXED REASON. Both report paths store a
/// `reason`, and both are read by a human triaging a queue. A client that
/// always sends the same value does not merely lose detail — it actively
/// poisons the field, because a moderator who sees `harassment` on
/// something that is plainly a scam link learns that the label carries no
/// information and starts ignoring it on the reports where it was
/// accurate. The reason also carries the response time: `selfHarm` is a
/// welfare escalation and `spam` is a volume problem, and a queue that
/// cannot tell them apart makes the welfare case wait behind the spam.
/// Repeat-offender detection has the same dependency — five
/// `impersonation` reports on one account from five different reporters
/// is a very different signal from five mixed ones.
///
/// The counter-argument is real and shaped the design: friction on a
/// safety path suppresses reports, and a person being harassed should not
/// have to fill in a form. So this is one sheet, one tap, no free text,
/// no mandatory confirmation step afterwards, and it is dismissible at
/// any point.
///
/// Returns the chosen reason, or null if the reporter backed out.
Future<ReportReason?> showReportReasonSheet({
  required BuildContext context,
  required String title,
  required String subtitle,
}) {
  return showModalBottomSheet<ReportReason>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    showDragHandle: false,
    constraints: ResponsiveContentFrame.adaptiveModalConstraints(
      context,
      maxWidth: 520,
    ),
    builder: (sheetContext) =>
        ReportReasonSheet(title: title, subtitle: subtitle),
  );
}

/// The picker itself, separated from [showReportReasonSheet] so it can be
/// pumped directly in a widget test without a route.
class ReportReasonSheet extends StatelessWidget {
  const ReportReasonSheet({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final media = MediaQuery.of(context);
    final palette = context.appPalette;

    return Container(
      key: const ValueKey('report-reason-sheet'),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: palette.border)),
      ),
      // The list is the only thing allowed to grow. Capped at 82% of the
      // height so the sheet never becomes a full-screen page on a short
      // phone in landscape, and so the grab handle and title stay on
      // screen while the reasons scroll under them.
      constraints: BoxConstraints(maxHeight: media.size.height * 0.82),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            YoModalSheetChrome(
              sheetLabel: copy.text('report reason', 'powód zgłoszenia'),
              surfaceColor: palette.surface,
              handleColor: palette.borderStrong,
              closeColor: palette.textSecondary,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      title,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: palette.border, height: 20),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.only(bottom: 12 + media.padding.bottom),
                children: [
                  for (final reason in ReportReason.values)
                    _ReportReasonTile(
                      key: ValueKey('report-reason-${reason.name}'),
                      reason: reason,
                      onTap: () => Navigator.of(context).pop(reason),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Self-harm is deliberately the one reason drawn in a different
  /// colour. It is the only entry in this list that can be a welfare
  /// emergency rather than a rule violation, and making it visually
  /// distinct is how a distressed reporter finds it without reading all
  /// eight.
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

class _ReportReasonTile extends StatefulWidget {
  const _ReportReasonTile({
    required this.reason,
    required this.onTap,
    super.key,
  });

  final ReportReason reason;
  final VoidCallback onTap;

  @override
  State<_ReportReasonTile> createState() => _ReportReasonTileState();
}

class _ReportReasonTileState extends State<_ReportReasonTile> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'Report reason ${widget.reason.name}',
  )..addListener(_handleFocusChange);
  bool _focused = false;

  void _handleFocusChange() {
    if (mounted && _focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context);
    final palette = context.appPalette;
    final reason = widget.reason;
    return AnimatedContainer(
      key: ValueKey('report-reason-focus-${reason.name}'),
      duration: const Duration(milliseconds: 120),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focused ? palette.focus : Colors.transparent,
          width: 2,
        ),
      ),
      child: ListTile(
        focusNode: _focusNode,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        focusColor: palette.focus.withValues(alpha: .12),
        onTap: widget.onTap,
        leading: Icon(
          ReportReasonSheet._iconFor(reason),
          color: reason == ReportReason.selfHarm
              ? palette.dangerForeground
              : palette.textSecondary,
        ),
        title: Text(
          reportReasonLabel(reason, copy: copy),
          style: TextStyle(color: palette.textPrimary, fontSize: 15),
        ),
      ),
    );
  }
}
