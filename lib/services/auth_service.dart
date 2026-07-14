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
        'Wystąpił nieoczekiwany błąd podczas logowania.',
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
          'Nie udało się utworzyć konta użytkownika.',
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

      throw const AuthServiceException(
        'Nie udało się utworzyć profilu użytkownika.',
      );
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException {
      rethrow;
    } catch (_) {
      throw const AuthServiceException(
        'Nie udało się wysłać wiadomości resetującej hasło.',
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
      return 'Wystąpił nieoczekiwany błąd.';
    }

    switch (error.code) {
      case 'invalid-email':
        return 'Adres e-mail jest nieprawidłowy.';
      case 'user-disabled':
        return 'To konto zostało zablokowane.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Nieprawidłowy e-mail lub hasło.';
      case 'email-already-in-use':
        return 'Konto z tym adresem e-mail już istnieje.';
      case 'weak-password':
        return 'Hasło jest zbyt słabe.';
      case 'too-many-requests':
        return 'Zbyt wiele prób. Spróbuj ponownie później.';
      case 'network-request-failed':
        return 'Brak połączenia z internetem.';
      case 'operation-not-allowed':
        return 'Ta metoda logowania nie została włączona w Firebase.';
      default:
        return error.message ?? 'Wystąpił błąd Firebase.';
    }
  }
}

class AuthServiceException implements Exception {
  const AuthServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
