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
| [053](#adr-053-paid-capabilities-come-only-from-the-trusted-entitlement-and-every-entry-boundary-fails-closed) | Paid capabilities come only from the trusted entitlement; every entry boundary fails closed | Accepted | 2026-08-16                           |
| [054](#adr-054-private-account-records-are-split-from-exact-server-owned-public-profiles) | Private account records are split from exact server-owned public profiles | Accepted | 2026-08-16 |
| [055](#adr-055-the-2026-08-16-production-cutover--order-the-deploy-by-what-fails-closed-and-verify-by-fingerprinting-served-bytes) | The 2026-08-16 production cutover — order the deploy by what fails closed, verify by fingerprinting served bytes | Accepted | 2026-08-16 |
| [056](#adr-056-a-moderation-action-belongs-in-a-callable-that-completes-the-whole-removal-not-in-a-rule-that-deletes-one-row) | A moderation action belongs in a callable that completes the whole removal, not in a rule that deletes one row | Accepted | 2026-08-16 |
| [057](#adr-057-voice-moment-recording-splits-only-at-byte-acquisition-and-byte-upload-and-the-server-pins-the-audio-container) | Voice Moment recording splits only at byte acquisition and byte upload; the server pins the audio container | Accepted | 2026-08-17 |
| [058](#adr-058-one-polite-live-region-per-screen-and-errors-go-out-on-the-assertive-channel) | One polite live region per screen; errors go out on the assertive channel | Accepted | 2026-08-17 |
| [059](#adr-059-a-ui-change-is-reviewed-before-it-is-deployed-on-the-same-terms-as-a-rules-change) | A UI change is reviewed before it is deployed, on the same terms as a rules change | Accepted | 2026-08-17 |
| [060](#adr-060-an-explanatory-comment-is-a-claim-measure-it-or-delete-it) | An explanatory comment is a claim — measure it or delete it | Accepted | 2026-08-17 |
| [061](#adr-061-a-callable-that-answers-is-the-whole-write-and-its-client-fallback-must-write-the-same-document) | A callable that answers is the whole write, and its client fallback must write the same document | Accepted | 2026-08-17 |

> **The index is incomplete and has been for a while**: rows for ADR-020
> through ADR-052 were never added, though the records themselves are all
> present below. Noted rather than silently left, and not repaired here —
> it is a mechanical pass of its own. The records are numbered
> chronologically, so browsing the headings works meanwhile.

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

### A bug the tests caught

Writing the reason-picker test surfaced a real defect in the shipped
panel: the message menu was rendered only while the row was hovered, but
opening its popup moves the pointer onto the overlay, which fires the
row's `MouseRegion.onExit` and unmounts the `PopupMenuButton` — and
`PopupMenuButton` silently drops `onSelected` when its State is gone. In
the running app, Report and Delete on a Global message did nothing at
all. The row now tracks `_menuOpen` via `onOpened`/`onCanceled` and keeps
the button mounted while its own menu is open.

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
[SECURITY.md](SECURITY.md#firebase-app-check). This is a real, currently-accepted
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

**Also learned, the hard way**: an earlier fix attempt for
`watchMyCommunities()` never actually worked, despite looking correct on
inspection. Don't trust a `collectionGroup()` rule without an emulator
test that runs the real query (ADR-007).

**Corrected 2026-08-16 — the original wording of this paragraph was wrong,
and wrong in the dangerous direction.** It claimed that combining an
`exists()`-based clause with a provable one via `||` does *not* satisfy
Firestore's collection-group provability check. Three independent emulator
runs this session (cloud-firestore-emulator v1.22.0) reproduce the
opposite: the OR'd rule **is** accepted, and because the `exists()` clause
is a constant with respect to the query, the rule becomes a tautology. The
query then returns **every document in that collection group, across the
whole database** — an unfiltered `collectionGroup('roomMembers')` came back
with every row, and a query filtered to another user's uid returned that
user's rows. So the failure mode is not "the query is rejected"; it is
silent full-collection-group enumeration. Anyone who reads the old wording
would believe such an edit fails closed. It fails open.

Two consequences worth carrying forward. First, the narrowness of the
top-level `match /{path=**}/...` rules is not a tidiness preference — it is
the only thing standing between a filtered feed and a full dump of that
collection group (ADR-006). Never OR anything caller-scoped into one.
Second, and separately verified the same day: a **nested**, parent-scoped
match block takes no part in authorizing a `collectionGroup()` query at
all, even when it is unconditionally permissive. Only the top-level
wildcard block authorizes those queries. This matches Firebase's own
documented rule that rules for `/parent/{id}/coll/{doc}` do not apply to
collection-group queries. The discriminating experiment is the one to
repeat if this is ever questioned again: set the top-level rule to `if
false` **while** the nested rule is `if true` — the query is still denied.
Setting the nested rule to `if false` proves nothing, because Firestore
unions `allow` rules and `false || provable` is allowed either way; that
invalid experiment is what produced two spurious defect reports before
being caught.

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

**Status**: Accepted, amended by
[ADR-053](#adr-053-paid-capabilities-come-only-from-the-trusted-entitlement-and-every-entry-boundary-fails-closed)

**Date**: 2026-08-08

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
  path. Creator and Clubs additionally require their own explicit feature
  flag plus `premiumIdentityEnabled`; active subscription status alone is not
  a capability. A daily sweep only tidies the cosmetic mirror.
- `users/{uid}.premiumIdentity` is the public, server-written mirror
  that lets OTHER users' clients render the premium ring; it is
  deliberately absent from the client-writable allowlist and is never an
  authorization input. The public VIP badge is cosmetic too: neither visible
  badge can unlock a paid tool.
- Server enforcement: ordinary Club `create` requires the Clubs capability;
  `accountType` may change to `creator` only with the Creator capability,
  `official` is never client-settable, and `personal` is always allowed.
  UI gates (PremiumGates, reactive destination guards and upsell sheets) are
  UX boundaries backed by Security Rules, not the security authority.
- **Expiration policy**: nothing is deleted. Clubs created while
  premium remain intact with owner and members; existing memberships,
  invites and direct participation remain free, while More → Clubs and
  creating more ordinary Clubs lock until Premium returns. Family Rooms stay
  free. A lapsed Creator keeps profile/followers/content, while Creator Studio
  locks until Premium returns.
  The rules allow `accountType` to REMAIN `creator` after expiry (the
  gate is on changing INTO creator), which is what makes the
  keep-your-data policy work.
- Purchases: `verifyPurchase` exists and deliberately declines until
  store verification is configured (App Store Server API key / Play
  service account / web provider webhooks). Nothing is ever unlocked on
  a client's claim. `adminSetPremiumEntitlements` (admin/superAdmin
  guarded) is the interim grant path and the testing mechanism.

**Consequences.**
- The original ADR-024 rules were emulator-tested and deployed on 2026-08-08.
  The capability-specific and first-create hardening in ADR-053 is covered by
  the expanded 225-case emulator suite but requires a new manual rules deploy.
  *(Amended 2026-08-16: that deploy has happened — the ADR-053 rules are
  live. The suite has since grown to 318 checks; 225 is kept as the
  historical figure. Note also that the scheduled `expirePremiumIdentity`
  sweep this ADR depends on had never once succeeded in production, for
  want of a deployed composite index — see
  [ADR-055](#adr-055-the-2026-08-16-production-cutover--order-the-deploy-by-what-fails-closed-and-verify-by-fingerprinting-served-bytes).)*
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

## ADR-032: Club lounges are club-identity rooms on the shared community shell; room writers source identity from the profile document

**Status**: Accepted
**Date**: 2026-08-09

### Context

Club lounges were already VoiceRoom documents (`rooms/club_lounge_{id}`,
`experience: community`) but opened in the legacy `VoiceCallScreen` —
outside the Rooms 2.0 stage system, without chat/reactions/moderation,
and with a leave path that never ran the lounge bookkeeping. Board
screen 6 specifies a club-identity room: club banner, stage, audience,
floating recent messages. Separately, live testing exposed that every
roster/member/message write took displayName/photoURL from FirebaseAuth,
which goes stale after profile edits — wrong avatars on stage tiles and
chat rows.

### Decision

- `VoiceRoom` gains an optional `clubId` (maps the field ensureClubLounge
  always wrote; falls back to the `club_lounge_` id prefix). Lounge entry
  points (Home's From your Clubs, Club overview) push `RoomEntryScreen`,
  which routes community-experience rooms — club lounges included — to
  `CommunityVoiceRoomScreen`. No second audio surface (ADR-028 holds).
- The community screen is club-aware, not forked: with a `clubId` it
  watches the club document and renders the club banner (art, name,
  members line, chevron → Club overview) in place of the generic room
  identity card, a "Club Room" top-bar subtitle with the club-teal
  accent (`AppColors.accent` — same identity language as the room
  cards), and a lounge-aware leave (`leaveClubLounge`, which finally has
  a caller — lounges no longer stay live forever).
- New shared `RecentRoomMessages` widget floats the newest two chat
  messages over the stage (board screens 2 and 6) — a window onto the
  existing `rooms/{id}/messages` backend, tap-through to the chat sheet,
  renders nothing when the room has no messages.
- `RoomService._identity()`: all identity writes read `users/{uid}`
  (canonical) with FirebaseAuth as the unseeded fallback.
  `VoiceCallScreen` remains for 1:1 calls only.

### Reasoning

One room shell means club rooms inherit everything the stage system
already does (scaling, moderation, chat, mic state) and everything it
gains later. The identity fix closes the writer-side half of the
canonical-avatar mandate — readers were consolidated in the M1/M2
passes, but stale writes kept re-introducing wrong avatars at the data
layer.

### Consequences

- Club-branch UI (banner, subtitle, teal accent) is code-complete but
  NOT yet verified in a live club room: no controllable account has
  Premium, club creation is Premium-gated, and
  `adminSetPremiumEntitlements` has no caller UI. Unblocking needs an
  owner-side entitlement grant; the live check stays on the ledger.
- Old messages keep their stale sender identity (message docs are
  immutable by rule); correctness applies to new writes.
- The overlay is verified live in a production two-user community room.

## ADR-033: Friend DMs never duplicate into the global bell; the notification document stays as the push carrier

**Status**: Accepted
**Date**: 2026-08-09

### Context

Every DM wrote a `directMessage`/`reply` record into
`users/{recipient}/notifications` — the same collection the global bell
feed and badge read — while the send also incremented the
conversation's `unreadCounts`. One friend DM therefore lit the Chats
badge, the bell screen's "Unread messages" card AND a bell "Activity"
row + badge. The document cannot simply be skipped for friends: it is
what triggers `onNotificationCreated`, the only push path.

### Decision

Routing is decided at the SOURCE and enforced at the storage/query
layer, never cosmetically per screen:

- `MessageService.sendTextMessage` checks whether the recipient is an
  existing friend (own `friends/{recipientId}` doc — fail-open on read
  errors) and passes `suppressBell` to `notify()`.
- `notify()` writes `bellSuppressed: true` only when suppressing, so
  every other notification type keeps its exact legacy document shape.
- `watchNotifications()` and `watchUnreadCount()` exclude suppressed
  records — filtered client-side because a Firestore `isNotEqualTo`
  query would also drop every pre-field legacy document.
- firestore.rules whitelists the optional field and requires it to be a
  bool (emulator-tested; suite now 95 checks).
- A non-friend's message keeps its bell entry — presented as
  "sent you a message request" (friend DMs never reach the bell, so a
  DM row there is by construction a stranger reaching out).
- push.js is untouched: friend DMs still push, copy unchanged.

### Consequences

- Legacy pre-fix friend-DM rows still sit in old feeds until they age
  out of the 50-item window (and now read "message request" — transient
  cosmetic cost accepted over a backfill).
- Suppressed records are never surfaced but are marked read by
  `markAllAsRead` like any other, so nothing accumulates as unread.
- Tests: `test/notification_routing_test.dart` (friend DM → chat YES /
  bell NO with record present; non-friend → bell message request;
  non-chat events → bell; read-state isolation both directions).

## ADR-033a: Notification routing hardened — suppression authority moved to rules; bell feed made flood-immune (amends ADR-033)

**Status**: Accepted
**Date**: 2026-08-09

### Context

ADR-033's first cut had two weaknesses. (1) `bellSuppressed` was
client-trusted: a modified client could write a non-friend DM record
with `bellSuppressed: true`, hiding its message request from the
recipient's bell. (2) `watchNotifications()` filtered suppressed
records AFTER a latest-50 query — enough accumulated friend-DM push
carriers could consume the window and crowd legitimate older bell
events out of the feed.

### Decision

- **Source of authority: firestore.rules.** A create with
  `bellSuppressed == true` is allowed only when
  `users/{recipient}/friends/{sender}` exists — the recipient-side
  friendship doc, written by the acceptance flow and unforgeable by the
  sender. The client's friendship read remains a UX optimization only;
  on a rules denial (asymmetric state) the client retries the record
  VISIBLE, so the recipient still gets it and its push. Denial gives an
  attacker nothing: a client can always simply not write a
  notification; the enforced invariant is that a suppressed record only
  ever exists between actual friends.
- **Flood-immune feed.** `notify()` now ALWAYS writes `bellSuppressed`
  (true/false), and the feed merges two queries: an indexed
  `bellSuppressed == false` query (composite index deployed —
  carriers can never consume its window) and the legacy latest-50 query
  (client-filtered) for pre-field documents, deduped/sorted/capped.
  If the indexed query fails, the feed degrades to exactly the
  pre-hardening behavior.
- **Legacy self-healing.** On feed subscription the client stamps
  `bellSuppressed: false` onto its own pre-field documents (one
  bounded pass over the unlimited unread set + opportunistically over
  the base window) — owner-only, bool-only per rules — after which the
  indexed query covers them permanently. All legacy docs are bell
  events by definition: suppression didn't exist yet.
- **Badge already correct.** `watchUnreadCount()` was and remains an
  UNLIMITED unread query with client-side suppression filtering — it
  counts real unread bell-visible records, never a windowed remainder.
- Push untouched: the carrier doc still fires `onNotificationCreated`;
  preferences behavior unchanged.

### Consequences

- One `exists()` read per suppressed create; one bounded unread fetch
  per feed subscription until legacy docs converge (then zero writes).
- READ legacy docs buried deeper than the base window stay hidden until
  normalized by passing through a window — identical to pre-hardening
  reach, accepted.
- Rules suite 99 checks (non-friend suppression denied; friend
  suppression allowed; visible request allowed; owner backfill allowed;
  cross-user routing rewrite denied). Dart suite: retry-to-visible,
  carrier-flood feed immunity incl. legacy self-heal, flood-proof
  unread count.

## ADR-034: The desktop layout is a presentation shell over the existing navigation, not a second navigation system

**Status**: Accepted
**Date**: 2026-08-09

### Context

The app had ONE layout at every width — the floating dock — so a 1440px
browser rendered a phone UI stretched wide. The desktop reference
(`assets/images/home page assets.png`) specifies a left rail, a Home
right column, and a Premium card. Nothing described in it existed yet:
there was no sidebar, no "Trending Now" card, no "Upgrade to YO Voice
Pro" card and no desktop Profile item to remove.

### Decision

- `MainShell` gains ONE width branch (`>= 1100`). Below it the phone
  path is byte-equivalent to before (the tab content moved into a shared
  `_tabContent()` used by both). Mobile layout, breakpoints and dock are
  untouched.
- `DesktopSidebar` is presentation only: it holds no navigation state
  and defines no routes. Every tap calls back into `MainShell`, which
  stays the single source of truth — Home/Chats/Friends switch the same
  `IndexedStack` index the dock uses; Discover and More reuse
  `MoreDestination` + `showMoreSheet`; Notifications pushes the same
  `NotificationsScreen` the Home bell opens. Nothing is duplicated and
  no destination became unreachable (More still exposes Profile, Clubs,
  Alerts, Awards, Creator Studio, Settings — the sheet is SHARED with
  mobile and was deliberately not modified).
- Profile is deliberately NOT a rail item: the signed-in user is the
  bottom profile card (body → profile, violet gear → the existing
  Settings screen — no duplicate settings surface).
- Home's right column shows `VoiceTrendingCard` (Trending Moments from
  `watchLivePublicRooms`, People to Follow from the existing
  `getFriendSuggestions` callable; each section HIDES when its real
  source is empty rather than showing invented people) and
  `PremiumDesktopCard` (three benefits read from `PremiumPlans.benefits`
  — the same source the mobile presentation and the website use — over
  a gradient "Check plans" CTA into the existing `PremiumScreen`).
- Desktop widgets construct their services defensively: a nav rail must
  degrade to an empty state, never a red error box, when a service can't
  be built (no session yet, dev harness).

### Consequences

- `lib/dev/desktop_preview.dart` (+ launch config, port 5608) renders
  the rail and right column at any width without signing in — the same
  reason profile_preview exists.
- Voice Trending's populated state is covered by widget tests; its live
  populated state in the real app still depends on real live rooms and
  real suggestions existing for the signed-in account.

---

## ADR-035: One launch route (`/app`) owns the hand-off into the application; the Flutter host page paints the app's background

**Repos:** `yovoice-website` (the transition), this repo (`web/index.html`).

### Context

There was no post-landing transition screen. "Open YO Voice" was a
`<Link href={getAppUrl()}>` scattered across seven call sites (header,
hero, download section, platform selector, mobile download, premium
plans, account profile), plus a `window.location.href = APP_URL` inside
the login form. Every one of them was an instant cross-origin jump from
`yovoice.app` to the Flutter web build, and because `web/index.html`
declared no background colour, the browser painted its default white
canvas for everything between navigation and Flutter's first frame — a
white flash at the end of every entry into the product. The auth-gated
pages filled the same moment with a bare `<p>Loading…</p>`.

### Decision

- A single client route, `/app`, plays a ~2.8s entry sequence (mark
  reveal + glow, `YO VOICE`, three rotating phrases, a segmented
  progress indicator) and is the **only** place that navigates to
  `NEXT_PUBLIC_APP_URL`. Every other affordance links to
  `APP_ENTRY_PATH` (`/app`). `getAppUrl()` still exists but is now
  private to the launch route by convention.
- `resolveAuthRedirect()` returns a same-site path in every case
  (`/app` when there is no `?redirect`), so callers use the Next router
  and no longer need a `startsWith("http")` branch.
- Progress is bound to this page's *real* initialization — Firebase auth
  resolving, the mark decoding, `document.fonts.ready` — with a 6s cap.
  Where no measurable signal exists (the destination is a different
  origin and cannot be probed), the three phases act purely as a
  **minimum** timeline. If initialization is slow the bar parks at 92%
  and holds; it never shows an invented percentage.
- The hand-off uses `location.replace()`, not `assign()`.
- `web/index.html` declares `html, body { background: #0D0618 }` plus
  `<meta name="color-scheme" content="dark">` — `AppColors.background`,
  the colour Flutter is about to paint anyway.

### Reasoning

- Seven call sites meant seven chances for the entry experience to
  differ. One route is one behaviour, and moving the destination (e.g.
  to `app.yovoice.app`) stays a single env var change.
- `replace()` rather than `assign()` is what keeps `/app` out of
  history. With `assign()`, Back out of the app lands on `/app`, which
  immediately relaunches and throws the user forward — a back-button
  trap. Verified over CDP: after the hand-off the history is
  `[…, yovoice.app/, app]` with no `/app` entry, and Back returns to the
  landing page.
- The white flash is not fixable from the website side; the destination
  document has to declare its own background. That is why this ADR spans
  both repos.
- The login form and the verify-email success path were switched from
  `router.push` to `router.replace` for the same reason: a consumed
  login/verification screen should not be a Back target.

### Consequences

- `/app` is `noindex` and disallowed in `robots.txt` — it is a hand-off,
  not a page with content.
- `/app` deliberately does **not** gate on authentication. The mobile
  download page could always open the web app while signed out, and the
  Flutter app authenticates independently; gating here would have
  removed working behaviour.
- The `web/index.html` change only takes effect on the next Flutter web
  build + deploy. Until then the flash remains in production.
- Reduced motion renders the final composition statically (mark,
  wordmark, "Create your space") with a plain segmented fill — no phrase
  rotation, no blur, no expanding glow.

---

## ADR-036: Desktop Home is composed of real-source modules; each one states the state it cannot prove

**Status**: Accepted
**Date**: 2026-08-10

### Context

The desktop Home from ADR-034 ("Pulse Home") left three large empty
regions — under the greeting, under the recommendation cards, and under
the Premium card — and carried two actions that duplicated the rail:
a second Moment-creation button (already removed in `5f02271`) and a
"Start a room" button inside the Your circle card. The annotated
reference (`assets/images/Zrzut ekranu 2026-08-10 o 22.11.05.png`) asks
for those regions to be filled with a Moments strip, a Conversations hub
and a followed-creators list, and for the two duplicate actions to go.

Each new module wants a state the schema does not actually record:
"unviewed" Moments, per-club unread counts, a separate "private"
conversation type, and creator activity in rooms they do not host.

### Decision

- Three new desktop-only widgets, each reading an EXISTING service, each
  injectable for tests:
  `DesktopMomentsStrip` (`HomeFeedService.watchSocialMoments` — self +
  friends + following), `DesktopConversations`
  (`MessageService.watchConversations` + `ClubService.watchMyClubs` +
  `FriendService.watchFriends`), `FollowedCreatorsCard`
  (`FollowService.watchFollowing` + `watchLivePublicRooms` +
  `watchSocialMoments`).
- Where a requested state is not in the schema, the module shows the
  closest state the data proves and says so in its doc comment:
  - Moments have **no per-viewer seen flag** and are recorded audio, so
    the ring and the "New" label both mean "posted in the last 24 hours";
    older Moments show their real `durationSeconds` instead. No "Live"
    state on a Moment, ever.
  - Club chat has **no per-member unread counter** (`clubs/{id}/channels/
    {id}/messages` has no read receipts), so club rows carry no unread
    badge. Direct conversations do — from `unreadCounts`.
  - The model has exactly **two** conversation types, club channels and
    1:1 direct conversations. `Private` is therefore every direct
    conversation (the model's own direct/private type) and `Friends` is
    the subset whose counterpart is in `users/{uid}/friends` — a subset,
    not a disjoint bucket.
  - A creator's live signal comes from `rooms.hostId` only. Surfacing
    "speaking in someone else's room" would mean a participant listener
    per live room in the right column; hosting is the case that matters
    and it costs nothing extra.
- `ClubChatService.watchLatestMessage(clubId, channelId)` is added
  because a conversation list needs one message per club and
  `watchMessages` pulls 250. Same collection, same ordering, `limit(1)`.
- `ClubService`'s `FirebaseFunctions` moves from constructor-eager to
  lazy. Only `transferClubOwnershipSelf` uses it, `FirebaseFunctions
  .instance` throws with no Firebase app, and there is no fake for
  cloud_functions — eager resolution made the whole service
  unconstructible in a widget test that only reads clubs.
- The "For you" cards are rebuilt as dark-glass editorial cards
  (cover + LIVE + title + host + topic + real chips + avatar stack +
  count + Join) instead of gradient-filled slabs, and `Your circle`
  trades its "Start a room" button for a real online count and one more
  face.
- Navigation is unchanged in kind: tab-level destinations still go
  through `MainShell._onDestinationSelected` (content slots). Only the
  flows that already own a full-screen route everywhere else — a room,
  a chat, a club, the Following list, the profile preview sheet — push.

### Reasoning

- The alternative for every "missing state" above was to fabricate it
  (a decayed unread guess, a "Live" badge on recorded audio, a third
  conversation bucket). The project's hard rule is that a feature with
  no backing shows as absent, not as invented data — and a state that
  is subtly wrong is worse on a social product than a state that is
  simply not shown.
- Widening the strip to one tile per PERSON (newest Moment) rather than
  one per Moment stops a single prolific poster from filling it.
- Filters are local `setState`, deliberately: the requirement is that
  changing them never rebuilds the desktop shell.
- Near the 1100px breakpoint the centre column is ~490px. Three equal
  live cards there are ~140px each — every room name an ellipsis. The
  row now scrolls at a 194px floor instead of shrinking past readable,
  so nothing is dropped and nothing is illegible.

### Consequences

- Home now opens 3–4 more Firestore listeners on desktop (social
  moments, conversations, my clubs + one per club, following). All are
  per-widget and disposed with it; the club previews are added and
  dropped as the club list changes.
- `DesktopHome` gained a `currentUserId` and eight callbacks. It is a
  wider constructor, but every one of them is wired by `MainShell` to a
  mechanism that already existed.
- A populated desktop Home could never be looked at before shipping —
  every module is data-driven and there is no signed-in session outside
  a real device. `test/desktop_home_preview.dart` fixes that: the
  production widgets against `fake_cloud_firestore`, run with
  `flutter run -d web-server -t test/desktop_home_preview.dart`
  (`?empty=1` for the new-account view). It lives under `test/` because
  the fakes are dev_dependencies and must not be importable from `lib/`.

---

## ADR-037: Global Chat is one canonical public channel, written directly under Security Rules with a rules-enforced rate limit

**Status**: Accepted
**Date**: 2026-08-11

### Context

Desktop Home's Conversations module shipped with an `All` tab that
merged the signed-in user's club and direct conversations into one list.
That is not a community chat — it is a per-user aggregation of private
material, and presenting it as "all" invites exactly the confusion
between public and private messages that a voice-social product cannot
afford. The requirement is a real shared channel: a message one
authenticated member sends appears, in the same conversation, for
everyone else.

Nothing in the data model supported that. `conversations` is strictly
1:1; `clubs/*/channels/*/messages` is member-gated. Neither can be
widened into a public channel without weakening it.

Before designing, the existing safety architecture was audited:
blocking exists (`users/{uid}/blocked/{id}`, enforced pairwise in
rules); platform roles exist as **custom claims** (`request.auth.token
.role`, set only by the admin-gated, audited `assignUserRole`); bans
exist and disable the Firebase Auth account outright; every admin action
writes `adminAuditLogs`. Reporting did **not** exist anywhere, and
neither did any rate limiting.

### Decision

- A new top-level collection, `globalChat/{channelId}/messages`, with
  the channel id **pinned to `main` by the rules themselves** so nobody
  can stand up a parallel "global" channel. It is deliberately not a
  subcollection of anything existing: a public message must not be
  reachable by, or confusable with, the private-message code paths.
- The `All` tab is **removed**. The tabs are `Global` (first, default),
  `Friends`, `Clubs`, `Private`.
- **Sends are direct client writes enforced by Security Rules, not a
  Cloud Function.** Rules require: `senderId == request.auth.uid`;
  `sentAt == request.time`; `senderName` / `senderIsCreator` equal to
  the sender's real `users/{uid}` document; `senderIsStaff` equal to
  the ID token's role claim; content non-blank after `trim()` and
  ≤ 500 characters; `isDeleted == false` on arrival; and an exact
  `keys().hasOnly([...])` allowlist.
- **The rate limiter is also in rules.** Each send is a two-document
  batch: the message plus `globalChat/main/senders/{uid}` set to
  `{lastMessageAt: request.time, lastMessageId: <that message's id>}`.
  The message rule verifies that document *after the same commit* with
  `getAfter()`, and the sender-document rule refuses an update until
  3 s have passed since its previous `lastMessageAt`. Deleting it is
  never allowed, and neither is reading or writing anyone else's.
- Deletion is **soft only**, by the author or by a role-claim
  moderator, with content and authorship frozen by the update rule.
  Hard delete is `if false` for everyone. A new Firestore trigger,
  `onGlobalMessageModerated`, writes an `adminAuditLogs` entry whenever
  the remover is not the author.
- A new `reports` collection: create-only for verified members with
  their own uid, server timestamp and `status: 'open'`; unreadable and
  unmodifiable by members (including their own reports); read and
  triage gated to the role claim.

### Reasoning

- **Why rules and not a callable.** ADR-013 reserves Cloud Functions
  for work rules structurally cannot do, and names "typing a chat
  message" as precisely the interaction where a cold start is felt by a
  person waiting. None of its four conditions apply here: no secret, no
  capability rules cannot compute, no fan-out, no cross-document
  choreography. The usual argument for a callable is rate limiting —
  and the `getAfter()` cooldown removes it. `request.time` is the
  server's clock, so the client never supplies the value being checked.
- **Why `lastMessageId` and not just `lastMessageAt`.** With only a
  timestamp, one batch containing 500 messages plus a single cooldown
  update would satisfy the check for all 500 — each create sees the
  same post-commit state. Binding the cooldown document to one specific
  message id means a commit can satisfy it for at most one message.
  This is covered by a dedicated burst-spam test.
- **Why validate the display name against the profile document.**
  A public feed is an impersonation surface in a way a 1:1 chat is not;
  without the check, any client could post as another member's name or
  as "YO Voice Support". The staff badge is compared to the token claim
  for the same reason, and because SECURITY.md's checklist forbids
  reading a role from a document the affected user can write.
- **Why reporting had to be built.** Shipping a channel open to the
  whole community with block-only tooling would have been shipping an
  abuse surface. This is the smallest secure version consistent with
  the existing patterns, not a moderation product.

### Consequences

- **Blocking is reader-side and one-directional on this channel.** Rules
  cannot filter one shared query differently per reader, and another
  user's blocked list is deliberately unreadable. You never see messages
  from someone you blocked; someone who blocked you can still see yours.
  Making it symmetrical would need a mirrored `blockedBy` edge, i.e. a
  change to the blocking schema, which this change deliberately did not
  touch.
- **Global has no unread badge.** No per-user last-seen marker exists
  for it, and one was not invented. Global messages live in their own
  collection and are never summed into the direct-message unread count.
- **Rate limiting is a floor, not a shield.** 3 s between messages
  (20/min) stops flooding; it does not stop a determined, distributed
  abuser, and there is no content filtering. Combined with
  ADR-004's open App Check gap, a script holding a valid ID token can
  post at that rate.
- **Report triage has no UI.** Reports are recorded and readable only by
  staff — through the Firestore Console until an Admin Center screen
  exists.
- Deploying this needs `firebase deploy --only firestore:rules,functions`
  and one manually created `globalChat/main` document. Until the rules
  ship, every client read of the channel is denied.

---

## ADR-038: Global Chat hardening — account status in rules, no manual channel, structural report uniqueness, two-tier rate limits

**Status**: Accepted (amends ADR-037)
**Date**: 2026-08-11

### Context

ADR-037 shipped Global Chat with rules-enforced direct writes. A
production review found five things that made it unsafe to enable, all
of them holes in the *assumptions* rather than the design:

1. It gated access on `isSignedIn()`, reasoning that a banned account is
   disabled in Firebase Auth and therefore holds no token. That is only
   true for *new* tokens: an ID token already in the client's hands
   stays valid until it expires, so a banned user kept full read/write
   access for up to an hour.
2. It documented "create `globalChat/main` by hand before launch" as a
   deploy step — a production feature depending on someone remembering.
3. `reports` was create-only but otherwise open to flooding: random ids,
   arbitrary target ids, free-text reasons, a client-supplied `status`.
4. The audit trigger called `add()` unconditionally, so an at-least-once
   redelivery would record the same removal twice, and had no tests.
5. The 3 s send floor still allowed 1,200 messages an hour per account.

### Decision

- **Account status is read from a document, not inferred from the
  token.** New rules helpers `isRestrictedAccount(uid)` /
  `isActiveAccount()` read `users/{uid}.banned` — the field
  `functions/admin/users.js`'s `setUserBan` already writes through the
  Admin SDK, and which is absent from the self-write allowlist on
  `users/{userId}`. No second ban system. It gates Global Chat reads,
  sends and soft deletes, plus report creation. `setUserBan` now also
  calls `revokeRefreshTokens`.
- **The manual channel step is gone**, because it was never real:
  Firestore addresses a subcollection independently of its parent, so
  `globalChat/main/messages` works with no `globalChat/main` document.
  The id stays pinned in rules and `allow write: if false` on the
  channel document keeps clients from creating one. Option 2 of the
  brief (a bootstrap script) was not needed and would have added a
  privileged script for nothing.
- **Report uniqueness is structural.** The document id must be
  `{reporterId}_{targetType}_{targetId}`, so a duplicate is a create
  over an existing document — Firestore rejects it with no counter, no
  query and nothing to race. Plus: target must exist, `reportedUserId`
  must be its real owner, `reason` is a closed enum, the note is capped,
  workflow fields are rejected on create, and `reportLimits/{uid}`
  enforces 30 s / 20-per-day.
- **Two-tier send limits.** The sender-state document gained
  `windowStartAt` / `windowCount`; rules enforce the 3 s floor *and*
  200 messages per FIXED one-hour window in the same atomic update, with
  a rollover branch when the hour has fully elapsed. The window tumbles
  rather than slides — `windowStartAt` is pinned at the first message of
  a window — so the honest worst case is 400 across two adjacent hours,
  against 1,200 with the floor alone. The composer reads the
  state to explain which limit was hit and when it lifts.
- **The audit entry id is derived from the CloudEvent id**
  (`globalMessage_${event.id}`), so a redelivery overwrites its own
  record. `writeAuditLog` gained an optional `entryId`; callables keep
  auto-ids.

### Reasoning

- Checking a document costs one rules `get()` per request. That is the
  price of a ban taking effect now instead of within the hour, on a
  surface where the abusive account is exactly the one being removed.
- Structural uniqueness beat every alternative considered: a counter
  races, a query cannot be expressed in rules, and a "has this reporter
  already reported X" check needs a read the reporter is not allowed to
  make. Making the id itself the constraint needs no extra state.
- 200/hour was chosen over something tighter because the limit should be
  invisible to humans and obvious to scripts. Sustained for a full hour
  it is 3.3 messages a minute — far beyond conversation, far below
  useful spam volume. It is a product tradeoff, not a security boundary:
  a determined abuser spreads across accounts.
- The trigger is at-least-once by contract. Anything that writes on
  delivery must be idempotent or it will eventually double-count.

### Consequences

- Every Global Chat read now performs one additional document read for
  the status check. Acceptable; noted here so it is not a surprise in
  billing.
- `bannedUntil` remains informational: nothing expires a ban
  automatically, so a temporary ban ends when an administrator lifts it.
  Rules deny while `banned == true`, full stop.
- Blocking is now documented accurately everywhere: Firestore delivers
  every public message to every active reader, the panel filters blocked
  senders locally and holds the first paint until the block list has
  resolved. It is comfort, not confidentiality.
- Global Chat sends require a verified email — `isVerified()`, the
  project's existing publishing policy (the same gate DMs, rooms, clubs
  and Moments use), reading `request.auth.token.email_verified`. READING
  stays open to unverified accounts, and **reporting is deliberately
  ungated**: that helper's own policy note puts safety actions like
  blocking outside the gate, and someone being harassed on their first
  day must be able to say so.
- The send window is FIXED (tumbling), not rolling, and is now named and
  documented that way everywhere. `windowStartAt` is pinned at the first
  message of a window; nothing decays continuously. Honest consequence:
  straddling a boundary allows up to 400 messages across two adjacent
  hours, versus 1,200 with the 3 s floor alone. A true sliding window
  would need per-message bookkeeping for a 2x tighter bound — not worth
  it here.
- Reporting asks for a reason. The panel previously sent `other` for
  everything, which makes triage close to useless; the menu now opens a
  compact required-reason picker over the enum rules already accept,
  with an optional note bounded to the same 300 characters, and
  deliberate success / duplicate / cooldown / failure states.
- Functions gained tests (seven, `npm test` in `functions/`) with **no new
  dependency**: `functions/node_modules` is tracked in this repository,
  so `firebase-functions-test` would have added ~200 packages to every
  future diff. The trigger's handler is exported alongside the
  `onDocumentUpdated` binding and the tests call it directly against the
  emulator. It covers this trigger only, on purpose. A separate
  `test/global_chat_trigger.smoke.js` (run against the functions
  emulator, outside `npm test`) proves the binding end to end: a real
  soft delete reaches the handler and produces exactly one
  `globalMessage_<eventId>` audit document.
- App Check enforcement stays off; `docs/DEPLOYMENT.md` now carries the
  staged rollout.

---

## ADR-039: The Moderation Center is a staff-gated More destination; triage is a callable, and staff authority is claim + server record

**Status**: Accepted
**Date**: 2026-08-11

### Context

ADR-037/038 gave Global Chat a `reports` collection that only staff can
read and nobody can triage — there was no surface for acting on a
report, and no workflow to act with. Reports accumulated with no way to
resolve them.

Three constraints shaped the design. The desktop navigation contract
(ADR-034) is six rail items and must not grow. Staff roles already exist
as custom claims assigned by `assignUserRole`. And `setUserBan` is gated
to `requireUserManager` — **admin and superAdmin only** — so moderators
have never had the authority to ban.

### Decision

- **Placement**: `MoreDestination.moderation`, listed in the desktop
  More popover ONLY when the account passes the staff check, opening in
  desktop content slot 10 like every other More destination. The rail
  keeps its six items. Nothing pushes a route.
- **Authority is two-factor**: the signed `role` custom claim AND the
  server-written `users/{uid}.role` mirror AND `banned != true`. Both
  are checked by `isActiveStaff()` in rules, by the callable
  server-side, and by the client before it queries anything.
- **Triage is a callable** (`moderateReport`), not a client write.
  `firestore.rules` denies `update`/`delete` on `reports` to everyone,
  staff included, so there is exactly one path that can move a status —
  the one that checks the role, enforces the state machine, detects a
  competing claim, and writes the audit entry.
- **Workflow**: `open → inReview → (resolved | dismissed)`, with
  `resolve`/`dismiss` also legal directly from `open`. Terminal states
  are terminal. A client may write exactly one workflow field on
  create — `status: 'open'`, pinned by rules.
- **Idempotency** is a caller-supplied `requestId`, stored on the report
  as `lastRequestId`. A replay returns the original outcome and writes
  nothing; the audit id is `report_{reportId}_{requestId}`.
- **Remove-and-resolve** soft-deletes the message and resolves the
  report in ONE transaction, and refuses if the message is gone rather
  than half-applying.
- **Banning stays admin-only.** Moderators get an explicit escalation
  note instead of a button that would be refused.

### Reasoning

- **Why the claim is not enough on its own.** A custom claim lives in an
  ID token that stays valid for up to an hour. A moderator removed for
  cause would keep reading the queue for that hour. `assignUserRole`
  already writes the role to the user document synchronously, and that
  field is absent from the self-write allowlist — so requiring both
  makes revocation effective on the next request while keeping the
  unforgeable claim as the primary check. Neither half alone is enough:
  the document is only trustworthy because it is server-written, and
  the claim is only timely because the document backs it.
- **Why a callable here but rules for chat sends.** ADR-013's second and
  fourth conditions both apply: enforcing a state machine, detecting
  that another moderator already claimed the report, and making a retry
  idempotent all need read-then-write atomicity over state the caller
  does not control; and "remove the message AND resolve the report" is
  one decision across two collections that must not half-apply. Unlike a
  chat send, a moderator clicking Resolve can afford a round trip — and
  gets a real answer instead of a permission error.
- **Two audit records per removal, deliberately.** `report_{id}_{req}`
  says "this report was resolved this way by this moderator";
  `globalMessage_{eventId}` (the existing trigger) says "this message
  was removed, and here is what it said". They key on different targets
  and answer different questions; neither duplicates the other.

### Consequences

- Every queue read costs two extra rules `get()`s (ban status + role).
  Acceptable for a staff-only surface with a bounded audience.
- A newly promoted moderator whose token has not refreshed fails
  CLOSED — no access until the claim propagates. That is the safe
  direction, and sign-out/in fixes it immediately.
- Reports created before workflow fields existed are treated as Open by
  both the model and the Function (`report.status ?? 'open'`). The
  collection has never existed in production, so no migration is
  required and none was written.
- One composite index is added: `reports` on `(status ASC, createdAt
  DESC)`. Target and reason are narrowed in memory over one bounded
  page rather than multiplying index combinations.
- Report triage still has no mobile surface, and there is no
  staff-facing view of `adminAuditLogs` — both deliberate for this
  milestone.

## ADR-040: A report's audit trail is served by a scoped callable, not by the admin audit browser; queue filters are server-side clauses

**Status**: Accepted
**Date**: 2026-08-11

### Context

[ADR-039](#adr-039-the-moderation-center-is-a-staff-gated-more-destination-triage-is-a-callable-and-staff-authority-is-claim--server-record)
shipped the Moderation Center with two loose ends it named honestly:
there was no staff-facing view of `adminAuditLogs`, and the target and
reason filters narrowed **one bounded page in memory** rather than
querying.

Both needed closing, and the obvious move for the first one was wrong.
`functions/admin/audit.js` already exposes `listAdminAuditLogs`, and it
is gated on `requireAdminCenterAccess` — which already includes
moderators. But it is a whole-collection browser: unfiltered by default,
free-text search across every field, and it returns `actor.email` and
`target.email`. Pointing the Moderation Center at it would let a
moderator reviewing one spam report page through every ban, role change
and club deletion in the product, with email addresses attached. That is
not a change to the Moderation Center; it is a silent expansion of what
a moderator can see.

The filters were a subtler problem. Narrowing a page in Dart *looks*
right — the wrong rows disappear — while telling the reviewer something
false: "all open spam reports" is really "the spam reports that happened
to fall inside the newest 20 open ones". A report older than the page
window is invisible with no indication that it exists.

### Decision

- **Add `listReportAuditTrail`**, a callable that answers exactly one
  question: what has happened to THIS report, and to the message it is
  about. The caller sends a report id and nothing else that selects
  data; both target ids are read from the report document server-side,
  so no parameter can be pointed at another report or an unrelated
  admin action. `listAdminAuditLogs` is left exactly as it is.
- **Same staff test as everywhere else** — `requireActiveStaff`: signed
  `role` claim, plus the server-written `users/{uid}.role` mirror, plus
  not banned. `adminAuditLogs` stays denied to every client in rules;
  the Admin SDK remains the only reader.
- **Response is an allowlist**, not a document: id, kind, action,
  actorId, actorName (public display name only), actorRole, previous and
  new status, resolution, note, contentRemoved, removedContent,
  createdAt. Strings are capped at 500 characters so a long removed
  message cannot turn the trail into a bulk content export.
- **Two event kinds, never merged.** `reportWorkflow` (how the report
  moved) and `contentModeration` (what happened to the message, and what
  it said) are different facts written by different writers. A
  remove-and-resolve legitimately produces one of each; collapsing them
  would imply every resolution removed content.
- **Every queue filter becomes a server-side equality clause**, with a
  composite index per combination the UI can produce. This supersedes
  ADR-039's in-memory narrowing.

### Reasoning

Least privilege is the whole point of the first decision: the capability
granted is "read this report's history", not "read the audit log". The
scoped callable cannot be talked into more, because there is no argument
that widens it — a bug would have to be introduced, not merely exploited.

Pagination uses `createdAt` as a strict upper bound rather than a
Firestore cursor because the trail is a merge of two independent
queries; a strict `<` advances both together and cannot repeat or skip
across the boundary. Ties break on document id so equal timestamps keep
one stable order across pages.

The index-per-combination cost is four small indexes. The alternative —
a filter that quietly lies about a queue of reports — is not a
performance tradeoff, it is a correctness one, and this is the surface
where "I saw no reports of that kind" has to be true.

### Consequences

- Four `reports` composite indexes and one on
  `adminAuditLogs (targetType, targetId, createdAt DESC)`. All five must
  be deployed and READY before the queue is opened, or its first query
  fails with `FAILED_PRECONDITION`.
- `writeAuditLog` accepts an optional `entryId`; `moderateReport` now
  records the moderator note that went with each transition, so the
  trail shows the note for that action rather than only the report's
  latest one.
- The timeline never inserts an event optimistically. After a confirmed
  action it reloads from the first page, which is what keeps a new event
  from appearing twice.
- `firestore.indexes.json` regained `rooms (isLive, visibility,
  createdAt DESC)`, which existed in production but had drifted out of
  the file. The file is now a superset of production, so an index deploy
  cannot be what removes it.
- Still no mobile moderation surface, and still no staff view of the
  broad audit log — deliberately.

## ADR-041: Friend-request, acceptance and follow notifications are derived from their source documents by Firestore triggers, not written by the acting client

**Status**: Accepted
**Date**: 2026-08-12

### Context

A regression report said notifications were "completely non-functional".
The investigation disproved the two obvious explanations before finding
the real shape of the problem.

*Not* stale rules: the deployed ruleset was read from the Firebase
Console and its notification block is current — the create allowlist
contains `bellSuppressed`, the friends-existence check is present, and
the owner-update rule permits the legacy backfill. *Not* broken client
logic either: running the real `FriendService`, `FollowService` and
`NotificationService` against a fake backend produced exactly one
correct document per event, and replaying the same payload against the
rules emulator was accepted, readable by the recipient through both feed
queries, and correctly deduped on retry.

What the end-to-end reproduction did show is that all three
notifications existed **only** as a second client write issued after the
authoritative write, from inside `try { ... } catch (_) {}`. Three
consequences follow from that shape, independent of any single bug:

- the notification is not a consequence of the event, it is a
  best-effort follow-up. Anything that stops the client between the two
  writes — a denied rule, a dropped connection, a closed tab, a
  navigation — loses it permanently, with no retry;
- every failure is silent. No log, no counter, nothing to inspect. An
  outage of this class can only be discovered by a human noticing that
  something never arrived;
- recipient, actor, type, timestamp and routing were all chosen by the
  sender's client, so the rules had to carry real complexity trying to
  make them unforgeable — and still could not verify the thing that
  actually matters, such as whether a friendship exists at all.

### Decision

Derive all three from the documents that already are the authoritative
record of the event:

- `onFriendRequestCreated` — `users/{userId}/friendRequests/{senderId}`
  created. The path carries both identities, so the recipient is the
  path owner and the actor is the document id. Neither is supplied by a
  caller.
- `onFriendRequestResolved` — the same document **deleted**. The request
  is removed on accept, decline and cancel alike; what separates them is
  whether the friendship now exists, which the acceptance transaction
  commits in the same batch. If it does, the original requester
  (`senderId`) is told that the path owner accepted. If it does not, the
  request was declined or cancelled and nothing is written. This also
  covers the mutual-accept path in `sendFriendRequest` without a special
  case.
- `onFollowerCreated` — `users/{userId}/followers/{followerId}` created.

All three write through the Admin SDK with server timestamps,
`bellSuppressed: false`, a deterministic id (`friendRequest_{actor}`,
`friendAccepted_{actor}`, `follow_{actor}`), and only public actor
fields. `friendRequest`, `friendAccepted` and `follow` were removed from
the client-creatable type list in `firestore.rules`.

### Reasoning

The trigger fires from the committed write and Cloud Functions retries
it, so the notification survives everything that used to lose it. The
deterministic id makes at-least-once delivery safe: a redelivery
overwrites its own record instead of appending a second one, and a
replayed source event is absorbed the same way.

Deleting the request document is a better acceptance signal than a
client-written marker: it needs no schema change, no client cooperation,
and it cannot be produced by a decline, because a decline leaves no
friendship behind. A client marker would have been one more field a
client could get wrong or lie about.

Removing the three types from the client allowlist is what closes the
forgery hole. Rules cannot check whether a friendship exists before
allowing "X accepted your friend request" — a trigger can, because it
reads the friendship itself.

### Consequences

- **Acceptance needs positive evidence, not just an existing
  friendship.** A stale request document sitting beside an
  already-established friendship would otherwise turn any later deletion
  of it — cleanup, an account teardown, a migration — into "X accepted
  your friend request" long after the fact. `onFriendRequestResolved`
  therefore also requires the friendship's `createdAt` to be within
  60 seconds of `event.time`, which a genuine acceptance always is
  because both are committed in the same transaction. Comparing against
  `event.time` rather than `now` keeps the answer identical on every
  retry of the same event. A friendship with no `createdAt` fails closed.
  `blockUser` is already safe without this — it deletes the friendship
  and both request documents in one transaction, so no friendship
  survives for the trigger to find — and all four cases (decline, block,
  stale cleanup, genuine acceptance) are exercised through the real
  exported trigger in `firestore-tests/notifications.smoke.js`.
- **Deploy order is load-bearing**: the Functions must ship BEFORE the
  rules change. Rules first would leave a window where the client is
  denied and no trigger exists yet. This is written into DEPLOYMENT.md.
- `FollowService` no longer takes a `NotificationService`; the two test
  call sites that injected one were updated.
- Client tests for these flows now assert the source documents and the
  absence of a client-written notification; the notification itself is
  proven against the real triggers in
  `firestore-tests/notifications.smoke.js`.
- Notification types still written by clients — club/room invites,
  `directMessage`, `mention`, `reply` — keep the existing path and the
  existing silent-catch weakness. Moving them is the obvious follow-up
  and is not done here.
- Push delivery is unaffected by this change and remains broken on web
  for a separate reason: there is no `web/firebase-messaging-sw.js` and
  `getToken()` is called without a `vapidKey`, so no web client ever
  registers a token for `onNotificationCreated` to send to. Fixing that
  needs a VAPID key, which is out of scope here.

## ADR-042: The activity feed renders on its own terms, and web push fails closed without its key

**Status**: Accepted
**Date**: 2026-08-12

### Context

Two smaller findings from the same investigation as
[ADR-041](#adr-041-friend-request-acceptance-and-follow-notifications-are-derived-from-their-source-documents-by-firestore-triggers-not-written-by-the-acting-client),
both capable of making a working notification system look dead.

The Notifications screen composes three streams — friend requests,
conversations, and the activity feed. It treated them as equals: one
`isLoading` covering all three, and one `hasError` across all three
replacing the entire screen with "Could not load notifications". So a
Chats-side permission error blanked the bell inbox, and one auxiliary
stream stuck in `waiting` held the screen on a spinner indefinitely.

Separately, web push could not work at all: no service worker existed,
and `getToken()` was called with no `vapidKey`. It failed obscurely
rather than saying so.

### Decision

- The **activity feed is canonical**; friend requests and unread
  conversations are auxiliary. Only the feed decides the loading state,
  and only a feed error that left nothing to render is fatal to the
  screen. An auxiliary failure contributes an empty section plus a small
  notice above the feed, which keeps rendering.
- The feed's own error state is **retryable** and distinguishes a
  permission denial from a connection failure.
- Web push is **configuration-gated**: the VAPID public key comes from
  `--dart-define=YOVOICE_WEB_PUSH_VAPID_KEY`. The production key is public
  client configuration and is supplied by the Hosting workflow; with no key
  the app skips web push setup entirely rather than half-attempting it.

### Reasoning

"Some of this screen is missing" is a true statement the user can act
on. "Could not load notifications" when the notifications loaded fine is
not, and it is worse than showing partial data.

Skipping the permission request when the key is absent matters more than
it looks: a browser grants that prompt once. Spending it on a capability
that cannot work costs the user the chance to enable push later.

### Consequences

- `NotificationsScreen` gained optional service and `currentUserId`
  parameters, used only by tests — the auxiliary streams have to be made
  to fail on demand for either regression to be testable at all.
- Production web builds supply the VAPID public key from the Hosting workflow;
  DEPLOYMENT.md records where the key comes from and how local deploy builds
  receive it.
- Notification-path `catch (_) {}` blocks now log a bounded diagnostic
  with no tokens, emails or message content. Behaviour is unchanged;
  only the silence is gone.


## ADR-043: Home is one room board of full-bleed banners; presence, VIP and Follow on the rail come from existing server-written sources

### Context

Home carried three overlapping presentations of the same room stream
(`Live around you`, `Featured Live`, `For you`), so one room could appear
three times on one screen, and the desktop and mobile surfaces had drifted
into different compositions. The redesign mockups asked for a single
vertical board of cover-art banners plus a combined `People & Moments`
rail, on both surfaces.

### Decision

One `HomeRoomBanner`, shared by `DesktopHome` and `MobileHome` via
`lib/features/home/presentation/widgets/shared/home_room_board.dart`,
differing only by a `compact` density flag. The room's cover is the card
background; legibility comes from a two-pass gradient scrim, NOT a
`BackdropFilter`. The banner's face pile reads the room's own
`watchParticipants` stream and opens the existing `RoomRosterList`.

The rail packs one horizontal row: `Your Moment`, then people whose
Moments the circle can hear, then a divider, then friends this account
has not followed yet. Online dots read the friend document's own
`isOnline`; the VIP frame reads `premiumIdentity` — the server-written
public mirror, now also carried on `FriendUser`; `Follow` calls the
existing `FollowService.follow`.

### Reasoning

A `BackdropFilter` per banner is a saved layer per banner. With up to
twelve banners that is a real cost on CanvasKit — measured here as the
screenshot rasteriser going from seconds to minutes per capture, which is
the same work a browser would do. Two gradient passes buy nearly all of
the legibility for none of it.

The rail's follow segment is deliberately drawn from friends-not-yet-
followed rather than a recommendation feed: there is no suggestion
backend, and inventing one would be fabricated activity. A real edge the
user already has is the honest version of "people you could follow".

`premiumIdentity` had to reach `FriendUser`, which is an additive read of
a field Cloud Functions already write — no schema change, and the client
still cannot grant itself the badge.

### Consequences

- `rankRoomsForHome` is the single ordering function for both surfaces;
  its top tier is now actually fed, by `FollowService.watchFollowing`.
- Two write-only roster subscription maps (`_friendRoomNames` on desktop,
  `_peopleInRooms` on mobile) were removed — they opened one Firestore
  listener per visible room to fill a map nothing read.
- The three retired card compositions and their private helpers are
  deleted; `RoomRosterList` survives as the shared roster.
- **A room has no start time in Firestore.** The mockups' `SCHEDULED`
  banner with a date is therefore NOT built: it needs a `scheduledFor`
  field, and adding one is a schema change. A non-live room shows
  `NOT LIVE` and no invented date.
- Likewise there is no sponsor backend, so `SponsoredCard` keeps its
  honest `Sponsored example` placeholder rather than the mockups'
  fictional brand.


## ADR-044: Family Room is a Club with `type: family`, pinned to a deterministic id, with a private read boundary

### Context

Family Room is a permanent, invite-only space for close family. It
overlaps almost entirely with what Club already provides: membership,
roles, invitations, persistent chat, announcements and a private voice
lounge. The open questions were where its data lives, how "one per
account" is enforced, and how its privacy differs from a private club.

### Decision

A Family Room IS a club document with `type: 'family'`. No parallel
collection, membership system or message service. It reuses `clubs/{id}`,
its `members`, `invites`, `channels` and the `club_lounge_{id}` private
room wholesale; the lounge is named "Family Lounge".

The id is deterministic: `family_{uid}`. `firestore.rules` refuses every
other id for a family-type create, which is what makes one-per-account
enforceable server-side.

Creation is one atomic seven-document graph, not permission to reserve the
root alone: the Family root, owner membership, owner's user projection,
default chat, announcements, voice channel and private Family Lounge must all
exist after the same batch. Rules bind the channel types and creators and bind
the voice channel to the lounge room. This prevents a modified or interrupted
client from creating only `clubs/family_{uid}` and permanently self-denying
the one deterministic id. The client may read its own missing canonical id so
reopen and retry can distinguish “not created” from an existing room.

Family creation is exempt from ADR-024's Premium gate; ordinary Club
creation is not, and its rule is unchanged. `ownerId` and `type` are
immutable for every club.

Family Moments live at `clubs/{id}/moments`, NOT in the global
`voiceMoments` collection. Check-ins live at `clubs/{id}/checkIns`.

### Reasoning

Rules cannot count documents. A deterministic id turns "at most one" into
"at most one id", which they can enforce exactly. Being invited into
someone else's family space writes a member document, not a club, so the
limit does not restrict membership.

Family Moments are a subcollection rather than a scoped field on
`voiceMoments` because the private boundary then IS the club membership
check. There is no query anywhere — in this app, the website, or Cloud
Functions — that could sweep a subcollection document into a public feed.
A `spaceId` field on the global collection would have required every
existing and future reader to remember to filter it out; forgetting once
would leak a family's private audio into a public feed.

Type immutability matters more than it looks: without it, one write
relabelling `family` as `community` would strip the read boundary off an
existing space and expose its metadata to every signed-in account.

### Consequences

- `/clubs/{clubId}` read is no longer unconditionally `isSignedIn()`. A
  family space is readable only by members and holders of a live
  invitation. Ordinary clubs are unaffected and pay no extra document
  reads — the `!= 'family'` test short-circuits first.
- Check-ins are append-only, restricted to four statuses, and rules
  actively REJECT `latitude`/`longitude`/`location` keys. They are
  ordinary status updates, not tracking.
- Family Moment audio uses a room-scoped Storage path
  `family_moments/{clubId}/{uid}/…` gated on the same membership document
  via `firestore.exists()` from storage.rules.
- The Storage boundary is preparatory only: production Family Moment
  recording/upload is not shipped and must not be advertised until its
  complete client and lifecycle exist.
- **No end-to-end encryption is claimed or implemented.** Family content
  is protected by Firestore rules and Storage rules, nothing stronger.
- Emulator regressions cover the private boundary and the real seven-write
  creation batch. Root-only, incomplete and malformed channel graphs are
  denied, while the full free-account batch, reopen and invite lifecycle pass.

## ADR-045: One authoritative identity-badge system — owner-guarded derivation, a batched client repository, and a single family of badge widgets

### Context

The public badge mirror (`publicBadges/{uid}`, ADR-list: derived by
Cloud Functions from the authoritative role and `effectiveVip()`) shipped
with no client consumer beyond a one-off read in Staff Center. Meanwhile
surfaces had begun growing their own identity renderings: Global Chat
trusted a `senderIsStaff` flag EMBEDDED IN THE MESSAGE (whatever the
sender's client claimed at write time), the desktop profile card ran its
own capability lookup, and `RoleIdentity` in `core/theme` duplicated the
role palette by hand. Three separate concepts — official role, VIP
entitlement, future achievement cosmetics — were one refactor away from
blurring together. The derivation also had one real hole: `deriveBadge()`
never saw the uid, so a forged or stale `superAdmin` role value in a user
document would have been mirrored — and rendered — as the owner badge.

### Decision

**Server.** `derivePublicRole(uid, user)` is the one function that says
what role the mirror may publish. `superAdmin` passes through only for
the confirmed protected owner (`isConfirmedOwner`, secret present AND
matched — same fail-closed-in-both-directions rule as the capability
matrix); any other uid carrying it is published as `superModerator` (the
tier deriveCapabilities() actually grants it) and raises the existing
`security_alert_non_owner_super_admin` audit event with
`attempted: badgeDerivation`. The `getPublicBadges` callable applies the
same demotion to STORED rows as defense in depth, and both badge
triggers plus the callable now bind `YOVOICE_PROTECTED_OWNER_UID`. The
backfill refuses to run at all without the owner guard in the
environment — failing safe there would demote the real owner's badge —
and reports `unconfirmedSuperAdmins` as an aggregate count without
blocking apply (the fail-safe badge is exactly the write that heals a
forged row).

**Client.** `PublicIdentityRepository` is the only way a client learns
anyone's role/VIP: it wraps `getPublicBadges` with flush-window batching
(one request per screenful, chunked to the 50-uid bound), in-memory
caching, in-flight dedup, cache clearing on account switch, a
`revision` notifier so a Staff Center role change refreshes every
mounted badge, and `PublicIdentity.fallback` (USER, no VIP) on any
failure. Absence of a badge document is the DESIGNED answer for an
ordinary account, and caches as USER. No surface reads role or VIP from
message documents or other client-written fields anymore.

**Presentation.** One family of widgets in `shared/widgets/identity/` —
`OfficialRoleBadge`, `VipBadge`, `UserIdentityBadges`,
`DecoratedUserAvatar` — renders identity everywhere: profile surfaces,
all four chat kinds, room stages/rosters/participant sheets, Moments,
the People & Moments rail, friends/follow lists, search, Discover, Top
creators, notifications, Staff Center and the Moderation Center. Labels
and colors live once: hexes in `AppColors` (roleUser #9189A6,
guideMaster #35E58D, support #38BDF8, auditor #818CF8, moderator
#A855F7, superModerator #FF6B81, owner #FF3344, vipGold #FFD166),
vocabulary in the `OfficialRole` enum (`superAdmin` on the wire renders
`OWNER · SUPER ADMIN` — safe because the server only publishes it for
the confirmed owner). `RoleIdentity` survives ONLY as the string-keyed
management-surface adapter (Staff Center legitimately shows a non-owner
`superAdmin` as `SUPER ADMIN`), aliasing `AppColors` so the palette
cannot fork again. Three variants (`full`, `compact`, `icon` with
tooltip) plus `Wrap` layout and a `Flexible` label inside the pill keep
narrow surfaces overflow-free without ever hiding the official role. An
ordinary account renders `USER` — visibly, everywhere, on purpose.

**Reserved, not built:** `AchievementStyle` (rank label, rank color,
frame colors, frame asset) is the cosmetic slot for the Achievement Rank
milestone. The contract it must honor when it ships: selection only of a
server-validated, actually-unlocked achievement; cosmetics change rank
text/color/frame ONLY; official role and VIP badges always render first
and cannot be replaced or restyled; reserved names (Owner, Admin,
Moderator, Support, and official-role variants) are refused server-side;
removal/invalidation of an achievement resets the style safely; other
users receive it through the public identity projection, never from
client-supplied fields. Nothing constructs an AchievementStyle today —
there is no selection flow until server-authoritative achievement data
exists.

### Reasoning

The mirror was built precisely so identity could be public without the
user document being public; leaving surfaces to trust message-embedded
flags defeated it. The owner-guard gap was the same class of bug the
capability matrix already solved — solving it AGAIN in the badge path,
with the same fail-safe tier and the same audit event, keeps one
security story rather than two. A repository with flush-window batching
is what makes "badge beside every chat message" affordable: N rows in a
frame collapse to one callable invocation instead of N Firestore reads.

### Consequences

- Global Chat's `senderIsStaff`-driven "Team" chip is gone; the field
  remains in the schema (still written, still validated at send time)
  but renders nothing. The "Creator" chip stays — account type is not a
  role.
- The desktop profile card no longer calls getMyStaffCapabilities for
  display; `DesktopSidebar.capabilityService` remains accepted for
  construction compatibility but feeds nothing.
- Deploy order: Functions (owner-guarded derivation + batch callable
  demotion) BEFORE the client that renders from it; rules are unchanged
  this pass. Backfill re-run (dry-run, then apply) with
  `YOVOICE_PROTECTED_OWNER_UID` exported, to converge any stored row
  written before the guard.
- 21 Functions badge tests (owner vs forged vs unguarded secret, stale
  stored rows, backfill refusal), the rules suite's existing
  publicBadges denials, and a new `identity_badges_test.dart` Flutter
  suite (exact labels/colors, role×VIP coexistence and order, USER
  fallback, batching/chunking/dedup/cache/account-switch, overflow at
  120px, cosmetics-cannot-replace-badges) hold the boundary.

## ADR-046: User search lives in a server-only directory behind an owner callable; Staff Center becomes seven capability-gated sections

### Context

Staff Center's user lookup was broken in production: `users.username` is
stored AS TYPED (seeded verbatim from the display name — "Sieeema"),
while the client lowercased the input into a case-sensitive Firestore
equality — so `sieeema` could never match `Sieeema`, and typing the
exact stored value failed too because the client lowercased it first.
Display-name search did not exist at all, `@` was not stripped, and the
resolution ran as a CLIENT query against `users`. Meanwhile the screen
itself was one card above an empty page.

### Decision

**Directory.** `userDirectory/{uid}` is a server-written search index:
names/username/email as stored PLUS normalized forms (NFKC, trimmed,
whitespace-collapsed, lowercased), the PUBLIC effective role (through
derivePublicRole — a forged superAdmin cannot wear the owner label
here either), VIP/banned/restricted flags and the Auth creation time.
Auth is authoritative for existence: an account with no profile document
is still discoverable. Three triggers (users, vipGrants, restrictions)
keep it converged; `scripts/backfill_directory.js` (dry-run default,
owner-guard env required, aggregate-only output, batched joins — never
one read per account) seeds and heals it. firestore.rules denies every
client read and write: a readable directory would be a user-enumeration
oracle carrying emails.

**Search.** `searchUserDirectory`, PROTECTED-OWNER-ONLY through
requireProtectedOwner (claim + server record + secret-confirmed uid;
forged superAdmin audited on the way out). Modes decided from the
normalized input: exact uid (raw, case-sensitive), email (Auth first —
case-insensitive by construction — then directory equality), name/
username (leading `@` stripped, ≥2 chars, case-insensitive PREFIX over
both normalized fields, exact matches first, always a LIST because
display names are not unique), and filter browse (all/staff/vip/
restricted/banned/recent) over composite-indexed flags. Pages are ≤20
rows; name mode pages a bounded (100/branch) deterministically-ordered
candidate set by offset cursor — honest about its bound instead of
pretending to scan the collection.

**Staff Center.** One screen, seven sections behind an internal rail
(≥980px) or tab chips: Overview, Users, Reports, Rooms & Spaces,
Sanctions, Staff & Roles, Audit Log. Every section renders only when
the SERVER-derived capability backing it exists (owner: all; moderation
tiers: Reports/Rooms/Sanctions) and every number is a real read:
`getStaffOverview` (owner-only count() aggregates + real lists),
ModerationService's live queue, RoomService's live rooms,
`listAdminAuditLogs` (remapped to the FLAT audit schema writeAuditLog
actually stores — the nested mapping it shipped with matched nothing).
The user detail drawer carries authoritative status (getUserRole),
history (audit browser by targetId), hosted public rooms, and the
owner's role/ban actions plus the shared ••• sanctions menu — every
action confirm-with-reason, double-submit-guarded, server-confirmed
before the UI updates, and re-verified server-side.

### Reasoning

Firestore cannot search case-insensitively; the honest fix is a
normalized index maintained where writes already are (triggers), read
where authorization already is (an owner callable). Reusing
derivePublicRole and requireProtectedOwner keeps ONE owner story across
badges, capabilities and search. The one-card screen was replaced with
sections that only exist where a real server operation backs them — no
placeholder counters, and the sections moderation tiers see are exactly
the operations their capabilities grant.

### Consequences

- The client no longer queries `users` for lookup; `StaffUserLookup`
  remains for the authoritative getUserRole detail path.
- New composite indexes: userDirectory flags × createdAt (4), and
  adminAuditLogs action/actorId/targetId × createdAt (3) for the audit
  browser's real filters.
- Deploy order: Functions + rules + indexes, then the directory
  backfill (dry-run, verify aggregates, apply), THEN the client push —
  Hosting auto-deploys on push, so the backend must exist first.
- 21 directory Functions tests (the Sieeema case under five spellings,
  uid/email modes, duplicates, missing profiles, pagination walking all
  matches exactly once, denial for user/mod/superMod/forged-superAdmin
  with the forged case audited, backfill idempotency + orphan sweep +
  owner-guard refusal), 2 overview tests, a userDirectory rules denial
  case, and 15 Staff Center widget tests (gating, real counts, debounce,
  duplicate names, error-vs-empty, pagination, drawer payloads with the
  expectedRole guard, double-submit, 1100px and mobile layouts).

## ADR-047: One shell, one slot per More destination; staff screens adapt chrome to how they were opened; three-breakpoint completeness is a hard rule

### Context

Opening Staff Center from the desktop More popover visibly shifted the
whole page while Moderation opened cleanly. Root cause: `staffCenter`
was the only More destination missing from the shell's desktop slot
map, so it fell through to the pushed `MoreDestinationHost` — which
mounts a SECOND `DesktopSidebar` (whose profile card resolves
asynchronously and pops in) and animates the entire viewport. On
mobile, Moderation was a navigation dead end: the screen accepted
`isRootTab` but never consumed it — no app bar, no Back, no Home — and
its header printed raw claim vocabulary (`superAdmin`).

### Decision

The slot map (`MainShell.desktopSlots`, now public) covers EVERY More
destination except deliberately-pushed Profile, and a contract test
pins that set — a future destination added without a slot fails CI.
Staff screens follow one chrome rule: rendered in a desktop shell slot
(`isRootTab` + wide) they draw NO app bar and show a
`Staff tools / …` context label; pushed as a route they carry a real
app bar with Back, Home and a human-readable role badge (Moderator /
Super Moderator / Admin — never internal claim names). The Moderation
workspace became a console: truthful summary (count() aggregates via
the new `ModerationService.countByStatus`, loaded-count otherwise,
nothing invented), a one-selected status segmented control, search
over the loaded page, filters behind an Apply/Cancel/Clear sheet or
dialog with removable active chips, a 400px master queue splitting at
900px, and cause-specific empty states that never compete. CLAUDE.md
now carries the rule that no user-facing UI feature is complete until
narrow, medium and wide layouts are intentionally implemented and
verified.

### Consequences

- Selecting any More destination swaps the IndexedStack slot: sidebar
  static, no route push, no document scroll, popover closes itself.
- All moderation services, statuses, permissions, confirmation dialogs,
  audit flows, rules and indexes are untouched; the redesign is
  presentation only plus one additive aggregate read.
- Suites updated to the new interface (status tabs and the Filters
  door replaced the pill wall); new `staff_shell_navigation_test.dart`
  holds the slot contract, slot-vs-pushed chrome, Back/Home behavior
  and the phone list→detail flow.

## ADR-048: Global Chat is retired from the app UI and Home previews three real private conversations

### Context

The public Global Chat feed no longer fits the product direction. Home
should instead help a signed-in person resume their own recent conversations
with friends. Deleting its Firestore collection, rules and moderation history
would be a breaking and destructive migration for older clients.

### Decision

Remove Global Chat entry points and live listeners from the mobile and desktop
Home surfaces. Replace them with `Your recent chats`, reading the same
`MessageService.watchConversations` stream used by the inbox. The stream is
already newest-first and excludes conversations archived by the current user;
Home takes at most three and presents them side by side. Each card uses real
conversation metadata, unread state and the existing DM navigation path.
Loading, empty and error states remain explicit. Existing Global Chat backend
data, security rules and moderation references stay in place as a compatibility
boundary, but current navigation exposes no route to the public channel.

### Reasoning

Reusing the inbox stream avoids a second recency definition, query or schema.
Keeping dormant backend records preserves backward compatibility and audit
integrity while fully removing the feature from the current user experience.

### Consequences

- Home opens an existing `ChatScreen`; it does not create conversations or
  fabricate contacts.
- Three cards is the hard display maximum at narrow, medium and wide widths.
- `See all` routes to Chats and the empty-state action routes to Friends.
- A future backend cleanup requires a separately planned migration and client
  compatibility window; it is not implied by this presentation change.

## ADR-049: Achievement updates are one allowed atomic write and Awards reconciles source-owned counters on open

### Context

Achievement source events were present for messages, created rooms and
published Moments, while friends and followers maintain their counters in
their own services. Nevertheless every title remained at zero in production.
`AchievementService` writes `unlockedTitleTimestamps` in the same transaction
as the counter and unlocked ids, but that field was absent from the
`users/{uid}` self-update allowlist. Firestore therefore rejected the entire
transaction. Callers correctly treated tracking as best-effort so a successful
message or room was not rolled back, which made the authorization failure
silent to users.

### Decision

`unlockedTitleTimestamps` is part of the existing achievement write contract
and is allowed only in the account owner's existing self-update field set.
The full atomic shape — source counter, unlocked ids, timestamp map, selected
title and `achievementsUpdatedAt` — is pinned in the rules emulator suite.
New profiles initialize the timestamp map. Opening Awards runs one
`refreshUnlockedTitles` reconciliation before continuing to render the live
profile stream, ensuring counters owned by Friend/Follow services unlock their
titles without waiting for another achievement-specific event. Category chips
show earned/total values so zero progress cannot be mistaken for an empty
catalog.

### Reasoning

Allowing the omitted field restores the transaction the service already
designed; splitting timestamps into a second write would permit partially
updated progress and make recent unlocks unreliable. Reconciliation belongs at
the Awards boundary because it is idempotent, reads existing real counters and
does not fabricate activity.

### Consequences

- Existing accounts self-heal when they next open Awards.
- New source events can persist their metric and unlock in one transaction.
- The client-side counters retain their documented vanity/progress trust model;
  this change does not turn them into security authority.
- Production requires the tested Firestore rules deployment in addition to the
  client release.

## ADR-050: Push presentation is explicit per platform and focused web tabs use an in-app banner

### Context

The activity feed and bell badge proved that notification documents arrived,
but presentation was not guaranteed. Android referenced a channel id without
creating that channel, the server payload did not explicitly select sound or
vibration on Android, and browsers intentionally do not display an incoming
FCM notification automatically while their tab is focused.

### Decision

Create `yovoice_default` as a high-importance, sound-and-vibration-enabled
Android channel before subscribing to foreground messages. Native foreground
delivery uses explicit Android and Darwin presentation settings. The server
payload selects the same channel and default sound/vibration on Android,
default sound and active interruption on APNs, and icon/badge metadata on web.
A focused web tab routes the foreground event into one floating in-app banner,
requests the platform alert sound, and exposes the same deep-link action as a
system notification.

### Reasoning

The Firestore activity record remains the durable source of truth while FCM is
best-effort presentation. Explicit platform configuration prevents device
defaults from silently downgrading the experience, and the in-app web banner
fills the foreground behavior browsers deliberately leave to applications.

### Consequences

- Users receive more than a bell count when notification permission is granted.
- The compact banner replaces the current banner rather than stacking alerts.
- Tapping `Open` follows the existing `NotificationRouter` destination.
- OS/browser permission, Focus/Do Not Disturb and mute settings remain outside
  application control; no implementation can override them.

## ADR-051: The transparent favicon mark is the canonical logo source for every platform

### Context

The browser favicon had already been corrected to use the clean transparent
YO Voice mark, but native launcher generation still read a retired opaque
asset with a black square baked around the symbol. Consequently App Store and
Google Play surfaces could disagree with the favicon even after the web fix.

### Decision

Use `assets/images/yo-voice-favicon-512.png` as the canonical transparent mark
for the Android adaptive foreground and in-app compact logo. Build the opaque
`assets/images/app-store-icon.png` from that exact mark, enlarged slightly for
launcher legibility, on a full-bleed `#0B1026` navy canvas, then derive iOS,
legacy Android, macOS and Windows launchers from it. Keep the web favicon set
transparent. Android uses a reduced adaptive-icon inset so the OS does not
shrink the mark twice.

### Reasoning

One artwork source prevents platform drift. iOS store icons cannot contain
alpha, while adaptive Android and browser icons benefit from transparency, so
separating the mark from the required platform canvas preserves the same
identity without reintroducing an inner square.

### Consequences

- App Store and Google Play use the same symbol and proportions as the
  favicon, at a deliberately larger launcher scale.
- Opaque launcher formats show the product background at their outer edge,
  not a black rectangle around the artwork.
- Future logo changes start from the favicon master and regenerate launchers;
  the retired squared artwork is not a valid generator input.

## ADR-052: The app origin owns the only startup surface and no startup animation imposes a minimum delay

### Context

Entry through the marketing site played a mandatory ~2.8-second `/app`
transition before navigating to Flutter. After authentication resolved,
Flutter independently held signed-in users on a second welcome screen for four
seconds. Direct entry skipped the first screen but still paid the second delay,
so the experience differed by route and animation—not real work—determined how
long users waited.

### Decision

The website `/app` route performs an immediate history-replacing navigation and
renders no transition of its own. The Flutter web host paints one animated
startup composition during actual engine initialization, removes it after
`runApp`, and Auth uses the visually matching `StartupLoadingScreen` only while
its stream is genuinely loading. Signed-in initialization of push/profile
services stays fire-and-forget and `MainShell` renders immediately. Both layers
retain `YO VOICE` and `Create your space`, animated voice rings and a waveform.
The mark is intentionally large and slightly below optical center; `YO VOICE`
renders in front of its lower edge with a dark readability shadow, creating one
matching depth-effect composition on narrow and wide screens. Reduced-motion
users receive a static waveform.

### Reasoning

The destination is the only process that knows when it is ready. Giving it the
startup surface makes landing and direct entry identical, while matching the
HTML bootstrap and first Flutter loading frame prevents a second visual jump.
No animation is allowed to become a minimum timer.

### Consequences

- Landing entry no longer waits 2.8 seconds before starting the app download.
- Returning signed-in users no longer wait an additional four seconds.
- On a fast start the animation may be brief; on a slow start it remains until
  real initialization completes without claiming a percentage.
- Web bootstrap removal is tied to the first Flutter `runApp`; Auth loading,
  error, logged-out and signed-in destinations keep their real state semantics.

## ADR-053: Paid capabilities come only from the trusted entitlement and every entry boundary fails closed

**Status**: Accepted
**Date**: 2026-08-16

### Context

ADR-024 established `entitlements/{uid}` as the subscription authority, but
several surfaces still treated Premium as one broad boolean or relied on an
entry-point button. Creator remained selectable in Edit profile, Creator
Studio and Clubs were unconditionally listed in More, and a destination could
be mounted directly after bypassing the menu. Security Rules checked active
status but did not consistently check the feature-specific flags intended for
future plans. More seriously, `users/{uid}` updates were narrow while the first
document create accepted arbitrary fields; a new account could therefore seed
itself as Creator, Premium or staff before the update protections existed. A
legitimate Premium Club still could not be created either: `ClubService`
commits the Club, owner member, user projection, three default channels and
lounge room atomically, while owner/channel rules used pre-write `get()` and
could not see the Club yet. The batch also attempted an unused root-user
`clubCount` update outside the profile allowlist.
The same review found that a pending Club invite authorized creation of a
membership without pinning its role or fields, so a modified client could join
as owner, co-owner or admin and immediately inherit management rights.

### Decision

- `entitlements/{uid}` remains the only paid-access source. Creator account and
  Creator Studio require active time validity, `premiumIdentityEnabled` and
  `creatorEnabled`; Clubs requires active time validity,
  `premiumIdentityEnabled` and `canCreateClubs`. The public
  `users/{uid}.premiumIdentity` mirror and the visible VIP badge are rendering
  data only and never authorize an action.
- Creator, Creator Studio and More → Clubs are checked before navigation. A
  reactive destination guard independently protects stale desktop slots,
  direct mounts and an entitlement that expires while open. Edit profile
  checks again on Save before changing into Creator, so a screen opened while
  entitled cannot commit after expiry. Missing or failed entitlement reads
  resolve to free access.
- Security Rules mirror the client policy through capability-specific helpers.
  Ordinary Club creation requires the Clubs capability and changing into
  Creator requires the Creator capability. The initial `users/{uid}` create is
  now a strict allowlist of non-privileged bootstrap/profile/presence fields;
  an optional `uid` must match the path and an optional `accountType` must be
  `personal`. Partial presence-first documents remain valid, so closing the
  privilege path does not reintroduce the legitimate first-write race.
- Owner-member and default-channel creates use `getAfter()` to validate the
  Club root as it will exist after the same atomic commit. `ClubService` no
  longer writes the unused root-user `clubCount`; joined Clubs remain derived
  from the existing user projection. The emulator case executes the complete
  seven-document production batch rather than proving only the root Club write.
- Invitation acceptance has a distinct narrow boundary: exactly the production
  membership fields are allowed, the persisted inviter must match the pending
  invite, and the role is always `member`. The owner bootstrap remains a
  separate `isClubOwnerAfter()` path, so invitation data can never manufacture
  an organizer role. Its Club-root counter update is valid only in the same
  atomic write that creates that plain membership and deletes the invite; the
  diff permits only `memberCount`, `onlineCount` and server `updatedAt`, with
  both counters increasing exactly once.
- The paid Clubs hub does not redefine club membership. Existing member and
  invite paths remain available without Premium, and Family Room creation
  keeps its separate free deterministic-id rule. Expiry never deletes a Club,
  membership, Creator content or profile state.

### Reasoning

A visible identity label is public and intentionally readable by other users;
making it authorization data would turn a display projection into a privilege
source. Capability flags also need to be checked individually or a future tier
with one disabled feature would silently receive the entire bundle. Checking
both before navigation and at the destination/save boundary prevents stale UI
state from becoming an access bypass, while Security Rules remain the final
authority against a modified client. An allowlist on first create is necessary
because update-only restrictions do not protect a document that does not yet
exist.

### Consequences

- Free and complimentary-VIP accounts see locks and a contextual Premium
  explanation; they do not receive Creator/Studio/Clubs capability from the
  badge. A verified server grant writes entitlement and public identity
  together, so access and visible Premium identity still arrive coherently.
- The full Flutter suite passes 396/396 tests across 41 files. The Firestore
  emulator suite passes 225/225, including forged first-create documents,
  Club-invite role escalation and permission-field smuggling, and
  active subscriptions whose individual feature flags are disabled, plus the
  complete Club + owner member + user projection + three channels + lounge
  room creation batch.
- The updated `firestore.rules` must be deployed manually before the new
  server-side restrictions protect production.
- Real App Store/Google Play verification adapters and the IAP client are still
  unconfigured. `verifyPurchase` therefore continues to decline; today only
  the guarded `adminSetPremiumEntitlements` path can create a working grant.

### Amendment, 2026-08-16 — deployed, and one thing this ADR did not know

The rules deploy this ADR required **has happened**; the restrictions are
live. The 396/396 and 225/225 figures above are kept as the historical
record of what this ADR shipped against — current counts are 521 Flutter
tests across 55 files and 318 rules checks, tracked in
[TESTING.md](TESTING.md#current-counts-2026-08-17).

The unknown: the scheduled `expirePremiumIdentity` sweep this ADR relies
on had **never once succeeded in production**. Its query needs a composite
index on `entitlements(isPremium, currentPeriodEnd)` that was committed
but not deployed, so every run threw `FAILED_PRECONDITION` and Premium
never expired for anyone. The index was deployed 2026-08-16. A successful
run has **not yet been observed in Console → Functions → Logs** — until it
is, treat Premium expiry as fixed-in-principle rather than proven. See
[ADR-055](#adr-055-the-2026-08-16-production-cutover--order-the-deploy-by-what-fails-closed-and-verify-by-fingerprinting-served-bytes).

## ADR-054: Private account records are split from exact server-owned public profiles

**Status**: Accepted
**Date**: 2026-08-16

### Context

The root `users/{uid}` document mixed public profile data with email,
notification preferences, presence, moderation state, staff mirrors and
operational counters. Any signed-in client could fetch another root document,
and staff clients could list the collection. Ordinary people search also
queried that private collection by username or email. Field-level filtering in
Flutter cannot make an over-broad Firestore read private: the full document has
already crossed the authorization boundary.

### Decision

- `users/{uid}` is private account state. A client may get only its own root
  document and may never list the collection. Staff lookup and directory flows
  use protected, server-side, field-picking callables; moderator and even
  super-admin client sessions receive no raw-record bypass.
- `publicProfiles/{uid}` is an exact replacement projection written only by a
  retryable `users/{uid}` trigger. It contains the explicitly public identity,
  biography/language fields and public social counts, never email, preferences,
  presence, role, ban/disable state, device tokens or achievement internals.
  Inactive/deleted accounts have no projection. Writes replace rather than
  merge so an accidental extra field is healed on the next sync.
- Presence is a separate `socialPresence/{uid}` projection. Its known-document
  read requires the caller to be the account or both canonical friendship
  mirrors to exist. Neither projection is listable or client-writable.
- Ordinary people search uses `searchPublicProfiles`, not Firestore queries.
  It accepts bounded name/username prefixes only, filters blocks in both
  directions, rechecks candidate account state, and returns an exact five-field
  result. Email search remains an owner-only staff capability in the protected
  directory. Because App Check enforcement is still off, every search attempt
  consumes transactional per-uid fixed-window budgets before querying: 30 per
  minute and 300 per hour. Quota documents are Admin-only.
- New friend requests and conversations store no email snapshot. Parsers keep
  tolerating legacy missing/old fields during rollout, but UI search and cards
  no longer offer or render email identity.
- The projection backfill is dry-run by default, project-pinned, paginated and
  resumable by cursor or uid prefix. It processes at most 200 users / 400
  projection operations in memory and per write batch, and at most 500 users
  per invocation unless the operator explicitly raises the capped run limit.

### Reasoning

Firestore authorizes documents, not selected response fields, so separating
public and private state is the only robust client-direct-read boundary. Exact
server-owned projections prevent privilege or private-field smuggling. A
callable is necessary for prefix search because `allow list: false` is what
prevents enumeration, and its transaction-backed budget limits abuse and cost
before App Check can be enforced. Canonical UIDs remain opaque and
case-sensitive throughout; no identity is trimmed, lowercased or truncated.

### Consequences

- Old app builds that read foreign `users/{uid}` or query `users` will fail
  closed after the rules cutover. Functions and projections must therefore be
  deployed/backfilled first, then updated clients, and only then the private
  rules.
- A missing projection hides the account until the trigger/backfill repairs it;
  it never falls back to the private source in a normal client.
- Existing conversation/request email snapshots are tolerated by parsers but
  no new snapshot is created. A separately reviewed historical scrub can remove
  old values without coupling that destructive migration to this cutover.
- Backfill pages existing source accounts only. It intentionally does not scan
  the full projection collections for orphans; source deletions are cleaned by
  the trigger, and any legacy orphan sweep must be a separate bounded job.
- The Firestore emulator suite passes 265/265, the profile/function security
  suites cover exact projection, replay/idempotency, block filtering, quota
  concurrency/window reset and bounded backfill, and scoped Flutter privacy,
  staff and responsive tests pass. No deployment is performed by this change.

### Amendment, 2026-08-16 — this decision is now live in production

The line above, "No deployment is performed by this change," was accurate
when written and is no longer the current state. The cutover was executed
the same day: functions, client and rules are all deployed, in that order,
and verified. The rules suite has since grown 265 → 301 and the figure
above is left as the historical record of what this ADR shipped against.

**Step 2 of the cutover, the projection backfill, did not run.** Production
holds 33 `users` documents and 1 `publicProfiles` document, counted in the
Firebase console after the rules deploy. The consequence bullet above —
"A missing projection hides the account until the trigger/backfill repairs
it" — is therefore not hypothetical: 32 accounts are currently invisible
to every other user, each repairing itself the moment its owner next opens
the app. Tracked in [Bugs.md](Bugs.md#data-integrity); unblock committed in
`4f9ad47` and not yet run. Execution record:
[ADR-055](#adr-055-the-2026-08-16-production-cutover--order-the-deploy-by-what-fails-closed-and-verify-by-fingerprinting-served-bytes).

## ADR-055: The 2026-08-16 production cutover — order the deploy by what fails closed, and verify by fingerprinting served bytes

**Status**: Accepted
**Date**: 2026-08-16

### Context

Production had drifted a long way from `main`. The Hosting release served
commit `9fdd8a9` while `main` had moved through ADR-051, ADR-052, ADR-053,
ADR-054 and the server-authoritative Stage B work in `c1d6cd9`. Cloud
Functions stood at 51 deployed against a repo that exports well over
twice that. `firestore.indexes.json` held 14 composites and 1
`fieldOverride`; production had the same, including one index that a
deployed scheduled function had needed since it shipped.

Two things caused the drift, and they are worth separating.

The first is a change in this repo's own behaviour that no document
recorded. Until `409c7ee`, pushing to `main` published Hosting, and every
deployment document in this tree was written on that premise — the
2026-08-11 manifest's central warning is literally "treat push to `main`
as a Hosting deploy, and sequence the backend first." `409c7ee` split
verification from release, making Hosting a manual `workflow_dispatch`.
Nothing updated the docs, so the project kept operating on a model in
which the client shipped itself, and it silently stopped doing so.

The second is that "deployed" and "working" are different properties, and
Firebase's tooling reports the first while everyone reads it as the
second. `firebase deploy` printing success means an upload succeeded. The
`expirePremiumIdentity` sweep had been deployed for as long as Premium had
existed, appeared healthy in `functions:list`, and had never once
succeeded: its query needs a composite index on
`entitlements(isPremium, currentPeriodEnd)` that was committed but never
deployed, so every run threw `FAILED_PRECONDITION` and **Premium never
expired for any account**. The emulator does not require composite
indexes, so 510 green Functions tests said nothing about it.

### Decision

- **Order a multi-target deploy by what fails closed.** Deploy the target
  whose absence is a silent no-op before the target whose absence is a
  denial: Cloud Functions and server-owned projections first, then
  clients, then restrictive rules last. ADR-054's cutover order is the
  worked example — rules that make `users/{uid}` owner-only must land
  after the clients that stopped needing foreign reads, or every released
  client breaks at once.
- **Verify every production claim against production, by fingerprinting
  the artifact.** Not the deploy log, not `git log`, not a green suite:
  - Hosting — fetch `https://app.yovoice.app/main.dart.js` and grep it for
    a symbol that exists only in the new build. This release: 5,139,256
    bytes containing `publicProfiles`, `searchPublicProfiles` and
    `selectMyAchievementTitle`.
  - Functions — `firebase functions:list`, and count.
  - Rules — Console → Firestore → Rules version history. There is still no
    read-only CLI command for the deployed ruleset.
  - Indexes — `firebase firestore:indexes`.
- **A deployed function that nothing calls is not evidence of anything.**
  For a scheduled or triggered function, the first real run in
  Console → Functions → Logs is the evidence. Treat a new server-side
  query as an index change until proven otherwise.
- **When a document's premise changes, the document is part of the
  change.** `409c7ee` altered how this repo ships and left five documents
  asserting the opposite. Doc corrections belong in the commit that
  invalidates them.

### Reasoning

Ordering by fail-closed direction is the only rule that survives the CI
model changing underneath it. "Backend first, the client ships itself"
encoded an assumption about the pipeline; "deploy what fails closed
first" encodes a property of the artifacts themselves and stays true
whether Hosting is automatic or manual.

Fingerprinting is required because every cheaper signal has already lied
here. A browser can serve a stale `main.dart.js` — this project's own
CLAUDE.md warns about it. `functions:list` shows a broken scheduled
function as present. A green emulator suite showed nothing about a missing
production index for the entire lifetime of the Premium feature. The
served bytes are the one artifact that cannot be stale relative to itself.

The two failure directions are worth naming as a pair, because the project
has now been bitten by each. Client-ahead-of-backend gives visibly broken
features: a staff account opens Moderation and the call resolves to
nothing. Backend-ahead-of-client gives *invisible* dead code: ~60
functions deployed, healthy, and never invoked. The second is worse to
diagnose precisely because nothing looks wrong.

### Consequences

- Production as of 2026-08-16: 111 Cloud Functions (from 51), 15
  composite indexes and 3 `fieldOverrides` (from 14 and 1), `storage.rules`
  deployed, `firestore.rules` deployed twice (20:40 by the operator, 21:06
  covering `952d8e4`), and the Flutter web client live and fingerprinted at
  `app.yovoice.app`.
- Premium expiry works for the first time. Any account whose
  `currentPeriodEnd` has passed will be expired by the next scheduled
  sweep. **UNVERIFIED**: nobody has yet watched a real run succeed in
  Console → Functions → Logs. Do that before calling Premium expiry
  proven.
- The ADR-054 backfill and scrub both ran the same day, completing the
  cutover 5/5: 28 projection writes (14 accounts), then 21 documents
  scrubbed across four phases with zero conflicts, each verified by a
  re-run that planned nothing further.
- **The ordering thesis of this ADR was proved by violating it.** The
  scrub ran after the rules, and the new rules require a follow edge to
  carry exactly `['uid','followedAt']`. Firestore evaluates list rules per
  document and denies the whole query if one fails, so a single legacy
  five-key edge emptied a user's entire followers/following list. A
  migration step that looks like data hygiene becomes an outage the moment
  rules move ahead of it — "order by what fails closed" has to include the
  data steps, not just the deploy targets.
- Two counting lessons. The apparent gap of "32 of 33 accounts missing a
  projection" was really **14**: 18 of the `users` documents are Auth
  orphans that correctly get none. Comparing the sizes of two collections
  is not a measurement when one is conditionally derived. And a read-only
  sweep of `rooms` found 28 rooms whose `memberCount` disagrees with their
  true row count but **zero trapped** by the counter defect — 24 of them
  carry no `memberCount` field at all, which is exactly the legacy shape
  that would have trapped members had any of them had one.
- `4f9ad47`'s `workflow_dispatch` runner path was dispatched and **failed
  with `7 PERMISSION_DENIED`** — the Hosting service-account secret has no
  Firestore access. It was deliberately not granted any: that secret would
  then reach all production data for anyone with repository write access.
  The backfill ran from the operator's local ADC instead, and the workflow
  stays in the repo as a documented, currently non-functional path.
- `publishPublicStatsSchedule` (`cb4651a`) is committed and deliberately
  undeployed behind three preconditions, and
  `receiveLiveKitAchievementWebhook` is unexported. Neither should be
  swept into the next blanket `--only functions` deploy without reading
  [DEPLOYMENT.md](DEPLOYMENT.md#deliberately-held-back-publishpublicstatsschedule).
- `npm run deploy` inside `functions/` is a full `--only functions` deploy
  with no `--project` pin, and now deploys 111 functions. PROJECT_STRUCTURE.md
  described it as a single-function convenience script until this date.
- **UNVERIFIED**: `NEXT_PUBLIC_APP_URL` in the website repo's three Vercel
  environments. `app.yovoice.app` resolves and serves, but whether the
  website points at it could not be checked from this repo.

## ADR-056: A moderation action belongs in a callable that completes the whole removal, not in a rule that deletes one row

**Status**: Accepted
**Date**: 2026-08-16

### Context

`2fc05e5` closed a real gap: `roomMembers` had no delete path at all, so a
host who privatised a room could not remove anyone and no member could
leave. It added self-leave and host-eviction, each requiring the room's
`memberCount` to decrement in the same commit — the counter transition
being the mechanism that bound the two writes together.

That gating choice was wrong, and it shipped to production.

Hosts can write `rooms/{roomId}.memberCount` directly. So a host could
drive the counter to zero in three plain writes while membership rows
remained, and from then on **nobody could leave and nobody could be
removed** — the decrement the delete required was no longer possible. A
banned host could do it too, because the room-update host branch selects
on `resource.data.hostId == request.auth.uid` and checks no account
status.

It also fired with no attacker at all. Any Community room whose stored
counter had drifted below its true row count was silently un-leavable, and
legacy rooms carrying no `memberCount` field were the clearest case.

Underneath the counter bug was a design error. Deleting a roster row is
not a removal. The evicted account stayed connected to the live audio,
kept chat through `isRoomParticipant`, and could rejoin a public room
immediately. Rules can authorize a write; they cannot disconnect a
participant, revoke a token, or coordinate with LiveKit.

### Decision

- **Remove the rules-level host-eviction path entirely rather than guard
  it.** Not narrow it, not re-gate it on something the host cannot write —
  delete it. No client ever called it, so removing it breaks nothing.
- **Room removal is a callable.** `removeRoomParticipantSelf` already does
  the whole job. If the product wants host-initiated eviction, it gets its
  own callable that completes every part of the removal, in the shape of
  the existing moderation callables.
- **Self-leave stays**, because it binds correctly: it checks
  `!existsAfter` on the caller's *own* row rather than on a counter anyone
  else can move. Its transition now tolerates a room with no `memberCount`
  field instead of erroring, and carries the same `status` /
  `deletionInProgress` guards as the join transition — a member still
  leaves a suspended room; a frozen room refuses the counter write rather
  than trapping them.
- **Accept that `memberCount` can overcount.** A client that deletes a row
  without pairing the room write leaves the counter high. It can never
  undercount below a real departure.

### Reasoning

The decisive property is which direction the error runs. An overcounting
`memberCount` is a wrong number on a screen. An undercounting one was a
trap: members locked into a room with no exit, remotely inducible by a
host and reachable by ordinary drift. **A wrong number beats a trapped
member.**

Gating a delete on a counter the deleting party can also write is a
starvation primitive by construction, and the general lesson is broader
than this rule: if a guard depends on a value the caller controls, the
caller can make the guard unsatisfiable. Prefer `existsAfter()` on the
row being changed over any counter transition.

Removing the path rather than repairing it also collapsed three separate
review findings at once — the starvation primitive, a batch pairing that
could not bind (twenty deletes behind one decrement), and a bypass of the
staff moderation freeze. All three existed only because the rule existed.
A capability nobody calls, that cannot complete the action it names, is
not worth the rules surface it occupies.

And a moderation action is judged by its effect, not its write. "Host
removed a member" that leaves the member speaking in the room is a
feature that lies about what it did — worse than not having it, because a
moderator will believe it worked.

### Consequences

- **Host eviction does not exist anywhere in the product today.** This is
  deliberate, not an oversight, and is recorded as such in
  [Bugs.md](Bugs.md#moderation--safety). Building it means writing a
  callable that removes the roster row, disconnects the participant from
  live audio, and withdraws chat — not re-adding the rule.
- `memberCount` is an upper bound, not an exact count. Anything reading it
  should treat it that way; see [Firebase.md](Firebase.md#firestore-schema).
- Rules suite 294 passed / 7 failed against the live ruleset → **301
  passed / 0 failed**. Storage 46, family-media 11.
- The `collectionGroup()` PROOF cases were hardened in the same commit:
  the variant helper now asserts each snippet is present before
  substituting, so a reformatted rule fails loudly instead of quietly
  running a control that proves nothing. Test scaffolding that can degrade
  into a no-op is a worse failure than a missing test, because it reports
  green.
- **Still open and pre-existing**: the room-update host branch has no
  account-status check, so a banned host can edit room metadata and start
  voice. Not introduced here and not fixed here; see
  [SECURITY.md](SECURITY.md#still-open-pre-existing-live-in-production).
  **Update 2026-08-17**: closed in `c75720a` and deployed. The starvation
  primitive described above therefore no longer has a banned host to
  exercise it — but that is defence in depth, not a reason to reconsider
  removing the eviction rule, which failed with no attacker at all.

---

## ADR-057: Voice Moment recording splits only at byte acquisition and byte upload, and the server pins the audio container

**Status**: Accepted
**Date**: 2026-08-17

### Context

Until `6ef4380`, **no production user could record a Voice Moment at
all.** Web is the only published client. The recorder called
`getTemporaryDirectory()`, which `path_provider` does not implement on
web, and a broad catch turned the resulting `MissingPluginException` into
"Could not start recording". The whole creator content loop was closed,
and the message named nothing that would lead anyone to the platform as
the cause.

The obvious repair — a second web recording screen, or a web-specific
service — would have duplicated reservation, metadata, publish and UI
logic that has nothing platform-specific about it, and duplicated it
around a feature this project has already shown it does not exercise
often enough to keep two copies honest.

The second question was which audio format web should produce. That one
is not open. The deployed backend pins `audio/mp4|m4a|x-m4a` in
`AUDIO_TYPES` and `isAllowedAudioType()`, and `momentStoragePath()` bakes
`.m4a` into the object name. The client has no free choice.

### Decision

Split at exactly two points — **how the bytes are acquired, and how they
are uploaded** — chosen by one conditional export
(`lib/features/moments/data/services/audio_capture/audio_capture_platform.dart`,
`export 'audio_capture_io.dart' if (dart.library.js_interop)
'audio_capture_web.dart'`). Native keeps file → `putFile`; web uses a
MediaRecorder blob → `fetch` → `arrayBuffer` → `putData`. State, service,
reservation, metadata and UI stay single-implementation, written once
against the `AudioCapture` and `VoiceRecorderBackend` interfaces.

Record AAC-LC in an MP4 container everywhere, because that is what the
server accepts. Probe support *before* requesting the microphone, so an
unsupported browser explains itself rather than failing at a permission
prompt.

### Reasoning

**The format was measured, not assumed, and the measurement is
counter-intuitive.** In Chromium 148,
`MediaRecorder.isTypeSupported('audio/mp4;codecs=mp4a')` returns **false**
while `'audio/mp4;codecs=mp4a.40.2'` returns **true** — the more specific
profile string is the supported one. `record_web` tries its candidates in
its own fixed order, so which one the browser accepts decides whether the
recording is publishable at all. Normalizing the codec parameter away
before comparing against the allowlist is **load-bearing**: the rules
compare against a bare set, so `audio/mp4;codecs=mp4a.40.2` matches
nothing unless it is reduced to `audio/mp4` first.

The candidate list is mirrored in `web_mime_negotiation.dart` from
`record_web`'s own `mimeTypes[AudioEncoder.aacLc]` at the pinned version
(record 7.1.1 / record_web 2.1.2), with the selection rule kept free of
`dart:js_interop` so it is unit-testable on the VM. The mirror is a
liability with an expiry date and is commented as one: upgrade
`record_web` and the support answer this screen gives its users is only as
accurate as the mirror.

Keeping the seam this narrow is what makes the format constraint
enforceable. If the platform choice reached further up — into the service
or the screen — there would be more than one place where a container could
be picked, and only one of them would be checked against the server.

### Consequences

- **Recording works on the web.** Suites 486 → **521 tests across 55
  files**; `flutter analyze` clean; `flutter build web` and `flutter build
  ios --simulator` both pass.
- **Firefox is unsupported and says so**, with an honest panel naming the
  reason and an action. It has no MP4/AAC `MediaRecorder`. Supporting it
  is **not a client change**: it needs a coordinated Functions *and* rules
  change — `momentStoragePath()` / `voiceReplyStoragePath()` taking a
  container, `reserveMomentDraft` accepting it, `AUDIO_TYPES` widening,
  `validateMoment()` following. **A rules-only widening fails closed
  against the current server**, which is the trap to avoid. Tracked as
  [Roadmap 0i](Roadmap.md#0i-voice-moment-recording-on-firefox-needs-a-coordinated-backend-change).
- **The waveform now draws real amplitude.** It had been `(index * 17) %
  48` — a fixed pattern that moved identically whether the microphone
  heard anything or not, in direct violation of this project's no-fake-data
  rule, present long enough that nobody questioned it. A meter that moves
  in silence is fabricated audio state, not a placeholder.
- `_publishRecordedMomentLegacy` writes a **14-key** document where
  `validateMoment()` requires exactly **20** and fails `data-loss` on a
  mismatch. Latent only because Stage B is deployed. It needs a deliberate
  decision — delete it or write the canonical shape —
  [Roadmap 0j](Roadmap.md#0j-decide-the-fate-of-_publishrecordedmomentlegacy).
- **UNVERIFIED**: Safari, Firefox's panel in a real Firefox, real
  microphone capture, and an end-to-end publish into production Storage
  and Firestore. Chromium 148's MIME negotiation was checked directly;
  everything else on the web path is seam-tested.

---

## ADR-058: One polite live region per screen, and errors go out on the assertive channel

**Status**: Accepted
**Date**: 2026-08-17

### Context

On the recording screen, a **failed** publish announced a success-sounding
line to assistive technology. Both announcements were correct in isolation.

**Flutter web has no per-node `aria-live`.** `LiveRegion` does not
annotate the widget's own DOM node; it writes into a *single shared*
announcement element and clears it after 300 ms. Two live regions changing
in the same frame therefore overwrite each other, and which one survives is
a race, not a design. Nothing in the widget API suggests this — each
`LiveRegion` reads as though it owns its own region.

### Decision

**One polite live region per screen.** Route every non-urgent status change
through that single region. Errors do not share it: they go out on the
**assertive** channel, which is a separate element and therefore cannot be
overwritten by a polite update landing in the same frame.

A screen that appears to need two polite regions needs one region and a
composed message.

### Reasoning

The failure is silent and direction-dependent: the surviving announcement
is not necessarily the important one, so the bug surfaces as *reassurance
during a failure* — the worst possible direction for a user who cannot see
the screen. It cannot be caught by reading a widget tree, because the tree
looks right.

Separating severity across the two channels is not a stylistic preference
here. It is the mechanism that makes an error announcement survive, given
that the polite channel is a single shared slot.

### Consequences

- The recording screen now has exactly one polite region; publish failures
  announce assertively.
- **Any new screen with more than one changing status must compose, not
  add a second `LiveRegion`.** Treat a second polite region in one screen
  as a defect on sight.
- **UNVERIFIED, and this must not be softened**: no screen reader has been
  run against this screen, or any screen in this project, on any platform.
  The fix is reasoned from Flutter's web `LiveRegion` implementation and
  covered by widget tests; keyboard tabbing is widget-tested only. Real
  VoiceOver/NVDA/TalkBack verification remains outstanding.
- Related, same commit: `record_web` collapses every `getUserMedia`
  rejection to a bare `false`, so absent hardware, a busy device and a
  dismissed prompt all surfaced as "your browser blocked access" — copy
  that blames the user for a hardware condition and points at a setting
  already reading Allow. The flow now calls `getUserMedia` directly and
  maps `DOMException.name`. **The generalizable rule: when a library
  collapses distinguishable failures into a boolean, the copy built on
  that boolean will be confidently wrong.** Also UNVERIFIED against a real
  browser refusal.

---

## ADR-059: A UI change is reviewed before it is deployed, on the same terms as a rules change

**Status**: Accepted
**Date**: 2026-08-17

### Context

On 2026-08-17 the web client was deployed from `6ef4380` **before** the
accessibility and visual reviews returned. The reasoning was defensible:
recording was totally broken for every production user, and a working
screen with defects beats no screen.

Both reviews came back **FAIL**. `cefa81a` closed them.

### Decision

**For a UI change, review precedes deploy** — the same gate this project
already applies without argument to a rules change.

### Reasoning

The deploy was not wrong about the tradeoff; it was wrong about the
timeline. The reviews were already in flight. Waiting would have shipped
the *fixed* version directly, at the cost of a short delay — instead of
shipping a screen that told screen-reader users a failed publish had
succeeded, and then shipping again.

The rules-deploy discipline exists because this project has repeatedly
found that "it passes locally and the fix is urgent" is exactly the
condition under which mistakes ship. A UI change does not have a smaller
blast radius in a product whose only published client is the web app; it
has a *different* one, and it reaches users with less warning because
nothing fails closed.

Urgency is an argument for reviewing faster. It is not an argument for
reviewing afterwards.

### Consequences

- The `6ef4380` deploy was not reverted; the tradeoff it made was
  reasonable and the outcome is now fixed in `cefa81a`.
- **This is a rule, not a suggestion, and it should not be restated as
  one.** If a future session finds itself arguing that a UI defect is
  urgent enough to skip review, that is the case this ADR was written
  about.
- Release-status claims for the recorder must be settled with the DevOps
  and Release Engineer by fingerprinting the served bytes, not inferred
  from the commit being on `main` — see
  [DEPLOYMENT.md](DEPLOYMENT.md#changes-since--2026-08-17).

---

## ADR-060: An explanatory comment is a claim, measure it or delete it

**Status**: Accepted
**Date**: 2026-08-17

### Context

`c7cea3e` corrected a comment in `firestore.rules` that justified a broad
ternary selector by asserting the tighter variant would be **looser** —
that a narrower selector would open a fall-through. An audit built the
tighter variant and measured it against the suite: **identical, denial for
denial.** The fall-through the comment described was real only against the
*previous* `roomMembers` create rule, which `c75720a` — the same change the
comment shipped alongside — had already closed. The comment was justifying
a shape with a mechanism its own commit had removed.

**This is the third such incident in two days.** ADR-005's collectionGroup
paragraph claimed an `exists()`-based widening would fail closed; it fails
**open**, and three emulator runs reproduce the opposite of what the ADR
said. PROJECT_STRUCTURE's description of the deploy script described a
script that did something else. Each was written confidently, by someone
who understood the system, and each was believed for as long as it stood.

### Decision

**An explanatory comment or doc paragraph that asserts a mechanism is a
claim, and carries the same evidence burden as a test.** Before writing
"this is necessary because X would happen", either produce X, or write
what is actually known and say the rest is unverified.

When a change removes a mechanism, **audit what cited that mechanism as a
reason** in the same commit — comments included, not only code.

### Reasoning

The failure mode is not ignorance; it is a correct explanation outliving
the thing it explained. All three incidents share a shape: the claim was
true when written, the surrounding system moved, and the prose stayed
confident. Confident prose is worse than no prose, because it *stops the
next reader from checking* — ADR-005's wrong paragraph directly produced
two spurious defect reports against a rule that was never the problem, and
would have told an engineer that a fail-open edit was safe to try.

Rules comments are a sharper case than most: they are the only in-place
documentation of an authorization decision, and the emulator makes the
counterfactual **cheap to actually run**. There was no reason to assert
the tighter variant was looser rather than build it, which took one audit
to do.

### Consequences

- **The measurement is the deliverable, not the assertion.** "The tighter
  variant denies exactly what the broad one denies, measured against the
  318-case suite" is a durable sentence; "the tighter variant would be
  looser" was not.
- Applies to `docs/` with equal force. Every correction in this repo's
  documentation history — ADR-005, PROJECT_STRUCTURE's deploy script,
  SECURITY.md's "there is no read-only CLI command", TESTING.md's stale
  suite counts — was a confident claim nobody re-derived. When correcting
  one, say what it previously said and why it was wrong; the existing
  entries follow that shape deliberately.
- A claim that cannot be cheaply measured should be labelled UNVERIFIED
  rather than dropped. The goal is calibration, not silence.

## ADR-061: A callable that answers is the whole write, and its client fallback must write the same document

**Status**: Accepted
**Date**: 2026-08-17

### Context

`MessageService.sendTextMessage` called the `sendDirectMessage` callable
and then ran its own client batch write **unconditionally**. The callable
is not a notification hook — it performs the entire send inside one server
transaction: the canonical message document, the conversation summary, the
unread counts and the typing state. The client batch that followed it
wrote a **second** message document under a Firestore auto-id and
incremented `unreadCounts.<recipientId>` a second time. Every direct
message in production was duplicated, and both copies render, because
`watchMessages` orders by `sentAt` with no filter. The early return the
code did have sat on the *fallback* path, where returning early was
harmless.

Two structural facts made this survivable for as long as it lasted. The
suite never executed the branch: every Flutter test injected a
`NotificationService`, which sets `_preferLegacyBehaviour` and
short-circuits `_tryCallable` to `false`. And the duplicate's most visible
symptom was suppressed by the same flag — the legacy notification twin
could never fire on the callable-success path, since `called == true`
implies no legacy notification service.

Re-reading the fallback surfaced a second, independent defect. Its
document was 14 keys; `validateMessage` in
`functions/messaging/direct_integrity.js` compares an **exact** 16-key set
and rejects anything else with `data-loss`. `schemaVersion` and `sequence`
were missing, and the conversation update omitted `lastMessageId` and
`lastMessageSequence`. This is the same latent shape as
`_publishRecordedMomentLegacy` (backlog item 0j).

### Decision

**1. When the callable answers, it is the whole write.** The client write
is the fallback for when the callable does *not* answer — never a
follow-up to when it does. The control flow returns early on success
rather than gating a later block on a flag, so the two paths are visibly
exclusive at the point where the branch is taken.

**2. A fallback must produce a document the server would have produced.**
The client path is now a `runTransaction`, not a `WriteBatch`,
specifically so it can read `lastMessageSequence` off the conversation and
derive `sequence` from it. It writes the full canonical 16-key shape,
advances `lastMessageId` and `lastMessageSequence`, and clamps
`replyToContent` to the server's 240 characters rather than the client
preview's 2000.

### Reasoning

A batch cannot read, and `sequence` has to come from the conversation
document — so "batch or transaction" was never a style question here; the
batch was the reason the shape was wrong. Choosing the cheaper primitive
had quietly decided the schema.

The shape parity matters more than the duplicate does. A duplicate is a
visible defect someone will report. A fallback-written message looks
completely normal in the app and is **permanently unmutable**: edit,
delete, react and reply-to all fail `data-loss` against it, forever, with
no client-side signal at write time that anything is wrong. An exact-key
validator makes every writer of that collection a schema author, so a
second writer that is "close enough" is a data-loss generator, not a
degraded mode.

On the coverage hole: it was as much the bug as the code was. Injecting a
`NotificationService` to get a test double also flipped the production
branch under test, so the suite grew to 521 tests while one side of the
send fork stayed unexecuted. The new tests inject through `functions:`
instead, with a double that performs the server's writes into the fake
Firestore — which is what makes "exactly one message document" a real
assertion rather than a call count.

### Consequences

- **The callable-answered path and the fallback path are now separately
  testable, and both are tested.** `test/direct_message_send_test.dart`
  asserts at Firestore level on each. Against the pre-fix service the
  suite fails 10 cases; the probe reading was `messages=2
  unread[recipient]=2` where 1 and 1 were expected.
- **Any future callable added to `MessageService` inherits this shape.**
  If a callable performs the write, the client returns; if a client
  fallback exists for it, that fallback owes the same document the server
  writes, key for key.
- **A test double that flips a production branch is a coverage hole, not a
  convenience.** Prefer injecting at the seam the production path actually
  uses. Worth checking wherever `_preferLegacyBehaviour` still gates
  behavior.
- The fallback is more expensive than it was — a transaction reads the
  conversation before writing, where the batch read nothing. It runs only
  when the callable is unavailable, so the cost lands on the degraded path
  by design.
- This does not repair the duplicates already in production. They are
  permanent and unmutable; scope, identification and any cleanup are
  tracked in [Bugs.md](Bugs.md#data-integrity).

---

## ADR-062: The client never creates a direct conversation — canonical binding is server-only, and a legacy thread is adopted in place, not forked

**Status**: Accepted
**Date**: 2026-08-17

### Context

[ADR-061](#adr-061-a-callable-that-answers-is-the-whole-write-and-its-client-fallback-must-write-the-same-document)
established that a callable which answers has performed the whole write.
`openOrCreateConversation` had the same fork and had it wrong in a
different, worse way: it called `openDirectConversation`, and on **any**
error `_isCallableUnavailable` recognized, it silently fell through to a
client transaction that created a conversation root itself.

`_isCallableUnavailable` counted `not-found` as "the callable is not
deployed". The server throws `not-found` itself, routinely, as a
legitimate refusal — `functions/integrity/guards.js:157` (`activeProfile`,
"Your profile does not exist."), `functions/messaging/direct_integrity.js:83`
(`conversationParticipants`, "The direct conversation does not exist.")
and `functions/messaging/direct_integrity.js:223` (`validateMessage`). A
user whose `users/{uid}` document was missing therefore got `not-found`
from **every** messaging callable, and the client read each one as an
absent deployment. That silently bypassed `assertNotBlocked`,
`assertNotRestricted` and the rate limits across send, edit, delete,
react, mark-read and typing — the entire server-authoritative guard set,
disabled by a missing profile document. The 32 accounts with no public
profile in [Roadmap 0a](Roadmap.md#0a-run-the-public-profile-backfill-32-accounts-currently-invisible)
are the population most likely to have been in exactly that state.

The conversation root it then wrote is not merely non-canonical, it is
unrepairable from the client. `validateConversation`
(`functions/messaging/direct_integrity.js:125-146`) demands an exact
18-key set; the client wrote 12, missing `pairKey`, `schemaVersion`,
`readSequences`, `participantEmails`, `lastMessageId` and
`lastMessageSequence`. The decisive omission is not a field at all:
`directConversationPairs/{pairKey}`, the guard binding a pair to one
conversation id, which no client can write because that collection has no
rules match block. A root without its guard fails every subsequent server
call with `data-loss`, "The canonical conversation is missing.", forever.

### Decision

The client never creates a direct conversation, at either layer.

1. `_isCallableUnavailable` recognizes only `unimplemented` (and the
   `FirebaseException 'no-app'` case, which is a genuinely appless
   client). `not-found` is a refusal and propagates.
2. `openOrCreateConversation` keeps `openDirectConversation` as its only
   production path, with **no** `_isCallableUnavailable` check at all.
   When the callable answers — success or failure — its answer stands. The
   legacy transaction is reachable only when there is no Firebase app
   (unit tests, previews) or under the legacy `notificationService:`
   harness.
3. `firestore.rules` makes `conversations` create `if false`, so the
   invariant also holds for installs that will never update.
4. `directConversationPairs` keeps **no** match block.
5. Legacy threads are healed by the migration callable that already
   exists, `migrateDirectIntegrityConversation` — adopted in place at
   their legacy id, never forked. No adoption logic is added to the hot
   path.

### Reasoning

**The asymmetry between a message and a conversation root is the whole
decision, and it is what makes this look like a contradiction of ADR-061
when it is not.** ADR-061 was right that `_sendTextMessageDirectly` should
write the exact 16-key canonical message shape. A canonical MESSAGE
asserts only what the client legitimately owns: its own `senderId` and its
own content. A client that writes one is stating true things about itself.

A conversation ROOT asserts three things the client does not own and
cannot be trusted to state:

- **The other participant's display name and photo.** The server derives
  these from the target's public profile via `canonicalPublicProfile`
  ([ADR-054](#adr-054-private-account-records-are-split-from-exact-server-owned-public-profiles)).
  A client-authored root puts up to 80 characters of *attacker-chosen*
  text into `participantNames[victim]`, rendered in the victim's own chat
  list — reopening precisely the boundary ADR-054 closed.
- **Both participants' `unreadCounts` and `readSequences` cursors**,
  including the other party's.
- **Which document id is THE thread for that pair, forever**, through
  `directConversationPairs/{pairKey}`.

So the shape was never what made the client's message write legitimate;
ownership was. Anyone reading only ADR-061 will be tempted to "fix" this
path by making the fallback write the canonical 18 keys. That cannot work
and is not the point: the missing piece is the pair guard, which is
default-denied to every client by design, and the reason it is denied is
that the root asserts facts about someone else.

**The `not-found` ambiguity is irreducible at the wire.** A genuinely
undeployed callable returns HTTP 404 → `NOT_FOUND`, and so does a deployed
handler refusing a missing profile. No client-side inspection separates
them. Given a status code that cannot carry deployment meaning, the only
safe reading is the one that fails closed. `unimplemented` (HTTP 501) is
thrown by no handler in this codebase, so it remains an unambiguous
absence signal.

**In-place adoption over forking.** Before migration, a legacy root at
`uidA_uidB` with no pair guard is not adopted by `openDirectConversation`
— it derives `dm_<hash>`, binds the pair to that, and leaves the legacy
thread and its whole history stranded. Adding adoption to the hot path
would put a second, rarely-exercised branch inside the transaction that
every chat open runs. `migrateDirectIntegrityConversation` already does
this correctly and idempotently, at the legacy id, and it is the right
place for it.

**Keeping the `resource == null` get branch.** Installs already in the
wild still run `transaction.get` on `uidA_uidB` before attempting a
create. Denying that read would be a rules *evaluation* error, which is
what surfaced on web as the boxed "Dart exception thrown from converted
Future" text. Letting the get succeed and the create fail hands those
installs a clean, mappable `permission-denied` instead.

### Consequences

- **`directConversationPairs` having no match block is now a recorded
  decision, not an oversight.** Any future reader who "notices the gap"
  and adds a participant-scoped rule reopens the impersonation vector
  described above. `firestore-tests/rules.test.js` now asserts the
  collection is denied read *and* write for a participant, a
  non-participant and an unauthenticated caller, and that it cannot be
  enumerated.
- **A missing `users/{uid}` document no longer disables the messaging
  guard set.** This is the mechanism that made the defect exploitable and
  it is worth naming twice: `not-found` was read as "not deployed", and
  every server-side block, restriction and rate-limit check was skipped
  for anyone the server could not find. That is now a hard failure.
- **Refusals reach the user.** `openDirectConversation` errors used to be
  swallowed into a local write; they now propagate.
  `friends_screen.dart` and `friend_profile_screen.dart` route them
  through `intentionalOrFriendly`, matching `messages_screen.dart` and
  `profile_preview_sheet.dart`, so no raw exception text reaches the UI.
- **Roots already written by the old fallback are stranded until
  migrated.** They have no pair guard, so every callable refuses them with
  `data-loss`. The migration run is
  [Roadmap 0m](Roadmap.md#0m-run-the-direct-conversation-migration-there-are-stranded-legacy-roots-in-production)
  and has **not** been run.
- **A client with no Firebase app still creates a local root**, and that
  is deliberate — it is what `test/public_profile_privacy_test.dart` and
  the preview harness depend on. `test/direct_conversation_open_test.dart`
  pins it as a strict subset of the canonical 18 keys that is *not equal*
  to them, so the document states in the suite itself that it is
  non-canonical on purpose and may only exist where no server does.
- `functions/test/direct_integrity.test.js` pins the pre-migration fork
  behaviour, so the cost of not running the migration is visible in the
  suite rather than only in production.
