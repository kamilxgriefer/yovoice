import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/rooms/data/services/room_service.dart';

/// Regression coverage for the false "This room has ended" ejection
/// (docs/Bugs.md): the roster stream can emit CACHE-sourced snapshots,
/// so a missing own-participant document is only a HINT. The room
/// screens now gate the ended state on
/// [RoomService.isParticipantRemovedOnServer], which must be
/// conservative — anything other than a confirmed absence keeps the
/// user in the room.
void main() {
  const roomId = 'room-1';
  const uid = 'me-uid';

  late FakeFirebaseFirestore db;

  RoomService service() => RoomService(
    firestore: db,
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, email: 'me@yovoice.app'),
    ),
  );

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  test('a participant still on the roster is NOT reported removed — a '
      'transient empty snapshot cannot eject them', () async {
    await db
        .collection('rooms')
        .doc(roomId)
        .collection('participants')
        .doc(uid)
        .set({
          'userId': uid,
          'displayName': 'Me',
          'role': 'host',
          'isMuted': false,
          'isSpeaker': true,
        });

    expect(
      await service().isParticipantRemovedOnServer(roomId: roomId, userId: uid),
      isFalse,
    );
  });

  test('a genuinely removed participant IS reported removed', () async {
    // Roster exists (someone else is in the room) but our doc is gone —
    // the real moderator-removal case.
    await db
        .collection('rooms')
        .doc(roomId)
        .collection('participants')
        .doc('someone-else')
        .set({'userId': 'someone-else', 'displayName': 'Other'});

    expect(
      await service().isParticipantRemovedOnServer(roomId: roomId, userId: uid),
      isTrue,
    );
  });

  test('the check fails CLOSED: an unreadable roster never ejects', () async {
    // A service whose Firestore throws stands in for offline/permission
    // failures — the answer must be "not removed", never an ejection.
    final failing = RoomService(
      firestore: _ThrowingFirestore(),
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: uid, email: 'me@yovoice.app'),
      ),
    );

    expect(
      await failing.isParticipantRemovedOnServer(roomId: roomId, userId: uid),
      isFalse,
    );
  });
}

/// Minimal stand-in whose collection access throws, exercising the
/// catch path of [RoomService.isParticipantRemovedOnServer].
class _ThrowingFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    throw StateError('network down');
  }
}
