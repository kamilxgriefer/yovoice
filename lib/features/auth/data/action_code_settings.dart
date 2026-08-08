import 'package:firebase_auth/firebase_auth.dart';

/// The Flutter app has no deep-link handling of its own for auth action
/// codes (no Android/iOS package configured for it, no Dynamic Links —
/// those were shut down by Google in 2025), so every action link always
/// opens the website's own handler page regardless of which platform
/// initiated the request. See the website's action-code-settings.ts for
/// the mirrored web-side config — including a note on what
/// handleCodeInApp actually does (and doesn't do) for these codes,
/// confirmed by testing a real emailed link.
/// With the console's "customize action URL" pointed at
/// https://yovoice.app/auth/action (see docs/email-templates/README.md),
/// the emailed link itself opens the website's branded handler; the `url`
/// below rides along as `continueUrl` and is where the post-action
/// "Continue" affordance leads. It must be an authorized domain or
/// Firebase rejects the send.
///
/// handleCodeInApp stays false (the plugin's default is not relied on;
/// explicit here): true would signal the passwordless email-link sign-in
/// handoff, which does nothing for verify/reset codes — confirmed
/// empirically on the website side — and this app has no deep-link
/// handler for action codes anyway.
ActionCodeSettings verifyEmailActionCodeSettings() {
  return ActionCodeSettings(
    url: 'https://yovoice.app/verify-email',
    handleCodeInApp: false,
  );
}

ActionCodeSettings resetPasswordActionCodeSettings() {
  return ActionCodeSettings(
    url: 'https://yovoice.app/login',
    handleCodeInApp: false,
  );
}
