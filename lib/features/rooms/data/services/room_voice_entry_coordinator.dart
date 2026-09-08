import 'dart:async' show TimeoutException;

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
/// either transition consistently for an ordinary room. Entry points used to
/// push straight into a room screen that asked for a token immediately, so a
/// persistent room's own host could press unmute and be told "This room is not
/// currently live."
///
/// ORDER IS THE WHOLE POINT. Liveness first, roster second, token third.
/// `joinRoom` refuses a room whose `isLive` is not true, and the token
/// function refuses both a dormant room and a caller with no participant row,
/// so any other order is a guaranteed, user-visible failure.
///
/// CONSENT IS THE BOUNDARY. Navigation only opens RoomEntryScreen's passive
/// preview. That screen invokes this coordinator after the explicit Join CTA;
/// constructing the screen never starts voice or creates a roster row. Once
/// invoked, [enter] performs the transition for anyone the deployed rules
/// accept and for nobody else. Someone with no such authority gets an honest
/// dormant state instead.
class RoomVoiceEntryCoordinator {
  RoomVoiceEntryCoordinator({
    required Future<VoiceRoom> Function(String roomId) readRoom,
    required Future<RoomVoiceStartAuthority> Function(VoiceRoom room)
    resolveAuthority,
    required Future<void> Function(String roomId) startVoice,
    required Future<VoiceRoom> Function(String roomId, {bool startMuted})
    joinRoom,
    String Function()? currentUserId,
  }) : _readRoom = readRoom,
       _resolveAuthority = resolveAuthority,
       _startVoice = startVoice,
       _joinRoom = joinRoom,
       _currentUserId = currentUserId;

  /// The production wiring. Constructed lazily so that merely importing this
  /// file cannot touch Firebase — the room screens are reachable from widget
  /// tests that have no Firebase app.
  /// COVER GRANTS STAY OFF THIS PATH. Entry reads a room to decide whether it
  /// may be joined; the cover is not part of that decision, and
  /// `getRoomCoverMediaAccess` is a callable of its own — a cold start sitting
  /// in the middle of the Join await chain. Both reads warm the same
  /// process-wide grant cache in the background instead, so the room screen's
  /// first `watchRoom` emission still finds it, and [enter] carries the
  /// caller's already-resolved URL forward so nothing on screen goes blank.
  factory RoomVoiceEntryCoordinator.production({RoomService? rooms}) {
    final service = rooms ?? RoomService();
    return RoomVoiceEntryCoordinator(
      readRoom: (roomId) => service.getRoom(roomId, resolveCover: false),
      resolveAuthority: service.resolveVoiceStartAuthority,
      startVoice: service.startRoomVoice,
      joinRoom: (roomId, {startMuted = false}) =>
          service.joinRoom(roomId, startMuted: startMuted, resolveCover: false),
      currentUserId: () => service.currentUserId,
    );
  }

  final Future<VoiceRoom> Function(String roomId) _readRoom;
  final Future<RoomVoiceStartAuthority> Function(VoiceRoom room)
  _resolveAuthority;
  final Future<void> Function(String roomId) _startVoice;
  final Future<VoiceRoom> Function(String roomId, {bool startMuted}) _joinRoom;
  final String Function()? _currentUserId;

  /// Whether prejoin must obtain microphone access before creating a roster
  /// row. Community members and a broadcast host enter with publish rights.
  /// A broadcast audience member does not: the server-minted token grants
  /// `canPublish: false`, so asking that listener for microphone access would
  /// be both unnecessary and a privacy regression.
  ///
  /// This is deliberately only the initial-role decision. LiveKit remains
  /// authoritative and [VoiceCallService] rechecks the token grant before it
  /// touches media; a listener promoted later is handled by that path.
  bool requiresMicrophoneForInitialEntry(VoiceRoom room) {
    if (!room.isBroadcast) return true;
    final currentUserId = _currentUserId?.call() ?? '';
    return currentUserId.isNotEmpty && currentUserId == room.hostId;
  }

