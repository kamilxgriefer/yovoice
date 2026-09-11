import 'package:flutter/foundation.dart';

/// Where one queued attachment currently is on its way to the server.
///
/// Deliberately coarse: every value is something a person can be told without
/// being lied to. There is no "sent" — a delivered attachment stops being a
/// queued entry at all, and the canonical message takes its place.
enum DirectAttachmentDeliveryStage {
  /// Reading the durable copy and getting ready to ask for a reservation.
  preparing,

  /// Waiting on `reserveDirectMessageAttachment`.
  reserving,

  /// Bytes are moving to Storage. This is the only stage with a real ratio.
  uploading,

  /// Waiting on `finalizeDirectMessageAttachment` to publish the message.
  finalizing,
}

@immutable
class DirectAttachmentDeliveryState {
  const DirectAttachmentDeliveryState({required this.stage, this.progress});

  final DirectAttachmentDeliveryStage stage;

  /// 0..1 while [stage] is [DirectAttachmentDeliveryStage.uploading] and
  /// Storage reported a total; null whenever a fraction would be invented.
  final double? progress;

  @override
  bool operator ==(Object other) =>
      other is DirectAttachmentDeliveryState &&
      other.stage == stage &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(stage, progress);
}

/// Live, in-memory delivery phase for each attachment being sent right now.
///
/// IN MEMORY ON PURPOSE. The durable outbox manifest stays at
/// `schemaVersion: 3` and keeps describing only what survives a restart:
/// which attachment, which reservation, which idempotency ids, how many
/// attempts. Upload progress survives nothing — Firebase Storage `putFile`
/// does not resume a partial object across process death, so a relaunched
/// entry genuinely starts its upload from zero. Persisting a percentage would
/// therefore persist a false claim, and the UI's honest reading of "no live
/// state" is "not currently uploading".
class DirectAttachmentDeliveryProgress
    extends ValueNotifier<Map<String, DirectAttachmentDeliveryState>> {
  DirectAttachmentDeliveryProgress()
    : super(const <String, DirectAttachmentDeliveryState>{});

  DirectAttachmentDeliveryState? stateFor(String entryId) => value[entryId];

  void report(
    String entryId,
    DirectAttachmentDeliveryStage stage, {
    double? progress,
  }) {
    final next = DirectAttachmentDeliveryState(
      stage: stage,
      // Whole percent. Storage emits a snapshot per chunk; rebuilding a card
      // for a change nobody can see is pure jank.
      progress: progress == null
          ? null
          : (progress.clamp(0.0, 1.0) * 100).roundToDouble() / 100,
    );
    if (value[entryId] == next) return;
    value = <String, DirectAttachmentDeliveryState>{...value, entryId: next};
  }

  void clear(String entryId) {
    if (!value.containsKey(entryId)) return;
    value = <String, DirectAttachmentDeliveryState>{...value}..remove(entryId);
  }
}
