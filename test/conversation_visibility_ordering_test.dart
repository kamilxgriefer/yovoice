import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/direct_conversation_open_intents.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';

/// Tester bug (2026-09-18): people the account had never exchanged a message
/// with appeared at the very top of Chats.
///
/// `openDirectConversation` (`functions/messaging/direct_integrity.js`)
/// creates the conversation root for BOTH participants the moment one of
/// them opens the other's profile, with `lastMessage: ""`,
/// `lastMessageSenderId: ""`, `lastMessageSequence: 0` and
/// `updatedAt = createdAt = now`. `watchConversations` streamed every root
/// and sorted by `updatedAt`, so the person who was merely looked at got an
/// empty "Start a conversation" row hoisted above every real thread.
///
/// The root records no opener, so the client keeps an in-memory,
/// account-scoped set of the conversations it opened from THIS device
/// (`DirectConversationOpenIntents.markOpenedHere`) and shows an empty thread
/// only when it is in that set.
void main() {
  const me = 'me-uid';
  const writer = 'writer-uid';
  const lurker = 'lurker-uid';
  const friend = 'friend-uid';
  const legacy = 'legacy-uid';

  final now = DateTime.utc(2026, 9, 18, 12);

  late FakeFirebaseFirestore db;

  MockFirebaseAuth auth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: me, email: 'me@yovoice.app', displayName: 'Me'),
  );

  /// The exact key set the server writes for a fresh root
  /// (`direct_integrity.js`, `openDirectConversation`), with the preview
  /// fields filled in the way `sendDirectMessage` leaves them.
  Map<String, Object?> root({
    required String other,
    required String otherName,
    required DateTime createdAt,
    required DateTime updatedAt,
    String lastMessage = '',
    String lastMessageSenderId = '',
    int lastMessageSequence = 0,
    List<String> archivedBy = const <String>[],
    List<String> deletedBy = const <String>[],
  }) {
    final participants = <String>[me, other]..sort();
    return <String, Object?>{
      'schemaVersion': 2,
      'pairKey': participants.join('_'),
      'participantIds': participants,
      'participantNames': <String, String>{me: 'Me', other: otherName},
      'participantEmails': <String, String>{me: '', other: ''},
      'participantPhotoUrls': <String, String>{me: '', other: ''},
      'unreadCounts': <String, int>{me: 0, other: 0},
      'readSequences': <String, int>{me: 0, other: 0},
      'typing': <String, Object?>{},
      'archivedBy': archivedBy,
      'mutedBy': <String>[],
      if (deletedBy.isNotEmpty) 'deletedBy': deletedBy,
      'lastMessage': lastMessage,
      'lastMessageId': lastMessageSequence == 0 ? null : 'm$lastMessageSequence',
      'lastMessageSequence': lastMessageSequence,
      'lastMessageType': 'text',
      'lastMessageSenderId': lastMessageSenderId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Future<void> seed() async {
    final conversations = db.collection('conversations');
    // A real thread: one message two hours ago.
    await conversations.doc('dm_writer').set(
      root(
        other: writer,
        otherName: 'Writer',
        createdAt: now.subtract(const Duration(hours: 5)),
        updatedAt: now.subtract(const Duration(hours: 2)),
        lastMessage: 'hello',
        lastMessageSenderId: writer,
        lastMessageSequence: 1,
      ),
    );
    // Someone opened MY profile a moment ago and never wrote. Newest
    // `updatedAt` of all — this is the row the tester saw on top.
    await conversations.doc('dm_lurker').set(
      root(
        other: lurker,
        otherName: 'Lurker',
        createdAt: now,
        updatedAt: now,
      ),
    );
    // A thread I will open myself below: created three hours ago, and its
    // root was touched just now WITHOUT a message.
    await conversations.doc('dm_friend').set(
      root(
        other: friend,
        otherName: 'Friend',
        createdAt: now.subtract(const Duration(hours: 3)),
        updatedAt: now,
      ),
    );
    // A pre-integrity root whose preview text is blank but which carries
    // committed messages (`lastMessageSequence`), four hours ago.
    await conversations.doc('dm_legacy').set(
      root(
        other: legacy,
        otherName: 'Legacy',
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(hours: 4)),
        lastMessageSequence: 3,
      ),
    );
  }

  List<String> ids(List<Conversation> conversations) =>
      conversations.map((c) => c.id).toList(growable: false);

  setUp(() async {
    db = FakeFirebaseFirestore();
    await seed();
  });

  group('watchConversations', () {
    test('hides a message-less thread someone else opened and orders by '
        'last message time, not by updatedAt', () async {
      final service = MessageService(firestore: db, auth: auth());
      addTearDown(service.dispose);

      final first = await service.watchConversations().first;

      expect(
        ids(first),
        <String>['dm_writer', 'dm_legacy'],
        reason:
            'the lurker root has the newest updatedAt and no message; the '
            'legacy root has a blank preview but committed messages',
      );
    });

    test('shows the empty thread THIS account opened, ordered by its '
        'creation time rather than the root touch', () async {
      final service = MessageService(
        firestore: db,
        auth: auth(),
        functions: _OpenFunctions('dm_friend'),
      );
      addTearDown(service.dispose);

      final emissions = <List<Conversation>>[];
      final subscription = service.watchConversations().listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(ids(emissions.last), <String>['dm_writer', 'dm_legacy']);

      final opened = await service.openOrCreateConversation(
        otherUserId: friend,
        otherDisplayName: 'Friend',
        otherEmail: '',
        otherPhotoUrl: '',
      );
      await pumpEventQueue();

      expect(opened, 'dm_friend');
      expect(
        ids(emissions.last),
        <String>['dm_writer', 'dm_friend', 'dm_legacy'],
        reason:
            'my own empty thread is visible, placed by createdAt (3 h ago) '
            'below the 2 h old message and above the 4 h old one — its '
            'updatedAt of "now" must not hoist it; the lurker stays hidden',
      );
    });

    test('an empty thread opened on the legacy client path is shown too',
        () async {
      // No Firebase app at all: `openOrCreateConversation` writes the root
      // itself. That path must register the id exactly like the callable.
      final service = MessageService(firestore: db, auth: auth());
      addTearDown(service.dispose);
      const newcomer = 'newcomer-uid';

      final opened = await service.openOrCreateConversation(
        otherUserId: newcomer,
        otherDisplayName: 'Newcomer',
        otherEmail: '',
        otherPhotoUrl: '',
      );

      final visible = await service.watchConversations().first;
      expect(ids(visible), contains(opened));
      expect(ids(visible), isNot(contains('dm_lurker')));
    });

    test('deleted-for-me and archived filters are unchanged', () async {
      await db.collection('conversations').doc('dm_writer').update({
        'deletedBy': <String>[me],
      });
      await db.collection('conversations').doc('dm_legacy').update({
        'archivedBy': <String>[me],
      });
      final service = MessageService(firestore: db, auth: auth());
      addTearDown(service.dispose);

      expect(ids(await service.watchConversations().first), isEmpty);
      expect(
        ids(await service.watchConversations(includeArchived: true).first),
        <String>['dm_legacy'],
      );
    });
  });

  group('DirectConversationOpenIntents.watchOpenedHere', () {
    test('emits the current set on listen and every later addition', () async {
      final intents = DirectConversationOpenIntents();
      intents.markOpenedHere('a');

      final emissions = <Set<String>>[];
      final subscription = intents.watchOpenedHere().listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(emissions, <Set<String>>[
        <String>{'a'},
      ]);

      intents.markOpenedHere('b');
      intents.markOpenedHere('b'); // idempotent: no second emission
      intents.markOpenedHere(''); // ignored
      await pumpEventQueue();
      expect(emissions.last, <String>{'a', 'b'});
      expect(emissions, hasLength(2));
      expect(intents.wasOpenedHere('b'), isTrue);
      expect(intents.wasOpenedHere('c'), isFalse);
    });
  });

  group('Conversation sort key', () {
    Conversation conversation({
      required String id,
      required DateTime createdAt,
      required DateTime updatedAt,
      String lastMessage = '',
      String lastMessageSenderId = '',
      int lastMessageSequence = 0,
    }) => Conversation(
      id: id,
      participantIds: const <String>[me, writer],
      participantNames: const <String, String>{},
      participantEmails: const <String, String>{},
      participantPhotoUrls: const <String, String>{},
      unreadCounts: const <String, int>{},
      lastMessage: lastMessage,
      lastMessageType: MessageType.text,
      lastMessageSenderId: lastMessageSenderId,
      updatedAt: updatedAt,
      createdAt: createdAt,
      archivedBy: const <String>[],
      mutedBy: const <String>[],
      lastMessageSequence: lastMessageSequence,
    );

    test('hasMessages accepts any of the three server witnesses', () {
      final blank = conversation(id: 'x', createdAt: now, updatedAt: now);
      expect(blank.hasMessages, isFalse);
      expect(
        conversation(
          id: 'x',
          createdAt: now,
          updatedAt: now,
          lastMessage: 'hi',
        ).hasMessages,
        isTrue,
      );
      expect(
        conversation(
          id: 'x',
          createdAt: now,
          updatedAt: now,
          lastMessageSenderId: writer,
        ).hasMessages,
        isTrue,
      );
      expect(
        conversation(
          id: 'x',
          createdAt: now,
          updatedAt: now,
          lastMessageSequence: 1,
        ).hasMessages,
        isTrue,
      );
    });

    test('lastActivityAt is updatedAt with messages and createdAt without',
        () {
      final created = now.subtract(const Duration(hours: 3));
      final empty = conversation(id: 'e', createdAt: created, updatedAt: now);
      final full = conversation(
        id: 'f',
        createdAt: created,
        updatedAt: now,
        lastMessage: 'hi',
      );
      expect(empty.lastActivityAt, created);
      expect(full.lastActivityAt, now);
    });

    test('compareByRecentActivity puts a 2 h old message above an empty '
        'thread whose root was touched just now', () {
      final messaged = conversation(
        id: 'messaged',
        createdAt: now.subtract(const Duration(hours: 5)),
        updatedAt: now.subtract(const Duration(hours: 2)),
        lastMessage: 'hi',
      );
      final touched = conversation(
        id: 'touched',
        createdAt: now.subtract(const Duration(hours: 3)),
        updatedAt: now,
      );
      final sorted = <Conversation>[touched, messaged]
        ..sort(Conversation.compareByRecentActivity);
      expect(sorted.map((c) => c.id), <String>['messaged', 'touched']);

      // Ties: newer creation first, then id, so snapshots never flicker.
      final a = conversation(id: 'a', createdAt: now, updatedAt: now);
      final b = conversation(id: 'b', createdAt: now, updatedAt: now);
      final older = conversation(
        id: 'older',
        createdAt: now.subtract(const Duration(minutes: 1)),
        updatedAt: now,
      );
      final tied = <Conversation>[b, older, a]
        ..sort(Conversation.compareByRecentActivity);
      expect(tied.map((c) => c.id), <String>['a', 'b', 'older']);
    });

    test('fromFirestore reads lastMessageSequence and tolerates junk',
        () async {
      await db.collection('conversations').doc('junk').set(
        root(
          other: writer,
          otherName: 'Writer',
          createdAt: now,
          updatedAt: now,
        )..['lastMessageSequence'] = -4,
      );
      await db.collection('conversations').doc('missing').set(
        root(
          other: writer,
          otherName: 'Writer',
          createdAt: now,
          updatedAt: now,
        )..remove('lastMessageSequence'),
      );
      final junk = Conversation.fromFirestore(
        await db.collection('conversations').doc('junk').get(),
      );
      final missing = Conversation.fromFirestore(
        await db.collection('conversations').doc('missing').get(),
      );
      final legacyRoot = Conversation.fromFirestore(
        await db.collection('conversations').doc('dm_legacy').get(),
      );
      expect(junk.lastMessageSequence, 0);
      expect(missing.lastMessageSequence, 0);
      expect(legacyRoot.lastMessageSequence, 3);
      expect(
        legacyRoot.withParticipantIdentity(
          userId: legacy,
          displayName: 'Renamed',
          photoUrl: '',
        ).lastMessageSequence,
        3,
      );
      expect(legacyRoot.withUnreadCountFor(me, 2).lastMessageSequence, 3);
    });
  });
}

/// Stands in for the deployed `openDirectConversation`: answers with the
/// canonical id and touches no documents, exactly like the server does when
/// the root already exists.
class _OpenFunctions implements FirebaseFunctions {
  _OpenFunctions(this.conversationId);

  final String conversationId;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub(
        (_) async => <Object?, Object?>{
          'conversationId': conversationId,
          'created': false,
        },
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
