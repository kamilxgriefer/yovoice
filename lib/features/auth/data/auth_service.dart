import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'package:yovoice/core/presence/presence_service.dart';
import 'package:yovoice/features/auth/data/action_code_settings.dart';
import 'package:yovoice/features/auth/data/auth_profile_identity.dart';
import 'package:yovoice/features/auth/data/totp_mfa_service.dart';
import 'package:yovoice/features/notifications/data/services/push_notification_service.dart';
import 'package:yovoice/features/premium/data/services/entitlement_service.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/models/app_user.dart';
import 'package:yovoice/services/firestore_service.dart';

enum AppleSignInAvailability {
  available,
  notConfigured,
  temporarilyUnavailable,
}

typedef AppleProviderProbe = Future<AppleSignInAvailability> Function();

/// Removes this device's FCM token registration. Injectable so the
/// sign-out ordering can be asserted without a live Firebase Messaging.
typedef DeviceTokenUnregister = Future<void> Function();

class AuthService {
  AuthService({
    FirebaseAuth? firebaseAuth,
    FirestoreService? firestoreService,
    @visibleForTesting bool? appleSignInFeatureEnabled,
    @visibleForTesting bool? appleUseWebPopup,
    @visibleForTesting AppleProviderProbe? appleProviderProbe,
    @visibleForTesting PresenceService? presenceService,
    @visibleForTesting DeviceTokenUnregister? unregisterDeviceToken,
    @visibleForTesting
    Duration bestEffortCleanupTimeout = const Duration(seconds: 10),
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firestoreService = firestoreService ?? FirestoreService(),
       _injectedPresenceService = presenceService,
       _injectedUnregisterDeviceToken = unregisterDeviceToken,
       _bestEffortCleanupTimeout = bestEffortCleanupTimeout,
       _appleSignInFeatureEnabled =
           appleSignInFeatureEnabled ??
           const bool.fromEnvironment(
             'YOVOICE_APPLE_SIGN_IN_ENABLED',
             defaultValue: true,
           ),
       _appleUseWebPopup = appleUseWebPopup,
       _appleProviderProbe = appleProviderProbe;

  final FirebaseAuth _firebaseAuth;
  final FirestoreService _firestoreService;
  final bool _appleSignInFeatureEnabled;
  final bool? _appleUseWebPopup;
  final AppleProviderProbe? _appleProviderProbe;

  // Resolved lazily, inside signOut() only. Building the production
  // PresenceService or touching PushNotificationService.instance eagerly in
  // the constructor would reach FirebaseAuth/Firestore/Messaging singletons
  // every time an AuthService is constructed — including in widget tests
  // that never sign out.
  final PresenceService? _injectedPresenceService;
  final DeviceTokenUnregister? _injectedUnregisterDeviceToken;
  final Duration _bestEffortCleanupTimeout;

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  Future<void>? _googleSignInInitialization;
  Future<AppleSignInAvailability>? _appleSignInAvailability;

  User? get currentUser => _firebaseAuth.currentUser;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  TotpSignInChallenge createTotpSignInChallenge(
    FirebaseAuthMultiFactorException exception,
  ) => TotpSignInChallenge(exception.resolver);

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException {
      rethrow;
    } catch (_) {
      throw const AuthServiceException(
        'An unexpected error occurred while signing in.',
      );
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      UserCredential credential;

      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider();

        googleProvider.setCustomParameters({'prompt': 'select_account'});

        credential = await _firebaseAuth.signInWithPopup(googleProvider);
      } else {
        await _initializeGoogleSignIn();

        if (!_googleSignIn.supportsAuthenticate()) {
          throw const AuthServiceException(
            'Google Sign-In is not supported on this platform.',
          );
        }

        final googleUser = await _googleSignIn.authenticate();
        final googleAuthentication = googleUser.authentication;
        final idToken = googleAuthentication.idToken;

        if (idToken == null || idToken.isEmpty) {
          throw const AuthServiceException(
            'Google did not return a valid authentication token.',
          );
        }

        final googleCredential = GoogleAuthProvider.credential(
          idToken: idToken,
        );

        credential = await _firebaseAuth.signInWithCredential(googleCredential);
      }

      await _createSocialUserProfileIfNeeded(
        credential,
        providerName: 'Google',
      );

      return credential;
    } on GoogleSignInException catch (error) {
      switch (error.code) {
        case GoogleSignInExceptionCode.canceled:
          throw const AuthServiceException('Google Sign-In was cancelled.');

        case GoogleSignInExceptionCode.interrupted:
          throw const AuthServiceException(
            'Google Sign-In was interrupted. Please try again.',
          );

        case GoogleSignInExceptionCode.clientConfigurationError:
          throw AuthServiceException(
            error.description ?? 'Google Sign-In is not configured correctly.',
          );

        case GoogleSignInExceptionCode.providerConfigurationError:
          throw AuthServiceException(
            error.description ??
                'Google authentication provider is unavailable.',
          );

        case GoogleSignInExceptionCode.uiUnavailable:
          throw const AuthServiceException(
            'Google Sign-In window could not be opened.',
          );

        default:
          throw AuthServiceException(
            error.description ?? 'An unexpected Google Sign-In error occurred.',
          );
      }
    } on FirebaseAuthException {
      rethrow;
    } on AuthServiceException {
      rethrow;
    } catch (_) {
      throw const AuthServiceException(
        'An unexpected error occurred during Google Sign-In.',
      );
    }
  }

