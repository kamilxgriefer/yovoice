import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/messages/data/services/direct_attachment_payload_store.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_outbox.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/services/audio_capture/audio_capture_io.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const conversationId = 'alice-uid_bob-uid';
  const messageId = 'm_0123456789abcdef0123456789abcdef01234567';
  const storagePath =
      'message_attachments/alice-uid/$conversationId/$messageId.m4a';

  MockFirebaseAuth signedInAuth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'alice-uid', email: 'alice@yovoice.app'),
  );

  late _MemoryPayloadStore payloadStore;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    payloadStore = _MemoryPayloadStore();
  });

  test('voice upload uses the reserved private path and retries finalize with '
      'one request id after a lost response', () async {
    final functions = _AttachmentFunctions(
      conversationId: conversationId,
      messageId: messageId,
      storagePath: storagePath,
      loseFirstFinalizeResponse: true,
    );
    final recording = _Recording(
      byteLength: 4096,
      contentType: 'audio/mp4;codecs=mp4a.40.2',
    );
    final service = MessageService(
      firestore: FakeFirebaseFirestore(),
      auth: signedInAuth(),
      functions: functions,
      storage: MockFirebaseStorage(),
      attachmentPayloadStore: payloadStore,
    );

    await service.sendVoiceMessage(
      conversationId: conversationId,
      audio: recording,
      durationSeconds: 7,
    );

    expect(recording.uploadCount, 0);
    expect(payloadStore.uploadCount, 1);
    expect(payloadStore.uploadPath, storagePath);
    expect(payloadStore.contentTypeAtUpload, 'audio/mp4');
    expect(payloadStore.customMetadataAtUpload, {
      'yovoiceConversationId': conversationId,
      'yovoiceMessageId': messageId,
      'yovoiceMessagePath': 'conversations/$conversationId/messages/$messageId',
      'yovoiceMediaType': 'voice',
      'yovoiceOwnerUid': 'alice-uid',
    });

    expect(functions.reservePayloads, hasLength(1));
    expect(functions.reservePayloads.single, containsPair('type', 'voice'));
    expect(
      functions.reservePayloads.single,
      containsPair('contentType', 'audio/mp4'),
    );
    expect(
      functions.reservePayloads.single,
      containsPair('durationSeconds', 7),
    );

    expect(functions.finalizePayloads, hasLength(2));
    expect(
      functions.finalizePayloads.map((payload) => payload['requestId']).toSet(),
      hasLength(1),
      reason:
          'a retry after a committed-but-lost response must address the '
          'same idempotency ledger entry',
    );
    expect(
      functions.finalizePayloads.every(
        (payload) => payload['objectGeneration'] == 'generation-7',
      ),
      isTrue,
    );
  });

  test(
    'short video uses the reserved private path, MIME and duration',
    () async {
      const videoMessageId = 'm_abcdefabcdefabcdefabcdefabcdefabcdefabcd';
      const videoStoragePath =
          'message_attachments/alice-uid/$conversationId/$videoMessageId.mp4';
      final functions = _AttachmentFunctions(
        conversationId: conversationId,
        messageId: videoMessageId,
        storagePath: videoStoragePath,
        mediaType: 'video',
      );
      final service = MessageService(
        firestore: FakeFirebaseFirestore(),
        auth: signedInAuth(),
        functions: functions,
        storage: MockFirebaseStorage(),
        attachmentPayloadStore: payloadStore,
      );

      await service.sendVideoMessage(
        conversationId: conversationId,
        video: XFile.fromData(
          Uint8List(4096),
          mimeType: 'video/mp4',
          name: 'clip.mp4',
        ),
        durationSeconds: 23,
      );

      expect(payloadStore.uploadPath, videoStoragePath);
      expect(payloadStore.contentTypeAtUpload, 'video/mp4');
      expect(payloadStore.customMetadataAtUpload?['yovoiceMediaType'], 'video');
      expect(functions.reservePayloads.single, containsPair('type', 'video'));
      expect(
        functions.reservePayloads.single,
        containsPair('durationSeconds', 23),
      );
      expect(functions.finalizePayloads, hasLength(1));
    },
  );

  test(
    'video rejects an unsafe duration or undersized payload before reserve',
    () async {
      final functions = _CountingFunctions();
      final service = MessageService(
        firestore: FakeFirebaseFirestore(),
        auth: signedInAuth(),
        functions: functions,
        storage: MockFirebaseStorage(),
        attachmentPayloadStore: payloadStore,
      );
      final validBytes = XFile.fromData(
        Uint8List(2048),
        mimeType: 'video/mp4',
        name: 'clip.mp4',
      );

      await expectLater(
        service.sendVideoMessage(
          conversationId: conversationId,
          video: validBytes,
          durationSeconds: 61,
        ),
        throwsStateError,
      );
      await expectLater(
        service.sendVideoMessage(
          conversationId: conversationId,
          video: XFile.fromData(
            Uint8List(512),
            mimeType: 'video/mp4',
            name: 'tiny.mp4',
          ),
          durationSeconds: 4,
        ),
        throwsStateError,
      );
      expect(functions.calls, 0);
    },
  );

  test(
    'oversized photos and videos are rejected before allocating bytes',
    () async {
      final functions = _CountingFunctions();
      final service = MessageService(
        firestore: FakeFirebaseFirestore(),
        auth: signedInAuth(),
        functions: functions,
        storage: MockFirebaseStorage(),
        attachmentPayloadStore: payloadStore,
      );
      final photo = _LengthGuardXFile(8 * 1024 * 1024 + 1);
      final video = _LengthGuardXFile(64 * 1024 * 1024 + 1);

      await expectLater(
        service.sendImageMessage(conversationId: conversationId, image: photo),
        throwsStateError,
      );
      await expectLater(
        service.sendVideoMessage(
          conversationId: conversationId,
          video: video,
          durationSeconds: 4,
        ),
        throwsStateError,
      );

      expect(photo.readCalled, isFalse);
      expect(video.readCalled, isFalse);
      expect(functions.calls, 0);
    },
  );

  test('an upload committed with a lost response recovers generation from '
      'the same reservation instead of creating another one', () async {
    final functions = _AttachmentFunctions(
      conversationId: conversationId,
      messageId: messageId,
      storagePath: storagePath,
    );
    final recording = _Recording(byteLength: 4096, contentType: 'audio/mp4');
    final storage = _RecoveryStorage();
    payloadStore.commitThenLoseResponse = true;
    final service = MessageService(
      firestore: FakeFirebaseFirestore(),
      auth: signedInAuth(),
      functions: functions,
      storage: storage,
      attachmentPayloadStore: payloadStore,
    );

    await service.sendVoiceMessage(
      conversationId: conversationId,
      audio: recording,
      durationSeconds: 7,
    );

    expect(recording.uploadCount, 0);
    expect(payloadStore.uploadCount, 1);
    expect(functions.reservePayloads, hasLength(1));
    expect(functions.finalizePayloads, hasLength(1));
    expect(
      functions.finalizePayloads.single['objectGeneration'],
      isNot(isEmpty),
    );
  });

  test('manual retry after three lost finalize responses reuses reservation, '
      'upload, message id and idempotency request', () async {
    final db = FakeFirebaseFirestore();
    final functions = _LostFinalizeCommitFunctions(
      db: db,
      conversationId: conversationId,
      messageId: messageId,
      storagePath: storagePath,
    );
    final recording = _Recording(byteLength: 4096, contentType: 'audio/mp4');
    final service = MessageService(
      firestore: db,
      auth: signedInAuth(),
      functions: functions,
      storage: MockFirebaseStorage(),
      attachmentPayloadStore: payloadStore,
    );

    await expectLater(
      service.sendVoiceMessage(
        conversationId: conversationId,
        audio: recording,
        durationSeconds: 7,
      ),
      throwsA(
        isA<FirebaseFunctionsException>().having(
          (error) => error.code,
          'code',
          'unavailable',
        ),
      ),
    );

    await service.sendVoiceMessage(
      conversationId: conversationId,
      audio: recording,
      durationSeconds: 7,
    );

    expect(functions.reservePayloads, hasLength(1));
    expect(recording.uploadCount, 0);
    expect(payloadStore.uploadCount, 1);
    expect(functions.finalizePayloads, hasLength(4));
    expect(
      functions.finalizePayloads.map((payload) => payload['requestId']).toSet(),
      hasLength(1),
    );
    expect(
      functions.finalizePayloads.map((payload) => payload['messageId']).toSet(),
      {messageId},
    );
    expect(
      functions.finalizePayloads
          .map((payload) => payload['objectGeneration'])
          .toSet(),
      {'generation-7'},
    );
    final committed = await db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .get();
    expect(committed.docs, hasLength(1));
    expect(committed.docs.single.id, messageId);
  });

  test('Retry on a failed media entry preserves its valid reservation and '
      'both idempotency ids', () async {
    final functions = _AttachmentFunctions(
      conversationId: conversationId,
      messageId: messageId,
      storagePath: storagePath,
      rejectFinalize: true,
    );
    final service = MessageService(
      firestore: FakeFirebaseFirestore(),
      auth: signedInAuth(),
      functions: functions,
      storage: MockFirebaseStorage(),
      attachmentPayloadStore: payloadStore,
    );

    await expectLater(
      service.sendVoiceMessage(
        conversationId: conversationId,
        audio: _Recording(byteLength: 4096, contentType: 'audio/mp4'),
        durationSeconds: 7,
      ),
      throwsA(isA<FirebaseFunctionsException>()),
    );
    final failed = service.attachmentOutbox.entries.single;
    final reservation = failed.reservation;
    final reserveRequestId = failed.reserveRequestId;
    final finalizeRequestId = failed.finalizeRequestId;
    expect(failed.status, DirectAttachmentOutboxStatus.failed);

    functions.rejectFinalize = false;
    await service.retryFailedAttachment(failed.id);

    expect(service.attachmentOutbox.entries, isEmpty);
    expect(functions.reservePayloads, hasLength(1));
    expect(functions.reservePayloads.single['requestId'], reserveRequestId);
    expect(functions.finalizePayloads, hasLength(2));
    expect(
      functions.finalizePayloads.map((item) => item['requestId']).toSet(),
      <Object?>{finalizeRequestId},
    );
    expect(
      functions.finalizePayloads.map((item) => item['messageId']).toSet(),
      <Object?>{reservation?.messageId},
    );
    expect(payloadStore.uploadCount, 1);
  });

  test('manual image retry keys identical bytes across distinct XFile objects '
      'to one pending operation', () async {
    const imageMessageId = 'm_abcdefabcdefabcdefabcdefabcdefabcdefabcd';
    const imageStoragePath =
        'message_attachments/alice-uid/$conversationId/$imageMessageId.jpg';
    final db = FakeFirebaseFirestore();
    final functions = _LostFinalizeCommitFunctions(
      db: db,
      conversationId: conversationId,
      messageId: imageMessageId,
      storagePath: imageStoragePath,
      mediaType: 'image',
    );
    final storage = _RecoveryStorage();
    final service = MessageService(
      firestore: db,
      auth: signedInAuth(),
      functions: functions,
      storage: storage,
      attachmentPayloadStore: payloadStore,
    );
    XFile photo() => XFile.fromData(
      Uint8List(256),
      mimeType: 'image/jpeg',
      name: 'photo.jpg',
    );

    await expectLater(
      service.sendImageMessage(conversationId: conversationId, image: photo()),
      throwsA(isA<FirebaseFunctionsException>()),
    );
    await service.sendImageMessage(
      conversationId: conversationId,
      image: photo(),
    );

    expect(functions.reservePayloads, hasLength(1));
    expect(storage.putCount, 1);
    expect(functions.finalizePayloads, hasLength(4));
    expect(
      functions.finalizePayloads.map((payload) => payload['requestId']).toSet(),
      hasLength(1),
    );
    final committed = await db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .get();
    expect(committed.docs, hasLength(1));
    expect(committed.docs.single.id, imageMessageId);
  });

  test('photo finalize resumes after a process restart with the same canonical '
      'reservation and deletes its durable bytes only after success', () async {
    const imageMessageId = 'm_restartimage0123456789012345678901234567';
    const imageStoragePath =
        'message_attachments/alice-uid/$conversationId/$imageMessageId.jpg';
    final db = FakeFirebaseFirestore();
    final functions = _LostFinalizeCommitFunctions(
      db: db,
      conversationId: conversationId,
      messageId: imageMessageId,
      storagePath: imageStoragePath,
      mediaType: 'image',
    );
    final storage = _RecoveryStorage();
    final preferences = await SharedPreferences.getInstance();
    var now = DateTime.utc(2026, 8, 28, 12);
    DirectAttachmentOutbox queue() => DirectAttachmentOutbox(
      ownerId: 'alice-uid',
      preferences: preferences,
      payloadStore: payloadStore,
      clock: () => now,
    );
    final firstQueue = queue();
    final firstProcess = MessageService(
      firestore: db,
      auth: signedInAuth(),
      functions: functions,
      storage: storage,
      attachmentOutbox: firstQueue,
    );
    final photo = XFile.fromData(
      Uint8List(512),
      mimeType: 'image/jpeg',
      name: 'restart.jpg',
    );

    await expectLater(
      firstProcess.sendImageMessage(
        conversationId: conversationId,
        image: photo,
      ),
      throwsA(isA<FirebaseFunctionsException>()),
    );
    expect(firstQueue.entries, hasLength(1));
    final beforeRestart = firstQueue.entries.single;
    expect(beforeRestart.reservation?.messageId, imageMessageId);
    expect(beforeRestart.generation, 'generation-7');
    expect(payloadStore.payloads, hasLength(1));
    await firstProcess.dispose();

    now = now.add(const Duration(seconds: 2));
    final restartedQueue = queue();
    final restartedProcess = MessageService(
      firestore: db,
      auth: signedInAuth(),
      functions: functions,
      storage: storage,
      attachmentOutbox: restartedQueue,
    );
    await restartedProcess.flushAttachmentOutbox();

    expect(restartedQueue.entries, isEmpty);
    expect(payloadStore.payloads, isEmpty);
    expect(functions.reservePayloads, hasLength(1));
    expect(
      storage.putCount,
      1,
      reason: 'the uploaded object is not duplicated',
    );
    expect(
      functions.finalizePayloads.map((item) => item['requestId']).toSet(),
      <Object?>{beforeRestart.finalizeRequestId},
    );
    final committed = await db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .get();
    expect(committed.docs.single.id, imageMessageId);
    await restartedProcess.dispose();
  });

  test('voice payload survives a process restart before upload and retries '
      'from the durable copy', () async {
    const voiceMessageId = 'm_restartvoice0123456789012345678901234567';
    const voiceStoragePath =
        'message_attachments/alice-uid/$conversationId/$voiceMessageId.m4a';
    final functions = _AttachmentFunctions(
      conversationId: conversationId,
      messageId: voiceMessageId,
      storagePath: voiceStoragePath,
    );
    final preferences = await SharedPreferences.getInstance();
    var now = DateTime.utc(2026, 8, 28, 12);
    DirectAttachmentOutbox queue() => DirectAttachmentOutbox(
      ownerId: 'alice-uid',
      preferences: preferences,
      payloadStore: payloadStore,
      clock: () => now,
    );
    final tempDirectory = await Directory.systemTemp.createTemp(
      'yovoice-durable-voice-test-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final tempFile = File('${tempDirectory.path}/voice.m4a');
    await tempFile.writeAsBytes(Uint8List(4096), flush: true);
    final recording = FileRecordedAudio(tempFile, 4096);
    payloadStore.uploadFailuresRemaining = 3;
    final firstQueue = queue();
    final firstProcess = MessageService(
      firestore: FakeFirebaseFirestore(),
      auth: signedInAuth(),
      functions: functions,
      storage: MockFirebaseStorage(),
      attachmentOutbox: firstQueue,
    );

    await expectLater(
      firstProcess.sendVoiceMessage(
        conversationId: conversationId,
        audio: recording,
        durationSeconds: 7,
      ),
      throwsA(isA<FirebaseException>()),
    );
    expect(firstQueue.entries, hasLength(1));
    final beforeRestart = firstQueue.entries.single;
    expect(beforeRestart.reservation?.messageId, voiceMessageId);
    expect(beforeRestart.generation, isNull);
    expect(payloadStore.payloads, hasLength(1));
    await firstProcess.dispose();
    await recording.discard();
    expect(await tempFile.exists(), isFalse);
    payloadStore.uploadCount = 0;

    now = now.add(const Duration(seconds: 2));
    final restoredStorage = _RecoveryStorage();
    final restartedQueue = queue();
    final restartedProcess = MessageService(
      firestore: FakeFirebaseFirestore(),
      auth: signedInAuth(),
      functions: functions,
      storage: restoredStorage,
      attachmentOutbox: restartedQueue,
    );
    await restartedProcess.flushAttachmentOutbox();

    expect(restartedQueue.entries, isEmpty);
    expect(payloadStore.payloads, isEmpty);
    expect(payloadStore.uploadCount, 1);
    expect(restoredStorage.putCount, 1);
    expect(functions.reservePayloads, hasLength(1));
    expect(functions.finalizePayloads, hasLength(1));
    expect(
      functions.finalizePayloads.single['requestId'],
      beforeRestart.finalizeRequestId,
    );
    await restartedProcess.dispose();
  });

  test('a cold restart after reservation expiry rotates message path and both '
      'idempotency ids without losing durable voice bytes', () async {
    final preferences = await SharedPreferences.getInstance();
    var now = DateTime.utc(2026, 8, 28, 12);
    final functions = _ExpiringAttachmentFunctions(
      conversationId: conversationId,
      clock: () => now,
    );
    DirectAttachmentOutbox queue() => DirectAttachmentOutbox(
      ownerId: 'alice-uid',
      preferences: preferences,
      payloadStore: payloadStore,
      clock: () => now,
    );
    payloadStore.uploadFailuresRemaining = 3;
    final firstQueue = queue();
    final firstProcess = MessageService(
      firestore: FakeFirebaseFirestore(),
      auth: signedInAuth(),
      functions: functions,
      storage: MockFirebaseStorage(),
      attachmentOutbox: firstQueue,
    );

    await expectLater(
      firstProcess.sendVoiceMessage(
        conversationId: conversationId,
        audio: _Recording(byteLength: 4096, contentType: 'audio/mp4'),
        durationSeconds: 7,
      ),
      throwsA(isA<FirebaseException>()),
    );
    final expired = firstQueue.entries.single;
    final expiredMessageId = expired.reservation!.messageId;
    final expiredReserveRequestId = expired.reserveRequestId;
    final expiredFinalizeRequestId = expired.finalizeRequestId;
    expect(payloadStore.payloads, hasLength(1));
    await firstProcess.dispose();

    now = now.add(const Duration(minutes: 16));
    final restartedQueue = queue();
    final restarted = MessageService(
      firestore: FakeFirebaseFirestore(),
      auth: signedInAuth(),
      functions: functions,
      storage: MockFirebaseStorage(),
      attachmentOutbox: restartedQueue,
    );
    await restarted.flushAttachmentOutbox();

    expect(restartedQueue.entries, isEmpty);
    expect(payloadStore.payloads, isEmpty);
    expect(functions.reservePayloads, hasLength(2));
    expect(
      functions.reservePayloads.map((item) => item['requestId']).toSet(),
      hasLength(2),
    );
    expect(
      functions.reservePayloads.last['requestId'],
      isNot(expiredReserveRequestId),
    );
    expect(functions.finalizePayloads, hasLength(1));
    expect(
      functions.finalizePayloads.single['messageId'],
      isNot(expiredMessageId),
    );
    expect(
      functions.finalizePayloads.single['requestId'],
      isNot(expiredFinalizeRequestId),
    );
    await restarted.dispose();
  });

  test('a server-expired finalize rotates even when the client clock is two '
      'hours behind', () async {
    final preferences = await SharedPreferences.getInstance();
    final serverNow = DateTime.utc(2026, 8, 28, 12);
    final clientNow = serverNow.subtract(const Duration(hours: 2));
    final functions = _SkewedAttachmentFunctions(
      conversationId: conversationId,
      serverNow: serverNow,
      rejectFirstFinalizeAsExpired: true,
    );
    final queue = DirectAttachmentOutbox(
      ownerId: 'alice-uid',
      preferences: preferences,
      payloadStore: payloadStore,
      clock: () => clientNow,
    );
    final service = MessageService(
      firestore: FakeFirebaseFirestore(),
      auth: signedInAuth(),
      functions: functions,
      storage: MockFirebaseStorage(),
      attachmentOutbox: queue,
    );

    await service.sendVoiceMessage(
      conversationId: conversationId,
      audio: _Recording(byteLength: 4096, contentType: 'audio/mp4'),
      durationSeconds: 7,
    );

    expect(functions.reservePayloads, hasLength(2));
    expect(
      functions.reservePayloads.map((item) => item['requestId']).toSet(),
      hasLength(2),
    );
    expect(functions.finalizePayloads, hasLength(2));
    expect(
      functions.finalizePayloads.first['messageId'],
      isNot(functions.finalizePayloads.last['messageId']),
    );
    expect(queue.entries, isEmpty);
    await service.dispose();
  });

  test('an authoritative upload expiry rotates while the local lease still '
      'looks valid', () async {
    final preferences = await SharedPreferences.getInstance();
    final serverNow = DateTime.utc(2026, 8, 28, 12);
    final functions = _SkewedAttachmentFunctions(
      conversationId: conversationId,
      serverNow: serverNow,
    );
    payloadStore
      ..uploadFailuresRemaining = 3
      ..uploadFailure = FirebaseException(
        plugin: 'firebase_storage',
        code: 'failed-precondition',
        message: 'The attachment reservation has expired.',
      );
    final queue = DirectAttachmentOutbox(
      ownerId: 'alice-uid',
      preferences: preferences,
      payloadStore: payloadStore,
      clock: () => serverNow.subtract(const Duration(hours: 2)),
    );
    final service = MessageService(
      firestore: FakeFirebaseFirestore(),
      auth: signedInAuth(),
      functions: functions,
      storage: MockFirebaseStorage(),
      attachmentOutbox: queue,
    );

    await service.sendVoiceMessage(
      conversationId: conversationId,
      audio: _Recording(byteLength: 4096, contentType: 'audio/mp4'),
      durationSeconds: 7,
    );

    expect(functions.reservePayloads, hasLength(2));
    expect(payloadStore.uploadCount, 4);
    expect(functions.finalizePayloads, hasLength(1));
    expect(
      functions.finalizePayloads.single['messageId'],
      contains(List<String>.filled(40, '2').join()),
    );
    await service.dispose();
  });

  test('an authoritative reserve expiry gets a new reserve request within the '
      'bounded delivery loop', () async {
    final preferences = await SharedPreferences.getInstance();
    final serverNow = DateTime.utc(2026, 8, 28, 12);
    final functions = _SkewedAttachmentFunctions(
      conversationId: conversationId,
      serverNow: serverNow,
      rejectFirstReserveAsExpired: true,
    );
    final queue = DirectAttachmentOutbox(
      ownerId: 'alice-uid',
      preferences: preferences,
      payloadStore: payloadStore,
      clock: () => serverNow,
    );
    final service = MessageService(
      firestore: FakeFirebaseFirestore(),
      auth: signedInAuth(),
      functions: functions,
      storage: MockFirebaseStorage(),
      attachmentOutbox: queue,
    );

    await service.sendVoiceMessage(
      conversationId: conversationId,
      audio: _Recording(byteLength: 4096, contentType: 'audio/mp4'),
      durationSeconds: 7,
    );

    expect(functions.reservePayloads, hasLength(2));
    expect(
      functions.reservePayloads.map((item) => item['requestId']).toSet(),
      hasLength(2),
    );
    expect(functions.finalizePayloads, hasLength(1));
    await service.dispose();
  });

  test('a freshly issued server lease does not rotate-loop when the client '
      'clock is two hours ahead', () async {
    final preferences = await SharedPreferences.getInstance();
    final serverNow = DateTime.utc(2026, 8, 28, 12);
    final functions = _SkewedAttachmentFunctions(
      conversationId: conversationId,
      serverNow: serverNow,
    );
    final queue = DirectAttachmentOutbox(
      ownerId: 'alice-uid',
      preferences: preferences,
      payloadStore: payloadStore,
      clock: () => serverNow.add(const Duration(hours: 2)),
    );
    final service = MessageService(
      firestore: FakeFirebaseFirestore(),
      auth: signedInAuth(),
      functions: functions,
      storage: MockFirebaseStorage(),
      attachmentOutbox: queue,
    );

    await service.sendVoiceMessage(
      conversationId: conversationId,
      audio: _Recording(byteLength: 4096, contentType: 'audio/mp4'),
      durationSeconds: 7,
    );

    expect(functions.reservePayloads, hasLength(1));
    expect(payloadStore.uploadCount, 1);
    expect(functions.finalizePayloads, hasLength(1));
    await service.dispose();
  });

  test(
    'server refusal never falls back to a client-owned media write',
    () async {
      final functions = _RejectingAttachmentFunctions();
      final recording = _Recording(byteLength: 4096, contentType: 'audio/mp4');
      final service = MessageService(
        firestore: FakeFirebaseFirestore(),
        auth: signedInAuth(),
        functions: functions,
        storage: MockFirebaseStorage(),
        attachmentPayloadStore: payloadStore,
      );

      await expectLater(
        service.sendVoiceMessage(
          conversationId: conversationId,
          audio: recording,
          durationSeconds: 7,
        ),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );

      expect(recording.uploadCount, 0);
    },
  );

  test(
    'oversized and spoofed recordings are rejected before reservation',
    () async {
      final functions = _CountingFunctions();
      final service = MessageService(
        firestore: FakeFirebaseFirestore(),
        auth: signedInAuth(),
        functions: functions,
        storage: MockFirebaseStorage(),
        attachmentPayloadStore: payloadStore,
      );

      await expectLater(
        service.sendVoiceMessage(
          conversationId: conversationId,
          audio: _Recording(
            byteLength: kMaxPublishableAudioBytes + 1,
            contentType: 'audio/mp4',
          ),
          durationSeconds: 60,
        ),
        throwsA(isA<VoiceRecordingException>()),
      );
      await expectLater(
        service.sendVoiceMessage(
          conversationId: conversationId,
          audio: _Recording(byteLength: 4096, contentType: 'audio/mpeg'),
          durationSeconds: 7,
        ),
        throwsA(isA<VoiceRecordingException>()),
      );

      expect(functions.calls, 0);
    },
  );
}

