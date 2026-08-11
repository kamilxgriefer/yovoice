import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

/// The friend-request notification lifecycle, CLIENT side.
///
/// Since ADR-041 the client does not write these notifications at all:
/// onFriendRequestCreated and onFriendRequestResolved derive them from
/// the documents these methods commit. So what belongs here is the
/// client's half of the contract — that it writes the authoritative
/// source documents the triggers key on, in the right places, and that
/// it does NOT write a notification of its own (which rules now refuse
/// anyway, and which used to fail silently).
///
/// The notification itself is proven end-to-end against the real
/// triggers in functions/test/social_notifications.smoke.js, and the
/// trigger logic in functions/test/social_notifications.test.js.
void main() {
  const senderUid = 'alice-uid';
  const acceptorUid = 'bob-uid';

  late FakeFirebaseFirestore db;

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

  FriendService serviceFor(String uid, String email, String name) {
    return FriendService(
      firestore: db,
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: uid, email: email, displayName: name),
      ),
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
    await seedUsers();
  });

  test('sending a request commits the source document the trigger keys '
      'on, under the RECIPIENT, and writes no notification itself', () async {
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

    // onFriendRequestCreated fires on users/{recipient}/friendRequests/
    // {sender}: the path itself carries both identities, which is why
    // neither can be spoofed by the caller.
    final request = await db
        .collection('users')
        .doc(acceptorUid)
        .collection('friendRequests')
        .doc(senderUid)
        .get();
    expect(request.exists, isTrue);
    expect(request.data()!['senderId'], senderUid);

    // And the mirror the sender uses to see their own outgoing request.
    final sent = await db
        .collection('users')
        .doc(senderUid)
        .collection('sentFriendRequests')
        .doc(acceptorUid)
        .get();
    expect(sent.exists, isTrue);

    // No client-written notification on either side.
    expect(await notificationsOf(acceptorUid), isEmpty);
    expect(await notificationsOf(senderUid), isEmpty);
  });

  test(
    'accepting commits the friendship AND removes the request, which is '
    'exactly what tells onFriendRequestResolved it was an acceptance',
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

      // Both halves of the friendship exist...
      for (final pair in [
        [senderUid, acceptorUid],
        [acceptorUid, senderUid],
      ]) {
        final friend = await db
            .collection('users')
            .doc(pair[0])
            .collection('friends')
            .doc(pair[1])
            .get();
        expect(friend.exists, isTrue, reason: '${pair[0]} -> ${pair[1]}');
      }

      // ...and the request document is gone. The trigger distinguishes
      // accept from decline precisely by whether the friendship exists
      // once this document disappears.
      final request = await db
          .collection('users')
          .doc(acceptorUid)
          .collection('friendRequests')
          .doc(senderUid)
          .get();
      expect(request.exists, isFalse);

      // Still nothing client-written in either feed.
      expect(await notificationsOf(senderUid), isEmpty);
      expect(await notificationsOf(acceptorUid), isEmpty);
    },
  );

  test(
    'a retried acceptance notification cannot duplicate: deterministic '
    'dedupe doc id keeps the sender feed at exactly one entry',
    () async {
      final bobNotifications = NotificationService(
        firestore: db,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: acceptorUid,
            email: 'bob@yovoice.app',
            displayName: 'Bob',
          ),
        ),
      );

      // The deterministic id onFriendRequestResolved writes under. The
      // mechanism is unchanged by ADR-041 — only the writer moved — so
      // this still pins "a replay lands on the same document".
      const dedupeKey = 'friendAccepted_$acceptorUid';
      await bobNotifications.notify(
        recipientId: senderUid,
        type: NotificationType.friendAccepted,
        dedupeKey: dedupeKey,
      );
      await bobNotifications.notify(
        recipientId: senderUid,
        type: NotificationType.friendAccepted,
        dedupeKey: dedupeKey,
      );

      final aliceFeed = await notificationsOf(senderUid);
      expect(
        aliceFeed.where(
          (n) => n['type'] == NotificationType.friendAccepted.name,
        ),
        hasLength(1),
        reason:
            'the deterministic doc id makes a duplicate physically '
            'impossible — a retry lands on the same document',
      );
    },
  );

  test('declining or cancelling leaves no acceptance notification', () async {
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

    final bob = serviceFor(acceptorUid, 'bob@yovoice.app', 'Bob');
    await bob.declineFriendRequest(senderUid);

    // Decline is intentionally silent toward the sender: no notification
    // of any kind is produced (product decision — a decline should not
    // broadcast rejection).
    expect(await notificationsOf(senderUid), isEmpty);

    // The request docs are gone, so the request can no longer be acted on.
    final requestDoc = await db
        .collection('users')
        .doc(acceptorUid)
        .collection('friendRequests')
        .doc(senderUid)
        .get();
    expect(requestDoc.exists, isFalse);
  });
}
