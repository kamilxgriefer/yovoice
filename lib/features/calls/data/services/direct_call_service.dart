import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/direct_call.dart';
import '../models/voice_connection_info.dart';
import 'direct_call_start_request_store.dart';

abstract interface class DirectCallGateway {
  Stream<DirectCall> watchCall(String callId);
  Future<DirectCall?> getCall(String callId);
  Stream<List<IncomingDirectCallSignal>> watchIncomingCalls();
  Future<String> startCall({
    required String calleeId,
    required String conversationId,
    DirectCallMediaType mediaType = DirectCallMediaType.audio,
  });
  Future<void> accept(String callId);
  Future<void> decline(String callId);
  Future<void> cancel(String callId);
  Future<void> end(String callId);
  Future<VoiceConnectionInfo> createJoinToken(String callId);
}

class DirectCallService implements DirectCallGateway {
  DirectCallService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    String Function()? requestIdFactory,
    DirectCallStartRequestStore? startRequestStore,
    DateTime Function()? clock,
    // A ringing call can become active after its start response was lost and
    // remain valid for eight hours. Keep the idempotency key slightly longer
    // than that server lifetime, while still bounding stale replays.
    this.startRequestTtl = const Duration(hours: 8, minutes: 5),
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1'),
       _auth = auth ?? FirebaseAuth.instance,
       _requestIdFactory = requestIdFactory ?? _newRequestId,
       _startRequestStore =
           startRequestStore ?? SharedPreferencesDirectCallStartRequestStore(),
       _clock = clock ?? DateTime.now;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final String Function() _requestIdFactory;
  final DirectCallStartRequestStore _startRequestStore;
  final DateTime Function() _clock;
  final Duration startRequestTtl;

