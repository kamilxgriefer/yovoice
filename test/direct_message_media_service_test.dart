import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';

void main() {
  const conversationId = 'alice-uid_bob-uid';
  const messageId = 'm_0123456789abcdef0123456789abcdef01234567';
  const storagePath =
      'message_attachments/alice-uid/$conversationId/$messageId.m4a';

  MockFirebaseAuth signedInAuth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: 'alice-uid', email: 'alice@yovoice.app'),
  );

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
    );

    await service.sendVoiceMessage(
      conversationId: conversationId,
      audio: recording,
      durationSeconds: 7,
    );

    expect(recording.uploadCount, 1);
    expect(recording.uploadPath, storagePath);
    expect(recording.contentTypeAtUpload, 'audio/mp4');
    expect(recording.customMetadataAtUpload, {
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

  test('an upload committed with a lost response recovers generation from '
      'the same reservation instead of creating another one', () async {
    final functions = _AttachmentFunctions(
      conversationId: conversationId,
      messageId: messageId,
      storagePath: storagePath,
    );
    final recording = _CommitThenLoseResponseRecording();
    final storage = _RecoveryStorage();
    final service = MessageService(
      firestore: FakeFirebaseFirestore(),
      auth: signedInAuth(),
      functions: functions,
      storage: storage,
    );

    await service.sendVoiceMessage(
      conversationId: conversationId,
      audio: recording,
      durationSeconds: 7,
    );

    expect(recording.uploadCount, 1);
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
    expect(recording.uploadCount, 1);
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

class _CommitThenLoseResponseRecording extends RecordedAudio {
  int uploadCount = 0;

  @override
  int get byteLength => 4096;

  @override
  String get contentType => 'audio/mp4';

  @override
  Future<String> uploadTo(
    Reference reference,
    SettableMetadata metadata,
  ) async {
    uploadCount += 1;
    await reference.putData(Uint8List(4096), metadata);
    throw FirebaseException(
      plugin: 'firebase_storage',
      code: 'unknown',
      message: 'The object committed, but the response was lost.',
    );
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
  });

  final String conversationId;
  final String messageId;
  final String storagePath;
  final bool loseFirstFinalizeResponse;
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
          'type': 'voice',
        };
      }
      if (name == 'finalizeDirectMessageAttachment') {
        finalizePayloads.add(payload);
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
