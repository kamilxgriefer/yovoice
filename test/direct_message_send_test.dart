import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_outbox.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';

/// Sending a direct message has TWO paths and they must leave the same
/// single thing behind.
///
/// Every other suite in this repo injects a `NotificationService`, which
/// flips `MessageService` into its legacy mode and makes `_tryCallable`
/// return false without ever calling anything — so the callable-SUCCESS
/// branch had no coverage at all, and shipped writing the message a second
/// time on top of the one the callable had already created. These doubles
/// deliberately go in through `functions:` instead, so both branches are
/// reachable, and every assertion here is about what ends up in Firestore
/// rather than about whether a callable was invoked.
void main() {
  // The outbox persists through SharedPreferences, whose backing store is
  // static. Without a per-test reset one test's queue leaks into the next.
  TestWidgetsFlutterBinding.ensureInitialized();

  const senderId = 'sender-uid';
  const recipientId = 'recipient-uid';
  const conversationId = 'recipient-uid_sender-uid';

  /// The exact key set `functions/messaging/direct_integrity.js`'s
  /// `validateMessage` demands. A message document missing any of these is
  /// one the server refuses to edit, delete, react to, or accept as a
  /// reply target ever again — `data-loss`, "The direct message schema is
  /// not canonical". Both send paths are held to it.
  const canonicalMessageKeys = <String>{
    'content',
    'conversationId',
    'durationSeconds',
    'editedAt',
    'isDeleted',
    'mediaUrl',
    'reactions',
    'readBy',
    'replyToContent',
    'replyToMessageId',
    'replyToSenderId',
    'schemaVersion',
    'senderId',
    'sentAt',
    'sequence',
    'type',
  };

  late FakeFirebaseFirestore db;

  MockFirebaseAuth authFor(String uid) => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: uid, email: '$uid@yovoice.app'),
  );

  Future<void> seedCanonicalConversation() async {
    await db.collection('conversations').doc(conversationId).set({
      'schemaVersion': 2,
      'pairKey': 'recipient-uid_sender-uid',
      'participantIds': [recipientId, senderId],
      'participantNames': {senderId: 'Sender', recipientId: 'Recipient'},
      'participantEmails': {senderId: '', recipientId: ''},
      'participantPhotoUrls': {senderId: '', recipientId: ''},
      'unreadCounts': {senderId: 0, recipientId: 0},
      'readSequences': {senderId: 0, recipientId: 0},
      'typing': <String, dynamic>{},
      'archivedBy': <String>[],
      'mutedBy': <String>[],
      'lastMessage': '',
      'lastMessageId': null,
      'lastMessageSequence': 0,
      'lastMessageType': 'text',
      'lastMessageSenderId': '',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1, 11)),
      'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1, 11)),
    });
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> messageDocs() async {
    final snapshot = await db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .get();
    return snapshot.docs;
  }

  Future<Map<String, dynamic>> conversationDoc() async {
    final snapshot = await db
        .collection('conversations')
        .doc(conversationId)
        .get();
    return snapshot.data() ?? <String, dynamic>{};
  }

  Future<int> unreadFor(String uid) async {
    final counts = (await conversationDoc())['unreadCounts'] as Map?;
    return (counts?[uid] as num?)?.toInt() ?? 0;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = FakeFirebaseFirestore();
    await seedCanonicalConversation();
  });

  group('the callable answers', () {
    test('one send leaves exactly one message, one unread increment and '
        'one conversation summary — the client adds nothing', () async {
      final server = _ServerSendFunctions(db, senderId: senderId);
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: server,
      );

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'hello once',
      );

      final docs = await messageDocs();
      expect(
        docs,
        hasLength(1),
        reason: 'the callable already created the message; the client batch '
            'used to create a second one under an auto-id',
      );
      expect(docs.single.id, server.messageIds.single);
      expect(docs.single.data()['content'], 'hello once');

      expect(
        await unreadFor(recipientId),
        1,
        reason: 'unreadCounts.<recipient> used to be incremented twice',
      );
      expect(await unreadFor(senderId), 0);

      final conversation = await conversationDoc();
      expect(conversation['lastMessageId'], server.messageIds.single);
      expect(conversation['lastMessageSequence'], 1);
      expect(conversation['lastMessage'], 'hello once');
      expect(conversation['lastMessageSenderId'], senderId);
      expect(
        conversation['updatedAt'],
        _ServerSendFunctions.serverClock,
        reason: 'the summary carries the SERVER write; a client batch '
            'landing after it would have stamped its own clock',
      );
    });

    test('the duplication does not compound over a conversation', () async {
      final server = _ServerSendFunctions(db, senderId: senderId);
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: server,
      );

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'first',
      );
      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'second',
      );
      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'third',
      );

      expect(await messageDocs(), hasLength(3));
      expect(await unreadFor(recipientId), 3);
      expect((await conversationDoc())['lastMessageSequence'], 3);
    });

    test('the client contributes no writes of its own', () async {
      // A callable that succeeds without touching Firestore isolates the
      // CLIENT's contribution: whatever is in Firestore afterwards was
      // written by `sendTextMessage` itself, and there must be none of it.
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _SilentSuccessFunctions(),
      );

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'the server owns this',
      );

      expect(await messageDocs(), isEmpty);
      expect(await unreadFor(recipientId), 0);
      final conversation = await conversationDoc();
      expect(conversation['lastMessage'], '');
      expect(conversation['lastMessageId'], isNull);
      expect(conversation['lastMessageSequence'], 0);
    });

    test('a reply routes through the callable with the reply target and '
        'still writes exactly one message', () async {
      final server = _ServerSendFunctions(db, senderId: senderId);
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: server,
      );

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'the original',
      );
      final original = (await messageDocs()).single;

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'the reply',
        replyTo: Message.fromFirestore(original),
      );

      expect(await messageDocs(), hasLength(2));
      expect(await unreadFor(recipientId), 2);
      expect(server.payloads.last['replyToMessageId'], original.id);
    });
  });

  group('the callable is unavailable', () {
    // Until ADR-082 this group asserted that the client wrote the message
    // to Firestore itself. That fallback is gone: it skipped every
    // server-side moderation check at once — activeProfile,
    // assertNotRestricted, assertNotBlocked, the recipient's messagePrivacy
    // and the rate limiter all live inside the callable — so a banned or
    // communication-muted account kept full direct messaging by taking it.
    // The rules now refuse a client-authored message document outright.
    //
    // What replaces it is the whole point: the message must not be lost.
    // These cases assert it is queued, retried under its ORIGINAL requestId,
    // and delivered exactly once.

    test('nothing is written to Firestore and the message is queued '
        'instead', () async {
      final outbox = MessageOutbox(
        preferences: null,
        capacity: 8,
        // Zeroed so a flush in the same tick is due. The backoff
        // itself is proven in its own case below.
        baseBackoff: Duration.zero,
        maxBackoff: Duration.zero,
      );
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _UnavailableFunctions('unimplemented'),
        outbox: outbox,
      );

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'queued not lost',
      );

      expect(
        await messageDocs(),
        isEmpty,
        reason: 'the client must never author a message document',
      );
      expect(await unreadFor(recipientId), 0);

      final queued = outbox.unsent;
      expect(queued, hasLength(1));
      expect(queued.single.text, 'queued not lost');
      expect(queued.single.conversationId, conversationId);
      expect(queued.single.state, OutboxState.retrying);
      expect(queued.single.attempts, 1);
    });

    test('the queued message is delivered when the callable comes back, '
        'exactly once and under its original requestId', () async {
      final outbox = MessageOutbox(
        preferences: null,
        capacity: 8,
        // Zeroed so a flush in the same tick is due. The backoff
        // itself is proven in its own case below.
        baseBackoff: Duration.zero,
        maxBackoff: Duration.zero,
      );
      final unavailable = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _UnavailableFunctions('unimplemented'),
        outbox: outbox,
      );

      await unavailable.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'survives the outage',
      );
      final queuedRequestId = outbox.unsent.single.requestId;

      // Same outbox, a service whose callable now answers.
      final server = _ServerSendFunctions(db, senderId: senderId);
      final restored = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: server,
        outbox: outbox,
      );
      await restored.flushOutbox();

      final docs = await messageDocs();
      expect(docs, hasLength(1), reason: 'delivered exactly once');
      expect(docs.single.data()['content'], 'survives the outage');
      expect(
        docs.single.data().keys.toSet(),
        canonicalMessageKeys,
        reason: 'a queued-then-retried message is still a SERVER-written '
            'message, so it carries the exact key set validateMessage '
            'demands — queueing changes when it is sent, not what is sent',
      );
      expect(await unreadFor(recipientId), 1);
      expect(outbox.entries, isEmpty, reason: 'a delivered message leaves');

      expect(
        server.payloads.single['requestId'],
        queuedRequestId,
        reason: 'the retry MUST reuse the id the message was queued with — '
            'the callable ledger keys on it, so a fresh id would turn a '
            'lost response into a duplicate message',
      );
    });

    test('a retry of a send that actually landed is deduplicated rather '
        'than duplicated', () async {
      // The nastiest real case: the server committed the write and the
      // response was lost. The entry is still queued, so it retries — and
      // must be recognised as a replay.
      final outbox = MessageOutbox(
        preferences: null,
        capacity: 8,
        // Zeroed so a flush in the same tick is due. The backoff
        // itself is proven in its own case below.
        baseBackoff: Duration.zero,
        maxBackoff: Duration.zero,
      );
      final server = _ServerSendFunctions(db, senderId: senderId);
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _LosesTheResponse(server),
        outbox: outbox,
      );

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'landed but unacknowledged',
      );

      // The message really is in Firestore, and the entry really is still
      // queued — the client cannot tell the difference from a failure.
      expect(await messageDocs(), hasLength(1));
      expect(outbox.unsent, hasLength(1));
      final requestId = outbox.unsent.single.requestId;

      // The retry reaches a server that recognises the ledger entry.
      final replaying = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _LedgerAwareFunctions(server, seen: {requestId}),
        outbox: outbox,
      );
      await replaying.flushOutbox();

      expect(
        await messageDocs(),
        hasLength(1),
        reason: 'the replay must not write a second message',
      );
      expect(outbox.entries, isEmpty);
    });

    test('a reply keeps its reply target through the queue', () async {
      await db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc('m_target')
          .set({
            'senderId': recipientId,
            'content': 'the original',
            'isDeleted': false,
          });

      final outbox = MessageOutbox(
        preferences: null,
        capacity: 8,
        // Zeroed so a flush in the same tick is due. The backoff
        // itself is proven in its own case below.
        baseBackoff: Duration.zero,
        maxBackoff: Duration.zero,
      );
      final unavailable = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _UnavailableFunctions('unimplemented'),
        outbox: outbox,
      );

      await unavailable.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'the reply',
        replyTo: Message(
          id: 'm_target',
          conversationId: conversationId,
          senderId: recipientId,
          type: MessageType.text,
          content: 'the original',
          sentAt: DateTime.utc(2026, 3, 1, 11, 30),
          readBy: const [recipientId],
          reactions: const <String, String>{},
        ),
      );

      expect(outbox.unsent.single.replyToMessageId, 'm_target');

      final server = _ServerSendFunctions(db, senderId: senderId);
      await MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: server,
        outbox: outbox,
      ).flushOutbox();

      expect(server.payloads.single['replyToMessageId'], 'm_target');
      final sent = (await messageDocs())
          .firstWhere((entry) => entry.id != 'm_target');
      expect(sent.data()['replyToMessageId'], 'm_target');
      expect(sent.data()['replyToSenderId'], recipientId);
    });

    test('messages leave the queue in the order they were written', () async {
      final outbox = MessageOutbox(
        preferences: null,
        capacity: 8,
        // Zeroed so a flush in the same tick is due. The backoff
        // itself is proven in its own case below.
        baseBackoff: Duration.zero,
        maxBackoff: Duration.zero,
      );
      final unavailable = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _UnavailableFunctions('unimplemented'),
        outbox: outbox,
      );

      for (final text in ['first', 'second', 'third']) {
        await unavailable.sendTextMessage(
          conversationId: conversationId,
          recipientId: recipientId,
          text: text,
        );
      }
      expect(outbox.unsent, hasLength(3));

      final server = _ServerSendFunctions(db, senderId: senderId);
      await MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: server,
        outbox: outbox,
      ).flushOutbox();

      expect(
        server.payloads.map((payload) => payload['text']).toList(),
        ['first', 'second', 'third'],
        reason: 'a conversation that arrives out of order is not the same '
            'conversation',
      );
      expect(outbox.entries, isEmpty);
    });

    test('a failed attempt waits out its backoff instead of hammering '
        'the server', () async {
      // The zeroed backoff used above is a testing convenience; this is the
      // case that proves the real one defers. A retry loop with no delay
      // turns one unreachable server into a denial-of-service from every
      // client that was mid-send.
      final outbox = MessageOutbox(
        preferences: null,
        capacity: 8,
        baseBackoff: const Duration(minutes: 1),
        maxBackoff: const Duration(minutes: 5),
      );
      final unavailable = _UnavailableFunctions('unimplemented');
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: unavailable,
        outbox: outbox,
      );

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'not yet',
      );
      final queued = outbox.unsent.single;
      expect(queued.state, OutboxState.retrying);
      expect(queued.attempts, 1);
      expect(queued.nextAttemptAt, isNotNull);
      expect(queued.nextAttemptAt!.isAfter(DateTime.now()), isTrue);

      expect(
        outbox.due(),
        isEmpty,
        reason: 'nothing is due until the backoff elapses',
      );

      // A flush now is a no-op: the entry stays, untouched, at one attempt.
      final server = _ServerSendFunctions(db, senderId: senderId);
      await MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: server,
        outbox: outbox,
      ).flushOutbox();

      expect(server.payloads, isEmpty);
      expect(outbox.unsent.single.attempts, 1);
    });

    test('the queue is bounded — it refuses rather than growing without '
        'limit', () async {
      final outbox = MessageOutbox(preferences: null, capacity: 2);
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _UnavailableFunctions('unimplemented'),
        outbox: outbox,
      );

      for (final text in ['one', 'two']) {
        await service.sendTextMessage(
          conversationId: conversationId,
          recipientId: recipientId,
          text: text,
        );
      }

      await expectLater(
        service.sendTextMessage(
          conversationId: conversationId,
          recipientId: recipientId,
          text: 'over the limit',
        ),
        throwsA(isA<OutboxFullException>()),
        reason: 'an unbounded queue turns a long outage into unbounded '
            'storage and a rate-limit burst on reconnect; refusing while '
            'the person can still see what they typed is the honest failure',
      );
      expect(outbox.entries, hasLength(2));
      expect(await messageDocs(), isEmpty);
    });

    test('retrying gives up after a bounded number of attempts and the '
        'message becomes Failed, not silently dropped', () async {
      final outbox = MessageOutbox(
        preferences: null,
        capacity: 8,
        maxAttempts: 3,
        baseBackoff: Duration.zero,
        maxBackoff: Duration.zero,
      );
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _UnavailableFunctions('unimplemented'),
        outbox: outbox,
      );

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'never lands',
      );
      for (var attempt = 0; attempt < 5; attempt++) {
        await service.flushOutbox();
      }

      expect(outbox.unsent, isEmpty);
      expect(outbox.failed, hasLength(1));
      final failed = outbox.failed.single;
      expect(failed.state, OutboxState.failed);
      expect(failed.attempts, 3);
      expect(
        failed.text,
        'never lands',
        reason: 'a failed message still holds what was written, so it can '
            'be retried by hand or copied out',
      );
    });

    test('a message the automatic loop gave up on can be retried by hand, '
        'keeping its original requestId', () async {
      final outbox = MessageOutbox(
        preferences: null,
        capacity: 8,
        maxAttempts: 1,
        baseBackoff: Duration.zero,
        maxBackoff: Duration.zero,
      );
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _UnavailableFunctions('unimplemented'),
        outbox: outbox,
      );
      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'retry me',
      );
      expect(outbox.failed, hasLength(1));
      final originalRequestId = outbox.failed.single.requestId;

      final server = _ServerSendFunctions(db, senderId: senderId);
      final restored = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: server,
        outbox: outbox,
      );
      await restored.retryFailedMessage(outbox.failed.single.id);

      expect(await messageDocs(), hasLength(1));
      expect(server.payloads.single['requestId'], originalRequestId);
      expect(outbox.entries, isEmpty);
    });
  });

  group('the callable refuses', () {
    test('not-found is a REFUSAL, not an absence — nothing is written '
        'locally', () async {
      // This case used to assert the opposite: that `not-found` fell back
      // "the same way as an unimplemented one". It encoded the defect.
      // The server throws `not-found` itself, routinely — guards.js:157
      // when `users/{uid}` is missing, direct_integrity.js:83 and :223.
      // Treating it as "not deployed" let a user with no profile document
      // bypass assertNotBlocked, assertNotRestricted and the rate limits
      // on every messaging callable. The ambiguity is irreducible (an
      // undeployed callable is HTTP 404 -> NOT_FOUND too), so `not-found`
      // must fail closed. See ADR-062.
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _UnavailableFunctions('not-found'),
      );

      await expectLater(
        service.sendTextMessage(
          conversationId: conversationId,
          recipientId: recipientId,
          text: 'not deployed',
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );

      expect(await messageDocs(), isEmpty);
      expect(await unreadFor(recipientId), 0);
      final conversation = await conversationDoc();
      expect(conversation['lastMessage'], '');
      expect(conversation['lastMessageSequence'], 0);
      expect(conversation['lastMessageId'], isNull);
    });

    test("a not-found carrying the SERVER's own message is not mistaken "
        'for an undeployed callable', () async {
      // The reason lives in the test: this is verbatim what
      // `conversationParticipants` (direct_integrity.js:83) throws when
      // the conversation document is missing. Nothing about it says
      // "deploy me".
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _UnavailableFunctions(
          'not-found',
          message: 'The direct conversation does not exist.',
        ),
      );

      await expectLater(
        service.sendTextMessage(
          conversationId: conversationId,
          recipientId: recipientId,
          text: 'the server said no',
        ),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (error) => error.message,
            'message',
            'The direct conversation does not exist.',
          ),
        ),
      );

      expect(await messageDocs(), isEmpty);
      expect(await unreadFor(recipientId), 0);
      expect((await conversationDoc())['lastMessage'], '');
    });

    test('a rejection propagates and nothing is written locally', () async {
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _RejectingFunctions(),
      );

      await expectLater(
        service.sendTextMessage(
          conversationId: conversationId,
          recipientId: recipientId,
          text: 'not allowed',
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );

      expect(
        await messageDocs(),
        isEmpty,
        reason: 'a refused send must not leave a half-written message',
      );
      expect(await unreadFor(recipientId), 0);
      expect((await conversationDoc())['lastMessage'], '');
    });

    test('empty text never reaches the callable or Firestore', () async {
      final server = _ServerSendFunctions(db, senderId: senderId);
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: server,
      );

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: '   ',
      );

      expect(server.payloads, isEmpty);
      expect(await messageDocs(), isEmpty);
      expect(await unreadFor(recipientId), 0);
    });
  });
}

