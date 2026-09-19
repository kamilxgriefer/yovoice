import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// `deleteAccountSelfV1` is a mark-and-sweep contract: the callable records the
/// intent in one transaction and returns, and a leased worker performs the
/// teardown. The client therefore never reports "deleted" — it reports
/// "being deleted", which is what actually happened.
const accountDeletionCallableName = 'deleteAccountSelfV1';

/// The `accountDeletion.state` machine as the server owns it.
enum AccountDeletionState {
  pending,
  running,
  completed,

  /// The pipeline gave up. The account is disabled and invisible rather than
  /// half-deleted; an operator has to finish it. The client still shows the
  /// request as accepted, because it was.
  deadLetter,

  /// A state this build does not know. Never treated as "finished".
  unknown;

  static AccountDeletionState parse(Object? value) => switch (value) {
    'pending' => pending,
    'running' => running,
    'completed' => completed,
    'deadLetter' => deadLetter,
    _ => unknown,
  };
}

@immutable
class AccountDeletionReceipt {
  const AccountDeletionReceipt({required this.state, this.requestedAt});

  factory AccountDeletionReceipt.fromMap(Map<String, Object?> data) {
    final millis = data['requestedAtMillis'];
    return AccountDeletionReceipt(
      state: AccountDeletionState.parse(data['state']),
      requestedAt: millis is int
          ? DateTime.fromMillisecondsSinceEpoch(millis)
          : null,
    );
  }

  final AccountDeletionState state;
  final DateTime? requestedAt;
}

/// Why a deletion request did not start. Each value maps to one sentence the
/// user can act on; the raw Firebase code is never shown.
enum AccountDeletionFailureKind {
  /// `failed-precondition` / `recent-authentication-required`: the sign-in is
  /// older than the privileged window. The flow re-authenticates and retries.
  recentSignInRequired,

  /// The callable is not deployed for this project yet, or the
  /// `appConfig/accountDeletion` kill switch is off. The email route on the
  /// same screen still works, and the copy says so.
  unavailable,

  /// The per-account attempt budget is spent.
  rateLimited,

  /// The session ended underneath the request.
  signedOut,

  unknown,
}

@immutable
class AccountDeletionFailure implements Exception {
  const AccountDeletionFailure(this.kind, {this.code});

  final AccountDeletionFailureKind kind;

  /// The originating callable code, for logs and tests only — never rendered.
  final String? code;

  @override
  String toString() => 'AccountDeletionFailure(${kind.name}, code: $code)';
}

/// The one shell callable this feature makes: `(name, payload) -> data`.
/// Injected in tests so the contract itself — the name and the empty payload —
/// is asserted rather than assumed.
typedef AccountDeletionInvoker =
    Future<Map<String, Object?>> Function(
      String name,
      Map<String, Object?> payload,
    );

/// Forces a new ID token and answers whether there was still a user to mint one
/// for. Injected in tests so the ORDERING — refresh, then callable — is
/// asserted rather than assumed.
typedef AccountDeletionTokenRefresher = Future<bool> Function();

abstract interface class AccountDeletionClient {
  Future<AccountDeletionReceipt> requestDeletion();
}

class AccountDeletionService implements AccountDeletionClient {
  AccountDeletionService({
    FirebaseFunctions? functions,
    FirebaseAuth? firebaseAuth,
    @visibleForTesting AccountDeletionInvoker? invoke,
    @visibleForTesting AccountDeletionTokenRefresher? refreshIdToken,
  }) : _functions = functions,
       _firebaseAuth = firebaseAuth,
       _invoke = invoke,
       _refreshIdToken = refreshIdToken;

  final FirebaseFunctions? _functions;
  final FirebaseAuth? _firebaseAuth;
  final AccountDeletionInvoker? _invoke;
  final AccountDeletionTokenRefresher? _refreshIdToken;

