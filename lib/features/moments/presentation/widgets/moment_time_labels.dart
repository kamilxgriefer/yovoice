/// Shared, honest time copy for Voice Moment surfaces.
///
/// Both labels are derived from the document's real timestamps and from
/// nothing else. When the fact is unknown (`null` createdAt, no
/// `expiresAt`) the label is empty/null rather than an invented value.
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

/// "Expires in 8h" / "Expires in 42m" / "Expires soon" — from the real
/// `expiresAt`. Returns `null` when there is nothing honest to print:
/// no `expiresAt` on the document, or the deadline already passed (such a
/// Moment should have been filtered before rendering at all).
String? momentExpiryLabel(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) return null;
  final remaining = expiresAt.difference(now ?? DateTime.now());
  if (remaining.isNegative) return null;
  if (remaining.inHours >= 1) return 'Expires in ${remaining.inHours}h';
  if (remaining.inMinutes >= 1) return 'Expires in ${remaining.inMinutes}m';
  return 'Expires soon';
}
