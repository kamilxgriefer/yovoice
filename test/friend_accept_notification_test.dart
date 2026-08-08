import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/friends/data/models/friend_request.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

/// Regression suite for the P0 friend-request notification lifecycle:
/// request created → notification to recipient; request ACCEPTED →
/// notification to the ORIGINAL SENDER (this was the broken direction);
/// no redundant "you accepted" notification for the acceptor; retries
/// cannot duplicate the acceptance notification; the resolved request
/// notification is retired instead of lingering as actionable.
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

  test('sending a request notifies the recipient, not the sender', () async {
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

    final bobFeed = await notificationsOf(acceptorUid);
    expect(bobFeed, hasLength(1));
    expect(bobFeed.single['type'], NotificationType.friendRequest.name);
    expect(bobFeed.single['actorId'], senderUid);
    expect(await notificationsOf(senderUid), isEmpty);
  });

  test(
    'accepting notifies the ORIGINAL SENDER with the acceptor as actor, '
    'and the acceptor gets no redundant self-notification',
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

      // The original sender's feed now holds the acceptance, attributed
      // to the acceptor — with real display data so the UI can show
      // "[Name] accepted your friend request."
      final aliceFeed = await notificationsOf(senderUid);
      final accepted = aliceFeed
          .where((n) => n['type'] == NotificationType.friendAccepted.name)
          .toList();
      expect(accepted, hasLength(1), reason: 'sender must be notified once');
      expect(accepted.single['actorId'], acceptorUid);
      expect(accepted.single['actorName'], 'Bob');

      // The acceptor's own feed must NOT contain an acceptance echo.
      final bobFeed = await notificationsOf(acceptorUid);
      expect(
        bobFeed.where(
          (n) => n['type'] == NotificationType.friendAccepted.name,
        ),
        isEmpty,
        reason: 'no redundant "you accepted" notification',
      );

      // The now-resolved friendRequest notification is retired (read),
      // so it no longer lingers as an actionable item.
      final request = bobFeed.singleWhere(
        (n) => n['type'] == NotificationType.friendRequest.name,
      );
      expect(request['isRead'], isTrue);
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

      // Same dedupeKey the production acceptFriendRequest passes.
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
