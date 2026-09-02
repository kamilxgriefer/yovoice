import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/follow_user.dart';

typedef FollowMutationInvoker =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> data);

class FollowService {
  static const int _maxVisibleEdges = 100;

  /// Follow notifications are no longer this service's business: the
  /// server-side social callable owns the graph and matching activity row
  /// transactionally (ADR-114), so there is nothing here to inject.
  FollowService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    FollowMutationInvoker? mutationInvoker,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions,
       _mutationInvoker = mutationInvoker;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;
  final FollowMutationInvoker? _mutationInvoker;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');
    return user.uid;
  }

  Stream<bool> watchIsFollowing(String targetUserId) {
    if (targetUserId == _uid) return Stream<bool>.value(false);
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('following')
        .doc(targetUserId)
        .snapshots()
        .map((document) => document.exists);
  }

  Stream<List<FollowUser>> watchFollowers(String userId) {
    return _watchEdges(userId, collectionName: 'followers');
  }

  Stream<List<FollowUser>> watchFollowing(String userId) {
    return _watchEdges(userId, collectionName: 'following');
  }

  Stream<List<FollowUser>> _watchEdges(
    String userId, {
    required String collectionName,
  }) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection(collectionName)
        .orderBy('followedAt', descending: true)
        .limit(_maxVisibleEdges)
        .snapshots()
        .asyncMap((snapshot) async {
          final resolved = await Future.wait(
            snapshot.docs.map((edge) async {
              final data = edge.data();
              final uid = (data['uid'] as String?)?.trim().isNotEmpty == true
                  ? data['uid'] as String
                  : edge.id;
              try {
                final profile = await _firestore
                    .collection('publicProfiles')
                    .doc(uid)
                    .get();
                return FollowUser.fromEdgeAndProfile(
                  edge: edge,
                  profile: profile,
                );
              } on FirebaseException catch (error) {
                if (error.code == 'permission-denied') return null;
                rethrow;
              }
            }),
          );
          return resolved.whereType<FollowUser>().toList(growable: false);
        });
  }

  Future<void> follow(String targetUserId) async {
    final currentUserId = _uid;
    if (targetUserId == currentUserId) {
      throw ArgumentError('You cannot follow yourself.');
    }

    await _setFollow(targetUserId, following: true);
  }

  Future<void> unfollow(String targetUserId) async {
    final currentUserId = _uid;
    if (targetUserId == currentUserId) return;

    await _setFollow(targetUserId, following: false);
  }

  Future<void> _setFollow(
    String targetUserId, {
    required bool following,
  }) async {
    final data = <String, dynamic>{
      'targetUserId': targetUserId,
      'following': following,
    };
    final injected = _mutationInvoker;
    if (injected != null) {
      await injected(data);
      return;
    }
    try {
      await _functions.httpsCallable('setFollow').call(data);
    } on FirebaseFunctionsException {
      throw StateError('The follow action could not be completed.');
    }
  }
}
