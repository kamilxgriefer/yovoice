import 'package:firebase_auth/firebase_auth.dart';

/// The Flutter app has no deep-link handling of its own for auth action
/// codes (no Android/iOS package configured for it, no Dynamic Links —
/// those were shut down by Google in 2025), so the verification link
/// always opens the website's own /verify-email handler regardless of
/// which platform the registration happened on. That page is what
/// actually applies the code; see the website's action-code-settings.ts
/// for the mirrored web-side config.
ActionCodeSettings verifyEmailActionCodeSettings() {
  return ActionCodeSettings(
    url: 'https://yovoice.app/verify-email',
    handleCodeInApp: true,
  );
}