  /// Returns whether Firebase's production configuration can start an Apple
  /// OAuth flow. The build flag is intentionally necessary as well: enabling
  /// the provider in the Firebase console before the Apple Service ID,
  /// signing capability and release profile are ready must not expose a
  /// half-configured button to users. Every shipped target is configured and
  /// therefore defaults on; an unconfigured build must explicitly set the
  /// compile-time flag to false.
  Future<AppleSignInAvailability> getAppleSignInAvailability() async {
    if (!_appleSignInFeatureEnabled) {
      return AppleSignInAvailability.notConfigured;
    }

    final probe = _appleSignInAvailability ??= _probeAppleProvider();

    try {
      final availability = await probe;
      if (availability == AppleSignInAvailability.temporarilyUnavailable &&
          identical(_appleSignInAvailability, probe)) {
        // A timeout/offline result is not configuration state. Do not make a
        // transient network failure disable Apple until the screen is rebuilt;
        // the next tap can probe again and continue immediately.
        _appleSignInAvailability = null;
      }
      return availability;
    } catch (_) {
      if (identical(_appleSignInAvailability, probe)) {
        _appleSignInAvailability = null;
      }
      rethrow;
    }
  }

  Future<UserCredential> signInWithApple() async {
    final availability = await getAppleSignInAvailability();
    if (availability != AppleSignInAvailability.available) {
      throw const AuthServiceException(
        'Apple Sign-In is not available right now.',
      );
    }

    try {
      final appleProvider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');

      final useWebPopup = _appleUseWebPopup ?? kIsWeb;
      final credential = useWebPopup
          ? await _firebaseAuth.signInWithPopup(appleProvider)
          : await _firebaseAuth.signInWithProvider(appleProvider);

      await _createSocialUserProfileIfNeeded(credential, providerName: 'Apple');

      return credential;
    } on FirebaseAuthException {
      rethrow;
    } on AuthServiceException {
      rethrow;
    } catch (_) {
      throw const AuthServiceException(
        'An unexpected error occurred during Apple Sign-In.',
      );
    }
  }

