/// How long a Voice Moment remains visible in the feed.
///
/// Timed Moments accept every whole-hour value from [minimumHours] through
/// [maximumHours], while [permanent] remains visible until its author deletes
/// it. The client never computes `expiresAt`; it only sends this value and the
/// server owns the timestamp.
final class MomentAvailability {
  const MomentAvailability._(this.hours);

  /// The shortest selectable lifetime.
  static const int minimumHours = 24;

  /// The longest selectable lifetime (30 days).
  static const int maximumHours = 720;

  /// Today's behaviour. It is omitted on the wire so old and new clients
  /// produce the same default request.
  static const MomentAvailability fallback = MomentAvailability._(24);
  static const MomentAvailability hours24 = fallback;

  /// No automatic expiry. The author can still delete the Moment.
  static const MomentAvailability permanent = MomentAvailability._(null);

  /// Creates a timed availability from a whole number of hours.
  factory MomentAvailability.timedHours(int hours) {
    if (hours < minimumHours || hours > maximumHours) {
      throw RangeError.range(
        hours,
        minimumHours,
        maximumHours,
        'hours',
        'Voice Moment availability must be between $minimumHours and '
            '$maximumHours hours.',
      );
    }
    return MomentAvailability._(hours);
  }

  /// Whole hours for a timed Moment, or `null` for [permanent].
  final int? hours;

  bool get isPermanent => hours == null;

  /// What goes into `finalizeMomentDraft.availabilityHours`.
  Object get wireValue => hours ?? 'permanent';

  /// An absent field means 24 hours server-side.
  bool get isServerDefault => hours == fallback.hours;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MomentAvailability && other.hours == hours;

  @override
  int get hashCode => hours.hashCode;

  @override
  String toString() => isPermanent
      ? 'MomentAvailability.permanent'
      : 'MomentAvailability.timedHours($hours)';
}
