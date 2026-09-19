import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// How this account proves, right now, that it is still the person holding the
/// device — the client half of `requireRecentPrivilegedAuthentication`
/// (`functions/utils/auth.js`), which refuses any sign-in older than five
/// minutes for a destructive action.
enum ReauthenticationMethod {
  google,
  apple,
  password,

  /// The account has a provider this app cannot re-challenge in place (a
  /// federated link with no password and no supported popup). Signing out and
  /// signing in again is the only honest route, and the copy must say so.
  unavailable,
}

/// The single provider-selection rule, shared by every caller that needs a
/// fresh sign-in. Google first, then Apple, then a password — the order the
/// two-factor screen has always used.
ReauthenticationMethod reauthenticationMethodFor(Iterable<String> providerIds) {
  final providers = providerIds.toSet();
  if (providers.contains(GoogleAuthProvider.PROVIDER_ID)) {
    return ReauthenticationMethod.google;
  }
  if (providers.contains(AppleAuthProvider.PROVIDER_ID)) {
    return ReauthenticationMethod.apple;
  }
  if (providers.contains(EmailAuthProvider.PROVIDER_ID)) {
    return ReauthenticationMethod.password;
  }
  return ReauthenticationMethod.unavailable;
}

/// The re-authentication surface, as its callers see it. One implementation
/// backs both the two-factor screen and account deletion, so a provider that
/// works in one works in the other.
abstract interface class ReauthenticationClient {
  List<String> get providerIds;
  Future<void> reauthenticateWithPassword(String password);
  Future<void> reauthenticateWithGoogle();
  Future<void> reauthenticateWithApple();
}

extension ReauthenticationClientMethod on ReauthenticationClient {
  ReauthenticationMethod get method => reauthenticationMethodFor(providerIds);
}

class ReauthenticationService implements ReauthenticationClient {
  ReauthenticationService({
    FirebaseAuth? firebaseAuth,
    String signedOutMessage = 'You must be signed in to continue.',
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _signedOutMessage = signedOutMessage;

  final FirebaseAuth _firebaseAuth;

  /// Kept per-caller so a surface that already had its own wording — the
  /// two-factor screen — does not silently change the message it throws.
  final String _signedOutMessage;

  User get _requiredUser {
    final user = _firebaseAuth.currentUser;
    if (user == null) throw StateError(_signedOutMessage);
    return user;
  }

  @override
  List<String> get providerIds => _requiredUser.providerData
      .map((provider) => provider.providerId)
      .toSet()
      .toList(growable: false);

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    final user = _requiredUser;
    final email = user.email?.trim();
    if (email == null || email.isEmpty) {
      throw StateError('This account does not have an email password.');
    }
    if (password.isEmpty) {
      throw const FormatException('Enter your password.');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  @override
  Future<void> reauthenticateWithGoogle() async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    if (kIsWeb) {
      await _requiredUser.reauthenticateWithPopup(provider);
    } else {
      await _requiredUser.reauthenticateWithProvider(provider);
    }
  }

  @override
  Future<void> reauthenticateWithApple() async {
    final provider = AppleAuthProvider();
    if (kIsWeb) {
      await _requiredUser.reauthenticateWithPopup(provider);
    } else {
      await _requiredUser.reauthenticateWithProvider(provider);
    }
  }
}
