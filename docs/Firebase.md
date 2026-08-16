# Firebase

The platform/data layer: Auth, Firestore, Storage, Hosting, App Check,
email delivery. For the compute layer (Cloud Functions code), see
[Backend.md](Backend.md); for the reasoning behind the overall
client-direct-writes model this schema is designed around, see
[Architecture.md](Architecture.md#the-core-architectural-choice) and
[ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work);
for the security principles this schema and its rules are held to, see
[SECURITY.md](SECURITY.md).

## Project

- **Project ID**: `yovoice-ec54a`.
- **Firestore region**: `europe-west4`.
- **Cloud Functions region**: `europe-west1`.
- Config lives in `firebase.json` / `lib/firebase_options.dart` (generated
  via `flutterfire configure`, already committed — no per-developer setup
  beyond access to the `yovoice-ec54a` project).

## Auth

Firebase Authentication (email/password + Google Sign-In), shared across
this Flutter app and `yovoice-website` via the custom Auth domain
`auth.yovoice.app` — one account works everywhere.

`email_verified` is a real gate, not just a UI banner: Firestore rules and
Cloud Functions check `request.auth.token.email_verified` (or the
equivalent server-side claim) before allowing content-creation/outbound
actions (posting, creating rooms/clubs/moments, `bootstrapSuperAdmin`).
See [Architecture.md](Architecture.md#authentication-flow) for the full
sign-up → verify → claim sequence, and
[ADR-008](Decisions.md#adr-008-resend-smtp-instead-of-firebases-default-email-sender)
for why registration/login through email still routes to Firebase's own
hosted action page rather than a custom `handleCodeInApp` deep link.
Roles (`superAdmin` and friends) live in the same custom-claims mechanism,
never in a Firestore field — see
[SECURITY.md](SECURITY.md#identity-and-roles) for why that specific
choice matters.

### Email delivery

Verification and password-reset emails go through **Resend SMTP** —
Firebase's default sender never reliably delivered. The SMTP username must
stay literally the string `"resend"`, not the account email or an
API-key-looking value. `ActionCodeSettings` (`lib/features/auth/data/action_code_settings.dart`)
configure both the verify-email and password-reset flows.

## Firestore schema

Top-level collections (from `firestore.rules`):

| Collection | Subcollections |
|---|---|
| `users/{userId}` (private; owner get only, never client-listable) | `friendRequests`, `sentFriendRequests`, `friends`, `blocked`, `following`, `followers`, `clubs`, `notifications`, `fcmTokens` |
| `publicProfiles/{userId}` (server-owned exact public profile) | — |
| `socialPresence/{userId}` (server-owned, self/canonical-friend read) | — |
| `privateRateLimits/{id}` (Admin-only search budgets) | — |
| `conversations/{id}` | `messages` |
| `clubs/{clubId}` | `members`, `invites`, `channels` → `messages` |
| `rooms/{roomId}` | `participants`, `roomMembers`, `messages`, `handRequests` |
| `voiceMoments/{momentId}` | `likes`, `comments` |

Notable fields:

- **Public-profile projection** — the safe `publicProfiles/{userId}` schema is
  `uid`, `displayName`, `username`, normalized name/username search keys,
  `photoUrl`, `bannerUrl`, `bio`, country/language/website/status fields,
  `accountType`, `premiumIdentity`, three public social counts,
  `schemaVersion` and `updatedAt`. No email, presence, notification settings,
  staff/moderation state or device data is valid here. Clients can get a known
  active account but cannot list or write; prefix discovery is the bounded
  `searchPublicProfiles` callable. Presence lives separately in
  `socialPresence` and requires self or both friendship mirrors. Full decision:
  [ADR-054](Decisions.md#adr-054-private-account-records-are-split-from-exact-server-owned-public-profiles).

- **`unlockedTitleTimestamps`** on `users/{userId}` — a map of achievement
  id → server timestamp, written by `AchievementService` whenever a title
  is newly unlocked. Exists specifically so the Awards screen's "recent
  unlocks" feed is real data, not inferred — see
  [ADR-010](Decisions.md#adr-010-real-per-achievement-unlock-timestamps).
- **`experience`** on `rooms/{roomId}` — `'community'` or `'broadcast'`.
  Legacy documents may still contain `'podcast'`; the client maps that to
  `broadcast` for backward compatibility. **Do not remove that mapping**
  until every production room document has been migrated — see
  [ADR-001](Decisions.md#adr-001-legacy-podcast-room-experience-stays-supported).

### Why `rooms/{roomId}/roomMembers` and not `members`

`rooms/{roomId}/members` was renamed to `roomMembers` specifically so it no
longer collides, as a `collectionGroup()` name, with `clubs/{clubId}/members`
— see
[ADR-005](Decisions.md#adr-005-roomsroomidmembers-renamed-to-roommembers)
for the full story (it was a real, confirmed production bug, not a style
choice).

### `collectionGroup()` queries need a top-level rule

A nested `match /parent/{id}/collection/{doc}` rule only authorizes reads
scoped to one specific parent — it does **not** make that collection
queryable via `collectionGroup()`. That needs a separate, top-level
`match /{path=**}/collection/{doc}` rule. Two exist today, both read-only
and narrowly scoped to "read your own record":

```
match /{path=**}/roomMembers/{memberId} {
  allow read: if isSignedIn() && resource.data.userId == request.auth.uid;
}
match /{path=**}/invites/{inviteId} {
  allow read: if isSignedIn() && resource.data.inviteeId == request.auth.uid;
}
```

See [TESTING.md](TESTING.md) for the emulator-testing workflow this
depends on, and [Bugs.md](Bugs.md) /
[ADR-005](Decisions.md#adr-005-roomsroomidmembers-renamed-to-roommembers)
for the production incident that made this rule necessary. The design
principles behind rules like this — check a claim against a real
document, never trust the request — are collected in
[SECURITY.md](SECURITY.md#firestore-security-rules--design-principles).

## Storage

`storage.rules` — four upload paths, each size/content-type limited:

| Path | Purpose | Read |
|---|---|---|
| `users/{userId}/profile/{fileName}` | Profile photos | Public |
| `room_images/{roomId}/{uid}_{ts}.ext` | Room cover images | Public |
| `clubs/{userId}/{clubId}/{kind}_{ts}.ext` | Club images | Public |
| `voice_moments/{userId}/{fileName}`, `voice_replies/{userId}/{momentId}/{fileName}` | Voice Moment audio | Signed-in only |

Uploads tied to content shown to other users require `email_verified`
(profile photos are deliberately exempt — setting one during onboarding,
before verification completes, is normal).

## Firebase App Check

Integrated client-side in the Flutter app
(`AndroidDebugProvider`/`AppleDebugProvider` in debug,
`AndroidPlayIntegrityProvider`/`AppleAppAttestWithDeviceCheckFallbackProvider`
in release, `lib/main.dart`). **`enforceAppCheck` is `false` on every Cloud
Function** — deliberately, pending a token-delivery monitoring period. See
[ADR-004](Decisions.md#adr-004-firebase-app-check-integrated-client-side-enforcement-deliberately-off),
[SECURITY.md](SECURITY.md#firebase-app-check), and [Bugs.md](Bugs.md) for
current status and what this gap does and doesn't expose.

Debug builds print a debug token to the device log on first launch — must
be registered in **Firebase Console → App Check → Apps → Manage debug
tokens** before Firestore/Auth calls succeed from a simulator/emulator.

## Firestore rules testing

```bash
brew install openjdk           # one-time, needed for the emulator's JVM
export PATH="/usr/local/opt/openjdk/bin:$PATH"
firebase emulators:start --only firestore --project yovoice-ec54a
cd firestore-tests && npm install && npm test
```

Full details in [`firestore-tests/README.md`](../firestore-tests/README.md)
and [TESTING.md](TESTING.md) — 265 checks, regression + attack-scenario
coverage. Always run against a freshly-started emulator before trusting a
"green" result; see
[ADR-007](Decisions.md#adr-007-firestore-rules-changes-are-always-emulator-tested-against-a-real-collectiongroup-query)
for why that distinction matters.

Deploying rules/indexes and Cloud Functions is manual, on purpose — see
[DEPLOYMENT.md](DEPLOYMENT.md) for the full reasoning and every deploy
command in one place, including a non-obvious gotcha in
`functions/package.json`'s `deploy` script.
