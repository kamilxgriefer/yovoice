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

/// "now", "5m ago", "2h ago", "1d ago" — from the real `createdAt`.
String momentRelativeAge(DateTime? createdAt, {DateTime? now}) {
  if (createdAt == null) return '';
  final diff = (now ?? DateTime.now()).difference(createdAt);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
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
String? momentExpiryLabel(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) return null;
  final remaining = expiresAt.difference(now ?? DateTime.now());
  if (remaining.isNegative) return null;
  if (remaining.inHours >= 48) return 'Expires in ${remaining.inDays}d';
  if (remaining.inHours >= 1) return 'Expires in ${remaining.inHours}h';
  if (remaining.inMinutes >= 1) return 'Expires in ${remaining.inMinutes}m';
  return 'Expires soon';
}

/// The availability line an AUTHOR sees on their own Moment: the real
/// countdown when a deadline exists, or "Stays until deleted" for a
/// permanent Moment. Returns `null` only when a deadline exists but has
/// already passed — the same "should have been filtered" case as
/// [momentExpiryLabel].
String? momentAvailabilityLabel(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) return 'Stays until deleted';
  return momentExpiryLabel(expiresAt, now: now);
}
