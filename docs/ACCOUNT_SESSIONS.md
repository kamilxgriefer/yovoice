# Account session management

YO Voice deliberately exposes only the session actions Firebase
Authentication can enforce truthfully.

**Release status (2026-08-18): implemented and tested in source, not yet
deployed.** The architectural boundary is recorded in
[ADR-073](Decisions.md#adr-073-firebase-session-management-exposes-account-wide-revocation-never-a-fabricated-device-list).

## Supported contract

- The Settings screen can show the current Firebase token session: the local
  platform, authentication provider and the token's `auth_time`.
- `revokeMyRefreshTokens` revokes **all** refresh tokens for the authenticated
  caller. The callable accepts no UID or other client-selected target.
- The caller must have authenticated within the previous ten minutes. This is
  derived from Firebase's verified `auth_time` claim, not device time.
- Banned, disabled or otherwise restricted profile state does not prevent the
  owner from using this security/recovery action.
- After the server confirms revocation, the client unregisters its current FCM
  token and signs out locally.

## Firebase limitation: no per-device revoke

Firebase Authentication's Admin SDK exposes account-wide
`revokeRefreshTokens(uid)`. It does not expose a list of individual mobile/web
refresh-token sessions and cannot revoke one refresh token by device. FCM push
tokens are device registrations, not authentication sessions, and must never be
presented as if deleting one signed the device out.

Already-issued Firebase ID tokens are stateless and can remain usable until
their normal expiry, at most about one hour. The interface states this window
instead of promising immediate eviction.

A real single-device revoke would require a different authentication authority:
every Firebase token would need a server-issued session identifier and every
Firestore, Storage and callable authorization boundary would need to reject a
revoked identifier. Adding a cosmetic device document without that enforcement
is specifically out of scope because it would create a false security control.

Reference: Firebase, [Manage User Sessions](https://firebase.google.com/docs/auth/admin/manage-sessions).

## Verification

- `node --test functions/test/session_management.test.js`
- `flutter test test/session_management_test.dart`
- `flutter analyze lib/features/settings/data/services/session_management_service.dart lib/features/settings/presentation/screens/device_sessions_screen.dart test/session_management_test.dart`

The Node suite covers authentication, opaque UIDs, recovery for restricted
accounts, exact input validation, recent-auth boundaries and Admin SDK error
redaction. Flutter tests cover response validation, the honest current-session
state, confirmation sequencing, error rendering and narrow-phone layout.
