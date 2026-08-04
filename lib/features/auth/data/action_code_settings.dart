import 'package:firebase_auth/firebase_auth.dart';

/// The Flutter app has no deep-link handling of its own for auth action
/// codes (no Android/iOS package configured for it, no Dynamic Links —
/// those were shut down by Google in 2025), so every action link always
/// opens the website's own handler page regardless of which platform
/// initiated the request. See the website's action-code-settings.ts for
/// the mirrored web-side config — including a note on what
/// handleCodeInApp actually does (and doesn't do) for these codes,
/// confirmed by testing a real emailed link.
ActionCodeSettings verifyEmailActionCodeSettings() {
  return ActionCodeSettings(
    url: 'https://yovoice.app/verify-email',
    handleCodeInApp: true,
  );
}

ActionCodeSettings resetPasswordActionCodeSettings() {
  return ActionCodeSettings(
    url: 'https://yovoice.app/login',
    handleCodeInApp: true,
  );
}
