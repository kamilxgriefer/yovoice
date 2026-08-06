# Decisions

Architecture Decision Records for YO Voice — the log of *why* the system
is shaped the way it is, not just what it currently looks like. Code shows
you the "what." This file exists because the "why" doesn't survive in code
at all — six months from now, nobody can tell from `firestore.rules` alone
whether a narrow rule was an oversight or a deliberate, hard-won fix for a
specific exploit. Read this before changing anything that looks
over-engineered or unnecessarily restrictive — there's a decent chance it
isn't.

## Format

Every ADR has four sections:

- **Context** — what situation forced a decision to be made.
- **Decision** — what was actually decided.
- **Reasoning** — why this option and not the obvious alternative.
- **Consequences** — what this makes easier, what it makes harder, and what
  it rules out. Every real decision has a cost; if a Consequences section
  reads as pure upside, look harder.

Numbered chronologically (ADR-001 is the oldest), so the numbers are stable
references — link to `Decisions.md#adr-005` from other docs, not to a
section title that might get reworded. When a decision is later reversed or
superseded, add a new ADR and mark the old one's status rather than
editing history away.

Dates come from `git log`, where the decision maps cleanly onto a commit.
A few predate careful commit hygiene, or belong to `yovoice-website`'s own
history (a separate repo) — those are marked **approximate** rather than
given a false-precision date.

## Index

