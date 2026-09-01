# Privileged authentication hardening

Status: implemented in source, not deployed.

No application can honestly guarantee that an attacker will never gain
access. This control reduces the useful lifetime and authority of a stolen
Firebase ID token for staff and owner mutations. It complements — and does
not replace — protected-owner UID checks, signed role claims, server role
mirrors, account restrictions, App Check, endpoint rate limits where present
and audit monitoring.

## Enforced now

Every destructive callable under `functions/admin` and `functions/staff`
requires all of the following before its first business write:

1. a Firebase-authenticated request;
2. a signed staff role claim matching `users/{uid}.role`;
3. an active, non-banned, non-disabled and non-deleted account;
4. for owner-only actions, an exact match with
   `YOVOICE_PROTECTED_OWNER_UID`;
5. `auth_time` no more than five minutes old.

The last condition deliberately uses Firebase's reserved `auth_time` claim,
not `iat`: automatic ID-token refresh changes `iat` without proving that the
human signed in again. This follows Firebase's documented decoded-token
semantics and its own five-minute recent-sign-in example:

- <https://firebase.google.com/docs/reference/admin/node/firebase-admin.auth.decodedidtoken>
- <https://firebase.google.com/docs/auth/admin/manage-cookies>

Missing, malformed, future and stale values fail with:

```text
failed-precondition / recent-authentication-required
```

This guard covers owner bootstrap, role assignment, account sanctions and
bans, report resolution, manual Premium grants, room/Club moderation,
participant removal/muting, ownership transfer, canonical-data migration
apply operations, message deletion and permanent room/Club deletion. Migration
scans/dry-runs and read-only staff listing do not force a new sign-in every
five minutes.

Club ownership transfer is additionally restricted to the protected owner.
A claim and Firestore mirror both saying `superAdmin` are no longer sufficient
for that operation.

The obsolete `functions/admin/apply-storage-cors.js` one-shot HTTP function
was removed. It was not exported by `functions/index.js`, but its source still
described an unauthenticated administrative mutation and could have been
accidentally reintroduced. Before release, compare the deployed Functions
inventory with `functions/index.js`; if a historical `applyStorageCors`
deployment exists, delete that deployed function explicitly because removing
source does not remove an already deployed Cloud Function.

## MFA release gate

The guard understands Firebase's reserved
`firebase.sign_in_second_factor` claim. Its deployment mode is selected only
from server configuration:

```text
YOVOICE_PRIVILEGED_MFA_MODE=optional  # rollout default
YOVOICE_PRIVILEGED_MFA_MODE=required  # fail closed without MFA sign-in
```

An unset value is `optional`. Any other value is a configuration error and
fails closed. In `required` mode, missing or malformed proof returns:

```text
failed-precondition / multi-factor-authentication-required
```

`optional` is intentional only for the migration window: it prevents locking
out staff before every privileged account has enrolled and the deployed client
can guide reauthentication. It is not the final desired production posture.

Before changing production to `required`:

1. confirm TOTP MFA is enabled for the production Firebase/Identity Platform
   project;
2. verify every owner, moderator and super moderator has enrolled a factor;
3. verify every supported client can handle the two explicit error reasons,
   reauthenticate, finish the MFA challenge and safely retry once;
4. test owner recovery with a second, offline recovery procedure — never by
   creating another in-app super administrator;
5. enable `required` in a canary environment, run role change, ban, delete,
   transfer and moderation tests, then roll it out to all Functions instances;
6. alert on repeated `recent-authentication-required`,
   `multi-factor-authentication-required` and
   `security_alert_non_owner_super_admin` events.

The source change does not set production environment variables and does not
deploy Functions. Until the release gate above is completed, recent sign-in is
enforced but MFA remains a documented open control.

## Remaining production gates

- Several privileged callable declarations still use `enforceAppCheck: false`.
  Do not flip these piecemeal: first verify App Check/attestation on every
  supported tester client, then enable enforcement for the whole privileged
  surface and monitor rejection metrics. Until then, Auth, live role mirrors,
  recent sign-in and owner binding remain the effective server gates.
- Not every privileged mutation has a dedicated per-actor rate limiter.
  Add conservative, server-time quotas for role changes, sanctions, report
  actions and permanent deletion before a public production launch. Idempotency
  keys and audit logs do not by themselves prevent intentional abuse.
- Reauthentication must be a first-class client flow. Showing the raw
  `failed-precondition` error or asking staff to sign out manually is not an
  acceptable final UX and risks operational workarounds.
- Review the deployed Functions inventory during every release; an old remote
  function remains callable until explicitly deleted even after its export or
  source file disappears.

## Verification

- Unit tests cover the exact five-minute boundary, stale/future/malformed
  `auth_time`, refreshed `iat`, missing/malformed MFA proof and invalid policy
  configuration.
- Emulator tests verify stale owner and missing-MFA role changes leave both
  Auth claims and Firestore role mirrors unchanged.
- Existing authorization/convergence suites cover protected owner, forged or
  stale roles, banned staff, sanctions, room/Club controls and audit writes.
