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
| `users/{userId}` (private; owner get only, never client-listable) | `friendRequests`, `sentFriendRequests`, `friends`, `blocked`, `following`, `followers`, `clubs`, `notifications`, `fcmTokens`, `incomingCalls` |
| `publicProfiles/{userId}` (server-owned exact public profile) | — |
| `socialPresence/{userId}` (server-owned, self/canonical-friend read) | — |
| `privateRateLimits/{id}` (Admin-only search budgets) | — |
| `conversations/{id}` | `messages` |
| `clubs/{clubId}` | `members`, `invites`, `channels` → `messages` |
| `rooms/{roomId}` | `participants`, `roomMembers`, `messages`, `handRequests` (legacy-client compatibility only) |
| `voiceMoments/{momentId}` | `likes`, `comments` |
| `reels/{reelId}` (server-owned; every client read and write denied, served through callables) | `likes`, `comments` |
| `reelVoiceCommentReservations/{commentId}` (server-only upload reservation; ADR-187, **not deployed**) | — |
| `momentCapacityLedgers/{userId}` (server-only revision/mutex; deployed 2026-08-27) | — |
| `creatorPinnedPosts/{creatorId}` (server-owned exact pointer) | — |
| `directCalls/{callId}` (server-owned; two participants get only) | — |
| `directCallLocks/{userId}` / `directCallControlOutbox/{callId}` (server-only) | — |
| `appConfig/{configId}` (server-only runtime configuration; every client read/write denied) | — |
| `accountDeletionOutbox/{outboxId}` (server-only deletion queue; `allow read, write: if false`, `firestore.rules:2504`) | — |
| `deletedAccountDigests/{digestId}` (server-only ban-survival digests; `allow read, write: if false`, `firestore.rules:2508`) | — |
| `serverMessageMediaUploadReservations/{messageId}`, `serverMessageMediaUploadLeases/{uid}`, `serverMessageMediaUploadBudgets/{digest}`, `serverMessageMediaDeletionJobs/{jobId}` (server channel media, ADR-216, **not deployed**; `allow read, write: if false`) | — |
| `serverMessageMediaObjects/{messageId}` (server-only owner index for account deletion: `schemaVersion`, `ownerId`, `serverId`, `channelId`, `messageId`, `storagePath`, `generation`, `createdAt`; ADR-216, **not deployed**; `allow read, write: if false`) | — |

Notable fields:

- **Account deletion (ADR-206, deployed 2026-09-19)** — `accountDeletionOutbox`
  is the queue `deleteAccountSelfV1` writes and the outbox worker leases:
  `status` (`pending` → `processing` → terminal), `leaseToken`, `leaseUntil`,
  `nextAttemptAt`, `attemptCount`. Both sweep queries are backed by composite
  indexes on `(status, leaseUntil)` and `(status, nextAttemptAt)`; the emulator
  does not need them, so nothing in the test suites reports them missing
  (ADR-007 again). `deletedAccountDigests/{digestId}` keys on a salted HMAC-
  SHA-256 of the lowercased e-mail (`functions/account/retention.js:60-69`) so a
  ban survives the account — and it is written **only** when
  `YOVOICE_DELETED_ACCOUNT_DIGEST_SALT` is configured, which as of 2026-09-19 it
  is not. Both collections are reached through the Admin SDK, which bypasses
  Rules; the two deny blocks close a client enumeration surface and enable
  nothing.

