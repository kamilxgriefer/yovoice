import 'package:yovoice/features/rooms/data/models/voice_room.dart';

/// WHO may turn a dormant room's voice session on.
///
/// This is a CLIENT MIRROR of the deployed `firestore.rules`, and it exists
/// so the app never offers a control the server will refuse. The rule set
/// splits on `resource.data.hostId == request.auth.uid` with a ternary, so
/// the two branches are genuinely separate authorities:
///
/// * `hostRoomUpdateAllowed()`'s `start` branch — the room's own host may
///   flip `isLive` false -> true on an active room, changing nothing but
///   `isLive`, `endedAt` and `updatedAt`.
/// * `roomVoiceStartAllowed()` — a NON-host may do the same when either the
///   room carries a non-empty `clubId` and the caller is an active member of
///   that Club (`isActiveClubRoomMember`), or the room sets
///   `membersCanStartVoice: true` and the caller holds a `roomMembers` row
///   (`isRoomMember`).
///
/// Every legacy-tolerant default matches the rules' own `.get(field, default)`
/// reads: a document with no `membersCanStartVoice`, no `roomType` and no
/// `experience` resolves to "host only", which is exactly what the server
/// would decide for it.
enum RoomVoiceStartAuthority {
  /// The room's host. Mirrors `hostRoomUpdateAllowed()`'s `start` branch.
  host,

  /// An active member of the Club that owns this lounge. Mirrors
  /// `roomVoiceStartAllowed()`'s `clubId` branch.
  clubMember,

  /// A `roomMembers` holder in a room whose host enabled
  /// `membersCanStartVoice`. Mirrors `roomVoiceStartAllowed()`'s second
  /// branch.
  roomMember,

  /// Nobody the server would accept. The UI must not offer a start control.
  none;

  bool get canStart => this != RoomVoiceStartAuthority.none;

  /// Honest, product-voice copy for someone who cannot start voice here.
  /// Never a permission code, never a dead control.
  String get waitingExplanation => switch (this) {
    RoomVoiceStartAuthority.host ||
    RoomVoiceStartAuthority.clubMember ||
    RoomVoiceStartAuthority.roomMember => 'Tap to start the voice session.',
    RoomVoiceStartAuthority.none =>
      'Voice has not started here yet — the host opens the mics.',
  };
}

/// What actually happened when a room was entered.
enum RoomVoiceEntryOutcome {
  /// Voice was already live and the caller is on the roster.
  live,

  /// Voice was dormant and this entry turned it on.
  started,

  /// Dormant, and the caller holds no authority to start it. Not an error —
  /// the room is fine, it simply has no voice session yet.
  dormant,

  /// Closed, archived, suspended, or mid-deletion. Voice cannot exist.
  unavailable,

  /// A transient failure (network, contention, a refused write). Retrying is
  /// reasonable and the UI offers exactly that.
  failed,
}

/// The resolved answer the room screens render from.
///
/// Produced BEFORE any LiveKit token is requested. `createLiveKitToken`
/// (functions/livekit/token.js) refuses a token unless the room document says
/// `status == 'active' && isLive == true`, so asking for one first is a
/// guaranteed "This room is not currently live." — which is the defect this
/// type exists to make unrepresentable.
class RoomVoiceEntry {
  const RoomVoiceEntry({
    required this.outcome,
    required this.room,
    required this.authority,
    this.message,
  });

  /// The state a screen assumes before any resolution has run: no authority,
  /// liveness taken from the document it was handed.
  factory RoomVoiceEntry.unresolved(VoiceRoom room) => RoomVoiceEntry(
    outcome: room.isLive
        ? RoomVoiceEntryOutcome.live
        : RoomVoiceEntryOutcome.dormant,
    room: room,
    authority: RoomVoiceStartAuthority.none,
  );

  final RoomVoiceEntryOutcome outcome;

  /// The room as the SERVER last described it, not the possibly stale
  /// document the caller navigated with.
  final VoiceRoom room;
  final RoomVoiceStartAuthority authority;

  /// Product copy explaining a non-live outcome. Never a raw error string.
  final String? message;

  /// True only when a LiveKit token may legitimately be requested.
  bool get voiceIsLive =>
      outcome == RoomVoiceEntryOutcome.live ||
      outcome == RoomVoiceEntryOutcome.started;

  /// True only when the deployed rules would accept a start from this
  /// account. The UI offers a start control on exactly this condition.
  bool get canStartVoice =>
      authority.canStart &&
      (outcome == RoomVoiceEntryOutcome.dormant ||
          outcome == RoomVoiceEntryOutcome.failed);

  RoomVoiceEntry copyWith({
    RoomVoiceEntryOutcome? outcome,
    VoiceRoom? room,
    RoomVoiceStartAuthority? authority,
    String? message,
  }) {
    return RoomVoiceEntry(
      outcome: outcome ?? this.outcome,
      room: room ?? this.room,
      authority: authority ?? this.authority,
      message: message ?? this.message,
    );
  }
}
