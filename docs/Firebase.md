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

Firebase Authentication (email/password + Google Sign-In + Sign in with Apple), shared across
this Flutter app and `yovoice-website` via the custom Auth domain
`auth.yovoice.app` — one account works everywhere.

The Flutter client and website implement Firebase Identity Platform TOTP MFA.
The enrollment secret exists only for the in-progress setup UI and is discarded
after Firebase accepts the first code. Sign-in catches Firebase's multi-factor
exception, uses its resolver and submits a TOTP assertion for the selected
enrolled factor. Production must not expose enrollment until `mfa.state` and the
TOTP provider are enabled in the project; see
[ADR-071](Decisions.md#adr-071-two-factor-authentication-uses-firebase-totp-and-fails-closed).

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
| `momentCapacityLedgers/{userId}` (server-only revision/mutex; source only, not deployed) | — |
| `creatorPinnedPosts/{creatorId}` (server-owned exact pointer) | — |

Notable fields:

- **Voice Moment lifecycle (ADR-115, source only)** — root create, publication,
  expiry and delete are Cloud Functions authority. Draft, expired and deleting
  roots are readable only by their author; published roots remain readable by
  signed-in clients. Like/comment documents and every root counter transition
  are server-owned; clients retain parent-gated reads only. The server-only
  `momentCapacityLedgers/{uid}` document is a transaction mutex/version, not a
  capacity counter: exact published roots remain the source of truth, so the
  change needs no backfill.

- **Display-name cooldown** — `users/{userId}.displayNameChangedAt` is an
  optional, server-owned Firestore Timestamp. Its absence means the account is
  legacy and its first callable change is available immediately; after an
  actual change, `updateMyDisplayName` refuses another different canonical
  value for exactly 30 days. Clients cannot create, alter or delete the field.
  Initial account creation and the one-time completion of a partial profile may
  seed `displayName`, but an established name is not client-writable. Resending
  the unchanged value in a merged profile write remains allowed for cached
  clients because Firestore `diff()` excludes equal values. The public
  projections contain the canonical name, never the private cooldown timestamp.
  A hashed `privateRateLimits` record enforces 10 profile-reaching, locally
  valid requests per fixed server minute before profile/Auth reads; clients can
  neither read nor reset it.

- **User-authored identity snapshots** — Broadcast
  `rooms/{roomId}/handRequests/{uid}.displayName` and Family
  `clubs/{clubId}/checkIns/{id}.displayName` must exactly equal the current
  canonical `users/{uid}.displayName`. Rules resolve the private owner record
  directly, so a stale Firebase Auth token/profile or a modified client cannot
  publish a forged name. Both creates also use an exact field allowlist and a
  `createdAt` pinned to `request.time`.

- **Creator pinned post** — `creatorPinnedPosts/{creatorId}` has exact schema
  `schemaVersion`, `creatorId`, `momentId`, `pinnedAt`, `updatedAt`. Clients
  may get only a known Creator id while both reader and target are active and
  the target still has canonical Premium Creator authority. Listing and every
  client write are denied. `setCreatorPinnedPost` owns the mutation and
  revalidates the published schema-v2 Voice Moment in one transaction.
  Cleanup runs on Moment eligibility, Creator profile and entitlement changes;
  subscription state is never copied into the public pin document.

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
- **`voiceMinutes`** on `users/{userId}` — **written by nothing.** It is
  seeded to `0` by `ProfileService` and is only ever derived from
  `voiceSeconds` inside `functions/achievements/model.js`, but the sole
  producer of `voiceSeconds` is `receiveLiveKitAchievementWebhook` in
  `functions/achievements/livekit_http.js`, which is **not exported from
  `functions/index.js`** and therefore not deployed. Consequence:
  Creator Studio's "Voice time" tile and the entire voice achievement
  category are permanently zero for every account. Do not read this field
  as a metric until the webhook is wired. See [Bugs.md](Bugs.md#achievements).
- **`memberCount`** on `rooms/{roomId}` — may **overcount**, by design
  since `952d8e4`. A client that deletes its `roomMembers` row without
  pairing the room write leaves the counter high. It can never undercount
  below a real departure, which is the property that matters: an
  undercount was what trapped members in a room they could not leave. See
  [ADR-056](Decisions.md#adr-056-a-moderation-action-belongs-in-a-callable-that-completes-the-whole-removal-not-in-a-rule-that-deletes-one-row).
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

## Composite indexes

`firestore.indexes.json` currently holds **26** composite indexes and **5**
`fieldOverrides`. The 2026-08-19 live reading of 19 and 4 is historical, not
proof of today's production state; re-read production before every release
rather than subtracting one stale count from another. ADR-115 adds the
source-only `voiceMoments(authorId ASC, isPublished ASC)` composite used by the
exact active-cap query. It must be deployed to READY/Enabled and the real query
must succeed before the new Functions can serve traffic. The emulator does not
enforce this requirement.

The file is deliberately kept a **superset** of production, so an index deploy
can never be the thing that removes one; being ahead is expected, and the thing
to check is whether a feature depends on the gap.

The first three `fieldOverrides` enable `COLLECTION_GROUP` scope on
`rooms.roomId`, `participants.userId` and `roomMembers.userId`; the
`invites.inviteeId` and `clubs.clubId` entries also re-declare their collection
orders while adding collection-group scope.

### A `fieldOverrides` entry *replaces* automatic single-field indexing

This is a **latent trap, not a current defect** — write it down now
because the day it bites, nothing in the test suite will say so.

Firestore indexes every field of every document automatically, but those
automatic single-field indexes are **`COLLECTION` scope only**:
"Automatic indexes with collection group scope are not maintained by
default" ([index overview](https://firebase.google.com/docs/firestore/query-data/index-overview)).
That is the entire reason a `COLLECTION_GROUP` override has to be written
by hand. The trap is what happens to the automatic indexes when you do:
a `fieldOverrides` entry **replaces** automatic indexing for that field
rather than adding to it. Declaring only `COLLECTION_GROUP` orders
therefore *removes* the field's automatic collection-scoped
ascending/descending indexes.

Verified against the live project with
`firebase firestore:indexes --project yovoice-ec54a` on 2026-08-17 and
again on 2026-08-19 (after the 2026-08-18 index deploy) — all three
overrides below declare `COLLECTION_GROUP` and nothing else, so the
collection-scope indexes for those three fields **do not exist in
production**:

| Field | Deployed scopes | The one query it exists for |
|---|---|---|
| `rooms.roomId` | `COLLECTION_GROUP` ASC | `collectionGroup("rooms").where("roomId", "==", …)` in `deleteActiveVoiceSessionsForRoom` (`functions/livekit/sessions.js:63`) |
| `participants.userId` | `COLLECTION_GROUP` ASC | `collectionGroup("participants").where("userId", "==", …)` (`functions/staff/voice_enforcement.js:248`) |
| `roomMembers.userId` | `COLLECTION_GROUP` ASC + `CONTAINS` | `collectionGroup('roomMembers').where('userId', isEqualTo: …)` in `RoomService` (`lib/features/rooms/data/services/room_service.dart:226`) |

Each override is exactly what its query needs, and **nothing anywhere runs
a collection-scoped `where`/`orderBy` on any of those three fields** — the
collection-scoped uses of `rooms` and `participants` are all `doc()` gets
or whole-subcollection reads. Adding the collection-scope orders back
would cost storage on every document to serve queries that do not exist,
so the correct action here is this paragraph, **not an index change**.

**What will go wrong, and when.** The first time anyone writes a
collection-scoped query or `orderBy` on `rooms.roomId`,
`participants.userId` or `roomMembers.userId` — including an innocuous
`.collection('participants').where('userId', …)` on a single room — it
will fail in production with `FAILED_PRECONDITION` and **pass in every
emulator test**, because the emulator does not require indexes. It is the
same failure mode that kept Premium expiry broken (below), reached by a
different route: there the index was missing because nobody deployed it,
here it is missing because an override quietly withdrew it.

**The fix at that point is to add the `COLLECTION`-scope orders to the
existing `fieldOverrides` entry — not to add a second entry.** One entry
owns the field's entire index configuration. The `invites.inviteeId`
override already in the same file is the shape to copy: `COLLECTION` ASC +
`COLLECTION` DESC + `COLLECTION_GROUP` ASC, i.e. it re-declares the
automatic indexes it displaced *and* adds the group scope.

**A `fieldOverrides` entry keys off the collection *group* id**, so
`collectionGroup: "rooms"` covers the root `rooms` collection **and** every
`activeVoiceSessions/{uid}/rooms` subcollection — which is precisely why
the mirror query above works, and a reason to think twice before assuming
an override touches only the collection you had in mind. The same aliasing
is what [ADR-005](Decisions.md#adr-005-roomsroomidmembers-renamed-to-roommembers)
renamed `members` to `roomMembers` to avoid.

Related and already known: `publishPublicStatsSchedule` runs
`collectionGroup("rooms").where("expiresAt", ">", …)`
(`functions/stats/public_stats.js:224`), which needs a `COLLECTION_GROUP`
index on `rooms.expiresAt` that no override declares — one of the
preconditions on that function's deploy, see
[DEPLOYMENT.md](DEPLOYMENT.md).

**One of these indexes fixed a live, silent production defect.** The
scheduled `expirePremiumIdentity` sweep queries

```
entitlements where isPremium == true and currentPeriodEnd < now
```

(`functions/premium/entitlements.js:163`), which needs a composite index
on `entitlements(isPremium ASC, currentPeriodEnd ASC)`. That index was in
the repo but had never been deployed, so every scheduled run failed with
`FAILED_PRECONDITION` and **Premium never expired for anyone**. Nothing
surfaced it: the emulator does not require composite indexes, so the
Functions suite was green throughout, and the failure lived only in
Cloud Scheduler logs. Deployed 2026-08-16.

The lesson generalizes: **a new server-side query is an index change until
proven otherwise**, and the only place that proof exists is production.
After deploying a scheduled function that queries, check Console →
Functions → Logs for its first real run rather than assuming it works.

## Storage

`storage.rules` — the six client-upload path families below, each
size/content-type limited:

| Path | Purpose | Read |
|---|---|---|
| `users/{userId}/profile/{fileName}` | Profile photos | Public |
| `room_images/{roomId}/{uid}_{ts}.ext` | Room cover images | Public |
| `clubs/{userId}/{clubId}/{kind}_{ts}.ext` | Club images | Public |
| `voice_moments/{userId}/{fileName}` | Voice Moment root audio | Draft/expired/deleting: author through the authenticated SDK; published: signed-in users |
| `voice_replies/{userId}/{momentId}/{fileName}` | Voice Moment reply audio | Signed-in only |
| `message_attachments/{ownerId}/{conversationId}/{messageId}.{ext}` | Private DM photos and voice messages | Active conversation participants only |

Uploads tied to content shown to other users require `email_verified`
(profile photos are deliberately exempt — setting one during onboarding,
before verification completes, is normal).

ADR-115's source-only root-audio contract accepts creation only for a
server-reserved schema-v2 `uploading` draft with a lowercase 20-hex Moment id,
exact path and `{authorId, momentId}` metadata, plus unpublished/null audio and
media state (`isPublished: false`; `audioUrl`, `publishedAt` and media fields
null).
New allocations require lowercase hex. Existing 20-character mixed-case ids
remain narrowly read-compatible so historical media is not cut off; the
metadata, root author and full path must still agree. Root audio is immutable
to every client, including its author while the draft is still `uploading`.
Abandoned uploads, published media, expired media and deleting media are all
cleanup-worker/Admin authority. This deliberately removes a cross-service race
where client deletion could land after Storage validation but before the
Firestore publish transaction. Changing Storage Rules
does not revoke a Firebase download-token URL already learned while a Moment
was published: that bearer URL remains usable until object cleanup or token
rotation.

Voice reply allocation is separately reservation-bound. A new object must use
the lowercase 20-hex comment id, exact path and `{authorId, momentId,
commentId}` metadata from an unexpired server-owned
`voiceMomentUploadReservations/{commentId}` row in canonical `uploading` state;
payload MIME and size must satisfy the same bounded audio allowlist the
finalizer validates. Reply audio is client-immutable before and after
finalization: bounded abandoned-reservation cleanup removes an unfinished
object, while `finalizeVoiceCommentDraft` creates the comment and removes the
reservation atomically. Already-existing mixed-case reply objects remain
signed-in readable, but receive no legacy create/delete exception.

**Club image names accept two shapes, and this matters** (fixed in
`56e7ea7`, deployed 2026-08-16): `validClubImageUpload()` previously
accepted only the bare `avatar`/`banner` object name, while the client
that was already in production uploads `{kind}_{millis}.{ext}`. Every club
avatar and banner upload was denied. Both shapes are now accepted, and the
timestamped form is validated the way the profile path is, including
MIME/extension agreement. The general lesson: a Storage rule that pins an
exact object name is a contract with a *deployed* client, so verify it
against what the shipped client actually writes, not against what the
current source writes.

Direct-message attachments use a stricter contract than the older media
paths. A server-owned `directMessageUploadReservations/{messageId}` document
pins owner, conversation, message id, path, media kind, MIME, duration and a
15-minute expiry. Storage creation requires that exact live reservation and
exact custom metadata; objects are immutable to clients. Finalization checks
the actual generation and writes only a private `gs://` reference into the
canonical message. Reads require an active authenticated participant in the
same schema-v2 conversation. Backend cleanup uses the canonical bucket from
Firebase configuration rather than synthesizing a suffix from `GCLOUD_PROJECT`.

Direct-message delivery also reads `users/{recipientId}.messagePrivacy`.
Accepted values are `everyone`, `peopleYouFollow`, `friends`, and `nobody`.
Missing means `everyone` for legacy accounts; unknown values fail closed.
`peopleYouFollow` checks the recipient-to-sender `following` edge, while
`friends` checks both server-owned `friendshipGuards`. Owner create/update
rules accept only the exact enum. The legacy client-direct message create rule
performs the same recipient check as Functions; reads and non-create message
operations keep existing conversation history usable.

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
and the single current-count table in [TESTING.md](TESTING.md). Coverage
includes Firestore, Storage and family-media regression/attack scenarios;
do not duplicate their moving counts here. Always run against a
freshly-started emulator before trusting a "green" result; see
[ADR-007](Decisions.md#adr-007-firestore-rules-changes-are-always-emulator-tested-against-a-real-collectiongroup-query)
for why that distinction matters. And note what a green run does *not*
prove: the emulator does not require composite indexes, so a query that
passes here can still fail in production with `FAILED_PRECONDITION` —
which is exactly how Premium expiry stayed broken (below).

Deploying rules/indexes and Cloud Functions is manual, on purpose — see
[DEPLOYMENT.md](DEPLOYMENT.md) for the full reasoning and every deploy
command in one place. Note that `npm run deploy` inside `functions/` is a
full `firebase deploy --only functions` against whatever project
`firebase use` points at — it is not the single-function shortcut this doc
tree described it as before 2026-08-16.

## Stripe billing data boundary (source only; not deployed)

- `entitlements/{uid}` remains the owner-readable, server-written access
  projection and now includes `cancelAtPeriodEnd` and an exact
  `renewalBehavior` (`renews`, `ends`, or `none`).
- `billingAccounts/{uid}` is the canonical Firebase uid ↔ Stripe Customer/
  Subscription binding plus provider lifecycle and pending Checkout recovery.
- `billingRateLimits/{uid_action}`, `billingCheckoutLocks/{uid}` and
  `stripeWebhookEvents/{eventId}` are operational anti-abuse/idempotency state.
- Firestore Rules deny every client read and write to all four operational
  collections. Only Admin SDK Functions access them.

No new composite index is required. The Rules emulator command in this file
passed 396 checks when this was written (2026-08-18) — the suite is **466** as
of 2026-08-20 — including read/create/update/delete denial for each billing
collection.

## Profile visibility (source only; not deployed)

The canonical preference is the private `users/{uid}.profileVisibility` field;
it is not accepted by any client create/update allowlist. The
`setMyProfileVisibility` callable writes it and revokes incompatible marketing
consent. `publicProfiles/{uid}` remains the minimal projection, but its exact-id
read rule re-checks active source state, visibility, blocks and—when set to
`friends`—both `friendshipGuards` rows. `privateShowcaseControl/live` is an
Admin-only monotonic generation used to reject stale website publication.
