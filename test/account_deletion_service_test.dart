import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/features/account/data/account_deletion_service.dart';

void main() {
  group('the ID token is refreshed before the callable is sent', () {
    // `requireRecentPrivilegedAuthentication` refuses a token whose `auth_time`
    // is older than 300s. Re-authenticating mints a new token but the CACHED
    // one is what cloud_functions sends, so without a forced refresh the
    // callable answers `recent-authentication-required` however recently the
    // user proved who they are, and the delete screen loops forever.
    test('the forced refresh happens FIRST, every time', () async {
      final order = <String>[];
      final service = AccountDeletionService(
        refreshIdToken: () async {
          order.add('refresh');
          return true;
        },
        invoke: (_, _) async {
          order.add('callable');
          return {'state': 'pending'};
        },
      );

      await service.requestDeletion();

      expect(order, ['refresh', 'callable']);
    });

    test('no signed-in user means no callable at all', () async {
      var invoked = false;
      final service = AccountDeletionService(
        refreshIdToken: () async => false,
        invoke: (_, _) async {
          invoked = true;
          return const {};
        },
      );

      await expectLater(
        service.requestDeletion(),
        throwsA(
          isA<AccountDeletionFailure>().having(
            (failure) => failure.kind,
            'kind',
            AccountDeletionFailureKind.signedOut,
          ),
        ),
      );
      expect(invoked, isFalse);
    });

    test('a refresh we could not complete is reported, not papered over',
        () async {
      var invoked = false;
      final service = AccountDeletionService(
        refreshIdToken: () async =>
            throw FirebaseAuthException(code: 'network-request-failed'),
        invoke: (_, _) async {
          invoked = true;
          return const {};
        },
      );

      await expectLater(
        service.requestDeletion(),
        throwsA(
          isA<AccountDeletionFailure>().having(
            (failure) => failure.kind,
            'kind',
            AccountDeletionFailureKind.recentSignInRequired,
          ),
        ),
      );
      // Sending a possibly stale token and rendering the server's refusal
      // would tell the user to do the one thing that cannot help.
      expect(invoked, isFalse);
    });
  });

  group('deleteAccountSelfV1 contract', () {
    test('sends the callable name with no input at all', () async {
      final calls = <(String, Map<String, Object?>)>[];
      final service = AccountDeletionService(
        refreshIdToken: () async => true,
        invoke: (name, payload) async {
          calls.add((name, payload));
          return {'state': 'pending', 'requestedAtMillis': 1758153600000};
        },
      );

      final receipt = await service.requestDeletion();

      // The uid comes from the verified Auth token, so there is nothing in the
      // payload a caller could substitute for somebody else's account.
      expect(calls.single.$1, 'deleteAccountSelfV1');
      expect(calls.single.$2, isEmpty);
      expect(receipt.state, AccountDeletionState.pending);
      expect(
        receipt.requestedAt,
        DateTime.fromMillisecondsSinceEpoch(1758153600000),
      );
    });

    test('a state this build does not know is never read as finished', () {
      final receipt = AccountDeletionReceipt.fromMap(const {
        'state': 'somethingNew',
      });
      expect(receipt.state, AccountDeletionState.unknown);
      expect(receipt.requestedAt, isNull);
    });

    test('every server state parses to its own value', () {
      for (final entry in const {
        'pending': AccountDeletionState.pending,
        'running': AccountDeletionState.running,
        'completed': AccountDeletionState.completed,
        'deadLetter': AccountDeletionState.deadLetter,
      }.entries) {
        expect(AccountDeletionState.parse(entry.key), entry.value);
      }
    });
  });

  group('failure mapping', () {
    Future<AccountDeletionFailure> failureFor(
      FirebaseFunctionsException error,
    ) async {
      final service = AccountDeletionService(
        refreshIdToken: () async => true,
        invoke: (_, _) async => throw error,
      );
      try {
        await service.requestDeletion();
      } on AccountDeletionFailure catch (failure) {
        return failure;
      }
      fail('the failure was swallowed');
    }

    test(
      'a stale sign-in is told apart from every other precondition',
      () async {
        // `requireRecentPrivilegedAuthentication` answers `failed-precondition`
        // with this exact reason; the kill switch answers the same code without
        // it. Reading only the code would send the user to re-authenticate on a
        // server that is simply switched off.
        final stale = await failureFor(
          FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'Sign in again before performing this sensitive action.',
            details: const {
              'reason': 'recent-authentication-required',
              'maxAgeSeconds': 300,
            },
          ),
        );
        expect(stale.kind, AccountDeletionFailureKind.recentSignInRequired);

        // The kill switch, `appConfig/accountDeletion` — same code, its own
        // reason.
        final switchedOff = await failureFor(
          FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'Account deletion is temporarily unavailable.',
            details: const {'reason': 'account-deletion-disabled'},
          ),
        );
        expect(switchedOff.kind, AccountDeletionFailureKind.unavailable);

        // A precondition this build has never seen still fails closed to an
        // availability fact rather than to a re-authentication loop.
        final unknownReason = await failureFor(
          FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'something new',
          ),
        );
        expect(unknownReason.kind, AccountDeletionFailureKind.unavailable);
      },
    );

    test('a callable that is not deployed reads as unavailable', () async {
      for (final code in ['not-found', 'unimplemented', 'unavailable']) {
        final failure = await failureFor(
          FirebaseFunctionsException(code: code, message: code),
        );
        expect(
          failure.kind,
          AccountDeletionFailureKind.unavailable,
          reason: code,
        );
      }
    });

    test('budget and session failures keep their own sentence', () async {
      expect(
        (await failureFor(
          FirebaseFunctionsException(
            code: 'resource-exhausted',
            message: 'slow down',
          ),
        )).kind,
        AccountDeletionFailureKind.rateLimited,
      );
      expect(
        (await failureFor(
          FirebaseFunctionsException(
            code: 'unauthenticated',
            message: 'signed out',
          ),
        )).kind,
        AccountDeletionFailureKind.signedOut,
      );
      expect(
        (await failureFor(
          FirebaseFunctionsException(code: 'internal', message: 'boom'),
        )).kind,
        AccountDeletionFailureKind.unknown,
      );
    });

    test(
      'the raw callable code is carried for logs, never for the user',
      () async {
        final failure = await failureFor(
          FirebaseFunctionsException(code: 'internal', message: 'RAW DETAIL'),
        );
        expect(failure.code, 'internal');
        expect(failure.toString(), isNot(contains('RAW DETAIL')));
      },
    );
  });
}
