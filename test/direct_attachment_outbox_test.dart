import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/messages/data/models/message.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_outbox.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_payload_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;
  late _MemoryPayloadStore payloadStore;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
    payloadStore = _MemoryPayloadStore();
  });

  test(
    'manifest and payload survive restart but remain account-scoped',
    () async {
      final accountA = DirectAttachmentOutbox(
        ownerId: 'account-a',
        preferences: preferences,
        payloadStore: payloadStore,
        idFactory: () => 'attachment_account_a',
      );
      final saved = await accountA.enqueue(
        fingerprint: List<String>.filled(64, 'a').join(),
        conversationId: 'account-a_friend',
        type: MessageType.image,
        contentType: 'image/jpeg',
        durationSeconds: null,
        bytes: Uint8List(256),
        reserveRequestId: 'reserve-request-a',
        finalizeRequestId: 'finalize-request-a',
      );
      await accountA.setReservation(
        saved.id,
        DirectAttachmentReservationRecord(
          conversationId: 'account-a_friend',
          messageId: 'm_restart',
          storagePath: 'message_attachments/account-a/restart.jpg',
          type: MessageType.image,
          expiresAt: DateTime.utc(2030),
          clientExpiresAt: DateTime.utc(2030),
        ),
      );

      final accountB = DirectAttachmentOutbox(
        ownerId: 'account-b',
        preferences: preferences,
        payloadStore: payloadStore,
      );
      await accountB.load();
      expect(accountB.entries, isEmpty);
      expect(
        await payloadStore.keys(accountB.accountNamespace),
        isEmpty,
        reason: 'a second signed-in account cannot enumerate account A media',
      );

      final restartedA = DirectAttachmentOutbox(
        ownerId: 'account-a',
        preferences: preferences,
        payloadStore: payloadStore,
      );
      await restartedA.load();
      expect(restartedA.entries, hasLength(1));
      expect(restartedA.entries.single.reserveRequestId, 'reserve-request-a');
      expect(restartedA.entries.single.finalizeRequestId, 'finalize-request-a');
      expect(restartedA.entries.single.reservation?.messageId, 'm_restart');
      expect(
        await payloadStore.exists(restartedA.accountNamespace, saved.id),
        isTrue,
      );
    },
  );

  test('a failed payload is retained until explicit discard', () async {
    final queue = DirectAttachmentOutbox(
      ownerId: 'account-a',
      preferences: preferences,
      payloadStore: payloadStore,
      idFactory: () => 'attachment_failed_1',
    );
    final saved = await queue.enqueue(
      fingerprint: List<String>.filled(64, 'b').join(),
      conversationId: 'account-a_friend',
      type: MessageType.voice,
      contentType: 'audio/mp4',
      durationSeconds: 7,
      bytes: Uint8List(2048),
      reserveRequestId: 'reserve-request-b',
      finalizeRequestId: 'finalize-request-b',
    );

    await queue.markFailed(saved.id, StateError('permanent refusal'));
    expect(queue.entries.single.status, DirectAttachmentOutboxStatus.failed);
    expect(await payloadStore.exists(queue.accountNamespace, saved.id), isTrue);

    await queue.discard(saved.id);
    expect(queue.entries, isEmpty);
    expect(
      await payloadStore.exists(queue.accountNamespace, saved.id),
      isFalse,
    );
  });

  test('public discard refuses queued/retrying work but canonical complete '
      'can remove it', () async {
    final queue = DirectAttachmentOutbox(
      ownerId: 'account-a',
      preferences: preferences,
      payloadStore: payloadStore,
      idFactory: () => 'attachment_private_1',
    );
    final saved = await queue.enqueue(
      fingerprint: List<String>.filled(64, 'e').join(),
      conversationId: 'account-a_friend',
      type: MessageType.image,
      contentType: 'image/jpeg',
      durationSeconds: null,
      bytes: Uint8List(256),
      reserveRequestId: 'reserve-request-private',
      finalizeRequestId: 'finalize-request-private',
    );

    await expectLater(queue.discard(saved.id), throwsA(isA<StateError>()));
    await queue.markRetry(saved.id, StateError('offline'));
    await expectLater(queue.discard(saved.id), throwsA(isA<StateError>()));
    expect(await payloadStore.exists(queue.accountNamespace, saved.id), isTrue);

    await queue.complete(saved.id);
    expect(queue.entries, isEmpty);
    expect(
      await payloadStore.exists(queue.accountNamespace, saved.id),
      isFalse,
    );
  });

  test('a stale failed-card discard loses its race with retry', () async {
    final queue = DirectAttachmentOutbox(
      ownerId: 'account-a',
      preferences: preferences,
      payloadStore: payloadStore,
      idFactory: () => 'attachment_race_1',
    );
    final saved = await queue.enqueue(
      fingerprint: List<String>.filled(64, 'f').join(),
      conversationId: 'account-a_friend',
      type: MessageType.voice,
      contentType: 'audio/mp4',
      durationSeconds: 4,
      bytes: Uint8List(2048),
      reserveRequestId: 'reserve-request-race',
      finalizeRequestId: 'finalize-request-race',
    );
    await queue.markFailed(saved.id, StateError('offline too long'));

    await queue.retryNow(saved.id);
    await expectLater(queue.discard(saved.id), throwsA(isA<StateError>()));

    expect(queue.entries.single.status, DirectAttachmentOutboxStatus.queued);
    expect(await payloadStore.exists(queue.accountNamespace, saved.id), isTrue);
  });

  test(
    'entry and byte caps refuse new work without evicting pending media',
    () async {
      var nextId = 0;
      final queue = DirectAttachmentOutbox(
        ownerId: 'account-a',
        preferences: preferences,
        payloadStore: payloadStore,
        capacity: 1,
        maxPayloadBytes: 300,
        idFactory: () => 'attachment_cap_${nextId++}',
      );
      final first = await queue.enqueue(
        fingerprint: List<String>.filled(64, 'c').join(),
        conversationId: 'account-a_friend',
        type: MessageType.image,
        contentType: 'image/jpeg',
        durationSeconds: null,
        bytes: Uint8List(256),
        reserveRequestId: 'reserve-request-c',
        finalizeRequestId: 'finalize-request-c',
      );

      await expectLater(
        queue.enqueue(
          fingerprint: List<String>.filled(64, 'd').join(),
          conversationId: 'account-a_friend',
          type: MessageType.image,
          contentType: 'image/jpeg',
          durationSeconds: null,
          bytes: Uint8List(128),
          reserveRequestId: 'reserve-request-d',
          finalizeRequestId: 'finalize-request-d',
        ),
        throwsA(isA<DirectAttachmentOutboxFullException>()),
      );
      expect(queue.entries.single.id, first.id);
      expect(
        await payloadStore.exists(queue.accountNamespace, first.id),
        isTrue,
      );

      await queue.markFailed(first.id, StateError('person can now discard'));
      await queue.discard(first.id);
      final recovered = await queue.enqueue(
        fingerprint: List<String>.filled(64, 'd').join(),
        conversationId: 'account-a_friend',
        type: MessageType.image,
        contentType: 'image/jpeg',
        durationSeconds: null,
        bytes: Uint8List(128),
        reserveRequestId: 'reserve-request-d',
        finalizeRequestId: 'finalize-request-d',
      );
      expect(queue.entries.single.id, recovered.id);
      expect(
        await payloadStore.exists(queue.accountNamespace, first.id),
        false,
      );
    },
  );

  test('a transient payload-store load failure remains retryable', () async {
    payloadStore.failNextKeys = true;
    final queue = DirectAttachmentOutbox(
      ownerId: 'account-a',
      preferences: preferences,
      payloadStore: payloadStore,
    );

    await expectLater(queue.load(), throwsA(isA<StateError>()));
    await queue.load();

    expect(payloadStore.keysCalls, 2);
    expect(queue.entries, isEmpty);
  });

  test(
    'sign-out clear removes both private metadata and payload bytes',
    () async {
      final queue = DirectAttachmentOutbox(
        ownerId: 'account-a',
        preferences: preferences,
        payloadStore: payloadStore,
        idFactory: () => 'attachment_logout_1',
      );
      final saved = await queue.enqueue(
        fingerprint: List<String>.filled(64, '9').join(),
        conversationId: 'private-conversation',
        type: MessageType.voice,
        contentType: 'audio/mp4',
        durationSeconds: 12,
        bytes: Uint8List(2048),
        reserveRequestId: 'reserve-logout',
        finalizeRequestId: 'finalize-logout',
      );
      expect(
        await payloadStore.exists(queue.accountNamespace, saved.id),
        isTrue,
      );

      await queue.clear();

      expect(queue.entries, isEmpty);
      expect(await payloadStore.keys(queue.accountNamespace), isEmpty);
      expect(
        preferences.getString(
          'messages.attachment_outbox.v1.${queue.accountNamespace}',
        ),
        isNull,
      );
    },
  );
}

