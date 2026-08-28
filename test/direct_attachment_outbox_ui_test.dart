import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_outbox.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_payload_store.dart';
import 'package:yovoice/features/messages/data/services/message_outbox.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/messages/presentation/screens/chat_screen.dart';
import 'package:yovoice/shared/identity/public_identity_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const currentUserId = 'me-uid';
  const otherUserId = 'them-uid';
  const conversationId = 'me-uid_them-uid';
  late SharedPreferences preferences;
  late _MemoryPayloadStore payloadStore;
  late DirectAttachmentOutbox mediaOutbox;
  late PublicIdentityRepository originalIdentityRepository;

  MockFirebaseAuth auth() =>
      MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: currentUserId));

  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    preferences = await SharedPreferences.getInstance();
    payloadStore = _MemoryPayloadStore();
    var nextId = 0;
    mediaOutbox = DirectAttachmentOutbox(
      ownerId: currentUserId,
      preferences: preferences,
      payloadStore: payloadStore,
      idFactory: () => 'attachment_ui_${nextId++}',
    );
    originalIdentityRepository = PublicIdentityRepository.instance;
    PublicIdentityRepository.instance = PublicIdentityRepository(
      auth: auth(),
      fetchOverride: (uids) async => <String, dynamic>{
        for (final uid in uids) uid: {'role': 'user', 'vip': false, 'uid': uid},
      },
      flushDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() {
    PublicIdentityRepository.instance = originalIdentityRepository;
  });

  Future<DirectAttachmentOutboxEntry> enqueue({
    String targetConversation = conversationId,
    MessageType type = MessageType.image,
  }) => mediaOutbox.enqueue(
    fingerprint: List<String>.filled(
      64,
      type == MessageType.image ? 'a' : 'b',
    ).join(),
    conversationId: targetConversation,
    type: type,
    contentType: type == MessageType.image ? 'image/jpeg' : 'audio/mp4',
    durationSeconds: type == MessageType.voice ? 7 : null,
    bytes: Uint8List(type == MessageType.image ? 256 : 2048),
    reserveRequestId: 'reserve-ui-request',
    finalizeRequestId: 'finalize-ui-request',
  );

  Future<void> pumpChat(
    WidgetTester tester,
    _MediaOutboxMessageService service, {
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: ChatScreen(
            conversationId: conversationId,
            otherUserId: otherUserId,
            otherDisplayName: 'Them',
            otherEmail: '',
            otherPhotoUrl: '',
            messageService: service,
            auth: auth(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('failed media is visible with 44px Retry and Discard at '
      '320px and 200% text', (tester) async {
    final failed = (await tester.runAsync(
      () => enqueue(type: MessageType.voice),
    ))!;
    await tester.runAsync(
      () => mediaOutbox.markFailed(failed.id, StateError('refused')),
    );
    await tester.runAsync(
      () => enqueue(targetConversation: 'another-conversation'),
    );
    final service = _MediaOutboxMessageService(mediaOutbox, auth());

    await pumpChat(tester, service, textScaler: const TextScaler.linear(2));

    expect(find.text('Voice message'), findsOneWidget);
    expect(find.text('Not sent'), findsOneWidget);
    expect(
      find.text('Photo'),
      findsNothing,
      reason: 'outbox is conversation scoped',
    );
    final retry = find.byKey(ValueKey('retry-media-${failed.id}'));
    final discard = find.byKey(ValueKey('discard-media-${failed.id}'));
    expect(retry, findsOneWidget);
    expect(discard, findsOneWidget);
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(discard).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);

    await tester.tap(retry);
    await tester.pump();
    expect(service.retryCalls, 1);
  });

  testWidgets('queued media exposes no recovery controls', (tester) async {
    final entry = (await tester.runAsync(enqueue))!;
    final service = _MediaOutboxMessageService(mediaOutbox, auth());
    await pumpChat(tester, service);

    expect(find.text('Sending…'), findsOneWidget);
    expect(find.byKey(ValueKey('retry-media-${entry.id}')), findsNothing);
    expect(find.byKey(ValueKey('discard-media-${entry.id}')), findsNothing);
    expect(
      await tester.runAsync(
        () => payloadStore.exists(mediaOutbox.accountNamespace, entry.id),
      ),
      isTrue,
    );
  });

  testWidgets('retrying media exposes no recovery controls', (tester) async {
    final entry = (await tester.runAsync(enqueue))!;
    await tester.runAsync(
      () => mediaOutbox.markRetry(entry.id, StateError('offline')),
    );
    final service = _MediaOutboxMessageService(mediaOutbox, auth());
    await pumpChat(tester, service);

    expect(find.text('Waiting for connection'), findsOneWidget);
    expect(find.byKey(ValueKey('retry-media-${entry.id}')), findsNothing);
    expect(find.byKey(ValueKey('discard-media-${entry.id}')), findsNothing);
    expect(
      await tester.runAsync(
        () => payloadStore.exists(mediaOutbox.accountNamespace, entry.id),
      ),
      isTrue,
    );
  });

  testWidgets('failed Discard invokes the service action', (tester) async {
    final entry = (await tester.runAsync(enqueue))!;
    await tester.runAsync(
      () => mediaOutbox.markFailed(entry.id, StateError('gave up')),
    );
    final service = _MediaOutboxMessageService(mediaOutbox, auth());
    await pumpChat(tester, service);

    expect(find.text('Not sent'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('discard-media-${entry.id}')));
    await tester.pump();

    expect(service.discardCalls, 1);
  });
}

class _MediaOutboxMessageService extends MessageService {
  _MediaOutboxMessageService(this.queue, MockFirebaseAuth auth)
    : super(
        firestore: FakeFirebaseFirestore(),
        auth: auth,
        outbox: MessageOutbox(preferences: null),
        attachmentOutbox: queue,
      );

  final DirectAttachmentOutbox queue;
  int retryCalls = 0;
  int discardCalls = 0;

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
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {}

  @override
  Future<void> retryFailedAttachment(String entryId) async {
    retryCalls += 1;
  }

  @override
  Future<void> discardQueuedAttachment(String entryId) async {
    discardCalls += 1;
  }
}

class _MemoryPayloadStore implements DirectAttachmentPayloadStore {
  final Map<String, Uint8List> payloads = <String, Uint8List>{};

  String _key(String namespace, String id) => '$namespace:$id';

  @override
  Future<void> write(String namespace, String id, Uint8List bytes) async {
    payloads[_key(namespace, id)] = Uint8List.fromList(bytes);
  }

  @override
  Future<bool> exists(String namespace, String id) async =>
      payloads.containsKey(_key(namespace, id));

  @override
  Future<Set<String>> keys(String namespace) async => payloads.keys
      .where((key) => key.startsWith('$namespace:'))
      .map((key) => key.substring(namespace.length + 1))
      .toSet();

  @override
  Future<String> upload(
    String namespace,
    String id,
    Reference reference,
    SettableMetadata metadata,
  ) => throw UnimplementedError();

  @override
  Future<void> delete(String namespace, String id) async {
    payloads.remove(_key(namespace, id));
  }

  @override
  Future<void> clear(String namespace) async {
    payloads.removeWhere((key, _) => key.startsWith('$namespace:'));
  }
}
