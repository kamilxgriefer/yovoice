import 'package:flutter/material.dart';

import 'package:yovoice/core/theme/app_colors.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';
import 'package:yovoice/features/moderation/presentation/report_reason_labels.dart';
import 'package:yovoice/shared/widgets/layout/responsive_content_frame.dart';

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
    final media = MediaQuery.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
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
            const SizedBox(height: 12),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
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
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.divider, height: 20),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.only(
                  bottom: 12 + media.padding.bottom,
                ),
                children: [
                  for (final reason in ReportReason.values)
                    ListTile(
                      key: ValueKey('report-reason-${reason.name}'),
                      onTap: () => Navigator.of(context).pop(reason),
                      leading: Icon(
                        _iconFor(reason),
                        color: reason == ReportReason.selfHarm
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                      title: Text(
                        reportReasonLabel(reason),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
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
