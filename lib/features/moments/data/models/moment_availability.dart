/// How long a Voice Moment stays live — the operator-chosen availability
/// contract that amends ADR-101's fixed 24 hours.
///
/// The values mirror `finalizeMomentDraft`'s SERVER-SIDE whitelist
/// exactly: 24, 72, 168 or 720 hours, or the literal string
/// `'permanent'`. The client never computes an `expiresAt` from these
/// (the create rule bans the field on client writes); it only names the
/// choice and lets the server stamp or omit the deadline.
enum MomentAvailability {
  hours24('24 hours', 24),
  days3('3 days', 72),
  days7('7 days', 168),
  days30('30 days', 720),
  permanent('Keep until deleted', null);

  const MomentAvailability(this.label, this.hours);

  /// The exact selector copy.
  final String label;

  /// Whitelisted hour count, or null for [permanent].
  final int? hours;

  /// Today's behaviour: absent (or 24) means a 24-hour Moment.
  static const MomentAvailability fallback = MomentAvailability.hours24;

  /// What goes into the callable's `availabilityHours` field: the hour
  /// count for timed choices, the literal `'permanent'` otherwise.
  Object get wireValue => hours ?? 'permanent';

  /// Whether the field can be omitted entirely: the server defaults an
  /// absent `availabilityHours` to 24, so the default choice sends
  /// nothing — indistinguishable from every pre-availability client.
  bool get isServerDefault => this == MomentAvailability.hours24;
}
