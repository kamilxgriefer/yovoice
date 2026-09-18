import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/helpers/callable_failure_reporter.dart';

/// Crashlytics only ever saw UNCAUGHT errors, and every callable failure in
/// this app is caught and turned into a snackbar. Two days of a total
/// publish-and-new-chat outage therefore produced zero signal.
///
/// These are the guarantees that make the new channel worth having and safe
/// to ship: it fires on deterministic refusals, it stays silent for
/// transport weather, it carries two constants and nothing else, and it can
/// never be the thing that takes the app down.
void main() {
  final recorded = <({CallableRefusal refusal, StackTrace? stackTrace})>[];

  setUp(() {
    recorded.clear();
    callableRefusalRecorder = (refusal, stackTrace) =>
        recorded.add((refusal: refusal, stackTrace: stackTrace));
  });

  tearDown(resetCallableRefusalRecorder);

  test('a terminal refusal records exactly one {callable, code} report', () {
    final reported = recordCallableRefusalIfTerminal(
      callable: 'reserveReelDraftV2',
      error: FirebaseFunctionsException(
        code: 'data-loss',
        message: 'The canonical public profile is unavailable.',
        details: const <String, Object?>{'uid': 'owner-uid'},
      ),
    );

    expect(reported, isTrue);
    expect(recorded, hasLength(1));
    expect(recorded.single.refusal.callable, 'reserveReelDraftV2');
    expect(recorded.single.refusal.code, 'data-loss');
  });

  test('the report carries no server message, details or identity', () {
    recordCallableRefusalIfTerminal(
      callable: 'openDirectConversation',
      error: FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'owner-uid may not message them-uid (Kamil Jaguszewski).',
        details: const <String, Object?>{
          'uid': 'owner-uid',
          'targetUserId': 'them-uid',
        },
      ),
    );

    final rendered = recorded.single.refusal.toString();
    expect(
      rendered,
      'CallableRefusal(openDirectConversation/permission-denied)',
    );
    for (final secret in const <String>[
      'owner-uid',
      'them-uid',
      'Kamil',
      'may not message',
    ]) {
      expect(
        rendered,
        isNot(contains(secret)),
        reason: 'the reporter must not be able to carry user data at all',
      );
    }
  });

  test('transport weather records nothing', () {
    for (final code in transientCallableCodes) {
      expect(
        recordCallableRefusalIfTerminal(
          callable: 'sendDirectMessage',
          error: FirebaseFunctionsException(code: code, message: 'later'),
        ),
        isFalse,
        reason: '$code is replayed, not a defect worth a non-fatal',
      );
    }
    expect(
      recordCallableRefusalIfTerminal(
        callable: 'sendDirectMessage',
        error: FirebaseException(plugin: 'cloud_functions', code: 'no-app'),
      ),
      isFalse,
      reason: 'a failure that never reached a server says nothing about it',
    );
    expect(recorded, isEmpty);
  });

  test('a throwing recorder is swallowed, never propagated', () {
    callableRefusalRecorder = (_, _) => throw StateError('crashlytics is down');

    expect(
      () => recordCallableRefusal(
        callable: 'finalizeReelDraftV2',
        code: 'internal',
      ),
      returnsNormally,
    );
  });
}