class _MemoryPayloadStore implements DirectAttachmentPayloadStore {
  final Map<String, Uint8List> _payloads = <String, Uint8List>{};
  bool failNextKeys = false;
  int keysCalls = 0;

  String _key(String namespace, String id) => '$namespace:$id';

  @override
  Future<void> write(String namespace, String id, Uint8List bytes) async {
    _payloads[_key(namespace, id)] = Uint8List.fromList(bytes);
  }

  @override
  Future<bool> exists(String namespace, String id) async =>
      _payloads.containsKey(_key(namespace, id));

  @override
  Future<Set<String>> keys(String namespace) async {
    keysCalls += 1;
    if (failNextKeys) {
      failNextKeys = false;
      throw StateError('temporary payload-store failure');
    }
    final prefix = '$namespace:';
    return _payloads.keys
        .where((key) => key.startsWith(prefix))
        .map((key) => key.substring(prefix.length))
        .toSet();
  }

  @override
  Future<String> upload(
    String namespace,
    String id,
    Reference reference,
    SettableMetadata metadata,
  ) => throw UnimplementedError();

  @override
  Future<void> delete(String namespace, String id) async {
    _payloads.remove(_key(namespace, id));
  }

  @override
  Future<void> clear(String namespace) async {
    final prefix = '$namespace:';
    _payloads.removeWhere((key, _) => key.startsWith(prefix));
  }
}
