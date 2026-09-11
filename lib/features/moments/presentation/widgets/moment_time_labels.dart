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
    return _template(copy, '{count}m ago', '{count} min temu', diff.inMinutes);
  }
  if (diff.inHours < 24) {
    return _template(copy, '{count}h ago', '{count} godz. temu', diff.inHours);
  }
  final days = diff.inDays;
  return _template(
    copy,
    '{count}d ago',
    days == 1 ? '{count} dzień temu' : '{count} dni temu',
    days,
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
    return _template(
      copy,
      'Expires in {count}d',
      days == 1 ? 'Wygasa za {count} dzień' : 'Wygasa za {count} dni',
      days,
    );
  }
  if (remaining.inHours >= 1) {
    return _template(
      copy,
      'Expires in {count}h',
      'Wygasa za {count} godz.',
      remaining.inHours,
    );
  }
  if (remaining.inMinutes >= 1) {
    return _template(
      copy,
      'Expires in {count}m',
      'Wygasa za {count} min',
      remaining.inMinutes,
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

String _template(
  AppLocalizations? copy,
  String english,
  String polish,
  int count,
) =>
    copy?.template(english, polish, values: {'count': count}) ??
    english.replaceAll('{count}', count.toString());
