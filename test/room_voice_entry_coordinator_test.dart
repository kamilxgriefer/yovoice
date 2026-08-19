import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/rooms/data/models/room_voice_access.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_voice_entry_coordinator.dart';

/// THE ORDER IS THE CONTRACT.
///
/// `createLiveKitToken` refuses a token unless the room document says
/// `status == 'active' && isLive == true` AND the caller already holds a
/// participant row, so the only sequence that can ever succeed is:
/// liveness -> roster -> token. Every case below asserts on an event log, so
/// a future change that starts audio first fails here rather than in
/// production with "This room is not currently live."
///
/// The platform constructor is @protected; a subclass is the supported way to
/// build the exact exception shape production callables raise.
class _ServerRefusal extends FirebaseFunctionsException {
  _ServerRefusal(String message)
    : super(code: 'failed-precondition', message: message);
}

VoiceRoom _room({
  String id = 'room-1',
  bool isLive = false,
  RoomStatus status = RoomStatus.active,
  bool deletionInProgress = false,
}) {
  return VoiceRoom(
    id: id,
    hostId: 'host',
    hostName: 'Host',
    hostPhotoUrl: null,
    name: 'A room',
    description: '',
    category: 'talk',
    visibility: 'public',
    language: 'English',
    maxParticipants: null,
    participantCount: 0,
    memberCount: 0,
    isLive: isLive,
    roomType: RoomType.community,
    status: status,
    imageUrl: null,
    approvalRequired: false,
    slowModeSeconds: 0,
    autoMuteNewUsers: true,
    membersCanStartVoice: false,
    createdAt: null,
    updatedAt: null,
    deletionInProgress: deletionInProgress,
  );
}

class _Harness {
  _Harness({
    VoiceRoom? server,
    this.authority = RoomVoiceStartAuthority.host,
    this.readError,
    this.startError,
    this.joinError,
  }) : _server = server ?? _room() {
    coordinator = RoomVoiceEntryCoordinator(
      readRoom: (roomId) async {
        events.add('read:$roomId');
        final error = readError;
        if (error != null) throw error;
        return _server;
      },
      resolveAuthority: (room) async {
        events.add('authority:${room.id}');
        return authority;
      },
      startVoice: (roomId) async {
        events.add('start:$roomId');
        final error = startError;
        if (error != null) throw error;
        _server = _server.withLiveness(true);
      },
      joinRoom: (roomId) async {
        events.add('join:$roomId');
        final error = joinError;
        if (error != null) throw error;
        return _server;
      },
    );
  }

  final RoomVoiceStartAuthority authority;
  final Object? readError;
  final Object? startError;
  final Object? joinError;
  final List<String> events = [];
  VoiceRoom _server;
  late final RoomVoiceEntryCoordinator coordinator;
}

void main() {
  test(
    'a dormant room is made live and joined before anything could ask for a '
    'token',
    () async {
      final harness = _Harness();

      final entry = await harness.coordinator.enter(_room());

      expect(harness.events, [
        'read:room-1',
        'authority:room-1',
        'start:room-1',
        'join:room-1',
      ]);
      expect(entry.outcome, RoomVoiceEntryOutcome.started);
      expect(entry.voiceIsLive, isTrue);
      expect(entry.room.isLive, isTrue);
    },
  );

  test('an already-live room is joined and never written to', () async {
    final harness = _Harness(server: _room(isLive: true));

    final entry = await harness.coordinator.enter(_room(isLive: true));

    expect(harness.events, ['read:room-1', 'join:room-1']);
    expect(
      harness.events,
      isNot(contains('start:room-1')),
      reason: 'both rule branches require isLive to be false to start',
    );
    expect(entry.outcome, RoomVoiceEntryOutcome.live);
  });

  test(
    'a stale caller document does not decide anything — the server copy does',
    () async {
      // Home hands over a room from a cached list that still says "live".
      final harness = _Harness(server: _room(isLive: false));

      final entry = await harness.coordinator.enter(_room(isLive: true));

      expect(harness.events, [
        'read:room-1',
        'authority:room-1',
        'start:room-1',
        'join:room-1',
      ]);
      expect(entry.outcome, RoomVoiceEntryOutcome.started);
    },
  );

  test(
    'no authority means no write, no join, and an honest explanation',
    () async {
      final harness = _Harness(authority: RoomVoiceStartAuthority.none);

      final entry = await harness.coordinator.enter(_room());

      expect(harness.events, ['read:room-1', 'authority:room-1']);
      expect(entry.outcome, RoomVoiceEntryOutcome.dormant);
      expect(entry.voiceIsLive, isFalse);
      expect(
        entry.canStartVoice,
        isFalse,
        reason: 'the UI must not offer a control the rules would refuse',
      );
      expect(entry.message, isNotNull);
      expect(entry.message, isNot(contains('permission')));
    },
  );

  test('a closed room is refused before authority is even resolved', () async {
    final harness = _Harness(server: _room(status: RoomStatus.closed));

    final entry = await harness.coordinator.enter(_room());

    expect(harness.events, ['read:room-1']);
    expect(entry.outcome, RoomVoiceEntryOutcome.unavailable);
    expect(entry.message, 'This room has ended.');
  });

  test('a room being deleted is never restarted', () async {
    final harness = _Harness(server: _room(deletionInProgress: true));

    final entry = await harness.coordinator.enter(_room());

    expect(harness.events, ['read:room-1']);
    expect(entry.outcome, RoomVoiceEntryOutcome.unavailable);
    expect(entry.message, 'This room is being deleted.');
  });

  test(
    'a refused start keeps the retry available and never reaches the roster',
    () async {
      final harness = _Harness(
        startError: _ServerRefusal('The room could not be opened.'),
      );

      final entry = await harness.coordinator.enter(_room());

      expect(harness.events, ['read:room-1', 'authority:room-1', 'start:room-1']);
      expect(entry.outcome, RoomVoiceEntryOutcome.failed);
      expect(entry.voiceIsLive, isFalse);
      expect(
        entry.canStartVoice,
        isTrue,
        reason: 'the authority is real; only the write failed',
      );
      expect(entry.message, 'The room could not be opened.');
    },
  );

  test(
    'a failed roster join stops the flow instead of letting audio discover it',
    () async {
      final harness = _Harness(joinError: StateError('This room is full.'));

      final entry = await harness.coordinator.enter(_room());

      expect(entry.outcome, RoomVoiceEntryOutcome.failed);
      expect(entry.voiceIsLive, isFalse);
      expect(entry.message, 'This room is full.');
    },
  );

  test(
    'a failed refresh falls back to the document we were handed rather than '
    'blocking entry',
    () async {
      final harness = _Harness(readError: StateError('offline'));

      final entry = await harness.coordinator.enter(_room(isLive: true));

      expect(harness.events, ['read:room-1', 'join:room-1']);
      expect(entry.outcome, RoomVoiceEntryOutcome.live);
    },
  );

  test('every non-live outcome speaks product copy, never an error code', () {
    const refusal = 'This room is not currently live.';
    final entry = RoomVoiceEntry(
      outcome: RoomVoiceEntryOutcome.failed,
      room: _room(),
      authority: RoomVoiceStartAuthority.host,
      message: refusal,
    );
    expect(entry.message, isNot(contains('firebase_functions')));
    expect(entry.canStartVoice, isTrue);
  });
}