  FirebaseFunctions get _resolvedFunctions =>
      _functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// The forced refresh lives HERE rather than in `ReauthenticationService`
  /// because this is the only place that knows a callable is about to be sent,
  /// and because it then holds for every route into deletion — password,
  /// Google, Apple, and any second factor resolved along the way.
  Future<bool> _forceIdTokenRefresh() async {
    final user = (_firebaseAuth ?? FirebaseAuth.instance).currentUser;
    if (user == null) return false;
    await user.getIdToken(true);
    return true;
  }

  @override
  Future<AccountDeletionReceipt> requestDeletion() async {
    // `requireRecentPrivilegedAuthentication` (functions/utils/auth.js) refuses
    // any token whose `auth_time` is older than 300 seconds.
    // `reauthenticateWithCredential` / `reauthenticateWithProvider` mint a new
    // token, but the CACHED one is what cloud_functions sends, and on the
    // native SDKs that cached token is not guaranteed to carry the new
    // auth_time. Without this the callable answers `failed-precondition /
    // recent-authentication-required` however recently the user proved who
    // they are, the screen shows "your sign-in is no longer recent enough",
    // and the user loops forever. The website hit exactly this and fixed it
    // the same way (src/providers/auth-provider.tsx).
    try {
      if (!await (_refreshIdToken ?? _forceIdTokenRefresh)()) {
        throw const AccountDeletionFailure(
          AccountDeletionFailureKind.signedOut,
          code: 'no-current-user',
        );
      }
    } on FirebaseAuthException catch (error) {
      // A refresh we could not complete means we cannot know the token is
      // fresh. Saying so and letting the user start again is honest; sending
      // a possibly stale token and rendering the server's refusal is not.
      throw AccountDeletionFailure(
        AccountDeletionFailureKind.recentSignInRequired,
        code: error.code,
      );
    }
    try {
      // No input at all: the uid comes from the verified Auth token, so there
      // is nothing a caller could substitute for somebody else's account.
      final data = await (_invoke ?? _callFunction)(
        accountDeletionCallableName,
        const <String, Object?>{},
      );
      return AccountDeletionReceipt.fromMap(data);
    } on FirebaseFunctionsException catch (error) {
      throw AccountDeletionFailure(_kindOf(error), code: error.code);
    }
  }

  Future<Map<String, Object?>> _callFunction(
    String name,
    Map<String, Object?> payload,
  ) async {
    final result = await _resolvedFunctions
        .httpsCallable(name)
        .call<Object?>(payload);
    final data = result.data;
    return data is Map ? Map<String, Object?>.from(data) : <String, Object?>{};
  }
}

AccountDeletionFailureKind _kindOf(FirebaseFunctionsException error) {
  if (error.code == 'failed-precondition') {
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    // `requireRecentPrivilegedAuthentication` and the `appConfig/accountDeletion`
    // kill switch answer the SAME code and are told apart only by `reason`.
    // Reading the code alone would send somebody to re-authenticate against a
    // server that is simply switched off.
    if (reason == 'recent-authentication-required') {
      return AccountDeletionFailureKind.recentSignInRequired;
    }
    if (reason == 'account-deletion-disabled') {
      return AccountDeletionFailureKind.unavailable;
    }
    // An unrecognised precondition is still an availability fact, not
    // something the person did wrong.
    return AccountDeletionFailureKind.unavailable;
  }
  return switch (error.code) {
    'unauthenticated' => AccountDeletionFailureKind.signedOut,
    'resource-exhausted' => AccountDeletionFailureKind.rateLimited,
    // `not-found` is genuinely ambiguous: it is what Firebase answers for a
    // callable that is not deployed, and also what `deleteAccountSelfV1`
    // answers when `users/{uid}` is already gone. Both mean "this cannot be
    // finished from here", and both are served by the same sentence and the
    // same email route, so they are not guessed apart.
    'not-found' ||
    'unimplemented' ||
    'unavailable' => AccountDeletionFailureKind.unavailable,
    _ => AccountDeletionFailureKind.unknown,
  };
}
