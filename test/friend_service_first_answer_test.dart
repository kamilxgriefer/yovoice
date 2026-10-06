import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';

/// `watchFriends()` must not answer "no friends" before it knows.
///
/// The stream reads the relationship rows first and joins each friend's
/// public profile afterwards. It used to publish its list at the end of the
/// first root snapshot, when no profile had joined yet: an EMPTY list for an
/// account that has friends. Its first listener took that at its word — the
/// Friends screen and the server invite sheet flashed "No friends yet" (now
/// with an "Add friend" / "Share the server link" button under it), and
/// Start's "Zacznij tutaj" card counted the friend step as open. A presence
/// answer that beat the profile did the same.
///
/// The list is now withheld while rows are listed and none has joined.
void main() {
  const meUid = 'me-uid';
  const friendId = 'ola-uid';

  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;

  setUp(() {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: meUid));
  });

  tearDown(FriendService.clearSharedReadCaches);

  DocumentReference<Map<String, dynamic>> edge(String id) =>
      db.collection('users').doc(meUid).collection('friends').doc(id);

  Future<void> settle() async {
    for (var turn = 0; turn < 20; turn += 1) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('an account with friends never hears an empty list first, even when '
      'presence answers before the profile', () async {
    await edge(friendId).set({'userId': friendId});
    await db.collection('publicProfiles').doc(friendId).set({
      'displayName': 'Ola Nowak',
    });
    await db.collection('socialPresence').doc(friendId).set({'isOnline': true});
    final profileDocument = await db
        .collection('publicProfiles')
        .doc(friendId)
        .get();
    final presenceDocument = await db
        .collection('socialPresence')
        .doc(friendId)
        .get();

    final profiles =
        StreamController<DocumentSnapshot<Map<String, dynamic>>>.broadcast();
    final presences =
        StreamController<DocumentSnapshot<Map<String, dynamic>>>.broadcast();
    addTearDown(profiles.close);
    addTearDown(presences.close);
    final profileAttached = Completer<void>();
    final presenceAttached = Completer<void>();
    final service = FriendService(
      firestore: db,
      auth: auth,
      publicProfileWatch: (_) {
        if (!profileAttached.isCompleted) profileAttached.complete();
        return profiles.stream;
      },
      socialPresenceWatch: (_) {
        if (!presenceAttached.isCompleted) presenceAttached.complete();
        return presences.stream;
      },
    );

    final heard = <List<FriendUser>>[];
    final subscription = service.watchFriends().listen(heard.add);
    addTearDown(subscription.cancel);

    // The relationship row is known; neither child has answered.
    await profileAttached.future.timeout(const Duration(seconds: 5));
    await presenceAttached.future.timeout(const Duration(seconds: 5));
    await settle();
    expect(
      heard,
      isEmpty,
      reason: 'a listed friend whose profile has not joined is not "nobody"',
    );

    // Presence first: still nothing to say about who the friends are.
    presences.add(presenceDocument);
    await settle();
    expect(heard, isEmpty, reason: 'presence alone must not publish []');

    // The profile joins: the first thing anybody hears is the friend.
    profiles.add(profileDocument);
    await settle();
    expect(heard, isNotEmpty);
    expect(heard.first.map((friend) => friend.id), [friendId]);
    expect(heard.first.single.displayName, 'Ola Nowak');
    expect(heard.first.single.isOnline, isTrue);
    expect(heard.every((list) => list.isNotEmpty), isTrue);

    // A late listener gets the same list replayed, never an empty one.
    final late = await service.watchFriends().first.timeout(
      const Duration(seconds: 5),
    );
    expect(late.map((friend) => friend.id), [friendId]);
  });

  test('an account with nobody hears the empty list at once', () async {
    final service = FriendService(firestore: db, auth: auth);
    final first = await service.watchFriends().first.timeout(
      const Duration(seconds: 5),
    );
    expect(first, isEmpty);
  });

  test('removing the last friend publishes the empty list', () async {
    await edge(friendId).set({'userId': friendId});
    await db.collection('publicProfiles').doc(friendId).set({
      'displayName': 'Ola Nowak',
    });
    final service = FriendService(firestore: db, auth: auth);

    final heard = <List<FriendUser>>[];
    final populated = Completer<void>();
    final emptied = Completer<void>();
    final subscription = service.watchFriends().listen((friends) {
      heard.add(friends);
      if (friends.isNotEmpty && !populated.isCompleted) populated.complete();
      if (populated.isCompleted && friends.isEmpty && !emptied.isCompleted) {
        emptied.complete();
      }
    });
    addTearDown(subscription.cancel);

    await populated.future.timeout(const Duration(seconds: 5));
    expect(heard.first, isNotEmpty, reason: 'no empty list before the join');

    await edge(friendId).delete();
    await emptied.future.timeout(const Duration(seconds: 5));
    expect(heard.last, isEmpty);
  });

  test(
    'a friend whose profile cannot be read still ends the silence',
    () async {
      await edge(friendId).set({'userId': friendId, 'displayName': 'Ola'});
      // No publicProfiles document: the row degrades in place and is listed.
      final service = FriendService(firestore: db, auth: auth);
      final first = await service.watchFriends().first.timeout(
        const Duration(seconds: 5),
      );
      expect(first.map((friend) => friend.id), [friendId]);
      expect(first.single.displayName, 'Ola');
    },
  );
}
