import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/friends/data/models/friend_user.dart';
import 'package:yovoice/features/friends/data/services/friend_service.dart';
import 'package:yovoice/features/messages/data/models/conversation.dart';
import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/message_outbox.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/features/messages/presentation/screens/messages_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

/// A user-visible action that fails must not fail invisibly.
///
/// Reacting to a message, publishing typing presence and un-archiving a
/// conversation were all fired through `unawaited(...)` with no error
/// handling, so a rejection from Firestore or a callable simply
/// evaporated: the tap did nothing and said nothing. That silence is how
/// the duplicate-send defect in `sendTextMessage` survived in production.
///
/// These tests hold each of the three to the project's shared error
/// presentation (`intentionalOrFriendly` / `friendlyErrorMessage`), at
/// narrow, medium and wide widths, and check that the recovery path is
/// still intact afterwards.
void main() {
  const currentUserId = 'me-uid';
  const otherUserId = 'them-uid';
  const conversationId = 'me-uid_them-uid';

  const narrow = Size(390, 844);
  const medium = Size(834, 1112);
  const wide = Size(1440, 900);

  late PublicIdentityRepository originalIdentityRepository;

  Widget host(Widget child) =>
      MaterialApp(theme: ThemeData.dark(useMaterial3: true), home: child);

  void useSurface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Message messageFrom({
    required String id,
    required String senderId,
    required String content,
  }) {
    return Message(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      type: MessageType.text,
      content: content,
      sentAt: DateTime.utc(2026, 3, 1, 12),
      readBy: const [currentUserId],
      reactions: const <String, String>{},
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    // ChatScreen's header resolves identity badges through the shared
    // singleton; point it at a scripted fetcher so no Firebase app is
    // needed and the header settles deterministically.
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

  Future<void> pumpChat(
    WidgetTester tester,
    _StubMessageService service, {
    required Size size,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    useSurface(tester, size);
    await tester.pumpWidget(
      host(
        MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: ChatScreen(
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
    );
    await tester.pumpAndSettle();
  }

  Future<void> sendAndWaitForQueuedMessage(
    WidgetTester tester,
    _StubMessageService service,
  ) async {
    // A tap does not await an async VoidCallback. Subscribe before tapping,
    // then wait for the outbox's post-persistence change notification rather
    // than merely observing the in-memory entry halfway through enqueue().
    final queued = service.outbox.changes.firstWhere(
      (entries) => entries.isNotEmpty,
    );
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.runAsync(() => queued.timeout(const Duration(seconds: 2)));
    await tester.pump();
  }

  Future<void> reactTo(WidgetTester tester, String messageText) async {
    await tester.longPress(find.text(messageText));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🔥'));
    await tester.pumpAndSettle();
  }

  group('a rejected reaction is reported, not swallowed', () {
    for (final entry in <String, Size>{
      'narrow': narrow,
      'medium': medium,
      'wide': wide,
    }.entries) {
      testWidgets('at ${entry.key} width', (tester) async {
        final service = _StubMessageService(
          messages: [
            messageFrom(
              id: 'm1',
              senderId: otherUserId,
              content: 'react to me',
            ),
          ],
          reactionFailure: FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'Missing or insufficient permissions.',
          ),
        );

        await pumpChat(tester, service, size: entry.value);
        await reactTo(tester, 'react to me');

        expect(service.reactionCalls, 1);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.text("You don't have permission to do that."),
          findsOneWidget,
        );
        // NOTE: no takeException() here — _MessageActionsSheet puts its
        // ListTiles inside a coloured Container with no Material ancestor,
        // which trips a pre-existing Flutter debug check unrelated to this
        // fix (reported separately).
      });
    }

    testWidgets('intentional copy is preserved verbatim', (tester) async {
      final service = _StubMessageService(
        messages: [
          messageFrom(id: 'm1', senderId: otherUserId, content: 'react to me'),
        ],
        reactionFailure: StateError('You must be signed in to use messages.'),
      );

      await pumpChat(tester, service, size: narrow);
      await reactTo(tester, 'react to me');

      expect(
        find.text('You must be signed in to use messages.'),
        findsOneWidget,
      );
    });

    testWidgets('an unrecognized failure still says something useful', (
      tester,
    ) async {
      final service = _StubMessageService(
        messages: [
          messageFrom(id: 'm1', senderId: otherUserId, content: 'react to me'),
        ],
        reactionFailure: Exception('boxed interop noise'),
      );

      await pumpChat(tester, service, size: narrow);
      await reactTo(tester, 'react to me');

      expect(find.text('Could not update your reaction.'), findsOneWidget);
      expect(
        find.textContaining('boxed interop noise'),
        findsNothing,
        reason: 'raw exception text must never reach the UI',
      );
    });

    testWidgets('a reaction that succeeds says nothing at all', (tester) async {
      final service = _StubMessageService(
        messages: [
          messageFrom(id: 'm1', senderId: otherUserId, content: 'react to me'),
        ],
      );

      await pumpChat(tester, service, size: narrow);
      await reactTo(tester, 'react to me');

      expect(service.reactionCalls, 1);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('typing presence failures surface once, not per keystroke', () {
    testWidgets('the first rejection is reported and later ones are not', (
      tester,
    ) async {
      final service = _StubMessageService(
        messages: const <Message>[],
        typingFailure: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
          message: 'backend unavailable',
        ),
      );

      await pumpChat(tester, service, size: narrow);

      await tester.enterText(find.byType(TextField), 'h');
      await tester.pumpAndSettle();

      expect(service.typingCalls, greaterThanOrEqualTo(1));
      expect(
        find.text('This is taking longer than expected. Please try again.'),
        findsOneWidget,
      );

      // Let the snackbar retire, then keep typing: the composer must not
      // turn into a nag.
      ScaffoldMessenger.of(
        tester.element(find.byType(TextField)),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      final callsSoFar = service.typingCalls;
      await tester.enterText(find.byType(TextField), 'hello there');
      await tester.pumpAndSettle();

      expect(
        service.typingCalls,
        callsSoFar,
        reason: 'typing is a state transition, not one write per keystroke',
      );
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'reported once per visit, not once per keystroke',
      );
    });

    testWidgets('typing presence that works is silent, and sending still '
        'works after a presence failure', (tester) async {
      final service = _StubMessageService(
        messages: const <Message>[],
        typingFailure: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
          message: 'backend unavailable',
        ),
      );

      await pumpChat(tester, service, size: wide);

      await tester.enterText(find.byType(TextField), 'still sendable');
      await tester.pumpAndSettle();

      // The presence warning sits over the composer; retire it the way a
      // real user would before reaching for Send.
      ScaffoldMessenger.of(
        tester.element(find.byType(TextField)),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      await sendAndWaitForQueuedMessage(tester, service);

      expect(
        service.sentTexts,
        ['still sendable'],
        reason: 'a broken presence signal must not block the actual send',
      );
      expect(
        (tester.widget<TextField>(find.byType(TextField))).controller?.text,
        isEmpty,
        reason: 'the composer acknowledges the local queue, not network RTT',
      );
      expect(find.text('still sendable'), findsOneWidget);
      expect(find.text('Sending…'), findsOneWidget);
    });

    testWidgets('leaving serializes the final not-typing state', (
      tester,
    ) async {
      final service = _BlockingTypingMessageService();
      await pumpChat(tester, service, size: narrow);

      await tester.enterText(find.byType(TextField), 'hello');
      await service.firstStarted.future;

      // Dispose the route while the `true` write is still in flight. The
      // final `false` must wait behind it rather than racing in parallel.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      service.releaseFirst.complete();
      await tester.pumpAndSettle();

      expect(service.states, <bool>[true, false]);
      expect(service.maxInFlight, 1);
    });

    testWidgets(
      'a terminal queued message stays visible with recovery actions',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final service = _StubMessageService(messages: const <Message>[]);
        await pumpChat(tester, service, size: narrow);

        await tester.enterText(find.byType(TextField), 'keep my words');
        await tester.pump();
        await sendAndWaitForQueuedMessage(tester, service);
        final entry = service.outbox.entries.single;
        await service.outbox.markFailed(
          entry.id,
          'permission denied internals',
        );
        await tester.pumpAndSettle();

        expect(find.text('keep my words'), findsOneWidget);
        expect(find.text('Not sent'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Remove'), findsOneWidget);
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Message status: Not sent'))
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Retry'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Remove'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(
          find.textContaining('permission denied internals'),
          findsNothing,
        );

        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect(find.text('keep my words'), findsNothing);
        semantics.dispose();
      },
    );

    testWidgets('retry status and empty state reflow at 320px and 200% text', (
      tester,
    ) async {
      final emptyService = _StubMessageService(messages: const <Message>[]);
      await pumpChat(
        tester,
        emptyService,
        size: const Size(320, 640),
        textScaler: const TextScaler.linear(2),
      );

      expect(find.text('Say hello 👋'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField), 'wait for the network');
      await tester.pump();
      await sendAndWaitForQueuedMessage(tester, emptyService);
      final entry = emptyService.outbox.entries.single;
      await emptyService.outbox.markRetry(entry.id, 'offline');
      await tester.pump();

      expect(find.text('Waiting for connection'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a local message never hides a server-history failure', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final service = _StubMessageService(
        messages: const <Message>[],
        messageStreamError: StateError('private Firestore diagnostics'),
      );
      final entry = await service.outbox.enqueue(
        conversationId: conversationId,
        recipientId: otherUserId,
        text: 'saved on this device',
      );
      await service.outbox.markFailed(entry.id, 'offline internals');

      await pumpChat(tester, service, size: narrow);

      expect(find.text('saved on this device'), findsOneWidget);
      expect(find.text('Could not load this conversation.'), findsOneWidget);
      expect(
        find.text('Your unsent messages are still shown.'),
        findsOneWidget,
      );
      expect(
        tester
            .getSemantics(
              find.bySemanticsLabel(
                'Could not load this conversation. '
                'Your unsent messages are still shown.',
              ),
            )
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(
        find.textContaining('private Firestore diagnostics'),
        findsNothing,
      );
      semantics.dispose();
    });

    testWidgets('an enqueue rejection cannot lose an earlier draft', (
      tester,
    ) async {
      final service = _BlockingQueueMessageService();
      await pumpChat(tester, service, size: narrow);

      await tester.enterText(find.byType(TextField), 'first draft');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.runAsync(
        () => service.started.future.timeout(const Duration(seconds: 2)),
      );
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.readOnly,
        isTrue,
        reason: 'editing is paused only until the local durable enqueue ends',
      );

      // Defend against a late platform edit already in flight even though
      // the field is read-only for the normal interaction path.
      field.controller!.text = 'second draft';
      service.result.completeError(const OutboxFullException(50));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'first draft\nsecond draft',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).readOnly,
        isFalse,
      );
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving the screen mid-failure throws nothing', (
      tester,
    ) async {
      final service = _StubMessageService(
        messages: const <Message>[],
        typingFailure: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
          message: 'backend unavailable',
        ),
      );

      await pumpChat(tester, service, size: narrow);
      await tester.enterText(find.byType(TextField), 'abandon ship');
      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving cancels the one shared server-history listener', (
      tester,
    ) async {
      final service = _CancellableMessageService();
      addTearDown(service.close);
      service.controller.add(const <Message>[]);
      await pumpChat(tester, service, size: narrow);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(service.cancelCalls, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('a rejected un-archive is reported and still opens the chat', () {
    Future<void> pumpMessages(
      WidgetTester tester,
      _StubMessageService service, {
      required Size size,
    }) async {
      useSurface(tester, size);
      await tester.pumpWidget(
        host(
          MessagesScreen(
            messageService: service,
            friendService: _StubFriendService(),
            auth: MockFirebaseAuth(
              signedIn: true,
              mockUser: MockUser(uid: currentUserId),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final entry in <String, Size>{
      'narrow': narrow,
      'wide': wide,
    }.entries) {
      testWidgets('at ${entry.key} width', (tester) async {
        final service = _StubMessageService(
          messages: const <Message>[],
          conversations: [_archivedConversation()],
          unarchiveFailure: FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'Missing or insufficient permissions.',
          ),
        );

        await pumpMessages(tester, service, size: entry.value);
        await tester.tap(find.byTooltip('Show archived conversations'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Them'));
        await tester.pumpAndSettle();

        expect(service.unarchiveCalls, 1);
        expect(
          find.text("You don't have permission to do that."),
          findsOneWidget,
          reason: 'the tap used to do nothing and say nothing',
        );
        expect(
          find.byType(ChatScreen),
          findsOneWidget,
          reason: 'opening was the intent; un-archiving was the side effect',
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a successful un-archive opens the chat silently', (
      tester,
    ) async {
      final service = _StubMessageService(
        messages: const <Message>[],
        conversations: [_archivedConversation()],
      );

      await pumpMessages(tester, service, size: narrow);
      await tester.tap(find.byTooltip('Show archived conversations'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Them'));
      await tester.pumpAndSettle();

      expect(service.unarchiveCalls, 1);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}

Conversation _archivedConversation() {
  return Conversation(
    id: 'me-uid_them-uid',
    participantIds: const ['me-uid', 'them-uid'],
    participantNames: const {'me-uid': 'Me', 'them-uid': 'Them'},
    participantEmails: const {'me-uid': '', 'them-uid': ''},
    participantPhotoUrls: const {'me-uid': '', 'them-uid': ''},
    unreadCounts: const {'me-uid': 0, 'them-uid': 0},
    archivedBy: const ['me-uid'],
    mutedBy: const <String>[],
    lastMessage: 'an archived thread',
    lastMessageType: MessageType.text,
    lastMessageSenderId: 'them-uid',
    updatedAt: DateTime.utc(2026, 3, 1, 12),
    createdAt: DateTime.utc(2026, 3, 1, 11),
  );
}

/// The friends list is not under test here; MessagesScreen only needs the
/// stream so the "new message" sheet has something to show.
class _StubFriendService extends FriendService {
  _StubFriendService()
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me-uid'),
        ),
      );

  @override
  Stream<List<FriendUser>> watchFriends() =>
      Stream<List<FriendUser>>.value(const <FriendUser>[]);
}

/// A [MessageService] whose individual operations can be failed on demand.
///
/// It extends the real service (over a fake Firestore that nothing here
/// reads) so the screens keep their real types and only the calls under
/// test are scripted.
class _StubMessageService extends MessageService {
  _StubMessageService({
    required this.messages,
    this.conversations = const <Conversation>[],
    this.messageStreamError,
    this.reactionFailure,
    this.typingFailure,
    this.unarchiveFailure,
  }) : super(
         firestore: FakeFirebaseFirestore(),
         auth: MockFirebaseAuth(
           signedIn: true,
           mockUser: MockUser(uid: 'me-uid'),
         ),
       );

  final List<Message> messages;
  final List<Conversation> conversations;
  final Object? messageStreamError;
  final Object? reactionFailure;
  final Object? typingFailure;
  final Object? unarchiveFailure;

  int reactionCalls = 0;
  int typingCalls = 0;
  int unarchiveCalls = 0;
  final List<String> sentTexts = <String>[];

  @override
  Stream<List<Message>> watchMessages(String conversationId) {
    final error = messageStreamError;
    return error == null
        ? Stream<List<Message>>.value(messages)
        : Stream<List<Message>>.error(error);
  }

  @override
  Stream<List<Conversation>> watchConversations({
    bool includeArchived = false,
  }) => Stream<List<Conversation>>.value(conversations);

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
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {
    typingCalls++;
    if (typingFailure != null) throw typingFailure!;
  }

  @override
  Future<void> toggleReaction({
    required String conversationId,
    required String messageId,
    required String emoji,
  }) async {
    reactionCalls++;
    if (reactionFailure != null) throw reactionFailure!;
  }

  @override
  Future<void> unarchiveConversation(String conversationId) async {
    unarchiveCalls++;
    if (unarchiveFailure != null) throw unarchiveFailure!;
  }

  @override
  Future<OutboxEntry> queueTextMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    Message? replyTo,
  }) async {
    sentTexts.add(text);
    return outbox.enqueue(
      conversationId: conversationId,
      recipientId: recipientId,
      text: text,
      replyToMessageId: replyTo?.id,
    );
  }
}

class _BlockingTypingMessageService extends _StubMessageService {
  _BlockingTypingMessageService() : super(messages: const <Message>[]);

  final Completer<void> firstStarted = Completer<void>();
  final Completer<void> releaseFirst = Completer<void>();
  final List<bool> states = <bool>[];
  int _inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {
    states.add(isTyping);
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      if (isTyping && !firstStarted.isCompleted) {
        firstStarted.complete();
        await releaseFirst.future;
      }
    } finally {
      _inFlight--;
    }
  }
}

class _BlockingQueueMessageService extends _StubMessageService {
  _BlockingQueueMessageService() : super(messages: const <Message>[]);

  final Completer<void> started = Completer<void>();
  final Completer<OutboxEntry> result = Completer<OutboxEntry>();

  @override
  Future<OutboxEntry> queueTextMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    Message? replyTo,
  }) {
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

class _CancellableMessageService extends _StubMessageService {
  _CancellableMessageService() : super(messages: const <Message>[]) {
    controller = StreamController<List<Message>>(onCancel: () => cancelCalls++);
  }

  late final StreamController<List<Message>> controller;
  int cancelCalls = 0;

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      controller.stream;

  Future<void> close() => controller.close();
}
