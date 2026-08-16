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
- **Roles live in Auth custom claims, never in a Firestore document.**
  This is the single most load-bearing security decision in the project:
  a user can always write their own `users/{uid}` document (that's how
  profile editing works), but a user can never write their own auth
  token. If role checks ever read from Firestore instead of custom
  claims, self-granting `role: 'superAdmin'` would be a one-line write
  away from any client. Every admin Cloud Function calls a shared
  `requireRole()` helper that reads the claim, not the document — see
  [Backend.md](Backend.md#admin).

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

New friend requests and conversations copy no email field; compatibility
parsers tolerate legacy documents without using email as visible identity. A
bounded, resumable, aggregate-only scrub removes historical request emails,
empties conversation email snapshots and replaces follow edges with their
exact schema. See
[ADR-054](Decisions.md#adr-054-private-account-records-are-split-from-exact-server-owned-public-profiles).

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

## Current status

**No known critical open vulnerabilities.** A full audit found 13 issues
(3 critical, 3 high, 6 medium, 1 client/server contract bug); 12 are
fixed, verified directly against current `firestore.rules`,
`storage.rules`, and `functions/` — not assumed from the audit's own
"fixed" claims. Only App Check enforcement remains open, deliberately.
Live-updated detail: [Bugs.md](Bugs.md#security). Full historical audit,
findings, and the exact fix for each: [Archive/SECURITY_AUDIT.md](Archive/SECURITY_AUDIT.md).

## If you find a security issue

This is currently a solo project with no formal disclosure program.
Report anything you find directly to the maintainer
(`kamil.piotr.jaguszewski@gmail.com`) rather than opening a public issue —
the same practice any project handling real user data should follow,
scaled to this project's actual size rather than a boilerplate policy no
one would act on. See [CONTRIBUTING.md](CONTRIBUTING.md) for what this
looks like if the project ever gains outside contributors.

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
