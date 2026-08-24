import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';

/// The friend-request notification lifecycle, CLIENT side. Graph mutations
/// are Cloud Function calls now; this suite pins the exact callable contract
/// and verifies that the client never attempts to write notification rows.
void main() {
  const senderUid = 'alice-uid';
  const acceptorUid = 'bob-uid';

  late FakeFirebaseFirestore db;
  late List<({String uid, String name, Map<String, dynamic> data})> calls;

  Future<void> seedUsers() async {
    await db.collection('users').doc(senderUid).set({
      'uid': senderUid,
      'displayName': 'Alice',
      'email': 'alice@yovoice.app',
    });
    await db.collection('users').doc(acceptorUid).set({
      'uid': acceptorUid,
      'displayName': 'Bob',
      'email': 'bob@yovoice.app',
    });
  }

  FriendService serviceFor(
    String uid,
    String email,
    String name, {
    String sendOutcome = 'requested',
  }) {
    return FriendService(
      firestore: db,
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: uid, email: email, displayName: name),
      ),
      mutationInvoker: (functionName, data) async {
        calls.add((uid: uid, name: functionName, data: data));
        if (functionName == 'sendFriendRequest') {
          return <String, dynamic>{'changed': true, 'outcome': sendOutcome};
        }
        return const <String, dynamic>{'changed': true};
      },
    );
  }

  Future<List<Map<String, dynamic>>> notificationsOf(String uid) async {
    final snapshot = await db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList(growable: false);
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    calls = [];
    await seedUsers();
  });

  test(
    'sending delegates only the target id to the authoritative callable',
    () async {
      final alice = serviceFor(senderUid, 'alice@yovoice.app', 'Alice');
      await alice.sendFriendRequest(
        const FriendUser(
          id: acceptorUid,
          displayName: 'Bob',
          email: 'bob@yovoice.app',
          photoUrl: null,
          isOnline: false,
          lastSeen: null,
        ),
      );

      expect(calls, hasLength(1));
      expect(calls.single.uid, senderUid);
      expect(calls.single.name, 'sendFriendRequest');
      expect(calls.single.data, {'targetUserId': acceptorUid});

      // No client-written notification on either side.
      expect(await notificationsOf(acceptorUid), isEmpty);
      expect(await notificationsOf(senderUid), isEmpty);
    },
  );

  test('an idempotent already-pending response remains Request sent', () async {
    final alice = serviceFor(
      senderUid,
      'alice@yovoice.app',
      'Alice',
      sendOutcome: 'alreadyPending',
    );

    final relationship = await alice.sendFriendRequest(
      const FriendUser(
        id: acceptorUid,
        displayName: 'Bob',
        email: 'bob@yovoice.app',
        photoUrl: null,
        isOnline: false,
        lastSeen: null,
      ),
    );

    expect(relationship, FriendRelationshipStatus.requestSent);
    expect(calls.single.name, 'sendFriendRequest');
  });

  test(
    'accepting delegates sender id and the explicit accept decision',
    () async {
      final bob = serviceFor(acceptorUid, 'bob@yovoice.app', 'Bob');
      await bob.acceptFriendRequest(
        const FriendRequest(
          senderId: senderUid,
          senderName: 'Alice',
          senderEmail: 'alice@yovoice.app',
          senderPhotoUrl: null,
          createdAt: null,
        ),
      );

      expect(calls, hasLength(1));
      expect(calls.single.uid, acceptorUid);
      expect(calls.single.name, 'respondToFriendRequest');
      expect(calls.single.data, {'senderId': senderUid, 'accept': true});

      // Still nothing client-written in either feed.
      expect(await notificationsOf(senderUid), isEmpty);
      expect(await notificationsOf(acceptorUid), isEmpty);
    },
  );

  test('declining delegates the explicit negative decision', () async {
    final bob = serviceFor(acceptorUid, 'bob@yovoice.app', 'Bob');
    await bob.declineFriendRequest(senderUid);

    // Decline is intentionally silent toward the sender: no notification
    // of any kind is produced (product decision — a decline should not
    // broadcast rejection).
    expect(await notificationsOf(senderUid), isEmpty);

    expect(calls, hasLength(1));
    expect(calls.single.name, 'respondToFriendRequest');
    expect(calls.single.data, {'senderId': senderUid, 'accept': false});
  });
}
