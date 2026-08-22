import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/messages/data/services/message_outbox.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/models/app_notification.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

/// Simulates the rules rejecting a SUPPRESSED write (asymmetric
/// friendship: sender-side doc exists, recipient-side doesn't) so the
/// fail-toward-visible retry in sendTextMessage can be exercised —
/// fake_cloud_firestore itself enforces no security rules.
class _DenySuppressedNotifications extends NotificationService {
  _DenySuppressedNotifications({super.firestore, super.auth});

  final List<bool> suppressBellCalls = <bool>[];

  @override
  Future<void> notify({
    required String recipientId,
    required NotificationType type,
    String? targetId,
    String? targetLabel,
    String? dedupeKey,
    bool suppressBell = false,
  }) {
    suppressBellCalls.add(suppressBell);
    if (suppressBell) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'bell suppression requires an accepted friendship',
      );
    }
    return super.notify(
      recipientId: recipientId,
      type: type,
      targetId: targetId,
      targetLabel: targetLabel,
      dedupeKey: dedupeKey,
      suppressBell: suppressBell,
    );
  }
}

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

  /// Delivers a direct message the way the BACKEND does.
  ///
  /// Since ADR-082 the client writes neither the message document nor its
  /// notification: `sendDirectMessage` writes the message, and the
  /// `conversations/{id}/messages/{id}` trigger in
  /// `functions/notifications/activity.js` derives the notification from it,
  /// setting `bellSuppressed` from whether the RECIPIENT has the sender as a
  /// friend. This mirrors both writes so the routing rules below stay
  /// covered on the client surfaces that render them.
  Future<String> sendDm(String text) async {
    final messages = senderMessages();
    final conversationId = await messages.openOrCreateConversation(
      otherUserId: recipientUid,
      otherDisplayName: 'Recipient',
      otherEmail: '$recipientUid@yovoice.app',
      otherPhotoUrl: '',
    );
    final conversation = db.collection('conversations').doc(conversationId);
    final snapshot = await conversation.get();
    final sequence =
        ((snapshot.data()?['lastMessageSequence'] as num?)?.toInt() ?? 0) + 1;
    final messageId = 'm_server_$sequence';
    final now = Timestamp.now();

    await conversation.collection('messages').doc(messageId).set({
      'schemaVersion': 2,
      'sequence': sequence,
      'conversationId': conversationId,
      'senderId': senderUid,
      'type': 'text',
      'content': text,
      'mediaUrl': null,
      'durationSeconds': null,
      'sentAt': now,
      'readBy': [senderUid],
      'reactions': <String, String>{},
      'isDeleted': false,
      'editedAt': null,
      'replyToMessageId': null,
      'replyToSenderId': null,
      'replyToContent': null,
    });
    await conversation.update({
      'lastMessage': text,
      'lastMessageId': messageId,
      'lastMessageSequence': sequence,
      'lastMessageType': 'text',
      'lastMessageSenderId': senderUid,
      'updatedAt': now,
      'unreadCounts.$senderUid': 0,
      'unreadCounts.$recipientUid': FieldValue.increment(1),
    });

    // The trigger's own rule: suppressed exactly when the recipient counts
    // the sender as a friend.
    final friendship = await db
        .collection('users')
        .doc(recipientUid)
        .collection('friends')
        .doc(senderUid)
        .get();
    await senderNotifications().notify(
      recipientId: recipientUid,
      type: NotificationType.directMessage,
      targetId: conversationId,
      suppressBell: friendship.exists,
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

  // --- Hardening: suppression authority + query-window immunity ---

  test('5. the client writes no notification of its own when sending — '
      'suppression is the backend\'s decision', () async {
    // This case asserted a CLIENT-side "fail toward visible" retry until
    // ADR-082: the old direct-write fallback called notify() itself, and
    // retried unsuppressed when the rules rejected a suppressed write.
    // Both halves are gone. `sendDirectMessage` writes the message, and the
    // trigger in functions/notifications/activity.js derives the
    // notification through the Admin SDK — which is not subject to the rule
    // that made the retry necessary, so suppression is decided once, from
    // the recipient's own friends document.
    //
    // What must stay true on this side is that sending writes NOTHING
    // locally: not the message, not the notification.
    await makeFriends();
    final probe = _DenySuppressedNotifications(
      firestore: db,
      auth: authFor(senderUid, 'Sender'),
    );
    final messages = MessageService(
      firestore: db,
      auth: authFor(senderUid, 'Sender'),
      notificationService: probe,
      outbox: MessageOutbox(preferences: null, capacity: 4),
    );
    final conversationId = await messages.openOrCreateConversation(
      otherUserId: recipientUid,
      otherDisplayName: 'Recipient',
      otherEmail: '$recipientUid@yovoice.app',
      otherPhotoUrl: '',
    );
    await messages.sendTextMessage(
      conversationId: conversationId,
      recipientId: recipientUid,
      text: 'asymmetric friendship',
    );

    expect(
      probe.suppressBellCalls,
      isEmpty,
      reason: 'the client no longer decides suppression, or writes the '
          'notification at all',
    );
    expect(await rawNotificationDocs(), isEmpty);
    final messageDocs = await db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .get();
    expect(messageDocs.docs, isEmpty);
    expect(
      messages.outbox.unsent,
      hasLength(1),
      reason: 'and the message is queued rather than lost',
    );
  });

  test('6. a flood of suppressed carrier docs cannot crowd legitimate '
      'bell events out of the feed window', () async {
    final own = db
        .collection('users')
        .doc(recipientUid)
        .collection('notifications');

    // Three legitimate bell events, OLDER than everything else — one of
    // them a LEGACY document that predates the routing field entirely.
    await own.doc('legacy-club-invite').set({
      'type': 'clubInvite',
      'actorId': 'someone',
      'actorName': 'Someone',
      'isRead': false,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      // no bellSuppressed field — pre-routing legacy shape
    });
    await own.doc('old-follow').set({
      'type': 'follow',
      'actorId': 'someone',
      'actorName': 'Someone',
      'isRead': false,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
      'bellSuppressed': false,
    });
    await own.doc('old-friend-request').set({
      'type': 'friendRequest',
      'actorId': 'someone-else',
      'actorName': 'Someone Else',
      'isRead': true,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 3)),
      'bellSuppressed': false,
    });

    // 60 newer suppressed friend-DM push carriers — more than the whole
    // 50-item window.
    for (var i = 0; i < 60; i++) {
      await own.doc('carrier-$i').set({
        'type': 'directMessage',
        'actorId': senderUid,
        'actorName': 'Sender',
        'isRead': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 3, 1, 12, i)),
        'bellSuppressed': true,
      });
    }

    // The unread legacy doc sits OUTSIDE the carrier-filled base window;
    // the subscription's legacy normalization stamps it visible, so the
    // indexed query picks it up — await the self-healed emission.
    final feed = await recipientNotifications()
        .watchNotifications()
        .firstWhere(
          (emission) =>
              emission.any((item) => item.id == 'legacy-club-invite'),
        )
        .timeout(const Duration(seconds: 5));
    final ids = feed.map((notification) => notification.id).toSet();
    expect(
      ids.containsAll({'old-follow', 'old-friend-request'}),
      isTrue,
      reason: 'indexed bell-visible query must survive the carrier flood',
    );
    expect(
      feed.any((notification) => notification.bellSuppressed),
      isFalse,
      reason: 'no carrier may ever surface in the bell',
    );

    // And the normalization is durable: the legacy doc now carries the
    // routing field, so it is visible to the indexed query directly.
    final healed = await db
        .collection('users')
        .doc(recipientUid)
        .collection('notifications')
        .doc('legacy-club-invite')
        .get();
    expect(healed.data()?['bellSuppressed'], isFalse);
  });

  test('7. unread bell count stays correct under a carrier flood — it '
      'counts unread bell-visible records, not a windowed remainder',
      () async {
    final own = db
        .collection('users')
        .doc(recipientUid)
        .collection('notifications');

    for (var i = 0; i < 60; i++) {
      await own.doc('carrier-$i').set({
        'type': 'directMessage',
        'actorId': senderUid,
        'actorName': 'Sender',
        'isRead': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 3, 1, 12, i)),
        'bellSuppressed': true,
      });
    }
    await own.doc('unread-visible').set({
      'type': 'follow',
      'actorId': 'someone',
      'actorName': 'Someone',
      'isRead': false,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'bellSuppressed': false,
    });
    await own.doc('unread-legacy').set({
      'type': 'clubInvite',
      'actorId': 'someone',
      'actorName': 'Someone',
      'isRead': false,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
      // legacy: no routing field
    });

    expect(await recipientNotifications().watchUnreadCount().first, 2);
  });
}
