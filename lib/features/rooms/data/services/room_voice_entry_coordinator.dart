import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:cloud_functions/cloud_functions.dart';

import 'package:yovoice/features/rooms/data/models/room_voice_access.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

/// The single ordered path from "a room was tapped" to "live audio may be
/// requested", shared by every room type — Community, Broadcast, Club Lounge
/// and Family Room.
///
/// WHY THIS EXISTS. `createLiveKitToken` (functions/livekit/token.js) refuses
/// a voice token unless the room document says
/// `status == 'active' && isLive == true`, and refuses again unless the
/// caller already holds a participant row. Nothing in the app performed
/// either transition for an ordinary room: `RoomService.startCommunityVoice`
/// had no callers at all, and `enterClubLounge` — the one path that did it —
/// was reachable only from the Club overview. Every other entry point (Home,
/// Discover, notifications, profile, the mini bar, and creating a room)
/// pushed straight into a room screen that asked for a token immediately, so
/// a persistent room's own host pressed unmute and was told "This room is not
/// currently live." Home's room board even labels the button "Start" for a
/// dormant room; nothing started anything.
///
/// ORDER IS THE WHOLE POINT. Liveness first, roster second, token third.
/// `joinRoom` refuses a room whose `isLive` is not true, and the token
/// function refuses both a dormant room and a caller with no participant row,
/// so any other order is a guaranteed, user-visible failure.
///
/// ENTERING IS THE START. A room screen has no lobby (that detour was removed
/// deliberately) — it renders a stage, a live status line and a microphone the
/// moment it opens, and Home already advertises a dormant room's entry button
/// as "Start". Making the start a second, separate tap on a screen that
/// already looks live is the mismatch this fix is about, so entry performs
/// the transition for anyone the deployed rules would accept and for nobody
/// else. Someone with no such authority is never shown a start control; they
/// get an honest dormant state instead.
class RoomVoiceEntryCoordinator {
  RoomVoiceEntryCoordinator({
    required Future<VoiceRoom> Function(String roomId) readRoom,
    required Future<RoomVoiceStartAuthority> Function(VoiceRoom room)
    resolveAuthority,
    required Future<void> Function(String roomId) startVoice,
    required Future<VoiceRoom> Function(String roomId) joinRoom,
  }) : _readRoom = readRoom,
       _resolveAuthority = resolveAuthority,
       _startVoice = startVoice,
       _joinRoom = joinRoom;

  /// The production wiring. Constructed lazily so that merely importing this
  /// file cannot touch Firebase — the room screens are reachable from widget
  /// tests that have no Firebase app.
  factory RoomVoiceEntryCoordinator.production({RoomService? rooms}) {
    final service = rooms ?? RoomService();
    return RoomVoiceEntryCoordinator(
      readRoom: service.getRoom,
      resolveAuthority: service.resolveVoiceStartAuthority,
      startVoice: service.startRoomVoice,
      joinRoom: service.joinRoom,
    );
  }

  final Future<VoiceRoom> Function(String roomId) _readRoom;
  final Future<RoomVoiceStartAuthority> Function(VoiceRoom room)
  _resolveAuthority;
  final Future<void> Function(String roomId) _startVoice;
  final Future<VoiceRoom> Function(String roomId) _joinRoom;

