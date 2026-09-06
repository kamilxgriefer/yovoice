import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yovoice/features/calls/data/models/direct_call.dart';
import 'package:yovoice/features/calls/data/services/direct_call_service.dart';
import 'package:yovoice/features/calls/data/services/direct_call_start_request_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  DirectCallService deadlineService(
    _DeadlineFunctions functions, {
    FakeFirebaseFirestore? firestore,
    _MemoryStartStore? store,
    _InstallationGate? installation,
    String requestId = 'bounded-request',
    Duration lateResultRetention = const Duration(minutes: 2),
  }) => DirectCallService(
    firestore: firestore ?? FakeFirebaseFirestore(),
    functions: functions,
    auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'caller')),
    startRequestStore: store ?? _MemoryStartStore(),
    installationIdStore: installation ?? _InstallationGate.ready(),
    requestIdFactory: () => requestId,
    operationTimeout: const Duration(milliseconds: 30),
    callableAttemptTimeout: const Duration(milliseconds: 20),
    reconciliationTimeout: const Duration(milliseconds: 5),
    lateResultRetention: lateResultRetention,
  );

  test(
    'missing canonical call emits typed unavailable instead of no result',
    () async {
      final service = deadlineService(_DeadlineFunctions());
      await expectLater(
        service.watchCall('missing').first,
        throwsA(isA<DirectCallUnavailableException>()),
      );
    },
  );

  test(
    'cached absence followed only by server metadata emits unavailable',
    () async {
      final firestore = _MetadataOnlyFirestore();
      final service = DirectCallService(
        firestore: firestore,
        functions: _DeadlineFunctions(),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'caller'),
        ),
      );
      await expectLater(
        service.watchCall('missing').first,
        throwsA(isA<DirectCallUnavailableException>()),
      );
      expect(firestore.document.includeMetadataRequests, <bool>[true]);
    },
  );

  testWidgets('server-confirmed absence closes and cancels the call stream', (
    tester,
  ) async {
    var cancellations = 0;
    final nativeCleanup = Completer<void>();
    final events = StreamController<DocumentSnapshot<Map<String, dynamic>>>(
      onCancel: () {
        cancellations++;
        return nativeCleanup.future;
      },
    );
    final firestore = _MetadataOnlyFirestore(
      document: _MetadataOnlyDocument(events: events.stream),
    );
    final service = DirectCallService(
      firestore: firestore,
      functions: _DeadlineFunctions(),
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'caller')),
    );
    final received = <DirectCall>[];
    final errors = <Object>[];
    final terminalEvents = <String>[];
    final done = Completer<void>();
    service
        .watchCall('call')
        .listen(
          received.add,
          onError: (Object error) {
            errors.add(error);
            terminalEvents.add('error');
          },
          onDone: () {
            terminalEvents.add('done');
            done.complete();
          },
        );
    await tester.pump();
    events.add(_MissingSnapshot(true));
    await tester.pump();
    expect(errors, isEmpty);
    expect(done.isCompleted, isFalse);
    events.add(_MissingSnapshot(false));
    await tester.pump();
    expect(done.isCompleted, isTrue);
    expect(errors, [isA<DirectCallUnavailableException>()]);
    expect(terminalEvents, ['error', 'done']);
    expect(cancellations, 1);
    expect(nativeCleanup.isCompleted, isFalse);
    expect(firestore.document.includeMetadataRequests, <bool>[true]);
    events.add(_RecreatedSnapshot());
    await tester.pump();
    expect(received, isEmpty);
    expect(errors, hasLength(1));
    expect(terminalEvents, ['error', 'done']);
    nativeCleanup.complete();
    await tester.pump();
    expect(cancellations, 1);
    events.close().ignore();
  });

  testWidgets(
    'timeout then unavailable retry still delivers the later own ACK',
    (tester) async {
      final functions = _DeadlineFunctions();
      final service = deadlineService(functions);
      final statuses = <DirectCallStatus>[];
      final outcome = expectLater(
        service.accept('call', onLateValidatedResult: statuses.add),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (error) => error.code,
            'code',
            'unavailable',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      functions.gates[1].completeError(
        FirebaseFunctionsException(
          code: 'unavailable',
          message: 'Transport unavailable',
        ),
      );
      await tester.pump();
      await outcome;
      expect(statuses, isEmpty);
      expect(service.retainedLateAcceptConsumersForTesting, 1);
      functions.complete(0, {'callId': 'call', 'status': 'active'});
      await tester.pump();
      expect(statuses, [DirectCallStatus.active]);
      expect(service.retainedLateAcceptConsumersForTesting, 0);
    },
  );

  testWidgets(
    'retention expiry releases consumer while native sources remain unresolved',
    (tester) async {
      final functions = _DeadlineFunctions();
      final service = deadlineService(
        functions,
        lateResultRetention: const Duration(milliseconds: 60),
      );
      final statuses = <DirectCallStatus>[];
      final outcome = expectLater(
        service.accept('call', onLateValidatedResult: statuses.add),
        throwsA(isA<DirectCallTimeoutException>()),
      );
      await tester.pump();
      expect(service.retainedLateAcceptConsumersForTesting, 1);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 10));
      await outcome;
      expect(service.retainedLateAcceptConsumersForTesting, 1);
      expect(functions.gates.every((gate) => !gate.isCompleted), isTrue);
      await tester.pump(const Duration(milliseconds: 30));
      expect(service.retainedLateAcceptConsumersForTesting, 0);
      expect(functions.gates.every((gate) => !gate.isCompleted), isTrue);
      functions.complete(0, {'callId': 'call', 'status': 'active'});
      functions.complete(1, {'callId': 'call', 'status': 'active'});
      await tester.pump();
      expect(statuses, isEmpty);
    },
  );

  testWidgets(
    'late valid Answer after deadline is delivered once and callback errors are contained',
    (tester) async {
      final functions = _DeadlineFunctions();
      final service = deadlineService(functions);
      final statuses = <DirectCallStatus>[];
      final outcome = expectLater(
        service.accept(
          'call',
          onLateValidatedResult: (status) {
            statuses.add(status);
            throw StateError('disposed caller callback');
          },
        ),
        throwsA(isA<DirectCallTimeoutException>()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 10));
      await outcome;
      expect(statuses, isEmpty);
      functions.complete(0, {'callId': 'call', 'status': 'active'});
      functions.complete(1, {'callId': 'call', 'status': 'active'});
      await tester.pump();
      expect(statuses, [DirectCallStatus.active]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'malformed or wrong-call late Answer never grants cleanup authority',
    (tester) async {
      final functions = _DeadlineFunctions();
      final service = deadlineService(functions);
      final statuses = <DirectCallStatus>[];
      final outcome = expectLater(
        service.accept('call', onLateValidatedResult: statuses.add),
        throwsA(isA<DirectCallTimeoutException>()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 10));
      await outcome;
      functions.complete(0, {'callId': 'other-call', 'status': 'active'});
      functions.complete(1, {'callId': 'call', 'status': 'ringing'});
      await tester.pump();
      expect(statuses, isEmpty);
    },
  );

  testWidgets(
    'successful retry suppresses cleanup callback from older late Answer',
    (tester) async {
      final functions = _DeadlineFunctions();
      final service = deadlineService(functions);
      final statuses = <DirectCallStatus>[];
      final outcome = service.accept(
        'call',
        onLateValidatedResult: statuses.add,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      functions.complete(1, {'callId': 'call', 'status': 'active'});
      expect(await outcome, DirectCallStatus.active);
      functions.complete(0, {'callId': 'call', 'status': 'active'});
      await tester.pump();
      expect(statuses, isEmpty);
    },
  );

  testWidgets('late own ACK during retry waits until the public deadline', (
    tester,
  ) async {
    final functions = _DeadlineFunctions();
    final service = deadlineService(functions);
    final statuses = <DirectCallStatus>[];
    final outcome = expectLater(
      service.accept('call', onLateValidatedResult: statuses.add),
      throwsA(isA<DirectCallTimeoutException>()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    functions.complete(0, {'callId': 'call', 'status': 'active'});
    await tester.pump();
    expect(statuses, isEmpty);
    await tester.pump(const Duration(milliseconds: 10));
    await outcome;
    expect(statuses, [DirectCallStatus.active]);
    functions.complete(1, {'callId': 'call', 'status': 'ended'});
    await tester.pump();
    expect(statuses, [DirectCallStatus.active]);
  });

  testWidgets('native SDK deadline errors use the same safe typed timeout', (
    tester,
  ) async {
    final functions = _DeadlineFunctions();
    final service = deadlineService(functions);
    final outcome = expectLater(
      service.accept('call'),
      throwsA(
        isA<DirectCallTimeoutException>().having(
          (error) => error.stage,
          'stage',
          'callable',
        ),
      ),
    );
    await tester.pump();
    functions.gates[0].completeError(
      FirebaseFunctionsException(
        code: 'deadline-exceeded',
        message: 'private native preflight detail',
      ),
    );
    await tester.pump();
    functions.gates[1].completeError(
      FirebaseFunctionsException(
        code: 'deadline-exceeded',
        message: 'private native preflight detail',
      ),
    );
    await tester.pump();
    await outcome;
    expect(functions.payloads[0], functions.payloads[1]);
  });

  testWidgets(
    'native preflight timeout retries the same durable start and binding',
    (tester) async {
      final functions = _DeadlineFunctions();
      final service = deadlineService(functions);
      final pending = service.startCall(
        calleeId: 'callee',
        conversationId: 'pair',
      );
      await tester.pump();
      expect(functions.payloads, hasLength(1));
      await tester.pump(const Duration(milliseconds: 20));
      expect(functions.payloads, hasLength(2));
      functions.complete(1, {'callId': 'canonical', 'status': 'ringing'});
      expect(await pending, 'canonical');
      expect(functions.payloads[0], functions.payloads[1]);
      expect(
        functions.timeouts,
        everyElement(const Duration(milliseconds: 20)),
      );
      functions.complete(0, {'callId': 'canonical', 'status': 'ringing'});
      await tester.pump();
      expect(functions.payloads, hasLength(2));
    },
  );

  testWidgets(
    'overall deadline retains uncertain start for exact later replay',
    (tester) async {
      final functions = _DeadlineFunctions();
      final store = _MemoryStartStore();
      final service = deadlineService(functions, store: store);
      final outcome = expectLater(
        service.startCall(calleeId: 'callee', conversationId: 'pair'),
        throwsA(
          isA<DirectCallTimeoutException>()
              .having(
                (error) => error.operation,
                'operation',
                'startDirectCall',
              )
              .having((error) => error.stage, 'stage', 'callable'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 10));
      await outcome;
      expect(functions.payloads, hasLength(2));
      expect(store.request?.requestId, 'bounded-request');
      functions.complete(0, {'callId': 'canonical', 'status': 'ringing'});
      functions.complete(1, {'callId': 'canonical', 'status': 'ringing'});
      await tester.pump();
      expect(store.request?.requestId, 'bounded-request');
      final next = deadlineService(
        functions,
        store: store,
        requestId: 'must-not-rotate',
      );
      final replay = next.startCall(calleeId: 'callee', conversationId: 'pair');
      await tester.pump();
      expect(functions.payloads.last['requestId'], 'bounded-request');
      functions.complete(2, {'callId': 'canonical', 'status': 'ringing'});
      expect(await replay, 'canonical');
      expect(
        functions.payloads.map((p) => p['installationId']).toSet(),
        hasLength(1),
      );
    },
  );

  testWidgets('late installation completion cannot dispatch a ghost start', (
    tester,
  ) async {
    final installation = _InstallationGate();
    final functions = _DeadlineFunctions();
    final service = deadlineService(functions, installation: installation);
    final outcome = expectLater(
      service.startCall(calleeId: 'callee', conversationId: 'pair'),
      throwsA(
        isA<DirectCallTimeoutException>().having(
          (error) => error.stage,
          'stage',
          'installation',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 30));
    await outcome;
    installation.gate.complete('stable-installation');
    await tester.pump();
    expect(functions.payloads, isEmpty);
  });

  testWidgets(
    'late durable acquire cannot dispatch after the overall deadline',
    (tester) async {
      final store = _MemoryStartStore()..acquireGate = Completer<void>();
      final functions = _DeadlineFunctions();
      final service = deadlineService(functions, store: store);
      final outcome = expectLater(
        service.startCall(calleeId: 'callee', conversationId: 'pair'),
        throwsA(
          isA<DirectCallTimeoutException>().having(
            (error) => error.stage,
            'stage',
            'start-request',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await outcome;
      store.acquireGate!.complete();
      await tester.pump();
      expect(functions.payloads, isEmpty);
      expect(store.request?.requestId, 'bounded-request');
    },
  );

  testWidgets(
    'accepted snapshot cannot bypass a timed-out installation-bound Answer',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('directCalls').doc('call').set({
        'status': 'active',
        'callerId': 'caller',
        'calleeId': 'callee',
      });
      final functions = _DeadlineFunctions();
      final service = deadlineService(functions, firestore: firestore);
      final outcome = expectLater(
        service.accept('call'),
        throwsA(isA<DirectCallTimeoutException>()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 10));
      await outcome;
      expect(functions.payloads[0], functions.payloads[1]);
      for (var index = 0; index < 2; index++) {
        functions.complete(index, {'callId': 'call', 'status': 'active'});
      }
      await tester.pump();
      expect(functions.payloads, hasLength(2));
    },
  );

  testWidgets(
    'token timeout is bounded and retries one request and installation',
    (tester) async {
      final functions = _DeadlineFunctions();
      final service = deadlineService(functions);
      final outcome = expectLater(
        service.createJoinToken('call'),
        throwsA(
          isA<DirectCallTimeoutException>().having(
            (error) => error.operation,
            'operation',
            'createDirectCallToken',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 10));
      await outcome;
      expect(functions.payloads[0], functions.payloads[1]);
      for (var index = 0; index < 2; index++) {
        functions.complete(index, {
          'serverUrl': 'wss://example.test',
          'participantToken': 'late',
          'permissions': {'canPublish': true},
        });
      }
      await tester.pump();
    },
  );

  testWidgets(
    'timed-out End reconciles canonical terminal state before retry',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('directCalls').doc('call').set({
        'status': 'ended',
        'callerId': 'caller',
        'calleeId': 'callee',
      });
      final functions = _DeadlineFunctions();
      final service = deadlineService(functions, firestore: firestore);
      final outcome = service.end('call');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await outcome;
      expect(functions.payloads, hasLength(1));
      functions.complete(0, null);
      await tester.pump();
    },
  );

  testWidgets('valid start ACK is not lost behind slow local cleanup', (
    tester,
  ) async {
    final store = _MemoryStartStore()..clearGate = Completer<void>();
    final functions = _DeadlineFunctions();
    final service = deadlineService(functions, store: store);
    final pending = service.startCall(
      calleeId: 'callee',
      conversationId: 'pair',
    );
    await tester.pump();
    functions.complete(0, {'callId': 'canonical', 'status': 'ringing'});
    expect(await pending, 'canonical');
    await tester.pump(const Duration(milliseconds: 40));
    expect(store.request?.requestId, 'bounded-request');
    store.clearGate!.complete();
    await tester.pump();
    expect(store.request, isNull);
  });

  test(
    'installation secret is durable and never rotated by a new service',
    () async {
      final firstStore = SharedPreferencesDirectCallInstallationIdStore();
      expect(
        await firstStore.loadOrCreate(candidate: 'installation-secret-first'),
        'installation-secret-first',
      );

      final afterRestart = SharedPreferencesDirectCallInstallationIdStore();
      expect(
        await afterRestart.loadOrCreate(candidate: 'installation-secret-other'),
        'installation-secret-first',
      );
    },
  );

  test(
    'lost start response retries the same request id and reuses call',
    () async {
      final functions = _LostStartResponseFunctions();
      final service = DirectCallService(
        firestore: FakeFirebaseFirestore(),
        functions: functions,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'caller'),
        ),
        requestIdFactory: () => 'call-request_1',
      );

      final callId = await service.startCall(
        calleeId: 'callee',
        conversationId: 'caller_callee',
      );

      expect(callId, 'canonical-call-1');
      expect(functions.payloads, hasLength(2));
      expect(
        functions.payloads.map((payload) => payload['requestId']).toList(),
        <Object?>['call-request_1', 'call-request_1'],
      );
      expect(
        functions.payloads.map((payload) => payload['calleeId']).toSet(),
        <Object?>{'callee'},
      );
      expect(
        functions.payloads.map((payload) => payload['mediaType']).toSet(),
        <Object?>{'audio'},
      );
      expect(
        functions.payloads.map((payload) => payload['installationId']).toSet(),
        hasLength(1),
      );
      expect(
        functions.payloads.first['installationId'],
        isA<String>().having((value) => value.length, 'length', 64),
      );
    },
  );

  test('video start is durably bound to the video media type', () async {
    final functions = _LostStartResponseFunctions();
    final service = DirectCallService(
      firestore: FakeFirebaseFirestore(),
      functions: functions,
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'caller')),
      requestIdFactory: () => 'video-request_1',
    );

    expect(
      await service.startCall(
        calleeId: 'callee',
        conversationId: 'caller_callee',
        mediaType: DirectCallMediaType.video,
      ),
      'canonical-call-1',
    );
    expect(
      functions.payloads.map((payload) => payload['mediaType']).toSet(),
      <Object?>{'video'},
    );
    expect(
      functions.payloads.map((payload) => payload['requestId']).toSet(),
      <Object?>{'video-request_1'},
    );
    expect(
      functions.payloads
          .map((payload) => payload['directVideoProtocol'])
          .toSet(),
      <Object?>{DirectCallService.directVideoProtocol},
    );
  });

  test('an explicit start refusal is never retried', () async {
    final functions = _RejectStartFunctions();
    final service = DirectCallService(
      firestore: FakeFirebaseFirestore(),
      functions: functions,
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'caller')),
      requestIdFactory: () => 'call-request_2',
    );

    await expectLater(
      service.startCall(calleeId: 'callee', conversationId: 'caller_callee'),
      throwsA(
        isA<FirebaseFunctionsException>().having(
          (error) => error.code,
          'code',
          'permission-denied',
        ),
      ),
    );
    expect(functions.calls, 1);

    final succeedingFunctions = _ColdRestartStartFunctions()
      ..allowCanonicalReplay = true;
    final nextAttempt = DirectCallService(
      firestore: FakeFirebaseFirestore(),
      functions: succeedingFunctions,
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'caller')),
      requestIdFactory: () => 'fresh-after-terminal-refusal',
    );
    await nextAttempt.startCall(
      calleeId: 'callee',
      conversationId: 'caller_callee',
    );
    expect(
      succeedingFunctions.payloads.single['requestId'],
      'fresh-after-terminal-refusal',
    );
  });

  test(
    'cold restart after a lost start acknowledgement replays the durable id',
    () async {
      final functions = _ColdRestartStartFunctions();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'caller'),
      );
      final beforeCrash = DirectCallService(
        firestore: FakeFirebaseFirestore(),
        functions: functions,
        auth: auth,
        requestIdFactory: () => 'durable-before-crash',
      );

      await expectLater(
        beforeCrash.startCall(
          calleeId: 'callee',
          conversationId: 'caller_callee',
        ),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (error) => error.code,
            'code',
            'unavailable',
          ),
        ),
      );
      expect(functions.payloads, hasLength(2));

      // A completely new service instance models the next app process. The
      // backend ledger can now replay the call whose first response was lost.
      functions.allowCanonicalReplay = true;
      final afterRestart = DirectCallService(
        firestore: FakeFirebaseFirestore(),
        functions: functions,
        auth: auth,
        requestIdFactory: () => 'must-not-be-used-after-restart',
      );

      expect(
        await afterRestart.startCall(
          calleeId: 'callee',
          conversationId: 'caller_callee',
        ),
        'canonical-call-after-crash',
      );
      expect(functions.payloads.last['requestId'], 'durable-before-crash');

      // A canonical response clears the pending record. A later intentional
      // call for the same pair is a fresh operation.
      final afterCanonicalResponse = DirectCallService(
        firestore: FakeFirebaseFirestore(),
        functions: functions,
        auth: auth,
        requestIdFactory: () => 'fresh-after-canonical',
      );
      await afterCanonicalResponse.startCall(
        calleeId: 'callee',
        conversationId: 'caller_callee',
      );
      expect(functions.payloads.last['requestId'], 'fresh-after-canonical');
    },
  );

  test('a stale pending start is discarded instead of replayed', () async {
    var now = DateTime(2026, 8, 28, 12);
    final functions = _ColdRestartStartFunctions();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'caller'),
    );
    final firstProcess = DirectCallService(
      firestore: FakeFirebaseFirestore(),
      functions: functions,
      auth: auth,
      requestIdFactory: () => 'stale-request',
      clock: () => now,
      startRequestTtl: const Duration(minutes: 5),
    );
    await expectLater(
      firstProcess.startCall(
        calleeId: 'callee',
        conversationId: 'caller_callee',
      ),
      throwsA(isA<FirebaseFunctionsException>()),
    );

    now = now.add(const Duration(minutes: 6));
    functions.allowCanonicalReplay = true;
    final restarted = DirectCallService(
      firestore: FakeFirebaseFirestore(),
      functions: functions,
      auth: auth,
      requestIdFactory: () => 'fresh-after-ttl',
      clock: () => now,
      startRequestTtl: const Duration(minutes: 5),
    );
    await restarted.startCall(
      calleeId: 'callee',
      conversationId: 'caller_callee',
    );

    expect(functions.payloads.last['requestId'], 'fresh-after-ttl');
  });

  test(
    'an active lost-ack call remains recoverable after five minutes',
    () async {
      var now = DateTime(2026, 8, 28, 12);
      final functions = _ColdRestartStartFunctions();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'caller'),
      );
      final beforeCrash = DirectCallService(
        firestore: FakeFirebaseFirestore(),
        functions: functions,
        auth: auth,
        requestIdFactory: () => 'active-before-crash',
        clock: () => now,
      );
      await expectLater(
        beforeCrash.startCall(
          calleeId: 'callee',
          conversationId: 'caller_callee',
        ),
        throwsA(isA<FirebaseFunctionsException>()),
      );

      now = now.add(const Duration(minutes: 6));
      functions
        ..allowCanonicalReplay = true
        ..canonicalStatus = 'active';
      final restarted = DirectCallService(
        firestore: FakeFirebaseFirestore(),
        functions: functions,
        auth: auth,
        requestIdFactory: () => 'must-not-replace-active-request',
        clock: () => now,
      );

      expect(
        await restarted.startCall(
          calleeId: 'callee',
          conversationId: 'caller_callee',
        ),
        'canonical-active-before-crash',
      );
      expect(functions.payloads.last['requestId'], 'active-before-crash');
    },
  );

  test('a terminal replay rotates once to a fresh bounded operation', () async {
    final functions = _TerminalThenFreshFunctions();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'caller'),
    );
    final beforeCrash = DirectCallService(
      firestore: FakeFirebaseFirestore(),
      functions: functions,
      auth: auth,
      requestIdFactory: () => 'terminal-before-crash',
    );
    await expectLater(
      beforeCrash.startCall(
        calleeId: 'callee',
        conversationId: 'caller_callee',
      ),
      throwsA(isA<FirebaseFunctionsException>()),
    );

    functions.allowCanonicalReplay = true;
    var generated = 0;
    final restarted = DirectCallService(
      firestore: FakeFirebaseFirestore(),
      functions: functions,
      auth: auth,
      requestIdFactory: () => generated++ == 0
          ? 'unused-existing-candidate'
          : 'fresh-after-terminal',
    );

    expect(
      await restarted.startCall(
        calleeId: 'callee',
        conversationId: 'caller_callee',
      ),
      'canonical-fresh-after-terminal',
    );
    expect(
      functions.payloads.skip(2).map((item) => item['requestId']),
      <Object?>['terminal-before-crash', 'fresh-after-terminal'],
    );
  });

  test(
    'concurrent service instances atomically share one start request',
    () async {
      final functions = _ConcurrentStartFunctions();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'caller'),
      );
      final first = DirectCallService(
        firestore: FakeFirebaseFirestore(),
        functions: functions,
        auth: auth,
        requestIdFactory: () => 'concurrent-request-a',
      );
      final second = DirectCallService(
        firestore: FakeFirebaseFirestore(),
        functions: functions,
        auth: auth,
        requestIdFactory: () => 'concurrent-request-b',
      );

      expect(
        await Future.wait([
          first.startCall(calleeId: 'callee', conversationId: 'caller_callee'),
          second.startCall(calleeId: 'callee', conversationId: 'caller_callee'),
        ]),
        <String>['canonical-concurrent', 'canonical-concurrent'],
      );
      expect(functions.payloads, hasLength(1));
      expect(
        functions.payloads.map((item) => item['requestId']).toSet(),
        <Object?>{'concurrent-request-a'},
      );
    },
  );

  test('video capability refusal becomes an actionable typed error', () async {
    final service = DirectCallService(
      firestore: FakeFirebaseFirestore(),
      functions: _VideoCompatibilityFunctions(),
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'caller')),
      requestIdFactory: () => 'video-capability-request',
    );

    await expectLater(
      service.startCall(
        calleeId: 'callee',
        conversationId: 'caller_callee',
        mediaType: DirectCallMediaType.video,
      ),
      throwsA(
        isA<DirectVideoCompatibilityException>().having(
          (error) => error.message,
          'message',
          contains('updates YO Voice'),
        ),
      ),
    );
  });

  test(
    'canonical friendship refusal is distinct from transport failure',
    () async {
      final service = DirectCallService(
        firestore: FakeFirebaseFirestore(),
        functions: _ReasonCodedStartRefusalFunctions(
          DirectCallFriendshipException.reason,
        ),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'caller'),
        ),
        requestIdFactory: () => 'friendship-required-request',
      );

      await expectLater(
        service.startCall(calleeId: 'callee', conversationId: 'caller_callee'),
        throwsA(
          isA<DirectCallFriendshipException>().having(
            (error) => error.message,
            'message',
            contains('friendship is verified'),
          ),
        ),
      );
    },
  );

  test('other reason-coded start refusals use safe typed copy', () async {
    Future<Object> refusal(String reason, String requestId) async {
      final service = DirectCallService(
        firestore: FakeFirebaseFirestore(),
        functions: _ReasonCodedStartRefusalFunctions(reason),
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'caller'),
        ),
        requestIdFactory: () => requestId,
      );
      try {
        await service.startCall(
          calleeId: 'callee',
          conversationId: 'caller_callee',
        );
      } catch (error) {
        return error;
      }
      throw StateError('Expected the reason-coded refusal.');
    }

    final conversation = await refusal(
      DirectCallConversationException.reason,
      'conversation-required-request',
    );
    expect(conversation, isA<DirectCallConversationException>());
    expect(conversation.toString(), isNot(contains('unsafe backend detail')));

    final email = await refusal(
      DirectCallEmailVerificationException.reason,
      'email-verification-request',
    );
    expect(email, isA<DirectCallEmailVerificationException>());
    expect(email.toString(), isNot(contains('unsafe backend detail')));
  });

  test('pending starts are isolated by signed-in account and peer', () async {
    final functions = _ColdRestartStartFunctions();
    final callerA = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'caller-a'),
    );
    final failed = DirectCallService(
      firestore: FakeFirebaseFirestore(),
      functions: functions,
      auth: callerA,
      requestIdFactory: () => 'caller-a-to-callee-a',
    );
    await expectLater(
      failed.startCall(calleeId: 'callee-a', conversationId: 'a_pair'),
      throwsA(isA<FirebaseFunctionsException>()),
    );

    functions.allowCanonicalReplay = true;
    final otherPeer = DirectCallService(
      firestore: FakeFirebaseFirestore(),
      functions: functions,
      auth: callerA,
      requestIdFactory: () => 'caller-a-to-callee-b',
    );
    await otherPeer.startCall(calleeId: 'callee-b', conversationId: 'b_pair');
    expect(functions.payloads.last['requestId'], 'caller-a-to-callee-b');

    final otherAccount = DirectCallService(
      firestore: FakeFirebaseFirestore(),
      functions: functions,
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'caller-b'),
      ),
      requestIdFactory: () => 'caller-b-to-callee-a',
    );
    await otherAccount.startCall(
      calleeId: 'callee-a',
      conversationId: 'other_account_pair',
    );
    expect(functions.payloads.last['requestId'], 'caller-b-to-callee-a');
  });

  test(
    'lost token response replays one request and concurrent joins coalesce',
    () async {
      final functions = _LostTokenResponseFunctions();
      final service = DirectCallService(
        firestore: FakeFirebaseFirestore(),
        functions: functions,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'caller'),
        ),
        requestIdFactory: () => 'token-request-1',
      );

      final results = await Future.wait(<Future<Object>>[
        service.createJoinToken('active-call-1'),
        service.createJoinToken('active-call-1'),
      ]);

      expect(results[0], same(results[1]));
      expect(functions.payloads, hasLength(2));
      expect(
        functions.payloads.map((payload) => payload['requestId']).toSet(),
        <Object?>{'token-request-1'},
      );
      expect(
        functions.payloads.map((payload) => payload['callId']).toSet(),
        <Object?>{'active-call-1'},
      );
      expect(
        functions.payloads.map((payload) => payload['installationId']).toSet(),
        hasLength(1),
      );
      expect(
        functions.payloads
            .map((payload) => payload['directVideoProtocol'])
            .toSet(),
        <Object?>{DirectCallService.directVideoProtocol},
      );
    },
  );

  test('wrong-installation token refusal becomes a safe typed error', () async {
    final service = DirectCallService(
      firestore: FakeFirebaseFirestore(),
      functions: _InstallationBindingRefusalFunctions(),
      auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'caller')),
    );

    await expectLater(
      service.createJoinToken('active-call-elsewhere'),
      throwsA(isA<DirectCallInstallationBindingException>()),
    );
  });

  test(
    'lost accept response retries the same installation-bound callable',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('directCalls').doc('call-1').set({
        'status': 'active',
        'callerId': 'caller',
        'calleeId': 'callee',
      });
      final functions = _LostThenReplayAcceptFunctions();
      final service = DirectCallService(
        firestore: firestore,
        functions: functions,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'callee'),
        ),
      );

      expect(
        await service.accept('call-1', mediaType: DirectCallMediaType.video),
        DirectCallStatus.active,
      );

      expect(functions.calls, 2);
      expect(functions.lastName, 'acceptDirectCall');
      expect(functions.lastPayload?['installationId'], isA<String>());
      expect(
        functions.lastPayload?['directVideoProtocol'],
        DirectCallService.directVideoProtocol,
      );
      expect(
        functions.payloads.map((payload) => payload['installationId']).toSet(),
        hasLength(1),
      );
      expect(functions.payloads[0], functions.payloads[1]);
    },
  );

  test(
    'active state from another installation never authorizes this device',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('directCalls').doc('call-race').set({
        'status': 'ringing',
        'callerId': 'caller',
        'calleeId': 'callee',
      });
      final functions = _ActionCommitRaceFunctions(firestore);
      final service = DirectCallService(
        firestore: firestore,
        functions: functions,
        auth: MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'callee'),
        ),
      );

      await expectLater(
        service.accept('call-race'),
        throwsA(isA<DirectCallInstallationBindingException>()),
      );

      expect(functions.calls, 2);
      expect(
        (await firestore.collection('directCalls').doc('call-race').get())
            .data()?['status'],
        'active',
      );
    },
  );
}

