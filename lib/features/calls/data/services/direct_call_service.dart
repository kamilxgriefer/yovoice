import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/direct_call.dart';
import '../models/voice_connection_info.dart';

abstract interface class DirectCallGateway {
  Stream<DirectCall> watchCall(String callId);
  Future<DirectCall?> getCall(String callId);
  Stream<List<IncomingDirectCallSignal>> watchIncomingCalls();
  Future<String> startCall({
    required String calleeId,
    required String conversationId,
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
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1'),
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

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
  }) async {
    final response = await _functions
        .httpsCallable('startDirectCall')
        .call<Map<String, dynamic>>({
          'calleeId': calleeId,
          'conversationId': conversationId,
        });
    final callId = response.data['callId'] as String?;
    if (callId == null || callId.isEmpty) {
      throw StateError('The call service returned no call identifier.');
    }
    return callId;
  }

  @override
  Future<void> accept(String callId) => _action('acceptDirectCall', callId);
  @override
  Future<void> decline(String callId) => _action('declineDirectCall', callId);
  @override
  Future<void> cancel(String callId) => _action('cancelDirectCall', callId);
  @override
  Future<void> end(String callId) => _action('endDirectCall', callId);

  Future<void> _action(String name, String callId) async {
    await _functions.httpsCallable(name).call<void>({'callId': callId});
  }

  @override
  Future<VoiceConnectionInfo> createJoinToken(String callId) async {
    final response = await _functions
        .httpsCallable('createDirectCallToken')
        .call<Map<String, dynamic>>({'callId': callId});
    return VoiceConnectionInfo.fromMap(response.data);
  }
}
