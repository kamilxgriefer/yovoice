import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/servers/data/models/server_creation.dart';
import 'package:yovoice/features/servers/presentation/server_action_failure.dart';

void main() {
  const polish = AppLocalizations(Locale('pl'));

  FirebaseFunctionsException failure({Object? details}) =>
      FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Servers are not enabled for this account.',
        details: details,
      );

  test('runtime rollout refusal has a distinct stable client meaning', () {
    final error = failure(
      details: const {'reason': serverActivationUnavailableReason},
    );

    expect(isServerActivationUnavailableFailure(error), isTrue);
    expect(
      classifyServerCreationFailure(error),
      ServerCreationFailure.unavailable,
    );
    expect(
      serverActionFailureCopy(error, polish),
      'Ta część YO Voice jest jeszcze przygotowywana.',
    );
  });

  test('ordinary failed-precondition keeps its product-rule meaning', () {
    final error = failure();

    expect(isServerActivationUnavailableFailure(error), isFalse);
    expect(
      classifyServerCreationFailure(error),
      ServerCreationFailure.precondition,
    );
    expect(
      serverActionFailureCopy(error, polish, fallback: 'Warunek produktu'),
      'Warunek produktu',
    );
  });

  test('malformed details cannot impersonate the rollout reason', () {
    for (final details in <Object?>[
      serverActivationUnavailableReason,
      const <String>[],
      const {'reason': 'something-else'},
    ]) {
      final error = failure(details: details);
      expect(isServerActivationUnavailableFailure(error), isFalse);
      expect(
        classifyServerCreationFailure(error),
        ServerCreationFailure.precondition,
      );
    }
  });
}
