import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

typedef RevokeSessionsCall = Future<Map<String, dynamic>> Function();
typedef CurrentSessionLoader = Future<CurrentSessionInfo> Function();

@immutable
class CurrentSessionInfo {
  const CurrentSessionInfo({
    required this.signedInAt,
    required this.providerLabels,
  });

  final DateTime? signedInAt;
  final List<String> providerLabels;
}

@immutable
class RevokeSessionsResult {
  const RevokeSessionsResult({required this.completeWithin});

  final Duration completeWithin;
}

class SessionManagementFailure implements Exception {
  const SessionManagementFailure(
    this.message, {
    this.requiresRecentSignIn = false,
  });

  final String message;
  final bool requiresRecentSignIn;

  @override
  String toString() => message;
}

class SessionManagementService {
  SessionManagementService({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    @visibleForTesting CurrentSessionLoader? currentSessionLoader,
    @visibleForTesting RevokeSessionsCall? revokeSessionsCall,
  }) : _auth = auth,
       _functions = functions,
       _currentSessionLoader = currentSessionLoader,
       _revokeSessionsCall = revokeSessionsCall;

  final FirebaseAuth? _auth;
  final FirebaseFunctions? _functions;
  final CurrentSessionLoader? _currentSessionLoader;
  final RevokeSessionsCall? _revokeSessionsCall;

  FirebaseAuth get _resolvedAuth => _auth ?? FirebaseAuth.instance;
  FirebaseFunctions get _resolvedFunctions =>
      _functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  Future<CurrentSessionInfo> currentSession() async {
    final loader = _currentSessionLoader;
    if (loader != null) return loader();

    final user = _resolvedAuth.currentUser;
    if (user == null) {
      throw const SessionManagementFailure(
        'Your session has ended. Sign in again to manage devices.',
      );
    }

    final token = await user.getIdTokenResult();
    final providers = user.providerData
        .map((provider) => _providerLabel(provider.providerId))
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    return CurrentSessionInfo(
      signedInAt: token.authTime,
      providerLabels: providers,
    );
  }

  Future<RevokeSessionsResult> signOutEverywhere() async {
    try {
      final call = _revokeSessionsCall;
      final data = call != null
          ? await call()
          : Map<String, dynamic>.from(
              (await _resolvedFunctions
                          .httpsCallable('revokeMyRefreshTokens')
                          .call<Object?>())
                      .data
                  as Map,
            );
      if (data['revoked'] != true || data['completeWithinSeconds'] is! num) {
        throw const SessionManagementFailure(
          'YO Voice received an invalid session response. Try again.',
        );
      }
      final seconds = (data['completeWithinSeconds'] as num).toInt();
      if (seconds <= 0 || seconds > 24 * 60 * 60) {
        throw const SessionManagementFailure(
          'YO Voice received an invalid session response. Try again.',
        );
      }
      return RevokeSessionsResult(completeWithin: Duration(seconds: seconds));
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      final reason = details is Map ? details['reason'] : null;
      if (error.code == 'failed-precondition' &&
          reason == 'recent-authentication-required') {
        throw const SessionManagementFailure(
          'For security, sign out and sign in again before ending every session.',
          requiresRecentSignIn: true,
        );
      }
      if (error.code == 'unauthenticated') {
        throw const SessionManagementFailure(
          'Your session has ended. Sign in again to manage devices.',
        );
      }
      throw const SessionManagementFailure(
        'YO Voice could not sign out every device. Check your connection and try again.',
      );
    } on SessionManagementFailure {
      rethrow;
    } catch (_) {
      throw const SessionManagementFailure(
        'YO Voice could not sign out every device. Check your connection and try again.',
      );
    }
  }

  static String? _providerLabel(String providerId) => switch (providerId) {
    'password' => 'Email',
    'google.com' => 'Google',
    'apple.com' => 'Apple',
    'phone' => 'Phone',
    _ => null,
  };
}
