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
  Future<DirectCallStatus> accept(
    String callId, {
    DirectCallMediaType mediaType = DirectCallMediaType.audio,
  });
  Future<void> decline(String callId);
  Future<void> cancel(String callId);
  Future<void> end(String callId);
  Future<VoiceConnectionInfo> createJoinToken(String callId);
}

/// A video call was refused because at least one active recipient device has
/// not advertised the direct-video protocol yet.
///
/// This is deliberately separate from generic callable failures so the UI can
/// offer the backward-compatible audio call instead of presenting a dead end.
class DirectVideoCompatibilityException implements Exception {
  const DirectVideoCompatibilityException({required this.message});

  static const reason = 'direct-video-capability-required';

  final String message;

  @override
  String toString() => message;
}

/// The direct-call transport is healthy, but this legacy friendship has not
/// yet been reconciled into the server-authoritative bilateral guard model.
///
/// Keeping this distinct from connectivity and LiveKit failures lets the UI
/// explain that retrying the same call cannot help and lets telemetry measure
/// the remaining reviewed migration population without exposing identities.
class DirectCallFriendshipException implements Exception {
  const DirectCallFriendshipException();

  static const reason = 'canonical-friendship-required';

  String get message =>
      'Calling will be available after this friendship is verified.';

  @override
  String toString() => message;
}

/// The supplied conversation is not the canonical direct conversation for
/// the selected pair. The fixed local copy avoids surfacing backend text.
class DirectCallConversationException implements Exception {
  const DirectCallConversationException();

  static const reason = 'direct-conversation-required';

  String get message => 'Open the direct conversation and try the call again.';

  @override
  String toString() => message;
}

/// Calls require a verified email even when an older screen has not yet
/// surfaced the global verification banner.
class DirectCallEmailVerificationException implements Exception {
  const DirectCallEmailVerificationException();

  static const reason = 'email-verification-required';

  String get message => 'Verify your email before starting a call.';

  @override
  String toString() => message;
}

/// A different installation of the same account tried to join a call that was
/// started or answered elsewhere.
class DirectCallInstallationBindingException implements Exception {
  const DirectCallInstallationBindingException();

  static const reason = 'direct-call-installation-binding-required';

  String get message =>
      'Continue this call on the device that started or answered it.';

  @override
  String toString() => message;
}

class DirectCallService implements DirectCallGateway {
  static const int directVideoProtocol = 1;

  DirectCallService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    String Function()? requestIdFactory,
    DirectCallStartRequestStore? startRequestStore,
    DirectCallInstallationIdStore? installationIdStore,
    String Function()? installationIdFactory,
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
       _installationIdStore =
           installationIdStore ??
           SharedPreferencesDirectCallInstallationIdStore(),
       _installationIdFactory = installationIdFactory ?? _newInstallationId,
       _clock = clock ?? DateTime.now;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final String Function() _requestIdFactory;
  final DirectCallStartRequestStore _startRequestStore;
  final DirectCallInstallationIdStore _installationIdStore;
  final String Function() _installationIdFactory;
  final DateTime Function() _clock;
  final Duration startRequestTtl;
  Future<String>? _installationIdFuture;

  // A second screen/service instance can be created while the first call
  // start is awaiting the network. The durable request store guarantees that
  // both attempts use one requestId; this registry additionally guarantees
  // that the process sends only one callable request and both callers observe
  // the same result.
  static final Map<String, Future<String>> _inFlightStarts =
      <String, Future<String>>{};
  static final Map<String, Future<VoiceConnectionInfo>> _inFlightTokens =
      <String, Future<VoiceConnectionInfo>>{};