class _MetadataOnlyFirestore implements FirebaseFirestore {
  _MetadataOnlyFirestore({_MetadataOnlyDocument? document})
    : document = document ?? _MetadataOnlyDocument();
  final _MetadataOnlyDocument document;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _MetadataOnlyCollection(document);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Firebase's public interface is sealed; this narrow fake is intentionally
// used to model the cache-to-server metadata transition the in-memory
// Firestore package does not expose.
// ignore: subtype_of_sealed_class
class _MetadataOnlyCollection
    implements CollectionReference<Map<String, dynamic>> {
  _MetadataOnlyCollection(this.document);
  final _MetadataOnlyDocument document;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => document;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _MetadataOnlyDocument implements DocumentReference<Map<String, dynamic>> {
  _MetadataOnlyDocument({this.events});
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? events;
  final includeMetadataRequests = <bool>[];
  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) async* {
    includeMetadataRequests.add(includeMetadataChanges);
    if (events != null) {
      yield* events!;
      return;
    }
    yield _MissingSnapshot(true);
    // Firestore suppresses an otherwise identical server result unless
    // metadata-only changes are requested by the actual production caller.
    if (includeMetadataChanges) yield _MissingSnapshot(false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _MissingSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _MissingSnapshot(this.cached);
  final bool cached;
  @override
  bool get exists => false;
  @override
  SnapshotMetadata get metadata => _Metadata(cached);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _RecreatedSnapshot extends _MissingSnapshot {
  _RecreatedSnapshot() : super(false);
  @override
  bool get exists => true;
  @override
  String get id => 'call';
  @override
  Map<String, dynamic> data() => {
    'callerId': 'caller',
    'calleeId': 'callee',
    'status': 'active',
  };
}

class _Metadata implements SnapshotMetadata {
  _Metadata(this.isFromCache);
  @override
  final bool isFromCache;
  @override
  bool get hasPendingWrites => false;
}

class _DeadlineFunctions implements FirebaseFunctions {
  final payloads = <Map<String, dynamic>>[];
  final timeouts = <Duration?>[];
  final gates = <Completer<Object?>>[];

  void complete(int index, Object? value) => gates[index].complete(value);

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((parameters) {
        payloads.add(Map<String, dynamic>.from(parameters as Map));
        timeouts.add(options?.timeout);
        final gate = Completer<Object?>();
        gates.add(gate);
        return gate.future;
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InstallationGate implements DirectCallInstallationIdStore {
  _InstallationGate();
  _InstallationGate.ready() {
    gate.complete('stable-installation');
  }
  final gate = Completer<String>();
  @override
  Future<String> loadOrCreate({required String candidate}) => gate.future;
}

class _MemoryStartStore implements DirectCallStartRequestStore {
  PendingDirectCallStartRequest? request;
  Completer<void>? acquireGate;
  Completer<void>? clearGate;
  @override
  Future<PendingDirectCallStartRequest> acquire({
    required PendingDirectCallStartRequest candidate,
    required DateTime now,
    required Duration ttl,
  }) async {
    if (acquireGate != null) await acquireGate!.future;
    return request ??= candidate;
  }

  @override
  Future<void> clear({
    required String callerId,
    required String calleeId,
    required String expectedRequestId,
  }) async {
    if (clearGate != null) await clearGate!.future;
    if (request?.requestId == expectedRequestId) request = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LostStartResponseFunctions implements FirebaseFunctions {
  final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((parameters) async {
        expect(name, 'startDirectCall');
        payloads.add(Map<String, dynamic>.from(parameters as Map));
        if (payloads.length == 1) {
          // Mirrors a committed server transaction whose transport response
          // was lost. The second attempt is the backend ledger replay.
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'The response never arrived.',
          );
        }
        return <String, dynamic>{
          'callId': 'canonical-call-1',
          'status': 'ringing',
          'expiresAtMillis': 1787947260000,
        };
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RejectStartFunctions implements FirebaseFunctions {
  int calls = 0;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((_) async {
        calls++;
        throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'This call is not allowed.',
        );
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ColdRestartStartFunctions implements FirebaseFunctions {
  final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[];
  bool allowCanonicalReplay = false;
  String canonicalStatus = 'ringing';

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((parameters) async {
        expect(name, 'startDirectCall');
        final payload = Map<String, dynamic>.from(parameters as Map);
        payloads.add(payload);
        if (!allowCanonicalReplay) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'The server committed but the acknowledgement was lost.',
          );
        }
        return <String, dynamic>{
          'callId': payload['requestId'] == 'durable-before-crash'
              ? 'canonical-call-after-crash'
              : 'canonical-${payload['requestId']}',
          'status': canonicalStatus,
          'expiresAtMillis': 1787947260000,
        };
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TerminalThenFreshFunctions implements FirebaseFunctions {
  final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[];
  bool allowCanonicalReplay = false;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((parameters) async {
        expect(name, 'startDirectCall');
        final payload = Map<String, dynamic>.from(parameters as Map);
        payloads.add(payload);
        if (!allowCanonicalReplay) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'The committed response was lost.',
          );
        }
        final requestId = payload['requestId'] as String;
        return <String, dynamic>{
          'callId': 'canonical-$requestId',
          'status': requestId == 'terminal-before-crash' ? 'ended' : 'ringing',
          'expiresAtMillis': 1787947260000,
        };
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ConcurrentStartFunctions implements FirebaseFunctions {
  final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[];
  final Completer<void> _release = Completer<void>();

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((parameters) async {
        expect(name, 'startDirectCall');
        payloads.add(Map<String, dynamic>.from(parameters as Map));
        Future<void>.delayed(const Duration(milliseconds: 10)).then((_) {
          if (!_release.isCompleted) _release.complete();
        });
        await _release.future;
        return <String, dynamic>{
          'callId': 'canonical-concurrent',
          'status': 'ringing',
          'expiresAtMillis': 1787947260000,
        };
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _VideoCompatibilityFunctions implements FirebaseFunctions {
  @override
  HttpsCallable httpsCallable(
    String name, {
    HttpsCallableOptions? options,
  }) => _CallableStub((_) async {
    expect(name, 'startDirectCall');
    throw FirebaseFunctionsException(
      code: 'failed-precondition',
      message:
          'Video calling is not available until your friend updates YO Voice on every active device.',
      details: const <String, Object>{
        'reason': DirectVideoCompatibilityException.reason,
        'audioFallbackAvailable': true,
        'requiredProtocol': 1,
      },
    );
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReasonCodedStartRefusalFunctions implements FirebaseFunctions {
  const _ReasonCodedStartRefusalFunctions(this.reason);

  final String reason;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((_) async {
        expect(name, 'startDirectCall');
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'unsafe backend detail',
          details: <String, Object>{'reason': reason},
        );
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LostThenReplayAcceptFunctions implements FirebaseFunctions {
  int calls = 0;
  String? lastName;
  Map<String, dynamic>? lastPayload;
  final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((parameters) async {
        calls++;
        lastName = name;
        lastPayload = Map<String, dynamic>.from(parameters as Map);
        payloads.add(lastPayload!);
        if (calls == 1) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'The committed response was lost.',
          );
        }
        return <String, dynamic>{
          'callId': lastPayload!['callId'],
          'status': 'active',
        };
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LostTokenResponseFunctions implements FirebaseFunctions {
  final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((parameters) async {
        expect(name, 'createDirectCallToken');
        payloads.add(Map<String, dynamic>.from(parameters as Map));
        if (payloads.length == 1) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'The signed token response was lost.',
          );
        }
        return <String, dynamic>{
          'serverUrl': 'wss://yovoice-3f7j9fb7.livekit.cloud',
          'participantToken': 'signed-token',
          'permissions': <String, Object?>{'canPublish': true},
        };
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InstallationBindingRefusalFunctions implements FirebaseFunctions {
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((_) async {
        expect(name, 'createDirectCallToken');
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'unsafe backend detail',
          details: const <String, Object>{
            'reason': DirectCallInstallationBindingException.reason,
          },
        );
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ActionCommitRaceFunctions implements FirebaseFunctions {
  _ActionCommitRaceFunctions(this.firestore);

  final FakeFirebaseFirestore firestore;
  int calls = 0;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((_) async {
        expect(name, 'acceptDirectCall');
        calls++;
        if (calls == 1) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'The first response was lost before local state changed.',
          );
        }
        // Another installation commits Answer while this installation's
        // ambiguous retry is in flight. The shared call document is active,
        // but this device still must fail closed on the binding refusal.
        await firestore.collection('directCalls').doc('call-race').update({
          'status': 'active',
        });
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'unsafe backend detail',
          details: const <String, Object>{
            'reason': DirectCallInstallationBindingException.reason,
          },
        );
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
