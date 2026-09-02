import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/moderation/data/services/report_service.dart';

/// User-facing label for each reason accepted by the reports contract.
String reportReasonLabel(ReportReason reason, {AppLocalizations? copy}) {
  final english = switch (reason) {
    ReportReason.spam => 'Spam or scam',
    ReportReason.harassment => 'Harassment or bullying',
    ReportReason.hate => 'Hate speech',
    ReportReason.sexual => 'Sexual content',
    ReportReason.violence => 'Violence or threats',
    ReportReason.selfHarm => 'Self-harm',
    ReportReason.impersonation => 'Impersonation',
    ReportReason.other => 'Something else',
  };
  final polish = switch (reason) {
    ReportReason.spam => 'Spam lub oszustwo',
    ReportReason.harassment => 'Nękanie lub zastraszanie',
    ReportReason.hate => 'Mowa nienawiści',
    ReportReason.sexual => 'Treści seksualne',
    ReportReason.violence => 'Przemoc lub groźby',
    ReportReason.selfHarm => 'Samookaleczenie',
    ReportReason.impersonation => 'Podszywanie się pod inną osobę',
    ReportReason.other => 'Inny powód',
  };
  return copy?.text(english, polish) ?? english;
}