  Future<UserCredential> register({
    required String email,
    required String password,
    required String username,
  }) async {
    UserCredential? credential;

    try {
      credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        throw const AuthServiceException(
          'Unable to create a new user account.',
        );
      }

      await user.updateDisplayName(username.trim());

      final appUser = AppUser(
        uid: user.uid,
        email: email.trim(),
        username: username.trim(),
        createdAt: DateTime.now(),
      );

      await _firestoreService.createUserProfile(appUser);

      try {
        await user.sendEmailVerification(verifyEmailActionCodeSettings());
      } catch (_) {
        // The account and profile already exist at this point — a failed
        // verification send shouldn't undo registration. The verify-email
        // screen's resend button covers this case.
      }

      return credential;
    } on FirebaseAuthException {
      rethrow;
    } catch (error) {
      if (credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {
          // The account may already have been removed or the session expired.
        }
      }

      if (error is AuthServiceException) {
        rethrow;
      }

      throw const AuthServiceException('Unable to create the user profile.');
    }
  }

  Future<void> resendVerificationEmail() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw const AuthServiceException('You must be signed in to do that.');
    }

    try {
      await user.sendEmailVerification(verifyEmailActionCodeSettings());
    } on FirebaseAuthException {
      rethrow;
    } catch (_) {
      throw const AuthServiceException(
        'Unable to send the verification email.',
      );
    }
  }

  /// Forces a fresh emailVerified read from Firebase. The cached [User]
  /// object never updates emailVerified on its own — reload() is the only
  /// way to learn a link opened elsewhere (another tab, another device)
  /// was actually applied.
  Future<bool> reloadCurrentUser() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _firebaseAuth.currentUser?.emailVerified ?? false;
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(
        email: email.trim(),
        actionCodeSettings: resetPasswordActionCodeSettings(),
      );
    } on FirebaseAuthException {
      rethrow;
    } catch (_) {
      throw const AuthServiceException(
        'Unable to send the password reset email.',
      );
    }
  }

  /// The single sign-out choke point for the whole app.
  ///
  /// Settings, Profile, the device-sessions screen, the 2FA
  /// expired-session path and [AuthController] all route through here, on
  /// purpose: signing out has to mean the same thing everywhere. Two pieces
  /// of cleanup are only *permitted* while the session is still live, so
  /// they run before [FirebaseAuth.signOut] rather than in reaction to it:
  ///
  ///  * **Presence.** `firestore.rules` gates `users/{uid}` updates on
  ///    `isSignedIn() && isOwner(uid)`. An offline write issued after the
  ///    session is cleared is denied, `socialPresence/{uid}` keeps
  ///    mirroring `isOnline: true`, and the account shows as Online to its
  ///    friends in DMs indefinitely.
  ///  * **This device's FCM token.** Deleting `fcmTokens/{token}` needs
  ///    `isOwner(uid)` for the same reason. A token left behind means the
  ///    previous account keeps receiving push on a shared device.
  ///
  /// Both are best-effort. A cleanup failure is reported and swallowed — it
  /// must never trap someone in a session they asked to leave.
  ///
  /// This covers sign-out, not process death: an app that is force-quit or
  /// whose refresh token is revoked server-side never reaches this code, and
  /// nothing on the client can write for a session that no longer exists.
  /// Expiring stale presence in that case needs a server-side sweeper over
  /// `presenceUpdatedAt`, which does not exist yet.
  Future<void> signOut() async {
    final userId = _firebaseAuth.currentUser?.uid;

    if (userId != null) {
      await Future.wait<void>([
        _unregisterDeviceTokenBestEffort(),
        _setOfflineBestEffort(userId),
      ]);
    }

    try {
      if (!kIsWeb) {
        try {
          await _initializeGoogleSignIn();
          await _googleSignIn.signOut();
        } catch (_) {
          // Firebase must still be signed out even when Google sign-out fails.
        }
      }
    } finally {
      await _firebaseAuth.signOut();
      // Drop the cached current-profile/entitlement streams so the next
      // account never inherits the previous user's replayed snapshots.
      ProfileService.resetCurrentProfileCache();
      EntitlementService.resetCache();
    }
  }

  Future<void> _unregisterDeviceTokenBestEffort() async {
    try {
      // Resolved inside the guard on purpose: reaching
      // PushNotificationService.instance builds the singleton, which touches
      // the FirebaseAuth and Messaging singletons.
      final unregister =
          _injectedUnregisterDeviceToken ??
          PushNotificationService.instance.unregisterCurrentDevice;
      await unregister().timeout(_bestEffortCleanupTimeout);
    } on TimeoutException {
      debugPrint(
        'AuthService.signOut: device-token cleanup exceeded the bounded '
        'window. Sign-out will continue; push identity remains epoch-blocked '
        'and the next binding must rotate its token.',
      );
    } catch (error) {
      debugPrint(
        'AuthService.signOut: could not unregister this device for push '
        '(${error.runtimeType}). The previous account may keep receiving '
        'push notifications here until the token is refreshed or '
        'invalidated.',
      );
    }
  }

  Future<void> _setOfflineBestEffort(String userId) async {
    try {
      await (_injectedPresenceService ?? PresenceService())
          .setOfflineForUser(userId)
          .timeout(_bestEffortCleanupTimeout);
    } on TimeoutException {
      debugPrint(
        'AuthService.signOut: presence cleanup exceeded the bounded window. '
        'Sign-out will continue; presence will converge on the next session.',
      );
    } catch (error) {
      debugPrint(
        'AuthService.signOut: could not mark the account offline '
        '(${error.runtimeType}). Friends may still see it as Online until '
        'the next sign-in sets presence again.',
      );
    }
  }

  Future<void> _initializeGoogleSignIn() async {
    final existingInitialization = _googleSignInInitialization;

    if (existingInitialization != null) {
      await existingInitialization;
      return;
    }

    final initialization = _googleSignIn.initialize();
    _googleSignInInitialization = initialization;

    try {
      await initialization;
    } catch (_) {
      _googleSignInInitialization = null;
      rethrow;
    }
  }

  Future<void> _createSocialUserProfileIfNeeded(
    UserCredential credential, {
    required String providerName,
  }) async {
    final isNewUser = credential.additionalUserInfo?.isNewUser ?? false;

    if (!isNewUser) {
      return;
    }

    final user = credential.user;

    if (user == null) {
      throw AuthServiceException(
        'Unable to retrieve the signed-in $providerName user.',
      );
    }

    final email = user.email?.trim();

    if (email == null || email.isEmpty) {
      throw AuthServiceException(
        '$providerName did not provide an email address.',
      );
    }

    final username = _resolveUsername(user);

    final appUser = AppUser(
      uid: user.uid,
      email: email,
      username: username,
      createdAt: DateTime.now(),
    );

    try {
      await _firestoreService.createUserProfile(appUser);
    } catch (error) {
      // Firebase publishes the authenticated user before this method returns.
      // A transient Firestore failure must therefore never roll a valid
      // Google/Apple session back to signed-out: that produced the visible
      // "login for one second, then back to Login" failure for both providers.
      // AuthGate owns the idempotent, retried profile bootstrap and does not
      // reveal MainShell until it succeeds.
      debugPrint(
        'AuthService: $providerName authentication succeeded; deferred '
        'profile bootstrap after ${error.runtimeType}.',
      );
    }
  }

  Future<AppleSignInAvailability> _probeAppleProvider() async {
    final injectedProbe = _appleProviderProbe;
    if (injectedProbe != null) {
      return injectedProbe();
    }

    try {
      final apiKey = Firebase.app().options.apiKey;
      if (apiKey.isEmpty) {
        return AppleSignInAvailability.temporarilyUnavailable;
      }

      final uri = Uri.https(
        'identitytoolkit.googleapis.com',
        '/v1/accounts:createAuthUri',
        {'key': apiKey},
      );
      final continueUri = kIsWeb && Uri.base.hasScheme
          ? Uri.base.origin
          : 'https://auth.yovoice.app';
      final response = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'providerId': AppleAuthProvider.PROVIDER_ID,
              'continueUri': continueUri,
            }),
          )
          .timeout(const Duration(seconds: 6));

      return parseAppleProviderProbeResponse(
        response.statusCode,
        response.body,
      );
    } catch (_) {
      // Availability is a fail-closed UI gate. Network and malformed-response
      // failures must never turn the sign-in button on optimistically.
      return AppleSignInAvailability.temporarilyUnavailable;
    }
  }

  String _resolveUsername(User user) {
    return resolveAuthProfileName(
      displayName: user.displayName,
      email: user.email,
    );
  }

  String getErrorMessage(Object error) {
    if (error is AuthServiceException) {
      return error.message;
    }

    if (error is! FirebaseAuthException) {
      return 'An unexpected error occurred.';
    }

    switch (error.code) {
      case 'invalid-email':
        return 'The email address is invalid.';

      case 'user-disabled':
        return 'This account has been disabled.';

      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';

      case 'email-already-in-use':
        return 'An account with this email already exists.';

      case 'weak-password':
        return 'The password is too weak.';

      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';

      case 'network-request-failed':
        return 'No internet connection.';

      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';

      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using another sign-in method.';

      case 'popup-blocked':
        return 'The browser blocked the sign-in window. Allow pop-ups and try again.';

      case 'canceled':
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return 'Sign-in was cancelled.';

      case 'unauthorized-domain':
        return 'This website domain is not authorized in Firebase Authentication.';

      default:
        return error.message ?? 'Firebase authentication error.';
    }
  }
}

@visibleForTesting
AppleSignInAvailability parseAppleProviderProbeResponse(
  int statusCode,
  String responseBody,
) {
  try {
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      return AppleSignInAvailability.temporarilyUnavailable;
    }

    if (statusCode == 200) {
      final authUri = Uri.tryParse(decoded['authUri'] as String? ?? '');
      final providerId = decoded['providerId'];
      final isAppleAuthorization =
          authUri != null &&
          authUri.scheme == 'https' &&
          authUri.host == 'appleid.apple.com' &&
          providerId == AppleAuthProvider.PROVIDER_ID;

      return isAppleAuthorization
          ? AppleSignInAvailability.available
          : AppleSignInAvailability.temporarilyUnavailable;
    }

    final error = decoded['error'];
    final message = error is Map<String, dynamic>
        ? error['message'] as String? ?? ''
        : '';
    if (statusCode == 400 && message.startsWith('OPERATION_NOT_ALLOWED')) {
      return AppleSignInAvailability.notConfigured;
    }
  } catch (_) {
    // Parsed below as unavailable.
  }

  return AppleSignInAvailability.temporarilyUnavailable;
}

class AuthServiceException implements Exception {
  const AuthServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
