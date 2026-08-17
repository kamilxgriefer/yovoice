import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

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
    test('the fallback leaves exactly one message, one unread increment '
        'and one conversation summary', () async {
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _UnavailableFunctions('unimplemented'),
      );

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'the callable is gone',
      );

      final docs = await messageDocs();
      expect(docs, hasLength(1));
      expect(docs.single.data()['content'], 'the callable is gone');
      expect(docs.single.data()['senderId'], senderId);
      expect(docs.single.data()['readBy'], [senderId]);

      expect(await unreadFor(recipientId), 1);
      expect(await unreadFor(senderId), 0);

      final conversation = await conversationDoc();
      expect(conversation['lastMessage'], 'the callable is gone');
      expect(conversation['lastMessageSenderId'], senderId);
      expect(conversation['lastMessageId'], docs.single.id);
      expect(conversation['lastMessageSequence'], 1);
      expect(conversation['archivedBy'], isEmpty);
      final typing = conversation['typing'] as Map;
      expect((typing[senderId] as Map)['isTyping'], isFalse);
    });

    test('the fallback writes the CANONICAL message shape, so the server '
        'can still edit, delete, react to and reply to it', () async {
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _UnavailableFunctions('unimplemented'),
      );

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'canonical please',
      );

      final data = (await messageDocs()).single.data();
      expect(
        data.keys.toSet(),
        canonicalMessageKeys,
        reason: 'validateMessage() compares an EXACT key set; a fallback '
            'that writes 14 of the 16 keys is the same latent defect as '
            '_publishRecordedMomentLegacy',
      );
      expect(data['schemaVersion'], 2);
      expect(data['sequence'], 1);
      expect(data['type'], 'text');
      expect(data['isDeleted'], isFalse);
      expect(data['mediaUrl'], isNull);
      expect(data['durationSeconds'], isNull);
      expect(data['editedAt'], isNull);
      expect(data['reactions'], isEmpty);
      expect(data['replyToMessageId'], isNull);
      expect(data['replyToSenderId'], isNull);
      expect(data['replyToContent'], isNull);
    });

    test('the fallback advances the sequence monotonically', () async {
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _UnavailableFunctions('unimplemented'),
      );

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'one',
      );
      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'two',
      );

      final docs = await messageDocs();
      expect(docs, hasLength(2));
      expect(
        docs.map((doc) => doc.data()['sequence']).toSet(),
        {1, 2},
      );
      expect(await unreadFor(recipientId), 2);
      expect((await conversationDoc())['lastMessageSequence'], 2);
    });

    test('a fallback reply keeps the full reply linkage the server '
        'validates', () async {
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _UnavailableFunctions('unimplemented'),
      );

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'the original',
      );
      final original = Message.fromFirestore((await messageDocs()).single);

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'the reply',
        replyTo: original,
      );

      final docs = await messageDocs();
      expect(docs, hasLength(2));
      final reply = docs
          .firstWhere((doc) => doc.data()['content'] == 'the reply')
          .data();
      expect(reply.keys.toSet(), canonicalMessageKeys);
      expect(reply['replyToMessageId'], original.id);
      expect(reply['replyToSenderId'], senderId);
      expect(reply['replyToContent'], 'the original');
      expect(await unreadFor(recipientId), 2);
    });

    test('a fallback reply to a very long message truncates the preview '
        'to the 240 characters the server accepts', () async {
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        functions: _UnavailableFunctions('unimplemented'),
      );

      final long = 'a very long original message. ' * 40;
      expect(long.length, greaterThan(240));

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: long,
      );
      final original = Message.fromFirestore((await messageDocs()).single);

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'short reply',
        replyTo: original,
      );

      final reply = (await messageDocs())
          .firstWhere((doc) => doc.data()['content'] == 'short reply')
          .data();
      expect(
        (reply['replyToContent'] as String).length,
        240,
        reason: 'validateMessage rejects replyToContent longer than 240',
      );
      expect(
        reply['replyToContent'],
        long.substring(0, 240),
      );
    });

    test('the legacy notification path still sends exactly one message '
        'and one increment', () async {
      // The `notificationService:` injection is what every other suite
      // uses; it must land on the same single write as the callable path.
      final service = MessageService(
        firestore: db,
        auth: authFor(senderId),
        notificationService: NotificationService(
          firestore: db,
          auth: authFor(senderId),
        ),
      );

      await service.sendTextMessage(
        conversationId: conversationId,
        recipientId: recipientId,
        text: 'legacy path',
      );

      final docs = await messageDocs();
      expect(docs, hasLength(1));
      expect(docs.single.data().keys.toSet(), canonicalMessageKeys);
      expect(await unreadFor(recipientId), 1);
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
