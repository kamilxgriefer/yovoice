import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, immutable, kDebugMode, kIsWeb, visibleForTesting;

/// One terminal callable refusal, reduced to the only two facts that are
/// safe to leave the device.
///
/// Deliberately NOT a wrapper around the original exception: a
/// `FirebaseFunctionsException` carries a server message and a `details`
/// map, and neither is ours to ship to a crash reporter. Only the callable
/// name (a constant in this source tree) and the stable error code (a fixed
/// vocabulary) are recorded.
@immutable
class CallableRefusal {
  const CallableRefusal({required this.callable, required this.code});

  /// The callable that refused, e.g. `reserveReelDraftV2`.
  final String callable;

  /// The stable `FirebaseFunctionsException` code, e.g. `data-loss`.
  final String code;

  @override
  bool operator ==(Object other) =>
      other is CallableRefusal &&
      other.callable == callable &&
      other.code == code;

  @override
  int get hashCode => Object.hash(callable, code);

  /// What Crashlytics groups and displays. Two fields, both constants.
  @override
  String toString() => 'CallableRefusal($callable/$code)';
}

/// Where a recorded refusal goes. Replaced wholesale in tests so a unit test
/// never needs a Firebase app.
typedef CallableRefusalRecorder =
    void Function(CallableRefusal refusal, StackTrace? stackTrace);

/// The codes that mean "the answer was inconclusive, try again" rather than
/// "the server decided".
///
/// Exactly the set `MessageService.isAmbiguousTransportFailure` already
/// treats as replayable, so one definition of "not yet terminal" governs
/// both the retry loops and this reporter. A failure in this set is normal
/// operational weather and must never become a non-fatal: recording it would
/// bury the deterministic refusals this exists to surface.
const Set<String> transientCallableCodes = <String>{
  'aborted',
  'cancelled',
  'deadline-exceeded',
  'internal',
  'unavailable',
  'unknown',
};

/// Whether [error] is a refusal the client will not retry — the server
/// answered, and the answer stands.
///
/// Only a `FirebaseFunctionsException` qualifies. A raw socket/timeout
/// failure never reached a server at all, so it says nothing about the
/// backend and is not a defect signal.
bool isTerminalCallableRefusal(Object error) =>
    error is FirebaseFunctionsException &&
    !transientCallableCodes.contains(error.code);

/// The sink every refusal is handed to.
///
/// Replace it in a test and restore it in `tearDown`; production leaves it
/// pointing at Crashlytics.
@visibleForTesting
CallableRefusalRecorder callableRefusalRecorder = _recordThroughCrashlytics;

/// Restores the production sink. Call from `tearDown` after overriding
/// [callableRefusalRecorder].
@visibleForTesting
void resetCallableRefusalRecorder() {
  callableRefusalRecorder = _recordThroughCrashlytics;
}

/// Records one terminal callable refusal as a Crashlytics non-fatal.
///
/// Before this, Crashlytics only ever saw UNCAUGHT errors (`main.dart`
/// installs `FlutterError.onError` and `PlatformDispatcher.onError`), while
/// every callable failure in the app is caught and turned into a snackbar.
/// A two-day total publish-and-new-chat outage therefore produced zero
/// signal. This is the missing channel, and it is deliberately narrow:
///
///  * only terminal refusals ([isTerminalCallableRefusal]) — a retryable
///    transport error is weather, not a defect;
///  * only `{callable, code}` — no uid, caption, message text or display
///    name can reach the reporter, because the reporter cannot accept them;
///  * never throws. Observability must not be the thing that takes the app
///    down, which is the posture `main.dart` already takes for Crashlytics
///    setup and App Check activation.
void recordCallableRefusal({
  required String callable,
  required String code,
  StackTrace? stackTrace,
}) {
  try {
    callableRefusalRecorder(
      CallableRefusal(callable: callable, code: code),
      stackTrace,
    );
  } catch (error) {
    debugPrint('Callable refusal could not be recorded: $error');
  }
}

/// Records [error] only when it is a terminal refusal, and returns whether
/// it did.
///
/// Call sites pass whatever they caught; the filter lives here so a future
/// call site cannot accidentally report an `unavailable` blip.
bool recordCallableRefusalIfTerminal({
  required String callable,
  required Object error,
  StackTrace? stackTrace,
}) {
  if (!isTerminalCallableRefusal(error)) return false;
  recordCallableRefusal(
    callable: callable,
    code: (error as FirebaseFunctionsException).code,
    stackTrace: stackTrace,
  );
  return true;
}

void _recordThroughCrashlytics(CallableRefusal refusal, StackTrace? stack) {
  // Same gate as `_installCrashReporting`: the plugin throws on web, and a
  // debug build's failures are already in front of the developer.
  if (kIsWeb || kDebugMode) return;
  FirebaseCrashlytics.instance.recordError(
    refusal,
    stack,
    reason: 'callable refusal',
    fatal: false,
  );
}
