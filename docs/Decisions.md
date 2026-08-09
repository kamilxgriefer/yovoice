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
| [019](#adr-019-more-menu-destinations-own-their-full-chrome-no-wrapper-scaffold)                        | "More" menu destinations own their full chrome; no wrapper Scaffold                         | Accepted | 2026-08-07                           |

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

---

## ADR-019: "More" menu destinations own their full chrome; no wrapper Scaffold

**Status**: Accepted
**Date**: 2026-08-07

### Context

A product-quality pass reported the Settings screen as "broken — large
white background, content missing." Tracing the actual navigation (not
assuming from the filename) found the real defect: every single one of
the seven "More" menu destinations (Friends, Discover, Clubs,
Notifications, Achievements, Creator Studio, Settings) is a complete,
independently-designed screen with its own `Scaffold`, its own
background, and its own custom header — but `main_shell.dart` was
pushing every one of them wrapped in `MoreDestinationPage`
(`more_sheet.dart`), which added a *second* `Scaffold` with a generic
`AppBar` (its own title, its own back button) on top.

The severity varied by screen: Settings only doubled its title text
(harmless-looking but visibly wrong). Achievements was worse —
`AchievementsScreen` has its own full `AppBar` showing real progress
("X/100 titles"), so reaching Awards via the More menu showed **two
stacked Material app bars and two back buttons**, a plainly broken
screen. Six of the seven destination screens had no back button of
their own at all — they'd been built assuming the wrapper's AppBar was
the only source of back navigation, which is why nobody had simply
deleted the wrapper before.

### Decision

Removed `MoreDestinationPage` and `moreDestinationLabel` entirely.
`main_shell.dart`'s `_openMoreDestination` now pushes each destination
screen directly. Added a small `YoIconButton`-based back button to each
screen's own header for the six that lacked one (Settings, Friends,
Discover, Clubs, Creator Studio — Achievements and Notification
preferences already had their own).

### Reasoning

Each destination screen's own header was already more considered and
on-brand than the wrapper's generic default AppBar (custom title +
subtitle copy, trailing actions like Friends' request-count badge or
Clubs' create button) — the wrapper was the lower-quality, redundant
layer, not the screens. Fixing this once at the call site
(`main_shell.dart`) plus one header addition per screen was less
invasive than trying to make seven different screens defer their own
chrome to a shared wrapper, and it gives every "More" destination the
same visual back-button treatment for the first time, which
`YoIconButton` (already existing in `lib/shared/widgets/buttons/`)
made trivial to keep consistent.

### Consequences

Every "More" destination now looks and behaves correctly with a single,
purpose-built header instead of doubled or missing chrome. This was a
universal, previously-undiscovered bug — worth remembering that "looks
right in a code read" isn't the same as "was ever actually opened and
looked at," especially for a navigation path (More menu) that's one tap
removed from the primary bottom navigation and easy to under-test.

## ADR-020: Service streams shared by more than one widget must be broadcast + replay

**Context.** `FriendService.watchFriends()` returned
`StreamController<List<FriendUser>>().stream` — a single-subscription
stream. `MessagesScreen` creates it once in `initState` and passes the same
instance to two widgets: `_FriendsRow`, which is always mounted, and
`NewMessageSheet`, which mounts when the user taps "New message". The
second `listen()` threw `Bad state: Stream has already been listened to`,
Flutter substituted its default `ErrorWidget` for that subtree, and in a
release web build that renders as a plain light-grey rectangle with no
text. It read as a layout/theming bug for months and was misattributed to
native window chrome (ADR-016, which remains correct for the *flash* it
describes — this was a second, unrelated defect).

**Decision.** A stream returned by a service and handed to UI is part of
that service's public contract, so it must tolerate more than one listener
and must replay its latest value to late subscribers.
`watchFriends()` now uses `StreamController.broadcast()` for the
Firestore fan-in and wraps it in `Stream.multi`, which seeds each new
subscriber with the cached list before forwarding live updates.

**Reasoning.** Broadcast alone is not enough: the sheet subscribes *after*
the first emission, and a bare broadcast stream delivers nothing until the
next Firestore change, so the sheet would show a spinner indefinitely on a
stable friends list. `Stream.multi` is the standard-library way to give
each listener its own subscription and is enough here — no rxdart, no
caching layer, no change to any caller.

