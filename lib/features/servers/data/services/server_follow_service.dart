import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

abstract interface class ServerFollowRepository {
  Stream<bool> watchCommunityFollow(String serverId);

  Future<bool> setCommunityFollow({
    required String serverId,
    required bool following,
  });
}

/// The current member's private community-follow preference. Server
/// membership remains the access boundary; following only controls whether
/// this person wants creator-style updates from that server.
class ServerFollowService implements ServerFollowRepository {
  ServerFollowService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    String? currentUserIdOverride,
    Future<Map<Object?, Object?>> Function(
      String name,
      Map<String, Object?> data,
    )?
    callOverride,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functionsOverride = functions,
       _authOverride = auth,
       _currentUserIdOverride = currentUserIdOverride,
       _callOverride = callOverride;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions? _functionsOverride;
  final FirebaseAuth? _authOverride;
  final String? _currentUserIdOverride;
  final Future<Map<Object?, Object?>> Function(
    String name,
    Map<String, Object?> data,
  )?
  _callOverride;

  String get _currentUserId =>
      _currentUserIdOverride ??
      (_authOverride ?? FirebaseAuth.instance).currentUser?.uid ??
      '';

  String _requestId() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  @override
  Stream<bool> watchCommunityFollow(String serverId) {
    final uid = _currentUserId;
    if (uid.isEmpty) return Stream.value(false);
    return _firestore
        .collection('clubs')
        .doc(serverId)
        .collection('followers')
        .doc(uid)
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          return snapshot.exists &&
              data?['schemaVersion'] == 1 &&
              data?['serverId'] == serverId &&
              data?['userId'] == uid &&
              data?['following'] == true;
        });
  }

  @override
  Future<bool> setCommunityFollow({
    required String serverId,
    required bool following,
  }) async {
    if (_currentUserId.isEmpty) {
      throw StateError('Sign in before following a community server.');
    }
    final payload = <String, Object?>{
      'serverId': serverId,
      'requestId': _requestId(),
      'following': following,
    };
    final override = _callOverride;
    final result = override != null
        ? await override('setCommunityServerFollowV1', payload)
        : (await (_functionsOverride ??
                      FirebaseFunctions.instanceFor(region: 'europe-west1'))
                  .httpsCallable('setCommunityServerFollowV1')
                  .call<Map<Object?, Object?>>(payload))
              .data;
    if (result['serverId'] != serverId || result['following'] is! bool) {
      throw const FormatException('Malformed server follow response.');
    }
    return result['following']! as bool;
  }
}
