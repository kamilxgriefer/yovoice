import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/active_conversation_registry.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

/// Read receipts follow the conversation snapshot, not the build cycle:
/// mark-read fires once per newest incoming-unread advance (never per rebuild
/// or outgoing message). A rejected background receipt stays out of the
/// conversation UI and is retried on the next relevant snapshot.
void main() {
  const currentUserId = 'me-uid';
  const otherUserId = 'them-uid';
  const conversationId = 'me-uid_them-uid';

  late PublicIdentityRepository originalIdentityRepository;

  setUp(() {
    ActiveConversationRegistry.instance.clear();
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
    ActiveConversationRegistry.instance.clear();
  });

  Message messageWith({
    required String id,
    required String content,
    String senderId = otherUserId,
    List<String> readBy = const <String>[],
  }) {
    return Message(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      type: MessageType.text,
      content: content,
      sentAt: DateTime.utc(2026, 3, 1, 12),
      readBy: readBy,
      reactions: const <String, String>{},
    );
  }

  Widget host(_StubMessageService service) => MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    home: ChatScreen(
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
  );

  testWidgets('mark-read fires once per newest message, not per rebuild', (
    tester,
  ) async {
    final service = _StubMessageService();
    // No pumpAndSettle before the first snapshot: the loading spinner
    // animates until the stream delivers.
    await tester.pumpWidget(host(service));
    await tester.pump();

    expect(
      service.markReadCalls,
      0,
      reason: 'nothing delivered yet, nothing to mark',
    );

    final newest = messageWith(id: 'm1', content: 'first');
    service.emit([newest]);
    await tester.pumpAndSettle();
    expect(service.markReadCalls, 1);

    // Firestore re-delivers the whole window on any change; rebuilds
    // happen for a hundred unrelated reasons. Neither may re-mark.
    service.emit([newest]);
    await tester.pumpAndSettle();
    service.emit([newest]);
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    expect(service.markReadCalls, 1);
  });

  testWidgets('chat route registers and releases its active conversation', (
    tester,
  ) async {
    final service = _StubMessageService();
    await tester.pumpWidget(host(service));
    await tester.pump();
    service.emit(const <Message>[]);
    await tester.pumpAndSettle();

    expect(
      ActiveConversationRegistry.instance.contains(conversationId),
      isTrue,
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(
      ActiveConversationRegistry.instance.contains(conversationId),
      isFalse,
    );
  });

  testWidgets('a newer message triggers exactly one more mark-read', (
    tester,
  ) async {
    final service = _StubMessageService();
    await tester.pumpWidget(host(service));
    await tester.pump();

    final first = messageWith(id: 'm1', content: 'first');
    service.emit([first]);
    await tester.pumpAndSettle();
    expect(service.markReadCalls, 1);

    // watchMessages orders newest-first.
    service.emit([messageWith(id: 'm2', content: 'second'), first]);
    await tester.pumpAndSettle();
    expect(service.markReadCalls, 2);

    service.emit([messageWith(id: 'm2', content: 'second'), first]);
    await tester.pumpAndSettle();
    expect(service.markReadCalls, 2);
  });

  testWidgets('an empty conversation never marks', (tester) async {
    final service = _StubMessageService();
    await tester.pumpWidget(host(service));
    await tester.pump();

    service.emit(const <Message>[]);
    await tester.pumpAndSettle();

    expect(service.markReadCalls, 0);
  });

  testWidgets('already-read history and outgoing messages never mark', (
    tester,
  ) async {
    final service = _StubMessageService();
    await tester.pumpWidget(host(service));
    await tester.pump();

    service.emit([
      messageWith(
        id: 'read',
        content: 'already handled',
        readBy: const <String>[currentUserId],
      ),
      messageWith(
        id: 'mine',
        content: 'outgoing',
        senderId: currentUserId,
        readBy: const <String>[currentUserId],
      ),
    ]);
    await tester.pumpAndSettle();

    expect(service.markReadCalls, 0);
  });

  testWidgets('a failing background mark-read never interrupts the chat '
      'and keeps retrying', (tester) async {
    final service = _StubMessageService(
      markReadFailure: Exception('boxed interop noise'),
    );
    await tester.pumpWidget(host(service));
    await tester.pump();

    service.emit([messageWith(id: 'm1', content: 'unseen')]);
    await tester.pumpAndSettle();

    expect(service.markReadCalls, 1);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.textContaining('boxed interop noise'),
      findsNothing,
      reason: 'raw exception text must never reach the UI',
    );

    service.emit([messageWith(id: 'm1', content: 'unseen')]);
    await tester.pumpAndSettle();

    expect(
      service.markReadCalls,
      2,
      reason: 'a failed mark is retried on the next relevant snapshot',
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('snapshot bursts coalesce behind one in-flight mark-read', (
    tester,
  ) async {
    final service = _StubMessageService(blockFirstMark: true);
    await tester.pumpWidget(host(service));
    await tester.pump();

    service.emit([messageWith(id: 'm1', content: 'first')]);
    await service.firstMarkStarted.future;

    // Both snapshots arrive while page one is blocked. Only the newest state
    // needs one follow-up pass; neither may start a concurrent cursor update.
    service.emit([messageWith(id: 'm2', content: 'second')]);
    service.emit([messageWith(id: 'm3', content: 'third')]);
    await tester.pump();
    expect(service.markReadCalls, 1);
    expect(service.maxConcurrentMarks, 1);

    service.releaseFirstMark.complete();
    await tester.pumpAndSettle();

    expect(service.markReadCalls, 2);
    expect(service.maxConcurrentMarks, 1);
  });
}

/// A [MessageService] whose message snapshots are pushed by the test and
/// whose mark-read can be failed on demand. It extends the real service
/// (over a fake Firestore nothing here reads) so ChatScreen keeps its real
/// types — same pattern as messages_silent_failure_test.dart.
class _StubMessageService extends MessageService {
  _StubMessageService({this.markReadFailure, this.blockFirstMark = false})
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'me-uid'),
        ),
      );

  final Object? markReadFailure;
  final bool blockFirstMark;
  final StreamController<List<Message>> _messages =
      StreamController<List<Message>>.broadcast();
  final Completer<void> firstMarkStarted = Completer<void>();
  final Completer<void> releaseFirstMark = Completer<void>();

  int markReadCalls = 0;
  int concurrentMarks = 0;
  int maxConcurrentMarks = 0;

  void emit(List<Message> messages) => _messages.add(messages);

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      _messages.stream;

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
  Future<void> markConversationRead(String conversationId) async {
    markReadCalls++;
    concurrentMarks++;
    if (concurrentMarks > maxConcurrentMarks) {
      maxConcurrentMarks = concurrentMarks;
    }
    try {
      if (blockFirstMark && markReadCalls == 1) {
        firstMarkStarted.complete();
        await releaseFirstMark.future;
      }
      if (markReadFailure != null) throw markReadFailure!;
    } finally {
      concurrentMarks--;
    }
  }

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {}
}