  /// Resolves [room] into the state the screens render from, performing the
  /// liveness transition when — and only when — this account may.
  Future<RoomVoiceEntry> enter(VoiceRoom room) async {
    // The caller's copy can be arbitrarily stale: Home hands over a document
    // from a cached list, a notification hands over one fetched minutes ago,
    // and `isLive` is exactly the field most likely to have moved. A refresh
    // that fails is not fatal — fall back to what we were given rather than
    // blocking entry on a transient read.
    var current = room;
    try {
      current = await _readRoom(room.id);
    } catch (_) {
      current = room;
    }

    if (!current.isActive || current.deletionInProgress) {
      return RoomVoiceEntry(
        outcome: RoomVoiceEntryOutcome.unavailable,
        room: current,
        authority: RoomVoiceStartAuthority.none,
        message: current.deletionInProgress
            ? 'This room is being deleted.'
            : 'This room has ended.',
      );
    }

    if (current.isLive) {
      return _joinLive(current, RoomVoiceEntryOutcome.live);
    }

    final RoomVoiceStartAuthority authority;
    try {
      authority = await _resolveAuthority(current);
    } catch (error) {
      return RoomVoiceEntry(
        outcome: RoomVoiceEntryOutcome.failed,
        room: current,
        authority: RoomVoiceStartAuthority.none,
        message: _friendly(error, 'Could not check this room. Try again.'),
      );
    }

    if (!authority.canStart) {
      return RoomVoiceEntry(
        outcome: RoomVoiceEntryOutcome.dormant,
        room: current,
        authority: authority,
        message: authority.waitingExplanation,
      );
    }

    try {
      await _startVoice(current.id);
    } catch (error) {
      // The affordance stays available: this account genuinely holds the
      // authority, the write simply did not land. `canStartVoice` is true on
      // a failed outcome for exactly this reason.
      return RoomVoiceEntry(
        outcome: RoomVoiceEntryOutcome.failed,
        room: current,
        authority: authority,
        message: _friendly(error, 'Could not start voice. Try again.'),
      );
    }

    return _joinLive(
      current.withLiveness(true),
      RoomVoiceEntryOutcome.started,
      authority: authority,
    );
  }

  Future<RoomVoiceEntry> _joinLive(
    VoiceRoom room,
    RoomVoiceEntryOutcome outcome, {
    RoomVoiceStartAuthority authority = RoomVoiceStartAuthority.none,
  }) async {
    try {
      final joined = await _joinRoom(room.id);
      return RoomVoiceEntry(
        outcome: outcome,
        room: joined,
        authority: authority,
      );
    } catch (error) {
      // Without a participant row the token function refuses with
      // "You must join this room before requesting voice access." — so a
      // failed join has to stop the flow here rather than let the room
      // screen discover it as an audio error.
      return RoomVoiceEntry(
        outcome: RoomVoiceEntryOutcome.failed,
        room: room,
        authority: authority,
        message: _friendly(error, 'Could not join this room. Try again.'),
      );
    }
  }

  /// Server refusals carry product copy in `.message`; the
  /// "[firebase_functions/…]" and "Bad state: " prefixes are developer noise
  /// and must never reach a person.
  ///
  /// This is the delivery vehicle for EVERY failure on the entry path — the
  /// room screen now announces the message on arrival, not only when the
  /// control is tapped — so anything falling through to `toString()` is
  /// shown to the user verbatim.
  static String _friendly(Object error, String fallback) {
    if (error is FirebaseFunctionsException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) return message;
      return fallback;
    }
    // Ordered AFTER the callable branch on purpose: FirebaseFunctionsException
    // IS a FirebaseException, and its `.message` carries real product copy
    // while a raw Firestore one carries "[cloud_firestore/permission-denied]
    // The caller does not have permission…". Map the code instead.
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' =>
          'You do not have access to this room right now.',
        'not-found' => 'This room no longer exists.',
        'unavailable' || 'deadline-exceeded' || 'network-request-failed' =>
          'You appear to be offline. Check your connection and try again.',
        'resource-exhausted' => 'Voice is busy right now. Try again shortly.',
        'unauthenticated' => 'Please sign in again to join this room.',
        'aborted' || 'failed-precondition' =>
          'The room changed while you were joining. Try again.',
        'cancelled' => fallback,
        _ => fallback,
      };
    }
    if (error is StateError) {
      final message = error.message.trim();
      if (message.isNotEmpty) return message;
    }
    final text = error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '')
        .trim();
    return text.isEmpty ? fallback : text;
  }
}
