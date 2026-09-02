import 'package:cloud_functions/cloud_functions.dart';

import 'package:yovoice/core/localization/app_localizations.dart';

/// Maps a raw exception to copy that's safe and useful to show a user.
///
/// Screens should never interpolate `error.toString()` directly into UI —
/// it leaks internal exception types/stack fragments and rarely explains
/// what to do next. This centralizes the mapping so every error state in
/// the app reads consistently instead of each screen re-guessing.
///
/// Pass the active [copy] to localize built-in messages. An explicit
/// [fallback] is treated as caller-owned, already-localized presentation copy.
String friendlyErrorMessage(
  Object error, {
  String? fallback,
  AppLocalizations? copy,
}) {
  String localized(String english, String polish) =>
      copy?.text(english, polish) ?? english;

  if (error is FirebaseFunctionsException) {
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    if (reason == 'recent-authentication-required') {
      return localized(
        'For security, sign in again before this sensitive action.',
        'Ze względów bezpieczeństwa zaloguj się ponownie przed wykonaniem tej chronionej operacji.',
      );
    }
    if (reason == 'multi-factor-authentication-required') {
      return localized(
        'Sign in with two-factor authentication before this sensitive action.',
        'Zaloguj się z użyciem uwierzytelniania dwuskładnikowego przed wykonaniem tej chronionej operacji.',
      );
    }
  }
  final String raw = error.toString().toLowerCase();

  if (raw.contains('permission-denied') || raw.contains('permission_denied')) {
    return localized(
      "You don't have permission to do that.",
      'Nie masz uprawnień, aby to zrobić.',
    );
  }
  if (raw.contains('not-found') || raw.contains('not_found')) {
    return localized(
      "We couldn't find that — it may have been removed.",
      'Nie udało się tego znaleźć — element mógł zostać usunięty.',
    );
  }
  if (raw.contains('unavailable') || raw.contains('deadline-exceeded')) {
    return localized(
      'This is taking longer than expected. Please try again.',
      'To trwa dłużej, niż oczekiwano. Spróbuj ponownie.',
    );
  }
  if (raw.contains('network') ||
      raw.contains('socketexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('connection')) {
    return localized(
      'Check your connection and try again.',
      'Sprawdź połączenie z internetem i spróbuj ponownie.',
    );
  }
  if (raw.contains('unauthenticated') ||
      raw.contains('requires-recent-login')) {
    return localized(
      'Please sign in again to continue.',
      'Zaloguj się ponownie, aby kontynuować.',
    );
  }
  if (raw.contains('already-exists')) {
    return localized('That already exists.', 'To już istnieje.');
  }
  if (raw.contains('resource-exhausted') || raw.contains('quota')) {
    return localized(
      "We're a little overloaded right now — please try again shortly.",
      'Usługa jest teraz przeciążona — spróbuj ponownie za chwilę.',
    );
  }
  if (raw.contains('cancelled')) {
    return localized('That was cancelled.', 'Anulowano.');
  }

  return fallback ??
      localized(
        'Something went wrong. Please try again.',
        'Coś poszło nie tak. Spróbuj ponownie.',
      );
}

/// For flows that throw INTENTIONAL user-facing copy via StateError /
/// ArgumentError (e.g. "You must be signed in to start a conversation."),
/// surfaces that copy; everything else — FirebaseException, boxed JS
/// interop errors ("Dart exception thrown from converted Future..."),
/// unexpected internals — is mapped through [friendlyErrorMessage] so raw
/// exception text can never reach the UI.
///
/// Intentional messages are caller-owned copy and are returned unchanged;
/// built-in mappings use [copy] when supplied.
String intentionalOrFriendly(
  Object error, {
  String? fallback,
  AppLocalizations? copy,
}) {
  if (error is StateError) {
    return error.message;
  }
  if (error is ArgumentError && error.message is String) {
    final message = error.message as String;
    if (message.isNotEmpty) return message;
  }
  return friendlyErrorMessage(error, fallback: fallback, copy: copy);
}
