import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import 'package:yovoice/core/localization/app_localizations.dart';
import 'package:yovoice/features/auth/data/auth_service.dart';

/// Converts authentication failures shown by the auth presentation layer into
/// user-facing copy. Firebase's raw message is never exposed in Polish; unknown
/// failures deliberately fall back to a safe, actionable message.
String localizedAuthError(
  BuildContext context,
  Object error, {
  AuthService? authService,
}) {
  final copy = AppLocalizations.of(context);

  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-email' => copy.text(
        'The email address is invalid.',
        'Adres e-mail jest nieprawidłowy.',
      ),
      'user-disabled' => copy.text(
        'This account has been disabled.',
        'To konto zostało wyłączone.',
      ),
      'user-not-found' || 'wrong-password' || 'invalid-credential' => copy.text(
        'Incorrect email or password.',
        'Nieprawidłowy adres e-mail lub hasło.',
      ),
      'email-already-in-use' => copy.text(
        'An account with this email already exists.',
        'Konto z tym adresem e-mail już istnieje.',
      ),
      'weak-password' => copy.text(
        'The password is too weak.',
        'Hasło jest zbyt słabe.',
      ),
      'too-many-requests' => copy.text(
        'Too many attempts. Please try again later.',
        'Zbyt wiele prób. Spróbuj ponownie później.',
      ),
      'network-request-failed' => copy.text(
        'No internet connection.',
        'Brak połączenia z internetem.',
      ),
      'operation-not-allowed' => copy.text(
        'This sign-in method is not enabled.',
        'Ta metoda logowania nie jest włączona.',
      ),
      _ => copy.text(
        'Authentication could not be completed. Try again.',
        'Nie udało się ukończyć uwierzytelniania. Spróbuj ponownie.',
      ),
    };
  }

  final english = authService?.getErrorMessage(error);
  if (!copy.isPolish && english != null && english.trim().isNotEmpty) {
    return english;
  }
  return copy.text(
    'Authentication could not be completed. Try again.',
    'Nie udało się ukończyć uwierzytelniania. Spróbuj ponownie.',
  );
}
