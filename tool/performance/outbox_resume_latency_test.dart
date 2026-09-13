import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_outbox.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_payload_source.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_payload_store.dart';
import 'package:yovoice/features/messages/data/services/message_outbox.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ResumeHarness harness;

  setUp(() {
    // This regression suite is intentionally outside the default test/ tree.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(<String, Object>{});
    harness = _ResumeHarness();
  });

  tearDown(() => harness.dispose());

  test(
    'cold resume starts persisted media while text delivery is suspended',
    () async {
      final first = await harness.queueText('first text');
      final second = await harness.queueText('second text');
      final attachment = await harness.queueAttachment();
      await harness.restart();
      harness.server.textGate = Completer<void>();

      var resumeCompleted = false;
      final resuming = harness.resume().then((_) => resumeCompleted = true);
      await _settleAsyncWork();

      expect(harness.server.textCalls, hasLength(1));
      expect(harness.server.textGate!.isCompleted, isFalse);
      expect(
        harness.server.reserveCalls,
        hasLength(1),
        reason:
            'persisted media must start before an unresolved text callable '
            'allows the text queue to drain',
      );
      expect(harness.server.finalizeCalls, hasLength(1));
      expect(harness.payloads.uploadedIds, [attachment.id]);
      expect(harness.service.attachmentOutbox.entries, isEmpty);
      expect(harness.service.outbox.entries.map((entry) => entry.id), [
        first.id,
        second.id,
      ]);
      expect(
        resumeCompleted,
        isFalse,
        reason: 'resume still waits for both independent queues',
      );

      harness.server.releaseText();
      await resuming;
      expect(harness.server.textCalls.map((call) => call.payload['text']), [
        'first text',
        'second text',
      ]);
      expect(
        harness.server.textCalls.map((call) => call.payload['requestId']),
        [first.requestId, second.requestId],
      );
      expect(harness.service.outbox.entries, isEmpty);

      await harness.resume();
      expect(harness.server.textCalls, hasLength(2));
      expect(harness.server.reserveCalls, hasLength(1));
      expect(harness.server.finalizeCalls, hasLength(1));
    },
  );

  test(
    'overlapping resume calls share in-flight text and media deliveries',
    () async {
      final text = await harness.queueText('send once');
      final attachment = await harness.queueAttachment();
      await harness.restart();
      harness.server.textGate = Completer<void>();
      harness.server.reserveGate = Completer<void>();

      final resumptions = [
        harness.resume(),
        harness.resume(),
        harness.resume(),
      ];
      await _settleAsyncWork();
      expect(harness.server.textCalls, hasLength(1));
      expect(harness.server.reserveCalls, hasLength(1));
      expect(harness.payloads.uploadedIds, isEmpty);

      harness.server.releaseReservation();
      await _settleAsyncWork();
      expect(harness.payloads.uploadedIds, [attachment.id]);
      expect(harness.server.finalizeCalls, hasLength(1));
      expect(
        harness.server.finalizeCalls.single.payload['requestId'],
        attachment.finalizeRequestId,
      );
      expect(
        harness.server.textCalls.single.payload['requestId'],
        text.requestId,
      );

      harness.server.releaseText();
      await Future.wait(resumptions);
      await harness.resume();
      expect(harness.server.textCalls, hasLength(1));
      expect(harness.server.reserveCalls, hasLength(1));
      expect(harness.server.finalizeCalls, hasLength(1));
      expect(harness.service.outbox.entries, isEmpty);
      expect(harness.service.attachmentOutbox.entries, isEmpty);
    },
  );

  test('a refused text remains failed while queued media completes', () async {
    final text = await harness.queueText('refused text');
    await harness.queueAttachment();
    await harness.restart();
    harness.server.textFailureCode = 'permission-denied';

    await harness.resume();

    final failed = harness.service.outbox.entries.single;
    expect(failed.id, text.id);
    expect(failed.requestId, text.requestId);
    expect(failed.state, OutboxState.failed);
    expect(failed.lastError, startsWith('permission-denied'));
    expect(harness.service.attachmentOutbox.entries, isEmpty);
    expect(harness.server.finalizeCalls, hasLength(1));
    await harness.resume();
    expect(
      harness.server.textCalls,
      hasLength(1),
      reason: 'background resume must not repeat an authoritative refusal',
    );
  });

  test(
    'a refused media reservation retains payload and retry identity',
    () async {
      await harness.queueText('healthy text');
      final attachment = await harness.queueAttachment();
      await harness.restart();
      harness.server.reserveFailureCode = 'permission-denied';

      await harness.resume();

      final queue = harness.service.attachmentOutbox;
      final failed = queue.entries.single;
      expect(failed.status, DirectAttachmentOutboxStatus.failed);
      expect(failed.reserveRequestId, attachment.reserveRequestId);
      expect(failed.finalizeRequestId, attachment.finalizeRequestId);
      expect(
        await harness.payloads.exists(queue.accountNamespace, failed.id),
        isTrue,
      );
      expect(harness.service.outbox.entries, isEmpty);
      expect(harness.server.finalizeCalls, isEmpty);

      await harness.resume();
      expect(harness.server.reserveCalls, hasLength(1));
      harness.server.reserveFailureCode = null;
      await harness.service.retryFailedAttachment(failed.id);
      expect(
        harness.server.reserveCalls.map((call) => call.payload['requestId']),
        [attachment.reserveRequestId, attachment.reserveRequestId],
      );
      expect(
        harness.server.finalizeCalls.single.payload['requestId'],
        attachment.finalizeRequestId,
      );
      expect(harness.payloads.uploadedIds, [attachment.id]);
      expect(queue.entries, isEmpty);
      expect(
        await harness.payloads.exists(queue.accountNamespace, failed.id),
        isFalse,
      );
    },
  );

  test(
    'an account switch stops captured queues before further delivery',
    () async {
      await harness.queueText('already submitted as A');
      final unsent = await harness.queueText('still owned by A');
      final attachment = await harness.queueAttachment();
      await harness.restart();
      harness.server.textGate = Completer<void>();
      harness.server.reserveGate = Completer<void>();

      final resuming = harness.resume();
      await _settleAsyncWork();
      final accountAText = harness.service.outbox;
      final accountAMedia = harness.service.attachmentOutbox;
      expect(harness.server.textCalls, hasLength(1));

      harness.auth.currentUser = MockUser(uid: 'resume-account-b');
      harness.server.releaseText();
      harness.server.releaseReservation();
      await resuming;
      await harness.resume();

      expect(
        harness.server.calls.every((call) => call.ownerId == _ownerId),
        isTrue,
      );
      expect(harness.server.textCalls, hasLength(1));
      expect(
        harness.payloads.uploadedIds,
        isEmpty,
        reason: 'a late reservation ACK cannot upload under the next account',
      );
      expect(harness.server.finalizeCalls, isEmpty);
      expect(accountAText.entries.single.id, unsent.id);
      expect(accountAMedia.entries.single.id, attachment.id);
      expect(
        await harness.payloads.exists(
          accountAMedia.accountNamespace,
          attachment.id,
        ),
        isTrue,
      );
      expect(harness.service.outbox.ownerId, 'resume-account-b');
      expect(harness.service.attachmentOutbox.ownerId, 'resume-account-b');
      expect(harness.service.outbox.entries, isEmpty);
      expect(harness.service.attachmentOutbox.entries, isEmpty);
    },
  );

  test(
    'restart replays an uploaded attachment with the stored finalize identity',
    () async {
      final attachment = await harness.queueAttachment();
      final queue = harness.service.attachmentOutbox;
      final expiresAt = DateTime.now().add(const Duration(minutes: 15));
      await queue.setReservation(
        attachment.id,
        DirectAttachmentReservationRecord(
          conversationId: _conversationId,
          messageId: 'persisted-server-message',
          storagePath:
              'message_attachments/$_ownerId/persisted-server-message.jpg',
          type: MessageType.image,
          expiresAt: expiresAt,
          clientExpiresAt: expiresAt,
        ),
      );
      await queue.setGeneration(attachment.id, 'persisted-generation');
      await queue.markFinalizeAttempted(attachment.id);
      await harness.restart();

      await harness.resume();

      expect(harness.server.reserveCalls, isEmpty);
      expect(harness.payloads.uploadedIds, isEmpty);
      expect(harness.server.finalizeCalls.single.payload, {
        'conversationId': _conversationId,
        'messageId': 'persisted-server-message',
        'objectGeneration': 'persisted-generation',
        'requestId': attachment.finalizeRequestId,
      });
      expect(harness.service.attachmentOutbox.entries, isEmpty);
      await harness.resume();
      expect(harness.server.finalizeCalls, hasLength(1));
    },
  );
}