  /// Resolves [room] into the state the screens render from, performing the
  /// liveness transition when — and only when — this account may.
  Future<RoomVoiceEntry> enter(
    VoiceRoom room, {
    bool startMuted = false,
  }) async {
    // The caller's copy can be arbitrarily stale: Home hands over a document
    // from a cached list, a notification hands over one fetched minutes ago,
    // and `isLive` is exactly the field most likely to have moved. A refresh
    // that fails is not fatal — fall back to what we were given rather than
    // blocking entry on a transient read.
    var current = room;
    try {
      current = _carryCover(await _readRoom(room.id), room);
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
      return _joinLive(
        current,
        RoomVoiceEntryOutcome.live,
        startMuted: startMuted,
      );
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
      startMuted: startMuted,
    );
  }

  Future<RoomVoiceEntry> _joinLive(
    VoiceRoom room,
    RoomVoiceEntryOutcome outcome, {
    RoomVoiceStartAuthority authority = RoomVoiceStartAuthority.none,
    bool startMuted = false,
  }) async {
    try {
      final joined = await _joinRoom(room.id, startMuted: startMuted);
      return RoomVoiceEntry(
        outcome: outcome,
        room: _carryCover(joined, room),
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

  /// Keeps a cover URL the caller had already resolved.
  ///
  /// A refreshed or joined room comes back with the canonical Storage identity
  /// but no signed URL, because resolving one is a callable this path
  /// deliberately does not wait for. Reusing the URL the previous copy carried
  /// is safe only while it describes the SAME object: the storage path and the
  /// generation must match, so a cover replaced between the two reads falls
  /// back to the gradient rather than painting the old image.
  static VoiceRoom _carryCover(VoiceRoom fresh, VoiceRoom previous) {
    final carried = previous.imageUrl;
    if (fresh.imageUrl != null || carried == null) return fresh;
    if (!fresh.hasCanonicalCover ||
        fresh.coverStoragePath != previous.coverStoragePath ||
        fresh.coverGeneration != previous.coverGeneration) {
      return fresh;
    }
    return fresh.withResolvedImageUrl(carried);
  }

  /// Maps transport and application failures to a small allow-list of product
  /// messages. Backend exception text must never cross this presentation
  /// boundary: it can contain implementation details or user-controlled data.
  static String _friendly(Object error, String fallback) {
    if (error is FirebaseFunctionsException) {
      final productMessage = _allowedProductMessage(error.message);
      if (productMessage != null) return productMessage;
      return switch (error.code) {
        'permission-denied' => 'You do not have access to this room right now.',
        'not-found' => 'This room no longer exists.',
        // A client deadline is NOT a missing network. The join callables now
        // carry their own deadlines, so a cold or stalled instance ends here;
        // telling that person to check their connection would send them to fix
        // something that is not broken. It falls through to this operation's
        // own retry message instead ("Could not start voice. Try again.").
        'deadline-exceeded' => fallback,
        'unavailable' || 'network-request-failed' =>
          'You appear to be offline. Check your connection and try again.',
        'resource-exhausted' => 'Voice is busy right now. Try again shortly.',
        'unauthenticated' => 'Please sign in again to join this room.',
        'aborted' || 'failed-precondition' =>
          'The room changed while you were joining. Try again.',
        _ => fallback,
      };
    }
    // Same reasoning as `deadline-exceeded`: a bounded wait that ran out is a
    // retry, not an offline report.
    if (error is TimeoutException) return fallback;
    // Ordered AFTER the callable branch on purpose: FirebaseFunctionsException
    // IS a FirebaseException, and its `.message` carries real product copy
    // while a raw Firestore one carries "[cloud_firestore/permission-denied]
    // The caller does not have permission…". Map the code instead.
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' => 'You do not have access to this room right now.',
        'not-found' => 'This room no longer exists.',
        'deadline-exceeded' => fallback,
        'unavailable' || 'network-request-failed' =>
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
      return _allowedProductMessage(error.message) ?? fallback;
    }
    return fallback;
  }

  static String? _allowedProductMessage(Object? rawMessage) {
    final message = rawMessage?.toString().trim();
    return switch (message) {
      'This room is full.' ||
      'This room is currently unavailable.' ||
      'Voice is not live in this room.' ||
      'Only club members can enter the Club Lounge.' ||
      'This lounge is not available right now.' ||
      'The room could not be opened.' ||
      'This room is not currently live.' => message,
      'The requested room does not exist.' ||
      'The room no longer exists.' ||
      'Room not found.' => 'This room no longer exists.',
      'You must be signed in to use rooms.' =>
        'Please sign in again to join this room.',
      _ => null,
    };
  }
}
