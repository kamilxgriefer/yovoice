import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

/// Notification ROUTING suite: a friend DM must light the chat unread
/// surfaces only — never the global bell — while the notification
/// document keeps existing (it is what fires the push). A non-friend's
/// message keeps its bell entry (the message-request moment), and
/// non-chat events (friend requests, follows, invites) stay bell
/// events. Read state clears only its own surface.
void main() {
  const senderUid = 'sender-uid';
  const recipientUid = 'recipient-uid';

  late FakeFirebaseFirestore db;

  MockFirebaseAuth authFor(String uid, String name) => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(
      uid: uid,
      email: '$uid@yovoice.app',
      displayName: name,
    ),
  );

  MessageService senderMessages() => MessageService(
    firestore: db,
    auth: authFor(senderUid, 'Sender'),
    notificationService: NotificationService(
      firestore: db,
      auth: authFor(senderUid, 'Sender'),
    ),
  );

  NotificationService senderNotifications() =>
      NotificationService(firestore: db, auth: authFor(senderUid, 'Sender'));

  NotificationService recipientNotifications() => NotificationService(
    firestore: db,
    auth: authFor(recipientUid, 'Recipient'),
  );

  Future<void> seedUsers() async {
    await db.collection('users').doc(senderUid).set({
      'uid': senderUid,
      'displayName': 'Sender',
      'photoUrl': 'https://example.com/sender.jpg',
    });
    await db.collection('users').doc(recipientUid).set({
      'uid': recipientUid,
      'displayName': 'Recipient',
      'photoUrl': 'https://example.com/recipient.jpg',
    });
  }

  Future<void> makeFriends() async {
    await db
        .collection('users')
        .doc(senderUid)
        .collection('friends')
        .doc(recipientUid)
        .set({'uid': recipientUid, 'displayName': 'Recipient'});
    await db
        .collection('users')
        .doc(recipientUid)
        .collection('friends')
        .doc(senderUid)
        .set({'uid': senderUid, 'displayName': 'Sender'});
  }

  Future<String> sendDm(String text) async {
    final messages = senderMessages();
    final conversationId = await messages.openOrCreateConversation(
      otherUserId: recipientUid,
      otherDisplayName: 'Recipient',
      otherEmail: '$recipientUid@yovoice.app',
      otherPhotoUrl: '',
    );
    await messages.sendTextMessage(
      conversationId: conversationId,
      recipientId: recipientUid,
      text: text,
    );
    return conversationId;
  }

  Future<int> conversationUnread(String conversationId) async {
    final doc = await db.collection('conversations').doc(conversationId).get();
    final unread = doc.data()?['unreadCounts'] as Map<String, dynamic>?;
    return (unread?[recipientUid] as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, dynamic>>> rawNotificationDocs() async {
    final snapshot = await db
        .collection('users')
        .doc(recipientUid)
        .collection('notifications')
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList(growable: false);
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    await seedUsers();
  });

  test('1. friend DM: chat unread YES, global bell NO — but the push-'
      'carrying record still exists, marked bellSuppressed', () async {
    await makeFriends();
    final conversationId = await sendDm('hey friend');

    // Chat surface lights up.
    expect(await conversationUnread(conversationId), 1);

    // The record exists (push depends on the document being created)...
    final raw = await rawNotificationDocs();
    expect(raw, hasLength(1));
    expect(raw.single['type'], 'directMessage');
    expect(raw.single['bellSuppressed'], isTrue);

    // ...but the bell feed and the bell badge never see it.
    final bell = recipientNotifications();
    expect(await bell.watchUnreadCount().first, 0);
    expect(await bell.watchNotifications().first, isEmpty);
  });

  test('2. non-friend DM: bell shows it as a message request', () async {
    final conversationId = await sendDm('hello stranger');

    // Chat surface lights up exactly like any conversation.
    expect(await conversationUnread(conversationId), 1);

    // The bell carries it — this is the message-request moment.
    final bell = recipientNotifications();
    expect(await bell.watchUnreadCount().first, 1);
    final feed = await bell.watchNotifications().first;
    expect(feed, hasLength(1));
    expect(feed.single.type, NotificationType.directMessage);
    expect(feed.single.bellSuppressed, isFalse);
    expect(feed.single.title, 'Sender sent you a message request');
  });

  test('3. non-chat events (friend request / follow / club invite) stay '
      'bell events', () async {
    final sender = senderNotifications();
    await sender.notify(
      recipientId: recipientUid,
      type: NotificationType.friendRequest,
    );
    await sender.notify(
      recipientId: recipientUid,
      type: NotificationType.follow,
    );
    await sender.notify(
      recipientId: recipientUid,
      type: NotificationType.clubInvite,
      targetId: 'club-1',
      targetLabel: 'Night Owls',
    );

    final bell = recipientNotifications();
    expect(await bell.watchUnreadCount().first, 3);
    final types = (await bell.watchNotifications().first)
        .map((notification) => notification.type)
        .toSet();
    expect(types, {
      NotificationType.friendRequest,
      NotificationType.follow,
      NotificationType.clubInvite,
    });
  });

  test('4a. opening the chat clears the conversation unread only — the '
      'bell state is untouched in both directions', () async {
    await makeFriends();
    final conversationId = await sendDm('read me');

    // A separate real bell event so the bell has something to protect.
    await senderNotifications().notify(
      recipientId: recipientUid,
      type: NotificationType.friendRequest,
    );

    final recipientMessages = MessageService(
      firestore: db,
      auth: authFor(recipientUid, 'Recipient'),
      notificationService: recipientNotifications(),
    );
    await recipientMessages.markConversationRead(conversationId);

    expect(await conversationUnread(conversationId), 0);
    // The unrelated bell event is still unread; the suppressed DM record
    // still never counts.
    expect(await recipientNotifications().watchUnreadCount().first, 1);
  });

  test('4b. reading a bell notification does not touch chat unread', () async {
    final conversationId = await sendDm('stranger message');

    final bell = recipientNotifications();
    final feedItem = (await bell.watchNotifications().first).single;
    await bell.markAsRead(feedItem.id);

    expect(await bell.watchUnreadCount().first, 0);
    // The conversation unread survives — it clears only by opening the
    // chat, never by reading the bell.
    expect(await conversationUnread(conversationId), 1);
  });
}
