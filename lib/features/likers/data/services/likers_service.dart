import 'package:cloud_functions/cloud_functions.dart';

import 'package:yovoice/features/likers/data/models/likers_page.dart';
import 'package:yovoice/features/likers/data/models/likers_target.dart';

/// Calls one list callable by [name] with the exact request [payload] and
/// returns the raw response data. Tests inject one; production uses
/// `europe-west1` Cloud Functions.
typedef LikersCallableInvoker =
    Future<Object?> Function(String name, Map<String, Object?> payload);

/// Why a likers page could not be shown (spec §3.0 error envelope).
enum LikersFailure {
  /// `failed-precondition` + `reason: "likersNotEnabled"`: the activation
  /// switch is off. The list shows its "coming soon" state.
  notEnabled,

  /// `failed-precondition` + `reason: "likersAccessRequired"`: the caller is
  /// not paid, VIP or staff (server truth). The list closes into the upsell.
  accessRequired,

  /// `permission-denied` (every content-side refusal collapsed) or
  /// `not-found` (an undeployed callable, spec §5.6).
  unavailable,

  /// `resource-exhausted`: a likers budget.
  rateLimited,

  /// `invalid-argument` for a request that carried a cursor: the cursor is
  /// expired, foreign or for another target. The list restarts once.
  invalidCursor,

  /// Everything else, including a malformed response and connectivity: the
  /// generic, retryable error state.
  network,
}

class LikersException implements Exception {
  const LikersException(this.failure);

  final LikersFailure failure;

  @override
  String toString() => 'LikersException(${failure.name})';
}

/// The one client for the three "See who liked" list callables.
///
/// No page size is ever sent (spec §3.0: a `limit` key is refused). Every
/// response is parsed with the exact [LikersPage] contract, and every failure
/// surfaces as a [LikersException] carrying a [LikersFailure].
class LikersService {
  LikersService({FirebaseFunctions? functions, LikersCallableInvoker? invoker})
    : _functionsOverride = functions,
      _invoker = invoker;

  final FirebaseFunctions? _functionsOverride;
  final LikersCallableInvoker? _invoker;

  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  Future<LikersPage> load(LikersTarget target, {String? cursor}) async {
    final payload = target.payload(cursor: cursor);
    final Object? raw;
    try {
      final injected = _invoker;
      raw = injected != null
          ? await injected(target.callableName, payload)
          : (await _functions
                    .httpsCallable(target.callableName)
                    .call<Object?>(payload))
                .data;
    } on FirebaseFunctionsException catch (error) {
      throw LikersException(failureFor(error, sentCursor: cursor != null));
    } on LikersException {
      rethrow;
    } catch (_) {
      throw const LikersException(LikersFailure.network);
    }
    try {
      return LikersPage.parse(raw);
    } on FormatException {
      throw const LikersException(LikersFailure.network);
    }
  }

  /// Maps a callable failure onto the list's states (spec §3.0).
  static LikersFailure failureFor(
    FirebaseFunctionsException error, {
    required bool sentCursor,
  }) {
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    return switch (error.code) {
      'failed-precondition' when reason == 'likersNotEnabled' =>
        LikersFailure.notEnabled,
      'failed-precondition' when reason == 'likersAccessRequired' =>
        LikersFailure.accessRequired,
      'permission-denied' || 'not-found' => LikersFailure.unavailable,
      'resource-exhausted' => LikersFailure.rateLimited,
      'invalid-argument' when sentCursor => LikersFailure.invalidCursor,
      _ => LikersFailure.network,
    };
  }
}
