import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

typedef CreatorAudienceMutationInvoker =
    Future<Map<Object?, Object?>> Function(
      String callable,
      Map<String, Object?> payload,
    );
typedef CreatorAudienceRequestIdFactory = String Function();

enum CreatorAudienceFailure {
  unauthenticated,
  eligibility,
  inactiveAccount,
  invalidRequest,
  conflictingRequest,
  staleRequest,
  unavailable,
  invalidResponse,
}

class CreatorAudienceException implements Exception {
  const CreatorAudienceException(this.failure);

  final CreatorAudienceFailure failure;

  @override
  String toString() => 'Creator audience update failed: ${failure.name}';
}

class CreatorAudienceUpdate {
  const CreatorAudienceUpdate({
    required this.enabled,
    required this.visible,
    required this.changed,
  });

  final bool enabled;
  final bool visible;
  final bool changed;
}

class CreatorAudienceProjection {
  const CreatorAudienceProjection({
    required this.visible,
    required this.followerCount,
    required this.followingCount,
  });

  const CreatorAudienceProjection.hidden()
    : visible = false,
      followerCount = 0,
      followingCount = 0;

  final bool visible;
  final int followerCount;
  final int followingCount;

  factory CreatorAudienceProjection.fromMap(Map<String, dynamic> data) {
    final visible = data['creatorAudienceVisible'] == true;
    if (!visible) return const CreatorAudienceProjection.hidden();
    int count(String field) =>
        ((data[field] as num?)?.toInt() ?? 0).clamp(0, 1 << 31);
    return CreatorAudienceProjection(
      visible: true,
      followerCount: count('followerCount'),
      followingCount: count('followingCount'),
    );
  }
}

/// Owns the private opt-in mutation and reads the safe public projection.
///
/// The client deliberately never reads the private age-verification signal.
/// The callable decides eligibility and publishes only
/// `creatorAudienceVisible` to the public profile.
class CreatorAudienceService {
  CreatorAudienceService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    CreatorAudienceMutationInvoker? mutationInvoker,
    CreatorAudienceRequestIdFactory? requestIdFactory,
  }) : _firestoreOverride = firestore,
       _functionsOverride = functions,
       _mutationInvoker = mutationInvoker,
       _requestIdFactory = requestIdFactory;

  static final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9_-]{8,128}$');

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseFunctions? _functionsOverride;
  final CreatorAudienceMutationInvoker? _mutationInvoker;
  final CreatorAudienceRequestIdFactory? _requestIdFactory;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  String newRequestId() {
    final supplied = _requestIdFactory?.call();
    if (supplied != null) {
      if (!_requestIdPattern.hasMatch(supplied)) {
        throw const CreatorAudienceException(
          CreatorAudienceFailure.invalidRequest,
        );
      }
      return supplied;
    }
    final random = Random.secure();
    final entropy = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'aud_${DateTime.now().toUtc().microsecondsSinceEpoch}_$entropy';
  }

  Stream<CreatorAudienceProjection> watchPublicProjection(String userId) {
    final normalized = userId.trim();
    if (normalized.isEmpty) {
      return Stream.value(const CreatorAudienceProjection.hidden());
    }
    return _firestore
        .collection('publicProfiles')
        .doc(normalized)
        .snapshots()
        .map(
          (snapshot) => CreatorAudienceProjection.fromMap(
            snapshot.data() ?? const <String, dynamic>{},
          ),
        );
  }

  Future<CreatorAudienceUpdate> setEnabled({
    required bool enabled,
    required String requestId,
  }) async {
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw const CreatorAudienceException(
        CreatorAudienceFailure.invalidRequest,
      );
    }
    final payload = <String, Object?>{
      'enabled': enabled,
      'requestId': requestId,
    };
    try {
      final injected = _mutationInvoker;
      final raw = injected != null
          ? await injected('setCreatorAudienceEnabled', payload)
          : (await _functions
                    .httpsCallable('setCreatorAudienceEnabled')
                    .call<Map<Object?, Object?>>(payload))
                .data;
      if (raw.length != 3 ||
          !raw.keys.toSet().containsAll(const {
            'creatorAudienceEnabled',
            'creatorAudienceVisible',
            'changed',
          })) {
        throw const CreatorAudienceException(
          CreatorAudienceFailure.invalidResponse,
        );
      }
      final savedEnabled = raw['creatorAudienceEnabled'];
      final visible = raw['creatorAudienceVisible'];
      final changed = raw['changed'];
      if (savedEnabled is! bool || visible is! bool || changed is! bool) {
        throw const CreatorAudienceException(
          CreatorAudienceFailure.invalidResponse,
        );
      }
      return CreatorAudienceUpdate(
        enabled: savedEnabled,
        visible: visible,
        changed: changed,
      );
    } on FirebaseFunctionsException catch (error) {
      throw CreatorAudienceException(switch (error.code) {
        'unauthenticated' => CreatorAudienceFailure.unauthenticated,
        'failed-precondition' => CreatorAudienceFailure.eligibility,
        'permission-denied' => CreatorAudienceFailure.inactiveAccount,
        'invalid-argument' => CreatorAudienceFailure.invalidRequest,
        'already-exists' => CreatorAudienceFailure.conflictingRequest,
        'aborted' => CreatorAudienceFailure.staleRequest,
        _ => CreatorAudienceFailure.unavailable,
      });
    } on CreatorAudienceException {
      rethrow;
    } catch (_) {
      throw const CreatorAudienceException(CreatorAudienceFailure.unavailable);
    }
  }
}
