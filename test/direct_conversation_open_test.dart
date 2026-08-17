import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/notifications/data/services/notification_service.dart';

/// Opening a direct conversation has exactly ONE production path, and the
/// client is not on it.
///
/// A canonical MESSAGE asserts only what the client owns — its own
/// `senderId`, its own content — which is why the send fallback can
/// legitimately write the exact 16-key canonical shape itself. A
/// conversation ROOT asserts three things the client does not own: the
/// other participant's server-derived display name and photo
/// (`canonicalPublicProfile`, ADR-054), BOTH participants' `unreadCounts`
/// and `readSequences` cursors, and — through
/// `directConversationPairs/{pairKey}` — which document id is THE thread
/// for that pair, forever. So when `openDirectConversation` ANSWERS, its
/// answer stands, success or failure. See ADR-062.
///
/// Following the seam this repo already established in
/// `direct_message_send_test.dart`: inject through `functions:` and assert
/// on what lands in `FakeFirebaseFirestore`, never on call counts.
void main() {
  const callerId = 'caller-uid';
  const otherUserId = 'other-uid';

  /// The exact key set `validateConversation`
  /// (`functions/messaging/direct_integrity.js:127-146`) demands of a
  /// conversation root. Mirrors `canonicalMessageKeys` in
  /// `direct_message_send_test.dart`. Anything the client writes is held
  /// against this to show it can never satisfy it.
  const canonicalConversationKeys = <String>{
    'archivedBy',
    'createdAt',
    'lastMessage',
    'lastMessageId',
    'lastMessageSenderId',
    'lastMessageSequence',
    'lastMessageType',
    'mutedBy',
    'pairKey',
    'participantEmails',
    'participantIds',
    'participantNames',
    'participantPhotoUrls',
    'readSequences',
    'schemaVersion',
    'typing',
    'unreadCounts',
    'updatedAt',
  };

  late FakeFirebaseFirestore db;

  MockFirebaseAuth authFor(String uid) => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(
      uid: uid,
      email: '$uid@yovoice.app',
      displayName: 'Caller Name',
    ),
  );

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  conversationDocs() async =>
      (await db.collection('conversations').get()).docs;

  Future<String> open(MessageService service) => service.openOrCreateConversation(
    otherUserId: otherUserId,
    otherDisplayName: 'Other Person',
    otherEmail: 'other@yovoice.app',
    otherPhotoUrl: 'https://cdn.example/other.jpg',
  );

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  group('the callable answers', () {
    test('its conversationId is returned verbatim and the client writes '
        'NOTHING', () async {
      // The double touches no documents, so anything at all in Firestore
      // afterwards is attributable to the client.
      final service = MessageService(
        firestore: db,
        auth: authFor(callerId),
        functions: _SilentOpenFunctions('dm_9f2c1ab4d7e64c0a'),
      );

      expect(await open(service), 'dm_9f2c1ab4d7e64c0a');
      expect(
        await conversationDocs(),
        isEmpty,
        reason: 'the server owns the root; the client may not author one',
      );
    });

    test('the returned id is not second-guessed against the legacy '
        'deterministic id', () async {
      // The server binds the pair to whatever id it chooses — including a
      // legacy `uidA_uidB` root it adopted IN PLACE rather than forking.
      // The client must accept it as given.
      final legacyId = MessageService.buildConversationId(
        callerId,
        otherUserId,
      );
      final service = MessageService(
        firestore: db,
        auth: authFor(callerId),
        functions: _SilentOpenFunctions(legacyId),
      );

      expect(await open(service), legacyId);
      expect(await conversationDocs(), isEmpty);
    });
  });

  group('the callable refuses', () {
    /// Every one of these is a REFUSAL from a deployed server. None of
    /// them may be answered by writing a conversation root locally.
    for (final code in <String>[
      'not-found',
      'unimplemented',
      'permission-denied',
      'failed-precondition',
      'unavailable',
    ]) {
      test('$code rethrows and no conversation is created', () async {
        final service = MessageService(
          firestore: db,
          auth: authFor(callerId),
          functions: _ThrowingFunctions(code),
        );

        await expectLater(
          open(service),
          throwsA(
            isA<FirebaseFunctionsException>().having(
              (error) => error.code,
              'code',
              code,
            ),
          ),
        );

        expect(
          await conversationDocs(),
          isEmpty,
          reason: 'a refused open must not leave a root the server will '
              'reject forever',
        );
      });
    }

    test('not-found in particular — the regression this suite exists for '
        '— creates nothing', () async {
      // `not-found` is thrown by the server itself: guards.js:157 when
      // `users/{uid}` is missing, direct_integrity.js:83 when the
      // conversation is missing. It was read as "the callable is not
      // deployed", which sent the client down a local transaction that
      // wrote a root with no `directConversationPairs` guard — a thread
      // `validateConversation` then refuses permanently.
      final service = MessageService(
        firestore: db,
        auth: authFor(callerId),
        functions: _ThrowingFunctions(
          'not-found',
          message: 'Your profile does not exist.',
        ),
      );

      await expectLater(open(service), throwsA(isA<FirebaseFunctionsException>()));

      expect(await conversationDocs(), isEmpty);
      expect(
        (await db.collection('directConversationPairs').get()).docs,
        isEmpty,
      );
    });
  });

  group('the callable answers malformed', () {
    for (final entry in <String, Map<String, Object?>>{
      'an empty payload': <String, Object?>{},
      'an empty conversationId': <String, Object?>{'conversationId': ''},
      'a non-string conversationId': <String, Object?>{'conversationId': 42},
      'a null conversationId': <String, Object?>{'conversationId': null},
    }.entries) {
      test('${entry.key} throws StateError and writes nothing', () async {
        final service = MessageService(
          firestore: db,
          auth: authFor(callerId),
          functions: _RawOpenFunctions(entry.value),
        );

        await expectLater(open(service), throwsA(isA<StateError>()));
        expect(
          await conversationDocs(),
          isEmpty,
          reason: 'a malformed answer is still an answer — not a licence to '
              'write the root locally',
        );
      });
    }
  });

  group('no server exists', () {
    // The legacy transaction is not dead code: unit tests and previews run
    // with no Firebase app at all, and `notificationService:` injection
    // keeps the legacy harness working. Both are guarded elsewhere —
    // `test/public_profile_privacy_test.dart:149` depends on the first.
    test('with no Firebase app the legacy transaction still runs', () async {
      final service = MessageService(firestore: db, auth: authFor(callerId));

      final conversationId = await open(service);

      expect(
        conversationId,
        MessageService.buildConversationId(callerId, otherUserId),
      );
      final docs = await conversationDocs();
      expect(docs, hasLength(1));
      expect(docs.single.id, conversationId);
      expect(docs.single.data()['participantIds'], contains(callerId));
    });

    test('with a notificationService injected the legacy transaction still '
        'runs', () async {
      final service = MessageService(
        firestore: db,
        auth: authFor(callerId),
        notificationService: NotificationService(
          firestore: db,
          auth: authFor(callerId),
        ),
        // Present AND deployed — the legacy harness must still win, or
        // every existing suite changes behaviour.
        functions: _SilentOpenFunctions('dm_should_not_be_used'),
      );

      final conversationId = await open(service);

      expect(
        conversationId,
        MessageService.buildConversationId(callerId, otherUserId),
      );
      expect(await conversationDocs(), hasLength(1));
    });

    test('re-opening an existing conversation only clears the caller from '
        'archivedBy', () async {
      final service = MessageService(firestore: db, auth: authFor(callerId));
      final conversationId = await open(service);
      final reference = db.collection('conversations').doc(conversationId);

      await reference.update({
        'archivedBy': [callerId, otherUserId],
        'lastMessage': 'an earlier message',
        'lastMessageType': 'text',
        'lastMessageSenderId': otherUserId,
        'unreadCounts': {callerId: 3, otherUserId: 0},
      });
      final before = (await reference.get()).data()!;

      expect(await open(service), conversationId);

      final after = (await reference.get()).data()!;
      expect(after['archivedBy'], [otherUserId]);
      expect(after['unreadCounts'], before['unreadCounts']);
      expect(after['lastMessage'], 'an earlier message');
      expect(after['lastMessageSenderId'], otherUserId);
      expect(after['updatedAt'], before['updatedAt']);
      expect(after['createdAt'], before['createdAt']);
      expect(after.keys.toSet(), before.keys.toSet());
      expect(await conversationDocs(), hasLength(1));
    });

    test('the legacy root is deliberately NOT canonical — a strict subset '
        'of what validateConversation demands', () async {
      // Stated here so nobody "fixes" the legacy path by making it write
      // the canonical shape. It could not work anyway: the missing piece
      // is not the key set, it is `directConversationPairs/{pairKey}`,
      // which has NO rules match block and so is default-denied to every
      // client. A root without its pair guard fails
      // `validateConversation` with data-loss, "The canonical
      // conversation is missing.", on every server call thereafter. This
      // document may only exist where no server does.
      final service = MessageService(firestore: db, auth: authFor(callerId));
      await open(service);

      final keys = (await conversationDocs()).single.data().keys.toSet();

      expect(
        canonicalConversationKeys.containsAll(keys),
        isTrue,
        reason: 'the legacy root must not invent keys the server rejects',
      );
      expect(
        keys,
        isNot(equals(canonicalConversationKeys)),
        reason: 'and it must not pretend to be canonical either',
      );
      expect(
        canonicalConversationKeys.difference(keys),
        <String>{
          'pairKey',
          'schemaVersion',
          'readSequences',
          'participantEmails',
          'lastMessageId',
          'lastMessageSequence',
        },
      );
    });
  });

  group('the guard clauses still come first', () {
    test('opening a conversation with yourself is refused before any '
        'callable or write', () async {
      final service = MessageService(
        firestore: db,
        auth: authFor(callerId),
        functions: _ThrowingFunctions('permission-denied'),
      );

      await expectLater(
        service.openOrCreateConversation(
          otherUserId: callerId,
          otherDisplayName: 'Myself',
          otherEmail: 'me@yovoice.app',
          otherPhotoUrl: '',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await conversationDocs(), isEmpty);
    });

    test('a signed-out caller is refused before any callable or write',
        () async {
      final service = MessageService(
        firestore: db,
        auth: MockFirebaseAuth(),
        functions: _ThrowingFunctions('permission-denied'),
      );

      await expectLater(open(service), throwsA(isA<StateError>()));
      expect(await conversationDocs(), isEmpty);
    });
  });
}

/// Stands in for the DEPLOYED `openDirectConversation` by answering with a
/// conversation id and touching no documents — so every document in
/// Firestore is attributable to the client.
class _SilentOpenFunctions implements FirebaseFunctions {
  _SilentOpenFunctions(this.conversationId);

  final String conversationId;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub(
        (_) async => <Object?, Object?>{
          'conversationId': conversationId,
          'created': true,
        },
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Answers with an arbitrary payload, for the malformed-response cases.
class _RawOpenFunctions implements FirebaseFunctions {
  _RawOpenFunctions(this.payload);

  final Map<String, Object?> payload;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((_) async => Map<Object?, Object?>.from(payload));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A deployed server that refused. Never a reason to write the root
/// locally, whatever the status code.
class _ThrowingFunctions implements FirebaseFunctions {
  _ThrowingFunctions(this.code, {this.message = 'The server refused.'});

  final String code;
  final String message;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub(
        (_) async =>
            throw FirebaseFunctionsException(code: code, message: message),
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
