# Firebase

The platform/data layer: Auth, Firestore, Storage, Hosting, App Check,
email delivery. For the compute layer (Cloud Functions code), see
[Backend.md](Backend.md).

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
See [Decisions.md](Decisions.md) for why registration/login through email
still routes to Firebase's own hosted action page rather than a custom
`handleCodeInApp` deep link.

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
| `users/{userId}` | `friendRequests`, `sentFriendRequests`, `friends`, `blocked`, `following`, `followers`, `clubs`, `notifications`, `fcmTokens` |
| `conversations/{id}` | `messages` |
| `clubs/{clubId}` | `members`, `invites`, `channels` → `messages` |
| `rooms/{roomId}` | `participants`, `roomMembers`, `messages`, `handRequests` |
| `voiceMoments/{momentId}` | `likes`, `comments` |

Notable fields:

- **`unlockedTitleTimestamps`** on `users/{userId}` — a map of achievement
  id → server timestamp, written by `AchievementService` whenever a title
  is newly unlocked. Exists specifically so the Awards screen's "recent
  unlocks" feed is real data, not inferred — see `Decisions.md`.
- **`experience`** on `rooms/{roomId}` — `'community'` or `'broadcast'`.
  Legacy documents may still contain `'podcast'`; the client maps that to
  `broadcast` for backward compatibility. **Do not remove that mapping**
  until every production room document has been migrated — see
  `Decisions.md`.

### Why `rooms/{roomId}/roomMembers` and not `members`

`rooms/{roomId}/members` was renamed to `roomMembers` specifically so it no
longer collides, as a `collectionGroup()` name, with `clubs/{clubId}/members`
— see `Decisions.md` for the full story (it was a real, confirmed
production bug, not a style choice).

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

See `firestore-tests/README.md` for the emulator-testing workflow this
depends on, and [Bugs.md](Bugs.md) / [Decisions.md](Decisions.md) for the
production incident that made this rule necessary.

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
[Decisions.md](Decisions.md) and [Bugs.md](Bugs.md).

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
— 43 checks, regression + attack-scenario coverage. Always run against a
freshly-started emulator before trusting a "green" result; see
`Decisions.md` for why that distinction matters.

Deploy rules/indexes with:

```bash
firebase deploy --only firestore:rules,firestore:indexes --project yovoice-ec54a
```