class _MemoryPayloadStore implements DirectAttachmentPayloadStore {
  final Map<String, Uint8List> payloads = <String, Uint8List>{};
  int uploadCount = 0;
  int uploadFailuresRemaining = 0;
  Object? uploadFailure;
  bool commitThenLoseResponse = false;
  String? uploadPath;
  String? contentTypeAtUpload;
  Map<String, String>? customMetadataAtUpload;

  String _key(String namespace, String id) => '$namespace:$id';

  @override
  Future<void> write(String namespace, String id, Uint8List bytes) async {
    payloads[_key(namespace, id)] = Uint8List.fromList(bytes);
  }

  @override
  Future<bool> exists(String namespace, String id) async =>
      payloads.containsKey(_key(namespace, id));

  @override
  Future<Set<String>> keys(String namespace) async {
    final prefix = '$namespace:';
    return payloads.keys
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
  ) async {
    final bytes = payloads[_key(namespace, id)];
    if (bytes == null) throw StateError('missing test payload');
    uploadCount += 1;
    uploadPath = reference.fullPath;
    contentTypeAtUpload = metadata.contentType;
    customMetadataAtUpload = metadata.customMetadata;
    if (uploadFailuresRemaining > 0) {
      uploadFailuresRemaining -= 1;
      throw uploadFailure ??
          FirebaseException(
            plugin: 'firebase_storage',
            code: 'unavailable',
            message: 'temporary upload failure',
          );
    }
    await reference.putData(bytes, metadata);
    if (commitThenLoseResponse) {
      commitThenLoseResponse = false;
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'unknown',
        message: 'committed response was lost',
      );
    }
    return 'generation-7';
  }

  @override
  Future<void> delete(String namespace, String id) async {
    payloads.remove(_key(namespace, id));
  }

  @override
  Future<void> clear(String namespace) async {
    final prefix = '$namespace:';
    payloads.removeWhere((key, _) => key.startsWith(prefix));
  }
}

