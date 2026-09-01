import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';

/// `watchFriends()` must never silently drop a canonical friend edge just
/// because the `publicProfiles/{id}` projection is missing or unreadable —
/// that made the Friends counter disagree with search ("counter 0 while
/// search says Friends"). Such rows degrade: last known mirror name or a
/// neutral label, no photo, presence never fabricated.
void main() {
  const meUid = 'me-uid';

  late FakeFirebaseFirestore db;
  late FriendService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    service = FriendService(
      firestore: db,
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: meUid)),
    );
  });

  Future<void> seedFriendEdge(String friendId, Map<String, dynamic> data) {
    return db
        .collection('users')
        .doc(meUid)
        .collection('friends')
        .doc(friendId)
        .set(data);
  }

  test('friends whose public profile is missing still appear, and the '
      'count includes them', () async {
    await seedFriendEdge('ada-uid', {'userId': 'ada-uid'});
    await seedFriendEdge('bea-uid', {
      'userId': 'bea-uid',
      // Legacy mirror rows stored a displayName; canonical ones do not.
      'displayName': 'Bea Legacy',
    });
    await seedFriendEdge('cal-uid', {'userId': 'cal-uid'});
    await db.collection('publicProfiles').doc('ada-uid').set({
      'displayName': 'Ada',
      'photoUrl': 'https://example.com/ada.png',
    });
    // bea-uid and cal-uid have NO publicProfiles document.

    final friends = await service
        .watchFriends()
        .firstWhere((list) => list.length == 3)
        .timeout(const Duration(seconds: 5));

    expect(
      friends.map((friend) => friend.id).toSet(),
      {'ada-uid', 'bea-uid', 'cal-uid'},
      reason: 'no silent row drop: the count must include degraded rows',
    );

    FriendUser byId(String id) =>
        friends.singleWhere((friend) => friend.id == id);

    final ada = byId('ada-uid');
    expect(ada.displayName, 'Ada');
    expect(
      ada.photoUrl,
      isNull,
      reason: 'friends resolve avatars from uid through the media callable',
    );

    final bea = byId('bea-uid');
    expect(
      bea.displayName,
      'Bea Legacy',
      reason: 'degraded rows fall back to the mirror row stored name',
    );
    expect(bea.photoUrl, isNull);
    expect(bea.isOnline, isFalse, reason: 'presence is never fabricated');
    expect(bea.lastSeen, isNull);

    final cal = byId('cal-uid');
    expect(
      cal.displayName,
      'YO Voice member',
      reason: 'no mirror name available: neutral label, not a dropped row',
    );
    expect(cal.photoUrl, isNull);
    expect(cal.isOnline, isFalse);
  });

  test('a degraded row upgrades in place when the profile appears', () async {
    await seedFriendEdge('dee-uid', {'userId': 'dee-uid'});

    final states = <List<FriendUser>>[];
    final subscription = service.watchFriends().listen(states.add);
    addTearDown(subscription.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(states, isNotEmpty);
    expect(states.last, hasLength(1));
    expect(states.last.single.displayName, 'YO Voice member');

    await db.collection('publicProfiles').doc('dee-uid').set({
      'displayName': 'Dee',
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(states.last, hasLength(1));
    expect(states.last.single.displayName, 'Dee');
  });

  test(
    'a block stays visible and unblockable when its profile is missing',
    () async {
      await db
          .collection('users')
          .doc(meUid)
          .collection('blocked')
          .doc('private-uid')
          .set({'blockedAt': DateTime.now()});

      final blocked = await service.watchBlockedUsers().first;
      expect(blocked, hasLength(1));
      expect(blocked.single.id, 'private-uid');
      expect(blocked.single.displayName, 'Blocked user');
    },
  );
}
