import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/auth/presentation/screens/auth_gate.dart';

void main() {
  test('authenticated profile bootstrap retries transient failures', () async {
    var attempts = 0;

    await ensureAuthenticatedProfileWithRetry(() async {
      attempts += 1;
      if (attempts < 3) {
        throw StateError('temporary Firestore failure');
      }
    }, retryDelays: const [Duration.zero, Duration.zero, Duration.zero]);

    expect(attempts, 3);
  });

  test('authenticated profile bootstrap fails closed after retries', () async {
    var attempts = 0;

    await expectLater(
      ensureAuthenticatedProfileWithRetry(() async {
        attempts += 1;
        throw StateError('persistent Firestore failure');
      }, retryDelays: const [Duration.zero, Duration.zero]),
      throwsStateError,
    );

    expect(attempts, 2);
  });
}