const _ownerId = 'resume-account-a';
const _recipientId = 'resume-recipient';
const _conversationId = 'resume-account-a_resume-recipient';

// These fakes use immediate futures, except for explicit completer gates.
// One event turn drains all ready work without measuring wall-clock latency.
Future<void> _settleAsyncWork() => Future<void>.delayed(Duration.zero);

class _ResumeHarness {
  _ResumeHarness() {
    server = _ControlledFunctions(auth);
    service = _newService();
  }

  final auth = _MutableAuth(MockUser(uid: _ownerId));
  final firestore = FakeFirebaseFirestore();
  final payloads = _MemoryPayloadStore();
  final resumptions = <Future<void>>[];
  late final _ControlledFunctions server;
  late MessageService service;

  MessageService _newService() => MessageService(
    firestore: firestore,
    auth: auth,
    functions: server,
    storage: _Storage(),
    connectivity: _QuietConnectivity(),
    attachmentPayloadStore: payloads,
  );

  Future<OutboxEntry> queueText(String text) => service.outbox.enqueue(
    conversationId: _conversationId,
    recipientId: _recipientId,
    text: text,
  );

  Future<DirectAttachmentOutboxEntry> queueAttachment() {
    final bytes = Uint8List.fromList(List<int>.filled(256, 42));
    return service.attachmentOutbox.enqueue(
      fingerprint: sha256.convert(bytes).toString(),
      conversationId: _conversationId,
      type: MessageType.image,
      contentType: 'image/jpeg',
      durationSeconds: null,
      bytes: bytes,
      reserveRequestId: 'persisted-reserve-request',
      finalizeRequestId: 'persisted-finalize-request',
    );
  }