  static String _newRequestId() {
    final random = Random.secure();
    final randomPart = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}-$randomPart';
  }

  static String _newInstallationId() {
    final random = Random.secure();
    return List<int>.generate(
      32,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<String> _installationId() {
    final existing = _installationIdFuture;
    if (existing != null) return existing;
    late final Future<String> operation;
    operation = _installationIdStore
        .loadOrCreate(candidate: _installationIdFactory())
        .catchError((Object error, StackTrace stackTrace) {
          if (identical(_installationIdFuture, operation)) {
            _installationIdFuture = null;
          }
          Error.throwWithStackTrace(error, stackTrace);
        });
    _installationIdFuture = operation;
    return operation;
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
  }) {
    final callerId = _currentUserId;
    final scope =
        '$callerId\u0000$calleeId\u0000$conversationId\u0000${mediaType.name}';
    final existing = _inFlightStarts[scope];
    if (existing != null) return existing;

    late final Future<String> operation;
    operation =
        _startCall(
          callerId: callerId,
          calleeId: calleeId,
          conversationId: conversationId,
          mediaType: mediaType,
        ).whenComplete(() {
          if (identical(_inFlightStarts[scope], operation)) {
            _inFlightStarts.remove(scope);
          }
        });
    _inFlightStarts[scope] = operation;
    return operation;
  }

  Future<String> _startCall({
    required String callerId,
    required String calleeId,
    required String conversationId,
    required DirectCallMediaType mediaType,
  }) async {
    final installationId = await _installationId();
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
        installationId: installationId,
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
    required String installationId,
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
              'installationId': installationId,
              if (mediaType == DirectCallMediaType.video)
                'directVideoProtocol': directVideoProtocol,
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
        final actionableError =
            _videoCompatibilityError(error) ?? _knownStartRefusal(error);
        Error.throwWithStackTrace(actionableError ?? error, stackTrace);
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

  DirectVideoCompatibilityException? _videoCompatibilityError(Object error) {
    if (error is! FirebaseFunctionsException ||
        error.code != 'failed-precondition') {
      return null;
    }
    final details = error.details;
    if (details is! Map ||
        details['reason'] != DirectVideoCompatibilityException.reason ||
        details['audioFallbackAvailable'] != true) {
      return null;
    }
    return DirectVideoCompatibilityException(
      message:
          error.message ??
          'Video calling is unavailable until your friend updates YO Voice.',
    );
  }

  Object? _knownStartRefusal(Object error) {
    if (error is! FirebaseFunctionsException ||
        error.code != 'failed-precondition') {
      return null;
    }
    final details = error.details;
    if (details is! Map) return null;
    switch (details['reason']) {
      case DirectCallFriendshipException.reason:
        return const DirectCallFriendshipException();
      case DirectCallConversationException.reason:
        return const DirectCallConversationException();
      case DirectCallEmailVerificationException.reason:
        return const DirectCallEmailVerificationException();
      case DirectCallInstallationBindingException.reason:
        return const DirectCallInstallationBindingException();
    }
    return null;
  }

  @override
  Future<DirectCallStatus> accept(
    String callId, {
    DirectCallMediaType mediaType = DirectCallMediaType.audio,
  }) async {
    final installationId = await _installationId();
    return _acceptAction(
      callId,
      payload: <String, Object?>{
        'installationId': installationId,
        if (mediaType == DirectCallMediaType.video)
          'directVideoProtocol': directVideoProtocol,
      },
    );
  }

  /// Accept is installation-bound, so an `active` Firestore snapshot cannot
  /// prove that *this* installation won the Answer race. Another installation
  /// of the same account may have committed that state while this request was
  /// in flight. Only a valid callable response (including an idempotent replay
  /// for the same binding) authorises this device to continue into LiveKit.
  Future<DirectCallStatus> _acceptAction(
    String callId, {
    required Map<String, Object?> payload,
  }) async {
    final callable = _functions.httpsCallable('acceptDirectCall');
    final request = <String, Object?>{'callId': callId, ...payload};
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await callable.call<Map<String, dynamic>>(request);
        final responseCallId = response.data['callId'];
        final status = response.data['status'];
        if (responseCallId != callId || status is! String) {
          throw StateError('The call service returned an invalid answer.');
        }
        return switch (status) {
          'active' => DirectCallStatus.active,
          'ended' => DirectCallStatus.ended,
          _ => throw StateError('The call service returned an invalid answer.'),
        };
      } catch (error, stackTrace) {
        if (attempt == 0 && _isAmbiguousStartFailure(error)) continue;
        Error.throwWithStackTrace(
          _installationBindingError(error) ?? error,
          stackTrace,
        );
      }
    }
    throw StateError('The call service did not complete the answer.');
  }

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
    acceptedStatuses: const <DirectCallStatus>{
      DirectCallStatus.cancelled,
      // If Answer committed first, the server converts the caller's pending
      // Cancel into an immediate End so the user gesture still wins.
      DirectCallStatus.ended,
    },
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
    Map<String, Object?> payload = const <String, Object?>{},
    required Set<DirectCallStatus> acceptedStatuses,
  }) async {
    final callable = _functions.httpsCallable(name);
    final request = <String, Object?>{'callId': callId, ...payload};
    try {
      await callable.call<void>(request);
      return;
    } catch (error, stackTrace) {
      if (!_isAmbiguousStartFailure(error)) {
        Error.throwWithStackTrace(
          _installationBindingError(error) ?? error,
          stackTrace,
        );
      }
      if (await _callReached(callId, acceptedStatuses)) return;
      try {
        await callable.call<void>(request);
        return;
      } catch (retryError, retryStackTrace) {
        // The retry can race the first committed transition and receive a
        // deterministic failed-precondition rather than another transport
        // error. Reconcile authoritative state after every second failure.
        if (await _callReached(callId, acceptedStatuses)) {
          return;
        }
        Error.throwWithStackTrace(
          _installationBindingError(retryError) ?? retryError,
          retryStackTrace,
        );
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
  Future<VoiceConnectionInfo> createJoinToken(String callId) {
    final uid = _currentUserId;
    final scope = '$uid\u0000$callId';
    final existing = _inFlightTokens[scope];
    if (existing != null) return existing;

    late final Future<VoiceConnectionInfo> operation;
    operation = _createJoinToken(callId: callId, requestId: _requestIdFactory())
        .whenComplete(() {
          if (identical(_inFlightTokens[scope], operation)) {
            _inFlightTokens.remove(scope);
          }
        });
    _inFlightTokens[scope] = operation;
    return operation;
  }

  Future<VoiceConnectionInfo> _createJoinToken({
    required String callId,
    required String requestId,
  }) async {
    final installationId = await _installationId();
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _functions
            .httpsCallable('createDirectCallToken')
            .call<Map<String, dynamic>>({
              'callId': callId,
              'requestId': requestId,
              'installationId': installationId,
              'directVideoProtocol': directVideoProtocol,
            });
        return VoiceConnectionInfo.fromMap(response.data);
      } catch (error, stackTrace) {
        if (attempt == 0 && _isAmbiguousStartFailure(error)) continue;
        Error.throwWithStackTrace(
          _installationBindingError(error) ?? error,
          stackTrace,
        );
      }
    }
    throw StateError('The private call connection did not complete.');
  }

  DirectCallInstallationBindingException? _installationBindingError(
    Object error,
  ) {
    if (error is! FirebaseFunctionsException ||
        error.code != 'failed-precondition') {
      return null;
    }
    final details = error.details;
    if (details is Map &&
        details['reason'] == DirectCallInstallationBindingException.reason) {
      return const DirectCallInstallationBindingException();
    }
    return null;
  }
}
