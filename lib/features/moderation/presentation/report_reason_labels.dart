import 'package:yovoice/features/moderation/data/services/report_service.dart';

/// User-facing label for each reason accepted by the reports contract.
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