**Consequences.**
- `onListen`/`onCancel` now fire on 0→1 and 1→0 listener transitions, so
  `start()` resets the teardown flag and `onCancel` clears the per-friend
  subscription map; a stream can legitimately be restarted.
- Existing single-listener callers are unaffected.
- The same shape should be used for any future service stream that a
  screen may share. `watchConversations()` did not need it: Firestore's
  own `snapshots()` is already broadcast, which is why only the friends
  half of the sheet failed.
- Regression coverage lives in `test/new_message_sheet_test.dart`, and
  `lib/dev/new_message_preview.dart` can reproduce the pre-fix behaviour
  on demand via its "Use pre-fix single-subscription streams" toggle.

## ADR-021: Profile images are pending local changes until Save

**Context.** Edit profile uploaded an avatar/banner to Storage and wrote
the URL to Firestore the moment the user picked a file, while every text
field on the same screen waited for the Save button. Pressing Back after
picking an image therefore still changed the profile remotely, and a
discarded pick left an orphaned Storage object that nothing ever deleted.
The screen also rendered no preview of either image, so a successful
upload produced no visible change — the "my new avatar doesn't appear"
report.

**Decision.** `ProfileService.pickProfileImage()` picks and validates but
does not upload; it returns a `PickedProfileImage` (bytes + sniffed
format). `EditProfileScreen` holds that as pending state, previews it
straight from memory, and `_save()` uploads it alongside the text fields.
Images upload before the Firestore text write so a failed upload aborts
the whole save rather than half-applying it.

