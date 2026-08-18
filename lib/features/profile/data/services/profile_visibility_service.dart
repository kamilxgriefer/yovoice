import 'package:cloud_functions/cloud_functions.dart';

import 'package:yovoice/features/profile/data/models/profile_visibility.dart';

typedef ProfileVisibilityMutationInvoker =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> data);

class ProfileVisibilityException implements Exception {
  const ProfileVisibilityException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProfileVisibilityService {
  ProfileVisibilityService({
    FirebaseFunctions? functions,
    ProfileVisibilityMutationInvoker? mutationInvoker,
  }) : _functionsOverride = functions,
       _mutationInvoker = mutationInvoker;

  final FirebaseFunctions? _functionsOverride;
  final ProfileVisibilityMutationInvoker? _mutationInvoker;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// Changes visibility through the server-owned privacy boundary.
  ///
  /// There is deliberately no direct Firestore fallback. The callable also
  /// revokes public-website consent and clears the already-materialised public
  /// people showcase when visibility becomes non-public; a client-only write
  /// could not close that signed-out copy without a leak window.
  Future<ProfileVisibility> setVisibility(ProfileVisibility visibility) async {
    try {
      final payload = <String, dynamic>{'visibility': visibility.name};
      final injected = _mutationInvoker;
      final raw = injected != null
          ? await injected(payload)
          : Map<String, dynamic>.from(
              (await _functions
                      .httpsCallable('setMyProfileVisibility')
                      .call<Map<String, dynamic>>(payload))
                  .data,
            );
      if (raw.keys.length != 2 ||
          !raw.keys.toSet().containsAll(const {'visibility', 'changed'})) {
        throw const ProfileVisibilityException(
          'The server returned an unexpected privacy update.',
        );
      }
      final value = raw['visibility'];
      final changed = raw['changed'];
      if (value is! String ||
          !ProfileVisibility.values.any((item) => item.name == value) ||
          changed is! bool) {
        throw const ProfileVisibilityException(
          'The server returned an incomplete privacy update.',
        );
      }
      return ProfileVisibility.fromValue(value);
    } on FirebaseFunctionsException catch (error) {
      throw ProfileVisibilityException(
        error.message ?? 'Profile visibility could not be updated.',
      );
    } on ProfileVisibilityException {
      rethrow;
    } catch (_) {
      throw const ProfileVisibilityException(
        'Profile visibility could not be updated. Check your connection and try again.',
      );
    }
  }
}
