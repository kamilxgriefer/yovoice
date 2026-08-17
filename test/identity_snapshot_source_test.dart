import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/clubs/data/models/family_check_in.dart';
import 'package:yovoice/features/clubs/data/services/club_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_experience_service.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

void main() {
  const uid = 'snapshot-user';
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: uid,
        email: 'stale@example.com',
        displayName: 'Stale Auth Name',
      ),
    );
    await firestore.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'Canonical Profile Name',
    });
  });

  test(
    'Family bootstrap uses one canonical name for root, owner and lounge',
    () async {
      final service = ClubService(
        firestore: firestore,
        auth: auth,
        storage: MockFirebaseStorage(),
      );

      await service.createFamilyRoom(
        name: 'Our Family',
        description: 'Private home',
      );

      expect(
        (await firestore.collection('clubs').doc('family_$uid').get())
            .data()?['ownerName'],
        'Canonical Profile Name',
      );
      expect(
        (await firestore
                .collection('clubs')
                .doc('family_$uid')
                .collection('members')
                .doc(uid)
                .get())
            .data()?['displayName'],
        'Canonical Profile Name',
      );
      expect(
        (await firestore
                .collection('rooms')
                .doc('club_lounge_family_$uid')
                .get())
            .data()?['hostName'],
        'Canonical Profile Name',
      );
    },
  );

  test(
    'room bootstrap uses canonical name, never modified Auth metadata',
    () async {
      final service = RoomService(firestore: firestore, auth: auth);

      final room = await service.createRoom(
        name: 'Canonical room',
        description: '',
        category: 'talk',
        visibility: 'public',
        language: 'English',
        maxParticipants: 25,
        roomType: RoomType.temporary,
      );

      expect(room.hostName, 'Canonical Profile Name');
      expect(
        (await firestore
                .collection('rooms')
                .doc(room.id)
                .collection('participants')
                .doc(uid)
                .get())
            .data()?['displayName'],
        'Canonical Profile Name',
      );
    },
  );

  test(
    'raise-hand snapshot uses users displayName, never stale Auth',
    () async {
      await firestore.collection('rooms').doc('broadcast-room').set({
        'experience': 'broadcast',
        'handRaisingEnabled': true,
      });
      final service = RoomExperienceService(firestore: firestore, auth: auth);

      await service.setHandRaised(roomId: 'broadcast-room', raised: true);

      final snapshot = await firestore
          .collection('rooms')
          .doc('broadcast-room')
          .collection('handRequests')
          .doc(uid)
          .get();
      expect(snapshot.data()?['displayName'], 'Canonical Profile Name');
    },
  );

  test(
    'Family check-in snapshot uses users displayName, never stale Auth',
    () async {
      final service = ClubService(
        firestore: firestore,
        auth: auth,
        storage: MockFirebaseStorage(),
      );

      await service.postCheckIn(
        clubId: 'family_snapshot-user',
        status: FamilyCheckInStatus.allGood,
      );

      final rows = await firestore
          .collection('clubs')
          .doc('family_snapshot-user')
          .collection('checkIns')
          .get();
      expect(rows.docs.single.data()['displayName'], 'Canonical Profile Name');
    },
  );

  test(
    'missing canonical displayName fails before either snapshot write',
    () async {
      await firestore.collection('users').doc(uid).set({'uid': uid});
      await firestore.collection('rooms').doc('broadcast-room').set({
        'experience': 'broadcast',
        'handRaisingEnabled': true,
      });
      final roomService = RoomExperienceService(
        firestore: firestore,
        auth: auth,
      );
      final clubService = ClubService(
        firestore: firestore,
        auth: auth,
        storage: MockFirebaseStorage(),
      );

      await expectLater(
        roomService.setHandRaised(roomId: 'broadcast-room', raised: true),
        throwsStateError,
      );
      await expectLater(
        clubService.postCheckIn(
          clubId: 'family_snapshot-user',
          status: FamilyCheckInStatus.home,
        ),
        throwsStateError,
      );
      await expectLater(
        clubService.createFamilyRoom(
          name: 'Missing identity',
          description: 'Must fail before bootstrap',
        ),
        throwsStateError,
      );

      expect(
        (await firestore
                .collection('rooms')
                .doc('broadcast-room')
                .collection('handRequests')
                .get())
            .docs,
        isEmpty,
      );
      expect((await firestore.collection('clubs').get()).docs, isEmpty);
      expect(
        (await firestore
                .collection('clubs')
                .doc('family_snapshot-user')
                .collection('checkIns')
                .get())
            .docs,
        isEmpty,
      );
    },
  );
}
