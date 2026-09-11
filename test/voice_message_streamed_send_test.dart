import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/messages/data/services/direct_attachment_delivery_progress.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_outbox.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_payload_source.dart';
import 'package:yovoice/features/messages/data/services/direct_attachment_payload_store.dart';
import 'package:yovoice/features/messages/data/services/message_service.dart';
import 'package:yovoice/features/moments/data/services/recorded_audio.dart';

/// The voice-message send path: streamed off the recording rather than
/// buffered, durable before the sheet closes, and honest about every later
/// outcome.
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

  late _StreamingPayloadStore payloadStore;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    payloadStore = _StreamingPayloadStore();
  });

  /// Lets pending microtasks and zero-delay futures run until [done] holds.
  Future<void> settle(bool Function() done) async {
    for (var turn = 0; turn < 400 && !done(); turn += 1) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  MessageService serviceWith(_AttachmentFunctions functions) => MessageService(
    firestore: FakeFirebaseFirestore(),
    auth: signedInAuth(),
    functions: functions,
    storage: MockFirebaseStorage(),
    attachmentPayloadStore: payloadStore,
  );

  _AttachmentFunctions attachmentFunctions({
    Completer<void>? reserveGate,
    bool refuseFinalize = false,
  }) => _AttachmentFunctions(
    conversationId: conversationId,
    messageId: messageId,
    storagePath: storagePath,
    reserveGate: reserveGate,
    refuseFinalize: refuseFinalize,
  );

  test('the recording is streamed into the outbox, never read whole', () async {
    final recording = _StreamedRecording(byteLength: 4096);
    final service = serviceWith(attachmentFunctions());

    await service.sendVoiceMessage(
      conversationId: conversationId,
      audio: recording,
      durationSeconds: 7,
    );

    expect(
      recording.readBytesCalls,
      0,
      reason: 'a finished recording is a file; it never needs to be resident',
    );
    expect(recording.openReadCalls, greaterThanOrEqualTo(1));
    expect(payloadStore.adoptCalls, 1);
    expect(payloadStore.largestChunk, lessThanOrEqualTo(512));
    expect(payloadStore.storedLength, 4096);
    expect(payloadStore.uploadPath, storagePath);
    expect(payloadStore.contentTypeAtUpload, 'audio/mp4');
  });

  test('the queue fingerprints exactly what it stored', () async {
    final recording = _StreamedRecording(byteLength: 4096);
    final service = serviceWith(attachmentFunctions(reserveGate: Completer()));

    await service.enqueueVoiceMessage(
      conversationId: conversationId,
      audio: recording,
      durationSeconds: 7,
    );

    final entry = service.attachmentOutbox.entries.single;
    expect(entry.byteLength, 4096);
    expect(
      entry.fingerprint,
      sha256.convert(Uint8List(4096)).toString(),
      reason: 'the streamed digest must equal the whole-buffer digest',
    );
  });

  test(
    'the sheet is released at the durable enqueue, not at the finalize',
    () async {
      final reserveGate = Completer<void>();
      final functions = attachmentFunctions(reserveGate: reserveGate);
      final recording = _StreamedRecording(byteLength: 4096);
      final service = serviceWith(functions);

      final entryId = await service.enqueueVoiceMessage(
        conversationId: conversationId,
        audio: recording,
        durationSeconds: 7,
      );

      // This is the exact instant the recorder sheet pops. The server has not
      // published anything yet — and it does not have to, because the bytes
      // and the manifest already survive process death.
      expect(functions.finalizePayloads, isEmpty);
      final queued = service.attachmentOutbox.entry(entryId);
      expect(queued, isNotNull);
      expect(queued!.status, DirectAttachmentOutboxStatus.queued);
      expect(
        await payloadStore.exists(
          service.attachmentOutbox.accountNamespace,
          entryId,
        ),
        isTrue,
      );

      reserveGate.complete();
      await settle(() => service.attachmentOutbox.entries.isEmpty);
      expect(functions.finalizePayloads, hasLength(1));
      expect(service.attachmentOutbox.entries, isEmpty);
    },
  );

  test(
    'ownership of the recording transfers only on a successful enqueue',
    () async {
      final recording = _StreamedRecording(byteLength: 4096);
      final service = serviceWith(
        attachmentFunctions(reserveGate: Completer()),
      );

      await service.enqueueVoiceMessage(
        conversationId: conversationId,
        audio: recording,
        durationSeconds: 7,
      );

      expect(
        recording.discardCalls,
        1,
        reason: 'the queue owns the only copy now and drops the recorder file',
      );
    },
  );

  test('a refused copy leaves the recording with whoever made it', () async {
    payloadStore.failNextAdopt = true;
    final recording = _StreamedRecording(byteLength: 4096);
    final service = serviceWith(attachmentFunctions());

    await expectLater(
      service.enqueueVoiceMessage(
        conversationId: conversationId,
        audio: recording,
        durationSeconds: 7,
      ),
      throwsA(isA<StateError>()),
    );

    expect(
      recording.discardCalls,
      0,
      reason:
          'deleting the only copy of a recording nobody queued is data loss',
    );
    expect(service.attachmentOutbox.entries, isEmpty);
  });

  test('a permanently refused delivery ends visibly failed, never silently '
      'successful, and keeps its bytes for a retry', () async {
    final functions = attachmentFunctions(refuseFinalize: true);
    final recording = _StreamedRecording(byteLength: 4096);
    final service = serviceWith(functions);

    final entryId = await service.enqueueVoiceMessage(
      conversationId: conversationId,
      audio: recording,
      durationSeconds: 7,
    );

    await settle(
      () =>
          service.attachmentOutbox.entry(entryId)?.status ==
          DirectAttachmentOutboxStatus.failed,
    );

    final failed = service.attachmentOutbox.entry(entryId);
    expect(failed, isNotNull, reason: 'a failed send must stay on screen');
    expect(failed!.status, DirectAttachmentOutboxStatus.failed);
    expect(
      await payloadStore.exists(
        service.attachmentOutbox.accountNamespace,
        entryId,
      ),
      isTrue,
      reason: 'Retry has to have something left to send',
    );
    expect(
      service.attachmentDelivery.stateFor(entryId),
      isNull,
      reason: 'nothing is in flight, so no phase may claim otherwise',
    );
  });

  test('Retry after a failure replays one reservation identity', () async {
    final functions = attachmentFunctions(refuseFinalize: true);
    final recording = _StreamedRecording(byteLength: 4096);
    final service = serviceWith(functions);

    final entryId = await service.enqueueVoiceMessage(
      conversationId: conversationId,
      audio: recording,
      durationSeconds: 7,
    );
    await settle(
      () =>
          service.attachmentOutbox.entry(entryId)?.status ==
          DirectAttachmentOutboxStatus.failed,
    );
    final failed = service.attachmentOutbox.entry(entryId)!;

    functions.refuseFinalize = false;
    await service.retryFailedAttachment(entryId);

    expect(service.attachmentOutbox.entries, isEmpty);
    expect(
      functions.reservePayloads.map((payload) => payload['requestId']).toSet(),
      <Object?>{failed.reserveRequestId},
      reason: 'a retry addresses the same reserve ledger entry',
    );
    expect(
      functions.finalizePayloads.map((payload) => payload['requestId']).toSet(),
      <Object?>{failed.finalizeRequestId},
    );
    expect(
      functions.finalizePayloads.map((payload) => payload['messageId']).toSet(),
      <Object?>{messageId},
      reason: 'one queued voice message can only ever publish one message',
    );
    expect(
      payloadStore.uploadCount,
      1,
      reason:
          'the object was already committed under this reservation, so the '
          'retry replays the finalize instead of uploading it again',
    );
    expect(payloadStore.adoptCalls, 1, reason: 'the durable bytes never move');
  });

  test('delivery reports real phases and a real upload fraction', () async {
    final functions = attachmentFunctions();
    final recording = _StreamedRecording(byteLength: 4096);
    final service = serviceWith(functions);
    payloadStore.progressFractions = const <double>[0.25, 0.5, 1];

    final observed = <String>[];
    service.attachmentDelivery.addListener(() {
      final states = service.attachmentDelivery.value.values;
      final state = states.isEmpty ? null : states.first;
      observed.add(
        state == null
            ? 'cleared'
            : '${state.stage.name}${state.progress == null ? '' : ' ${state.progress}'}',
      );
    });

    final entryId = await service.enqueueVoiceMessage(
      conversationId: conversationId,
      audio: recording,
      durationSeconds: 7,
    );
    await settle(() => service.attachmentOutbox.entries.isEmpty);

    expect(observed, contains('preparing'));
    expect(observed, contains('reserving'));
    expect(observed, contains('uploading 0.25'));
    expect(observed, contains('uploading 0.5'));
    expect(observed, contains('uploading 1.0'));
    expect(observed, contains('finalizing'));
    expect(observed.last, 'cleared');
    expect(
      observed.indexOf('reserving'),
      lessThan(observed.indexOf('uploading 0.25')),
    );
    expect(
      observed.indexOf('uploading 1.0'),
      lessThan(observed.indexOf('finalizing')),
    );
    expect(service.attachmentDelivery.stateFor(entryId), isNull);
  });

  test('the phase notifier reports whole percents and nothing else', () {
    final progress = DirectAttachmentDeliveryProgress();
    addTearDown(progress.dispose);
    var notifications = 0;
    progress.addListener(() => notifications += 1);

    progress.report(
      'a',
      DirectAttachmentDeliveryStage.uploading,
      progress: 0.5,
    );
    progress.report(
      'a',
      DirectAttachmentDeliveryStage.uploading,
      progress: 0.5004,
    );
    progress.report(
      'a',
      DirectAttachmentDeliveryStage.uploading,
      progress: 0.51,
    );

    expect(
      notifications,
      2,
      reason: 'a change nobody can see must not rebuild a card',
    );
    expect(progress.stateFor('a')?.progress, 0.51);

    progress.report('a', DirectAttachmentDeliveryStage.finalizing);
    expect(
      progress.stateFor('a')?.progress,
      isNull,
      reason: 'only the upload has a measurable fraction',
    );

    progress.clear('a');
    expect(progress.stateFor('a'), isNull);
  });
}

