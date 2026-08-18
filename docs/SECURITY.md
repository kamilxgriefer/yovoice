# Security

The security model as a whole — what enforces what, the principles this
project has learned to hold itself to (some of them the hard way), and
where to find current status versus historical record. For the day-to-day
mechanics (rules syntax, schema, testing commands), see
[Firebase.md](Firebase.md) and [TESTING.md](TESTING.md); this file is the
model and the reasoning that tie those mechanics together.

## The model in one sentence

Firestore Security Rules are this app's entire authorization layer —
there is no API server standing between a client and the database — so a
bug in a rule is not a bug in one feature, it's a bug in the authorization
system itself. Everything else in this document follows from taking that
sentence seriously. See
[ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work)
for why this architecture was chosen anyway.

## Identity and roles

- **Identity**: Firebase Authentication, shared across the Flutter app and
  `yovoice-website` via the `auth.yovoice.app` domain — one account, one
  identity, everywhere. See
  [Architecture.md](Architecture.md#authentication-flow) for the full
  sign-up → verify → claim flow.
- **Email verification is a real gate**, not a UI nicety:
  `request.auth.token.email_verified` is checked directly in Firestore
  rules and Cloud Functions before allowing outbound/content-creation
  actions (posting, creating rooms/clubs/moments, admin bootstrap).
- **Two-factor authentication uses Firebase TOTP, not an app-owned secret or
  SMS code.** Enrollment and sign-in assertions are created by the Firebase
  Auth SDK. The app keeps an enrollment secret only in memory until setup is
  completed or cancelled, never writes it to Firestore/Storage/logs, and
  requires recent primary authentication when Firebase requests it. Project
  MFA stays disabled until both compatible sign-in clients can be rolled out
  together.
- **Roles live in Auth custom claims, never in a Firestore document.**
  This is the single most load-bearing security decision in the project:
  a user can always write their own `users/{uid}` document (that's how
  profile editing works), but a user can never write their own auth
  token. If role checks ever read from Firestore instead of custom
  claims, self-granting `role: 'superAdmin'` would be a one-line write
  away from any client. Every admin Cloud Function calls a shared
  `requireRole()` helper that reads the claim, not the document — see
  [Backend.md](Backend.md#admin).
- **An established display name is server authority.** Clients may seed an
  initial name, but Firestore Rules deny every later direct change and deny all
  client writes to `displayNameChangedAt`. `updateMyDisplayName` requires
  `email_verified == true`, an active private account document and one exact
  input field, then enforces the 30-day boundary in a transaction. A malformed
  server cooldown fails closed instead of resetting the window. Same-name
  replay is the only cooldown bypass and is deliberately idempotent so it can
  repair a transient Firebase Auth mirror failure without granting another
  change. The Auth sync reads first and writes only on mismatch, limiting the
  amplification surface while callable App Check enforcement remains off. A
  separate private transactional fixed-window quota additionally stops locally
  valid, profile-reaching requests after 10 per uid per server minute. It
  commits before any profile/Auth read, so a later cooldown or integrity
  refusal is not a free request; the counter is not client-readable or
  writable.
- **A client-authored display-name snapshot must match the private canonical
  profile.** Broadcast hand raises and Family check-ins are attributed by
  `request.auth.uid`, but uid pinning alone did not prevent a modified or stale
  client from supplying another display name. Their create rules now require
  exact equality with `users/{uid}.displayName`, an exact document schema and
  `createdAt == request.time`; the app reads that canonical field before the
  write. No Firebase Auth display-name fallback is accepted.

## Firestore Security Rules — design principles

These aren't abstract best practices; each one maps to a specific incident
in [Decisions.md](Decisions.md) where violating it caused a real,
production-shipped bug:

1. **Never trust a permission, role, or ownership claim the request itself
   carries.** Check it against a document the requester doesn't control.
   This is [ADR-003](Decisions.md#adr-003-security-fixes-move-permission-authority-to-the-server)
   — the pattern behind nearly every finding in the original security
   audit ([Archive/SECURITY_AUDIT.md](Archive/SECURITY_AUDIT.md)).
2. **`hasOnly()` restricts which fields change, not whether the new values
   are true.** A field-allowlist alone doesn't stop someone from writing a
   *false* value into an allowed field (`likeCount: 999999`) — that needs
   value-level validation (matching a real transaction, or an
   `existsAfter()`/`getAfter()` check against a document they don't
   control), not just a narrower field list.
3. **A `collectionGroup()` query needs a top-level rule the query's own
   filter can prove — full stop.** A nested `match /parent/{id}/collection/{doc}`
   rule, no matter how correct, cannot authorize a `collectionGroup()`
   query spanning that collection name across every parent. See
   [ADR-005](Decisions.md#adr-005-roomsroomidmembers-renamed-to-roommembers)
   and [ADR-006](Decisions.md#adr-006-top-level-collectiongroup-wildcard-rules-stay-read-only-and-narrow)
   for the incident this came from and how narrowly the fix was scoped.
   **Getting the top-level rule wrong fails OPEN, not closed.** OR-ing any
   caller-scoped clause (`|| exists(/databases/$(database)/documents/users/$(request.auth.uid))`)
   into a top-level wildcard makes it a tautology for the query, and the
   query then returns every document in that collection group across the
   entire database rather than being rejected — verified on the emulator
   2026-08-16. So the narrowness of those two wildcard rules is a live
   containment boundary, not housekeeping. Never widen one to "let staff
   read these too"; give staff a callable instead.
4. **Two collections should never share a subcollection name unless
   they're actually related.** A coincidental name collision
   (`rooms/{id}/members` and `clubs/{id}/members`, unrelated in every way
   except the string `members`) constrains what rules can safely express
   for *either* one. Check this before naming a new subcollection.
5. **Test every rule with the access pattern the app actually uses**, not
   just the easiest one to write a test for. See
   [ADR-007](Decisions.md#adr-007-firestore-rules-changes-are-always-emulator-tested-against-a-real-collectiongroup-query) —
   a rule that only gets `getDoc()`-tested but is actually reached via
   `collectionGroup()` in the app is untested, no matter how green the
   suite looks.
6. **`diff().affectedKeys()` reports only fields whose *value* changed —
   it is not "fields present in the request."** So any guard gated on
   `affectedKeys().hasAny([...])` is silently skippable two ways: omit the
   field entirely, or resend the value already stored. This is how club
   role attribution was forgeable until `2fc05e5` — a promotion could
   carry a `roleUpdatedBy` naming someone else, or none at all, and the
   attribution guard simply never fired. **Require attribution
   unconditionally whenever the attributed thing changes, and check it
   against the post-write document (`getAfter()`/`request.resource`), not
   against the diff.** Discovered 2026-08-16.
7. **Every membership-shaped write needs a field allowlist, including the
   ones that look self-scoped.** `roomMembers` update had none, so a host
   could repoint their own membership row at a victim's uid. The victim's
   `collectionGroup` query then returned a row whose room they cannot
   read, and `Future.wait` in `watchMyCommunities()` emptied their entire
   Communities tab — permanently, remotely, and with no action available
   to the victim. Writes are now limited to `displayName`, `photoUrl` and
   `updatedAt`, with `userId`, `role` and `joinedAt` pinned. The
   generalizable part: **a rule that lets a caller write an identity field
   on a row that another query keys off is a way to corrupt someone
   else's client, not just their data.** Fixed 2026-08-16 (`2fc05e5`).
8. **A rule can delete a row; it cannot complete a moderation action.** A
   rules-level "host evicts member" removed a roster row and nothing else
   — the evicted account stayed connected to the live audio, kept chat
   through `isRoomParticipant`, and could rejoin a public room
   immediately. Worse, gating the delete on a counter the host can also
   write created a starvation primitive. Removal in full belongs in a
   callable. See
   [ADR-056](Decisions.md#adr-056-a-moderation-action-belongs-in-a-callable-that-completes-the-whole-removal-not-in-a-rule-that-deletes-one-row).
9. **A branch selector is an authorization condition, and it does not
   inherit the checks the branch's helpers perform.** The room-root update
   rule chose its host branch on `resource.data.hostId == request.auth.uid`
   alone, while `isRoomHost()` — used elsewhere — did check account status.
   The rule therefore *looked* status-aware anywhere a reader followed the
   helper, and was not on the path that mattered: a banned or disabled host
   could edit room metadata and start voice. **When identity selects a
   branch, re-state the status requirement inside the branch; do not rely
   on a sibling helper's diligence.** A corollary from the same fix:
   `isRestrictedAccount()` reads `banned` only and returns **false when the
   account document does not exist**, so gating on it silently admits
   disabled accounts — a helper that fails open on an absent document is a
   different check from the one its name implies. Fixed 2026-08-17
   (`c75720a`), deployed and verified by diffing the live ruleset source.

Full schema and the exact current rules structure: [Firebase.md](Firebase.md).

## Storage rules

Four upload paths (profile photos, room images, club images, Voice
Moments audio), each size- and content-type-limited. Uploads tied to
content shown to other users require `email_verified`; profile photos are
deliberately exempt, since setting one during onboarding — before
verification completes — is normal, expected behavior, not a gap. Full
table in [Firebase.md](Firebase.md#storage).

## Secrets

LiveKit's API key and secret are Google Secret Manager secrets
(`defineSecret()` in `functions/livekit/token.js`) — never committed to
the repo, never sent to a client. `LIVEKIT_URL` is a plain `defineString`,
not a secret, since it's just the public WebSocket endpoint every client
needs to connect (equivalent to a hostname, not a credential). No other
Cloud Function in this project currently holds a secret — see
[Backend.md](Backend.md) for the full function inventory.

## Firebase App Check

Integrated client-side; **enforcement is deliberately off** on every Cloud
Function today (`enforceAppCheck: false`). This means a script holding a
valid Firebase Auth ID token — obtained however, not necessarily through a
real instance of this app — can currently call any Cloud Function without
proving it's a genuine client. This is a real, accepted, currently-open
gap, not an oversight: see
[ADR-004](Decisions.md#adr-004-firebase-app-check-integrated-client-side-enforcement-deliberately-off)
for why enforcement needs a monitoring period before it's safe to flip,
and [Bugs.md](Bugs.md#security) for current status.

**What this gap does and doesn't affect**: App Check raises the cost of
casual backend abuse. It does not gate anything that Firestore rules and
each Cloud Function's own authorization checks (principle 1, above)
don't already gate — those remain the actual authorization boundary
regardless of App Check's status.

## Private account records and public profiles

`users/{uid}` is private account state, not a public profile API. It mixes
email, notification preferences, presence, moderation/ban state, staff mirrors
and operational counters with editable profile fields. Firestore authorizes an
entire document, so hiding fields after a foreign read in Flutter would already
be a data leak. Current rules therefore permit a client to get only its own
root user document and deny every list/query, including moderator and
super-admin client sessions. Owner/staff account management uses protected
callables that select an explicit response schema.

Public identity is projected by the retryable `onUserPrivacySourceChanged`
trigger into two server-owned documents:

- `publicProfiles/{uid}`: exact public identity/profile/count fields; known-id
  get for active authenticated accounts, no list and no client write;
- `socialPresence/{uid}`: online/last-seen only; known-id get for self or when
  both server-owned `friendshipGuards` exist, no list and no client write.

The trigger re-reads current source state, replaces rather than merges, deletes
both projections for banned/disabled/deleted accounts and is idempotent under
retry/out-of-order delivery. The Auth deletion trigger also retires every
identity projection and marks a lingering private record inactive. Both the
trigger and the bounded backfill check Firebase Auth, so a Firestore orphan
cannot republish a deleted Auth identity. Rules also recheck the private
target's active state, so a stale projection is denied during the trigger's
short consistency window. UIDs are treated as opaque, case-sensitive values
and are never normalized into an alias.

Ordinary discovery goes through `searchPublicProfiles`: verified-account-only,
bounded name/username prefixes, blocks filtered in both directions, active
candidates rechecked, and a five-field response allowlist. Email search exists
only in the protected-owner staff directory. That directory derives email from
Auth only and exposes a staff role only when the Auth claim agrees with the
server-owned role mirror. App Check is not enforced yet, so each search attempt
consumes an Admin-only transactional budget before querying (30/minute,
300/hour per authenticated uid).

Friendship authority is a pair of server-owned `friendshipGuards`, created in
the same transaction as canonical request acceptance and removed atomically on
unfriend or block. Client-writable historical friend mirrors never mint a
guard. Every social mutation/read consumes a private transactional rate budget,
graph degree and pending/block collections have hard caps, and every bounded
read requests `MAX + 1` so an oversized graph fails closed instead of silently
truncating authority. Follow edges contain only uid and server time; display
identity is resolved from the current public projection and inactive endpoints
are denied.

## Direct-message privacy

The recipient, not the sender or client UI, controls new direct-message
delivery. `users/{uid}.messagePrivacy` accepts `everyone`,
`peopleYouFollow`, `friends`, or `nobody`; absence is a backwards-compatible
Everyone default and every unknown value fails closed. The follow mode reads
the recipient's server-owned following edge. Friends requires both canonical
friendship guards, so a stranded half or forged legacy mirror grants nothing.

Functions enforce the preference when a conversation opens and again for each
text send, media reservation, and media finalization. This closes the existing
conversation and reserve-before-change bypasses. Firestore Rules mirror the
check on the legacy message-create path, and owner writes are allowlisted to
the exact enum. Blocks, account state, email verification, and sanctions are
still checked independently and can only narrow access. History, reactions,
read receipts, edits, and deletes are intentionally not revoked by a new inbox
preference.

New friend requests and conversations copy no email field; compatibility
parsers tolerate legacy documents without using email as visible identity. A
bounded, resumable, aggregate-only scrub removes historical request emails,
empties conversation email snapshots and replaces follow edges with their
exact schema. See
[ADR-054](Decisions.md#adr-054-private-account-records-are-split-from-exact-server-owned-public-profiles).

**Fully live as of 2026-08-16.** Rules, triggers, callables, client,
projection backfill and identity scrub are all deployed and run — the
sequence completed 5/5. The backfill created 14 projections (28 writes)
and a verification re-run planned zero; the scrub cleared 21 documents
across four phases with zero conflicts, likewise verified by a re-run.

Two things from that run belong in a security document rather than only
an operational one.

**The scrub is a security step with an ordering constraint, not
cleanup.** It ran after the rules deploy, which was the wrong way round.
The new rules require a follow edge to carry exactly `['uid','followedAt']`,
and Firestore evaluates list rules **per document**, denying the entire
query if any single document fails. So one unscrubbed legacy edge emptied
a user's whole followers/following list. Any future exact-schema rule has
the same shape: the data must conform *before* the rule lands, or the
rule is an outage rather than a boundary.

**The CI credential boundary was deliberately not widened.** A GitHub
Actions path for the backfill (`4f9ad47`) was dispatched and failed with
`7 PERMISSION_DENIED` — the `FIREBASE_SERVICE_ACCOUNT_YOVOICE_EC54A`
secret is scoped to Hosting. Granting it Firestore access would have
meant anyone with repository write access could reach all production data
through a secret that today reaches only Hosting. The backfill ran from
operator-local Application Default Credentials instead. **Treat that
workflow as present but non-functional**, and treat the temptation to
"just add the role" as the security decision it is. Tracked in
[Bugs.md](Bugs.md#data-integrity).

This is a fail-closed gap, not a leak: an account with no projection is
unreadable, not over-readable. It is still a real product defect.

## Global Chat (public write surface)

`globalChat/main/messages` is the product's only surface where one
member's write is read by every other member, so it is worth stating its
model in one place. Full reasoning:
[ADR-037](Decisions.md#adr-037-global-chat-is-one-canonical-public-channel-written-directly-under-security-rules-with-a-rules-enforced-rate-limit).

- **Reads**: any signed-in account whose `users/{uid}.banned` is not
  true. `request.auth != null` is deliberately NOT sufficient: disabling
  an account in Firebase Auth stops it minting new ID tokens, but a
  token already issued stays cryptographically valid until it expires
  (up to an hour), during which `isSignedIn()` still passes. Reading the
  account-status document makes a ban effective on the very next
  request. `setUserBan` additionally calls `revokeRefreshTokens`, so the
  session cannot be renewed. The field is written only by the Admin SDK
  and is absent from the self-write allowlist on `users/{userId}`, so
  the affected account can neither set nor clear it.
- **Writes**: rules-enforced direct writes, no Cloud Function. The
  sender must have a **verified email** (`isVerified()`, i.e.
  `request.auth.token.email_verified` — the ID token's own claim, not a
  profile field), the same gate DMs, rooms, clubs and Moments already
  use. `senderId` must equal the caller's uid, `sentAt` must equal
  `request.time`, `senderName`/`senderIsCreator` must match the caller's
  own `users/{uid}` document, `senderIsStaff` must match the ID token's
  `role` claim, content must be non-blank after `trim()` and ≤ 500
  characters, and the document must carry exactly the allowed keys.
- **Rate limit**: two limits, both enforced in rules against
  `request.time`. Every send is a batch of the message plus
  `globalChat/main/senders/{uid}`; the message rule verifies that
  document post-commit with `getAfter()`, and the sender-document rule
  refuses to advance it unless **3 s** have elapsed since the last
  message **and** the current one-hour window holds fewer than **200**
  messages. The 3 s floor alone would still permit 1,200 an hour from
  one valid account; the window is what caps that. Binding the state to
  a specific `lastMessageId` is what stops one update authorising a
  whole batch. The state document cannot be deleted, reset or read by
  anyone else.
- **Reports**: `reports/{reportId}` uses a deterministic id
  (`{reporterId}_{targetType}_{targetId}`), so a duplicate is a create
  over an existing document and fails without a counter or a query. The
  reported message or account must exist and `reportedUserId` must be
  its real owner; `reason` is a closed enum; the note is capped at 300
  characters; workflow fields are not accepted on create; and
  `reportLimits/{uid}` enforces 30 s between reports and 20 per fixed
  24-hour window with the same batched-state mechanism. Reporting is
  deliberately NOT gated on email verification: it is a safety action and
  follows the blocking precedent, not the publishing one.
- **Deletion**: soft only, author or `role`-claim moderator, content and
  authorship frozen. Hard delete is `if false` for everyone; the Admin
  SDK remains the only way to purge.
- **Audit**: `onGlobalMessageModerated` writes an `adminAuditLogs` entry
  whenever the remover is not the author.
- **Reports**: `reports` is create-only for verified members with their
  own uid and a server timestamp; members cannot read, edit or delete
  reports, including their own.
- **Blocking is NOT a read boundary.** Global Chat content is public to
  every active authenticated account. Firestore returns every message in
  the channel to every such reader, including messages from accounts
  that reader has blocked; `GlobalChatService` exposes the block list
  separately and the panel filters those senders out of the rendered
  list, holding the first paint until the list has resolved so nothing
  flashes. That is a local UI filter for the blocker's comfort, not
  per-recipient confidentiality — and it is one-directional: an account
  that blocked you can still read your public messages. Anyone reading
  the channel through the SDK directly sees everything.
- **Known limits**: the blocking behaviour above, rate limits that are a
  floor rather than abuse prevention, and report triage with no UI. See
  [Bugs.md](Bugs.md#moderation--safety).

## Staff moderation (privileged surface)

The Moderation Center reads `reports` and mutates them through one
callable. Full reasoning:
[ADR-039](Decisions.md#adr-039-the-moderation-center-is-a-staff-gated-more-destination-triage-is-a-callable-and-staff-authority-is-claim--server-record).

- **Who is staff**: `isActiveStaff()` requires ALL THREE — the signed
  `role` custom claim in `['moderator','admin','superAdmin']`, the same
  value in the server-written `users/{uid}.role` mirror, and
  `banned != true`. `assignUserRole` writes both the claim and the
  mirror; `role` is absent from the self-write allowlist, so no account
  can promote itself.
- **Why both**: the claim cannot be forged but can be an hour stale, so
  a revoked moderator would keep access until their token expired. The
  document is written synchronously on revocation, so the next request
  fails. Requiring both also means a freshly promoted moderator fails
  CLOSED until their claim refreshes.
- **Reads**: `reports` is readable only by active staff. Ordinary users —
  including a reporter reading their own report — are denied.
- **Writes**: `allow update, delete: if false` on `reports` for
  everyone. Triage goes through `moderateReport`, which re-checks the
  full staff test server-side, validates the report id and action,
  enforces `open → inReview → resolved|dismissed`, refuses to overwrite
  another moderator's active claim (`aborted`), is idempotent on a
  caller-supplied `requestId`, sets the acting uid and all timestamps
  server-side, and never touches reporter-created evidence.
- **Content removal** reuses the Global Chat soft-delete: the message is
  never hard-deleted, authorship survives, and the removal happens in
  the same transaction that resolves the report.
- **Banning is admin-only** and unchanged — `setUserBan` is gated to
  `requireUserManager` (admin/superAdmin). Moderators are shown an
  escalation note rather than an action that would be refused.
- **Audit**: `adminAuditLogs` is `if false` for every client — that has
  not changed and must not. Report actions write
  `report_{reportId}_{requestId}`; message removals write
  `globalMessage_{eventId}` from the existing trigger. Both ids are
  deterministic, so retries overwrite rather than duplicate.
- **Reading the audit trail** goes through `listReportAuditTrail`, and
  only that. It re-checks the same three-part staff test as every other
  moderation path (signed claim + server-written `users/{uid}.role`
  mirror + not banned), then answers one question: what happened to this
  report and to the message it is about. The client supplies a report
  id; **both target ids are read from the report document server-side**,
  so no argument exists that could point it at another report or at an
  unrelated admin action. The response is a field allowlist — id, kind,
  action, actorId, actorName (public display name only), actorRole,
  previous/new status, resolution, note, contentRemoved, removedContent,
  createdAt — with strings capped at 500 characters. No email, no
  provider data, no raw document, no unrelated `details` keys.
  `listAdminAuditLogs`, which lists the whole collection with free-text
  search and returns `actor.email`, was deliberately **not** reused and
  **not** widened; see
  [ADR-040](Decisions.md#adr-040-a-reports-audit-trail-is-served-by-a-scoped-callable-not-by-the-admin-audit-browser-queue-filters-are-server-side-clauses).
- **Privacy**: the panel shows only public profile fields
  (display name, avatar). No email, phone, provider data or internal
  field is read. The reporter's identity is not shown to the reported
  account or any ordinary client — reports are unreadable outside staff.

## Social notification integrity

`friendRequest`, `friendAccepted` and `follow` are no longer in the
client-creatable notification type list. They are written by
`onFriendRequestCreated`, `onFriendRequestResolved` and
`onFollowerCreated` through the Admin SDK, from the authoritative source
documents (ADR-041).

What that closes: a client used to be able to write "X accepted your
friend request" into someone's inbox with no friendship existing
anywhere. Rules cannot check that — the relationship is a different
document, and a create rule that reads it still cannot know which side
accepted. The trigger reads the friendship directly, so the claim is
verified rather than asserted.

Recipient, actor, type and timestamp now all come from the document path
and the server clock; none is caller-supplied. Only public profile
fields (display name, photo) enter the payload — a Functions test
asserts the exact key set and that no email, phone, role or preference
data appears. Recipients may still only change `isRead`/`readAt`, and
`fcmTokens` remain owner-scoped.

## Room and club membership authority (hardened 2026-08-16)

Room deletion has two deliberately separate authorities. A room owner uses
`deleteRoomSelf`; the callable reads the canonical room and requires
`room.hostId == request.auth.uid`, so displaying or forging the owner menu does
not grant deletion of somebody else's room. Permanent deletion of an arbitrary
room uses `adminDeleteRoom`, which requires an active, matching Auth-claim and
server role in `['superModerator', 'superAdmin']` and writes the existing audit
trail. A regular `moderator` cannot use that path. Mobile and desktop both
render from the same server-derived capability, but UI visibility is never the
authorization boundary. See ADR-075.

`isRoomMember()` now requires `isActiveAccount()`, matching
`isActiveClubRoomMember()`. Before `2fc05e5` it required only
`isSignedIn()`, so widening `canAccessRoom()` to include members handed
private rooms, their rosters and their participant lists to banned and
disabled accounts. This also withdraws room chat and voice-start from
suspended accounts, which is the point: **a suspension that stops at the
Club lounge door but not the Community room door is not a suspension.**

Club manager role updates are allowlisted to `role`, `roleUpdatedAt` and
`roleUpdatedBy`, with `roleUpdatedBy` pinned to the acting uid and both
timestamps pinned to `request.time`. Attribution is required
unconditionally whenever `role` changes (principle 6 above). An unknown
role string no longer falls through `clubRolePower`'s else branch.

Room membership rows can be created and self-deleted, never
host-deleted — see principle 8 and
[ADR-056](Decisions.md#adr-056-a-moderation-action-belongs-in-a-callable-that-completes-the-whole-removal-not-in-a-rule-that-deletes-one-row).

The banned-host gap that stood here is **closed and deployed** as of
2026-08-17 (`c75720a`): the host room-update branch,
`isHostAdmittedRoomParticipant()`, `roomMembers` create and message
reaction updates all require `isActiveAccount()`. Rules suite 310 passed /
8 failed → 318 passed / 0 failed; the deployed ruleset source was read back
and diffed byte-for-byte against `firestore.rules` at HEAD. The design
principle it produced is principle 9 above.

### Still open, pre-existing, live in production

**"Every write behind `canAccessRoom()` is now gated" is false.** Two
remain, and stating it plainly here is the point — the claim was made and
is wrong:

- **`roomMembers` update** lets a banned account rewrite `displayName` and
  `photoUrl` on its own roster row, **including a blind write into a
  private room it can no longer read**, with no type or length check on
  either field.
- **`participants` update** lets a banned account un-mute itself and raise
  its hand.

Neither escalates privilege, and neither bypasses audio: LiveKit will not
issue a token to a suspended account, so an un-muted `participants` row is
a flag on a document, not a voice in a room. What makes them worth closing
is the *cost*, not the risk — **no client issues either write**, so gating
them carries zero trap risk, which is the opposite of the eviction rule
that had to be removed wholesale in `952d8e4`. Tracked as
[Roadmap 0k](Roadmap.md#0k-gate-the-last-two-writes-behind-canaccessroom).

Also found during the same pass and **not a security defect**, but live:
every non-host room message raises an unhandled permission-denied after
the message has landed, because `sendRoomMessage()` bumps the room root's
`updatedAt` and the non-host branch accepts no such transition. Room
ordering on Home never advances from non-host conversation. See
[Bugs.md](Bugs.md#security) and
[Roadmap 0l](Roadmap.md#0l-non-host-room-messages-always-throw-after-the-message-lands).

## Current status

**No known open privilege-escalation gap.** What remains behind
`canAccessRoom()` are the two non-escalating ungated writes directly above,
plus App Check enforcement, which stays off deliberately. A full audit
found 13 issues (3 critical, 3 high, 6 medium, 1 client/server contract
bug); 12 are fixed, verified directly against current `firestore.rules`,
`storage.rules`, and `functions/` — not assumed from the audit's own
"fixed" claims.

**Deployment status, 2026-08-18**: the hardened `firestore.rules` and
`storage.rules` are **live in production**. `firestore.rules` was deployed
twice on 2026-08-16 — 20:40 by the operator and 21:06 covering `952d8e4` —
and again on 2026-08-17 covering `c75720a`. Until this date, both this file
and [Bugs.md](Bugs.md) described the 2026-08-16 fixes as "FIXED IN SOURCE,
PENDING RULES DEPLOY"; that is no longer true and those markers have been
cleared.

The Storage rules' Firestore lookups also require production IAM state that is
not contained in either rules file. On 2026-08-18 the missing
`roles/firebaserules.firestoreServiceAgent` grant on the Google-managed
Firebase Storage service agent was restored after real uploads reproduced a
403 while the emulator suite remained green. The binding grants only
`datastore.entities.get`; it must never be replaced by a broad database role
or by weakening upload authorization. The mandatory verification and smoke
test are in [DEPLOYMENT.md](DEPLOYMENT.md#storage-rules-manual).

**Corrected 2026-08-17 — the deployed ruleset is readable, so stop
treating the Console as the only evidence.** This section previously said
the Console's version history "remains the only way to read the deployed
ruleset (there is still no read-only CLI command)". The Firebase Rules API
returns the released ruleset's full source; the `c75720a` deploy was
verified by fetching it and diffing byte-for-byte against the repository.
A version-history timestamp proves *a* deploy happened. A diff proves
**which bytes** are enforcing. For an authorization layer, only the second
is evidence. Commands in
[DEPLOYMENT.md](DEPLOYMENT.md#reading-the-deployed-ruleset-the-verification-standard).

Live-updated detail: [Bugs.md](Bugs.md#security). Full historical audit,
findings, and the exact fix for each: [Archive/SECURITY_AUDIT.md](Archive/SECURITY_AUDIT.md).

## Public website showcase boundary

The marketing site has no read path into account, presence, social-graph or
Club collections. A person or public Community Club appears only after its
owner creates an exact private consent document. A scheduled Admin publisher
rechecks Firebase Auth and canonical Firestore state, then writes one bounded,
short-lived `publicShowcase/live` document. Anonymous access is pinned to that
single id; list, sibling and client writes are denied.

Recent activity is deliberately labelled **Active recently**, not **Online
now**: the source is an explicitly consented, fresh client heartbeat and is
suppressed unless a minimum privacy cohort exists. Family Rooms, private
Clubs, staff identities, photos, usernames, identifiers, email, last-seen
timestamps and blocked-relationship data are never published. Consent is
revoked during Auth deletion, permanent Club deletion and both ownership
transfer paths so a recreated identity or a new owner cannot inherit an old
public grant.

## Creator pinned-post boundary

`creatorPinnedPosts/{creatorId}` is a server-owned, known-id projection, not a
public activity directory. Firestore denies collection queries and every
client write. An exact get requires an active reader, active non-deleted
Creator target, canonical Premium Creator entitlement and an exact document
shape bound to the path id. The callable accepts no caption, author, billing
field or URL from the client; it points only to an already-published canonical
Voice Moment owned by the caller. Entitlement, profile and Moment triggers
remove stale pointers, while rules independently fail closed during trigger
delay.

## If you find a security issue

This is currently a solo project with no formal disclosure program.
Report anything you find directly to the maintainer
(`kamil.piotr.jaguszewski@gmail.com`) rather than opening a public issue —
the same practice any project handling real user data should follow,
scaled to this project's actual size rather than a boilerplate policy no
one would act on. See [CONTRIBUTING.md](CONTRIBUTING.md) for what this
looks like if the project ever gains outside contributors.

## Stripe billing boundary (source only; not deployed)

The client selects only `monthly` or `yearly`; it cannot provide amount,
currency, Price, Customer, Firebase uid or return URL. Checkout and Portal use
fixed HTTPS destinations. A canonical server-created `billingAccounts/{uid}`
binding—not mutable Stripe metadata—owns the Customer. Provider secrets and all
operational billing collections are server-only.

Webhook acceptance requires Stripe signature, deployment livemode match,
validated immutable Prices and a paid latest Invoice for first activation.
Entitlement + billing + event receipt use one transaction, replay is absorbed,
and every transaction retry fetches current Stripe state so an older active
handler cannot resurrect canceled access. Checkout creation uses a lease plus a
persisted provider idempotency token and checks existing subscriptions. Portal
authorization deliberately permits the authenticated payer even when their app
account is suspended, so moderation cannot trap recurring charges.

Production deployment is fail-closed unless `yovoice-ec54a` uses `sk_live_`,
live Prices and live webhook events. App Check enforcement remains off pending
the project-wide monitored rollout; it is not treated as billing authorization.
Full refunds and newly-created disputes fail closed by canceling every
nonterminal canonical Customer subscription and revoking access. Partial
refunds preserve the current paid entitlement and create a private support
review audit; no financial or proration conclusion is inferred. Seller/VAT,
refund-money timing and B2B policy remain launch blockers.

## Profile visibility boundary (source only; not deployed)

Profile privacy is enforced from private `users/{uid}.profileVisibility`, never
from client-writable state or from the public projection alone. Missing legacy
state is public for compatibility; malformed state is private. Foreign known-id
reads require an active account, no inbound block and the visibility grant;
friends-only access requires two canonical server-owned guards. Collection
listing stays denied. Search applies the same checks server-side. Website
consent cannot override non-public app visibility, and a private Admin-only
generation prevents a stale publisher transaction from restoring removed data.
Existing conversation access is intentionally independent and reveals only the
participant label already stored on that authorised conversation.

## Checklist for new privileged write paths

Before shipping any new write path that grants a role, a permission, or
access to something another user controls:

- [ ] Does the rule (or Cloud Function) check the claim against a real,
      independently-controlled document — not just against the shape of
      the request?
- [ ] If it's a Cloud Function, does it actually need to be one (see
      [ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work)'s
      four conditions), or could a correctly-scoped rule do the same job
      with less latency and less code?
- [ ] If it involves a `collectionGroup()`-queried collection, is there a
      real `collectionGroup()` test for it, not just a direct-path one?
- [ ] Does a value-level check exist where a field's *truth*, not just its
      presence in an allowlist, matters (counters, roles, ownership)?
- [ ] Is a role or permission ever read from a Firestore document that the
      affected user (or an attacker impersonating them) could write? If
      so, that's a bug — move it to a custom claim or a
      Cloud-Function-computed value instead.
- [ ] Does the rule check **account status** (`isActiveAccount()`), not
      just signed-in-ness or ownership? A branch that selects on
      `resource.data.hostId == request.auth.uid` and stops there grants a
      banned account everything that ownership grants.
- [ ] Is any guard gated on `affectedKeys().hasAny([...])`? If so it is
      skippable by omission or by resending the stored value — see
      principle 6.
- [ ] Does every write path on the collection have a field allowlist,
      including the ones that look self-scoped? Ask specifically whether
      the caller can point an identity field at somebody else.
- [ ] If the rule gates on a counter, can the caller also **write** that
      counter? If yes, they can starve the gate. Prefer `existsAfter()` on
      the row itself over a counter transition.
- [ ] Does this write complete the whole action, or only part of it? If a
      rule deletes a row while live audio, chat and rejoin remain
      untouched, the action belongs in a callable (principle 8).
- [ ] Does the new query need a composite index, and has that index been
      **deployed** — not merely committed to `firestore.indexes.json`? The
      emulator does not require them, so no suite will tell you.
