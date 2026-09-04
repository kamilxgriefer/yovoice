import 'dart:async';

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
