import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/core/theme/app_theme.dart';
import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_outbox.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_payload_store.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

/// Deleting a chat.
///
/// The semantics under test, in one line: it goes for the deleter only, the
/// other participant is untouched, and a thread that comes back comes back
/// EMPTY of everything the deleter removed. The last part is the one worth
/// pinning — a "deleted" chat that quietly returns carrying its old messages
/// is not a bug, it is the privacy promise broken.
void main() {
  const currentUserId = 'me-uid';
  const otherUserId = 'them-uid';
  const conversationId = 'me-uid_them-uid';

  const narrow = Size(390, 844);
  const tablet = Size(834, 1112);
  const wide = Size(1440, 900);

  late PublicIdentityRepository originalIdentityRepository;

  Widget host(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.darkTheme,
    home: child,
  );

  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Conversation conversationFor() => Conversation(
    id: conversationId,
    participantIds: const [currentUserId, otherUserId],
    participantNames: const {currentUserId: 'Me', otherUserId: 'Them'},
    participantEmails: const {currentUserId: '', otherUserId: ''},
    participantPhotoUrls: const {currentUserId: '', otherUserId: ''},
    unreadCounts: const {currentUserId: 0, otherUserId: 0},
    lastMessage: 'See you tomorrow',
    lastMessageType: MessageType.text,
    lastMessageSenderId: otherUserId,
    updatedAt: DateTime.utc(2026, 3, 1, 12),
    createdAt: DateTime.utc(2026, 2, 1, 12),
    archivedBy: const <String>[],
    mutedBy: const <String>[],
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    originalIdentityRepository = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: currentUserId),
      ),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentityRepository;
  });

  Future<void> pumpMessages(
    WidgetTester tester,
    _StubMessageService service, {
    required Size size,
    Locale locale = const Locale('en'),
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    useSurface(tester, size);
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: MessagesScreen(
              messageService: service,
              friendService: _EmptyFriendService(),
              auth: MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(uid: currentUserId),
              ),
            ),
          ),
        ),
        locale: locale,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openRowActions(WidgetTester tester) async {
    await tester.longPress(find.text('Them'));
    await tester.pumpAndSettle();
  }

  group('chat list row', () {
    testWidgets('offers Delete alongside Archive and confirms before acting', (
      tester,
    ) async {
      final service = _StubMessageService(
        conversations: [conversationFor()],
      );
      await pumpMessages(tester, service, size: narrow);
      await openRowActions(tester);

      expect(find.byKey(const ValueKey('conversation-archive-action')), findsOne);
      expect(find.byKey(const ValueKey('conversation-delete-action')), findsOne);
      // The row itself has to say the scope, before the dialog does.
      expect(find.text('Removes it for you only'), findsOne);

      await tester.tap(find.byKey(const ValueKey('conversation-delete-action')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('conversation-delete-dialog')), findsOne);
      // Nothing has happened yet.
      expect(service.deleted, isEmpty);
      expect(
        find.textContaining('for you only'),
        findsOne,
        reason: 'the confirmation must state that only this copy goes',
      );
      expect(find.textContaining('Them keeps their copy'), findsOne);
      expect(
        find.textContaining('the new messages only'),
        findsOne,
        reason: 'the revive semantics belong in the confirmation, not a doc',
      );
    });

    testWidgets('cancel leaves the conversation exactly where it was', (
      tester,
    ) async {
      final service = _StubMessageService(
        conversations: [conversationFor()],
      );
      await pumpMessages(tester, service, size: narrow);
      await openRowActions(tester);
      await tester.tap(find.byKey(const ValueKey('conversation-delete-action')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('conversation-delete-cancel')));
      await tester.pumpAndSettle();

      expect(service.deleted, isEmpty);
      expect(find.byKey(const ValueKey('conversation-delete-dialog')), findsNothing);
      expect(find.text('Them'), findsOne);
    });

    testWidgets('confirming removes the row and reports success', (
      tester,
    ) async {
      final service = _StubMessageService(
        conversations: [conversationFor()],
      );
      await pumpMessages(tester, service, size: narrow);
      await openRowActions(tester);
      await tester.tap(find.byKey(const ValueKey('conversation-delete-action')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('conversation-delete-confirm')),
      );
      await tester.pumpAndSettle();

      expect(service.deleted, [conversationId]);
      // The production stream drops a conversation the account deleted; the
      // stub replays that by emitting the list without it.
      expect(find.text('Them'), findsNothing);
      expect(find.text('Chat deleted for you.'), findsOne);
    });

    testWidgets('a refused delete says so instead of pretending it worked', (
      tester,
    ) async {
      final service = _StubMessageService(
        conversations: [conversationFor()],
        // An unmapped code, so the flow's OWN fallback copy is what has to
        // reach the screen rather than a generic mapping that would pass
        // this test without the handler existing.
        deleteFailure: FirebaseFunctionsException(
          code: 'internal',
          message: 'The delete never committed.',
        ),
      );
      await pumpMessages(tester, service, size: narrow);
      await openRowActions(tester);
      await tester.tap(find.byKey(const ValueKey('conversation-delete-action')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('conversation-delete-confirm')),
      );
      await tester.pumpAndSettle();

      expect(service.deleted, [conversationId]);
      expect(find.text('Chat deleted for you.'), findsNothing);
      expect(find.textContaining('Could not delete'), findsOne);
      // Still there. A failed delete that hid the row would be the worst
      // outcome of all: it would look exactly like success.
      expect(find.text('Them'), findsOne);
    });

    testWidgets('Polish copy carries the same for-you-only promise', (
      tester,
    ) async {
      final service = _StubMessageService(
        conversations: [conversationFor()],
      );
      await pumpMessages(
        tester,
        service,
        size: narrow,
        locale: const Locale('pl'),
      );
      await openRowActions(tester);

      expect(find.text('Usuń czat'), findsOne);
      expect(find.text('Usuwa tylko u Ciebie'), findsOne);

      await tester.tap(find.byKey(const ValueKey('conversation-delete-action')));
      await tester.pumpAndSettle();

      expect(find.text('Usunąć czat?'), findsOne);
      expect(find.textContaining('tylko u Ciebie'), findsOne);
    });

    for (final entry in <String, Size>{
      'phone': narrow,
      'tablet': tablet,
      'desktop': wide,
    }.entries) {
      testWidgets('${entry.key} reaches Delete and confirms without overflow', (
        tester,
      ) async {
        final service = _StubMessageService(
          conversations: [conversationFor()],
        );
        await pumpMessages(tester, service, size: entry.value);
        await openRowActions(tester);
        await tester.tap(
          find.byKey(const ValueKey('conversation-delete-action')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('conversation-delete-dialog')),
          findsOne,
        );
        await tester.tap(
          find.byKey(const ValueKey('conversation-delete-confirm')),
        );
        await tester.pumpAndSettle();
        expect(service.deleted, [conversationId]);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('the actions sheet still reaches Delete at 200% text', (
    tester,
  ) async {
    // Three rows, one of them two-line, on a small phone: the sheet has to
    // scroll rather than clip the destructive action out of reach.
    final service = _StubMessageService(conversations: [conversationFor()]);
    await pumpMessages(
      tester,
      service,
      size: narrow,
      textScaler: const TextScaler.linear(2),
    );
    // At this scale the row uses its stacked layout, so the overflow button
    // rather than the name is the layout-independent way in.
    final actions = find.byTooltip('Conversation actions for Them');
    await tester.ensureVisible(actions);
    await tester.pumpAndSettle();
    await tester.tap(actions);
    await tester.pumpAndSettle();

    final deleteAction = find.byKey(
      const ValueKey('conversation-delete-action'),
    );
    expect(deleteAction, findsOne);
    await tester.ensureVisible(deleteAction);
    await tester.pumpAndSettle();
    await tester.tap(deleteAction);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('conversation-delete-dialog')), findsOne);
    expect(tester.takeException(), isNull);
  });

  group('chat screen overflow', () {
    Future<void> pumpChat(
      WidgetTester tester,
      _StubMessageService service, {
      required Size size,
    }) async {
      useSurface(tester, size);
      await tester.pumpWidget(
        host(
          Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                body: ChatScreen(
                  conversationId: conversationId,
                  otherUserId: otherUserId,
                  otherDisplayName: 'Them',
                  otherEmail: '',
                  otherPhotoUrl: '',
                  messageService: service,
                  auth: MockFirebaseAuth(
                    signedIn: true,
                    mockUser: MockUser(uid: currentUserId),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> chooseDelete(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_horiz_rounded).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-delete-action')));
      await tester.pumpAndSettle();
    }

    testWidgets('delete confirms, then closes the thread it removed', (
      tester,
    ) async {
      final service = _StubMessageService(conversations: [conversationFor()]);
      await pumpChat(tester, service, size: narrow);
      await chooseDelete(tester);

      expect(find.byKey(const ValueKey('conversation-delete-dialog')), findsOne);
      await tester.tap(
        find.byKey(const ValueKey('conversation-delete-confirm')),
      );
      await tester.pumpAndSettle();

      expect(service.deleted, [conversationId]);
      expect(find.byType(ChatScreen), findsNothing);
    });

    testWidgets('a refused delete keeps the thread open and explains', (
      tester,
    ) async {
      final service = _StubMessageService(
        conversations: [conversationFor()],
        deleteFailure: FirebaseFunctionsException(
          code: 'internal',
          message: 'The delete never committed.',
        ),
      );
      await pumpChat(tester, service, size: narrow);
      await chooseDelete(tester);
      await tester.tap(
        find.byKey(const ValueKey('conversation-delete-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOne);
      expect(find.textContaining('Could not delete'), findsOne);
      // And the raw server text never reaches the user.
      expect(find.textContaining('never committed'), findsNothing);
    });

    testWidgets('a mapped transport failure still refuses to look like success', (
      tester,
    ) async {
      final service = _StubMessageService(
        conversations: [conversationFor()],
        deleteFailure: FirebaseFunctionsException(
          code: 'unavailable',
          message: 'offline',
        ),
      );
      await pumpChat(tester, service, size: narrow);
      await chooseDelete(tester);
      await tester.tap(
        find.byKey(const ValueKey('conversation-delete-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOne);
      expect(find.byType(SnackBar), findsOne);
      expect(find.textContaining('try again'), findsOne);
    });

    testWidgets('cancel from the thread deletes nothing', (tester) async {
      final service = _StubMessageService(conversations: [conversationFor()]);
      await pumpChat(tester, service, size: narrow);
      await chooseDelete(tester);
      await tester.tap(find.byKey(const ValueKey('conversation-delete-cancel')));
      await tester.pumpAndSettle();

      expect(service.deleted, isEmpty);
      expect(find.byType(ChatScreen), findsOne);
    });
  });

  group('what the deleter can still see', () {
    late FakeFirebaseFirestore firestore;
    late MessageService service;

    Future<void> seedConversation({
      List<String> deletedBy = const <String>[],
      Map<String, int> deletedSequences = const <String, int>{},
      int lastMessageSequence = 0,
    }) async {
      await firestore.collection('conversations').doc(conversationId).set({
        'schemaVersion': 2,
        'participantIds': [currentUserId, otherUserId],
        'participantNames': {currentUserId: 'Me', otherUserId: 'Them'},
        'participantEmails': {currentUserId: '', otherUserId: ''},
        'participantPhotoUrls': {currentUserId: '', otherUserId: ''},
        'unreadCounts': {currentUserId: 0, otherUserId: 0},
        'readSequences': {currentUserId: 0, otherUserId: 0},
        'typing': <String, Object?>{},
        'archivedBy': <String>[],
        'mutedBy': <String>[],
        if (deletedBy.isNotEmpty || deletedSequences.isNotEmpty) ...{
          'deletedBy': deletedBy,
          'deletedSequences': deletedSequences,
        },
        'lastMessage': '',
        'lastMessageId': null,
        'lastMessageSequence': lastMessageSequence,
        'lastMessageType': 'text',
        'lastMessageSenderId': '',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 2, 1)),
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
      });
    }

    Future<void> seedMessage(int sequence, String content) async {
      await firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc('m$sequence')
          .set({
            'schemaVersion': 2,
            'sequence': sequence,
            'conversationId': conversationId,
            'senderId': otherUserId,
            'type': 'text',
            'content': content,
            'mediaUrl': null,
            'durationSeconds': null,
            'sentAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1, sequence)),
            'readBy': <String>[otherUserId],
            'reactions': <String, String>{},
            'isDeleted': false,
            'editedAt': null,
            'replyToMessageId': null,
            'replyToSenderId': null,
            'replyToContent': null,
          });
    }

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = MessageService(
        firestore: firestore,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: currentUserId),
        ),
        functions: _DeleteFunctions(),
      );
    });

    test('with no deletion, every message is visible', () async {
      await seedConversation(lastMessageSequence: 3);
      for (var index = 1; index <= 3; index++) {
        await seedMessage(index, 'message $index');
      }

      final messages = await service.watchMessages(conversationId).first;

      expect(
        messages.map((message) => message.content),
        containsAll(<String>['message 1', 'message 2', 'message 3']),
      );
    });

    test(
      'a revived thread carries the new messages and NOT the deleted history',
      () async {
        // Three messages, deleted through all three, then the other person
        // writes again — which is exactly the case that must not hand the
        // history back.
        await seedConversation(
          deletedBy: const <String>[],
          deletedSequences: const {currentUserId: 3, otherUserId: 0},
          lastMessageSequence: 4,
        );
        for (var index = 1; index <= 3; index++) {
          await seedMessage(index, 'deleted history $index');
        }
        await seedMessage(4, 'are you there?');

        final messages = await service.watchMessages(conversationId).first;

        expect(messages.map((message) => message.content), ['are you there?']);
        expect(
          messages.map((message) => message.content),
          isNot(contains('deleted history 1')),
        );
      },
    );

    test('the OTHER participant keeps the whole thread', () async {
      final theirService = MessageService(
        firestore: firestore,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: otherUserId),
        ),
        functions: _DeleteFunctions(),
      );
      await seedConversation(
        deletedBy: const [currentUserId],
        deletedSequences: const {currentUserId: 2, otherUserId: 0},
        lastMessageSequence: 2,
      );
      await seedMessage(1, 'first');
      await seedMessage(2, 'second');

      final theirs = await theirService.watchMessages(conversationId).first;

      expect(theirs.map((message) => message.content), hasLength(2));
    });

    test('a deleted conversation leaves every list, archived included', () async {
      await firestore.collection('conversations').doc(conversationId).set({
        'participantIds': [currentUserId, otherUserId],
        'participantNames': {currentUserId: 'Me', otherUserId: 'Them'},
        'unreadCounts': {currentUserId: 0, otherUserId: 0},
        'archivedBy': <String>[],
        'mutedBy': <String>[],
        'deletedBy': <String>[currentUserId],
        'deletedSequences': {currentUserId: 2, otherUserId: 0},
        'lastMessage': 'gone',
        'lastMessageType': 'text',
        'lastMessageSenderId': otherUserId,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 2, 1)),
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
      });

      expect(await service.watchConversations().first, isEmpty);
      expect(
        await service.watchConversations(includeArchived: true).first,
        isEmpty,
      );
    });
  });

  group('local state the deleter leaves behind', () {
    test('queued attachments for that chat lose their entry AND their bytes', () async {
      final payloads = _MemoryPayloadStore();
      final attachments = DirectAttachmentOutbox(
        ownerId: currentUserId,
        payloadStore: payloads,
      );
      Future<void> queue(String chatId, String fingerprint) => attachments
          .enqueue(
            fingerprint: fingerprint,
            conversationId: chatId,
            type: MessageType.image,
            contentType: 'image/jpeg',
            durationSeconds: null,
            bytes: Uint8List.fromList(List<int>.filled(64, 7)),
            reserveRequestId: 'reserve-$fingerprint',
            finalizeRequestId: 'finalize-$fingerprint',
          )
          .then((_) {});
      await queue(conversationId, 'doomed');
      await queue('other-chat', 'unrelated');
      final namespace = attachments.accountNamespace;
      expect(await payloads.keys(namespace), hasLength(2));

      await attachments.purgeConversation(conversationId);

      expect(
        attachments.entries.map((entry) => entry.conversationId),
        ['other-chat'],
      );
      expect(
        await payloads.keys(namespace),
        hasLength(1),
        reason: 'private media bytes must not survive on the device',
      );
    });

    test('queued text for that chat is purged', () async {
      final firestore = FakeFirebaseFirestore();
      final attachments = DirectAttachmentOutbox(
        ownerId: currentUserId,
        payloadStore: _MemoryPayloadStore(),
      );
      final service = MessageService(
        firestore: firestore,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: currentUserId),
        ),
        functions: _DeleteFunctions(),
        attachmentOutbox: attachments,
      );
      await service.queueTextMessage(
        conversationId: conversationId,
        recipientId: otherUserId,
        text: 'never going out',
      );
      await service.queueTextMessage(
        conversationId: 'other-chat',
        recipientId: otherUserId,
        text: 'unrelated, must survive',
      );

      await service.deleteConversationForMe(conversationId);

      expect(
        service.outbox.entries.map((entry) => entry.conversationId),
        ['other-chat'],
        reason: 'an unsent message must not resurrect a deleted thread',
      );
    });

    test('a refused delete keeps the queue intact', () async {
      final firestore = FakeFirebaseFirestore();
      final service = MessageService(
        firestore: firestore,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: currentUserId),
        ),
        functions: _DeleteFunctions(
          failure: FirebaseFunctionsException(
            code: 'unavailable',
            message: 'offline',
          ),
        ),
      );
      await service.queueTextMessage(
        conversationId: conversationId,
        recipientId: otherUserId,
        text: 'still mine',
      );

      await expectLater(
        service.deleteConversationForMe(conversationId),
        throwsA(isA<FirebaseFunctionsException>()),
      );

      expect(service.outbox.entries, hasLength(1));
    });

    test('a build without the callable refuses rather than faking it', () async {
      final service = MessageService(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: currentUserId),
        ),
        functions: _DeleteFunctions(
          failure: FirebaseFunctionsException(
            code: 'unimplemented',
            message: 'not deployed',
          ),
        ),
      );

      await expectLater(
        service.deleteConversationForMe(conversationId),
        throwsA(isA<StateError>()),
      );
    });
  });
}