| ADR                                                                                                     | Title                                                                                       | Status   | Date                                 |
| ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- | -------- | ------------------------------------ |
| [001](#adr-001-legacy-podcast-room-experience-stays-supported)                                          | Legacy `podcast` room experience stays supported                                            | Accepted | 2026-07-28                           |
| [002](#adr-002-git-workflow-push-straight-to-main-no-prs)                                               | Git workflow: push straight to `main`, no PRs                                               | Accepted | 2026-08-02                           |
| [003](#adr-003-security-fixes-move-permission-authority-to-the-server)                                  | Security fixes move permission authority to the server                                      | Accepted | 2026-08-02                           |
| [004](#adr-004-firebase-app-check-integrated-client-side-enforcement-deliberately-off)                  | Firebase App Check integrated client-side, enforcement deliberately off                     | Accepted | 2026-08-04                           |
| [005](#adr-005-roomsroomidmembers-renamed-to-roommembers)                                               | `rooms/{roomId}/members` renamed to `roomMembers`                                           | Accepted | 2026-08-04                           |
| [006](#adr-006-top-level-collectiongroup-wildcard-rules-stay-read-only-and-narrow)                      | Top-level `collectionGroup` wildcard rules stay read-only and narrow                        | Accepted | 2026-08-04                           |
| [007](#adr-007-firestore-rules-changes-are-always-emulator-tested-against-a-real-collectiongroup-query) | Firestore rules changes are always emulator-tested against a real `collectionGroup()` query | Accepted | 2026-08-04                           |
| [008](#adr-008-resend-smtp-instead-of-firebases-default-email-sender)                                   | Resend SMTP instead of Firebase's default email sender                                      | Accepted | 2026-08-04 (approximate)             |
| [009](#adr-009-next_public_app_url-as-an-env-var-website-repo)                                          | `NEXT_PUBLIC_APP_URL` as an env var (website repo)                                          | Accepted | 2026-08-04 (approximate)             |
| [010](#adr-010-real-per-achievement-unlock-timestamps)                                                  | Real per-achievement unlock timestamps                                                      | Accepted | 2026-08-06                           |
| [011](#adr-011-permission_handler-for-real-device-permission-status)                                    | `permission_handler` for real device-permission status                                      | Accepted | 2026-08-06                           |
| [012](#adr-012-coming-soon-instead-of-fabricated-data-or-dead-buttons)                                  | "Coming soon" instead of fabricated data or dead buttons                                    | Accepted | 2026-08-06                           |
| [013](#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work)       | Clients write Firestore directly; Cloud Functions are reserved for privileged work          | Accepted | Foundational — documented 2026-08-06 |
| [014](#adr-014-two-deployables-one-firebase-project)                                                    | Two deployables, one Firebase project                                                       | Accepted | Foundational — documented 2026-08-06 |
| [015](#adr-015-feature-based-folder-structure-over-layer-based)                                         | Feature-based folder structure over layer-based                                             | Accepted | Foundational — documented 2026-08-06 |
| [016](#adr-016-native-android-and-ios-window-chrome-is-pinned-dark-not-os-controlled)                   | Native Android and iOS window chrome is pinned dark, not OS-controlled                      | Accepted | 2026-08-06                           |
| [017](#adr-017-android-build-fixes-core-library-desugaring-and-drawable-resource-references)            | Android build fixes: core library desugaring and drawable resource references               | Accepted | 2026-08-07                           |
| [018](#adr-018-per-screen-firestore-streams-are-created-once-in-initstate-never-inline-in-build)         | Per-screen Firestore streams are created once in `initState`, never inline in `build()`      | Accepted | 2026-08-07                           |

---

## ADR-001: Legacy `podcast` room experience stays supported

**Status**: Accepted, still in effect
**Date**: 2026-07-28 (approximate — the rooms rebuild's "Stage 1"; see
[Archive/ROOMS_REBUILD_PLAN.md](Archive/ROOMS_REBUILD_PLAN.md))

### Context

Rooms originally had three experience types. The product simplified this
down to two — `community` and `broadcast` — and `BroadcastRoomScreen`
became the single entry point for what used to be a separate `podcast`
type. No migration of existing Firestore documents was ever run.

### Decision

`room_experience.dart` maps the legacy string `'podcast'` to
`RoomExperience.broadcast` when reading. New and updated rooms only ever
*write* `'community'` or `'broadcast'` — but reading `'podcast'` must keep
working indefinitely, until proven otherwise.

### Reasoning

Deleting a two-line compatibility branch is easy. Confirming zero
production documents still contain the old value is not — it needs a
Firestore Console query or `firebase-admin` access this project hasn't
reliably had (see [Bugs.md](Bugs.md#data-integrity)). Given that
asymmetry, keeping the mapping costs almost nothing and removing it
prematurely risks silently breaking any room a real user created before
the rename. When in doubt, the safer failure mode is "the old code path
still runs," not "the old data becomes unreadable."

### Consequences

`room_experience.dart` carries a permanent-feeling piece of legacy logic
that looks unnecessary to anyone who doesn't know the history — which is
exactly why this ADR exists. The mapping cannot be safely deleted until
someone actually confirms production has zero `'podcast'` documents (a
concrete, trackable task — see [Roadmap.md](Roadmap.md)), not just "seems
safe now." Until then, any code reading `experience` must go through the
mapping function rather than comparing the raw string.

---

## ADR-002: Git workflow: push straight to `main`, no PRs

**Status**: Accepted, still in effect
**Date**: 2026-08-02 (the PR merge — `66b64f4`, `75b64e0` — that prompted
the explicit preference)

### Context

A large mechanical refactor (splitting `broadcast_room_screen.dart` into a
`broadcast_room/` folder) was proposed and shipped through a feature
branch + pull request, the standard "safe" workflow for a multi-file
change. This is a solo project: one person writes the code, reviews the
code, and is the only stakeholder who needs to sign off on it.

### Decision

Commit and push directly to `main`, in both this repo and
`yovoice-website`. No feature branches, no PR ceremony, by default. Before
a change large enough to be risky, take a backup first — a local tag or
branch snapshot of `main` — rather than relying on a PR as the safety net.

### Reasoning

A PR's value is code review and a rollback point before merge. With a
single contributor, the review step is theater — there's no second set of
eyes it's actually gating. The rollback value is real but doesn't require
a PR; a tag or branch snapshot taken before a risky change gives the same
safety net with none of the process overhead. The user said so directly
after the PR-based refactor felt like unwanted ceremony.

### Consequences

Faster iteration, no merge-queue friction, no "waiting for my own
approval." The tradeoff is real and worth naming: `main` can be broken by
any single push, there's no forced review step to catch a mistake before
it's live, and this workflow stops making sense the moment a second
contributor joins — see [CONTRIBUTING.md](CONTRIBUTING.md) for what
changes then. `flutter analyze` passing and (for backend/rules changes)
the emulator test suite passing are the closest things this project has to
a pre-merge gate — treat them as non-negotiable precisely because there's
no human review backstopping them.

---

## ADR-003: Security fixes move permission authority to the server

**Status**: Accepted, still in effect
**Date**: 2026-08-02 (`55e8627`, `cea73d1`)

### Context

A full security audit ([Archive/SECURITY_AUDIT.md](Archive/SECURITY_AUDIT.md))
found a repeating failure shape across nearly every critical and high
finding: a write or a token request carried its own claimed permission —
`role: 'owner'` on a new club-member document, `canPublish: true` on a
LiveKit token request, `hostId: <my uid>` on a room update — and nothing
on the server actually checked that claim against reality. Firestore's
`hasOnly()` field-allowlisting restricts *which* fields a write can touch,
but says nothing about whether the *values* being written are true.

### Decision

Every finding was fixed by moving the authority for "what is this caller
actually allowed to do" onto the server: a Firestore rule that reads the
real, already-stored role or relationship via `exists()`/`get()`, or a
Cloud Function that looks up the caller's actual participant/member
document instead of trusting the request body.

### Reasoning

The alternative — trying to patch each exploit with a narrower field
allowlist — doesn't address the root cause and would need re-doing for
every new write path that can carry a permission claim. Checking against
a real, independently-controlled document (one the *target* of a
permission, not the requester, can write) closes the whole class of bug at
once. `createLiveKitToken` computing `canPublish` from the caller's actual
participant document (see [Backend.md](Backend.md)) is the reference
example: nothing about the caller's *request* influences their publish
permission — only the actual state of a document they don't control.

### Consequences

New write paths that grant a role, a capability, or a permission must be
designed with this pattern from the start — see
[SECURITY.md](SECURITY.md) for the checklist. It's more Firestore-rule
complexity (`exists()`/`get()` calls cost an extra read and add rule
verbosity) than a naive `hasOnly()` check, and Cloud Functions that used to
trust `request.data` now need an extra Firestore round-trip before acting.
That cost is the price of the fix, not a side effect to optimize away.
Status of every individual finding: [Bugs.md](Bugs.md#security) — 12 of
13 are closed; App Check enforcement (ADR-004) is the one still open,
tracked separately because it's a different kind of decision (a rollout
plan, not a bug).

---

## ADR-004: Firebase App Check integrated client-side, enforcement deliberately off

**Status**: Accepted, still in effect — revisit once token-delivery data exists
**Date**: 2026-08-04 (`0e18d24`)

### Context

Nothing prevented a script with a valid Firebase Auth token — obtained
however, not necessarily through this app — from calling this project's
Cloud Functions directly, bypassing the actual client entirely. App Check
exists specifically to attest that a request came from a genuine instance
of this app, not just from anyone holding a valid user token.

### Decision

Integrate `firebase_app_check` client-side
(`AndroidDebugProvider`/`AppleDebugProvider` in debug,
`AndroidPlayIntegrityProvider`/`AppleAppAttestWithDeviceCheckFallbackProvider`
in release), but leave `enforceAppCheck: false` on every Cloud Function.

### Reasoning

Enforcement is a one-line flag per function, but flipping it wrong (before
confirming real devices are actually attaching valid tokens) turns into an
outage: every request without one gets rejected, including from
legitimate users on a platform/App Check-provider combination that isn't
working yet. Firebase Console → App Check has real token-delivery metrics
that only exist *after* the client-side integration has been live for a
while. Shipping the integration first and watching that data before
flipping enforcement turns a risky one-shot flag into a monitored rollout.

### Consequences

Right now, any script holding a valid Firebase Auth ID token can call
every Cloud Function in this project without App Check attesting it came
from the real app — see [Bugs.md](Bugs.md#security) and
[SECURITY.md](SECURITY.md#app-check). This is a real, currently-accepted
gap, not a false negative in this document: it raises the cost of casual
backend abuse but does not by itself gate anything Firestore rules and
Cloud Function authorization checks (ADR-003) don't already gate. The
follow-up task (monitor token delivery, then flip enforcement
function-by-function) is tracked in [Roadmap.md](Roadmap.md) and should
not be forgotten just because it isn't urgent.

---

## ADR-005: `rooms/{roomId}/members` renamed to `roomMembers`

**Status**: Accepted, still in effect
**Date**: 2026-08-04 (`e620582`)

### Context

`RoomService.watchMyCommunities()` and `ClubService.watchMyClubInvites()`
were broken in production for every user, silently. Root cause: a
`collectionGroup()` query needs a **top-level**
`match /{path=**}/collection/{doc}` rule that Firestore can prove from the
query's own filter — a nested `match /parent/{id}/collection/{doc}` rule
only ever authorizes reads scoped to one specific, already-known parent,
and does not make that collection name queryable via `collectionGroup()`
at all. `rooms/{roomId}/members` and `clubs/{clubId}/members` happened to
share the collection name `members`, purely coincidentally — they were
never related. `clubs/{clubId}/members` legitimately needs a more
permissive, `exists()`-based rule for its own roster-browsing use case,
which can't satisfy `collectionGroup()`'s provability requirement (see
ADR-006). Any top-level wildcard rule written to unblock the rooms query
would have had to somehow also satisfy — or accidentally widen — the
clubs one.

### Decision

Rename the rooms subcollection to `roomMembers`, decoupling it from
`clubs/{clubId}/members` entirely, and add a narrow top-level wildcard
rule scoped to just the new name (ADR-006).

### Reasoning

The two collections were never actually related — they shared a name by
coincidence, not by design (`watchMyCommunities()` never needed club data;
it only ever used room IDs derived from the parent path). Once that's
clear, the fix is obvious: give them distinct names so a rule written for
one can never be constrained by the other's requirements. The alternative
— a single, cleverer rule trying to serve both — was explored and
abandoned; see the "also learned" note under Consequences.

### Consequences

Every one of the 5 `collection('members')` call sites in
`room_service.dart` had to move to `roomMembers` in the same change — a
partial rename would have been worse than no rename (some code reading
the old path, some the new one, silently disagreeing). Any future
subcollection name should be checked against this question before it's
chosen: will this ever need a `collectionGroup()` query, and if so, could
its name collide with an unrelated collection elsewhere in the schema?

**Also learned, the hard way**: combining an `exists()`-based clause with
a provable one via `||` does **not** satisfy Firestore's collection-group
provability check, despite documentation seeming to suggest an OR'd
provable clause should work — verified directly against the emulator. An
earlier fix attempt for `watchMyCommunities()` relied on exactly that
assumption and never actually worked, despite looking correct on
inspection. Don't trust that pattern without an emulator test proving it
(ADR-007).

---

## ADR-006: Top-level `collectionGroup` wildcard rules stay read-only and narrow

**Status**: Accepted, still in effect
**Date**: 2026-08-04 (`e620582`, alongside ADR-005)

### Context

Fixing ADR-005 required adding Firestore's first top-level
`match /{path=**}/...` rules to this project. Wildcard rules like this are
easy to over-scope, since `{path=**}` matches *any* document depth,
anywhere in the database, not just the collection the fix was aiming for.

### Decision

The two wildcard rules added (`roomMembers`, `invites`) only allow
`read`, and only "read your own record" —
`resource.data.userId == request.auth.uid` /
`resource.data.inviteeId == request.auth.uid`. All writes to both
collections still only go through their original, nested, parent-scoped
rules; the wildcard rules add no new write path at all.

### Reasoning

The narrowest rule that unblocks the two specific `collectionGroup()`
queries this app actually runs is also the safest one — it can't be
walked back into a broader hole later just because it already exists and
"seems related enough" to reuse for something else. A wildcard `allow
write` at this scope would be a much bigger, harder-to-reason-about
surface for very little benefit, since no code path needs it.

### Consequences

Any future `collectionGroup()` need should default to this same shape —
read-only, `resource.data.<ownerField> == request.auth.uid`, nothing
broader — rather than treating the existence of one top-level wildcard
rule as precedent for a looser one. If a genuine cross-parent *write* need
ever comes up, that's a new decision, not an extension of this one.

---

## ADR-007: Firestore rules changes are always emulator-tested against a real `collectionGroup()` query

**Status**: Accepted, still in effect — process rule, not a code change
**Date**: 2026-08-04 (`e620582`; the test suite itself landed 2026-08-03,
`67fd8fe`)

### Context

The bug behind ADR-005 shipped, stayed broken in production, and passed a
40-check test suite the entire time. Every one of those 40 checks called
`getDoc()`/`getDocs()` against a fully-specified document path. That
access pattern never exercises Firestore's `collectionGroup()`-provability
check at all — a nested rule that's completely unable to authorize a
`collectionGroup()` query will pass every direct-path test perfectly.

### Decision

Never deploy a Firestore rules change on the strength of a test suite that
only calls `getDoc()`/`getDocs()` on a known path. Any rule meant to
support (or that could affect) a `collectionGroup()` query needs an actual
`collectionGroup()` query in its test.

### Reasoning

A green test suite is only worth as much as what it actually exercises.
"43 checks passing" and "this code path works in production" are
different claims, and this bug is the concrete proof that they can
diverge without anyone noticing until a user reports a broken feature.
`firestore-tests/rules.test.js` now includes real `collectionGroup()`
regression tests specifically closing this gap (see
[TESTING.md](TESTING.md)).

### Consequences

Every future Firestore rules change needs to ask "does anything read this
collection via `collectionGroup()`, anywhere in the app?" before deploying
— not just "did the existing tests pass." This is slower than trusting a
green suite blindly, on purpose. See
[Firebase.md](Firebase.md#firestore-rules-testing) for the actual
emulator-testing workflow this enforces.

---

## ADR-008: Resend SMTP instead of Firebase's default email sender

**Status**: Accepted, still in effect
**Date**: 2026-08-04 (approximate — Firebase Console configuration, not a
code commit, made around the same time as the email-verification work in
`a21d00d`/`04882cc`/`14cc7f7`)

### Context

Firebase Auth's built-in email sender is a Firebase-branded SMTP relay
with no delivery guarantees suited to a real product — verification and
password-reset emails sent through it never reliably reached inboxes. This
was a confirmed, real deliverability failure, not a preference or a guess.

### Decision

Route Firebase Auth's action emails (verification, password reset)
through Resend's SMTP relay instead of Firebase's default sender,
configured in Firebase Console → Authentication → Templates → SMTP
settings.

### Reasoning

Resend is a transactional-email-focused provider with real deliverability
guarantees and monitoring; confirmed working end-to-end for both flows
after the switch. This is Firebase Console configuration, not application
code — it doesn't show up in a `git diff`, which is exactly why it needs
to be written down here.

### Consequences

The SMTP username in Firebase Console must stay literally the string
`"resend"` — not the account email, not an API-key-looking value; getting
this field wrong silently breaks delivery again with no obvious error in
the app. `handleCodeInApp` is intentionally **not** used for verify/reset
codes — Firebase's own hosted action page still handles those, by design.
Since this configuration lives outside git, anyone rotating the Resend API
key or reconfiguring Auth templates needs to know to update it in the
Firebase Console directly, and should update this ADR's date if the setup
changes materially.

---

## ADR-009: `NEXT_PUBLIC_APP_URL` as an env var (website repo)

**Status**: Accepted, still in effect
**Date**: 2026-08-04 (approximate — `yovoice-website` repo, not tracked in
this repo's git history)

### Context

`yovoice-website` needs to redirect signed-in users to the actual Flutter
web app. The intended final URL, `https://app.yovoice.app`, needs a DNS
record on Cloudflare that only the domain owner can add — a genuine
external blocker with no fixed timeline (see
[Roadmap.md](Roadmap.md)).

### Decision

Make the redirect target an environment variable
(`NEXT_PUBLIC_APP_URL`), currently `https://yovoice-ec54a.web.app`
(Firebase Hosting's default domain), rather than hardcoding either URL in
code.

### Reasoning

Hardcoding the target would mean a code change and a redeploy the moment
DNS finally goes live — small, but an unnecessary coupling between an
infrastructure event nobody controls the timing of and a code change that
otherwise has nothing to do with it. An env var makes the eventual switch
a Vercel dashboard change, not a pull request.

### Consequences

Every environment (production/preview/development in Vercel) needs this
variable set consistently, and it's easy for local `.env.local` to drift
from what's actually configured in Vercel — worth double-checking with
`vercel env ls` after any change. The flip to `app.yovoice.app` still
needs someone to notice DNS has actually propagated and go make the
Vercel change; nothing automates that trigger.

---

## ADR-010: Real per-achievement unlock timestamps

**Status**: Accepted, still in effect
**Date**: 2026-08-06 (`6cfd208`)

### Context

The Awards screen needed a genuine "recent unlocks" feed as part of
turning it into a real achievement hub. The existing `unlockedTitleIds`
field is a list with no ordering information — it's fully recomputed from
the achievement catalog on every relevant write, so its order is
deterministic by catalog definition order, not by when the user actually
unlocked anything.

### Decision

Add `unlockedTitleTimestamps` — a `Map<achievementId, Timestamp>` — to
`users/{userId}`, written by `AchievementService.incrementMetric()` and
`refreshUnlockedTitles()` whenever an achievement is newly unlocked.
Existing entries are merged, never overwritten.

### Reasoning

The alternative was faking recency somehow — reversing catalog order, or
treating "most recently recomputed" as meaningful, both of which would be
exactly the kind of convincing-looking fake ADR-012 rules out. A real
timestamp, written once at the moment of unlock, is the only honest way to
answer "when did this happen."

### Consequences

Achievements unlocked *before* this field existed have no timestamp and
simply don't appear in "recent unlocks" — not backfilled with a guessed
date. That's a deliberate, accepted gap for existing users, not a bug to
fix later. Every future per-user "when did X happen" feature should reach
for this same pattern (a real, once-written timestamp map) rather than
inferring order from something that gets recomputed.

---

## ADR-011: `permission_handler` for real device-permission status

**Status**: Accepted, still in effect
**Date**: 2026-08-06 (`6cfd208`)

### Context

Settings needed a real Permissions section (microphone, camera, push
notifications). `permission_handler` was already a dependency, previously
used only for the one-shot microphone-permission request inside
`voice_call_service.dart` before joining a voice room.

### Decision

Query actual OS-level permission status via `permission_handler` for each
relevant permission, and offer a real "open system settings" action when
one is denied — not a static description of what the app *could* ask for.

### Reasoning

The dependency and the underlying capability already existed; the only
question was whether to wire it up honestly or fake a settings-looking UI
with no real data behind it. Given ADR-012's standing rule, there wasn't
really a decision to make here — this is that rule applied to a case where
"real" happened to be nearly free.

### Consequences

None significant — this is the easy case of "real data was cheap, so
there's no excuse not to use it." Worth recording anyway so the next
person building a similar permission-aware UI element knows the pattern
(and the existing call site) to follow rather than reinventing it.

---

## ADR-012: "Coming soon" instead of fabricated data or dead buttons

**Status**: Accepted, still in effect — the standing UI rule for the whole app
**Date**: 2026-08-06 (`6cfd208`)

### Context

Settings, Awards, and Creator Studio all needed sections describing
features with no backend support yet (two-factor auth, creator analytics,
monetization, multi-device session management, and more). The tempting
shortcut for any of these is a convincing static mockup — a chart with
plausible-looking numbers, a toggle that flips but persists nothing.

### Decision

When a screen needs a feature with no real backend support, show it
visibly, disable it, and label it "Coming soon" — a small pill/badge, not
just grayed-out text. Never fake the data behind it, never silently hide
the option instead, and never leave a button that does nothing with no
explanation at all.

### Reasoning

A convincing fake is worse than an honest gap: it erodes trust the moment
a user notices the numbers never move or the toggle doesn't survive a
restart, and that erosion spreads to *every other number in the app*, real
ones included. This mirrors the same call already made on the website's
download center (honest "coming soon" instead of fake app-store links)
and account pages (Firestore-backed preferences deliberately left unbuilt
rather than shipped half-working). It's a product-quality decision, not
just a UI-copy one — see
[Vision.md](Vision.md#what-done-looks-like-for-a-feature) for the fuller
"what done looks like" framing this rule is one piece of, and
[UI.md](UI.md#the-coming-soon-pattern) for the exact visual pattern.

### Consequences

New screens take marginally longer to ship, since every "not built yet"
element needs an explicit disabled/labeled treatment instead of just being
left off the screen. In exchange, no screen in this app can be
misread as more finished than it is — hiding a gap and labeling it are
different failure modes, and this project has chosen to never do the
former. A "Coming soon" section shipping next to *real* data in the same
screen is expected and correct (e.g. Creator Studio's real room/moment
counts next to its disabled analytics card) — the rule is about honesty
per-element, not an all-or-nothing gate on the whole screen.

---

## ADR-013: Clients write Firestore directly; Cloud Functions are reserved for privileged work

**Status**: Accepted, still in effect
**Date**: Foundational — implicit in the project since its Firebase
adoption, documented explicitly on 2026-08-06

### Context

Firebase's model makes a real architectural choice available that a
traditional REST/GraphQL backend doesn't: clients can read and write the
database directly, with Firestore Security Rules acting as the
authorization layer instead of a server-side API. This project has always
used that model — most features (rooms, clubs, friends, messages, Voice
Moments, achievements, settings) have their Flutter services write
Firestore directly, with no backend code in the path at all.
`functions/` is comparatively small and does not mediate most writes.

### Decision

Default to client-direct Firestore reads/writes, enforced by Security
Rules. Reserve a Cloud Function for a write path only when at least one of
these is true:

1. **It needs a secret the client can never hold** — minting a LiveKit
   token needs `LIVEKIT_API_SECRET`; a Firestore rule has no access to
   Secret Manager (`createLiveKitToken`, see [Backend.md](Backend.md)).
2. **It grants a capability rules can't safely compute** — admin role
   assignment needs a decision no Firestore rule can make safely, because
   the rule itself would need the very authority being granted
   (`assignUserRole`, `bootstrapSuperAdmin`).
3. **It fans out as a side effect the writer shouldn't have to orchestrate
   client-side** — turning "a notification document was created" into an
   actual push notification via FCM is a side effect the original writer
   (whoever triggered the notification) has no business knowing or caring
   about (`onNotificationCreated`, see [Backend.md](Backend.md)).
4. **It's a cross-cutting operation better expressed as one atomic,
   server-trusted step than as client-side choreography** — self-service
   club ownership transfer touches two member documents at once in a way
   that's cleaner and safer to guarantee from a Cloud Function than from
   two separate rule-gated client writes (`transferClubOwnershipSelf`).

### Reasoning

A Cloud Function for every write would mean rebuilding, in Node, a huge
amount of authorization logic that Security Rules already express more
directly against the data shape they're protecting — and it would add
network hops and cold-start latency to interactions (typing a chat
message, raising a hand) where that cost is felt immediately by a real
person waiting on it. Rules-enforced direct writes keep those interactions
fast and keep the authorization logic co-located with the schema it's
protecting, which is also why `firestore.rules` is as detailed as it is
(see ADR-003 for what happens when that authorization logic is
insufficiently paranoid). Cloud Functions earn their cost — the extra
hop, the cold start, the separate deploy — specifically where rules
structurally cannot do the job.

### Consequences

Most new features should start by asking "can Security Rules express this
correctly," and only reach for a Cloud Function when the answer is
genuinely no — not by default, and not because a server-side function
"feels more correct" for a write that rules can actually gate just fine.
This also means Firestore Security Rules carry unusually high stakes for
a config file: they are the *entire* authorization layer for most of this
app's data, not a secondary check behind an API. Treat every rules change
with the same seriousness as a change to an authentication system,
including the ADR-007 testing discipline. See
[Firebase.md](Firebase.md) for the schema those rules protect and
[SECURITY.md](SECURITY.md) for the resulting security model in full.

---

## ADR-014: Two deployables, one Firebase project

**Status**: Accepted, still in effect
**Date**: Foundational — documented 2026-08-06

### Context

The product needs both a public marketing/SEO-friendly website and a
full-featured app. A single Flutter web build can serve as the app, but
it's a poor fit for marketing pages (SEO, fast static rendering, content
that changes independently of the app's release cycle) — and a Next.js
site is a poor fit for a feature-rich, real-time, cross-platform app
experience.

### Decision

Ship two separate deployables — this repo (Flutter: mobile, web, desktop)
and `yovoice-website` (Next.js, marketing + auth + account pages) —
sharing one Firebase project (`yovoice-ec54a`) for Auth, Firestore, and
Cloud Functions, connected via a shared custom Auth domain
(`auth.yovoice.app`) so one account works identically on both.

### Reasoning

This mirrors a pattern used by companies with the same shape of problem
(the reference point discussed at the time was `discord.com` +
`discord.com/app`): a marketing/auth/account layer that's optimized for
being found and understood by new visitors, sitting in front of a
completely different technology optimized for the actual product
experience. Splitting them lets each side use the right tool — Next.js's
SSR/SEO strengths for the site nobody's logged into yet, Flutter's
cross-platform reach for the app itself — without either compromising for
the other's constraints. Sharing one Firebase project instead of two
avoids duplicating user accounts, security rules, or Cloud Functions.

### Consequences

Two codebases, two deploy pipelines (GitHub Actions for this repo's
Hosting target, Vercel for the website — see
[DEPLOYMENT.md](DEPLOYMENT.md)), and one Firestore schema now has two
independent client codebases both depending on its shape staying stable —
raising the bar on schema changes (see the "never break the schema" rule
in [CLAUDE.md](../CLAUDE.md)). A feature that needs to exist in both
places (e.g. account settings) has to be built twice, once per stack, with
no shared UI code between them — an accepted cost of the split, not an
oversight. `app.yovoice.app`'s pending DNS record (see
[Roadmap.md](Roadmap.md)) is the current visible seam between the two.

---

## ADR-015: Feature-based folder structure over layer-based

**Status**: Accepted, still in effect
**Date**: Foundational — documented 2026-08-06

### Context

A Flutter app of this size needs *some* organizing principle for `lib/`.
The two common ones are layer-based (one top-level `models/`, one
`services/`, one `screens/`, spanning the whole app) and feature-based
(each product area owns its own `data/` + `presentation/`).

### Decision

Organize `lib/` by feature — `lib/features/<feature>/{data,presentation}/`
— rather than by technical layer. See
[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) for the concrete layout.

### Reasoning

This app has 15 distinct feature areas (rooms, clubs, friends, messages,
moments, achievements, creator, settings, notifications, and more) that
are each substantial enough to reason about independently, and that only
rarely need to share code with each other beyond `lib/core/` and
`lib/shared/`. A layer-based structure would mean every change to "how
Clubs work" touches three unrelated top-level folders
(`models/club.dart`, `services/club_service.dart`,
`screens/club_screen.dart`) instead of one (`features/clubs/`) — and
finding "everything related to Clubs" would mean searching by filename
convention across the whole codebase instead of opening one directory.

### Consequences

Cross-feature code has to earn its place in `lib/core/` or
`lib/shared/` rather than defaulting there — the moment something is
genuinely feature-specific, it belongs inside that feature's folder, not
promoted to shared just because two features happen to use something
similar today. This structure also makes it easy to end up with small
amounts of duplication between features that solve a similar problem
slightly differently (a known, accepted cost — see
[UI.md](UI.md) for one concrete instance: the inline-hex color convention
repeated per-screen rather than centralized). That's judged an acceptable
trade for the alternative of premature sharing that couples features that
should be free to evolve independently.

---

## ADR-016: Native Android and iOS window chrome is pinned dark, not OS-controlled

**Status**: Accepted
**Date**: 2026-08-06

### Context

Users reported a large white panel flashing in from the bottom of the
screen when opening New Chat. The Dart-side implementation
(`_NewMessageSheet` in `messages_screen.dart`, a `DraggableScrollableSheet`
inside `showModalBottomSheet`) was already fully dark-themed — the bug
wasn't there. The actual cause was one level down, in the native shell:

- **Android**: `android/app/src/main/res/drawable/launch_background.xml`
  hardcoded `@android:color/white` (an untouched Flutter template
  default), and both `values/styles.xml` and `values-night/styles.xml`
  set `NormalTheme`'s `android:windowBackground` to
  `?android:colorBackground` — a reference Android docs describe as
  determining "the color of the Android Window ... behind your Flutter UI
  while it's running." That reference resolves against the **phone's own
  OS-level light/dark setting**, not the Flutter app's theme.
- **iOS**: `LaunchScreen.storyboard`'s root view had a hardcoded white
  `backgroundColor` (also an untouched template default), and
  `Info.plist` had no `UIUserInterfaceStyle`, so native chrome again
  followed the **system** appearance.

YO Voice's Flutter theme (`lib/core/theme/app_theme.dart`) is dark-only —
`Brightness.dark` unconditionally, no light variant. So on any device with
the system set to Light mode (the common default), the native layer
sitting behind Flutter's compositor was white while the Flutter layer on
top was dark. That native layer is what showed through during route/sheet
transition compositing — most visibly on the New Chat sheet because
`DraggableScrollableSheet`'s transition is the heaviest one in the app,
giving the white layer the most opportunity to be seen. It was never
specific to New Chat; that sheet just made an app-wide condition visible.

### Decision

Pin every native-chrome color source to the app's actual dark background
(`#0D0618`, matching `AppColors.background`) instead of an OS-relative
reference, on both platforms:

- Android: hardcoded `#FF0D0618` in both `launch_background.xml` variants
  (`drawable/`, `drawable-v21/`) and both `styles.xml` variants
  (`values/`, `values-night/`) for `NormalTheme.windowBackground`; also
  switched `values/styles.xml`'s `LaunchTheme`/`NormalTheme` parent from
  `Theme.Light.NoTitleBar` to `Theme.Black.NoTitleBar` so the two
  variants are now identical regardless of the OS setting.
- iOS: recolored `LaunchScreen.storyboard`'s background to the same
  `#0D0618`, and added `UIUserInterfaceStyle: Dark` to `Info.plist`.

### Reasoning

The app has no light theme, so its native shell has no legitimate reason
to vary with the OS's light/dark setting — doing so wasn't a feature, it
was an unhandled case. Fixing it per-screen (e.g. giving
`_NewMessageSheet` an opaque backdrop) would have hidden the symptom on
that one sheet while leaving the same native-layer mismatch behind every
other transition in the app. Pinning the native layer once, at the
source, fixes it everywhere at once and can't regress by a future screen
forgetting to set a background color.

### Consequences

Native chrome (status bar style, window background, launch screen) no
longer respects the system's light/dark setting on either platform — this
is correct today because the app has no light theme, but if a light theme
is ever added, this decision needs to be revisited alongside it (the
native layer would need to switch dynamically instead of staying pinned).
Required an unrelated fix to get iOS building at all in this session: the
Podfile had no explicit `platform`, so CocoaPods defaulted a subset of pod
targets below the 15.0 minimum Firebase's Swift Package Manager
dependencies already require, producing an Xcode Target Integrity error.
Set `platform :ios, '15.0'` in `ios/Podfile` to match `Runner.xcodeproj`'s
existing deployment target.

---

## ADR-017: Android build fixes: core library desugaring and drawable resource references

**Status**: Accepted
**Date**: 2026-08-07

### Context

Verifying ADR-016's Android fix required an actual Android build, which
this project apparently had never had attempted end-to-end recently —
CI only builds the Flutter *web* target (see
[DEPLOYMENT.md](DEPLOYMENT.md)), so an Android-specific build regression
had no way to surface on its own. Two genuine, unrelated build blockers
turned up:

1. `flutter_local_notifications` requires Java 8+ core library
   desugoring to be enabled for `:app` — not configured in
   `android/app/build.gradle.kts`. `flutter build apk --debug` failed
   outright with `AAR metadata` errors before compiling a single Dart
   line.
2. After fixing (1), the build failed again — AAPT2 rejected
   `<item android:drawable="#FF0D0618" />` inside
   `drawable/launch_background.xml` and `drawable-v21/launch_background.xml`
   (ADR-016's own fix) with "incompatible with attribute drawable (attr)
   reference." A `<style>` item's `android:windowBackground` accepts a
   literal color directly; a `<layer-list>` `<item>`'s `android:drawable`
   attribute does not — it needs an actual drawable/color *resource*
   reference. `xmllint` (used to validate ADR-016's changes) only checks
   XML well-formedness, not AAPT2 resource-compiler semantics, so this
   passed that check and only surfaced once a real Android build ran.

### Decision

- Added `isCoreLibraryDesugaringEnabled = true` to `compileOptions` and
  `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")` to
  `dependencies` in `android/app/build.gradle.kts`.
- Changed both `launch_background.xml` variants' `android:drawable` to
  reference the existing `@color/ic_launcher_background` resource
  (`android/app/src/main/res/values/colors.xml`) instead of a literal hex
  string.

### Reasoning

Both are the standard, documented fixes for their respective errors —
no workaround or version pin was needed. Reusing the existing
`ic_launcher_background` color resource (rather than adding a new one)
keeps a single source of truth for the app's Android launch-surface
color, matching ADR-016's intent.

### Consequences

`flutter build apk` (and, by extension, `flutter run` on Android) now
succeeds; verified with two full builds in this session, plus
`flutter analyze`/`flutter test` passing unrelated to this change. No
Android emulator or physical device was available in the session that
made this fix, so it's build-verified but not runtime-verified — see the
session's own report for exactly what that does and doesn't cover. Since
nothing in CI builds Android, a similar regression could resurface
silently again; worth considering whether an Android build step belongs
in CI (currently out of scope — see [DEPLOYMENT.md](DEPLOYMENT.md) for
why CI is deliberately narrow today).

---

## ADR-018: Per-screen Firestore streams are created once in `initState`, never inline in `build()`

**Status**: Accepted
**Date**: 2026-08-07

### Context

Auditing the Rooms and Clubs screens for the same class of bug behind
ADR-016 turned up a different, unrelated one: several
`StreamBuilder<T>(stream: _service.watchX(id), ...)` calls had the
stream expression written directly inline as the `stream:` argument,
inside the State's `build()` method — e.g.
`broadcast_room_screen.dart`, `community_voice_room_screen.dart`,
`podcast_room_screen.dart`, and `club_overview_screen.dart`. Since
`_service.watchX(id)` returns a **new** `Stream` object every time it's
called, and `StreamBuilder` tears down and re-subscribes whenever its
`stream` argument is a different instance (Dart streams don't have value
equality), every `setState()` in that screen — joining, muting,
hand-raising, switching a tab, opening a dialog — was silently tearing
down and re-registering a live Firestore listener on the participants/
members/channels/room subcollection. In `club_overview_screen.dart`
specifically this was provably wasteful: the members/channels listeners
lived *inside* the outer `watchClub()` StreamBuilder's own builder
callback, so they were also re-created on every unrelated field change
on the club document itself (an online-count tick, e.g.), not just on
user interaction.

### Decision

Stream instances a screen depends on for its whole lifetime are created
exactly once, stored in a `late final Stream<T>` field set in
`initState()`, and referenced by that field everywhere — never called
fresh inside `build()`. Fixed in the four files above; documented here so
new room/club screens follow the same pattern from the start.

### Reasoning

This is a plain Flutter/Dart identity-vs-value semantics issue, not a
design tradeoff — there's no version of "call the stream method inline"
that's actually correct once a screen has more than one `setState()`
trigger, which every non-trivial screen does. The fix costs nothing
(one field, one line in `initState`) and removes an entire class of
avoidable Firestore listener churn.

### Consequences

Two related, more invasive findings from the same audit were
**deliberately not fixed** in this pass, to keep it scoped:
`room_screen.dart` and `podcast_room_screen.dart`'s screen classes
(`RoomScreen`, `PodcastRoomScreen`) are confirmed **dead code** — no
navigation path in the app reaches either of them any more
(`RoomEntryScreen` only routes to `BroadcastRoomScreen` or
`CommunityRoomLobbyScreen`; legacy `experience: podcast` Firestore values
are mapped to `broadcast` before that routing happens, per
[ADR-001](Decisions.md#adr-001-legacy-podcast-room-experience-stays-supported)).
`podcast_room_screen.dart` got this same stream fix anyway since it was
already being edited and the fix is harmless either way; `room_screen.dart`
was left untouched entirely. Per this project's rule against removing
existing functionality without being asked (see
[CLAUDE.md](../CLAUDE.md)), neither file was deleted — that's a decision
for whoever owns the product to make deliberately, not a side effect of
an audit pass. The same inline-stream pattern also exists in a handful of
lower-traffic spots (`friends_screen.dart`, `friend_profile_screen.dart`,
a `club_overview_screen.dart` invite sheet) that weren't fixed this pass
because they don't sit behind a frequently-rebuilding `build()` the way
the four fixed screens did — lower severity, not zero, worth a future
pass.
