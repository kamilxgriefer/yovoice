import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/messages/data/services/message_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const currentUserId = 'sender-uid';
  const peerUserId = 'recipient-uid';
  const conversationId = 'recipient-uid_sender-uid';

  late FakeFirebaseFirestore firestore;

  MockFirebaseAuth signedInAuth() => MockFirebaseAuth(
    signedIn: true,
    mockUser: MockUser(uid: currentUserId, email: '$currentUserId@yovoice.app'),
  );

  Future<void> seedConversation({required bool archived}) async {
    await firestore.collection('conversations').doc(conversationId).set({
      'schemaVersion': 2,
      'pairKey': conversationId,
      'participantIds': <String>[peerUserId, currentUserId],
      'archivedBy': archived ? <String>[currentUserId] : <String>[],
      'mutedBy': <String>[],
      'unreadCounts': <String, int>{currentUserId: 7, peerUserId: 2},
    });
  }

  Future<Map<String, dynamic>> conversation() async {
    final snapshot = await firestore
        .collection('conversations')
        .doc(conversationId)
        .get();
    return snapshot.data()!;
  }

  MessageService serviceFor(_PreferenceFunctions functions) => MessageService(
    firestore: firestore,
    auth: signedInAuth(),
    functions: functions,
  );

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  group('archiveConversation', () {
    test('succeeds through the callable once', () async {
      await seedConversation(archived: false);
      final functions = _PreferenceFunctions(
        firestore,
        actorId: currentUserId,
        expectedConversationId: conversationId,
      );

      await serviceFor(functions).archiveConversation(conversationId);

      expect(functions.payloads, hasLength(1));
      expect(functions.commitCount, 1);
      expect(functions.payloads.single, containsPair('preference', 'archived'));
      expect(functions.payloads.single, containsPair('enabled', true));
      expect(
        functions.payloads.single['requestId'],
        isA<String>().having((value) => value.isNotEmpty, 'isNotEmpty', true),
      );
      final data = await conversation();
      expect(data['archivedBy'], contains(currentUserId));
      expect((data['unreadCounts'] as Map)[currentUserId], 0);
    });

    test(
      'replays the same request after a committed response is lost',
      () async {
        await seedConversation(archived: false);
        final functions = _PreferenceFunctions(
          firestore,
          actorId: currentUserId,
          expectedConversationId: conversationId,
          loseFirstResponseAfterCommit: true,
        );

        await serviceFor(functions).archiveConversation(conversationId);

        expect(functions.payloads, hasLength(2));
        expect(functions.payloads[1], equals(functions.payloads[0]));
        expect(functions.commitCount, 1);
        final data = await conversation();
        expect(data['archivedBy'], <String>[currentUserId]);
        expect((data['unreadCounts'] as Map)[currentUserId], 0);
      },
    );

    test('does not retry or bypass a permanent refusal', () async {
      await seedConversation(archived: false);
      final functions = _PreferenceFunctions(
        firestore,
        actorId: currentUserId,
        expectedConversationId: conversationId,
        permanentFailureCode: 'permission-denied',
      );

      await expectLater(
        serviceFor(functions).archiveConversation(conversationId),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (error) => error.code,
            'code',
            'permission-denied',
          ),
        ),
      );

      expect(functions.payloads, hasLength(1));
      expect(functions.commitCount, 0);
      final data = await conversation();
      expect(data['archivedBy'], isEmpty);
      expect((data['unreadCounts'] as Map)[currentUserId], 7);
    });
  });

  group('unarchiveConversation', () {
    test('succeeds through the callable once', () async {
      await seedConversation(archived: true);
      final functions = _PreferenceFunctions(
        firestore,
        actorId: currentUserId,
        expectedConversationId: conversationId,
      );

      await serviceFor(functions).unarchiveConversation(conversationId);

      expect(functions.payloads, hasLength(1));
      expect(functions.commitCount, 1);
      expect(functions.payloads.single, containsPair('preference', 'archived'));
      expect(functions.payloads.single, containsPair('enabled', false));
      final data = await conversation();
      expect(data['archivedBy'], isEmpty);
      expect((data['unreadCounts'] as Map)[currentUserId], 7);
    });

    test(
      'replays the same request after a committed response is lost',
      () async {
        await seedConversation(archived: true);
        final functions = _PreferenceFunctions(
          firestore,
          actorId: currentUserId,
          expectedConversationId: conversationId,
          loseFirstResponseAfterCommit: true,
        );

        await serviceFor(functions).unarchiveConversation(conversationId);

        expect(functions.payloads, hasLength(2));
        expect(functions.payloads[1], equals(functions.payloads[0]));
        expect(functions.commitCount, 1);
        final data = await conversation();
        expect(data['archivedBy'], isEmpty);
        expect((data['unreadCounts'] as Map)[currentUserId], 7);
      },
    );

    test('does not retry or bypass a permanent refusal', () async {
      await seedConversation(archived: true);
      final functions = _PreferenceFunctions(
        firestore,
        actorId: currentUserId,
        expectedConversationId: conversationId,
        permanentFailureCode: 'invalid-argument',
      );

      await expectLater(
        serviceFor(functions).unarchiveConversation(conversationId),
        throwsA(
          isA<FirebaseFunctionsException>().having(
            (error) => error.code,
            'code',
            'invalid-argument',
          ),
        ),
      );

      expect(functions.payloads, hasLength(1));
      expect(functions.commitCount, 0);
      final data = await conversation();
      expect(data['archivedBy'], <String>[currentUserId]);
      expect((data['unreadCounts'] as Map)[currentUserId], 7);
    });
  });
}