class _Recording extends RecordedAudio {
  _Recording({required this.byteLength, required this.contentType});

  @override
  final int byteLength;

  @override
  final String contentType;

  int uploadCount = 0;
  String? uploadPath;
  String? contentTypeAtUpload;
  Map<String, String>? customMetadataAtUpload;

  @override
  Future<Uint8List> readBytes() async => Uint8List(byteLength);

  @override
  Future<String> uploadTo(
    Reference reference,
    SettableMetadata metadata,
  ) async {
    uploadCount += 1;
    uploadPath = reference.fullPath;
    contentTypeAtUpload = metadata.contentType;
    customMetadataAtUpload = metadata.customMetadata;
    return 'generation-7';
  }

  @override
  Future<void> discard() async {}
}

class _RecoveryStorage implements FirebaseStorage {
  bool committed = false;
  int putCount = 0;
  String? storedContentType;
  Map<String, String>? storedCustomMetadata;

  @override
  Reference ref([String? path]) => _RecoveryReference(this, path ?? '');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecoveryReference implements Reference {
  _RecoveryReference(this.backend, this.fullPath);

  final _RecoveryStorage backend;

  @override
  final String fullPath;

  @override
  UploadTask putData(Uint8List data, [SettableMetadata? metadata]) {
    backend.putCount += 1;
    backend.committed = true;
    backend.storedContentType = metadata?.contentType;
    backend.storedCustomMetadata = metadata?.customMetadata;
    return _UploadTask(Future<TaskSnapshot>.value(_TaskSnapshot(this)));
  }

  @override
  Future<FullMetadata> getMetadata() async {
    if (!backend.committed) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'object-not-found',
      );
    }
    return _FullMetadata(
      contentType: backend.storedContentType,
      customMetadata: backend.storedCustomMetadata,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TaskSnapshot implements TaskSnapshot {
  _TaskSnapshot(this.ref);

  @override
  final Reference ref;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UploadTask implements UploadTask {
  _UploadTask(this._future);

  final Future<TaskSnapshot> _future;

  @override
  Stream<TaskSnapshot> asStream() => _future.asStream();

  @override
  Future<TaskSnapshot> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) => _future.catchError(onError, test: test);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(TaskSnapshot value) onValue, {
    Function? onError,
  }) => _future.then(onValue, onError: onError);

  @override
  Future<TaskSnapshot> timeout(
    Duration timeLimit, {
    FutureOr<TaskSnapshot> Function()? onTimeout,
  }) => _future.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<TaskSnapshot> whenComplete(FutureOr<void> Function() action) =>
      _future.whenComplete(action);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FullMetadata implements FullMetadata {
  _FullMetadata({required this.contentType, required this.customMetadata});

  @override
  final String? contentType;

  @override
  final Map<String, String>? customMetadata;

  @override
  String get generation => 'committed-generation';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AttachmentFunctions implements FirebaseFunctions {
  _AttachmentFunctions({
    required this.conversationId,
    required this.messageId,
    required this.storagePath,
    this.loseFirstFinalizeResponse = false,
    this.rejectFinalize = false,
    this.mediaType = 'voice',
  });

  final String conversationId;
  final String messageId;
  final String storagePath;
  final bool loseFirstFinalizeResponse;
  final String mediaType;
  bool rejectFinalize;
  final List<Map<String, dynamic>> reservePayloads = [];
  final List<Map<String, dynamic>> finalizePayloads = [];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    return _CallableStub((parameters) async {
      final payload = Map<String, dynamic>.from(parameters as Map);
      if (name == 'reserveDirectMessageAttachment') {
        reservePayloads.add(payload);
        return <Object?, Object?>{
          'conversationId': conversationId,
          'messageId': messageId,
          'storagePath': storagePath,
          'type': mediaType,
          'expiresAtMillis': DateTime.utc(2030).millisecondsSinceEpoch,
        };
      }
      if (name == 'finalizeDirectMessageAttachment') {
        finalizePayloads.add(payload);
        if (rejectFinalize) {
          throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'finalize refused',
          );
        }
        if (loseFirstFinalizeResponse && finalizePayloads.length == 1) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'The server committed, but the response was lost.',
          );
        }
        return <Object?, Object?>{
          'conversationId': conversationId,
          'messageId': messageId,
        };
      }
      throw StateError('Unexpected callable $name');
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LostFinalizeCommitFunctions implements FirebaseFunctions {
  _LostFinalizeCommitFunctions({
    required this.db,
    required this.conversationId,
    required this.messageId,
    required this.storagePath,
    this.mediaType = 'voice',
  });

  final FakeFirebaseFirestore db;
  final String conversationId;
  final String messageId;
  final String storagePath;
  final String mediaType;
  final List<Map<String, dynamic>> reservePayloads = [];
  final List<Map<String, dynamic>> finalizePayloads = [];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    return _CallableStub((parameters) async {
      final payload = Map<String, dynamic>.from(parameters as Map);
      if (name == 'reserveDirectMessageAttachment') {
        reservePayloads.add(payload);
        return <Object?, Object?>{
          'conversationId': conversationId,
          'messageId': messageId,
          'storagePath': storagePath,
          'type': mediaType,
          'expiresAtMillis': DateTime.utc(2030).millisecondsSinceEpoch,
        };
      }
      if (name == 'finalizeDirectMessageAttachment') {
        finalizePayloads.add(payload);
        final ref = db
            .collection('conversations')
            .doc(conversationId)
            .collection('messages')
            .doc(messageId);
        if (!(await ref.get()).exists) {
          await ref.set({
            'messageId': messageId,
            'requestId': payload['requestId'],
            'mediaUrl': 'gs://private/$storagePath',
          });
        }
        if (finalizePayloads.length <= 3) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'Committed response was lost.',
          );
        }
        return <Object?, Object?>{
          'conversationId': conversationId,
          'messageId': messageId,
        };
      }
      throw StateError('Unexpected callable $name');
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ExpiringAttachmentFunctions implements FirebaseFunctions {
  _ExpiringAttachmentFunctions({
    required this.conversationId,
    required this.clock,
  });

  final String conversationId;
  final DateTime Function() clock;
  final List<Map<String, dynamic>> reservePayloads = [];
  final List<Map<String, dynamic>> finalizePayloads = [];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    return _CallableStub((parameters) async {
      final payload = Map<String, dynamic>.from(parameters as Map);
      if (name == 'reserveDirectMessageAttachment') {
        reservePayloads.add(payload);
        final digit = reservePayloads.length == 1 ? '1' : '2';
        final messageId = 'm_${List<String>.filled(40, digit).join()}';
        return <Object?, Object?>{
          'conversationId': conversationId,
          'messageId': messageId,
          'storagePath':
              'message_attachments/alice-uid/$conversationId/$messageId.m4a',
          'type': 'voice',
          'expiresAtMillis': clock()
              .add(const Duration(minutes: 15))
              .millisecondsSinceEpoch,
        };
      }
      if (name == 'finalizeDirectMessageAttachment') {
        finalizePayloads.add(payload);
        return <Object?, Object?>{
          'conversationId': conversationId,
          'messageId': payload['messageId'],
        };
      }
      throw StateError('Unexpected callable $name');
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SkewedAttachmentFunctions implements FirebaseFunctions {
  _SkewedAttachmentFunctions({
    required this.conversationId,
    required this.serverNow,
    this.rejectFirstReserveAsExpired = false,
    this.rejectFirstFinalizeAsExpired = false,
  });

  final String conversationId;
  final DateTime serverNow;
  final bool rejectFirstReserveAsExpired;
  final bool rejectFirstFinalizeAsExpired;
  final List<Map<String, dynamic>> reservePayloads = [];
  final List<Map<String, dynamic>> finalizePayloads = [];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    return _CallableStub((parameters) async {
      final payload = Map<String, dynamic>.from(parameters as Map);
      if (name == 'reserveDirectMessageAttachment') {
        reservePayloads.add(payload);
        if (rejectFirstReserveAsExpired && reservePayloads.length == 1) {
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'The attachment reservation has expired.',
          );
        }
        final digit = reservePayloads.length == 1 ? '1' : '2';
        final messageId = 'm_${List<String>.filled(40, digit).join()}';
        return <Object?, Object?>{
          'conversationId': conversationId,
          'messageId': messageId,
          'storagePath':
              'message_attachments/alice-uid/$conversationId/$messageId.m4a',
          'type': 'voice',
          'expiresAtMillis': serverNow
              .add(const Duration(minutes: 15))
              .millisecondsSinceEpoch,
        };
      }
      if (name == 'finalizeDirectMessageAttachment') {
        finalizePayloads.add(payload);
        if (rejectFirstFinalizeAsExpired && finalizePayloads.length == 1) {
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'The attachment reservation is invalid.',
          );
        }
        return <Object?, Object?>{
          'conversationId': conversationId,
          'messageId': payload['messageId'],
        };
      }
      throw StateError('Unexpected callable $name');
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RejectingAttachmentFunctions implements FirebaseFunctions {
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    return _CallableStub(
      (_) async => throw FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'You cannot message this person.',
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingFunctions implements FirebaseFunctions {
  int calls = 0;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    return _CallableStub((_) async {
      calls += 1;
      return <Object?, Object?>{};
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LengthGuardXFile implements XFile {
  _LengthGuardXFile(this.declaredLength);

  final int declaredLength;
  bool readCalled = false;

  @override
  Future<int> length() async => declaredLength;

  @override
  Future<Uint8List> readAsBytes() async {
    readCalled = true;
    throw StateError('Oversized files must not be allocated.');
  }

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
