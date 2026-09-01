import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yovoice/core/helpers/error_messages.dart';

/// Regression suite for the P0 "raw Dart exception rendered to users"
/// class of bug: whatever a flow throws, the string that reaches the UI
/// must be human copy — never exception types, codes or interop noise.
void main() {
  test('intentional StateError copy is surfaced verbatim', () {
    expect(
      intentionalOrFriendly(
        StateError('You must be signed in to start a conversation.'),
      ),
      'You must be signed in to start a conversation.',
    );
  });

  test('intentional ArgumentError copy is surfaced without the prefix', () {
    expect(
      intentionalOrFriendly(ArgumentError('You cannot message yourself.')),
      'You cannot message yourself.',
    );
  });

  test('the exact web-interop wrapper the user saw maps to friendly copy', () {
    // This is the P0 report verbatim: Flutter Web boxes Firestore JS
    // errors into this Exception text.
    final error = Exception(
      'Dart exception thrown from converted Future. Use the properties '
      "'error' to fetch the boxed error and 'stack' to recover the stack "
      'trace.',
    );
    final message = intentionalOrFriendly(
      error,
      fallback: "Couldn't open this chat. Please try again.",
    );
    expect(message, "Couldn't open this chat. Please try again.");
    expect(message, isNot(contains('Dart exception')));
    expect(message, isNot(contains('Exception')));
  });

  test('FirebaseException codes map to actionable copy, never the code', () {
    final permissionDenied = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'PERMISSION_DENIED: false for update @ L201',
    );
    final message = intentionalOrFriendly(permissionDenied);
    expect(message, "You don't have permission to do that.");
    expect(message, isNot(contains('cloud_firestore')));
    expect(message, isNot(contains('PERMISSION_DENIED')));

    expect(
      intentionalOrFriendly(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      ),
      'This is taking longer than expected. Please try again.',
    );
  });

  test('unknown errors fall back to safe copy with no internals', () {
    final message = intentionalOrFriendly(
      Exception('NoSuchMethodError: _TypeError at frame 7'),
    );
    expect(message, 'Something went wrong. Please try again.');
    expect(message.toLowerCase(), isNot(contains('error')));
  });

  test('privileged authentication failures explain the safe next step', () {
    expect(
      friendlyErrorMessage(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'private backend detail',
          details: const <String, Object?>{
            'reason': 'recent-authentication-required',
          },
        ),
      ),
      'For security, sign in again before this sensitive action.',
    );
    expect(
      friendlyErrorMessage(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'private backend detail',
          details: const <String, Object?>{
            'reason': 'multi-factor-authentication-required',
          },
        ),
      ),
      'Sign in with two-factor authentication before this sensitive action.',
    );
  });
}
