import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:yovoice/features/clubs/data/models/family_check_in.dart';

abstract interface class ServerFamilyCheckInRepository {
  Stream<List<FamilyCheckIn>> watchCheckIns(String serverId, {int limit = 20});

  Future<void> postCheckIn({
    required String serverId,
    required FamilyCheckInStatus status,
  });

  Future<void> deleteCheckIn({
    required String serverId,
    required String checkInId,
  });
}

class ServerFamilyCheckInService implements ServerFamilyCheckInRepository {
  ServerFamilyCheckInService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    Future<Map<Object?, Object?>> Function(
      String name,
      Map<String, Object?> data,
    )?
    callOverride,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functionsOverride = functions,
       _authOverride = auth,
       _callOverride = callOverride;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions? _functionsOverride;
  final FirebaseAuth? _authOverride;
  final Future<Map<Object?, Object?>> Function(
    String name,
    Map<String, Object?> data,
  )?
  _callOverride;

  String _requestId() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _call(String name, Map<String, Object?> data) async {
    if (_callOverride == null &&
        (_authOverride ?? FirebaseAuth.instance).currentUser == null) {
      throw StateError('Sign in before updating a family server.');
    }
    final override = _callOverride;
    if (override != null) {
      await override(name, data);
      return;
    }
    await (_functionsOverride ??
            FirebaseFunctions.instanceFor(region: 'europe-west1'))
        .httpsCallable(name)
        .call<Map<Object?, Object?>>(data);
  }

  @override
  Stream<List<FamilyCheckIn>> watchCheckIns(
    String serverId, {
    int limit = 20,
  }) => _firestore
      .collection('clubs')
      .doc(serverId)
      .collection('checkIns')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(FamilyCheckIn.fromFirestore)
            .where(
              (checkIn) => checkIn.userId.isNotEmpty && checkIn.status != null,
            )
            .toList(growable: false),
      );

  @override
  Future<void> postCheckIn({
    required String serverId,
    required FamilyCheckInStatus status,
  }) => _call('createServerFamilyCheckInV1', {
    'serverId': serverId,
    'requestId': _requestId(),
    'status': status.value,
  });

  @override
  Future<void> deleteCheckIn({
    required String serverId,
    required String checkInId,
  }) => _call('deleteServerFamilyCheckInV1', {
    'serverId': serverId,
    'checkInId': checkInId,
    'requestId': _requestId(),
  });
}