**Reasoning.** One rule for the whole screen ("nothing is committed until
Save") is easier to explain than two, it removes the orphaned-upload
problem at the source rather than adding cleanup, and previewing from
`MemoryImage` makes the new image appear instantly with no network round
trip — which is what the user was actually asking for.

**Consequences.**
- `pickAndUploadImage()` is kept and now delegates, so any other caller
  keeps working.
- Nothing reaches Storage until Save, so there is no cleanup job to write.
- Accepted formats are sniffed from magic bytes (JPEG/PNG/WebP) rather
  than trusted from the file extension; limits are 5 MB / 1024 px for
  avatars and 10 MB / 1920 px for banners, encoded in
  `ProfileImageRules`.
- The interactive crop/reposition step is **not** implemented yet; the
  aspect ratios in `ProfileImageRules` (1:1 and 16:9) are already the
  values that step should honour.

## ADR-022: Auth action links route through yovoice.app, not Firebase's hosted handler

**Context.** Password-reset and verification emails sent users to
`yovoice-ec54a.firebaseapp.com/__/auth/action` — Firebase's generic white
utility page, with no YO Voice identity. A prior session established
empirically (see the website's `action-code-settings.ts`) that
`ActionCodeSettings.url` cannot bypass that page: it only becomes the
`continueUrl` afterward. The only supported bypass is the console's
"customize action URL" setting, which redirects the emailed link itself.

**Decision.** The website owns the action experience. A server-side
dispatcher at `yovoice.app/auth/action` (Next.js route handler) receives
`mode`/`oobCode`/`continueUrl`/`lang` and fans out to branded pages:
`/reset-password` (verifyPasswordResetCode → form → confirmPasswordReset),
`/verify-email` (existing applyActionCode handler), `/recover-email`
(recoverEmail + verifyAndChangeEmail). The console action URL must be set
to `https://yovoice.app/auth/action` — a one-time manual step documented
in docs/email-templates/README.md, because Firebase exposes no
CLI/deploy surface for it in our toolchain. Firebase stays the sole
source of truth for code validity; nothing is faked client-side.

**Reasoning.** One dispatcher (the console allows exactly one custom
action URL) keeps every mode on a branded page, including the
email-change revocation flow that would otherwise silently regress to
the hosted page. A route handler rather than a page keeps the oobCode
out of rendered HTML and needs no client JS to dispatch. `continueUrl`
is allowlist-validated (`safe-continue-url.ts`) at the dispatcher AND at
each consuming page — it is attacker-controllable input on a page
reached from an email, i.e. a textbook open-redirect vector.

**Consequences.**
- The full reset lifecycle was verified against the Firebase Auth
  emulator end to end (form → confirmPasswordReset → old password
  rejected / new accepted / code replay rejected). The emulator entry in
  firebase.json and the env-gated `connectAuthEmulator` hook in the
  website's firebase config are permanent test infrastructure.
- Email template bodies are customizable ONLY because Resend SMTP is
  configured; templates live in docs/email-templates/ and must be pasted
  into the console by hand.
- The Flutter app's ActionCodeSettings keep their yovoice.app continue
  URLs and stop claiming `handleCodeInApp: true`, which was a no-op for
  these code types.
- If yovoice.app is ever unreachable, emailed auth links break with it —
  accepted: the website already fronts registration/login for the same
  accounts.

## ADR-023: One profile source of truth; identity fans out server-side

**Context.** Avatar/banner "not appearing consistently" survived three
rounds of fixes because the architecture allowed it: four separate code
paths wrote `users/{uid}.photoUrl` (PresenceService, friend_service's
ensureUserDocument, registration's FirestoreService.createUserProfile —
which merged a literal `photoUrl: null` — and ProfileService itself),
several screens read identity from FirebaseAuth instead of Firestore, and
the copies denormalized into conversations/club members/moments were
never updated after a change. Separately, Edit Profile stretched
edge-to-edge on desktop, blowing its 16:9 banner preview up to ~800px
tall, and profile editing was reachable from three Settings entry points.

**Decision.**
- `users/{uid}` in Firestore is canonical for all profile identity;
  ProfileService is its only writer for identity fields. FirebaseAuth
  mirrors displayName/photoURL (written by ProfileService after saves)
  but is never read for display.
- Field names stay `photoUrl`/`bannerUrl` — they are load-bearing schema
  shared with the website and Functions (CLAUDE.md hard rule); no
  `avatarUrl` rename, no aliases, no migration needed.
- A new Cloud Function `onProfileIdentityChanged` (users/{uid} update
  trigger) fans photoUrl/displayName out to conversations
  (participantPhotoUrls/Names), club member docs (via the
  users/{uid}/clubs mirror — deliberately no collectionGroup query,
  ADR-007) and voice_moments author fields. Room participant docs are
  excluded: they die with the session.
- All own-identity UI renders through shared widgets
  (`UserAvatar`, `ProfileBanner`) with explicit loading/error/fallback
  states; a broken URL falls back to initials / brand gradient instead
  of rendering like "no image set".
- Storage/Firestore consistency: upload first, flip the Firestore
  pointer second; on pointer failure the fresh upload is deleted (best
  effort) and the old image stays live. After a successful flip the
  replaced object is deleted (best effort) — every upload has a fresh
  timestamped name (that IS the cache-busting strategy), so cleanup is
  what prevents unbounded orphan growth.
- Profile editing lives only on Profile → Edit profile; Settings keeps
  read-only identity summaries and links to the Profile screen.

**Consequences.**
- The fan-out requires a manual `firebase deploy --only functions`.
- Username uniqueness remains unenforced (usernames are seeded from
  display names and duplicates already exist in production). Enforcing
  it needs a claims collection + backfill migration — deliberately out
  of scope, recorded in Roadmap rather than half-shipped client-side.
- lib/dev/profile_preview.dart renders Profile header + Edit profile
  with fake data at arbitrary widths, so profile-layout regressions can
  be caught without a signed-in session.

## ADR-024: Premium entitlements are server-written, time-validated, and gate Creator + Clubs

**Context.** The product needed a real subscription tier (Creator,
Club creation, premium identity) — and the audit found Creator was
already claimable by ANY client: `accountType` sat in the users-doc
write allowlist with no gate. No billing/IAP code existed anywhere.

**Decision.**
- `entitlements/{uid}` is the trusted subscription document. Written
  exclusively by Cloud Functions (`premium/entitlements.js`); rules deny
  all client writes and allow reads only by the owner. It stores plan
  (monthly €9.99 / yearly €89.99, centralized in Flutter's
  `premium_plans.dart`), status (`active|trialing|grace|expired`),
  `currentPeriodEnd`, and derived flags (creatorEnabled, canCreateClubs,
  premiumIdentityEnabled, maxOwnedClubs=3) so future tiers can vary
  entitlements without schema changes.
- **Validity is time-based everywhere**: rules (`hasActivePremium()`),
  the client model, and the paywall all compare `currentPeriodEnd`
  against now — expiry enforces itself with no job in the authorization
  path. A daily sweep only tidies the cosmetic mirror.
- `users/{uid}.premiumIdentity` is the public, server-written mirror
  that lets OTHER users' clients render the premium ring; it is
  deliberately absent from the client-writable allowlist.
- Server enforcement: club `create` requires `hasActivePremium()`;
  `accountType` may change to `creator` only with active premium,
  `official` is never client-settable, `personal` is always allowed.
  UI gates (PremiumGates, upsell sheets) are UX, not security.
- **Expiration policy**: nothing is deleted. Clubs created while
  premium remain intact with owner and members; only creating MORE
  clubs is blocked. A lapsed Creator keeps profile/followers/content;
  Creator Studio shows a "tools paused" banner until Premium returns.
  The rules allow `accountType` to REMAIN `creator` after expiry (the
  gate is on changing INTO creator), which is what makes the
  keep-your-data policy work.
- Purchases: `verifyPurchase` exists and deliberately declines until
  store verification is configured (App Store Server API key / Play
  service account / web provider webhooks). Nothing is ever unlocked on
  a client's claim. `adminSetPremiumEntitlements` (admin/superAdmin
  guarded) is the interim grant path and the testing mechanism.

**Consequences.**
- firestore.rules changes are implemented and covered by six new cases
  in firestore-tests/rules.test.js but NOT deployed — the emulator
  convention (ADR-007) requires a JVM this machine lacks. Until the
  user runs the suite and deploys rules, the server gates are not live.
- Store console setup (products `yovoice_premium_monthly`/`_yearly`),
  verification credentials, and an IAP client plugin remain manual.
- EntitlementService caches one replayed stream per uid (the
  ProfileService pattern) and fails closed: errors emit FREE.

## ADR-025: Profile media crop editor ships the final cropped JPEG, not crop metadata

**Status**: Accepted
**Date**: 2026-08-08

### Context

The P1 profile-media pass required a real crop/reposition editor
(pinch-zoom, drag, fixed 1:1 avatar frame with circular preview, real
16:9 banner frame) instead of uploading the picked file as-is and
letting `BoxFit.cover` decide what's visible. Two architectures were on
the table: (A) upload the final cropped image, or (B) store the original
plus deterministic crop metadata (scale / x / y / crop rect) and apply
it at display time.

### Decision

Option A. `ImageCrop` (`lib/features/profile/data/services/image_crop.dart`)
decodes with `ui.instantiateImageCodec` (EXIF-correct on all platforms),
maps the `InteractiveViewer` transform inverse onto source pixels, draws
the crop through a `PictureRecorder`, and JPEG-encodes via
`package:image` (quality 85; 1024×1024 avatars, 1920×1080 banners).
`ImageCropScreen` is the editor UI; `EditProfileScreen._pick` routes
every pick through it, and the pending/Save semantics of ADR-021 are
unchanged — the pending bytes are simply the cropped render. The picker
now requests 2× the output edge so the editor can zoom to 2× before the
render has to upscale.

### Reasoning

One artifact renders identically on Web and iOS with zero display-time
transform math; every existing consumer (UserAvatar, ProfileBanner,
conversations, clubs, the ADR-023 fan-out copies) keeps working
unchanged; and there is no cross-platform crop-metadata schema to keep
in sync (option B would have needed every consumer on every platform —
including the website — to apply the transform identically forever).
Trade-off: the original never leaves the device, so re-cropping means
re-picking — the same trade Instagram/WhatsApp/Discord make.

### Consequences

- New dependency: `package:image` (pure Dart, Web-safe) — encode only.
- Uploads are always JPEG now regardless of picked format.
- The 10 MB `storage.rules` cap for `users/{uid}/profile/*` can come
  back down once real-world sizes are observed (Roadmap follow-up).
- Regression tests: `test/image_crop_test.dart` (geometry + 1:1 output),
  `test/profile_save_e2e_test.dart` (whole pipeline through the editor).

## ADR-026: "More" destinations re-host the shell's bottom navigation (amends ADR-019)

**Status**: Accepted
**Date**: 2026-08-08

### Context

P0 report: "the bottom navigation randomly disappears" when entering
screens through More. It wasn't random — `_openMoreDestination` pushed
each destination as a plain full-screen `MaterialPageRoute`, which
covers the shell `Scaffold` and therefore its bottom bar (deterministic,
but wrong per product intent). Product decision: main destinations
reached from More (Friends, Discover, Clubs, Notifications, Awards,
Creator Studio, Settings) are shell-level surfaces and must keep the
persistent bottom navigation; deep detail flows (a chat, a room, edit
profile, a settings subpage, another user's profile) intentionally cover
it.

### Decision

`MoreDestinationHost` (`main_shell.dart`) is the single wrapper for
every pushed More destination: it re-hosts the shell's own private
`_BottomNavigation` widget — one source of truth, nothing reimplemented
per screen — wired so any bar tap pops back to the shell FIRST and then
forwards to the shell's handler (tab switch, voice sheet, More menu).
ADR-019's "no wrapper AppBar" rule still stands: destination screens
keep their own complete headers; only the bottom bar is re-hosted.

### Consequences

- Bottom-nav visibility is now policy, not an accident of which
  navigation API a screen happened to use.
- Bar state (selected tab, unread badge) on a pushed destination
  reflects the shell state at push time; taps always land on the live
  shell because they pop first.
- Regression tests: `test/more_destination_nav_test.dart`.

## ADR-027: CI gates on the full test suite; Crashlytics is the production crash channel

**Status**: Accepted
**Date**: 2026-08-08

### Context

The 2026-08-08 product audit found the project's two biggest
non-feature gaps were observability and CI: (1) the deploy workflow ran
only `flutter analyze` — a push that broke all 78 Flutter tests and the
entire rules suite still deployed to production; (2) the app had zero
crash or error reporting on any platform — a crash in the field left no
trace anywhere.

### Decision

1. `.github/workflows/firebase-hosting-merge.yml` now gates the Hosting
   deploy on `flutter test` AND both rules suites
   (`firestore-tests/rules.test.js`, `firestore-tests/storage.test.js`)
   run against real emulators in CI (Java + `firebase-tools
   emulators:exec`, `demo-yovoice` project id so no credentials are
   needed). Rules *deploys* remain manual per DEPLOYMENT.md — CI only
   proves the repo's rules pass their tests.
2. `firebase_crashlytics` added, installed in `main()`:
   `FlutterError.onError` + `PlatformDispatcher.onError` route uncaught
   errors to Crashlytics. Collection is disabled in debug builds, the
   whole setup is try/caught (observability must never take the app
   down — same posture as the App Check guard), and web is excluded
   (plugin unsupported there; tracked as a gap in TESTING.md).

### Reasoning

Both use infrastructure the project already has (GitHub Actions,
the Firebase project) — no new services, accounts, or credentials. The
storage suite also allowed the `users/{uid}/profile/*` cap to drop from
10 MB to 2 MB with test proof instead of inspection (the crop editor's
re-encode made the old ceiling obsolete — ADR-025).

### Consequences

- CI time increases by a few minutes (tests + two emulator boots).
- Android builds now require the Crashlytics gradle plugin (pinned in
  `android/settings.gradle.kts`).
- Web crash reporting remains an open gap; candidates (Sentry, a
  Firestore error sink) need their own decision.

## ADR-028: Rooms are continuous — no lobby, minimize-not-disconnect, one audio surface per room

**Status**: Accepted
**Date**: 2026-08-09

### Context

Joining a room was a chain of screens: community rooms went
entry → lobby → voice screen (backing out dropped you in the lobby,
possibly still connected), and broadcast rooms split the stage view from
a second PodcastVoiceCallScreen with its own duplicate stage. Backing
out of a room left the LiveKit connection running with NO UI attached.
Separately, `room_screen.dart` and `podcast_room_screen.dart` (~2,160
lines) were unreachable legacy.

### Decision

1. Entering a room puts you IN the room: RoomEntryScreen routes straight
   to CommunityVoiceRoomScreen / BroadcastRoomScreen; both own their
   VoiceCallService connection (community already did; broadcast now
   connects on entry — the "Join broadcast"→second-screen flow is gone).
   The lobby and both legacy screens plus PodcastVoiceCallScreen are
   deleted (~4,000 lines).
2. Back = minimize, Leave = leave. Backing out keeps the audio alive and
   the shell's new RoomMiniBar (ListenableBuilder on the
   VoiceCallService singleton, hosted above the bottom nav in MainShell
   and MoreDestinationHost) shows room name, live/reconnecting state,
   mute and an explicit leave; tapping returns to the room.
3. VoiceCallService.join() tolerates listen-only tokens: broadcast
   audience tokens have canPublish=false, and setMicrophoneEnabled(true)
   throwing there was aborting the whole join (the bug that made
   listeners' audio silently fail). Now it degrades to muted-listener.
4. Room end / removal shows the shared RoomEndedState (Discover / Home
   actions) instead of a snackbar eject. Raised hands get one-tap
   Accept/Decline in the participants sheet (new
   RoomService.moderateHandLowered for decline; accept was already
   setParticipantSpeakerStatus, which clears the hand).
5. Every participant row / chat header opens the new ProfilePreviewSheet
   (shared widget) — relationship-aware actions without leaving the
   room. New optional users.statusMessage ("vibe") field added to the
   rules allowlist (emulator-tested) and Edit Profile; website field
   demoted below it.

### Consequences

- The community lobby's room-details content has no dedicated surface
  right now (share stays in both rooms' UIs; a compact room-info sheet
  is a known follow-up).
- Old flow's per-room "Enter" tap is gone; audio connects on entry.
- Regression tests unchanged except the suite additions (statusMessage
  rule check; 92 rules checks total).

## ADR-029: "Podcast Room" is the product name; `broadcast` stays the stored identifier. Mic state is LiveKit-authoritative

**Status**: Accepted
**Date**: 2026-08-09

### Context

Rooms 2.0 renames Broadcast Rooms to **Podcast Rooms** everywhere a user
can see, and the microphone button was P0-broken: it rendered muted in a
near-background color (indistinguishable from disabled), went fully dead
while connecting/failed, and its state came from a remembered boolean
that could diverge from LiveKit after reconnects and role changes.

### Decision

1. **Rename, option A (no migration)**: every user-facing string in the
   app and website now says Podcast; the persisted
   `experience: 'broadcast'` identifier, enum value, class names, and
   `broadcastInvite` notification type are unchanged. History note:
   pre-rename data stored `'podcast'` and ADR-001's legacy mapping
   already translates it — so the stored vocabulary has now cycled
   podcast → broadcast → (displayed) Podcast. Renaming stored values
   would be a two-client migration for zero user value.
2. **Mic state**: `VoiceCallService.micState` (`MicState` enum: on /
   muted / listenOnly / connecting / unavailable) is the ONE state the
   mic UI renders from. `isMuted` now reads LiveKit's
   `localParticipant.isMicrophoneEnabled()` while connected;
   `canPublish` reads token permissions. Community room controls render
   all five states distinctly (muted = bright amber, connecting =
   spinner, listen-only = "Listening", unavailable = tappable
   explanation) — a mic that works can never look disabled.

### Consequences

- Rooms 2.0 remaining milestones (new room visuals, chat, board,
  covers, reactions, Friends-tab navigation) tracked in Roadmap.
- Broadcast-room controls inherit the authoritative getters; their
  connecting-state visuals can still be enriched (follow-up).

## ADR-030: The Rooms 2.0 stage is a bounded speaker grid; audiences are numbers, never floating avatars

**Status**: Accepted
**Date**: 2026-08-09

### Context

The community room's orbit layout painted every participant as a
floating avatar around a "heart" — charming at 5 people, unusable at 50,
and its constant orbital animation ran even in silent rooms. Rooms 2.0
requires layouts whose complexity does not grow with audience size.

### Decision

New pure stage system in
`lib/features/rooms/presentation/widgets/room_stage.dart`
(RoomIdentityCard / SpeakerTile / StageGrid / ListenersStrip), consumed
by the community room and previewable at 2/10/50/500 mocked
participants via `lib/dev/stage_preview.dart`:

- The STAGE shows at most 8 tiles — host, moderators, speakers, ordered
  host → mods → actively-speaking — with a "+N on stage" overflow tile.
  Listeners appear ONLY as a count strip and in the People drawer.
- Speaking state animates per-tile from real LiveKit audio levels; a
  silent stage is a still stage (the orbit's perpetual AnimationController
  is gone).
- The room's identity (name, description/topic, future cover via
  VoiceRoom.imageUrl) is painted INTO the stage; when nobody speaks the
  identity card leans in with a conversation prompt instead of an empty
  center.
- One People drawer (host → speakers → listeners) replaces the two
  separate speaker/listener sheets.

Also fixed while verifying live: the roster-sync race that reverted a
user's own Mute tap (the participants listener force-applied a stale
`isMuted:false` doc). Sync is now ONE-WAY — a moderator's mute is
enforced onto the mic; an unmuted doc never auto-unmutes anyone. Applied
to both room types.

