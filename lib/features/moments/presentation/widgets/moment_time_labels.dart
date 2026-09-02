/// Shared, honest time copy for Voice Moment surfaces.
///
/// Both labels are derived from the document's real timestamps and from
/// nothing else. When the fact is unknown (`null` createdAt) the label is
/// empty rather than an invented value. A `null` expiresAt is not
/// unknown — it means PERMANENT under the amended availability contract
/// (see `VoiceMoment.expiresAt`) — so [momentExpiryLabel] stays silent
/// for it (nothing is expiring) and [momentAvailabilityLabel] names the
/// fact on the author's own surfaces.
library;

import 'package:yovoice/core/localization/app_localizations.dart';

/// "now", "5m ago", "2h ago", "1d ago" — from the real `createdAt`.
String momentRelativeAge(
  DateTime? createdAt, {
  DateTime? now,
  AppLocalizations? copy,
}) {
  if (createdAt == null) return '';
  final diff = (now ?? DateTime.now()).difference(createdAt);
  if (diff.inMinutes < 1) return _text(copy, 'now', 'teraz');
  if (diff.inMinutes < 60) {
    return _text(copy, '${diff.inMinutes}m ago', '${diff.inMinutes} min temu');
  }
  if (diff.inHours < 24) {
    return _text(copy, '${diff.inHours}h ago', '${diff.inHours} godz. temu');
  }
  final days = diff.inDays;
  return _text(
    copy,
    '${days}d ago',
    days == 1 ? '1 dzień temu' : '$days dni temu',
  );
}

/// "Expires in 12d" / "Expires in 8h" / "Expires in 42m" /
/// "Expires soon" — from the real `expiresAt`. Returns `null` when there
/// is nothing honest to print: no `expiresAt` on the document (a
/// PERMANENT Moment never expires, so no countdown belongs anywhere), or
/// the deadline already passed (such a Moment should have been filtered
/// before rendering at all).
///
/// Days appear from 48 hours up: the 7- and 30-day availability choices
/// made "Expires in 719h" a real string, and nobody counts hours in the
/// hundreds.
String? momentExpiryLabel(
  DateTime? expiresAt, {
  DateTime? now,
  AppLocalizations? copy,
}) {
  if (expiresAt == null) return null;
  final remaining = expiresAt.difference(now ?? DateTime.now());
  if (remaining.isNegative) return null;
  if (remaining.inHours >= 48) {
    final days = remaining.inDays;
    return _text(
      copy,
      'Expires in ${days}d',
      days == 1 ? 'Wygasa za 1 dzień' : 'Wygasa za $days dni',
    );
  }
  if (remaining.inHours >= 1) {
    return _text(
      copy,
      'Expires in ${remaining.inHours}h',
      'Wygasa za ${remaining.inHours} godz.',
    );
  }
  if (remaining.inMinutes >= 1) {
    return _text(
      copy,
      'Expires in ${remaining.inMinutes}m',
      'Wygasa za ${remaining.inMinutes} min',
    );
  }
  return _text(copy, 'Expires soon', 'Wkrótce wygaśnie');
}

/// The availability line an AUTHOR sees on their own Moment: the real
/// countdown when a deadline exists, or "Stays until deleted" for a
/// permanent Moment. Returns `null` only when a deadline exists but has
/// already passed — the same "should have been filtered" case as
/// [momentExpiryLabel].
String? momentAvailabilityLabel(
  DateTime? expiresAt, {
  DateTime? now,
  AppLocalizations? copy,
}) {
  if (expiresAt == null) {
    return _text(copy, 'Stays until deleted', 'Dostępny do usunięcia');
  }
  return momentExpiryLabel(expiresAt, now: now, copy: copy);
}

String _text(AppLocalizations? copy, String english, String polish) =>
    copy?.text(english, polish) ?? english;
