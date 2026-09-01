import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/rooms/data/services/room_service.dart';

void main() {
  const roomId = 'secure-room';
  const userId = 'member';
  late FakeFirebaseFirestore firestore;
  late RoomService rooms;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    rooms = RoomService(
      firestore: firestore,
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: userId,
          email: 'member@yovoice.app',
          displayName: 'Member',
        ),
      ),
    );
    await firestore.collection('users').doc(userId).set({
      'displayName': 'Member',
      'photoUrl': null,
    });
    await firestore.collection('rooms').doc(roomId).set({
      'hostId': 'host',
      'hostName': 'Host',
      'name': 'Secure room',
      'description': '',
      'category': 'talk',
      'visibility': 'public',
      'language': 'English',
      'participantCount': 0,
      'memberCount': 0,
      'isLive': true,
      'roomType': 'community',
      'status': 'active',
      'experience': 'community',
      'approvalRequired': false,
      'slowModeSeconds': 0,
      'autoMuteNewUsers': false,
      'membersCanStartVoice': true,
    });
  });

  test(
    'confirmed external entry writes the same muted state as LiveKit',
    () async {
      await rooms.joinRoom(roomId, startMuted: true);

      final participant = await firestore
          .collection('rooms')
          .doc(roomId)
          .collection('participants')
          .doc(userId)
          .get();
      expect(participant.data()?['isMuted'], isTrue);
    },
  );

  test(
    're-entry replaces a stale roster mute with the requested state',
    () async {
      final participant = firestore
          .collection('rooms')
          .doc(roomId)
          .collection('participants')
          .doc(userId);
      await participant.set({
        'userId': userId,
        'displayName': 'Member',
        'photoUrl': null,
        'role': 'speaker',
        'isMuted': false,
        'isSpeaker': true,
        'isHandRaised': false,
      });

      await rooms.joinRoom(roomId, startMuted: true);
      expect((await participant.get()).data()?['isMuted'], isTrue);

      await rooms.joinRoom(roomId);
      expect((await participant.get()).data()?['isMuted'], isFalse);
    },
  );
}