  Future<void> restart() async {
    await service.dispose();
    service = _newService();
  }

  Future<void> resume() {
    final pending = service.resumeOutbox();
    resumptions.add(pending);
    return pending;
  }

  Future<void> dispose() async {
    server.releaseText();
    server.releaseReservation();
    await Future.wait(resumptions);
    await service.dispose();
  }
}

class _MutableAuth implements FirebaseAuth {
  _MutableAuth(this.currentUser);

  @override
  User? currentUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietConnectivity implements Connectivity {
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Call {
  _Call(this.name, this.ownerId, this.payload);

  final String name;
  final String? ownerId;
  final Map<String, Object?> payload;
}

class _ControlledFunctions implements FirebaseFunctions {
  _ControlledFunctions(this.auth);

  final _MutableAuth auth;
  final calls = <_Call>[];
  Completer<void>? textGate;
  Completer<void>? reserveGate;
  String? textFailureCode;
  String? reserveFailureCode;

  List<_Call> get textCalls =>
      calls.where((call) => call.name == 'sendDirectMessage').toList();
  List<_Call> get reserveCalls => calls
      .where((call) => call.name == 'reserveDirectMessageAttachment')
      .toList();
  List<_Call> get finalizeCalls => calls
      .where((call) => call.name == 'finalizeDirectMessageAttachment')
      .toList();

  void releaseText() {
    final gate = textGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void releaseReservation() {
    final gate = reserveGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _Callable((parameters) async {
        final payload = Map<String, Object?>.from(parameters! as Map);
        calls.add(_Call(name, auth.currentUser?.uid, payload));
        switch (name) {
          case 'sendDirectMessage':
            await textGate?.future;
            final code = textFailureCode;
            if (code != null) {
              throw FirebaseFunctionsException(
                code: code,
                message: 'Text refused.',
              );
            }
            return {
              'conversationId': payload['conversationId'],
              'created': true,
            };
          case 'reserveDirectMessageAttachment':
            await reserveGate?.future;
            final code = reserveFailureCode;
            if (code != null) {
              throw FirebaseFunctionsException(
                code: code,
                message: 'Media refused.',
              );
            }
            return <String, Object?>{
              'conversationId': payload['conversationId'],
              'messageId': 'reserved-server-message',
              'storagePath':
                  'message_attachments/$_ownerId/reserved-server-message.jpg',
              'type': payload['type'],
              'expiresAtMillis': DateTime.now()
                  .add(const Duration(minutes: 15))
                  .millisecondsSinceEpoch,
            };
          case 'finalizeDirectMessageAttachment':
            return {'created': false};
          default:
            throw StateError('Unexpected callable: $name');
        }
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Callable implements HttpsCallable {
  _Callable(this.handler);

  final Future<Object?> Function(Object?) handler;

  @override
  Future<HttpsCallableResult<T>> call<T>([Object? parameters]) async =>
      _CallableResult<T>((await handler(parameters)) as T);

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

class _Storage implements FirebaseStorage {
  @override
  Reference ref([String? path]) => _StorageReference(path!);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StorageReference implements Reference {
  _StorageReference(this.fullPath);

  @override
  final String fullPath;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryPayloadStore implements DirectAttachmentPayloadStore {
  final payloads = <String, List<int>>{};
  final uploadedIds = <String>[];

  String _key(String namespace, String id) => '$namespace:$id';

  @override
  Future<void> adopt(
    String namespace,
    String id,
    DirectAttachmentPayloadSource source,
  ) async {
    final bytes = <int>[];
    await for (final chunk in source.openRead()) {
      bytes.addAll(chunk);
    }
    payloads[_key(namespace, id)] = bytes;
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
    SettableMetadata metadata, {
    void Function(double progress)? onProgress,
  }) async {
    expect(await exists(namespace, id), isTrue);
    expect(reference.fullPath, contains('reserved-server-message'));
    expect(metadata.customMetadata?['yovoiceOwnerUid'], _ownerId);
    uploadedIds.add(id);
    onProgress?.call(1);
    return 'uploaded-generation';
  }

  @override
  Future<void> delete(String namespace, String id) async {
    payloads.remove(_key(namespace, id));
  }

  @override
  Future<void> clear(String namespace) async {
    payloads.removeWhere((key, _) => key.startsWith('$namespace:'));
  }
}