/// A recording that only ever hands out bounded chunks.
class _StreamedRecording extends RecordedAudio {
  _StreamedRecording({required this.byteLength});

  @override
  final int byteLength;

  @override
  String get contentType => 'audio/mp4;codecs=mp4a.40.2';

  int readBytesCalls = 0;
  int openReadCalls = 0;
  int discardCalls = 0;

  @override
  Future<Uint8List> readBytes() async {
    readBytesCalls += 1;
    return Uint8List(byteLength);
  }

  @override
  Stream<List<int>> openRead() async* {
    openReadCalls += 1;
    const chunk = 512;
    for (var offset = 0; offset < byteLength; offset += chunk) {
      final end = offset + chunk < byteLength ? offset + chunk : byteLength;
      yield Uint8List(end - offset);
    }
  }

  @override
  Future<String> uploadTo(Reference reference, SettableMetadata metadata) =>
      throw StateError('A voice DM never uses the Moment upload path.');

  @override
  Future<void> discard() async {
    discardCalls += 1;
  }
}

class _StreamingPayloadStore implements DirectAttachmentPayloadStore {
  final Map<String, Uint8List> _payloads = <String, Uint8List>{};

  bool failNextAdopt = false;
  int adoptCalls = 0;
  int uploadCount = 0;
  int largestChunk = 0;
  int? storedLength;
  String? uploadPath;
  String? contentTypeAtUpload;
  List<double> progressFractions = const <double>[];

