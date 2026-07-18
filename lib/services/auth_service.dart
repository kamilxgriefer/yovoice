import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';
import 'firestore_service.dart';

class AuthService {
  AuthService({FirebaseAuth? firebaseAuth, FirestoreService? firestoreService})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _firestoreService = firestoreService ?? FirestoreService();

  final FirebaseAuth _firebaseAuth;
  final FirestoreService _firestoreService;

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

      return credential;
    } on FirebaseAuthException {
      rethrow;
    } catch (error) {
      if (credential?.user != null) {
        await credential!.user!.delete();
      }

      if (error is AuthServiceException) {
        rethrow;
      }

      throw const AuthServiceException('Unable to create the user profile.');
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException {
      rethrow;
    } catch (_) {
      throw const AuthServiceException(
        'Unable to send the password reset email.',
      );
    }
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
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
