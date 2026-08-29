import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/features/home/presentation/screens/main_shell.dart';

void main() {
  test(
    'presentation guard rejects a second launch until route completion',
    () async {
      final guard = GuidedOnboardingPresentationGuard();
      final route = Completer<String?>();

      final first = guard.run(() => route.future);
      expect(guard.isActive, isTrue);

      var duplicatePresented = false;
      final duplicate = await guard.run(() async {
        duplicatePresented = true;
        return 'duplicate';
      });

      expect(duplicate, isNull);
      expect(duplicatePresented, isFalse);
      expect(guard.isActive, isTrue);

      route.complete('completed');
      expect(await first, 'completed');
      expect(guard.isActive, isFalse);
    },
  );

  test(
    'eligibility waits for the native-permission readiness barrier',
    () async {
      final readiness = Completer<void>();
      var evaluated = false;
      var completed = false;

      final result = evaluateGuidedOnboardingAfterReadiness(
        readiness: readiness.future,
        evaluate: () async {
          evaluated = true;
          return true;
        },
      )..then((_) => completed = true);

      await Future<void>.delayed(Duration.zero);
      expect(evaluated, isFalse);
      expect(completed, isFalse);

      readiness.complete();
      expect(await result, isTrue);
      expect(evaluated, isTrue);
      expect(completed, isTrue);
    },
  );

  test(
    'a readiness failure fails open and still evaluates eligibility',
    () async {
      var evaluations = 0;

      final result = await evaluateGuidedOnboardingAfterReadiness(
        readiness: Future<void>.error(StateError('prompt unavailable')),
        evaluate: () async {
          evaluations += 1;
          return true;
        },
      );

      expect(result, isTrue);
      expect(evaluations, 1);
    },
  );
}
