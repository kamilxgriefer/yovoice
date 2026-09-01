import 'package:cloud_functions/cloud_functions.dart';

/// Maps a raw exception to copy that's safe and useful to show a user.
///
/// Screens should never interpolate `error.toString()` directly into UI —
/// it leaks internal exception types/stack fragments and rarely explains
/// what to do next. This centralizes the mapping so every error state in
/// the app reads consistently instead of each screen re-guessing.
String friendlyErrorMessage(Object error, {String? fallback}) {
  if (error is FirebaseFunctionsException) {
    final details = error.details;
    final reason = details is Map ? details['reason'] : null;
    if (reason == 'recent-authentication-required') {
      return 'For security, sign in again before this sensitive action.';
    }
    if (reason == 'multi-factor-authentication-required') {
      return 'Sign in with two-factor authentication before this sensitive action.';
    }
  }
  final String raw = error.toString().toLowerCase();

  if (raw.contains('permission-denied') || raw.contains('permission_denied')) {
    return "You don't have permission to do that.";
  }
  if (raw.contains('not-found') || raw.contains('not_found')) {
    return "We couldn't find that — it may have been removed.";
  }
  if (raw.contains('unavailable') || raw.contains('deadline-exceeded')) {
    return 'This is taking longer than expected. Please try again.';
  }
  if (raw.contains('network') ||
      raw.contains('socketexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('connection')) {
    return 'Check your connection and try again.';
  }
  if (raw.contains('unauthenticated') ||
      raw.contains('requires-recent-login')) {
    return 'Please sign in again to continue.';
  }
  if (raw.contains('already-exists')) {
    return 'That already exists.';
  }
  if (raw.contains('resource-exhausted') || raw.contains('quota')) {
    return "We're a little overloaded right now — please try again shortly.";
  }
  if (raw.contains('cancelled')) {
    return 'That was cancelled.';
  }

  return fallback ?? 'Something went wrong. Please try again.';
}

/// For flows that throw INTENTIONAL user-facing copy via StateError /
/// ArgumentError (e.g. "You must be signed in to start a conversation."),
/// surfaces that copy; everything else — FirebaseException, boxed JS
/// interop errors ("Dart exception thrown from converted Future..."),
/// unexpected internals — is mapped through [friendlyErrorMessage] so raw
/// exception text can never reach the UI.
String intentionalOrFriendly(Object error, {String? fallback}) {
  if (error is StateError) {
    return error.message;
  }
  if (error is ArgumentError && error.message is String) {
    final message = error.message as String;
    if (message.isNotEmpty) return message;
  }
  return friendlyErrorMessage(error, fallback: fallback);
}