class _StubMessageService extends MessageService {
  _StubMessageService({required List<Conversation> conversations, this.deleteFailure})
    : _conversationState = conversations,
      super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me-uid'),
        ),
      );

  List<Conversation> _conversationState;
  final Object? deleteFailure;
  final List<String> deleted = <String>[];
  final StreamController<List<Conversation>> _conversations =
      StreamController<List<Conversation>>.broadcast();

  @override
  Stream<List<Conversation>> watchConversations({bool includeArchived = false}) {
    return Stream<List<Conversation>>.multi((controller) {
      controller.add(_conversationState);
      final subscription = _conversations.stream.listen(controller.add);
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      Stream<List<Message>>.value(const <Message>[]);

  @override
  Stream<bool> watchTyping({
    required String conversationId,
    required String otherUserId,
  }) => Stream<bool>.value(false);

  @override
  Stream<ChatPresence> watchUserPresence(String userId) =>
      Stream<ChatPresence>.value(
        const ChatPresence(isOnline: false, lastSeen: null),
      );

  @override
  Future<void> markConversationRead(String conversationId) async {}

  @override
  Future<void> deleteConversationForMe(String conversationId) async {
    deleted.add(conversationId);
    final failure = deleteFailure;
    if (failure != null) throw failure;
    // The real stream drops it because the server put this account into
    // `deletedBy`; the stub replays that observable consequence.
    _conversationState = _conversationState
        .where((conversation) => conversation.id != conversationId)
        .toList(growable: false);
    _conversations.add(_conversationState);
  }
}

/// A functions double that accepts (or refuses) exactly the delete callable.
class _DeleteFunctions implements FirebaseFunctions {
  _DeleteFunctions({this.failure});

  final Object? failure;
  final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((parameters) async {
        if (name != 'deleteDirectConversationForMe') {
          throw FirebaseFunctionsException(
            code: 'not-found',
            message: 'Unexpected callable $name.',
          );
        }
        payloads.add(Map<String, dynamic>.from(parameters! as Map));
        final refusal = failure;
        if (refusal != null) throw refusal;
        return <String, Object?>{'conversationId': payloads.last['conversationId']};
      });

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

class _MemoryPayloadStore implements DirectAttachmentPayloadStore {
  final Map<String, Uint8List> _bytes = <String, Uint8List>{};

  String _key(String namespace, String id) => '$namespace/$id';

  @override
  Future<void> clear(String namespace) async {
    _bytes.removeWhere((key, _) => key.startsWith('$namespace/'));
  }

  @override
  Future<void> delete(String namespace, String id) async {
    _bytes.remove(_key(namespace, id));
  }

  @override
  Future<bool> exists(String namespace, String id) async =>
      _bytes.containsKey(_key(namespace, id));

  @override
  Future<Set<String>> keys(String namespace) => Future<Set<String>>.value(
    _bytes.keys
        .where((key) => key.startsWith('$namespace/'))
        .map((key) => key.split('/').last)
        .toSet(),
  );

  @override
  Future<void> write(String namespace, String id, Uint8List bytes) async {
    _bytes[_key(namespace, id)] = bytes;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyFriendService implements FriendService {
  @override
  Stream<List<FriendUser>> watchFriends() =>
      Stream<List<FriendUser>>.value(const <FriendUser>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