  static String _newRequestId() {
    final random = Random.secure();
    final randomPart = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}-$randomPart';
  }

  String get _currentUserId {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw StateError('User is not signed in.');
    return uid;
  }

  @override
  Stream<DirectCall> watchCall(String callId) {
    return _firestore
        .collection('directCalls')
        .doc(callId)
        .snapshots()
        .where((snapshot) => snapshot.exists)
        .map(DirectCall.fromFirestore);
  }

  @override
  Future<DirectCall?> getCall(String callId) async {
    final snapshot = await _firestore
        .collection('directCalls')
        .doc(callId)
        .get();
    return snapshot.exists ? DirectCall.fromFirestore(snapshot) : null;
  }

  @override
  Stream<List<IncomingDirectCallSignal>> watchIncomingCalls() {
    return _firestore
        .collection('users')
        .doc(_currentUserId)
        .collection('incomingCalls')
        .where('status', isEqualTo: DirectCallStatus.ringing.name)
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          final signals = snapshot.docs
              .map(IncomingDirectCallSignal.fromFirestore)
              .where(
                (signal) =>
                    signal.expiresAt == null || signal.expiresAt!.isAfter(now),
              )
              .toList(growable: false);
          signals.sort((a, b) {
            final aExpiry =
                a.expiresAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bExpiry =
                b.expiresAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bExpiry.compareTo(aExpiry);
          });
          return signals;
        });
  }

  @override
  Future<String> startCall({
    required String calleeId,
    required String conversationId,
    DirectCallMediaType mediaType = DirectCallMediaType.audio,
  }) async {
    final callerId = _currentUserId;
    var request = await _acquireStartRequest(
      callerId: callerId,
      calleeId: calleeId,
      conversationId: conversationId,
      mediaType: mediaType,
    );
    // At most one canonical-but-terminal replay is retired per user action.
    // This lets a tap recover an active lost-ACK call after a restart, or start
    // a genuinely new call when that recovered operation has already ended,
    // without ever looping over historical request IDs indefinitely.
    for (var operation = 0; operation < 2; operation++) {
      final response = await _invokeStartCall(
        callerId: callerId,
        calleeId: calleeId,
        conversationId: conversationId,
        mediaType: mediaType,
        requestId: request.requestId,
      );
      final callId = response['callId'] as String?;
      if (callId == null || callId.isEmpty) {
        throw StateError('The call service returned no call identifier.');
      }
      final status = response['status'];
      if (status == null || status == 'ringing' || status == 'active') {
        await _startRequestStore.clear(
          callerId: callerId,
          calleeId: calleeId,
          expectedRequestId: request.requestId,
        );
        return callId;
      }
      if (status is! String ||
          !const <String>{
            'declined',
            'cancelled',
            'ended',
            'missed',
          }.contains(status)) {
        // A malformed/unknown response cannot prove whether a canonical call
        // is usable, so preserve its request ID for a later reconciliation.
        throw StateError('The call service returned an invalid call status.');
      }
      await _startRequestStore.clear(
        callerId: callerId,
        calleeId: calleeId,
        expectedRequestId: request.requestId,
      );
      if (operation == 1) {
        throw StateError('The call is no longer available. Try again.');
      }
      request = await _acquireStartRequest(
        callerId: callerId,
        calleeId: calleeId,
        conversationId: conversationId,
        mediaType: mediaType,
        previousRequestId: request.requestId,
      );
    }
    throw StateError('The call service did not complete.');
  }

  Future<PendingDirectCallStartRequest> _acquireStartRequest({
    required String callerId,
    required String calleeId,
    required String conversationId,
    required DirectCallMediaType mediaType,
    String? previousRequestId,
  }) async {
    var candidateId = _requestIdFactory();
    for (
      var attempt = 0;
      previousRequestId != null && candidateId == previousRequestId;
      attempt++
    ) {
      if (attempt >= 3) {
        throw StateError('The call request identifier could not be rotated.');
      }
      candidateId = _requestIdFactory();
    }
    final now = _clock();
    return _startRequestStore.acquire(
      candidate: PendingDirectCallStartRequest(
        callerId: callerId,
        calleeId: calleeId,
        conversationId: conversationId,
        mediaType: mediaType,
        requestId: candidateId,
        createdAt: now,
      ),
      now: now,
      ttl: startRequestTtl,
    );
  }

  Future<Map<String, dynamic>> _invokeStartCall({
    required String callerId,
    required String calleeId,
    required String conversationId,
    required DirectCallMediaType mediaType,
    required String requestId,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _functions
            .httpsCallable('startDirectCall')
            .call<Map<String, dynamic>>({
              'calleeId': calleeId,
              'conversationId': conversationId,
              'mediaType': mediaType.name,
              'requestId': requestId,
            });
        return response.data;
      } catch (error, stackTrace) {
        if (attempt == 0 && _isAmbiguousStartFailure(error)) continue;
        // Explicit callable refusals prove there is no uncertain canonical
        // start to reconcile. Transport and malformed-response failures stay
        // durable because the server may already have committed the call.
        if (_isTerminalStartFailure(error)) {
          await _startRequestStore.clear(
            callerId: callerId,
            calleeId: calleeId,
            expectedRequestId: requestId,
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    throw StateError('The call service did not complete.');
  }

  bool _isAmbiguousStartFailure(Object error) =>
      error is FirebaseFunctionsException &&
      const <String>{
        'aborted',
        'cancelled',
        'deadline-exceeded',
        'internal',
        'unknown',
        'unavailable',
      }.contains(error.code);

  bool _isTerminalStartFailure(Object error) =>
      error is FirebaseFunctionsException && !_isAmbiguousStartFailure(error);

  @override
  Future<void> accept(String callId) => _action(
    'acceptDirectCall',
    callId,
    acceptedStatuses: const <DirectCallStatus>{
      DirectCallStatus.active,
      DirectCallStatus.ended,
    },
  );
  @override
  Future<void> decline(String callId) => _action(
    'declineDirectCall',
    callId,
    acceptedStatuses: const <DirectCallStatus>{DirectCallStatus.declined},
  );
  @override
  Future<void> cancel(String callId) => _action(
    'cancelDirectCall',
    callId,
    acceptedStatuses: const <DirectCallStatus>{DirectCallStatus.cancelled},
  );
  @override
  Future<void> end(String callId) => _action(
    'endDirectCall',
    callId,
    acceptedStatuses: const <DirectCallStatus>{
      DirectCallStatus.ended,
      DirectCallStatus.declined,
      DirectCallStatus.cancelled,
      DirectCallStatus.missed,
    },
  );

  Future<void> _action(
    String name,
    String callId, {
    required Set<DirectCallStatus> acceptedStatuses,
  }) async {
    final callable = _functions.httpsCallable(name);
    try {
      await callable.call<void>({'callId': callId});
      return;
    } catch (error) {
      if (!_isAmbiguousStartFailure(error)) rethrow;
      if (await _callReached(callId, acceptedStatuses)) return;
      try {
        await callable.call<void>({'callId': callId});
        return;
      } catch (retryError, retryStackTrace) {
        // The retry can race the first committed transition and receive a
        // deterministic failed-precondition rather than another transport
        // error. Reconcile authoritative state after every second failure.
        if (await _callReached(callId, acceptedStatuses)) {
          return;
        }
        Error.throwWithStackTrace(retryError, retryStackTrace);
      }
    }
  }

  Future<bool> _callReached(
    String callId,
    Set<DirectCallStatus> acceptedStatuses,
  ) async {
    try {
      final current = await getCall(callId);
      return current != null && acceptedStatuses.contains(current.status);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<VoiceConnectionInfo> createJoinToken(String callId) async {
    final response = await _functions
        .httpsCallable('createDirectCallToken')
        .call<Map<String, dynamic>>({'callId': callId});
    return VoiceConnectionInfo.fromMap(response.data);
  }
}
