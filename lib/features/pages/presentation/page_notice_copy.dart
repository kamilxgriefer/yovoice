import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/pages/presentation/page_delete_copy.dart';
import 'package:yovoice/features/pages/presentation/pages_copy.dart';

/// The Page notices in the notification centre (spec premium-pages §2.8,
/// §2.10, R12): `pageModeration`, the statement of reasons for a staff
/// action, and `pageLapse`, the Day 0 / Day 23 notices and (ADR-236) the
/// "deleted in 3 days" reminder of a pending Page deletion.
///
/// The server writes an English `targetLabel` (builds 36-38 show it as a
/// system row); this client composes the line in the reader's language
/// from the row's `moderationAction`, `moderationReason` and `lapsePhase`,
/// and falls back to the server's label for anything it does not know.
class PageNoticeCopy {
  const PageNoticeCopy(this.copy);

  final AppLocalizations copy;

  String moderation(AppNotification row) {
    final action = switch (row.moderationAction) {
      'postRemoved' => copy.text(
        'Your Page post was removed',
        'Twój post na stronie został usunięty',
      ),
      'postHeld' => copy.text(
        'Your Page post is hidden while we review it',
        'Twój post na stronie jest ukryty do czasu weryfikacji',
      ),
      'postRestored' => copy.text(
        'Your Page post is visible again',
        'Twój post na stronie jest znów widoczny',
      ),
      'commentRemoved' => copy.text(
        'Your comment on a Page was removed',
        'Twój komentarz na stronie został usunięty',
      ),
      'pageSuspended' => copy.text(
        'Your Page was suspended',
        'Twoja strona została zawieszona',
      ),
      'pageSuspensionLifted' => copy.text(
        'Your Page is no longer suspended',
        'Twoja strona nie jest już zawieszona',
      ),
      _ => null,
    };
    if (action == null) {
      final label = row.targetLabel?.trim();
      return label == null || label.isEmpty
          ? copy.text(
              'A moderator took action on your Page',
              'Moderator wykonał działanie dotyczące Twojej strony',
            )
          : label;
    }
    final withReason =
        row.moderationAction != 'postRestored' &&
        row.moderationAction != 'pageSuspensionLifted';
    final reason = withReason ? reasonLabel(row.moderationReason) : null;
    if (reason == null) return action;
    return copy.template(
      '{action}: {reason}',
      '{action}: {reason}',
      values: <String, Object>{'action': action, 'reason': reason},
    );
  }

  String lapse(AppNotification row) => switch (row.lapsePhase) {
    'readOnly' => copy.text(
      'Your Page is read-only because YO Voice VIP ended. Nothing is deleted.',
      'Twoja strona jest tylko do odczytu, bo skończył się YO Voice VIP. Nic nie zostało usunięte.',
    ),
    'hidingSoon' => copy.text(
      'Your Page will be hidden in 7 days. Nothing is deleted; it returns with VIP.',
      'Twoja strona zostanie ukryta za 7 dni. Nic nie zostanie usunięte; wróci razem z VIP.',
    ),
    // ADR-236: 3 days before a Page its owner asked to delete is removed.
    'deletionSoon' => PagesCopy(copy).deletionSoonNotice,
    _ =>
      row.targetLabel?.trim().isNotEmpty == true
          ? row.targetLabel!.trim()
          : copy.text('Your Page changed', 'Twoja strona się zmieniła'),
  };

  /// The report reasons of `report_contract.js` (PAGE_REASON_LABELS).
  String? reasonLabel(String? reason) => switch (reason) {
    'spam' => copy.contextualText('pages.reason.spam', 'spam', 'spam'),
    'harassment' => copy.contextualText(
      'pages.reason.harassment',
      'harassment',
      'nękanie',
    ),
    'hate' => copy.contextualText(
      'pages.reason.hate',
      'hate speech',
      'mowa nienawiści',
    ),
    'sexual' => copy.contextualText(
      'pages.reason.sexual',
      'sexual content',
      'treści seksualne',
    ),
    'violence' => copy.contextualText(
      'pages.reason.violence',
      'violence',
      'przemoc',
    ),
    'selfHarm' => copy.contextualText(
      'pages.reason.selfHarm',
      'self-harm',
      'samookaleczenia',
    ),
    'impersonation' => copy.contextualText(
      'pages.reason.impersonation',
      'impersonation',
      'podszywanie się',
    ),
    'restrictedCategory' => copy.contextualText(
      'pages.reason.restrictedCategory',
      'restricted category',
      'niedozwolona kategoria',
    ),
    'scam' => copy.contextualText(
      'pages.reason.scam',
      'scam or fraud',
      'oszustwo',
    ),
    'intellectualProperty' => copy.contextualText(
      'pages.reason.intellectualProperty',
      'intellectual property',
      'własność intelektualna',
    ),
    'other' => copy.contextualText(
      'pages.reason.other',
      'breaking the rules',
      'naruszenie zasad',
    ),
    _ => null,
  };
}