  String _key(String namespace, String id) => '$namespace:$id';

  @override
  Future<void> adopt(
    String namespace,
    String id,
    DirectAttachmentPayloadSource source,
  ) async {
    adoptCalls += 1;
    if (failNextAdopt) {
      failNextAdopt = false;
      throw StateError('The attachment could not be saved.');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in source.openRead()) {
      if (chunk.length > largestChunk) largestChunk = chunk.length;
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    storedLength = bytes.length;
    _payloads[_key(namespace, id)] = bytes;
  }

  @override
  Future<bool> exists(String namespace, String id) async =>
      _payloads.containsKey(_key(namespace, id));

  @override
  Future<Set<String>> keys(String namespace) async => _payloads.keys
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
    if (!_payloads.containsKey(_key(namespace, id))) {
      throw StateError('Pending attachment bytes are missing.');
    }
    uploadCount += 1;
    uploadPath = reference.fullPath;
    contentTypeAtUpload = metadata.contentType;
    for (final fraction in progressFractions) {
      onProgress?.call(fraction);
    }
    return 'generation-7';
  }

  @override
  Future<void> delete(String namespace, String id) async {
    _payloads.remove(_key(namespace, id));
  }

  @override
  Future<void> clear(String namespace) async {
    _payloads.removeWhere((key, _) => key.startsWith('$namespace:'));
  }
}

class _AttachmentFunctions implements FirebaseFunctions {
  _AttachmentFunctions({
    required this.conversationId,
    required this.messageId,
    required this.storagePath,
    this.reserveGate,
    this.refuseFinalize = false,
  });

  final String conversationId;
  final String messageId;
  final String storagePath;
  final Completer<void>? reserveGate;
  bool refuseFinalize;
  final List<Map<String, dynamic>> reservePayloads = [];
  final List<Map<String, dynamic>> finalizePayloads = [];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    return _CallableStub((parameters) async {
      final payload = Map<String, dynamic>.from(parameters! as Map);
      if (name == 'reserveDirectMessageAttachment') {
        final gate = reserveGate;
        if (gate != null) await gate.future;
        reservePayloads.add(payload);
        return <Object?, Object?>{
          'conversationId': conversationId,
          'messageId': messageId,
          'storagePath': storagePath,
          'type': 'voice',
          'expiresAtMillis': DateTime.utc(2030).millisecondsSinceEpoch,
        };
      }
      if (name == 'finalizeDirectMessageAttachment') {
        finalizePayloads.add(payload);
        if (refuseFinalize) {
          throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'finalize refused',
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