### Consequences

- ~440 lines of orbit/cosmic painting deleted from the community screen.
- The podcast room keeps its red editorial stage (already list-based and
  scalable); it adopts RoomIdentityCard when covers land (M4).
- Stage tiles open the profile preview; moderation stays in the drawer.

## ADR-031: Premium is two surfaces — presentation and plans; the hero is the member's real identity

**Status**: Accepted
**Date**: 2026-08-09

### Context

`PremiumScreen` was one screen doing three jobs: benefit marketing, plan
cards, and purchase entry. The presentation-board mockups (screens 3–4)
separate them: a Premium landing ("More room for your voice.", identity
hero, three benefit cards, "Check plans") and a distinct plans &
purchase page ("Choose your plan", Monthly/Yearly toggle, side-by-side
cards, "Everything Premium includes"). The mockup hero is a generated
marketing portrait — production must not ship fake people.

### Decision

- `PremiumScreen` keeps every existing entry point (settings ×3, upsell
  sheet, creator studio) and the entitlement-stream success flip, but
  its free-member body is now the screen-3 presentation. The "Check
  plans" CTA pushes the new `PremiumPlansScreen`, which owns the plan
  cards and the real `verifyPurchase` call (moved, not duplicated —
  honest decline behavior unchanged). If the entitlement turns premium
  while the plans screen is open, it pops back so `PremiumScreen` plays
  the existing welcome state.
