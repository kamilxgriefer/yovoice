import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/achievements/data/services/achievement_service.dart';
import 'package:yovoice/features/rooms/data/models/voice_room.dart';
import 'package:yovoice/features/rooms/data/services/room_service.dart';

import 'helpers/room_creation_test_double.dart';

/// Achievements could only ever progress from ONE source event (chat
/// messages): `incrementMetric` had a single caller, and the other
/// counters — momentCount, roomCount, … — were never written by the
/// actions that should feed them, so those achievements sat at 0/N
/// forever. These tests pin the source events that are now wired, and
/// the recompute that turns a counter into an unlocked title.
void main() {
  const uid = 'achiever-uid';

  late FakeFirebaseFirestore db;

  MockFirebaseAuth auth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: 'a@yovoice.app', displayName: 'A'),
  );

  Future<Map<String, dynamic>> userDoc() async {
    final snapshot = await db.collection('users').doc(uid).get();
    return snapshot.data() ?? const <String, dynamic>{};
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.collection('users').doc(uid).set({
      'uid': uid,
      'displayName': 'A',
      'email': 'a@yovoice.app',
    });
  });

  test('creating a room increments roomCount — the rooms metric now has '
      'a real source event', () async {
    final rooms = RoomService(
      firestore: db,
      auth: auth(),
      roomCreateInvoker: (request) => createRoomForTest(
        firestore: db,
        userId: uid,
        request: request,
        incrementRoomCount: true,
      ),
    );

    await rooms.createRoom(
      name: 'First room',
      description: '',
      category: 'talk',
      visibility: 'public',
      language: 'English',
      maxParticipants: 25,
      roomType: RoomType.community,
    );

    expect((await userDoc())['roomCount'], 1);

    await rooms.createRoom(
      name: 'Second room',
      description: '',
      category: 'talk',
      visibility: 'public',
      language: 'English',
      maxParticipants: 25,
      roomType: RoomType.community,
    );

    expect((await userDoc())['roomCount'], 2);
  });

  test('a counter reaching a threshold unlocks its achievement and the '
      'unlock is persisted', () async {
    final achievements = AchievementService(firestore: db, auth: auth());

    final unlocked = await achievements.incrementMetric('rooms');
    final data = await userDoc();

    expect(data['roomCount'], 1);
    // The first-room achievement (threshold 1) must be unlocked by the
    // very event that produced the count — not on some later screen open.
    expect(unlocked, isNotEmpty);
    expect(
      (data['unlockedTitleIds'] as List<dynamic>).cast<String>(),
      contains(unlocked.first.id),
    );
    expect(data['unlockedTitleTimestamps'], isNotNull);
  });

  test('refreshUnlockedTitles recomputes unlocks from counters written by '
      'OTHER services (friends/followers), which never called '
      'incrementMetric', () async {
    // FriendService/FollowService write these counters directly.
    await db.collection('users').doc(uid).set({
      'friendCount': 1,
      'followerCount': 1,
    }, SetOptions(merge: true));

    await AchievementService(
      firestore: db,
      auth: auth(),
    ).refreshUnlockedTitles();

    final ids = ((await userDoc())['unlockedTitleIds'] as List<dynamic>)
        .cast<String>();
    expect(
      ids,
      isNotEmpty,
      reason: 'counters written elsewhere must still be able to unlock',
    );
  });

  test('incrementing an unknown metric is rejected rather than silently '
      'writing a junk field', () async {
    final achievements = AchievementService(firestore: db, auth: auth());
    expect(
      () => achievements.incrementMetric('not-a-metric'),
      throwsArgumentError,
    );
  });
}
