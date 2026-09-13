import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:yovoice/features/messages/data/models/premium_messaging_privacy.dart';

abstract interface class PremiumMessagingPrivacyGateway {
  Stream<PremiumMessagingPrivacy> watchCurrent();

  Future<void> setPreference(
    PremiumMessagingPrivacyPreference preference,
    bool enabled,
  );
}

class PremiumMessagingPrivacyService implements PremiumMessagingPrivacyGateway {
  PremiumMessagingPrivacyService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functionsOverride = functions;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions? _functionsOverride;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');
    return user.uid;
  }

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  @override
  Stream<PremiumMessagingPrivacy> watchCurrent() {
    final uid = _uid;
    return _firestore
        .collection('directPrivacyPreferences')
        .doc(uid)
        .snapshots()
        .map(PremiumMessagingPrivacy.fromFirestore);
  }

  @override
  Future<void> setPreference(
    PremiumMessagingPrivacyPreference preference,
    bool enabled,
  ) async {
    final requestId = _newRequestId();
    final payload = <String, Object?>{
      'preference': preference.storageValue,
      'enabled': enabled,
      'requestId': requestId,
    };
    HttpsCallableResult<Map<Object?, Object?>>? response;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        response = await _functions
            .httpsCallable('setPremiumMessagingPrivacyV1')
            .call<Map<Object?, Object?>>(payload);
        break;
      } catch (error) {
        if (attempt == 0 && _isAmbiguousTransportFailure(error)) {
          continue;
        }
        rethrow;
      }
    }
    final data = response?.data;
    final selectedResult = data?[preference.storageValue];
    if (data == null ||
        data['preference'] != preference.storageValue ||
        data['enabled'] != enabled ||
        selectedResult != enabled ||
        data['hideReadReceipts'] is! bool ||
        data['hideTyping'] is! bool) {
      throw StateError(
        'The Premium messaging privacy service returned a malformed result.',
      );
    }
  }

  bool _isAmbiguousTransportFailure(Object error) =>
      error is FirebaseFunctionsException &&
      const <String>{
        'aborted',
        'cancelled',
        'deadline-exceeded',
        'internal',
        'unknown',
        'unavailable',
      }.contains(error.code);

  String _newRequestId() {
    final random = Random.secure();
    final randomPart = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}-$randomPart';
  }
}
