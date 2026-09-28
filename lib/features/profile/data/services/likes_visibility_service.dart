import 'package:cloud_functions/cloud_functions.dart';

typedef LikesVisibilityMutationInvoker =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> data);

class LikesVisibilityException implements Exception {
  const LikesVisibilityException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The server's answer to one Hide my likes change.
class LikesVisibilityResult {
  const LikesVisibilityResult({required this.hidden, required this.changed});

  final bool hidden;
  final bool changed;
}

/// "Hide my likes" (ADR-230, spec §1.3 / §3.7).
///
/// `users/{uid}.likesHidden` is server-written: the owner update allowlist in
/// firestore.rules deliberately excludes it, so the ONLY way to change it is
/// the `setMyLikesHiddenV1` callable. There is no Firestore fallback. The
/// setting is not behind the likers activation switch, so people can opt out
/// before any list is exposed.
class LikesVisibilityService {
  LikesVisibilityService({
    FirebaseFunctions? functions,
    LikesVisibilityMutationInvoker? mutationInvoker,
  }) : _functionsOverride = functions,
       _mutationInvoker = mutationInvoker;

  final FirebaseFunctions? _functionsOverride;
  final LikesVisibilityMutationInvoker? _mutationInvoker;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// Sends EXACTLY `{hidden}` and accepts EXACTLY `{hidden, changed}`, where
  /// `hidden` must be the value asked for.
  Future<LikesVisibilityResult> setHidden(bool hidden) async {
    try {
      final payload = <String, dynamic>{'hidden': hidden};
      final injected = _mutationInvoker;
      final raw = injected != null
          ? await injected(payload)
          : Map<String, dynamic>.from(
              (await _functions
                      .httpsCallable('setMyLikesHiddenV1')
                      .call<Object?>(payload))
                  .data as Map,
            );
      if (raw.length != 2 ||
          !raw.keys.toSet().containsAll(const {'hidden', 'changed'})) {
        throw const LikesVisibilityException(
          'The server returned an unexpected privacy update.',
        );
      }
      final value = raw['hidden'];
      final changed = raw['changed'];
      if (value is! bool || changed is! bool || value != hidden) {
        throw const LikesVisibilityException(
          'The server returned an incomplete privacy update.',
        );
      }
      return LikesVisibilityResult(hidden: value, changed: changed);
    } on FirebaseFunctionsException {
      throw const LikesVisibilityException(
        'Hide my likes could not be updated.',
      );
    } on LikesVisibilityException {
      rethrow;
    } catch (_) {
      throw const LikesVisibilityException(
        'Hide my likes could not be updated. Check your connection and try again.',
      );
    }
  }
}