- The hero renders the signed-in member's REAL avatar: canonical
  `UserAvatar` (via `ProfileService.watchCurrentProfile()`) wrapped in
  the canonical `PremiumAvatarFrame`, plus a presentation-only backdrop
  bloom, crown chip and capability pills. No second avatar
  implementation; the frame's subtle in-product treatment is unchanged.
- Copy lives in `PremiumPlans` (data layer): 3 presentation benefit
  cards, the per-plan checklist, and the "Everything Premium includes"
  list — one source so app and marketing surfaces can't drift. Pricing
  is untouched: €9.99 / €89.99 (Best value, ≈ €7.50/month), store
  pricing authoritative once billing adapters exist.
- Both screens take optional injected services (`entitlementService`,
  `profileService`) so widget tests run against fakes.

### Reasoning

Marketing and purchasing have different jobs: the presentation sells the
identity ("this is YOU with Premium" — which is also why the hero must
be the real user, not a fixture), while the plans page handles
comparison and commitment. Splitting them matches the mockup board, the
website flow (landing → /premium), and keeps each screen simple.

### Consequences

- The upsell funnel gained one hop: upsell sheet → presentation → plans.
  Acceptable — the presentation IS the pitch, and "Check plans" is its
  single primary action.
- `PremiumPlansScreen` opened while already premium (only reachable via
  a race) still shows plans; purchase attempts decline server-side as
  before. The free→premium transition path is what auto-pops.
- Purchase feedback remains a snackbar with the server's message —
  live-verified against production `verifyPurchase` (four invocations,
  auth+app VALID, decline message rendered).
