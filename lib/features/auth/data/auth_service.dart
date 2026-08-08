import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:yovoice/features/auth/data/action_code_settings.dart';
import 'package:yovoice/features/profile/data/services/profile_service.dart';
import 'package:yovoice/shared/models/app_user.dart';
import 'package:yovoice/services/firestore_service.dart';

class AuthService {
  AuthService({FirebaseAuth? firebaseAuth, FirestoreService? firestoreService})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _firestoreService = firestoreService ?? FirestoreService();

  final FirebaseAuth _firebaseAuth;
  final FirestoreService _firestoreService;

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  Future<void>? _googleSignInInitialization;

  User? get currentUser => _firebaseAuth.currentUser;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

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

      await _createSocialUserProfileIfNeeded(credential);

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

  Future<void> signOut() async {
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
      // Drop the cached current-profile stream so the next account never
      // inherits the previous user's replayed snapshot.
      ProfileService.resetCurrentProfileCache();
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
    UserCredential credential,
  ) async {
    final isNewUser = credential.additionalUserInfo?.isNewUser ?? false;

    if (!isNewUser) {
      return;
    }

    final user = credential.user;

    if (user == null) {
      throw const AuthServiceException(
        'Unable to retrieve the signed-in Google user.',
      );
    }

    final email = user.email?.trim();

    if (email == null || email.isEmpty) {
      throw const AuthServiceException(
        'Google did not provide an email address.',
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
    } catch (_) {
      try {
        await user.delete();
      } catch (_) {
        await _firebaseAuth.signOut();
      }

      throw const AuthServiceException(
        'Google account was authenticated, but the user profile could not be created.',
      );
    }
  }

  String _resolveUsername(User user) {
    final displayName = user.displayName?.trim();

    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final email = user.email?.trim();

    if (email != null && email.contains('@')) {
      final emailUsername = email.split('@').first.trim();

      if (emailUsername.isNotEmpty) {
        return emailUsername;
      }
    }

    return 'YO Voice User';
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
        return 'The browser blocked the Google Sign-In window. Allow pop-ups and try again.';

      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return 'Google Sign-In was cancelled.';

      case 'unauthorized-domain':
        return 'This website domain is not authorized in Firebase Authentication.';

      default:
        return error.message ?? 'Firebase authentication error.';
    }
  }
}

class AuthServiceException implements Exception {
  const AuthServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