/// Stands in for the DEPLOYED `sendDirectMessage` callable by doing what
/// `functions/messaging/direct_integrity.js` does: it writes the canonical
/// message document and the conversation summary itself. That is what
/// makes "exactly one message document" a meaningful assertion — the
/// server's write is really in Firestore, so a client write on top of it
/// shows up as a second document rather than as a missing one.
class _ServerSendFunctions implements FirebaseFunctions {
  _ServerSendFunctions(this.db, {required this.senderId});

  /// A fixed clock so a client summary write landing afterwards is
  /// detectable in `updatedAt`.
  static final Timestamp serverClock = Timestamp.fromDate(
    DateTime.utc(2026, 3, 1, 12),
  );

  final FakeFirebaseFirestore db;
  final String senderId;
  final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[];
  final List<String> messageIds = <String>[];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((parameters) => _send(name, parameters));

  Future<Map<String, Object?>> _send(String name, Object? parameters) async {
    if (name != 'sendDirectMessage') {
      throw FirebaseFunctionsException(
        code: 'not-found',
        message: 'Unexpected callable $name.',
      );
    }

    final payload = Map<String, dynamic>.from(parameters as Map);
    payloads.add(payload);

    final conversationId = payload['conversationId'] as String;
    final text = payload['text'] as String;
    final replyToMessageId = payload['replyToMessageId'] as String?;
    final conversation = db.collection('conversations').doc(conversationId);
    final snapshot = await conversation.get();
    final data = snapshot.data() ?? <String, dynamic>{};
    final sequence =
        ((data['lastMessageSequence'] as num?)?.toInt() ?? 0) + 1;
    final messageId = 'm_server_$sequence';
    messageIds.add(messageId);

    String? replyToSenderId;
    String? replyToContent;
    if (replyToMessageId != null) {
      final target = await conversation
          .collection('messages')
          .doc(replyToMessageId)
          .get();
      replyToSenderId = target.data()?['senderId'] as String?;
      replyToContent = target.data()?['content'] as String?;
    }

    await conversation.collection('messages').doc(messageId).set({
      'schemaVersion': 2,
      'sequence': sequence,
      'conversationId': conversationId,
      'senderId': senderId,
      'type': 'text',
      'content': text,
      'mediaUrl': null,
      'durationSeconds': null,
      'sentAt': serverClock,
      'readBy': [senderId],
      'reactions': <String, String>{},
      'isDeleted': false,
      'editedAt': null,
      'replyToMessageId': replyToMessageId,
      'replyToSenderId': replyToSenderId,
      'replyToContent': replyToContent,
    });

    final unreadCounts = Map<String, dynamic>.from(
      data['unreadCounts'] as Map? ?? const <String, dynamic>{},
    );
    unreadCounts[senderId] = 0;
    for (final uid in unreadCounts.keys) {
      if (uid != senderId) {
        unreadCounts[uid] = ((unreadCounts[uid] as num?)?.toInt() ?? 0) + 1;
      }
    }

    await conversation.update({
      'lastMessage': text,
      'lastMessageId': messageId,
      'lastMessageSequence': sequence,
      'lastMessageType': 'text',
      'lastMessageSenderId': senderId,
      'updatedAt': serverClock,
      'archivedBy': <String>[],
      'unreadCounts': unreadCounts,
      'typing': {
        senderId: {'isTyping': false, 'updatedAt': serverClock},
      },
    });

    return {'conversationId': conversationId, 'messageId': messageId};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Succeeds without writing anything, so a test can attribute every
/// document in Firestore to the client.
class _SilentSuccessFunctions implements FirebaseFunctions {
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((_) async => <String, Object?>{'ok': true});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Throws a chosen status code. With `unimplemented` that means the
/// callable is not deployed — the only reason the client fallback exists.
/// With `not-found` it means the deployed server refused, which is a very
/// different thing and must NOT fall back (ADR-062).
/// Commits the write the way the real server would, then loses the response.
///
/// This is the failure the idempotency ledger exists for: the client cannot
/// distinguish "never arrived" from "arrived and the acknowledgement was
/// dropped", so it retries — and a retry that wrote a second message would
/// be worse than the failure it was recovering from.
class _LosesTheResponse implements FirebaseFunctions {
  _LosesTheResponse(this.inner);

  final _ServerSendFunctions inner;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((parameters) async {
        await inner.httpsCallable(name).call(parameters);
        throw FirebaseFunctionsException(
          code: 'unavailable',
          message: 'The response never arrived.',
        );
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A server that remembers which requestIds it has already committed.
///
/// Mirrors `assertLedgerReplay` in
/// `functions/messaging/direct_integrity.js`: a repeat of a known requestId
/// returns the original outcome instead of writing again.
class _LedgerAwareFunctions implements FirebaseFunctions {
  _LedgerAwareFunctions(this.inner, {required this.seen});

  final _ServerSendFunctions inner;
  final Set<String> seen;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((parameters) async {
        final payload = Map<String, dynamic>.from(parameters as Map);
        final requestId = payload['requestId'] as String;
        if (seen.contains(requestId)) {
          // Replay: acknowledged, nothing written.
          return <String, Object?>{'replayed': true};
        }
        seen.add(requestId);
        return (await inner.httpsCallable(name).call(parameters)).data;
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnavailableFunctions implements FirebaseFunctions {
  _UnavailableFunctions(this.code, {this.message = 'The callable is unavailable.'});

  final String code;
  final String message;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub(
        (_) async => throw FirebaseFunctionsException(
          code: code,
          message: message,
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The callable answered — with a refusal. Not a reason to fall back.
class _RejectingFunctions implements FirebaseFunctions {
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub(
        (_) async => throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'You cannot message this person.',
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CallableStub implements HttpsCallable {
  _CallableStub(this.handler);

  final Future<Object?> Function(Object? parameters) handler;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async {
    final result = await handler(parameters);
    return _CallableResult<T>(result as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CallableResult<T> implements HttpsCallableResult<T> {
  _CallableResult(this.data);

  @override
  final T data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