/// A small model of the deployed preference callable and its request ledger.
///
/// The first response can disappear after the authoritative write. A retry
/// with the same request id is then a replay; a different payload for that id
/// is rejected, mirroring the backend's operation identity guard.
class _PreferenceFunctions implements FirebaseFunctions {
  _PreferenceFunctions(
    this.firestore, {
    required this.actorId,
    required this.expectedConversationId,
    this.loseFirstResponseAfterCommit = false,
    this.permanentFailureCode,
  });

  final FakeFirebaseFirestore firestore;
  final String actorId;
  final String expectedConversationId;
  final bool loseFirstResponseAfterCommit;
  final String? permanentFailureCode;
  final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> _ledger =
      <String, Map<String, dynamic>>{};
  int commitCount = 0;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) =>
      _CallableStub((parameters) => _call(name, parameters));

  Future<Map<String, Object?>> _call(String name, Object? parameters) async {
    if (name != 'setDirectConversationPreference') {
      throw FirebaseFunctionsException(
        code: 'not-found',
        message: 'Unexpected callable $name.',
      );
    }

    final payload = Map<String, dynamic>.from(parameters! as Map);
    payloads.add(payload);

    final permanentCode = permanentFailureCode;
    if (permanentCode != null) {
      throw FirebaseFunctionsException(
        code: permanentCode,
        message: 'The deployed callable refused this preference update.',
      );
    }

    final requestId = payload['requestId'] as String;
    final replay = _ledger[requestId];
    if (replay != null) {
      if (!_samePayload(replay, payload)) {
        throw FirebaseFunctionsException(
          code: 'already-exists',
          message: 'The request id was reused with different input.',
        );
      }
      return <String, Object?>{
        'conversationId': payload['conversationId'],
        'preference': payload['preference'],
        'enabled': payload['enabled'],
        'replayed': true,
      };
    }

    await _commit(payload);
    _ledger[requestId] = Map<String, dynamic>.from(payload);
    commitCount++;

    if (loseFirstResponseAfterCommit) {
      throw FirebaseFunctionsException(
        code: 'unavailable',
        message: 'The write committed, but its acknowledgement was lost.',
      );
    }

    return <String, Object?>{
      'conversationId': payload['conversationId'],
      'preference': payload['preference'],
      'enabled': payload['enabled'],
    };
  }

  Future<void> _commit(Map<String, dynamic> payload) async {
    final conversationId = payload['conversationId'];
    if (conversationId != expectedConversationId ||
        payload['preference'] != 'archived' ||
        payload['enabled'] is! bool ||
        (payload['requestId'] as String).isEmpty) {
      throw FirebaseFunctionsException(
        code: 'invalid-argument',
        message: 'The preference request is not canonical.',
      );
    }

    final reference = firestore
        .collection('conversations')
        .doc(expectedConversationId);
    final snapshot = await reference.get();
    final data = snapshot.data();
    final participants = List<String>.from(
      data?['participantIds'] as List? ?? const <String>[],
    );
    if (data == null ||
        data['pairKey'] != expectedConversationId ||
        !participants.contains(actorId)) {
      throw FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'The canonical pair guard refused this conversation.',
      );
    }

    final archivedBy = List<String>.from(
      data['archivedBy'] as List? ?? const <String>[],
    );
    final enabled = payload['enabled'] as bool;
    if (enabled) {
      if (!archivedBy.contains(actorId)) archivedBy.add(actorId);
    } else {
      archivedBy.remove(actorId);
    }

    final update = <String, Object?>{'archivedBy': archivedBy};
    if (enabled) {
      final unreadCounts = Map<String, dynamic>.from(
        data['unreadCounts'] as Map? ?? const <String, dynamic>{},
      );
      unreadCounts[actorId] = 0;
      update['unreadCounts'] = unreadCounts;
    }
    await reference.update(update);
  }

  bool _samePayload(Map<String, dynamic> first, Map<String, dynamic> second) =>
      first.length == second.length &&
      first.entries.every((entry) => second[entry.key] == entry.value);

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