- **Server channel messages gain reactions and media (ADR-216, source
  only, NOT deployed)** — additive, server-written fields on the existing
  `clubs/{serverId}/channels/{channelId}/messages/{messageId}` document:
  `reactions` (map uid → one of the DM's six emoji, at most 500 entries);
  new values `image` and `video` of the existing optional `type`; `mediaUrl`
  (`gs://…`, never an HTTPS URL); `media {schemaVersion, storagePath,
  generation, contentType, size, durationSeconds}`; and `content` carrying
  `Photo` or `Video` for a media message so installed clients render a
  readable line. Nothing renamed or removed, no rules change on the message
  match (every write is Admin SDK), and no new index: the sweeps use a
  single-field range on `expiresAt` and equality filters.

- **Direct-call signaling (ADR-117)** — `directCalls` is the canonical status
  machine (`ringing`, `active`, `declined`, `cancelled`, `ended`, `missed`). A
  callee's `users/{uid}/incomingCalls/{callId}` is a read-only delivery mirror;
  per-user locks prevent overlap and the control outbox makes terminal LiveKit
  cleanup retryable. Clients cannot list arbitrary calls or write any of these
  collections. Scheduled expiry uses the composite index on
  `directCalls(status, expiresAt)`.

- **Servers V1 activation (`appConfig/serversV1`, ADR-176)** — exact document
  `{schemaVersion: 1, callableAccess, testerUids, workersEnabled, revision}`.
  `callableAccess` is `disabled`, `testers` or `all`; only `testers` may carry
  a non-empty list, bounded to 100 unique valid Auth UIDs. Missing data is
  disabled. Unknown fields, malformed values, duplicates, an inconsistent
  list or a read failure fails closed. Functions read it uncached: callables
  use the authenticated UID and workers use the independent boolean. Clients
  cannot read the cohort or mutate the gate because `match
  /appConfig/{configId}` denies every client operation. The 54 base export
  names are source-static and ignore `YOVOICE_SERVERS_V1`; the seven Podcast
  recording/Egress exports remain source-disabled. *(On `nb/integrate` the base
  is 55: the ADR-180 amendment adds `releaseServerChannelSessionIfEmptyV1`.
  The seven ADR-216 message exports sit outside that manifest and use the
  same gate.)*

  **Live production values (read 2026-09-16, unchanged by either deploy that
  day).** `appConfig` holds exactly two documents. `appConfig/serversV1` is
  `{schemaVersion: 1, callableAccess: "all", testerUids: [] (0 entries),
  workersEnabled: true, revision: 4}`, `updateTime 2026-09-14T06:43:29Z`;
  `appConfig/gif` is `{enabled: true}`, `updateTime 2026-09-14T06:40:15Z`. So
  every signed-in account can reach every Servers callable today, and those
  callables are registered `enforceAppCheck: false` — that is the owner's
  decision of 2026-09-16
  ([ADR-197](Decisions.md#adr-197-the-2026-09-16-owner-decisions-on-servers-exposure-warm-instances-and-the-obs-canary)),
  not a regression, but it is the live security posture and the earlier
  "Servers for testers only" intent is not enforced by configuration.
  `serverRuntimeCapacity/communityBroadcastV1` does **not** exist and
  `serverBroadcastUsage` is empty, so the OBS surface is inert. Absence means
  *enabled* for `appConfig/gif` and *disabled* for the capacity document —
  never delete either.

- **Community OBS usage and capacity (`serverBroadcastUsage/{uid}`,
  `serverRuntimeCapacity/communityBroadcastV1`, ADR-192, source only)** — both
  are `allow read, write: if false` for every client and are written only by
  `createServerBroadcastIngressV1` and its cleanup paths through the Admin SDK.
  A usage slot holds the exact host, server, channel, room, session, LiveKit
  room and OBS identity, `state` (`provisioning` or `active`), the operation and
  lease ids and the committed `ingressId`. The capacity document is exactly
  `{schemaVersion: 1, enabled, activeCount, limit (1-25), updatedAt}`; an
  operator creates it, and a missing document means OBS is disabled. The
  Stream Key is never stored in either. `firestore-tests/server_rules.test.js`
  proves get, set, update, delete and list are denied for owner, admin, member
  and outsider.

- **Voice Moment lifecycle (ADR-115, deployed 2026-08-27)** — root create, publication,
  expiry and delete are Cloud Functions authority. Draft, expired and deleting
  roots are readable only by their author; published roots remain readable by
  signed-in clients. Like/comment documents and every root counter transition
  are server-owned; clients retain parent-gated reads only. The server-only
  `momentCapacityLedgers/{uid}` document is a transaction mutex/version, not a
  capacity counter: exact published roots remain the source of truth, so the
  change needs no backfill.

- **Reel voice comments (ADR-187/ADR-191, source only, NOT deployed)** — a Reel
  comment document keeps its exact eight text keys (`authorId, authorName,
  createdAt, durationSeconds, reelId, schemaVersion, text, type`) and
  `schemaVersion: 1`. `type` is `"text"` (duration `null`, text 1–1000) or
  `"voice"`, which adds exactly `storagePath, mediaGeneration, mediaSize,
  mediaContentType`, an integer `durationSeconds` 1–60 and a caption of 0–140
  characters. `storagePath` must equal
  `reel_voice_comments/{authorId}/{reelId}/{commentId}.m4a` recomputed from the
  document's own author and id. No backfill: existing text comments are
  unchanged. `getReelViewV2` withholds voice comments unless the caller sends
  `commentTypes`, so installed clients never receive one; `commentCount`
  counts both kinds. A report on a voice comment adds `targetCommentType`,
  `targetDurationSeconds`, `targetStoragePath` and `targetMediaGeneration`
  (absent type means text). Server-only
  `reelVoiceCommentReservations/{commentId}` rows (`kind: "reelVoiceComment"`,
  30-minute `expiresAt`) authorize the upload and are deleted by finalize or by
  `expireAbandonedReelVoiceCommentDraftsSchedule`; audio deletion goes through
  `reelCleanupOutbox` kind `reelVoiceComment`.

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

- **User-authored identity snapshots** — legacy Broadcast clients may still
  write `rooms/{roomId}/handRequests/{uid}.displayName`, while current Podcast
  stage requests use `participants/{uid}.isHandRaised`. The legacy name and
  Family `clubs/{clubId}/checkIns/{id}.displayName` must exactly equal the current
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
  `voiceSeconds` inside `functions/achievements/model.js`, and the sole
  producer of `voiceSeconds` is `receiveLiveKitAchievementWebhook` in
  `functions/achievements/livekit_http.js`. Consequence: Creator Studio's
  "Voice time" tile and the entire voice achievement category are zero for
  every account. Do not read this field as a metric until the webhook is
  confirmed to be receiving events. See [Bugs.md](Bugs.md#achievements).

  *(Corrected 2026-09-19: `receiveLiveKitAchievementWebhook` **is** exported
  from `functions/index.js` and deployed — the earlier wording here said it
  was not. `voiceMinutes` is still zero for a different reason: the webhook
  URL was registered in LiveKit Cloud on 2026-09-19 but no delivery has been
  read back, so the function may still be receiving no events. Confirming a
  real delivery (see [DEPLOYMENT.md](DEPLOYMENT.md)) is what starts both
  voice-time accounting and the provider-driven end of an empty channel
  session.)*
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

### GIF collections (ADR-172) — server-owned, client-invisible

Five dedicated collections plus `appConfig` and existing private report quotas,
every one of them
`allow read, write: if false` for **every** client including staff. All are
written by the Admin SDK inside `functions/media/gif/**`.

| Collection | Document | Holds | Lifetime |
|---|---|---|---|
| `gifAssets/{provider}_{id}` | one asset | `provider, gifId, title, rating, url, previewUrl, width, height, firstSeenAt, lastSeenAt, reportCount, blocked, suppressed` | **never expired** |
| `gifQueryCache/{sha256}` | one result page | `items[], nextCursor, cachedAt, expiresAt` | native TTL on `expiresAt` |
| `gifRateLimits/{uid}` | one token bucket | `tokens, lastRefillAt, windowStartedAt, windowCount, dayStartedAt, dayCount` | rolling |
| `gifProviderBudget/{yyyymmddhh}` | one UTC hour | `calls, budget` | append-only, per hour |
| `gifBlocklist/current` | suppression index | `assetIds[]` (capped at 500) | rolling |
| `appConfig/gif` | feature config | `enabled` | operator-written |
| `privateRateLimits/{digest}` | GIF report attempt/day quota | bounded window/count from shared rate-limit contract | rolling |

GIF safety reports use `reports/gif_{digest(reporter,provider,id)}`, not raw
UID concatenation; opaque/dotted/Unicode account IDs cannot violate the
moderator's bounded report-ID contract. Report resolution, durable asset block
and protected `adminAuditLogs` record commit atomically. The optional discovery
suppression cache may be repaired on replay. These additions do not grant
clients access to private quotas or catalog authority.

**`gifAssets` must never be given a TTL policy.** It is three things at once —
the send-time authority `resolveGifAsset()` consults, the moderation record
carrying `blocked`/`reportCount`, and the per-asset blocklist — so expiring it
would break sending. It grows at roughly one document per unique asset ever
surfaced, on cache misses only. Add its document count to what you watch.

**`gifQueryCache` ids are digests, not readable text**, so the collection is not
a public list of what people search for. The cache is shared across all
accounts on purpose: that sharing is what makes a beta API key viable.

**No new composite index is required.** Every lookup here is by document id.
The moderation queue's existing `reports` indexes cover `targetType:
'gifAsset'`.

A `gifAsset` report is server-written only: the `reports` create rule has no
branch for that target type, and its field allowlist has no room for
`gifProvider`, `gifId`, `targetTextSnapshot` or `targetMediaUrl`.

### Bug report collections (ADR-223) — server-owned, client-invisible

| Collection | Document | Holds | Lifetime |
|---|---|---|---|
| `bugReports/{br_<40 hex>}` | one report | `schemaVersion, reportId, reporterId, inputHash, description, context{appVersion, buildNumber, platform, osVersion, locale, theme, brightness, route, routeDepth, viewportWidth, viewportHeight, textScale}, screenshot{status (reserved, attached, expired, deleted, refused, removed, missing), storagePath, contentType, size, generation, attachedAt} \| null, screenshotExpiresAt, status, createdAt, updatedAt, expiresAt`; server-added `delivery.{email,github}` and `statusUpdatedAt` | 180 days (hourly sweep) |
| `bugReportUploadReservations/{reportId}` | one screenshot upload capability | `schemaVersion, kind, reportId, ownerId, contentType, size, storagePath, status, createdAt, expiresAt` | 15 minutes, then swept |
| `appConfig/bugReports` | operator switches | `enabled` (missing = on), `emailEnabled, emailTo, emailFrom, githubEnabled, githubRepo` (a stale `githubIncludeDescription` is ignored: alerts are link-only) | operator-written |

Both collections are `allow read, write: if false` for every client. The owner
list uses the composites `bugReports (status ASC, createdAt DESC)`,
`(reporterId ASC, createdAt DESC)` and `(reporterId ASC, status ASC, createdAt
DESC)` (the reporter filter answers access and erasure requests); everything
else is a document read or a single-field range. The owner's delete and
remove-screenshot actions write `adminAuditLogs` entries
(`targetType: "bugReport"`). The alert channels' daily budgets are
`privateRateLimits` documents keyed by the `bug-report-global-sentinel`
sentinel.

## Composite indexes

`firestore.indexes.json` currently holds **47** composite indexes and **13**
`fieldOverrides` (counted 2026-09-19 at `a18fe789`; 45 and 13 at `58853fb0` on
2026-09-17, plus the two `accountDeletionOutbox` composites Build 32 added —
`(status, leaseUntil)` and `(status, nextAttemptAt)`. The count includes the
`gifQueryCache.expiresAt` TTL override and the `serverInviteRefs.expiresAt`
collection-group exemption). Production agrees: the Firestore admin API
reported **47/47** composite indexes `READY` after the Build 32 index deploy on
`2026-09-19` (`yovoice-evidence/2026-09-18/b32/deploy-indexes-readback.json`),
and 45/45 plus the `serverInviteRefs.expiresAt` exemption `READY` at
`2026-09-16T22:18:55Z`. The
2026-08-19 live reading of 19 and 4 is historical, not
proof of today's production state; re-read production before every release
rather than subtracting one stale count from another. Note that a live
`firebase firestore:indexes` listing of "12 overrides" and a source count of 12
were never the same twelve — the live list mixes source overrides with the
database's built-in `__default__` entry, and `gifQueryCache.expiresAt` shows up
only in the TTL query because it carries `usesAncestorConfig: true`. Compare
sets, not totals. ADR-115's
`voiceMoments(authorId ASC, isPublished ASC)` composite is deployed and reached
READY on 2026-08-27; the exact production query succeeded before the new
Functions received traffic. The emulator does not enforce this requirement,
so the live query remains a mandatory release gate.

The file is deliberately kept a **superset** of production, so an index deploy
can never be the thing that removes one; being ahead is expected, and the thing
to check is whether a feature depends on the gap.

The first three `fieldOverrides` enable `COLLECTION_GROUP` scope on
`rooms.roomId`, `participants.userId` and `roomMembers.userId`; the
`invites.inviteeId` and `clubs.clubId` entries also re-declare their collection
orders while adding collection-group scope.

The thirteenth entry, **`serverInviteRefs.expiresAt`**, was added on 2026-09-16
(`58853fb0`) and follows the preserve-then-extend shape: `COLLECTION` ASC +
`COLLECTION` DESC + `COLLECTION CONTAINS` + `COLLECTION_GROUP` ASC, and
deliberately **no `ttl`**. It exists for exactly one query,
`collectionGroup("serverInviteRefs").where("expiresAt", "<=", now)` in
`sweepExpiredServerInvitesSchedule` (`functions/notifications/invites.js:465`).
Without it that sweep had failed on every one of its 250 runs since
2026-09-14T06:13Z with `FAILED_PRECONDITION: The query requires a
COLLECTION_GROUP_ASC index`, so expired invite pointers and their notifications
were never cleaned up — the emulator does not enforce index requirements, so an
existing suite that drove the real sweep stayed green throughout. The three
`COLLECTION`-scope entries are re-declared on purpose: an override *replaces*
automatic single-field indexing (the trap below), and omitting them would have
withdrawn collection-scope indexing of that field as a side effect of fixing the
sweep. Adding `ttl: true` would have started a second, uncoordinated deleter on
invite pointers, which is why the test asserts `ttl` stays absent.

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

Related and already known: `fetchFreshVoiceSessions` runs
`collectionGroup("rooms").where("expiresAt", ">", …)`
(`functions/stats/public_stats.js`), which needs a `COLLECTION_GROUP`
index on `rooms.expiresAt` that no override declares — one of the
preconditions on that function's deploy, see
[DEPLOYMENT.md](DEPLOYMENT.md).

**`rooms.expiresAt` is the same latent defect class as
`serverInviteRefs.expiresAt`, and it is the one still open.** The difference is
purely that nobody calls it: `fetchFreshVoiceSessions` is exported and tested
but deliberately **not** called by `publishPublicStatsSchedule` (the comment at
the top of `public_stats.js` says so in capitals), and that schedule was
returning 150 × 200 with 0 errors when it was last read on 2026-09-16. The
moment anyone reconnects that function, it fails in production exactly the way
the invite sweep did and passes in every emulator run. Give it the same
treatment before that happens: the preserve-then-extend override plus a test
that executes the real cross-parent `collectionGroup()` query
(`functions/test/server_invite_sweep_index.test.js` is the shape to copy). Every
other production `collectionGroup()` query was cross-checked against the live
index set on 2026-09-16 and is covered: `rooms.roomId`, `clubs.clubId`,
`participants.userId`, `serverFollows.serverId`,
`channelSessions.livekitRoomName`, `invites.inviteeId` and the composite
`episodes(serverId, studioChannelId)`.

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

**The same trap is already loaded for Servers V1.** The all-member channel
query is `accessMode ==` + `status ==` ordered by `position`, and the file
carried **no `channels` entry at all** until 2026-09-12; the
`channels(accessMode ASC, status ASC, position ASC)` COLLECTION-scope composite
is now committed. Committed is not deployed. Every emulator suite passes
without it — the emulator creates indexes on demand — so the first failure
would be in production, on the first real channel list. It is recorded as a
named activation precondition in [Servers.md](Servers.md) alongside the
`channelSessions.livekitRoomName` collection-group override, which has the same
committed-but-unverified status.

Both of those indexes are now deployed and READY in production (checked
2026-09-16: 45/45 composite `READY`, and the `channelSessions.livekitRoomName`
override live), so the READY half of this gate is discharged for them (the "exact production queries succeed" half is still unobserved) — the *rule* below still
governs every future query.

Deploying the static 54-name Server surface does not discharge either index
gate. **Superseded 2026-09-16 — ADR-197 records `callableAccess` as `all` in production by owner decision; the original gate read:** keep `appConfig/serversV1.callableAccess` disabled until both indexes
report READY and the exact production queries succeed. Keep workers disabled
during the inert infrastructure phase, then enable them in a revision-checked
document replacement before the tester cohort. The complete order and rollback
are in [DEPLOYMENT.md](DEPLOYMENT.md#servers-v1-static-registration-and-runtime-activation).

The lesson generalizes: **a new server-side query is an index change until
proven otherwise**, and the only place that proof exists is production.
After deploying a scheduled function that queries, check Console →
Functions → Logs for its first real run rather than assuming it works.

## Storage

`storage.rules` — the client-upload path families below, each
size/content-type limited:

| Path | Purpose | Read |
|---|---|---|
| `users/{userId}/profile/{kind}_{uploadId}.ext` | Profile photos | Direct reads denied; server-authorized, generation-bound V4 grant only |
| `room_images/{roomId}/{uid}_{revision}.ext` | Room cover images | Direct get/list denied; server-authorized, generation-bound V4 grant only |
| `clubs/{userId}/{clubId}/{kind}_{ts}.ext` | Club images | Public |
| `voice_moments/{userId}/{fileName}` | Voice Moment root audio | Draft/expired/deleting: author through the authenticated SDK; published: signed-in users |
| `voice_replies/{userId}/{momentId}/{fileName}` | Voice Moment reply audio | Signed-in only |
| `reel_voice_comments/{userId}/{reelId}/{commentId}.m4a` | Reel voice-comment audio (ADR-187, **not deployed**) | Uploader only while reserved; published audio only through a server-authorized, generation-bound V4 grant |
| `message_attachments/{ownerId}/{conversationId}/{messageId}.{ext}` | Private DM photos and voice messages | Active conversation participants only |
| `server_message_media/{serverId}/{channelId}/{userId}/{messageId}.{jpg\|png\|webp\|mp4\|mov\|webm}` | Server channel photos and videos (ADR-216, **not deployed**) | Create: verified, active uploader with a live server-issued reservation and exact metadata; image 128 B–8 MiB, video 1 KiB–64 MiB and 1–60 s. Get: uploader only while reserved. List/update/delete: never. Viewers: `getServerChannelMessageMediaAccessV1` V4 grants (90 s) only |

| `bug_reports/{uid}/{reportId}.jpg` | In-app bug report screenshots (ADR-223, **not deployed**) | Uploader only while reserved; the owner through a 5-minute generation-bound V4 URL |

Profile and room-cover uploads require a verified account plus an exact,
server-issued reservation binding owner, object path, MIME type, byte length
and a ten-minute expiry. Only one active lease per media kind is permitted and
daily byte budgets bound abandoned uploads. Finalization atomically rechecks
the active account, restriction state, authority and previous pointer before
publishing the canonical path and object generation. Expired reservations are
deleted by scheduled cleanup.

`getRoomCoverMediaAccess` rechecks current room visibility, account status,
both block directions and private membership/admission, then issues an HTTPS
`storage.googleapis.com` V4 URL for at most 90 seconds. Public covers use the
same callable because a public Storage prefix would otherwise expose pending,
superseded and orphaned objects. Durable Firebase download tokens are revoked
by the room migration and paginated object-inventory pass before rollout.

ADR-115's deployed root-audio contract accepts creation only for a
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

Reel voice-comment allocation (ADR-187, **not deployed**) is a clone of the
Voice reply block, not a widening of it. A new object must use the lowercase
40-hex comment id, the exact path `reel_voice_comments/{uid}/{reelId}/{commentId}.m4a`
and exactly `{authorId, reelId, commentId}` metadata from an unexpired
server-owned `reelVoiceCommentReservations/{commentId}` row
(`kind: "reelVoiceComment"`, `status: "uploading"`, duration 1–60), under
`isVerified() && isActiveUser() && isValidAudioPayload()` (1 KiB–12 MiB, audio
MIME allowlist). The uploader may read it back only while reserved; update and
delete are denied to every client, including after finalization. Published
audio is never readable directly: `getReelMediaAccessV2` with
`asset: "voiceComment"` and a `commentId` re-checks the viewer against BOTH
the Reel author and the comment author and returns a V4 URL bound to the
comment's `mediaGeneration` for at most 90 seconds (and never past the Reel's
own expiry). Finalize validates the object's size, declared content type,
generation and metadata identity — it does not inspect the bytes, so the stored
duration is the uploading app's declaration. The block reads Firestore through
`firestore.get()`, so it depends on the same Storage service-agent IAM binding
as every other reservation-bound path — see
[DEPLOYMENT.md](DEPLOYMENT.md#pending-not-yet-deployed-reel-voice-comments-adr-187-adr-191)
for the mandatory Firestore Rules → Storage Rules → Functions order.

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
Function** — deliberately. See
[ADR-004](Decisions.md#adr-004-firebase-app-check-integrated-client-side-enforcement-deliberately-off),
[SECURITY.md](SECURITY.md#firebase-app-check), and [Bugs.md](Bugs.md) for
current status and what this gap does and doesn't expose.

**Integrated is not the same as working — measured 2026-09-18.** The release
Android client fails its App Check exchange on the device
(`FirebaseContextProvider: Error getting App Check token`) and sends an
undecodable token on every call, which the backend logs as `Decoding App
Check token failed`; `playintegrity.googleapis.com` is not enabled on
`yovoice-ec54a`. iOS and web are unproven rather than healthy: a *missing*
token produces no log line at all while enforcement is off, so silence in
Cloud Functions logs cannot be read as delivery — only Firebase Console →
App Check separates verified from unverified requests. A release **web**
build activates no provider whatsoever unless
`--dart-define=YOVOICE_WEB_RECAPTCHA_SITE_KEY=…` is supplied; without it the
app logs `Web App Check is not configured for this release build.` and
carries on, by design. Treat this section as describing the *integration*,
not a working attestation path, until
[Roadmap item 2](Roadmap.md#2-firebase-app-check-enforcement)'s blockers are
cleared.

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

## Stripe billing data boundary (source-ready; provider rollout disabled)

- `entitlements/{uid}` remains the owner-readable, server-written access
  projection. `plan` is `monthly` or `yearly`; `currentPeriodEnd` is the exact
  paid access boundary. `renewalBehavior` is `renews` for an active recurring
  card/PayPal subscription and `ends` after recurring cancel-at-period-end.
  Prepaid BLIK uses `source=stripe_prepaid` and `renewalBehavior=none`; the
  active plan plus `currentPeriodEnd` still expose its exact paid window without
  implying a future provider charge.
- Moderator preview is not stored in this collection. Active exact
  `moderator`/`superModerator` roles derive an independent product overlay;
  acting operations require claim–mirror equality and public/background
  projections use only the client-immutable role mirror. Demotion removes the
  overlay without changing any paid plan, period, receipt or provider source.
- `billingAccounts/{uid}` is the canonical Firebase uid ↔ Stripe Customer
  binding. It stores either the recurring Subscription lifecycle or the
  verified one-time Checkout/Payment references needed to reconcile a 30-day
  PLN 26 or 365-day PLN 260 BLIK grant. Pending Checkout recovery is bound to
  both plan and payment method so a retry cannot silently change the purchase.
- `billingRateLimits/{uid_action}`, `billingCheckoutLocks/{uid}` and
  `stripeWebhookEvents/{eventId}` are operational anti-abuse/idempotency state.
  The event receipt is the replay boundary for both Subscription/Invoice and
  one-time BLIK events.
- `stripeCustomerCleanup/{attemptId}` records pre-provider Customer creation
  intent and any orphan cleanup/manual-review state, closing the account-delete
  race without exposing provider identifiers to clients.
- Firestore Rules deny every client read and write to all five operational
  collections. Only Admin SDK Functions access them. The public user document
  carries only the existing cosmetic Premium mirror, never Price, payment,
  Customer, PayPal or BLIK details.

No access write is authorized by `?checkout=success`, client metadata or a
client-submitted payment method. The signed webhook and canonical provider
state must commit billing, entitlement and event receipt together. No new
composite index is required for this source change; the existing rules denial
coverage remains mandatory. The secret-free catalog callable was deployed on
2026-08-28 and returns `checkoutAvailable=false`. Provider objects, mutation
handlers and checkout entry points are not live until the ordered rollout in
DEPLOYMENT.md is completed.

## Profile visibility (source only; not deployed)

The canonical preference is the private `users/{uid}.profileVisibility` field;
it is not accepted by any client create/update allowlist. The
`setMyProfileVisibility` callable writes it and revokes incompatible marketing
consent. `publicProfiles/{uid}` remains the minimal projection, but its exact-id
read rule re-checks active source state, visibility, blocks and—when set to
`friends`—both `friendshipGuards` rows. `privateShowcaseControl/live` is an
Admin-only monotonic generation used to reject stale website publication.
