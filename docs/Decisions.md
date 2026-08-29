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
| [066](#adr-066-display-name-changes-are-server-authoritative-and-use-one-fixed-thirty-day-window) | Display-name changes are server-authoritative and use one fixed thirty-day window | Accepted | 2026-08-17 |
| [072](#adr-072-appearance-and-ui-language-are-device-local-preferences-with-explicit-beta-boundaries) | Appearance and UI language are device-local preferences with explicit Beta boundaries | Accepted in source | 2026-08-18 |
| [073](#adr-073-firebase-session-management-exposes-account-wide-revocation-never-a-fabricated-device-list) | Firebase session management exposes account-wide revocation, never a fabricated device list | Accepted in source | 2026-08-18 |
| [074](#adr-074-offline-voice-moments-are-bounded-account-isolated-device-storage-not-a-server-database) | Offline Voice Moments are bounded, account-isolated device storage, not a server database | Accepted in source | 2026-08-18 |
| [077](#adr-077-firestore-backed-storage-rules-require-an-explicit-production-iam-gate) | Firestore-backed Storage Rules require an explicit production IAM gate | Accepted and restored in production | 2026-08-18 |
| [082](#adr-082-a-feature-is-not-shipped-until-a-user-can-reach-it--reachability-is-part-of-done-and-a-green-suite-cannot-prove-it) | A feature is not shipped until a user can reach it — reachability is part of done | Accepted | 2026-08-19 → 2026-08-20 |
| [083](#adr-083-a-firestore-list-rule-is-evaluated-against-the-querys-constraints-so-every-clause-is-a-bare-field-access-and-the-clients-query-carries-the-equality) | A Firestore `list` rule is evaluated against the query's constraints; the client's query carries the equality | Accepted in source | 2026-08-19 |
| [084](#adr-084-client-authored-writes-carry-an-exact-key-allowlist-and-identity-and-time-are-pinned-to-canonical-server-values-or-the-remaining-gap-is-stated) | Client-authored writes carry an exact key allowlist; identity and time are pinned or the gap is stated | Accepted in source | 2026-08-19 |
| [085](#adr-085-authorization-branches-in-a-rule-are-disjoint-by-construction-because-cels--absorbs-errors) | Authorization branches in a rule are disjoint by construction, because CEL's `\|\|` absorbs errors | Accepted in source | 2026-08-19 |
| [086](#adr-086-a-safety-action-is-never-gated-on-email-verification-and-every-moderation-endpoint-checks-access-before-existence) | A safety action is never gated on email verification; access is checked before existence | Accepted in source | 2026-08-20 |
| [087](#adr-087-an-idempotency-key-derived-from-a-request-payload-is-a-compatibility-surface--new-fields-fold-in-only-when-the-target-carries-them) | An idempotency key derived from a payload is a compatibility surface — fields fold in only when present | Accepted in source | 2026-08-20 |
| [088](#adr-088-entering-a-room-performs-the-liveness-transition-through-one-ordered-coordinator-that-mirrors-the-deployed-rule) | Entering a room performs the liveness transition, through one ordered coordinator | Accepted in source | 2026-08-20 |
| [089](#adr-089-moments-is-a-primary-destination-and-its-discovery-feed-ranks-client-side-because-firestore-can-neither-order-by-a-computed-sum-nor-randomise) | Moments is a primary destination; its discovery feed ranks client-side | Accepted in source | 2026-08-19 |
| [090](#adr-090-session-cleanup-converges-on-authservicesignout-because-a-write-the-rules-authorize-by-session-cannot-live-after-the-session-ends) | Session cleanup converges on `AuthService.signOut()` | Accepted in source | 2026-08-19 |
| [115](#adr-115-voice-moment-review-stays-local-availability-is-user-sized-the-root-lifecycle-is-server-authoritative) | Voice Moment review stays local; availability is user-sized; the root lifecycle is server-authoritative | Deployed | 2026-08-27 |
| [116](#adr-116-product-sound-is-a-material-feedback-system-not-a-set-of-jingles) | Product sound is a material feedback system, not a set of jingles | Hosting deployed; native/FCM held | 2026-08-27 |
| [118](#adr-118-premium-pairs-recurring-eur-with-non-renewing-prepaid-blik) | Premium pairs recurring EUR with non-renewing prepaid BLIK | Catalog deployed; provider rollout disabled | 2026-08-28 |
| [119](#adr-119-moderator-premium-preview-is-a-derived-product-benefit-not-a-paid-entitlement) | Moderator Premium preview is a derived product benefit, not a paid entitlement | Implemented; production release pending | 2026-08-28 |
| [120](#adr-120-podcast-studio-uses-the-participant-roster-as-its-production-state) | Podcast Studio uses the participant roster as its production state | Deployed to web and mobile beta | 2026-08-28 |

> **The index is incomplete and has been for a while**: rows for ADR-020
> through ADR-052 were never added, and neither were ADR-062–065,
> ADR-067–071, ADR-075–076, ADR-078–081 or ADR-117, though the records themselves
> are all present below. Noted rather than silently left, and not repaired
> here — it is a mechanical pass of its own. The records are numbered
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

**Status**: Superseded for runtime appearance by ADR-129; dark launch retained
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

Native chrome (status bar style, window background, launch screen) initially
stopped respecting the system's light/dark setting on either platform. That
was correct while the app had no light theme. ADR-129 performs the explicitly
required revisit after Pearl shipped: the branded launch remains dark, while
iOS runtime appearance is no longer application-wide pinned.
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
(recoverEmail + verifyAndChangeEmail), and `/revert-second-factor` for
`revertSecondFactorAddition`. The last route checks the exact action-code
operation on load but calls `applyActionCode` only after a deliberate click;
mail scanners must not remove a legitimate authenticator. All token-bearing
routes send private/no-store, no-referrer and noindex headers. The project-wide
action URL remains intended to be `https://yovoice.app/auth/action`, but may
change only through a supported narrow Firebase admin mechanism after the
website routes are deployed and probed. Firebase stays the sole source of truth
for code validity; nothing is faked client-side.

**Reasoning.** One dispatcher (the console allows exactly one custom
action URL) keeps every mode on a branded page, including the
email-change revocation flow that would otherwise silently regress to
the hosted page. A route handler rather than a page keeps the oobCode
out of rendered HTML and needs no client JS to dispatch. `continueUrl`
is allowlist-validated (`safe-continue-url.ts`) at the dispatcher AND at
each consuming page — it is attacker-controllable input on a page
reached from an email, i.e. a textbook open-redirect vector.

The callback setting is global across reset, verification, email-change and
MFA recovery. Therefore the safe rollout order is website first, production
route/header probes second, a supported leaf-only Auth config change third,
then immediate read-back and real mailbox journeys. A pre-change snapshot and
the identical leaf scope are the rollback boundary; patching the parent
`notification` object would risk the write-only custom-SMTP secret and is
forbidden.

**Release record, 2026-08-27.** Website commit `ce11602` is live and all five
token routes passed production mode/header probes. The narrowly field-masked
callback/template request was rejected with HTTP 400
`EMAIL_TEMPLATE_UPDATE_NOT_ALLOWED`; immediate authenticated read-back proved
that every targeted field remained unchanged. Production email therefore
continues to use Firebase's previous callback and templates. Do not broaden the
mask or overwrite a parent object to work around that backend refusal; the
blocked configuration step remains tracked in
[the email-template runbook](email-templates/README.md).

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
  (monthly €9.99 / yearly €89.99 at the time, centralized in Flutter's
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

**Corrective amendment (2026-08-27, deployed to web from `65c1c5f`; native
store build pending).** The cover
matrix must scale X, Y **and Z** uniformly. `InteractiveViewer` clamps pinch
gestures with `getMaxScaleOnAxis()`; leaving Z at 1 while a large photo's X/Y
cover scale was below 1 made the first pinch multiply the cover scale twice and
shrink the photo into a corner. Pinch/drag are not the only way to operate the
crop: named 44 px Zoom −/+ and four directional controls are available to a
single pointer and keyboard, and the preview exposes its current zoom through
semantics. Widget regressions exercise the actual gesture and controls at
normal and 200% text, confirming that the visible frame stays fully covered.

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
  VoiceRoom.imageUrl) is painted INTO the stage. Silence is represented by
  the real, still stage state; the identity card never invents a
  conversation prompt.
- At desktop widths the bounded workspace is split into a readable voice
  stage on the left and a permanent 350 px room-chat rail on the right. On
  phones and compact tablets, Stage and Chat are separate full-width views,
  so neither is compressed into a miniature column.
- Chat messages live only in the chat surface. Closing compact chat returns
  to the stage; it does not leave a floating latest-message bubble over the
  listener strip.
- One People drawer (host → speakers → listeners) replaces the two
  separate speaker/listener sheets.

Also fixed while verifying live: the roster-sync race that reverted a
user's own Mute tap (the participants listener force-applied a stale
`isMuted:false` doc). Sync is now ONE-WAY — a moderator's mute is
enforced onto the mic; an unmuted doc never auto-unmutes anyone. Applied
to both room types.

### Consequences

- ~440 lines of orbit/cosmic painting deleted from the community screen.
- Community, Podcast, Club and Family rooms share the same responsive
  stage/chat workspace while retaining their own identity palette.
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
  list — one source so app and marketing surfaces can't drift. This ADR's
  historical €9.99 / €89.99 placeholder was superseded by ADR-067: PLN
  19.99/month and PLN 199.99/year (17% saving; ≈ PLN 16.67/month), with Stripe
  Checkout authoritative for the final localized web price. ADR-118 later
  superseded that undeployed catalog with recurring EUR 6/EUR 60 and prepaid,
  non-renewing BLIK PLN 26/PLN 260.
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
- Room chat uses the existing `rooms/{id}/messages` backend in the shared
  responsive workspace from ADR-030: a permanent desktop rail and a
  full-width compact view. The earlier floating latest-message overlay was
  removed because it detached messages from their conversation and collided
  with the listener strip and room controls.
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

**Status**: Partially superseded. The Moments strip
(`DesktopMomentsStrip`) and the followed-creators list
(`FollowedCreatorsCard`) are still in effect, as is the lazy
`FirebaseFunctions` in `ClubService`. Two parts are retired, both by
[ADR-043](#adr-043-home-is-one-room-board-of-full-bleed-banners-presence-vip-and-follow-on-the-rail-come-from-existing-server-written-sources):

- **The Conversations hub is gone.** `DesktopConversations` was dropped
  from `desktop_home.dart` in `98f477d` (the ADR-043 board rebuild, which
  did not say so at the time) and the widget file was deleted in
  `409c7ee`. Home's conversation surface is now DM-only `RecentChats`,
  decided in
  [ADR-048](#adr-048-global-chat-is-retired-from-the-app-ui-and-home-previews-three-real-private-conversations);
  it reads `MessageService.watchConversations` and shows no club rows, so
  the per-club unread and club/private/friends bucketing reasoned about
  below no longer describe a shipped surface.
  `ClubChatService.watchLatestMessage`, added by this ADR for that hub,
  survives with no callers — see its doc comment for why it was kept.
- **The dark-glass "For you" editorial cards are gone.** ADR-043 collapsed
  `Live around you`, `Featured Live` and `For you` into the single
  `HomeRoomBanner` board and deleted all three compositions.

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

**Status**: Superseded by ADR-114
**Date**: 2026-08-12

This section records the historical trigger design. Its trigger smoke was
retired with ADR-114; current lifecycle coverage lives in
`functions/test/social_graph_security.test.js` and the callable binding smoke.

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
  survives for the trigger to find. This trigger-specific coverage was
  retired with ADR-114.
- **Deploy order is load-bearing**: the Functions must ship BEFORE the
  rules change. Rules first would leave a window where the client is
  denied and no trigger exists yet. This is written into DEPLOYMENT.md.
- `FollowService` no longer takes a `NotificationService`; the two test
  call sites that injected one were updated.
- Client tests for these flows asserted the source documents and the absence
  of a client-written notification. ADR-114 replaces the trigger proof with
  direct callable lifecycle and binding coverage.
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

> **Partially superseded by ADR-110 (2026-08-24).** The server-written
> presence/VIP sources and friends-not-yet-followed suggestion pool remain,
> but People & Moments no longer mutates follows inline. Suggestions now open
> the profile, where the relationship action keeps its proper context.

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

> **Presentation amended by ADR-111 (2026-08-24).** The stream, three-item
> maximum, recency, unread state and navigation contract below remain. Only
> the desktop card presentation changes; mobile keeps the original avatar
> cards.

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

Create a high-importance, sound-and-vibration-enabled Android channel before
subscribing to foreground messages. Native foreground delivery uses explicit
Android and Darwin presentation settings. The server payload selects the same
channel and configured sound/vibration on Android,
default sound and active interruption on APNs, and icon/badge metadata on web.
A focused web tab routes the foreground event into one floating in-app banner,
requests the platform alert sound, and exposes the same deep-link action as a
system notification.

### Reasoning

The Firestore activity record remains the durable source of truth while FCM is
best-effort presentation. Explicit platform configuration prevents device
defaults from silently downgrading the experience, and the in-app web banner
fills the foreground behavior browsers deliberately leave to applications.

**Amended by ADR-076.** The shipping channel is the versioned
`yovoice_activity_v2`, with the original `yovoice_notification` sound. The
earlier `yovoice_default`/default-sound names are historical, not an instruction
for current code or deployment.

**Amended by ADR-116 (2026-08-27; Hosting deployed, native/FCM held).** The
Velvet Prism migration uses `yovoice_activity_v3`; Android cannot mutate the
sound of an already-created channel. Production push remains on v2 until the
staged mobile-client and Functions cutover in ADR-116 is completed.

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
transparent. Android uses the generator's standard 16% adaptive-icon inset.
The transparent master already occupies most of its source canvas, so this
keeps the visible mark inside Android's 66dp safe area across OEM masks
without changing the larger iOS/store composition.

### Reasoning

One artwork source prevents platform drift. iOS store icons cannot contain
alpha, while adaptive Android and browser icons benefit from transparency, so
separating the mark from the required platform canvas preserves the same
identity without reintroducing an inner square.

### Consequences

- App Store and Google Play use the same symbol as the favicon, with
  platform-specific safe-area spacing: the larger full-bleed iOS/store
  composition is preserved, while Android adaptive launchers add 16% inset.
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
The native, web-bootstrap and Flutter mark remain centred and fixed at exactly
170 logical pixels;
`YO VOICE` renders in front of its lower edge with a dark readability shadow,
creating one matching depth-effect composition without a centre or size jump.
The stage is positioned independently from supporting copy so font metrics and
200% text cannot move the mark. Auth destinations crossfade from the loading
surface without delaying readiness. Reduced-motion users receive a static
waveform and an immediate state replacement.

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
- iOS and Android own a matching #0D0618 native launch frame and centred mark;
  Android 12+ has matching light/dark system-splash resources.

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
[TESTING.md](TESTING.md#current-counts).

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
profile in [Roadmap 0a](Roadmap.md#0a-run-the-public-profile-backfill-verified-consistent-2026-08-18)
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

## ADR-063: Private conversation media uses a server reservation and web audio preserves the browser-native Blob

**Status:** Accepted — 2026-08-17

### Context

The direct-chat photo and microphone buttons were presentation-only
placeholders. Voice Moment recording did reserve canonical drafts in
production Safari, but no object reached Storage and finalization was never
called. The web recorder converted its native Blob through ArrayBuffer, Dart
`Uint8List` and back into JavaScript bytes before upload. A separate bootstrap
bug could also initialize Admin Storage with a guessed `.appspot.com` bucket
while the client used the configured `.firebasestorage.app` bucket.

Media messages cannot safely be implemented as client-authored public URLs.
The server must bind the object to one canonical conversation/message, and a
lost upload or callable response must not create duplicates.

### Decision

1. A DM photo or voice message begins with
   `reserveDirectMessageAttachment`. The server rechecks the authenticated,
   verified, active participant, both block directions, restrictions and
   quota, then issues a deterministic message id, immutable Storage path and
   15-minute reservation.
2. Storage creation requires that exact reservation, owner, conversation,
   message id, MIME/extension, size, duration and custom metadata. Clients may
   neither update nor delete the object. Reads require an active participant
   in the canonical schema-v2 conversation.
3. `finalizeDirectMessageAttachment` reads the actual object generation and
   metadata, rechecks live access in the transaction and atomically writes the
   message/summary/unread state. The message stores a private `gs://`
   reference; it never stores a download-token URL.
4. Retry keeps the same reservation, object path, generation and finalization
   request id. After a lost upload response the client verifies metadata on
   that path before retrying. Expired reservations and deleted-message media
   enter bounded, idempotent backend cleanup.
5. Web audio uploads retain the browser-native `Blob` and call Firebase
   Storage `putBlob`. Native platforms keep their file upload path.
6. Admin SDK initialization trusts the canonical bucket in `FIREBASE_CONFIG`
   unless an operator explicitly supplies a bucket override. It never derives
   a bucket suffix from `GCLOUD_PROJECT`.

### Consequences

- DM media remains private even if a Firestore document id is guessed.
- Network ambiguity cannot create a second message or silently delete a valid
  object.
- Existing HTTPS media URLs remain readable for legacy messages, but every new
  message uses the private `gs://` contract.
- Functions and Storage rules must be deployed before the Hosting client.
- Automated browser/native seams and emulator rules are release gates; a real
  iPhone Safari publish remains a required post-deploy smoke test.

## ADR-064: Room identity shares one stage; creation type is atomic; Club media is root-first

**Date**: 2026-08-17
**Status**: Accepted

### Context

The four voice-space products had drifted into different visual structures,
while their creation failures had three unrelated causes. Podcast wrote its
authorization-relevant `experience` only after the initial room create;
Family probed a deterministic missing document against an older deployed
ruleset; and ordinary Clubs uploaded artwork before a Premium/quota-bound
Club root existed. The last flow both produced misleading Storage errors and
allowed a modified client to create unbounded orphan objects.

Family artwork also had a more serious privacy problem. Its deterministic
Storage path was publicly readable and a Firebase download-token URL would
continue bypassing membership rules after removal. A green-colored picker
would therefore have advertised privacy the backend could not enforce.

### Decision

1. Community, Podcast, Club Lounge and Family Lounge share one bounded stage
   composition: identity hero, On stage grid, listener strip and adaptive
   controls. Product behavior stays separate. Identity comes only from
   canonical data: room `experience` for Podcast and immutable Club `type`
   for Club versus Family. Palettes are purple, coral/red, gold and emerald.
2. A room writes `experience`, topic, audience policy, hand raising and stage
   limit in the same create as every type-scoped field. `experience` is
   immutable after creation.
3. An ordinary Club is created with null media first. Only its active owner
   may upload deterministic `avatar`/`banner` objects. The callable
   `finalizeClubMedia` rechecks account, owner membership, Club lifecycle,
   projection and lounge; verifies the exact Storage path, generation, MIME
   and size; then atomically mirrors the generation-pinned URL.
4. Family Room artwork is disabled in this release. Its root, owner
   projection and lounge image must remain null, and Storage denies every
   client read/write of Family artwork, including legacy objects. Family
   chat, invitations, check-ins and Lounge remain available.
5. Production errors never instruct users to deploy rules. Those are release
   diagnostics, not actionable UX.

### Consequences

- The four rooms feel like one product without merging their lifecycle or
  authorization models.
- Podcast creation cannot be misclassified as Community by Security Rules.
- Club upload retries are bounded to two canonical objects and cannot mint
  pre-root orphans or attach caller-supplied external URLs.
- Family artwork returns only after an authenticated media resolver and
  synchronous revocation model exist; permanent bearer URLs are not an
  acceptable shortcut.
- This change requires a coordinated Hosting, Functions, Firestore Rules and
  Storage Rules release. Emulator success describes source, not production.

## ADR-065: Creator tools expose truthful snapshots and pin one canonical Voice Moment

**Date**: 2026-08-17
**Status**: Accepted

### Context

Creator Studio advertised Analytics, Pinned posts and Monetization as disabled
future cards. Analytics could provide useful current totals from data already
loaded by the Studio, but the product has no event ledger for listens, unique
reach, historical attendance or trends. A pinned post had no canonical model,
and adding `isPinned` to arbitrary Voice Moments could not enforce one pin per
Creator or cleanly follow Premium expiry.

### Decision

1. Analytics is computed only from the current canonical profile, owned rooms,
   owned Clubs and published Voice Moments captured when the screen opens. Its
   copy says it is a snapshot; load failures are errors, never zeroes.
2. A Creator may pin exactly one canonical published schema-v2 Voice Moment.
   `creatorPinnedPosts/{creatorId}` is an exact, server-owned pointer written
   only by `setCreatorPinnedPost`. Clients may get a known id under active
   account and canonical Premium Creator checks, but cannot list or write.
3. Moment, profile and entitlement triggers remove a stale pointer. Firestore
   Rules repeat the target/account/entitlement checks so trigger delay cannot
   expose a deleted, downgraded or expired Creator pin.
4. The pin appears on both self and foreign full-profile surfaces and streams
   the referenced Moment, so unpublish/delete/re-pin changes fail closed in an
   already-open profile.
5. Monetization remains absent from Creator Studio until a real payment,
   settlement and dispute model exists.

### Consequences

- The Studio has two working tools without presenting invented metrics or a
  dead payment affordance.
- Renewing Premium requires an explicit Creator reactivation after downgrade;
  no copied entitlement expiry lives in the pin document.
- Deploy Functions/triggers and Firestore Rules before the Hosting client.

## ADR-066: Display-name changes are server-authoritative and use one fixed thirty-day window

**Date**: 2026-08-17
**Status**: Accepted

### Context

Flutter and the website could write `users/{uid}.displayName` directly, and
the owner update rule explicitly allowed the field. A client-side date or
disabled text field therefore could not enforce the product limit: a modified,
stale or second client could rename without it. Identity is also mirrored into
Firebase Auth and several server projections, so partial failure must not start
a second cooldown or leave the canonical Firestore record ambiguous.

### Decision

1. `updateMyDisplayName` is the sole post-bootstrap name mutation. It accepts
   one normalized, bounded visible Unicode string from a verified active
   account and transactionally updates `users/{uid}`. A private server-time
   fixed-window record limits each uid to 10 profile-reaching, locally valid
   requests per minute and commits before any profile/Auth read.
2. `displayNameChangedAt` is an optional server-only Timestamp. Its absence is
   legacy state and permits one immediate change. Every actual change starts a
   fixed 30-day window; exact same-name replay changes neither timestamp.
3. Firestore Rules allow initial creation, completion of a partial profile and
   unchanged merged values, but deny an established direct rename and every
   client mutation of the cooldown field.
4. Firestore is canonical. Firebase Auth synchronization happens after commit,
   reads before writing, and can be retried with the same name. A transient Auth
   error does not roll back or consume another window. Existing triggers own
   all public/directory/materialized identity fan-out.
5. The callable returns canonical epoch-millisecond timestamps and structured
   cooldown/Auth-sync reasons so both clients render the same boundary without
   inventing local authority.
6. Its exact success shape is `displayName`, `changed`,
   `displayNameChangedAtMs`, `nextDisplayNameChangeAtMs`, `canChange`. Distinct
   `failed-precondition` reasons identify unverified email
   (`email-verification-required`), malformed server state
   (`display-name-state-invalid`), cooldown (`display-name-cooldown`) and a
   missing Auth mirror (`auth-account-missing`); transient mirror repair uses
   `unavailable` with `auth-display-name-sync-pending`.
7. Client-authored room identity snapshots are bound to the same Firestore
   authority: Broadcast hand requests and Family check-ins must carry the exact
   current `users/{uid}.displayName`. Firebase Auth is a mirror and is not an
   accepted fallback for either write.

### Reasoning

Rules cannot compare a write against a previous write time that the same client
is also allowed to alter, and separate client writes cannot atomically claim a
single window. A transaction on the private canonical document serializes
concurrent names. Firestore-first ordering lets retryable triggers converge
public identity even when Auth has a transient outage; idempotent same-name
retry closes that outage without weakening the limit.

### Consequences

- New clients must use the callable; there is deliberately no direct-write
  fallback for an established name.
- Legacy accounts are not retroactively locked for 30 days because they have no
  trustworthy last-change timestamp.
- The cooldown is 30 exact 24-hour days, not a calendar-month calculation.
- Deploy Functions, then Rules, then clients. The Rules step is the authority
  cutoff; source and production behavior differ until it is deployed.

## ADR-067: Stripe owns payment and cancellation; Firestore owns access; localized prices are finalized only in Checkout

**Status:** superseded by ADR-118 before deployment; retained as the
2026-08-18 historical decision.

YO Voice web billing uses two immutable recurring Stripe Prices on one Product:
PLN 19.99/month and PLN 199.99/year, both `tax_behavior=inclusive`. The app may
show those truthful base prices, but it never performs exchange-rate or tax
math. Stripe Checkout Adaptive Pricing selects and displays the final local
currency/tax before payment. This is deliberately not Stripe manual
`currency_options`, and the catalog says `priceDisplaySource=base` and
`localizedAtCheckout=true`.

Checkout accepts only a plan id. Server configuration supplies the Price,
customer, success/cancel URLs, automatic tax and card payment method. Stripe's
hosted Customer Portal is the only change/cancel surface and its fixed
configuration must allow cancellation plus switching between exactly the two
validated Prices. Suspended users retain Portal access because product access
and the payer's right to cancel are different permissions.

Signed webhooks re-read the canonical Subscription and latest Invoice. A first
grant requires a paid Invoice; an unpaid renewal can retain only the already
paid entitlement window. The private customer binding, entitlement projection
and event receipt commit in one Firestore transaction. Metadata cannot create a
binding. The production Firebase project hard-fails unless Stripe mode, key,
Price and webhook are all live. Auth deletion immediately expires open Checkout
and cancels the canonical customer's subscriptions while retaining the private
binding for refund/dispute/replay reconciliation; late events never recreate a
deleted profile.

`billingAccounts`, `billingRateLimits`, `billingCheckoutLocks` and
`stripeWebhookEvents` are Admin-SDK-only. App Check stays unenforced until the
existing monitored cutover; auth, canonical binding, rate limits, Stripe
signatures and idempotency remain mandatory independently.

The access policy is intentionally narrower than the unresolved financial
policy: `charge.dispute.created` and a full `charge.refunded` immediately revoke
access and cancel every nonterminal subscription for the canonical Customer. A
partial refund preserves access and records a server-only support-review audit;
it never guesses whether the remaining payment merits a prorated entitlement.
Seller-of-record, VAT registration, customer money-return timing and B2B tax-ID
policy remain production blockers until legally approved and configured.

## ADR-068: OAuth handlers are provider-registered endpoints; unavailable identity providers fail closed

**Status:** accepted 2026-08-18; build 6 client recovery deployed to web and
Android internal testing 2026-08-28; signed iOS artifact retained.

Flutter Web previously used the branded `auth.yovoice.app` domain as its
Firebase `authDomain`, even though Google's OAuth client did not register
`https://auth.yovoice.app/__/auth/handler`. A Firebase authorized domain is not
automatically an OAuth redirect URI; the result was a deterministic Google 400
`redirect_uri_mismatch`.

Flutter Web therefore uses Firebase's registered
`yovoice-ec54a.firebaseapp.com` popup handler. The branded Auth domain remains
valid for email action links and can only become the popup handler after the
exact redirect is registered and proven end to end. Android release and debug
certificate fingerprints are separately registered; Play App Signing will add
another identity at store-distribution time.

Apple Auth is additive but must never be represented as available from source
code alone. The client uses Firebase's `AppleAuthProvider` and the same
server-backed social-profile bootstrap as Google, guarded by a build flag and a
runtime Firebase provider probe. Notification/APNs keys are not interchangeable
with Sign in with Apple keys.

**Amended 2026-08-27.** The production Apple provider stack is now configured
for every shipped target, so Apple is enabled by default and can still be
disabled explicitly with `YOVOICE_APPLE_SIGN_IN_ENABLED=false` for an
unconfigured build. The runtime provider probe remains the configuration gate:
a confirmed missing provider disables the action, while a transient network
failure is shown as retriable and is never cached as configuration state.
Android uses Firebase's provider-hosted OAuth flow and is no longer
intentionally unavailable. Signed iOS release artifacts must still prove the
`com.apple.developer.applesignin` entitlement and matching distribution
profile before upload.

Firebase Auth success is the identity boundary: a concurrent Firestore profile
bootstrap failure must not revoke or delete that identity. `AuthGate` withholds
`MainShell`, retries the idempotent canonical profile bootstrap, and exposes
retry or explicit sign-out if it still fails. Profile identity is bounded by
the same UTF-16 length contract as Firestore Rules, and each bootstrap captures
one uid/document reference so an in-flight account switch cannot retarget
provider PII into another account's document. Real-account web/Android/iOS
smoke tests remain release evidence.

## ADR-069: Profile visibility is private source authority, not a cosmetic projection flag

**Status:** accepted in source, not deployed (2026-08-18).

`users/{uid}.profileVisibility` has the exact server-owned values `public`,
`friends` and `private`. Missing legacy state means public; any unknown stored
value fails closed. Clients change it only through the rate-limited
`setMyProfileVisibility` callable. Firestore known-id profile reads, callable
search and the signed-out website showcase all re-check this private source;
`friends` requires two exact server-owned friendship guards.

The public projection is never used as privacy authority. Switching away from
public atomically revokes website consent, clears people from the anonymous
showcase and advances a backend-only privacy generation. A scheduled publisher
that computed against the older generation aborts rather than re-publishing a
newly hidden person. Existing chats remain accessible under their own rules and
use their stored participant label if the profile projection is no longer
readable. Rooms, clubs and existing conversations can still show participation,
which is stated explicitly in the UI.

## ADR-070: Direct-message privacy is recipient-authoritative on every new send

**Status:** accepted in source, not deployed (2026-08-18).

The recipient stores one exact `users/{uid}.messagePrivacy` value:
`everyone`, `peopleYouFollow`, `friends`, or `nobody`. A missing field means
`everyone` only for accounts created before the setting shipped. Any unknown
stored value fails closed. `peopleYouFollow` is deliberately directional: the
recipient must follow the sender. `friends` requires both server-owned
`friendshipGuards`; a client-writable historical friend/follow mirror is never
authorization.

The setting controls delivery, not history. It is re-evaluated when opening a
canonical direct conversation and for every text, photo, and voice send in an
existing conversation. Media reservation and media finalization both recheck
it, so changing the setting during an upload cannot create a message. Existing
history, read receipts, reactions, edits, and deletes remain usable. A block,
inactive account, verification requirement, or sanction remains a separate
stricter denial and always wins.

Callable Functions are the primary authority. Firestore Rules apply the same
recipient check to the legacy direct message-create path so an old or modified
client cannot bypass it. The client may write only its own exact enum value and
shows a responsive settings route; it does not decide whether any sender is
eligible. Relationship checks and the recipient profile are read inside the
same transaction as the canonical write.

This change requires Functions, Firestore Rules, then client deployment. Until
all three ship together, the production UI and production enforcement must not
be described as live.

## ADR-071: Two-factor authentication uses Firebase TOTP and fails closed

**Status:** accepted in source, not deployed (2026-08-18).

YO Voice uses Firebase Identity Platform's TOTP factor rather than implementing
an OTP secret store or choosing SMS. The client asks Firebase for an enrollment
session and secret, presents the standard `otpauth` URI plus a deliberate copy
action, then enrolls only after Firebase validates a six-digit assertion. The
temporary secret remains in memory and is discarded after completion or
cancellation; it is never copied into Firestore, Storage, analytics or logs.

Every primary sign-in surface catches Firebase's multi-factor exception and
resolves the provider-supplied session with the selected canonical TOTP factor.
Settings reads enrolled factors directly from Firebase Auth, supports removal,
and performs primary-provider reauthentication when Firebase requires a recent
login. Unknown or unsupported factor types fail closed with a support message
instead of bypassing the challenge.

The project MFA switch and both client resolvers are one release boundary. TOTP
must not be enabled before compatible Flutter and website clients are deployed,
and the UI must not claim it is live while the project provider is disabled.
SMS MFA remains out of scope because of SIM-swap risk, per-message cost and the
additional phone-data surface. Recovery codes and support recovery require a
separate decision.

## ADR-072: Appearance and UI language are device-local preferences with explicit Beta boundaries

**Status:** Accepted; deployed to web/PWA on 2026-08-18 (`8fa0192`). Native
store release pending.

### Context

Settings exposed Light mode and app language as disabled future rows. The app
also contained two different kinds of legacy surface: widgets already driven
by the shared Material theme, and screens that still own inline dark colors or
English text. A root theme/locale switch can make the first group respond
immediately, but describing the whole product as light-themed or translated
would fabricate coverage in the second group. These are presentation choices,
not account authority or social data.

### Decision

1. Appearance has three exact values: `system`, `dark`, and `light`.
   Language has three exact values: `system`, `english`, and `polish`.
   System language resolves to Polish only for a Polish device locale and to
   English otherwise.
2. Both values are non-sensitive, device-local preferences persisted with
   `shared_preferences`. They do not create a Firestore document and do not
   synchronize across devices.
3. The root `MaterialApp` owns `theme`, `darkTheme`, `themeMode`, `locale`,
   supported locales and the YO Voice plus Material/Widgets/Cupertino
   delegates. A persisted selection therefore changes framework controls and
   every migrated surface from one source rather than screen-local flags.
4. Polish is explicitly labelled **Beta** and remains bounded to migrated
   navigation, authentication, Settings and framework controls. Light
   graduated to the Pearl semantic theme on 2026-08-29 under ADR-127; this
   preference contract remains unchanged.
5. Missing, malformed or unreadable state falls back to Dark and English so an
   existing installation never opts itself into an incomplete Beta because of
   the device's system settings. Startup logs a preferences-store failure and
   continues to authentication. A failed save rolls the optimistic selection
   back and gives the user a retryable error.

### Reasoning

Putting visual/language preferences in Firestore would add a network and
privacy dependency to application startup for state that needs no server
authority. Persisting the exact enums locally makes switching immediate and
works offline. The Beta boundary lets the useful infrastructure ship without
violating the project's rule against presenting unfinished coverage as
complete.

### Consequences

- A user selects Appearance and language separately on each browser/device.
- The preference read adds a small local startup operation but cannot block
  sign-in when it fails.
- Polish remains migration work and keeps its Beta label until linguistic and
  accessibility verification covers the full product. Pearl's rendered and
  accessibility contract is recorded separately in ADR-127.
- `flutter_localizations` and `shared_preferences` are maintained dependencies;
  the latter must remain limited to non-secret presentation state.

## ADR-073: Firebase session management exposes account-wide revocation, never a fabricated device list

**Status:** Accepted; callable and web/PWA client deployed on 2026-08-18
(`8fa0192`). Native store release pending.

### Context

Settings showed only a static current-device row. Firebase Auth can return the
current user's token/provider data and the Admin SDK can revoke every refresh
token for one uid. It does not enumerate each web/mobile refresh token and
does not revoke one token by device. FCM token documents identify push
destinations, not authenticated sessions. Treating those documents as a device
login list would create a security control that appears precise and is not.

### Decision

1. Devices & sessions displays only data Firebase can prove for the current
   token: local platform label, primary providers and `auth_time`.
2. `revokeMyRefreshTokens` accepts no client fields and derives its only target
   from the authenticated caller. It requires `auth_time` within ten minutes
   and calls Admin Auth `revokeRefreshTokens(caller.uid)`.
3. Suspended, banned or disabled-looking profile state does not block this
   owner recovery action. Authentication and recent-auth remain mandatory.
4. After the server confirms revocation, the client unregisters its current
   FCM token and signs out locally. Admin SDK detail is redacted from failures.
5. The UI does not promise immediate eviction: a stateless Firebase ID token
   already issued before revocation can remain valid until its normal expiry,
   at most about one hour.
6. No Firestore device/session registry is added. Per-device revoke remains
   unsupported rather than being simulated with push-token deletion.
7. App Check enforcement follows the project's existing monitored rollout and
   remains off for this callable. Authenticated uid binding, empty input,
   recent-auth and Admin SDK targeting are mandatory independently.

### Reasoning

Account-wide refresh-token revocation is the strongest truthful primitive the
current authentication authority supplies and is useful after loss or suspected
compromise. A cosmetic registry would not affect a token already accepted by
Firestore, Storage or a callable. True single-device revocation would require
a server-issued session identifier and enforcement of that identifier at every
authorization boundary, which is a different architecture rather than a UI
extension.

### Consequences

- Users gain a real "sign out everywhere" recovery action, including from a
  restricted account, after recent authentication.
- Individual device enumeration and revoke are intentionally absent.
- Functions must be deployed before the compatible client. This ordering was
  satisfied for the 2026-08-18 web/PWA release.
- Revocation is account-wide and disruptive by design: the initiating device
  also signs out, and every device must authenticate again after existing ID
  tokens expire.

## ADR-074: Offline Voice Moments are bounded, account-isolated device storage, not a server database

**Status:** Accepted; deployed to web/PWA on 2026-08-18 (`8fa0192`). Native
store release pending.

### Context

Settings advertised Downloaded audio without a storage contract. Voice Moments
already use public HTTPS audio for published posts, but making offline copies a
Firestore/Storage feature would duplicate public media, add sync and cleanup
cost, and still not guarantee that bytes exist on the listening device. An
unbounded byte cache would also risk application storage growth and memory
spikes, especially on web.

### Decision

1. Only a published, non-deleted Voice Moment with a valid HTTPS audio URL,
   canonical author metadata and duration from 1 through 60 seconds can be
   downloaded. A file must be at least 1 KB and at most 12 MB. Total offline
   audio is capped at 250 MB per account on each device.
2. Account directory/cache names use a SHA-256 key of the UTF-8 Firebase uid;
   audio object names use a SHA-256 key of the validated Moment id. A different
   signed-in account cannot list, play or delete the previous account's local
   objects through the service.
3. Native platforms store the manifest and audio under the application-support
   directory using temporary-file replacement. Playback gives `audioplayers`
   the device path directly instead of reading the full file into Dart memory.
4. Web stores the same account-scoped manifest and audio in Cache Storage. It
   reads bytes only for the selected playback. Browser eviction or cleared
   site data is expected; list reconciliation hides a manifest row whose audio
   object no longer exists.
5. Downloads use a 25-second connection/response-header timeout, stream into a
   byte accumulator and abort beyond the item cap. Mutating operations are
   serialized so concurrent download/delete/clear actions cannot race manifest
   writes.
6. The manager shows the real local count and bytes and supports offline play,
   one-item removal and Remove all. The Moments card supplies the download
   action. There is no Firestore collection, server-side database, cross-device
   sync or fabricated usage counter.

### Reasoning

Offline playback is fundamentally a device capability. Local persistence keeps
it usable without network access and avoids turning a cache into canonical
backend state. Exact file and total limits bound disk use, the streamed item
limit bounds download memory, serialized writes protect the manifest, and
direct-path native playback avoids a second in-memory copy during listening.

### Consequences

- Downloads consume no Firestore documents or duplicate Firebase Storage
  objects and do not appear on another device.
- A browser, OS cleanup or app uninstall can remove local copies. The product
  reports that state rather than promising permanent storage.
- Server unpublish/delete cannot recall a public file already copied to a
  user's device; the user removes it locally. This is the ordinary consequence
  of offering downloads and must not be described as remote revocation.
- Cache Storage playback materializes only the selected web item, still bounded
  by 12 MB; native playback stays path-based.
- Raising either quota requires a performance/storage review rather than only a
  copy change.

## ADR-075: Owning one room and deleting any room are separate authorities on every form factor

**Status:** Accepted and deployed on 2026-08-18 (`e524497`).

### Context

Desktop Home loaded the server-derived staff capability matrix, but mobile Home
did not. As a result, an administrator or super moderator had no way to reach
the audited permanent-delete workflow from a phone. A normal owner had a
different usability gap: self-deletion existed in Room settings but was not a
clear room-card action, and it appeared only when that room reached the narrow
`Your active rooms` presentation. Reusing one destructive control for both
cases would blur a material authorization boundary.

### Decision

1. A host manages and deletes only their own room through an owner overflow
   menu rendered when `room.hostId` exactly matches the signed-in uid. Deletion
   still calls `deleteRoomSelf`; the server re-reads the room and enforces the
   same exact ownership before any deletion or cleanup.
2. Permanent deletion of an arbitrary room remains a separate staff shield and
   calls `adminDeleteRoom`. Its server role allowlist is exactly
   `superModerator` and `superAdmin`; ordinary `moderator` is denied.
3. Mobile and desktop both load `getMyStaffCapabilities` and render the same
   `permanentDeleteSpaces` result. UI capability checks are presentation only;
   the callable repeats claim, server-role, account-status and room checks.
4. Owner deletion requires typing the room name. Staff deletion preserves its
   existing reason, typed-name confirmation, cleanup and audit contract.

### Reasoning

Ownership is object-scoped authority, while senior moderation is platform-wide
authority. Keeping two callables and two visually distinct affordances makes
that distinction inspectable and prevents a regular moderator capability from
quietly becoming a data-erasure permission. Loading the same capability source
on both layouts fixes parity without copying role-string comparisons into
Flutter.

### Consequences

- A regular user can delete a room only when they are its canonical owner.
- `superModerator` and `superAdmin` can delete any room from phone or desktop;
  regular moderators cannot.
- A forged or stale UI cannot widen either authority because both callables
  fail closed server-side.
- Functions must be deployed before the client so the new senior-role matrix
  is authoritative when the mobile control becomes visible.

## ADR-076: Product sounds are original, bounded and reserved for meaningful events

**Status:** Accepted on 2026-08-18.

### Context

Voice interactions had no consistent confirmation beyond visuals, while push
notifications used generic platform sounds. Copying a recognisable competitor
sound would create an identity and licensing problem; adding a sound to every
tap would create fatigue and unnecessary audio work.

### Decision

1. YO Voice owns eight oscillator-synthesized WAV cues: room created, local
   joined/left, participant joined/left, microphone muted/unmuted and
   notification. No sampled or copied competitor audio is included.
2. In-app playback uses at most one lazy `audioplayers` instance for each of
   three channels: room, controls and notifications. It catches every playback
   failure so a browser autoplay policy or unavailable audio device can never
   fail the underlying product action.
3. Repeated events are coalesced with per-sound and per-channel cooldowns.
   There is deliberately no generic navigation or button-click sound.
4. Sound effects default on and are controlled by a device-local preference.
   Disabling them allocates no player and suppresses room, microphone and
   focused-web notification cues.
5. Native background notifications package the same notification motif.
   Android moves to the versioned `yovoice_activity_v2` channel because an
   existing installed channel's sound cannot be changed; APNs references the
   packaged WAV by exact name.

**Amendment, 2026-08-27 (ADR-116; Hosting deployed, native/FCM held).** The
eight semantic events remain, but their oscillator/jingle language does not:
one 48 kHz stereo material pack replaces it, native and in-app notification
bytes are identical, Android moves to v3, and foreground FCM/Firestore
presentation claims one audible owner.

### Consequences

- The original deployed assets were mono and under 300 KB. The source v3 pack
  is stereo PCM16 and about 300 KB in total; each cue remains shorter than one
  second and adds no database, network request or background loop.
- A burst of participant changes produces a restrained cue rather than one
  overlapping sound per event.
- Platform notification settings remain authoritative for background push
  sound; the in-app preference controls cues rendered by the focused app.

## ADR-077: Firestore-backed Storage Rules require an explicit production IAM gate

**Status:** Accepted and restored in production on 2026-08-18.

### Context

Storage authorization reads canonical Firestore documents for active-account,
ownership and upload-reservation authority. The Storage emulator evaluates
those calls internally, so the complete emulator suite passed while production
returned `storage/unauthorized` before creating any object. The deployed rules
source was correct and byte-identical to the repository; the missing state was
the separate IAM bridge that lets the Firebase Storage rules service read the
default Firestore database.

### Decision

1. The Google-managed Firebase Storage service agent receives exactly
   `roles/firebaserules.firestoreServiceAgent`, not a general Firestore role.
2. Every Storage-rules rollout verifies that exact project binding before the
   deploy and performs one authenticated production upload through a rule
   branch that calls `firestore.get()` or `firestore.exists()` afterward.
3. Emulator tests remain the semantic gate, but are never cited as evidence
   that production IAM is configured.
4. A missing binding is repaired as infrastructure; Storage rules must not be
   loosened to hide the failure.

### Reasoning

The predefined service-agent role contains only `datastore.entities.get`, the
least privilege needed for cross-service Security Rules. Binding it to the
Storage service agent follows Firebase's documented setup and preserves the
existing fail-closed authorization model. A production smoke test covers the
one dependency that a local emulator cannot represent.

### Consequences

- Voice Moment, profile/room/Club artwork and private message uploads can use
  their existing Firestore-backed authority checks in production.
- IAM policy becomes a named deployment prerequisite alongside rules source,
  Functions and indexes.
- Removing the role intentionally disables every affected upload path until it
  is restored; this is preferable to silently widening access.

## ADR-078: An onCall handler takes exactly one parameter; dependency injection never rides the handler signature

**Status:** accepted, deployed (2026-08-18).

**Context.** firebase-functions v2 invokes every callable handler as
`handler(request, responseProxy)` — the second argument is the streaming
`CallableResponse`, passed unconditionally
(`lib/common/providers/https.js`). Seven room callables in
`rooms/participants.js` registered their multi-parameter `execute*`
functions directly (`onCall(OPTS, executeDeleteRoom)`), so in production the
response proxy landed in the `roomControl` dependency-injection slot and
`roomControl ?? getProductionLiveKitControl()` selected the proxy. Every
LiveKit method call on it threw `TypeError: ….endRoom is not a function`
AFTER the Firestore transaction had committed: `deleteRoomSelf` stranded
rooms as `status:"closed" / deletionInProgress:true` zombies (the "beyb"
room), `leaveRoomSelf` errored after deleting the roster row (users pressed
Leave and stayed in the room UI), `setOwnRoomParticipantMute` wrote the
roster then failed ("Could not change microphone state"), and ended rooms
produced "This room is not currently live" on rejoin. All seven had been
broken since the 2026-08-16 18:24 deploy. The tests never saw it because
every suite called `executeX(request, fakeControl)` directly — the framework
calling convention itself was uncovered.

**Decision.** Callable registrations pass one-argument wrappers only:
`onCall(OPTS, (request) => executeX(request))`. The injectable signature
stays for tests. Two permanent guards in
`functions/test/callable_invocation_contract.test.js`: invoking the
REGISTERED callables via `.run(request, proxy)` must never treat the second
argument as a dependency, and a structural scan fails if any `onCall`
anywhere registers a multi-parameter named handler.

**Consequences.** Fixed and deployed 2026-08-18 ~20:36 UTC. Zombie rooms
remain deletable: `"closed"` is in `ROOM_STATUSES` and `deletionInProgress`
does not block `executeDeleteRoom`, so a host retry completes the deletion.

## ADR-079: Owner-scoped social lists split get from list; wildcard liveness reads never run inside list evaluation

**Status:** accepted, deployed (2026-08-18).

**Context.** `users/{u}/friendRequests/{senderId}`, `sentFriendRequests` and
`friends` each had a single `allow read` calling
`accountIsActive(<wildcard>)`. A list query evaluates that per candidate
row; one denied row — or the query access-call budget — fails the whole
list. In production the Notifications screen lost every accept/decline
control ("Friend requests and unread messages could not be loaded"), and
the Friends counter read 0 while search said "Friends". The prior
regression test claimed to cover "the incoming request list" but executed a
single `getDoc`.

**Decision.** `get` keeps the cross-party liveness checks; `list` is
`isActiveAccount() && isOwner(userId)` — already path-scoped to the owner's
own subcollection, where a per-sender liveness read adds nothing. New rules
tests execute the real LIST queries; the pre-fix rules fail exactly the
three owner-list regressions (400/3) and pass all denial cases, proving the
change loosens nothing.

**Consequences.** Owner lists work under the deployed ruleset
(2026-08-18T20:38Z, byte-identical to HEAD). Any rule whose read condition
dereferences a document-ID wildcard must either split get/list or prove a
list query is impossible.

## ADR-080: Unconfigured billing endpoints stay out of the deploy manifest behind an explicit operator flag

**Status:** accepted (2026-08-18).

**Context.** The Functions CLI validates every secret declared by any
discovered endpoint at deploy time — even endpoints excluded from `--only`.
The five ADR-067 Stripe endpoints declare `STRIPE_SECRET_KEY`, which
deliberately does not exist yet, so their mere presence in `index.js`
blocked deploying the entire codebase non-interactively.

**Decision.** `functions/index.js` requires and exports the Stripe module
only when `STRIPE_BILLING_EXPORTS=enabled` is set (functions/.env) — 125
exports with the flag off, 130 with it on. The flag is flipped only as part
of the real ADR-067 go-live, after live Stripe configuration exists.

**Consequences.** The codebase deploys without fake secrets and without
half-configured billing endpoints appearing in production. The go-live
checklist gains one explicit step.

**Amended 2026-08-28.** ADR-118 supersedes ADR-067's catalog, but not this
gate. `getPremiumBillingContext` is now a separate secret-free export; with the
flag disabled it renders truthful EUR and PLN offers while reporting checkout
unavailable. Enabling the flag still adds exactly Checkout, Portal, webhook and
Auth-deletion Stripe handlers, and now belongs to ADR-118's live-only rollout.

## ADR-081: Ledger fingerprint mismatches are terminal, and canonical content is a pure function of the event's identity

**Status:** accepted, deployed (2026-08-19), production data repaired.

**Context.** The achievement dedup ledger keys entries by
`sha256(sourceType|sourceKey|metric)` and stores a fingerprint of the full
canonical content, occurredAt included. `activeDay` events collapse a whole
UTC day into one identity but fingerprinted the triggering event's exact
time, so the second qualifying action of any user-day derived the same
eventId with a different fingerprint. `engine.js` threw
`AchievementEventIntegrityError` — permanently, since redelivery re-derives
the same mismatch — and `retry: true` turned that into infinite Eventarc
redelivery. Three loops ran from 2026-08-18 17:34Z (ledger ids
`v1_29153e…`, `v1_96d81c…`, `v1_3c2af0…`, the last unreported), burning
invocations every 1–3 minutes; the primary events had already committed, so
nothing was pending except the poison. The same latent class covered every
identity that deliberately collapses recurrences: community re-joins and
re-added reactions would have collided the same way. Separately,
`reconcileAchievementsV1` had been wedged on the collection's first user
since 2026-08-16 18:40Z: a presence-only legacy profile made the bootstrap
write `undefined` (rejected by Firestore), `failUser` merge-created a
partial record, and `beginUser` treated it as unrecoverable corruption on
every run while the cursor never advanced.

**Decision.** Three rules. (1) A fingerprint mismatch on an existing ledger
entry is *terminal*, never a retry: if the derived event re-fingerprinted
at the stored entry's own observation time matches the stored fingerprint —
the recurrence-of-a-collapsing-identity case — it resolves as a quiet
`replayed`; anything else returns a `collision` outcome with a forensic
error log. Neither branch applies the event or touches the stored entry;
dedup always keeps the first write. (2) Every field of an event's canonical
content must be a pure function of its identity: `activeDay` now stamps the
UTC day start, not the triggering event's time. (3) The migration treats
per-user state failures as per-user outcomes: `failUser` always writes a
self-describing record with an attempt counter, `beginUser` re-initializes
pre-bootstrap failure records (terminal after `MAX_BOOTSTRAP_ATTEMPTS`),
marks contradictory records failed and lets the run advance — and adopts
already-existing live progress instead of overwriting it. The four pre-fix
`activeDay` entries and the poisoned migration record were rewritten in
production by `functions/scripts/repair_achievement_canonical_ledger.js`
(dry-run default, identity re-derived through the engine's own modules,
apply refuses on any anomaly, idempotent; rehearsed against the emulator
including the refusal gate).

**Reasoning.** Fail-closed is right for *transient* uncertainty but wrong
for *permanent* divergence: at-least-once delivery makes an unresolvable
throw an infinite loop, which is a worse integrity posture than a logged,
inert outcome — the ledger still wins, nothing is double-counted, and the
forensic record survives in Cloud Logging instead of a retry storm. The
quiet-replay tier exists because collapsing identities *by design* receive
recurrences whose only honest difference is observation time; logging those
as errors would page on routine re-joins and re-likes. Comparing at the
stored time is sound: equal eventIds already pin sourceType, sourceKey and
metric, so the substituted fingerprint proves every other content field
equal.

**Consequences.** All 12 achievement functions redeployed 2026-08-19
~05:30Z; the three loops went silent and the reconciler advanced past its
wedge on the next scheduled run. Regression tests (10 of them failing
against the pre-fix code) pin the terminal outcomes, the day-start
canonicalization, the quiet-replay tier and every migration recovery path.
Any future source adapter whose identity collapses recurrences must derive
*all* canonical content from the identity alone — the sources test now
asserts fingerprint equality, not just id equality, for same-day activeDay
events.

## ADR-082: A feature is not shipped until a user can reach it — reachability is part of done, and a green suite cannot prove it

**Status**: Accepted (2026-08-19 → 2026-08-20). The four instances below are
fixed in source; none is verified in production.

**Context.** Within one wave, four separate features were found to exist in
source, pass their tests, and — where a backend was involved — be deployed
and active, while being unusable by any user:

1. **Voice never worked in any Community room or lounge** (`b0f1062`).
   `createLiveKitToken` refuses a token unless the room says status active
   and `isLive` true; performing that transition is the *caller's* job, and
   only `enterClubLounge` ever did it — reachable in practice from the Club
   overview alone, because `HomeScreen` is not mounted anywhere in the
   running app (`main_shell` holds it at `_screens[0]`, but `_slotChildren`
   special-cases index 0 to `MobileHome`/`DesktopHome` and never reads it).
   `RoomService.startCommunityVoice` had **zero callers**. Nine call sites
   push `RoomEntryScreen`, whose own comment says callers joined beforehand,
   and the room screen then asks for a token immediately. Production agreed:
   **45 rooms, 3 live**.
2. **Club chat moderation had never worked** (`b3c27fd`). The client
   authorised moderator, admin and owner; the rule was author-only; and the
   UI never offered the action at all, wiring `onLongPress` solely to the
   viewer's own messages. Three layers, three different beliefs.
3. **No message anywhere in the product could be reported** (`9f3ce7f`).
   `createContentReport` was deployed and ACTIVE and already accepted
   `directMessage`, `voiceMoment` and `voiceMomentComment`. No Dart file
   called it. The only report action in the product was on a profile, with
   `reason` hardcoded to `harassment`.
4. **Home's "Discover clubs" rail was denied for everyone** (`01c0ab2`,
   `155ad61`), including a club owner listing their own club, because
   `clubs` carried `allow list: if false` — and the denial was swallowed by
   `snapshot.data ?? []` with no `hasError`, so a permission error rendered
   as an empty rail whose heading vanished with it. It also lives in the
   unmounted `HomeScreen`, so it was broken twice over, independently.

**Decision.** Reachability is part of the definition of done, and is stated
explicitly rather than assumed. Before a feature is called complete:

- **Name the entry point in the *mounted* composition.** A file that exists
  is not a screen a user can open. `HomeScreen` is the standing
  counterexample in this repo — grep for the widget in the composition the
  shell actually builds, not for the class.
- **Name the caller of every required state transition.** If a server
  precondition exists (`isLive`, a composite index, a verified email, a role
  claim), the code that satisfies it is identified by name, or the feature is
  not wired.
- **Assert on the payload the client actually sends.** A rules test written
  from the rule's own text proves the rule is self-consistent, not that the
  shipped client can satisfy it.
- **Where none of that can be proved, label it UNVERIFIED** rather than
  letting a green suite imply it.

**Reasoning.** Four in one wave is a mechanism, not a run of bad luck, and
the mechanism is that every verification layer this project owns validates a
layer against a *model* of its neighbour rather than against the seam:

- The **emulator does not enforce composite indexes**, so a query that
  cannot run in production runs green locally (ADR-055's
  `expirePremiumIdentity` was the first instance; the moment-cleanup
  schedules were the second).
- **Rules tests exercise fixtures the test author wrote**, not what the
  client sends — which is why an author-only club-chat rule and a
  moderator-authorising client both passed their own suites.
- **`fake_cloud_firestore` does not evaluate rules at all**, so every Dart
  test asserting "the client may do X" proves the client's mirror of the
  rule, never the server's answer.

Each layer is honest about itself and silent about the join. Nothing in the
existing gates closes that, so the gate has to be a named step.

**Consequences.** Slower completion claims, and several items in this wave
are recorded as *fixed in source, unproven in production* rather than fixed —
which is the point. It also makes the unmounted-`HomeScreen` question a
blocking product decision rather than a curiosity: three widgets
(`DiscoverClubsRail`, `FromYourClubs`, `LiveNowHero`) are finished, tested
and unreachable, and placing them is a Home information-architecture call
nobody has taken. Recorded in [Bugs.md](Bugs.md) and
[Roadmap.md](Roadmap.md) as open, not as fixed. The corresponding limitation
is stated in [TESTING.md](TESTING.md) so the next reader meets it before
trusting a suite count.

## ADR-083: A Firestore `list` rule is evaluated against the query's constraints, so every clause is a bare field access and the client's query carries the equality

**Status**: Accepted in source (`01c0ab2` rules, `155ad61` client);
**UNVERIFIED in production** — the ruleset has not been deployed from this
work, and the rail that consumes it is not reachable (ADR-082).

**Context.** `clubs` had `allow list: if false`, and its comment claimed no
legitimate listing remained. That was wrong — Home's club-discovery rail is
a legitimate caller that had simply been missed. Writing the replacement
rule surfaced a property of the rules evaluator worth pinning down: a `list`
rule is proved **against the query's constraints, never against the
documents it would return**. A clause written with a default —
`get('type', 'community') == 'community'` — was *measured* to **ADMIT a
family club**, because with no matching filter in the query the clause
satisfies itself and the rule permits a listing it was written to exclude.

**Decision.** Every clause of a `list` rule is a **bare field access**
(`resource.data.type == 'community'`, no default), which forces the caller's
query to carry the matching equality or be denied. The client query is
written to send exactly those equalities, and its comment records that the
filters **are the authorization**, not defensive narrowing:
`watchSuggestedClubs` sends all three. Only the exact three-equality query
passes; bare listing, privacy alone, privacy+type, private, inviteOnly and a
banned account are all denied.

**Reasoning.** A default makes an absent filter *succeed*, which inverts the
rule's intent precisely in the case it exists to catch. A bare access makes
an absent filter an error, and an erroring clause denies. Reverting the
client query to the old privacy-only shape fails 4 of the 6 service tests —
a family room, a suspended club and a club with no status all leak through
it — which is the property being defended, expressed as a test rather than a
comment.

**Consequences.** The rule and the client query are now a **matched pair**:
changing either one alone breaks discovery, and the client's filters can
never be "optimised away" as redundant. Any future list surface over `clubs`
must send the same three equalities or get a new, separately-tested rule
branch. A production probe confirmed the three-equality query needs no
composite index — it is served by a zigzag merge join — so this shape costs
nothing to index. The same discipline applies to the failure channel:
`hasError` is checked **before** any read of `snapshot.data`, because
`StreamBuilder` retains data alongside an error, and a Firestore
subscription is terminated by its first error, so a retry affordance must
re-subscribe rather than rebuild.

## ADR-084: Client-authored writes carry an exact key allowlist, and identity and time are pinned to canonical server values or the remaining gap is stated

**Status**: Accepted in source (`b3c27fd`, `01c0ab2`); **UNVERIFIED in
production** — rules not deployed from this work.

**Context.** Room chat was the largest unguarded client write surface in the
product. The rule checked `senderId` and membership and nothing else about
the document, so an ordinary member could write another member's
`senderName` and photo, a 60,000-character body, arbitrary extra fields, and
a `sentAt` in 2099 that pinned the message to the top of every member's list
permanently. Every other client-authored identity snapshot in
`firestore.rules` was already pinned; room chat was the exception, and the
client compensating is why it never surfaced. Club chat had the mirror-image
hole: no field allowlist on create, so a plain member could write a message
that was **already a forged tombstone** — reading as "removed by the club
owner", carrying `deletedByRole: superAdmin` and a `senderName` of
"YO Voice Support", with `sentAt` in 2099. And it was unrepairable: the new
update rule refuses already-deleted documents, `delete` is `false`, and
`adminDeleteMessage` short-circuits on `isDeleted`, so only a raw Admin SDK
script could clear it.

**Decision.** Every client-authored document write states its **exact key
set** (`keys().hasOnly([...])`), and each identity or ordering field is
either pinned to a server-canonical value or explicitly documented as
unpinned with the reason:

- Room messages: **six keys**, `senderName` pinned to the canonical `users`
  document, `createdAt` pinned to `request.time`, content capped at 500.
- `senderPhotoUrl` is **deliberately not pinned** — the client falls back to
  the Firebase Auth mirror when the profile field is empty, so a pin would
  refuse a legitimate send. It gets the bounds the server already applies,
  and the residual gap is stated rather than hidden: **an avatar can still
  point at another member's image**. Closing it needs the client to drop that
  fallback first.
- Reactions updates are bounded at **32 keys**, with the comment saying
  plainly what that does not cover: the uid list under each key is still
  caller-authored and unbounded, and rules cannot iterate map values. The
  real fix is a `reactions/{uid}` subcollection, which is a schema change.
- Club messages get `clubMessageCreateShapeAllowed`, which is what makes the
  moderation rule of [ADR-085](#adr-085-authorization-branches-in-a-rule-are-disjoint-by-construction-because-cels--absorbs-errors)
  safe to ship — a forged tombstone would otherwise be permanent.

**Reasoning.** Two measurements made the allowlist non-negotiable rather
than tidy.

**(1) Extra-field freedom silently dropped achievement credit.** The six-key
allowlist is not invented: `functions/achievements/sources.js` already treats
exactly that key set as canonical, and any extra field made the adapter
return `null`, so the event was skipped and the sender lost the credit. Rules
and adapter now agree — the *same* keyset described in two places was already
a latent divergence, and the write surface is where it gets enforced.

**(2) Rules `String.size()` counts UTF-16 code units**, the same unit as
Dart's `String.length`. Measured, not assumed: it means a 500-character cap
in the rule is the same 500 the app's own field counts, so emoji-heavy
messages are not rejected for being "too long" by a rule counting a
different unit than the composer the user is looking at.

**Consequences.** Two pins were deliberately **not** added, because each
would break sending today and each needs a paired client change first:
`senderName` cannot be pinned to the canonical profile on the *club* side
while the client reads it from a club member row that nothing re-syncs on
rename, and `sentAt` cannot be pinned to `request.time` while the client
writes `Timestamp.now()`. Neither can now produce unrepairable state — a
message with a forged name or a 2099 timestamp is removable. Any new field
on a room or club message now requires a rules change *and* an
`achievements/sources.js` change in the same commit, or the sender silently
loses achievement credit again.

## ADR-085: Authorization branches in a rule are disjoint by construction, because CEL's `||` absorbs errors

**Status**: Accepted in source (`b3c27fd`); **UNVERIFIED in production** —
rules not deployed from this work.

**Context.** A club owner could not remove an abusive message from their own
club. Making that work meant a rule with two authorities in it: the author
retracting their own message, and a moderator removing someone else's. The
obvious shape is two overlapping branches joined by `||`. An adversarial
review measured why that shape is unsafe: **CEL absorbs errors through
`||`** — `<error> || true` **ALLOWS** — so a branch that errors (a missing
document, a failed `get`, a type mismatch) silently hands its decision to the
other branch, which may be permitting for reasons that have nothing to do
with the erroring case.

**Decision.** The two branches are made **disjoint before any document
read**: one tests `senderId == request.auth.uid`, the other tests
`senderId != request.auth.uid`. Exactly one branch is applicable to any
document, so absorption cannot produce an unintended permit whatever guards
each side carries. Editing is not expressible by *anyone*: both branches pin
`content` to the empty string, making removal and editing separate
authorities structurally rather than by convention. Attribution is checked
against the **post-write document**, never the diff — which is what catches a
`deletedBy` planted at create and left unchanged (the `hasAny` hole
[SECURITY.md](SECURITY.md) principle 6 describes).

**Reasoning.** Disjointness converts a whole class of reasoning ("could this
guard ever error, and what would the other branch then say?") into a property
you can read off the first line of each branch. The cheap alternative —
auditing every `get()` in every guard for error-freedom — has to be redone
every time either branch grows a clause.

**Consequences.** The moderator branch had to restate the sanctions the
author branch already carried: an early version restated only account status,
so a communication-muted moderator and an unverified-email moderator kept
full reach over every non-owner message in every club where they held a role,
bypassing the sanction's whole lifecycle. Both are now required on that
branch. Disjoint branches mean shared conditions cannot be factored out to
one place — that duplication is the cost, and it is worth it. Accepted gaps
are named in the rule's own comment rather than left for a reader to
discover: **removals are recorded nowhere** (the only trigger on that
collection is `onAchievementClubMessageCreated`, an `onDocumentCreated`, so a
moderator removal leaves no `adminAuditLogs` entry — the client writes
`deletedBy`/`deletedAt` from day one so an audit trigger has what it needs
when one exists), **no rate limit**, **no restore path**, and **no rank
ordering**, so a moderator can clear an admin's or a co-owner's messages.

## ADR-086: A safety action is never gated on email verification, and every moderation endpoint checks access before existence

**Status**: Accepted in source (`2c086c7`); **UNVERIFIED in production** —
`createContentReport` has not been redeployed from this work.

**Context.** `createContentReport` required a verified email, so someone
being harassed on their first day could not report it. `requireActor`
defaults to `{verified: true}`, and the inner call at
`functions/moments/integrity.js` overrode an outer binding that already
passed `{verified: false}`. `firestore.rules` states the opposite policy **in
writing** on the client-direct `reports` create path: reporting is a SAFETY
action and sits with blocking, which the same policy explicitly leaves
available to a freshly-registered account. Separately, the callable answered
`not-found` *before* checking access, which made the endpoint an **existence
oracle**: a caller could learn whether a private room, club, channel or
message id was real by watching which refusal came back.

**Decision.** Two rules, both stated at the call site.

1. **Safety actions run for any active account**, verified or not. The
   relaxation carries a comment naming the rule it follows, the blocking
   precedent and the rate budget that bounds it, ending "Do not restore the
   default here." Volume is bounded by the deterministic id, the 30 s
   cooldown and the 20-per-window cap, not by verification.
2. **Access is checked before existence, for every target type.** A caller
   who cannot read the container gets `permission-denied` and nothing else.

**Reasoning.** Email verification gates *outbound, spam-prone publishing*;
reporting is inbound and self-protective, and the account most likely to need
it is exactly the new one. A neighbour audit of **every** `requireActor` call
site found this was the ONLY tightened safety path — `setUserBlock`,
`unfollow`, conversation mute/archive, mark-read and both delete paths were
already correct, and every remaining `verified: true` site is genuinely
outbound — so this was a local defect against a written policy, not a policy
disagreement. On ordering: refusing with the most-specific error is good
product copy and a bad security boundary; the endpoint's job is to accept a
report, and it can do that without ever confirming an id exists to someone
who cannot see the container.

**Consequences.** One live behaviour changes: a non-participant reporting a
DM could previously distinguish a missing message from a real one, and now
cannot. Room and club messages became reportable in the same change, using
the target names `roomMessage` and `clubMessage` because `admin/messages.js`
already uses exactly those for the callable a moderator uses to *remove* the
message — same vocabulary, same ids, so a report and the action taken on it
describe the same thing. Membership mirrors the rule governing each
container's reads, including the Club-lounge case and a participants row
whose `admittedBy` equals the CURRENT host, which is what refuses a
self-forged row. Still open and named rather than implied fixed: moderators
can **triage** room and club message reports but cannot **action** them
(`removeAndResolve` is still globalChat-only), and `reason` has no
server-side enum on the callable path — only the client-direct v1 rule
constrains it — so the Moderation Center's equality filter cannot see a
report whose reason is off-list.

## ADR-087: An idempotency key derived from a request payload is a compatibility surface — new fields fold in only when the target carries them

**Status**: Accepted in source (`2c086c7`); **UNVERIFIED in production**.

**Context.** `createContentReport` deduplicates through the server's
operation ledger, whose `inputHash` was computed over a fixed five-key
target. The client derives its `requestId` from the target too, so the pair
is what makes a re-tap on an already-reported message replay quietly instead
of erroring. Adding an optional bounded `note` and the new room/club target
fields to that hash unconditionally would have **re-keyed every report
already filed in production**: the next re-tap on an existing report would
have stopped replaying and started answering `already-exists`.

**Decision.** New fields are folded into the hash **only when the target
actually carries them**, so a legacy target hashes exactly as it did before.
A regression test recomputes the legacy hash and pins it.

**Reasoning.** An idempotency hash is a wire format, not an implementation
detail: it is the shared secret between a client's `requestId` derivation and
the server's ledger, and it is *retroactive* — changing it silently
reclassifies every historical entry. Conditional folding keeps old and new
payloads on their own hashes with no migration and no dual-read window.

**Consequences.** The hash function now has a shape that must be preserved:
any future field is additive-when-present, and the legacy-hash regression
test is the thing that says so. One cost is inherited from the previous
deterministic-id path and restated plainly rather than discovered later: a
report **cannot be re-filed after a moderator dismisses it**, because the key
is the target and not the attempt.

## ADR-088: Entering a room performs the liveness transition, through one ordered coordinator that mirrors the deployed rule

**Status**: Accepted in source (`b0f1062`); **UNVERIFIED in production** —
no production or emulator round trip, no real LiveKit, no device run.

**Context.** Opening a Family Room you created yourself and pressing unmute
returned "This room is not currently live." It was not a Family Room bug:
voice had never worked in any Community room or lounge, for the reason
recorded in [ADR-082](#adr-082-a-feature-is-not-shipped-until-a-user-can-reach-it--reachability-is-part-of-done-and-a-green-suite-cannot-prove-it) —
`createLiveKitToken` requires `isLive`, the transition is the caller's job,
and no reachable caller performed it. Production: **45 rooms, 3 live**.

**Decision.** **Entering a room performs the liveness transition** for anyone
the deployed rules would accept, rather than adding a second tap. One
coordinator (`RoomVoiceEntryCoordinator`) runs the ordered path **liveness →
roster → token**. `RoomVoiceStartAuthority` mirrors the deployed rule branch
for branch, and `startRoomVoice` sends exactly the three keys the rule
permits, as a standalone update so nothing can ride along in the same commit.
`room_mic_affordance` makes "a mute control in a dormant room"
unrepresentable rather than merely unlikely.

**Reasoning.** The product already promises liveness on entry: the room board
labels a dormant room's button "Start", and the screen has no lobby —
it renders a stage, a live status line and a microphone the moment it opens.
**A second gate on a screen that already looks live *is* the mismatch**, so
the fix is to make the screen's promise true rather than to add UI
explaining why it is false. Exposure stays host-opt-in:
`membersCanStartVoice` defaults false, so only the host starts an ordinary
room, and lounges are private and already auto-started.

**Consequences.** **Legacy documents are tolerated deliberately**, because
most production rooms are legacy — 25 of 45 carry no `membersCanStartVoice`
and 24 have neither `roomType` nor `experience` — so every read defaults
rather than raising. Community and Broadcast stay separate screens, separate
control docks, separate identity; only the lifecycle is shared, which keeps
the product invariant in CLAUDE.md intact. The client authority is a
*mirror*: it must be re-checked whenever the rule branch changes, and because
`fake_cloud_firestore` does not evaluate rules, every "the client may start
voice" test proves the mirror and not the server. Known and queued rather
than hidden: a **member-started room can stay live with nobody in it**
(the server drops `isLive` at zero participants only for lounges),
`executeEndRoomVoice` re-checks nothing before tearing a room down, and an
ended room still offers Start voice to someone who never held a participant
row.

## ADR-089: Moments is a primary destination, and its discovery feed ranks client-side because Firestore can neither order by a computed sum nor randomise

**Status**: Accepted in source (`cef05e6`); **UNVERIFIED** — nothing has been
rendered at any width, and the two new composite indexes are committed, not
confirmed deployed.

**Context.** Moments was buried in the More menu while the product it belongs
to is voice-first, and the screen behind it showed only the people you
already follow.

**Decision.** Moments becomes a primary destination on both form factors —
directly above Discover in the desktop rail, and a slot in the mobile dock —
and the screen behind it shows Moments from every user. The mobile dock has
five slots and no room for a sixth, so **Moments displaced Friends there**;
Friends keeps its desktop rail entry, its More entry, its screen and its
state. Nothing was removed, and the trade is asserted in
`more_destination_nav_test` rather than left for someone to discover. The
Voice Trending card's "View all" now reaches Moments instead of Discover.

**Reasoning.** The feed ranks by engagement and then shuffles because
Firestore can do neither of the two things the brief asked for directly: it
cannot order by a computed sum, so `likeCount + commentCount` can never be an
`orderBy`, and it cannot randomise server-side. So the service pulls a
bounded popular pool, weights each Moment by a strictly increasing function
of engagement, shuffles under a **held seed** so paging stays stable, and
spaces authors apart so one prolific account cannot own the stack.

**One Firestore trap worth carrying forward**: `orderBy('likeCount')`
**SILENTLY OMITS every document missing that field**. A popularity ordering
would therefore have hidden exactly the Moments that had never been liked —
which on a pre-launch product is most of them — and the omission would have
looked like an empty feed rather than a bug. Two composite indexes cover the
real query shapes: `isPublished`+`likeCount` desc and
`isPublished`+`createdAt` desc.

**Consequences.** Ranking quality is now a client concern and cannot be tuned
without shipping a client. The held seed is what makes paging coherent, so it
must survive any future refactor of the pool fetch. Three defects the design
pass found in the screen are closed with it: `MomentsScreen` rendered a heart
and a like count with **no tap target**, so it displayed engagement it would
not let you create while the same feature worked on Home; both of its
`StreamBuilder`s used the forbidden `snapshot.data ?? []` with no `hasError`,
so a permission error, a missing index and a still-connecting stream all
rendered as the same "No Moments yet"; and the screen imported `AppColors`
and then hardcoded six off-palette colours anyway. The empty state — the
state most users on a pre-launch product will actually hit — has still never
been looked at.

## ADR-090: Session cleanup converges on `AuthService.signOut()`, because a write the rules authorize by session cannot live after the session ends

**Status**: Accepted in source (`3d54bc3`); **UNVERIFIED in production** —
presence actually flipping needs two real accounts.

**Context.** An adversarial audit traced sign-out end to end. The offline
presence write lived in the `authStateChanges()` **null branch** — i.e.
after `FirebaseAuth.signOut()` had already cleared the session — so the
rule's `isSignedIn()` gate denied it and `presence_service` swallowed the
denial to a `debugPrint`. `isOnline` stayed true,
`onUserPrivacySourceChanged` mirrored it into `socialPresence`, and that is
exactly what the DM header dot and the conversation list read: **a
signed-out account showed as online to its friends indefinitely.** The
comment above that code claimed it fixed exactly this. There were two such
writes; the second, in the account-switch branch, wrote a previous uid under
a new identity and failed `isOwner()` just as structurally. The FCM token had
the same shape of bug across **five sign-out entry points with five different
amounts of cleanup**, so two of them left the previous account receiving push
on a shared device.

**Decision.** Both cleanups converge into `AuthService.signOut()`,
immediately **before** `_firebaseAuth.signOut()` — the only place in `lib/`
where a live session becomes a dead one. Presence and token cleanup start
together while the session is still authorized, are independently bounded and
report a named consequence, then Google/Firebase sign-out continues. The push
path synchronously revokes its identity epoch and marks rotation required
before any fallible await; durable-marker persistence, owner-row deletion and
platform invalidation then settle independently. One offline or
never-completing Future therefore cannot skip the other cleanup or trap a user
in a session they asked to leave. Token-row deletion is issued eagerly and
repeated after a successfully drained pre-transition registration queue, so an
already-started registration cannot complete after the delete and resurrect
the previous account's subscription. The two denied writes are **removed
rather than relocated**: keeping a write the ruleset always rejects is the
mistake being fixed.

**Reasoning.** A write authorized by `isSignedIn()`/`isOwner()` has a
precondition the client controls the timing of, and the signed-out branch is
the one place that precondition is guaranteed false. Convergence is the
proof: Settings, Profile and the 2FA path needed no edit at all. The
load-bearing test assertion is not that the write happened but **when** —
the tests record `_auth.currentUser != null` at the moment of each write, so
a write recorded outside a live session is a write the deployed ruleset
denies. 8 of 10 fail against the pre-fix code; 10/10 pass after.

**Consequences.** Any future sign-out-adjacent cleanup belongs in that one
method, and a swallowed `debugPrint` on a permission denial is now a known
smell in this codebase rather than a stylistic choice. **Not fixed, and it
cannot be from the client: process death.** A force-quit or a server-revoked
refresh token never reaches client code, and no client can write for a
session that no longer exists. `functions/` has no presence sweeper —
`public_profiles.js` clears `isOnline` only on account deletion. Closing that
needs a scheduled function expiring `users/{uid}` on a stale
`presenceUpdatedAt`, or a staleness cutoff when reading `socialPresence`.
Flagged in the doc comment rather than approximated.

## ADR-091: The roster, not `participantCount`, decides that a room is empty — and the leave path asks the server to prove it

**Context.** Until this wave nothing in the app ever set `isLive: true` on an
ordinary room, so `executeLeaveRoom` dropping liveness only for
`roomKind == 'clubLounge'` was survivable. ADR-088 makes entering a room
perform the liveness transition, which turns that omission into a permanent
stuck state: a Community room with `membersCanStartVoice`, started by a member
who then leaves last, has no exit at all — `endRoomVoiceSelf` is host-only and
there is no scheduled sweeper — so it keeps advertising itself on
`watchLivePublicRooms` as a live room nobody is in.

The obvious repair, having the client call the host-only "end voice" callable
when its `participantCount` read reaches zero, carries a worse failure than
the one it fixes.

**Decision.** Three parts.

1. `executeLeaveRoom` ends the voice session for the last participant out of
   **any** room, and proves emptiness by re-reading the participants roster
   with `limit(2)` **inside the same transaction**, before any write (the
   Admin SDK refuses a read that follows one).
2. `executeEndRoomVoice` takes an optional `onlyIfEmpty`. When set it repeats
   that roster check and, if anyone other than the caller is present, writes
   nothing and returns `{ success: true, ended: false }` — a success, not an
   error. Omitting the flag is byte-for-byte the previous behaviour.
3. `RoomService.endCommunityVoice` gained `onlyIfEmpty`, defaulting to false.
   The leave path passes true; the host's explicit "End room" control does not.

The Club lounge branch stays counter-derived and character-for-character
unchanged, because `roomParticipantLeaveRootExists` in `firestore.rules`
mirrors that exact transition and the two must not drift.

**Reasoning.** `participantCount` is a denormalised field with several
writers. A stale-**low** value would turn one person's leave into an
`endRoom()` that disconnects everyone still talking — the client cannot
distinguish "empty" from "the counter has not caught up", and the server can.
A client-supplied `expectedParticipantCount` precondition was considered and
rejected: it makes a stale client authoritative, and it fails **loudly** on
the one control that ends a room, stranding it `isLive: true` with nobody in
it — precisely the defect part 1 exists to stop creating. Returning success on
a no-op is deliberate: a leave must never surface to the user as a failure,
and a room left live because someone is genuinely in it is correct, not an
error. The client-side close is retained rather than deleted because the app
and Cloud Functions ship separately; it is self-disabling, since its re-read
demands `isLive == true` *after* the leave and the new server build has
already cleared it. **Deploy Functions before the app and it is dead code on
arrival.**

**Consequences.** "This room is empty" is now a server-proved claim
everywhere it causes a disconnect. `leaveRoomSelf` returns an additive
`endedVoiceSession`; `endRoomVoiceSelf` returns an additive `ended`. No
Firestore field, collection or document shape moved, and no new index is
needed. The generalised branch requires the counter **and** the roster to
agree, so a stale-**high** counter leaves a room live with an empty roster —
conservative in the safe direction, and self-healing the next time anyone
enters and leaves. **One residual gap is not closed:** if the liveness write
succeeds and the following `joinRoom` fails, nobody ever holds a participant
row, `executeLeaveRoom` returns early, and a room nobody revisits keeps
advertising itself. Extending the repair to callers with no participant row
was rejected — it would let any signed-in account drop `isLive` on a live room
during the start→join window. Closing it properly needs a scheduled sweeper.
CORRECTED: the implementing agent recorded this as "the first scheduled
function in `functions/`, adding Cloud Scheduler as a new deploy dependency."
That is wrong, and the 2026-08-20 deploy is the evidence —
`expireAbandonedMomentDraftsSchedule`, `expireAbandonedDirectMessageAttachmentsSchedule`,
`processPendingContentCleanupSchedule` and
`expireAbandonedVoiceCommentDraftsSchedule` all deployed alongside it. Cloud
Scheduler is an existing dependency, so the sweeper is a materially cheaper
piece of work than that note implies.

## ADR-092: A scheduled sweep closes the room no client can close, and the roster is still the only thing that proves it empty

**Context.** [ADR-091](#adr-091-the-roster-not-participantcount-decides-that-a-room-is-empty--and-the-leave-path-asks-the-server-to-prove-it)
named one residual gap and left it open.
`RoomVoiceEntryCoordinator.enter()` writes liveness first and calls
`joinRoom` second — it has to, because `joinRoom` refuses a dormant room and
`createLiveKitToken` refuses both a dormant room and a caller with no
participant row. When that join fails the coordinator returns
`RoomVoiceEntryOutcome.failed` and does **not** call `leaveRoomSelf`: there is
nothing to leave, the roster row was never written. The room is left
`isLive: true, participantCount: 0` with an empty `participants`
subcollection, and `watchLivePublicRooms` keeps advertising it on Home and
Discover. A process death between the two calls produces the identical
document and no client can repair it at all.

`executeLeaveRoom` deliberately does not fix this: it returns early when the
caller holds no participant row, and extending the repair there would let any
signed-in account drop `isLive` on a live room during somebody else's
start→join window — a denial-of-service lever on a public room.

**Decision.** A scheduled `sweepStrandedLiveRoomsSchedule`
(`functions/rooms/liveness_sweeper.js`, `europe-west1`, every 5 minutes)
closes rooms that have been `isLive: true` with an **empty roster** for longer
than a 5-minute grace period, setting `isLive: false`, `participantCount: 0`
and `endedAt`, then calling LiveKit `endRoom` and clearing the
`activeVoiceSessions` mirrors exactly as `executeEndRoomVoice` does.

Four properties carry the safety:

1. **The roster decides, never `participantCount`.** The counter is only ever
   written (repaired to 0), never read to decide anything — a stale-low value
   would turn the sweep into an eviction, because `endRoom()` disconnects
   everyone.
2. **Every decision is re-made inside a transaction** against a fresh read of
   the room and the roster. The scan is a hint; the transaction is the
   verdict. This is the same defence `onlyIfEmpty` uses, and without it the
   sweep would be the very bug that flag exists to prevent.
3. **`updatedAt` is the age anchor, and it is provably sound.** No server path
   writes `isLive: true` — every server write of that field is `false` — so
   the client is its only writer, and both client branches that may write it
   (`roomVoiceStartAllowed()` and `hostRoomUpdateAllowed()`'s start branch)
   require `request.resource.data.updatedAt == request.time`. Every later
   write moves it forward, so the anchor can only ever be too conservative,
   never too eager.
4. **A deleting or explicitly moderated room is skipped**, because
   `executeDeleteRoom` and `executeSetRoomStatus` own those teardowns.

`status` is read through `roomIsActive()` in memory rather than filtered in
the query, so the 25 production rooms with no `status` field are covered.

**Reasoning.** The repair belongs on a schedule precisely because a schedule
has no caller to impersonate — that is what buys the fix without the
denial-of-service lever. Five minutes is set by the window it must not
interrupt: the start→join gap is one Firestore round trip, so the grace period
carries two orders of magnitude of headroom while still clearing a ghost
inside one sweep of the same Home screen. The query is a **bare equality on
`isLive`**, served by Firestore's automatic single-field index, so this
function cannot fail its first production run on a missing composite — the
failure mode that left Premium never expiring for any account
([DEPLOYMENT.md](DEPLOYMENT.md)). Per-room failures are isolated and re-raised
in aggregate so one unreachable SFU room cannot cost the others their sweep,
nor turn a broken run green.

**Consequences.** No Firestore field, collection or document shape moved, and
**no index change is required**: `getAdminDashboard` and `getStaffOverview`
already run a strictly harder version of the same query in production, and
`deleteActiveVoiceSessionsForRoom`'s collection-group lookup is backed by the
existing `rooms.roomId` `COLLECTION_GROUP` override. Cloud Scheduler is an
**existing** deploy dependency — seven `onSchedule` functions already ship —
so this adds a schedule, not a dependency.

**What this does not fix, stated rather than implied.** A client that crashes
**while in a room** leaves its participant row behind. That roster is not
empty, so this sweep skips it and the room stays live with a ghost on stage.
Repairing that needs per-participant liveness only the SFU can honestly
report — the unexported `receiveLiveKitAchievementWebhook`, which is Roadmap
item 0h and which DEPLOYMENT.md already names as the real fix for the
`voiceMinutes` and live-presence gaps. This sweep is scoped to the
empty-roster case on purpose and is not a substitute for that work.

## ADR-093: An absent `status` means active — one reading of the field, shared by the rules and every callable

*(Renumbered from ADR-092 on 2026-08-20: two concurrent sessions appended
an ADR-092 within the same minute. The scheduled-sweep entry above kept the
number because it appears first in this file and carried three inbound
references to this entry's one.)*

**Context.** ADR-088 made entering a room perform the `isLive: true`
transition. Hours after that shipped, an audit of the deployed code found that
five callables gated on a bare `room.status !== "active"` while
`firestore.rules` reads the same field as `.get('status', 'active')`
everywhere. **25 of the 45 rooms in production carry no `status` field at all**
— they predate it.

The two readings therefore disagreed on the majority production shape, and the
disagreement was the defect rather than a cosmetic inconsistency:

1. The deployed ruleset **authorised** the client's `isLive: true` write on a
   legacy room.
2. `authorizeRoomVoiceAccess` (functions/livekit/token.js) then **refused** the
   LiveKit token for that same room with *"This room is not currently live."* —
   the exact sentence the whole wave existed to remove.
3. `executeEndRoomVoice` read the field the same bare way, so the room could not
   be switched off either. It was left flipped live with nobody able to connect.

**Decision.** One helper, `roomIsActive(room)` in `functions/utils/firestore.js`,
returning `String(room?.status ?? "active") === "active"`. It is the only
reading of the field, used by the LiveKit token gate, participant removal, host
moderation, own-mute and end-voice. `executeLeaveRoom` had already defaulted the
field correctly and converges on the helper rather than keeping a second copy.

**Reasoning.** A legacy document is not a suspended one. Moderation writes an
EXPLICIT `"suspended"` / `"closed"` / `"archived"` value, so every genuinely
inactive room carries the field — which is precisely why defaulting the absent
case to active loosens nothing moderation depends on. The alternative,
backfilling `status: "active"` onto 25 documents, was rejected: it fixes the
data once and leaves the next legacy field to produce the same class of bug,
whereas agreeing with the ruleset fixes the reading. Two regression cases pin
the boundary — a legacy room that is `deletionInProgress` is still refused, and
an explicitly suspended room is still refused — and both pass on either side of
the change, which is what proves the default did not widen the gate.

**Consequences.** Client and server now answer "is this room active?"
identically, so a room the rules let you start is a room the token endpoint will
serve. **The achievements webhook gate was deliberately left alone**: it rejects
these rooms through a separate `roomType` allowlist regardless, so changing its
status read would alter no behaviour, and it is not currently delivering.

**The same root cause had a client-side twin, fixed with it.**
`RoomService.leaveRoom` classified rooms with `RoomType.fromValue`, which
answers `temporary` for anything that is not the string `'community'` —
including the 24 production rooms with no `roomType` field. Routed through the
temporary branch, a host merely backing out of such a room would end the voice
session for everyone still talking: that call is unconditional, passes no
`onlyIfEmpty`, and never reaches `leaveRoomSelf`, so the caller's own
participant row is left behind too. The branch now requires the literal field.
Production carries exactly three values — `community` (6), `temporary` (15),
absent (24) — so a room that genuinely opted into temporary still ends when its
host leaves, unchanged.

**The lesson worth keeping is about defaults, not about `status`.** Any field
added after launch splits production into documents that have it and documents
that do not, and every reader must then agree on what absence means. The rules
made that choice explicitly with `.get(field, default)`; the callables made it
implicitly and differently. **When a rule uses `.get` with a default, the
server code reading the same field must use the same default, and the cheapest
way to guarantee that is one shared predicate rather than a convention.**

## ADR-094: A self-mute is a track state, not a permission — and outside a broadcast, everyone present may speak

**Context.** Muting yourself in a room revoked the LiveKit `canPublish`
permission: `deriveVoiceGrant` and both permission-recompute callables folded
`participant.isMuted` — the person's OWN mute — into the grant. The client
reads a missing publish grant as "you are audience" (`MicState.listenOnly`),
hides the mute toggle, and leaves nothing to unmute with; the flag persists in
Firestore, so every later token — including on re-entry — reproduced the trap.
Separately, self-service joins are pinned to `role: 'listener'` by
firestore.rules while the grant required host-or-speaker, so every non-host in
a Family or Community room was a permanent audience member who could never
speak at all.

**Decision.** Publishing is taken away only by a moderator mute (`hostMuted`),
a server mute (`serverMuted`) or a sanction (`communicationMuted`) — never by
the participant's own mute, which is a track state the client toggles locally.
Outside a broadcast room (`experience` of `broadcast` or the legacy
`podcast`), every participant may publish without promotion; a fieldless room
is a community room, mirroring `RoomExperience.fromValue`. One shared
`publishAllowed` predicate keeps the two callables and the token computing the
same answer, and `joinRoom`'s re-entry path reconciles the caller's own stale
`isMuted` flag (moderator flags are pinned by the rules on that write and
survive re-entry).

**Reasoning.** The Discord model is the correct one: mute controls the track,
permission controls the right, and conflating them builds a trap that closes
on the person who used the control correctly. The broadcast audience model is
untouched — that product genuinely has listeners who must be promoted, and the
tests pin promotion on both sides of the change.

**Consequences.** 7 new `deriveVoiceGrant` cases; 3 fail against the previous
code and the moderation/broadcast cases pass on both sides, which is what
proves nothing was loosened. The permission had NO test before this — that is
how a defect this visible shipped. No rules change, no schema change.

## ADR-095: The Moments board ranks deterministically and freezes its order, while counts update live in place

**Context.** The Discover tab rendered one Moment per viewport with a huge
empty middle; the operator asked for a wall of avatar circles with the
most-engaged at the top, compact Following tiles, and counts that do not wait
for a page reload.

**Decision.** The board sorts by `rankByEngagement` — a deterministic
descending sort over the existing `discoveryWeight` (like + half-comment,
log-compressed), ties broken by recency then id — and the weighted shuffle
survives behind an explicit chip. Engagement counts stream via
`watchEngagement()` (one listener over the recency pool, an already-used query
shape) and patch documents in place through `VoiceMoment.withCounts`, but the
ORDER is frozen for the life of a load.

**Reasoning.** Live counts and live ordering must not be coupled: reordering a
board under a person's finger as likes arrive is worse than a count being a
minute old. Freezing the order per load gives both truths — the numbers move,
the layout does not. A failing counter stream leaves the loaded (real) numbers
alone rather than zeroing them.

**Consequences.** Live counters cover the 60 most recent published Moments; an
older Moment that reached the board only via the popularity pool keeps its
loaded counts — real numbers, just not live. `MomentCard` moved to its own
file with a re-export from `moments_screen.dart`, so importers are untouched.
Playback, like, comment, report and offline download all survive behind the
new tile/sheet presentation.

## ADR-096: A club is deleted by its owner through `deleteClubSelf`, and the lounge's delete dialog is that lifecycle's front door

**Context.** `executeDeleteRoom` refuses club lounges with "A Club Lounge is
deleted through the Club lifecycle" — and that lifecycle did not exist: no
callable, no `ClubService` method, no control anywhere in the UI. Family Rooms
are club lounges, so the operator's family and club rooms were permanently
undeletable, with a dialog whose Delete button could only ever display the
server's refusal.

**Decision.** A new owner-only callable `deleteClubSelf({clubId})` performs
the whole teardown: one transaction marks the club (`deletionInProgress`,
`deletionRequestedBy/At` — the exact fields `adminDeleteClub` already writes)
and closes the lounge; after commit it ends LiveKit, clears session mirrors,
recursively deletes the lounge tree and the club tree (members, invites,
channels+messages, moments, checkIns), cleans Storage media, sweeps every
`users/{uid}/clubs` projection via `collectionGroup('clubs')`, and writes an
audit entry. A repeat call RESUMES an interrupted teardown (idempotent), and
after a pending ownership transfer the RECIPIENT is the owner who may delete.
The client routes a lounge's delete — on the Home board and in Room settings —
to this callable with copy naming the club; a non-owner gets no control, and
the lounge branch is structurally incapable of calling `deleteRoomSelf`.
`executeDeleteRoom`'s refusal stays as defense in depth.

**Reasoning.** The lounge IS the club's room; deleting one honestly means
deleting the club, and the dialog says so rather than pretending it is a room
deletion. Authorization is the server-read `club.ownerId` only — never the
lounge's client-influenced `hostId`.

**Consequences.** The mandatory reviews earned their place: the adversarial
security audit passed the design (SHIP), and the independent correctness
review caught two real defects before deploy. (1) The projection sweep's
`collectionGroup('clubs')` query had NO single-field exemption in the live
project — verified against production, invisible to the emulator (the ADR-007
class); `firestore.indexes.json` now carries the `clubs.clubId` override in
the full COLLECTION+COLLECTION_GROUP form the invites fix established, it was
deployed FIRST, and the exact query was executed against production before
the callable shipped. (2) `_OwnedRoomMenu` bound its club stream in
`initState` alone while Home's lists reorder on every join/leave — a recycled
element could show one club's name and delete ANOTHER; fixed with
`didUpdateWidget` re-binding plus room-id keys at both sites, and pinned by a
regression test that fails against the unfixed widget. Known limitation,
accepted: if the post-commit sweep fails midway (e.g. Storage outage), the
repeat call resumes it, but once the dialog is dismissed the UI offers no
retry surface — the club stays consistently marked and refusable, never
half-alive.

## ADR-097: A live-room count that must honour an absent `status` is a bounded read, not a `count()` aggregate

**Context.** [ADR-093](#adr-093-an-absent-status-means-active--one-reading-of-the-field-shared-by-the-rules-and-every-callable)
settled that an absent `status` means active, and `roomIsActive()` made that
the one reading used by every callable. Three server-side queries were never
converted, because they are not in-memory checks: `getAdminDashboard`'s
`liveRooms` `.count()`, and `getStaffOverview`'s live-room `.count()` and its
`limit(5)` listing. All three ran
`where("status","==","active").where("isLive","==",true)`, which matches only
documents where the field is present and equal — so all 25 legacy production
rooms were dropped from the numbers the owner and staff use to see what is
happening right now. `DEPLOYMENT.md` had already named this gap in writing
when the liveness sweeper shipped, and left it open.

**Decision.** One helper, `listLiveActiveRoomDocs()` in
`functions/rooms/live_rooms.js`: query `where("isLive","==",true)` with a
bounded `limit`, then filter the documents with `roomIsActive()` in memory.
Both callables use it. It returns the documents rather than a number, because
the staff overview needs both a count and the first few rows and previously
issued the same query twice to get them. A run that reaches the scan bound
reports `truncated: true` and logs it.

**Reasoning.** There is no Firestore filter that spells "absent OR equal to
active", so a server-side aggregate **cannot** express the reading the rules
use — the choice is not between two equivalent implementations. That leaves
reading the documents or backfilling `status: "active"` onto the 25 legacy
rooms, and ADR-093 already rejected the backfill for a reason that has not
changed: it fixes the data once and leaves the next legacy field to produce
the same class of bug. Reading the documents is affordable here for the same
reason `sweepStrandedLiveRooms` relies on: the whole collection is ~45
documents and only a handful are ever live. **This is not a general licence to
replace aggregates with reads** — it applies where an absent-field default has
to be honoured AND the candidate set is small and bounded.

**Consequences.** The index that serves the query changed, which is the part
worth checking before landing a dropped clause: the two-equality form needed a
zigzag merge of two automatic single-field indexes (there is no
`(status, isLive)` composite in `firestore.indexes.json` and there never was),
while a single equality on `isLive` is served by the automatic single-field
index alone. This **removes** an index dependency rather than adding one, and
it is the identical query the deployed sweeper has run every five minutes
since `b7c6d99`. The staff overview now performs one live-room read instead of
two. Both counts become O(live rooms) reads rather than a metered aggregate —
correct, and on this collection cheaper than the pair of aggregates it
replaces. If `rooms` ever grows such that hundreds are live at once, the bound
is what will show it: the `truncated` warning names the surface, and that is
the point at which a `status` backfill plus a real aggregate becomes the right
trade. `LIVE_ROOM_SCAN_LIMIT` duplicates the sweeper's `MAX_LIVE_ROOM_SCAN`
rather than importing it, so two callables do not drag the scheduler and the
LiveKit control plane into their cold start.

## ADR-098: One room presentation system, four identities — and the stage owns the leftover height

**Context.** The four room types (Community, Family, Club, Podcast/Broadcast)
had drifted into near-copies of the same stage/controls/chat code —
`broadcast_stage.dart`, `broadcast_bottom_controls.dart` and
`broadcast_owner_controls.dart` largely duplicated what the community screen
built inline — and the operator supplied rendered references asking for a
substantial visual rebuild: floating control dock, light header, hero banner,
a stage where the host reads as central rather than a small card adrift in a
tall panel, compact audience strip, and a compact desktop sidebar with the
notification bell moved to the top.

**Decision.** One shared presentation layer under
`lib/features/rooms/presentation/widgets/` — `RoomHeader`, `RoomHeroBanner`,
`RoomStagePanel`/`StageGrid`/`SpeakerTile`, `AudienceStrip`,
`RoomControlDock`, `RoomQuickActions`, `RoomEnergyWave` — consumed by both
screens. The room type controls ONLY accent, icon, wording, hero content and
optional actions (Community/violet, Family/emerald, Club/gold,
Podcast/coral); layout is one system. The three `broadcast_*` duplicates are
deleted. Community and Broadcast remain SEPARATE PRODUCTS — separate screens,
separate routing, broadcast audiences still promoted to speak; only
presentation is shared, which is the boundary CLAUDE.md's invariant draws.

On width>=900 and height>=720 the main column stops being a ListView: hero
and audience strip keep natural size and the stage takes the leftover height
(`RoomStagePanel.fill`), growing a small cast's tiles. Narrow and short
viewports keep the scroll — fill inside an unbounded-height parent would be
both broken and pointless.

**Reasoning.** A stage is the room's centre of gravity; a layout that lets it
hug one small card under a third of a screen of dead space misstates what the
product is. Sharing the system rather than the screens keeps the two-product
invariant intact while ending the four-way drift.

**Consequences.** Accent-consistency is now a per-identity property the
harness photographs (all four identities, 1..n speakers, empty and crowded
audiences, 390..1440 plus 320@200% and short viewports). Three defects were
found only by OPENING the rendered PNGs and are worth remembering as classes:
(1) `ButtonStyle.styleFrom(textStyle:)` REPLACES the style — omit the family
and that control falls off the app typeface (it rendered as solid block
glyphs under the test framework's fallback font); (2) a screenshot harness
rendering under `ThemeData.dark()` instead of `AppTheme.darkTheme` produces
PNGs that prove nothing about the shipped screen; (3) letter-fallback avatars
carried the app default purple into green/gold/coral rooms — fallback colours
are identity surface too. The sidebar's More popover is a true Overlay (no
layout shift), the bell is the single notifications entry point, and Alerts
(preferences) stays a separate concept.

## ADR-099: UI sounds are build artifacts of a checked-in generator, in one musical language

**Context.** The eight UI sounds (room created/joined/left, participant
joined/left, mic muted/unmuted, notification) were opaque hand-made WAVs the
operator found unpleasant, with no record of how to remake or extend them
consistently.

**Decision.** `tool/generate_ui_sounds.py` deterministically synthesizes the
whole set — soft glass-bell timbre (sine partials only, ±2.5-cent chorus),
one key (A-major pentatonic: E4/A4/C#5/E5), one grammar (beginnings rise,
endings fall, mirrored intervals), 8 ms attacks, exponential decays, last
sample exactly zero, every file peak-normalized to -6 dBFS. Filenames and
durations match `lib/core/audio/ui_sound.dart`, so regeneration never touches
Dart; loudness balance stays in each `UiSound.volume`.

**Reasoning.** "More pleasant" was made measurable: energy above 2 kHz
dropped in every file (notification 25.9% → 8.2%, participant_joined
17.7% → 7.2%). Crest factor was rejected as the metric — a decaying bell's
quiet tail inflates it regardless of timbre. A generator beats binaries
because the next sound has to join a family, not a pile.

**Amended same day (v2, "exclusive").** The set became STEREO with a
felt-mallet glass-bell timbre: a sub-octave body, slightly inharmonic glass
partials (2.756x, 5.04x — real bells are not integer stacks), an 8-cent
mallet pitch-settle over 40 ms, longer silk tails, and subtle width from a
±2.5-cent Haas pair around a mono anchor. Two width mistakes were caught by
the script's own verification rather than by ear: delaying the whole right
channel decorrelated the longest file to 0.18 inter-channel correlation
(phasey), and the partial stack alone was too quiet an anchor (0.20) — an
undetuned center fundamental joined the anchor and every file now measures
0.76-0.94, inside the 0.2..0.98 window the generator checks.

**Consequences.** New sounds are added by composing notes from the same four
pitches in the script and rerunning it. Subjective pleasantness is
UNVERIFIED by the author (no ears); the operator's listen is the acceptance
test. Preview locally: `afplay assets/audio/ui/v3/notification.wav`.

**Superseded by ADR-116 (2026-08-27; Hosting deployed, native/FCM held).** The
operator rejected the v2 glass-bell/pentatonic language as retro and kitschy.
The generator remains the authority, but the musical grammar above is
historical rather than a rule for new work.

## ADR-100: The pre-stories Discover avatar board is deleted, not kept dormant

**Context.** The Voice Moments stories redesign replaced the Discover avatar
board (`MomentDiscoveryView`, ~2000 lines) with the feed + story viewer
(`MomentsFeedView`, mounted by `moments_screen.dart`). After the last test
importer (`test/moment_report_reachability_test.dart`) was re-targeted to the
new surfaces, nothing in `lib/` or `test/` imported the board.

**Decision.** `lib/features/moments/presentation/widgets/moment_discovery_view.dart`
is removed. The dangling dartdoc link in `moment_card.dart` now points at the
card's other injection seams; the HISTORY note in
`moment_report_reachability_test.dart` deliberately keeps the old name as
prose, recording where its claims came from.

**Reasoning.** An unreferenced 2000-line surface is not a fallback, it is a
trap: it silently drifts from the services and theme it once matched, and it
keeps showing up in searches as if it were a live answer. Git history is the
archive; the working tree should only contain what runs.

**Consequences.** `flutter analyze` clean and all 1114 tests pass after the
removal. Any future "board" style discovery surface starts from the current
feed architecture, not from resurrecting this file.

## ADR-101: Voice Moments are 24-hour audio stories — many per author, expiring server-side, viewed per-user

**Context.** The operator asked for an Instagram-Stories-like rebuild: more
than one Moment per user, a clear 24-hour lifetime, story-chain playback,
and a modern feed with a detail panel. Scouting found the backend never
enforced a single Moment (`momentId = digest(uid, requestId)`) — the limit
was a client illusion — but nothing expired, nothing was viewed-tracked,
and the feed was the ADR-089 board.

**Decision.**
- `finalizeMomentDraft` stamps `expiresAt = createdAt + 24h` (additive);
  the create rule BANS `expiresAt` on client writes and the author-update
  branch pins `createdAt`/`expiresAt` immutable, so only the server ever
  sets or moves an expiry — an author cannot extend their own story.
- Expiry is two-layer: `expireVoiceMomentsSchedule` (10 min) flips past-due
  docs to `{isPublished:false, status:'expired'}` and the client filters
  `expiresAt > now` everywhere, covering the sweep gap. A legacy document
  with NO `expiresAt` is treated as expired — intended: the 24-hour product
  has no place for immortal posts.
- `reserveMomentDraft` caps 10 simultaneously active Moments per author
  (bounded scan over the new `(authorId, createdAt DESC)` composite; the
  sweeper query gets `(isPublished, expiresAt ASC)`).
- Viewed state is per-user at `users/{uid}/momentViews/{momentId}`,
  owner-only, `{viewedAt: request.time}` pinned, no delete. No global view
  counter exists, so none is displayed — the reference's play counts are
  deliberately not reproduced.
- Chains play oldest→newest; the strip orders authors by newest Moment;
  a chain is unviewed if any member lacks the caller's view doc.
- The client's legacy direct-publish fallback is CLOSED with a loud
  refusal: it could never stamp `expiresAt`, so its output would be
  invisible forever — including to its author — while reporting success.

**Reasoning.** Every piece keeps server authority where forgery would pay
(expiry, cap, canonical creation) and keeps client-side what only the
client knows (which Moments THIS user heard). The review pass earned its
place again: it caught an ADR-095 regression (ranking on live counters —
reordering under the user), an unordered `limit(40)` window that legacy
squatters could starve, and the fallback-invisibility trap, all fixed
before deploy.

**Consequences.** Deploy order is load-bearing: indexes to READY and
query-proved (ADR-007), then rules, then functions, then hosting — hosting
before functions would publish author-invisible Moments for the window.
Known open edges (Bugs.md): sheet/card playback does not yet mark viewed
(chain rings can stay "unviewed" after listening through the sheet); the
website's `?moment=` links to expired Moments land on an unpublished doc.

## ADR-102: The active-room mini-player — isolated tap targets, one session, session-local "new"

**Context.** The persistent live-room bar wrapped everything in a single
`InkWell(onTap: return-to-room)` with IconButtons inside. Flutter forwards a
tap THROUGH a disabled button to its parent, and Mute is briefly disabled on
every toggle (`muteChangeInProgress`/coordinator busy) — so pressing Mute in
that window NAVIGATED INTO THE ROOM, as did taps in the padding between
icons. The operator reported exactly this, and asked for a full mini-player
rebuild to reference mockups (desktop dock + mobile card, live chat preview,
expand-in-place, isolated controls).

**Decision.** `ActiveRoomMiniPlayer` (one controller; desktop/mobile are
layout variants) with NO parent-wide tap: room-info navigates, Mute toggles
(a disabled Mute CONSUMES the tap), Expand opens the reused `RoomChatPanel`
(desktop: anchored overlay popover with FocusScope/Escape/announcement;
mobile: draggable sheet that the session's death now dismisses), Return
navigates, Leave/End leaves via `RoomService.leaveRoom` (ADR-091). The
destructive label says **"End room" only when the tap genuinely ends the
session now** (temporary-room host); a persistent-room or lounge host reads
"Leave room", because the server ends those on an empty roster — the label
follows what the tap does, while the chat surface still receives TRUE host
status for moderation. The collapsed preview subscribes to `limit(1)` on the
newest message; "N new" is a SESSION-LOCAL counter (arrivals while
collapsed; reset on expand/return) — the backend has no per-user room-chat
read state and none is faked.

**Consequences.** 18 regression tests pin the navigation-isolation matrix
(including the disabled-Mute repro that failed RED against the old bar).
The three reviews ran pre-deploy; the a11y FIX_FIRST items (26px Expand
target → 44pt floor, duplicate merged tile labels → excludeSemantics,
4.41:1 preview labels → lifted, popover Escape/focus/announce) and the
principal's sheet-outlives-room and End-overclaim findings were all fixed
before release. Known limits, recorded: the in-player 1.6x text clamp;
real mobile-Safari insets and AT behaviour unverified headlessly.

**Amendment, 2026-08-29 — mobile YO Live Capsule.** The controller and desktop
four-zone dock remain unchanged, but widths below 880 px no longer render the
multi-row collapsed card. Mobile now reserves one 82 px capsule: room identity
is one isolated return target, while Chat, Mic and More are separate 48 px
circular targets. Latest-chat, session-local unread, audience and reconnecting
state are compressed into one-line metadata; Return and truthful Leave/End are
secondary actions in a compact modal. Mobile honors the complete system text
scale and ellipsizes visual metadata while retaining full semantic labels.
The modal is owned by its exact `ModalBottomSheetRoute`; session cleanup may
pop it only while that route is current, preventing a reverse-transition race
from removing the underlying screen. Host confirmation is likewise bound to
the captured room id, so a stale response cannot affect a replacement session.
The focused matrix is now 26 tests, including gaps, busy Mute semantics,
remote-end cleanup and a real sentinel-route race. Dark/Pearl stills at
320/390/430 px and 200% text use the production YO dock; visual, accessibility
and principal reviews all passed.

## ADR-103: The author chooses a Moment's availability — and a missing `expiresAt` now means permanent

**Context.** ADR-101 fixed every Moment's life at 24 hours and read a
missing `expiresAt` as "legacy, hidden". The operator asked for
author-chosen availability — 24h / 3 days / 7 days / 30 days / keep until
deleted — plus first-class deletion of own Moments (the way to free a slot
and record something new) and the mobile feed/detail/nav redesign.

**Decision.**
- `finalizeMomentDraft` accepts optional `availabilityHours`: strict
  whitelist [24, 72, 168, 720] or the literal `'permanent'`; absent
  defaults to 24; anything else is invalid-argument before any transaction.
  `'permanent'` writes NO `expiresAt` field.
- **A missing `expiresAt` now means PERMANENT** on every client surface —
  the deliberate reversal of ADR-101's null=hidden. The only null-expiry
  docs in production are operator-owned legacy ones, which become visible
  again by design. The sweeper is untouched (a range filter never matches a
  missing field), and the rules needed NO change: create still bans the
  field, and the author-update `affectedKeys()` pin refuses add, change
  AND removal — stripping the field to self-grant permanence is the new
  attack the amendment creates, and it was already impossible (now pinned
  by a rules test).
- The ledger hash keeps the deployed composition for the default, so live
  production replays keep working; a NON-default availability joins the
  hash, so replaying the same requestId with a different duration answers
  already-exists and the stored deadline never moves — no
  publish-then-flip-permanent.
- The cap counts permanent Moments as active forever; DELETION frees the
  slot immediately. The client's `deleteMoment` now routes through the
  deployed `deleteMoment` callable — the review caught the old client-side
  subcollection sweep failing permission-denied on any Moment somebody
  else had liked or commented (rules only let each engager delete their
  own docs), which would have broken the ONLY exit for permanent Moments.
- Mobile: the feed and the new `MomentDetailScreen` follow the operator's
  mockup within the honesty deviations (no cover photos, no plays counter,
  no tags — none of that data exists; "Top reactions" ARE real likers from
  the likes subcollection); the bottom nav's center action is the YO logo.

**Consequences.** Deploy order is functions BEFORE hosting: the old
finalize refuses unknown fields, so a new client sending a non-default
duration against old functions cannot publish at all. Legacy operator
moments start occupying cap slots at functions deploy. Known small gaps
recorded in Bugs.md: the availability cannot be changed after publishing
(deferred by the brief), and real-device rendering remains unverified
headlessly.
## ADR-104: The Admin Center's "active" room filter reads `status` the way the rules do — and the filter it replaced never ran at all

*(Renumbered 097 → 101 → 104. The third instance of the hazard ADR-093
records: 097 was free when this was drafted, `main` then landed
ADR-097/098/099 — including this change's sibling `fb88dbd` — and while
this branch sat unmerged `main` also took 101, 102 and 103. Merged from
`claude/distracted-cannon-2d2529` on 2026-08-22. The two collisions the
earlier note flagged are both resolved: `claude/determined-feistel-e7a87a`
turned out to be fully superseded by `main`, and the then-uncommitted
ADR-100 has landed.)*

**Context.** `listAdminRooms` (`functions/admin/rooms.js`) built the room
browser's status filter as a literal
`db.collection("rooms").where("status", "==", status).orderBy("updatedAt", "desc")`
from a caller-supplied value. ADR-093 had already settled what this field
means everywhere else: `firestore.rules` reads it as
`.get('status', 'active')`, `roomIsActive()` mirrors that default, and an
absent `status` therefore IS active. ADR-097 had just applied that same
reading to the staff aggregates via `listLiveActiveRoomDocs()`; this is the
paginated browser, which that helper does not serve — it answers
"`isLive` and active, up to a scan cap", not "any status, by cursor". A read-only production census
(Admin SDK, 2026-08-21) puts numbers on the gap — of 45 rooms, **9 carry an
explicit `"active"`, 11 carry `"closed"`, and 25 carry no `status` at all**.
The clause recognised 9 of the 34 rooms the rules call active.

Two things sharpened that from an inconsistency into a defect:

1. **`mapRoom`, in the same callable, already defaulted the field** —
   it returns `data.status ?? "active"`. So the unfiltered browser
   displayed all 25 legacy rooms as *active*, and then the "active" filter
   denied they existed. The callable contradicted its own output.
2. **The filter never actually ran.** No `status`+`updatedAt` composite
   index exists in the live project — confirmed twice, by executing the
   query (`9 FAILED_PRECONDITION: The query requires an index`) and by
   reading the deployed config with `firebase firestore:indexes`. Staff
   filtering by *any* status got an error, not a short list. The premise
   that legacy rooms were "silently dropped" was too generous.

**Decision.** "Active" means active as the rules read it, absent included.
For that one value the equality clause is dropped and the page is filtered
in memory with the shared `roomIsActive()` predicate; every other value
(`closed`, `suspended`, `archived`) is written EXPLICITLY by moderation and
keeps the indexed server-side equality. The two missing composite indexes
(`rooms` and `clubs`, `status` ASC + `updatedAt` DESC) are added to
`firestore.indexes.json` so those other values can resolve at all.

**Reasoning.** This was a product call before it was a code fix, and the
census decides it: because moderation always writes an explicit value,
"explicitly active" does not name a moderation state — it names the cohort
of rooms created after the field was introduced. A staff member filtering
"active" is asking which rooms users can currently enter, and under the
deployed ruleset that is 34 rooms, not 9. Choosing the literal reading
would have rebuilt, in the moderation surface specifically, the exact
disagreement ADR-093 exists to prevent: a room the rules let a user join,
that the browser insists is not active.

**Consequences.**

- **An index deploy is required for the non-"active" filters.** The
  "active" path now needs no composite index at all (a bare
  `orderBy("updatedAt")` is served by the automatic single-field index, and
  all 45 production rooms carry `updatedAt`, so it drops nothing). `closed`
  and `suspended` stay broken until `firebase deploy --only firestore:indexes`
  runs. Deploys remain manual on purpose (`docs/DEPLOYMENT.md`).
- **Do not deploy indexes from this branch alone.** This branch's
  `firestore.indexes.json` does not carry the live `clubs.clubId` exemption
  that `claude/determined-feistel-e7a87a` backported; an index deploy from
  here would offer to DELETE it and break `adminDeleteClub`'s projection
  sweep — precisely the trap that branch's ADR-096 documents. Merge first,
  or verify against `firebase firestore:indexes` before deploying.
- **`nextCursorId` counts documents SCANNED, not rooms returned.** Both
  filters run after the `limit`, so a page can come back empty and still
  carry a cursor. This is not new — `search` has always behaved this way —
  but it is now commented at the call site and pinned by a test, because
  the obvious "stop when a page is short" client loop would stop early.
- **Clubs were checked and deliberately left alone.** `admin/clubs.js:180`
  has the identical query shape and 1 of 3 production clubs carries no
  `status` — but the answer there is NOT the same, because the club rules
  read the field BARE (`get(clubPath).data.status == 'active'`), so an
  absent status already means "not active" to the ruleset. Copying the room
  fix across would have made the browser disagree with the rules rather than
  agree with them. Two real findings are logged in `docs/Bugs.md` instead:
  that bare read is itself inconsistent with `deletion.js`'s
  `String(club.status ?? "active")`, and `mapClub` defaults absent to
  `"open"` — a value the codebase never writes.
- The emulator enforces no composite index (ADR-007, ADR-082, ADR-096), so
  the eight new cases in `functions/test/admin_room_listing.test.js` prove
  the *semantics* and prove nothing about the index. The index claim rests
  on the two production reads above, not on the suite.
## ADR-105: A direct message is written only by the server, and an unsendable one waits in a bounded local outbox

*(Renumbered 082 → 105 when this branch was merged on 2026-08-22. It had
sat unmerged while `main` moved 36 commits ahead and independently used
082 for the reachability decision. Inbound links elsewhere in the docs
were updated in the same merge.)*


**Status**: Accepted
**Date**: 2026-08-19

### Context

`conversations/{conversationId}/messages/{messageId}` allowed a client to
create a message document. The rule checked `isVerified()`, that the caller
was a participant and the sender id matched, that the pair was not blocked,
and — added shortly before this — the recipient's `messagePrivacy`.

It did not check whether the SENDER was still allowed to speak.
`isVerified()` reads `request.auth.token.email_verified`: a token claim that
says an email was confirmed once, and nothing about account standing. The
authoritative status lives in `users/{uid}.banned|disabled` and
`restrictions/{uid}` (a staff `communicationMute`), which `canCommunicate()`
reads and which the conversation-root rule directly above already required.

The gap was reachable. `sendDirectMessage` does call `activeProfile()` and
`assertNotRestricted()` — but inside the callable, and
`message_service.dart`'s `_sendTextMessageDirectly` wrote the message
document straight from the client whenever `_tryCallable` reported the
callable absent. On that path the rule was the only backstop, and it did not
enforce the sanction. **A banned or communication-muted account kept full
direct messaging by taking the fallback**, along with a bypass of the rate
limiter and the idempotency ledger.

### Decision

`allow create: if false` on the message subcollection. `sendDirectMessage`
is the sole writer. The client keeps a bounded, persisted outbox
(`lib/features/messages/data/services/message_outbox.dart`) with Pending /
Retrying / Failed states, retries each entry under its original `requestId`,
and drains when connectivity returns. One process-wide production
`MessageService.live` owns one queue per authenticated UID under
`messages.outbox.v2.<uid>`; its first load is a shared Future and all mutations
are serialized. The ownerless v1 key is retired instead of guessed across an
account switch, and MainShell resumes the authenticated queue on cold start.
`_sendTextMessageDirectly` is deleted. Chat renders the queue optimistically:
local persistence releases the composer, the backend's deterministic message
id reconciles callable and Firestore arrival order, and terminal entries retain
Retry/Remove recovery. Typing presence is a coalesced state transition with a
bounded heartbeat, not a write per keystroke.

### Reasoning

The obvious fix — add `canCommunicate()` to the rule — was implemented,
tested, and **abandoned on evidence**. It exceeds Firestore's per-request
document access-call budget. Measured against the emulator (the run below
was taken at `b123aec`, before the club chat pass added 43 more checks; the
counts differ from today's table for that reason, the finding does not):

- pure `b123aec`: 403 rules checks green, friends-mode send allowed;
- with `canCommunicate()` added: 408 passed / 1 failed, the failure being
  `SECURITY DM PRIVACY: friends requires both canonical guard halves` with
  `Service call error. Function: [exists]` on the second friendship guard;
- synthetic `exists()` probes on the same path: **+1 access call passes,
  +2 fails** — exactly one call of headroom;
- the mute check alone (1 call, a single `exists` on a usually-absent
  document, which short-circuits) fits; `isActiveAccount()` (3 calls) does
  not; full `canCommunicate()` (4) does not.

An exhausted rule does not skip the check. It errors, and an error denies —
so the "fix" broke legitimate sends. Consolidating the rule's five redundant
re-reads of the conversation document, collapsing `accountIsActive()` to a
single `get`, and collapsing `canonicalFriendshipGuard`'s seven access calls
to one were each tried; none freed enough.

That leaves a choice between shipping a partial gate — closing the mute
bypass while leaving banned and disabled accounts able to send — and moving
the write behind something that can afford every check. A rule that can only
afford some of its authorization is not the right place for any of it, and a
sanction enforced against two of three states is one a moderator cannot
reason about. The callable already performs all of it, plus the rate limit
and the ledger.

The cost is losing the fallback, and that cost is only acceptable because
the message is not lost with it. `requestId` was already part of the
callable's contract and already recorded in a server-side idempotency ledger
(`operationIdentity` / `assertLedgerReplay`), so a persisted queue that
reuses the id makes retries safe for free — including the case that
motivates the whole design, where the server committed the write and the
response was lost.

The queue is bounded (50) because an unbounded one turns a long offline
stretch into unbounded local storage and a reconnect burst the server's own
rate limiter would reject, converting a queue into a pile of permanent
failures. It refuses at capacity rather than evicting an unsent message,
and evicts FAILED entries first to make room. Retries stop after 6 attempts;
a retry loop that never gives up is how a permanently-broken send becomes a
permanent battery and quota drain. Refusals are never retried — a refusal
repeated on a timer is just a slower refusal, and for the moderation
refusals this path exists to honour, retrying would be an attempt to wear
the server down.

### Consequences

- A sanctioned account cannot send a direct message by any client path.
  Enforcement is uniform: one writer, all checks.
- Sending is no longer synchronous with UI acknowledgement. Chat uses
  `queueTextMessage`, which returns after local enqueue and drains in the
  background; the older `sendTextMessage` API deliberately still awaits the
  first attempt for callers/tests that need the server outcome. The chat consumes
  `MessageService.outbox.changes` plus its accepted hand-off stream and renders
  Pending / Retrying / Failed, preserving a terminal message until the person
  retries or removes it. Rapid sends are drained FIFO inside each conversation;
  a backed-off message blocks overtaking in its chat but not an unrelated chat.
  A rejected local enqueue restores (and defensively merges) the draft instead
  of losing it. A server-history error remains visible beside local bubbles,
  and closing Chat cancels the one shared Firestore source subscription.
- `canDirectMessage` and `canonicalFollowingEdge` in `firestore.rules` are
  no longer referenced by any rule. They are kept, annotated as such, with a
  pointer to `functions/messaging/direct_integrity.js` where privacy is
  actually enforced — a reader must not mistake them for live enforcement.
  `conversationBlocked` is likewise now unused by the create path.
- The legacy `notificationService:` injection no longer produces a
  notification on send. It never should have: the
  `conversations/{id}/messages/{id}` trigger in
  `functions/notifications/activity.js` derives the notification from the
  committed message and sets `bellSuppressed` from the recipient's own
  friends document. `notification_routing_test.dart` now drives that path
  the way the server does.
- `connectivity_plus` becomes a direct dependency. It was already resolved
  transitively and pinned in `dependency_overrides`, so this names what the
  code imports and changes no resolution.
- Deploying the rules and the app in either order is safe in one direction
  only: **rules first strands old installs' fallback sends** (they will see
  `permission-denied` with no queue to catch them), while **app first** is
  clean — the new client stops writing directly before the rule forbids it.
  Ship the app first, or accept that installs older than this release lose
  the fallback without the outbox that replaces it.
## ADR-106: firestore.indexes.json mirrors the deployed index state exactly — a console-created exemption is backported to the repo the day it is found

*(Renumbered 096 → 106 on merge, 2026-08-22; `main` independently used 096
while this branch sat unmerged. The index change this ADR was written to
carry had ALREADY reached `main` by another route, and re-applying it here
produced a DUPLICATE `clubs.clubId` entry in `fieldOverrides` — caught and
dropped during the merge, which is the policy below working as intended,
against the very commit that states it. The decision is kept; the redundant
index edit is not.)*


**Context.** `adminDeleteClub` sweeps the `users/{uid}/clubs` projections
with `db.collectionGroup("clubs").where("clubId", "==", clubId)`
(`functions/admin/clubs.js:1005`) — the only `collectionGroup("clubs")`
query in the codebase. Firestore refuses a collection-group query unless a
COLLECTION_GROUP-scope single-field exemption exists for that field, and
the emulator does not enforce this (ADR-007), so the suite proves nothing
about it. A background review flagged that `firestore.indexes.json` has
overrides for `rooms.roomId`, `participants.userId`, `roomMembers.userId`
and `invites.inviteeId` — but none for `clubs.clubId`. Checking production
(`firebase firestore:indexes --project yovoice-ec54a`, 2026-08-20) showed
the OPPOSITE failure mode: the live project already has the `clubs.clubId`
exemption (COLLECTION ASC, COLLECTION DESC, COLLECTION_GROUP ASC) —
evidently created in the console and never backported — so club deletion
works today, but the checked-in file had drifted BEHIND production.

**Decision.** The exemption is backported to `firestore.indexes.json`
verbatim, and the standing rule is: the repo file mirrors the deployed
index state exactly. Anything created in the console gets backported the
day it is discovered, because `firebase deploy --only firestore:indexes`
treats the file as the source of truth and offers to DELETE live indexes
and exemptions the file does not list (`--force` deletes them without
asking).

**Reasoning.** Drift in this direction is a delayed-action break: nothing
is wrong until the next index deploy, at which point a working production
query loses its index and `adminDeleteClub` dies at the projection-sweep
`.get()` — after `deletionInProgress: true` is already set, leaving the
club stuck in a retryable state no retry can complete. The full live
config was diffed against the repo file (composite indexes and overrides,
modulo the implicit `__name__` suffix the CLI export appends): this
exemption was the only difference, and after the backport the two match
exactly.

**Consequences.** No deploy is needed — production already has the
exemption; the change only removes the trap from the next index deploy.
Index deploys remain a deliberate manual step (`docs/DEPLOYMENT.md`).
The emulator cannot catch a missing single-field exemption any more than
a missing composite index, so "the suite is green" remains non-evidence
for any `collectionGroup()` query — same family as ADR-007 and ADR-082.

## ADR-107: The desktop rail owns its scroll position and sizes its decoration from the RAIL, not the window

**Context.** The rail was reported as "moving with the page". It was not, and
proving that mattered more than patching it. The rail is a `Row` child inside
an `Expanded` inside the shell's `Column` (`main_shell.dart`), so nothing
above it can translate it, and the browser document cannot scroll: read live
in a running build, `document.scrollingElement.scrollHeight == clientHeight`
and `body` computes to `position: fixed; overflow: hidden`, because
`flutter_bootstrap.js` initializes with no `hostElement`.

What moved was the nav column's own `SingleChildScrollView`. The rail's fixed
chrome plus six destinations, two Create buttons and More demand more height
than the rail gets once the window is short or `RoomMiniBar` is mounted.
Measured on the real widget: `maxScrollExtent` is 0 at 1440×768, **40** at
720, **82** at 620. Past that threshold a wheel gesture with the pointer over
the rail scrolls it, and it stays scrolled — which is what clipped the Home
tile under the wordmark in the original report.

**Two plausible causes were tested and rejected**, and they are recorded
because both are folklore that sounds right:

1. **A shared `PrimaryScrollController` does not couple two scrollables.**
   Driving one and measuring the other gives a delta of 0.0 — each
   `Scrollable` keeps its own `ScrollPosition`. What it *does* do is put two
   positions on one controller, which `Scrollbar` asserts against and
   `controller.offset` throws on. That is a real defect
   ([`desktop_home.dart`](../lib/features/home/presentation/widgets/desktop/desktop_home.dart)
   already hit it once) but it is not this one, and it is only reachable at
   all on a mobile-platform target at ≥1100 px — an Android tablet in
   landscape — because `shouldInherit` gates on
   `automaticallyInheritForPlatforms`, which defaults to the mobile set.
2. **macOS `BouncingScrollPhysics` does not rubber-band at zero extent.** A
   held pointer drag and a trackpad pan-zoom both left `pixels` at 0.0. No
   physics override is warranted, so none was added.

**Decision.** Three parts.

1. The rail is a `StatefulWidget` owning a `ScrollController`, and its nav
   column declares `controller` + `primary: false`. The Home feed and the
   344 px right rail declare `primary: false` too — closing the latent
   two-positions-on-one-controller collision on principle, not as the cause.
2. The map tier reads the **rail's** height from a `LayoutBuilder` in the
   rail itself. `MediaQuery.sizeOf(context).height` is the wrong measurement:
   `RoomMiniBar` (~118 px with a live room) and the verification banner
   (~38 px) both shrink the rail without changing the window, which is
   exactly the state the old `>= 700` window gate got wrong. A `LayoutBuilder`
   inside the card cannot do this — as a non-flex `Column` child its own
   vertical constraint is `Infinity`, confirmed by probe — so the rail
   measures once and passes `railHeight` down.
3. `SidebarClock` becomes `TimezoneWorldMapCard`: the same painter, the same
   minute-boundary timer, plus card chrome lifted verbatim from the
   `_ProfileCard` beneath it, a UTC-offset pill, an IANA city/region line and
   a day/night tint. It **replaces** the clock rather than joining it — there
   is one local time in the rail, not two.

**Reasoning.** Fixing the symptom (`primary: false` alone) would have left the
rail still demanding 758 px it does not always have. Fixing only the height
would have left the controller collision for the next Android-tablet user.
The card is an extension rather than a new build because the rail already
shipped a procedural dotted world map with a UTC-offset glow dot; adding a
second one was the obvious wrong move.

Timezone resolution is **detection-only**, and the privacy posture is
structural rather than declared: `TimezoneReading` has no latitude, longitude,
city, country or IP field, because none is collected. `UserProfile` has no
timezone field, and its `country` is free text typed into a bare
`TextEditingController`, so nothing stored could have been used. The chain is
injected label → browser IANA → `DateTime.timeZoneName` → UTC offset. The web
reader is one isolated conditional-import file following
`audio_capture_platform.dart`, with the parsing kept in plain Dart so the VM
test runner can drive it. **`@JS('Intl.DateTimeFormat')` is load-bearing** —
without it the `external factory` names no global constructor and the reader
silently returns null; that was found by looking at the running app, in a
browser whose console answered `Europe/Amsterdam` perfectly well.

**Consequences.** No Firestore, rules, index or Storage change. No
`web/index.html` change, and that is now evidence-backed rather than assumed.
The rail is a `StatefulWidget`, so anything constructing it in a test keeps
working but `tester.widget<DesktopSidebar>` still resolves. `SidebarClock`
and `SidebarClockState` are renamed; the three call sites and six existing
clock tests moved with them. The card now honours
`MediaQuery.alwaysUse24HourFormatOf` instead of hard-coding 24-hour — the
same fix `message_bubble.dart`, `edit_profile_screen.dart` and
`club_chat_screen.dart` each needed — so tests asserting `18:42` must supply
that `MediaQuery`.

**Not done, and stated rather than hidden.** The brief preferred the centre
and right Home columns to scroll as one surface. They remain two independent
scrollables, which is the approved composition (`useRightRail`, a fixed
344 px rail) and merging them would be the redesign the same brief forbids.
Raise it as its own change if the preference is firm.

## ADR-108: `main` is unprotected again — a solo repository pays the pull-request tax for a review that never happens

**Context.** On 2026-08-23 a `Protect main` ruleset was activated and
[ADR-002](#adr-002-git-workflow-push-straight-to-main-no-prs) was declared
superseded: every change had to go through a focused branch, a pull request,
three required checks and a squash merge. That policy lasted one day and
produced exactly one delivery through it (PR #20).

The reversal is not "protection turned out to be worthless". It is that the
protection was buying a review step **that does not exist here**. The ruleset
required zero approvals, because an author cannot approve their own pull
request and this repository has one author. What remained was ceremony:
branch, push branch, open PR, wait ~8 minutes for `verify_and_build`, squash,
pull, delete branch — for a change one person wrote, verified locally and was
always going to ship.

**Decision.** `main` is unprotected. Commit and push straight to it.

- The ruleset keeps only what protects against **destructive Git**:
  `deletion`, `non_fast_forward` and `required_linear_history`. The
  `pull_request` and `required_status_checks` rules — the two that make a
  direct push impossible — are gone. `bypass_actors` is empty, so nobody,
  administrator included, is exempt.
- `.github/rulesets/main-protection.json` is **kept** and now states exactly
  that policy, so the intent is reviewable in the repo and re-appliable with
  one command.

  > **CORRECTED 2026-08-24.** The first version of this ADR deleted both the
  > live ruleset (id `21232425`) and the versioned file outright, on the
  > reasoning that a "how to restore protection" recipe is what a future
  > agent re-imports while trying to be helpful. That threw out the
  > force-push and deletion guards along with the pull-request requirement,
  > which was more than the decision called for — "no mandatory review" and
  > "no protection from destructive Git" are different things. A replacement
  > ruleset (id `21243097`) with the three rules above was created and the
  > file restored. The re-import concern is handled by wording instead: the
  > file and `CLAUDE.md` both say in the imperative that a `pull_request`
  > rule must not be added back.
- Agents do not open pull requests unless the maintainer asks in that session,
  and do not re-add protection. `CLAUDE.md` says so in the imperative and
  names this ADR.
- **CI is untouched.** `verify_and_build`, `Playwright against release web
  build` and `CodeQL` already declared `push: branches: [main]` alongside
  `pull_request:`, so they keep running automatically on every direct push.
  No workflow file needed editing — verified by reading the `on:` blocks
  rather than assumed.
- Dependabot keeps opening dependency pull requests. That is dependency
  monitoring, not a review gate on the maintainer's own work.

**Reasoning.** The pull-request workflow moved CI from "reports on `main`" to
"blocks a merge". That is a genuine improvement *when a human reviews the
diff*. With no reviewer, the same checks run either way and the only thing the
gate adds is latency between writing a change and having it on `main` — plus a
standing invitation for an agent to spend a turn on branch bookkeeping instead
of the work.

What the trade actually costs is worth stating plainly rather than
minimising: **CI now reports after `main` has already moved.** A broken push
lands on `main` and is discovered minutes later. The mitigation is that the
local gate becomes the real gate — `flutter analyze`, `flutter test` and the
emulator suites must be green *before* the push, not after — and that `main`
is recoverable because force-push is not used and risky work is preceded by a
tag snapshot. For a repository whose production deploys are all manual, a
briefly-red `main` costs a follow-up commit, not an outage.

**Consequences.** ADR-002 is reinstated, not superseded; this entry records
why the one-day detour happened and why it was reversed, so the question is
not reopened by rediscovering the same reasoning. `docs/BRANCH_PROTECTION.md`
now documents what `main` still refuses (deletion, force push, non-linear
history) and what it no longer requires (a pull request), and is kept —
deliberately — because a file that says "there is no PR requirement, do not
add one" is a stronger signal to a future session than a missing file.
`docs/DEVELOPMENT_WORKFLOW.md` and `docs/CONTRIBUTING.md` needed no change:
the first never stopped documenting direct-to-main (the two docs had silently
contradicted each other for a day), and the second describes what would change
if a second contributor joined, which is still true and is still the trigger
for reinstating protection.

**The release boundary is unchanged and is unaffected.** Production Hosting
deploys only on `workflow_dispatch` with `deploy_hosting: true`; rules,
indexes and Functions deploy by hand. Pushing to `main` ships nothing to
users, which is what makes an unprotected default branch an acceptable trade
here and would not make it one in a repository that auto-deploys.

## ADR-109: The desktop rail has no scroll position — Home is a pinned header destination

**Context.** ADR-107 proved that the reported moving sidebar was not coupled
to the page: the rail stayed fixed while its own navigation
`SingleChildScrollView` moved. Giving that scrollable an explicit controller
made the behavior correct and predictable, but did not make it visually
desirable. At short heights a wheel gesture could still leave the menu shifted
by up to 82 px, which made a permanent navigation surface look unstable.

Simply deleting the scroll view was not safe. Moving the 47 px Home row into
the header still left too little height at 620 px once header targets were
corrected from 38 to 44 px. `RoomMiniBar` and the verification banner also sat
outside the shell's desktop `Row`, subtracting roughly 118 and 38 px from the
rail respectively. At 200% text, a fixed replacement column overflowed by 61
px even after the ordinary 620 px layout fit.

**Decision.** The desktop rail is a fixed `Column` with no `Scrollable` and no
`ScrollController`.

1. Home moves from a full-width `_NavTile` to a shared `_HeaderNavButton`
   beside Notifications. Both actions are 44×44, expose a localized Tooltip
   and one explicit Semantics label, report `selected`, and keep the existing
   `DesktopNavItem` callbacks and content slots.
2. Below 700 px of measured rail height, Create Room and Create Voice Moment
   share one 46 px row. The primary room action keeps its label; Voice Moment
   becomes an icon with the same tooltip and semantic label. Navigation rows
   never shrink below 44 px.
3. The desktop shell becomes `Row(rail, Expanded(contentColumn))`. The email
   verification banner and `RoomMiniBar` live inside `contentColumn`, so their
   appearance cannot change the rail's height. `MoreDestinationHost` uses the
   same composition.
4. As soon as text is enlarged, the informational timezone card and decorative
   section labels yield on rails below 900 px, and the rail widens from 264 to
   528 px at 200% so primary labels remain fully visible. No navigation,
   creation, profile or settings action is removed. If the logical viewport is
   below 620 px high, the shell uses its existing mobile navigation instead of
   clipping a desktop rail — important for a wide display at high browser zoom.

**Reasoning.** A permanent navigation surface should have permanent geometry.
Moving Home into the header follows the user's requested information
architecture and saves one full row. The horizontal short-height create tier
recovers the remaining space without hiding functionality. Giving content-only
chrome to the content column removes the largest variable constraint rather
than adding more rail-specific compression rules. The mobile fallback is the
honest responsive answer once 44 px targets and scaled text physically cannot
fit; shrinking targets or clipping focusable controls would fail the product's
own accessibility contract.

**Consequences.** `DesktopSidebar` returns to `StatelessWidget`; tests and
screenshots that asserted internal scrolling are intentionally replaced by a
stronger invariant: there is no descendant `Scrollable`. The timezone map
still follows the rail-height tier from ADR-107, and timezone detection/privacy
are unchanged. The profile card, More anchor, unread streams, routing, backend
and mobile navigation are unchanged. No Firebase, schema, rule, index,
dependency or backend deployment change is involved. Deployed through the
byte-verified Hosting release from `5377aa6` on 2026-08-25.

## ADR-110: People & Moments suggests profiles but does not mutate follows inline

**Context.** ADR-043 combined playable Moments and friends-not-yet-followed in
one desktop rail, giving the latter a compact `Follow` chip. In practice that
chip competed visually with Moment playback and duplicated a relationship
action that already has a clearer home on the person's profile. Removing only
the chip initially left the avatar as the sole target while the visible name
and identity badge were dead pixels.

**Decision.** The real friends-not-yet-followed pool stays after the divider,
and `FollowService.watchFollowing` remains a read-only filter so an existing
follow is never suggested again. Each suggestion is one full-tile
`AccessibleTapRegion`, named `Open profile for <display name>`, with a 44 px
minimum target, keyboard activation and a visible focus ring. It opens the
existing profile preview. People & Moments contains no `Follow` button and no
follow mutation; relationship changes remain on profile and creator surfaces.

**Reasoning.** The rail's primary job is fast listening and lightweight
discovery. A profile shortcut preserves the honest, server-backed discovery
value without asking for a relationship change in a cramped mixed-purpose
strip. Making the whole visible tile interactive also aligns it with the
Moment tiles and avoids repeating the dead-label defect already fixed for the
signed-in user's Moment.

**Consequences.** Dedicated Follow controls, their service contract and their
double-submit protection are unchanged. Only the desktop People & Moments
mutation path and its test helper are removed. Widget coverage asserts no
inline `Follow`, continued filtering, a named semantic button, full-tile name
activation and Enter/Space activation. No backend, rules, schema or index
change is involved. Deployed through the byte-verified Hosting release from
`5377aa6` on 2026-08-25.

## ADR-111: Desktop recent chats use current profile artwork as a bounded full-bleed backdrop

**Context.** The desktop `Your recent chats` cards were 148 px tall but placed
only a 40 px avatar in the upper-left and two short text rows at the bottom.
Most of each surface was empty, the avatar felt detached from the card, and
the result did not share the full-bleed visual language of the room banners.
The same `RecentChats` widget also serves mobile, where the smaller avatar card
remains appropriate and must not drift as a side effect of a desktop request.

**Decision.** `RecentChats` gains an explicit presentation style. Mobile keeps
the existing standard style and geometry. `DesktopHome` selects a 116 px
`desktopBackdrop` style. The initial deployed version used the denormalized
conversation photo, enlarged it 1.14× and blurred it with `ImageFiltered`.

**Corrective amendment, 2026-08-27 (source only).** Desktop Home now resolves
each of the at-most-three visible partners through the server-owned
`publicProfiles` projection. The conversation photo remains an immediate
loading/error fallback, while an emitted empty profile value truthfully means
the avatar was removed. A real image fills the card sharply with
`BoxFit.cover`, a slight upward face bias and medium filtering; a lower
vertical scrim owns text contrast without hiding the upper artwork. Missing or
broken photos show a deterministic dark brand surface, hashed accent and
visible monogram. The generic chat glyph is removed because the section and
whole-card action already communicate the destination; unread count remains at
the upper-right, with name/preview at the bottom. The whole surface remains one
`AccessibleTapRegion` named `Open chat with <display name>`.

**Reasoning.** The participant photo provides identity without consuming a
separate layout slot, while the shorter card removes dead space. This mirrors
the room board's full-bleed image-plus-scrim hierarchy without copying its
scale. Identity must remain recognizable: heavy blur plus an almost-opaque
scrim reduced a square portrait to an anonymous color band. The public profile
projection is already the authorized identity source used by profile surfaces,
whereas the conversation copy can lag fan-out or predate it. A maximum of three
mounted point listeners is a bounded cost and repairs existing conversations
without a production backfill. The scrim, not blur, owns text contrast over
arbitrary portraits.

**Consequences.** Conversation ordering, the three-item cap, unread data,
preview copy, callbacks, backend and mobile layout are unchanged. The desktop
surface adds at most three active `publicProfiles/{uid}` point listeners; each
is cancelled with its card, and a read failure degrades to the conversation
copy rather than breaking Home. Tests pin live-photo replacement, the sharp
full-card treatment, 116/212 px heights, semantic action and tap callback while
the existing multi-width suite pins standard avatar cards at 148 px. Missing
images remain intentional rather than showing a broken glyph. No schema,
rules, indexes or Functions change is involved. The original blurred
presentation shipped in the byte-verified Hosting release from `5377aa6` on
2026-08-25; the 2026-08-27 correction deployed to web from `65c1c5f`, while a
new signed native store build remains pending.

## ADR-112: Find Creators presents `official` as a verified Creator, not a separate account type

**Context.** The creator directory exposed the storage value `official` as a
third public category beside All and Creators. That mixed two concepts: what
the account does (Creator) and whether YO Voice has verified it. It also made a
verified creator appear not to be a Creator. The existing value cannot simply
be renamed in storage: `official` is server-owned, is accepted by the deployed
callable and indexes, and is the only current signal that distinguishes these
profiles from ordinary Creator accounts. Firebase email verification is a
different anti-abuse fact about the signed-in searcher and is not a public
endorsement of a search result.

**Decision.** Find Creators keeps `official` as the wire value and maps it only
at the presentation boundary. Every directory result is labelled `Creator`.
An `official` result additionally receives a blue verified-check badge with the
explicit tooltip and semantic label `Verified by YO Voice`. The filters become
`All creators` (`creator + official`) and `Verified` (`official` only); the
client never sends `verified` to the backend. Intro, fallback and empty-state
copy no longer expose `Official`. The verified badge is independent from
Premium identity and the staff `OfficialRoleBadge` system.

**Reasoning.** Verification is a property of a Creator, not a competing account
type. Two filters express that subset relationship without the previous
redundant `All / Creators / Official` taxonomy. Keeping the mapping at the UI
boundary preserves the server authority, current queries, security rules and
existing data while making the visible model accurate.

**Consequences.** No Firestore document, rule, index, Function or entitlement
changes. Search still sends `official`, and the dedicated result model still
decodes it for backward compatibility. Filter targets are at least 44 px, the
two badges wrap at narrow widths, enlarged text stacks the card actions, and
tests cover 320–2560 px plus 200% text. This ADR is intentionally scoped to
Find Creators; Profile Preview, profile headers, Settings and Creator Studio
still use their existing account-type vocabulary and should be aligned in a
separate audited identity-copy pass rather than through an unreviewed global
replacement. Deployed through the byte-verified Hosting release from
`5377aa6` on 2026-08-25.

## ADR-113: Modal sheets own one chrome contract instead of inheriting a global drag handle

**Context.** `AppTheme.bottomSheetTheme.showDragHandle` was enabled globally,
so every `showModalBottomSheet` route received Material's automatic handle.
Many YO Voice sheets also rendered a custom 42–44 px bar inside their visible
surface. The duplication was especially misleading on transparent routes that
wrapped a `DraggableScrollableSheet`: the automatic handle was laid out at the
top of the route-sized transparent layer while the custom handle stayed on the
panel, visually suggesting two sheets. Dismissal still existed through the
scrim, Back/Escape and drag defaults, but none of those routes provided a
consistent, discoverable close action.

**Decision.** The theme no longer draws a handle implicitly, and every
production `showModalBottomSheet` call explicitly sets `showDragHandle: false`.
Visible sheet surfaces use `YoModalSheetChrome`:

1. Below the existing 1100 px desktop breakpoint, the chrome renders one
   centered 44×4 cue attached to the sheet and one named Close action with a
   target of at least 44×44.
2. At 1100 px and above, the drag cue is omitted because pointer-first desktop
   does not present dragging as the primary interaction; the same Close action
   remains.
3. Close uses the sheet navigator by default and can be overridden for routes
   with specialised teardown. The component exposes one explicit semantic
   button, tooltip and keyboard target; the decorative cue is excluded from
   semantics and ignores pointer events so vertical gestures reach the route.
   Every caller supplies its actual surface color, from which the chrome
   derives a WCAG-compliant light or dark foreground independently of the
   ambient app theme.
4. New Message uses `DraggableScrollableSheet(expand: false)`, keeping its
   visible Material as the sheet boundary instead of expanding a transparent
   child across the route. Its content list still owns the supplied scroll
   controller. Profile Preview gains bounded scrolling and stacks actions at
   narrow widths or enlarged text.

**Reasoning.** A drag cue describes a gesture; it is not a reliable close
control. Separating the cue from an explicit Close action makes the interaction
discoverable without removing native scrim, swipe, Back or Escape dismissal.
Making ownership explicit at both theme and route levels prevents a future
Material/theme change from silently reintroducing duplicate chrome. One shared
component also keeps breakpoint, target size, contrast and semantics aligned
across otherwise unrelated features.

**Consequences.** All 26 current production modal routes adopt the same chrome
contract. Dialogs and non-modal in-page panels are unchanged. Route-level tests
exercise the real New Message and Profile Preview launchers at 320, 390, 430,
768, 1100, 1440 and 2560 logical pixels with 200% text, plus Close, Escape,
scrim, swipe, scrolling and focus restoration. Contrast tests cover dark,
light and fixed-dark sheet surfaces. Production-theme visual frames cover
phone, tablet and desktop.
No Firebase data, rules, indexes, Functions, schema or dependency changes are
involved. Deployed through the byte-verified Hosting release from `5377aa6` on
2026-08-25.

**Corrective amendment (2026-08-27, deployed to web from `65c1c5f`; native
store build pending).** An action
that leaves Profile Preview must not navigate through the preview's `BuildContext`
after calling `pop`. The modal returns a typed destination; the launcher keeps
its stable `NavigatorState`, awaits full dismissal, then pushes Chat or the full
profile. Failures that keep the preview open render inside its surface as a
friendly live region, because a root snackbar sits underneath stacked modal
barriers. The resolved Auth and MessageService travel together into Chat;
short-lived injected services remain owned by the launcher and are disposed
after the route returns. Opening also has a concise live status while the
action is disabled. A route-level regression reproduces Profile Preview above
an existing modal, then verifies one request/Chat route, optimistic identity
reconciliation and correct Back behavior.

## ADR-114: Social graph callables own the notification lifecycle end to end

**Context.** ADR-041 correctly removed social-notification writes from the
client, but derived them through three asynchronous Firestore triggers while
the newer social callables also wrote the same deterministic notification
documents in their graph transactions. Two authorities could overwrite one
another. A delayed trigger could restore `isRead: false` after a request was
accepted, declined or cancelled; cancel did not retire its alert at all; and
reusing a deterministic id meant a later legitimate request, acceptance or
follow was an update, so the create-only push trigger did not run again.

**Decision.** `sendFriendRequest`, `respondToFriendRequest`,
`cancelFriendRequest`, `removeFriend`, `setFollow` and `setUserBlock` are the
single authority for both graph state and its in-app notification row. The
legacy `onFriendRequestCreated`, `onFriendRequestResolved` and
`onFollowerCreated` exports are retired. Actionable request alerts are deleted
atomically on accept, decline and cancel, including idempotent repair replays.
Every new request, acceptance and follow receives a generation-specific
notification id; request, friendship and follow mirrors store the ids needed
for atomic retirement. Unfollow and block retire the active follow activity
row with the edge, while the next follow gets a different generation. The
first post-upgrade lifecycle also deletes the retired
pair-lifetime id, so an existing production row cannot turn the next event into
an update without `onCreate`. The generic `onNotificationCreated` push trigger
re-reads the row, requires the same Firestore `createTime`, rejects the retired
id shape whenever its live source is generation-bound, and revalidates the
live graph source immediately before FCM. During the ordered cutover, a
genuine old source with no pointer may still emit its one legacy alert; once a
pointer exists only the exact generation is accepted. Invalid compatibility
rows are removed. This materially narrows delayed-event races;
it does not pretend to eliminate the final source-change-vs-network-send
TOCTOU inherent in best-effort FCM.
After the legacy trigger exports are verified absent, a bounded, resumable,
aggregate-only Admin sweep deletes any retired deterministic ids whose
best-effort event-time cleanup hit a transient error. It calls the same source
predicate as push, preserving genuine pointer-less legacy state and deleting
only source-less or upgraded-source duplicates. Dry-run, apply and a zero-plan
verification are part of rollout, not optional hygiene.

**Reasoning.** The graph transaction is the only point that can atomically
decide whether a relationship event exists, allocate a fresh notification
generation and retire the previous actionable generation. Moving that work to
the callables removes trigger-order races, while exact source pointers let the
best-effort push layer reject delayed events without trusting client payloads.
Backward-compatible legacy predicates and an ordered rollout are necessary
because Cloud Functions updates are not atomic and the deployed two-field
follow edge must remain readable throughout the cutover.

On Flutter, a friend-request tap opens the actionable Friends → Requests queue
rather than a profile that assumes friendship. Accepted/follow activity opens
the relationship-aware profile preview. Mobile Home receives the same unread
count as desktop. Friends and blocked-user failures render safe error states,
missing/private blocked profiles retain a UID-backed Unblock row, the social
graph callables use `europe-west1`, and Add Friend controls meet the 44 px
minimum. Sign-out rotates the platform FCM token independently of the
owner-scoped Firestore delete. The process-local guard is set before the
fallible durable-marker write; persistence, the owner-row delete, registration
drain and platform invalidation are all started independently and awaited only
within bounded windows; owner-row deletion repeats after a successful drain so
its final operation wins a delayed registration race. When the marker write succeeds it survives process
death and blocks reuse by the next account until deletion or a platform token
refresh succeeds. Cold starts and direct account rebindings force rotation too,
and an identity epoch plus serialized write queue prevents a refresh from
clearing or re-registering during sign-out. Failed social-profile provisioning
also enters this cleanup path before its Auth rollback. If both local
persistence and platform invalidation fail, the running process remains closed;
after a full restart the signed-out screen cannot prove ownership until the
next identity binding forces another invalidation attempt. That narrow residual
interval is explicit.

**Consequences.** No index change. Firestore Rules widen the exact follow-edge
read schema from `{uid, followedAt}` to `{uid, followedAt, notificationId?}`;
the pointer is bounded, remains server-write-only and the legacy two-field row
stays readable. Request mirrors gain an additive server-owned
`notificationId`; friendship mirrors gain the acceptance id and recipient
needed for cleanup. The source removes three deployed Functions, so release is
deliberate: deploy the backward-compatible Rules widening first; deploy the
compatibility-aware push trigger and four widened DM validators; then deploy
cleanup consumers before social producers. Verify the two-account journey,
explicitly delete the three retired trigger Functions, run the source-aware
sweep to completion, and repeat the final smoke. Hosting follows only after
backend readiness. The exact staged commands and rollback boundaries live in
DEPLOYMENT.md.
Emulator tests cover cancel/decline/accept/replay/unfriend notification
lifecycle, fresh re-requests/refollows, region/routing contracts, blocked-row
degradation, mobile badge semantics and 200% request actions. System FCM still
requires a two-device smoke because delivery beyond the durable notification
row is best effort. **DEPLOYED 2026-08-25.** The ordered Rules/Functions
cutover, trigger deletion, backup and zero-plan sweep completed before Hosting.
The release owner explicitly proceeded without the physical two-device FCM
smoke, so OS-level delivery on two real devices remains unverified.

## ADR-115: Voice Moment review stays local; availability is user-sized; the root lifecycle is server-authoritative

**Status**: **DEPLOYED 2026-08-27** from `65c1c5f`; physical mobile validation
remains outstanding
**Date**: 2026-08-27

### Context

ADR-103 shipped five fixed availability choices and no way to listen to a
finished recording before publishing. The active-Moment cap also scanned only
the newest 100 authored documents, while the Firestore rules still permitted
client root creation, broad author updates and direct deletion. A client could
therefore create an undeclared permanent Moment, bypass publish/media
validation or delete a root without queuing media cleanup.

### Decision

A finished recording remains device-local during review. Native playback uses
the temporary recording file; web playback uses a Blob object URL owned and
revoked by the recording. Play, pause and seek never reserve a draft, upload an
object or call finalize. Publish first stops and disposes playback, then starts
the existing reservation/upload/finalize flow.

Timed availability accepts any whole-hour value from 24 through 720. The UI
also accepts 1–30 whole days and converts them to hours. `permanent` remains the
explicit Until deleted mode; absent and explicit 24 preserve the deployed
request identity, while every non-default duration participates in the
idempotency hash. Caption and availability are locked after the first publish
attempt so a retry cannot change the request behind an existing requestId.
Voice replies receive local preview but no independent availability selector.

The complete published set for an author is the source of truth for the
10-active cap. `momentCapacityLedgers/{uid}` is a server-only revision/mutex,
not a counter: finalize, delete and expiry advance it in their transactions so
competing capacity changes serialize. The exact query requires
`voiceMoments(authorId ASC, isPublished ASC)` and no backfill.

Voice Moment root create, every update and delete are server authority. Like
and comment documents are server-owned too; clients may read engagement only
when they can read the parent. The old direct engagement fallbacks are removed
rather than preserving counter transitions that cannot be proven atomic and
non-forgeable in Rules. Draft/expired/deleting roots and their subcollections
are author-private; Storage creation requires the exact canonical uploading
draft. Voice-reply media creation requires the exact unexpired server
reservation; finalize atomically removes that reservation and creates the
comment. Root and reply objects are immutable to clients at every state;
bounded abandoned-upload workers and the cleanup outbox are the only deletion
authority. Existing mixed-case reply objects retain signed-in read
compatibility only.

Every unfinished finalize attempt consumes its rate budget before any external
Storage metadata or download-URL read, even when the same requestId already has
a matching preflight. Only a completed operation-ledger replay is free and
skips Storage. Timed Moments are removed from already-open feeds, detail,
story, sheet and comment surfaces by a client timer at the exact `expiresAt`;
playback stops as the subtree is removed. Each visible transition produces one
deduplicated accessibility announcement and restores keyboard focus to a
stable surviving item or heading. Story maps the previous position into the
surviving chain by keeping the same link, then the first surviving successor,
then the nearest predecessor; a multi-deadline resume therefore cannot skip a
live link. Waits longer than the browser's signed 32-bit millisecond timer
limit are chunked and rechecked against the clock. Cached hidden tabs neither
announce nor reclaim focus, and a parent rebuild after a deadline preserves
the same single visible transition. The server independently rejects new likes
and text/voice replies at `expiresAt`, without waiting for the scheduled
sweeper to persist the retired state. Permanent Moments arm no timer.

### Reasoning

Preview should let an author judge the audio without changing server state or
creating abandoned uploads. A continuous range expresses the user's intent
without introducing a new schema, while keeping the deployed 24-hour request
identity makes retries and older clients compatible. Exact capacity cannot be
derived safely from a bounded newest-first window, and two finalizations of
different roots do not otherwise conflict; the small per-author revision makes
those transactions contend while leaving the actual published set as the
reconstructible source of truth. Root publication and deletion bind Firestore,
Storage generations, expiry and cleanup side effects that Security Rules cannot
make atomic, so they belong to the existing callables rather than a permissive
client fallback.

### Consequences

Expiry means exact removal from live app surfaces and refusal of new
engagement, not destruction of the document or media. Explicit author deletion
queues Storage cleanup; bounded server workers also remove abandoned uploads.
A Firebase download-token URL
already learned while a Moment was published remains a bearer URL until cleanup
or token revocation, regardless of later Storage-rule denial.

Release order is index to READY and production query proof, then Functions and
callable/concurrency smoke, then Firestore Rules, Storage Rules and their
read-back/smoke, and only then the client. That order completed on 2026-08-27:
all backend stages and controlled production smokes passed before Hosting run
`33043536603` deployed the verified `65c1c5f` artifact. Existing ADR-103
remains the historical pre-rollout contract; this ADR now supersedes its
fixed-selector, bounded-cap and client-root-authority details in production.

## ADR-116: Product sound is a material feedback system, not a set of jingles

**Status**: **DEPLOYED 2026-08-27** — Hosting and FCM v3 live; Android build 5
available to internal testers; signed iOS build 5 artifact retained
**Date**: 2026-08-27

### Context

ADR-076 introduced eight bounded semantic cues and ADR-099 made them
reproducible, but both generated versions were melodic glass-bell synths: a
pentatonic scale, rising/falling pairs, detune, pitch settle and a classic
two-note notification. The operator rejected that language as retro and
kitschy. The audit also found two generators, a much louder old native push
WAV, two audible foreground owners, an obsolete Android manifest fallback and
an immutable v2 channel that could not receive replacement bytes reliably.

### Decision

The event inventory stays deliberately small: create/join/leave, participant
join/leave, mute/unmute and notification. User recordings, LiveKit speech,
Voice Moments and voice messages are media, not soundtrack assets, and remain
untouched.

The new family is **Velvet Prism**: a 4–10 ms filtered material contact, muted
inharmonic body and quiet air layer. There are no notes, scales, arpeggios,
chorus, detune, pitch glide or generic tap sounds. Beginnings open texture and
width; endings fold them into a mono body. All eight files are deterministic
48 kHz stereo PCM16, 95–360 ms long, mastered in the asset, and end in
exact silence. `UiSound.volume` is therefore 1.0 for every cue.

`tool/generate_ui_sounds.py` is the only authoring source. It renders all eight
Flutter assets under the cache-safe `assets/audio/ui/v3/` path and bit-identical
Android/iOS notification copies, and
`--check` verifies inventory, format, loudness ceiling, DC, stereo correlation,
mono loss, terminal silence and byte reproducibility. The conflicting Dart
generator is removed, and CI runs the same check before analysis or build. The
`v3` asset path is immutable for browser-cache purposes; a future remaster must
bump the pack path rather than silently replacing it.

Playback remains lazy and preference-gated, but commands are serialized through
the actual playback-complete event, so an audible tail is never hard-cut; only
still-queued stale work is dropped by the newest-queued-wins policy. Android marks cues as sonification
and requests no audio focus; iOS is deliberately not reconfigured from this
layer because AVAudioSession is process-global and LiveKit/recording own it.
Room creation consumes the immediately following connected cue, so one action
cannot become two jingles. FCM and the Firestore banner share one foreground
claim: whichever presents first owns the only sound.

Android uses `yovoice_activity_v3` in Flutter, Functions and the manifest
fallback, because installed channel sound is immutable. APNs retains the
stable `yovoice_notification.wav` filename. Platform notification settings,
DND and the system volume remain authoritative.

### Reasoning

Premium sound is restraint, material consistency and reliable behavior, not a
brighter melody. Short aperiodic contacts remain legible on a phone speaker
without sounding like a game reward, while one mono anchor and a low side
level survive headphones and accessibility mono audio. One generator and one
foreground owner turn brand language into an enforceable system rather than a
folder of unrelated WAVs.

### Consequences

The staged cutover completed on 2026-08-27. Hosting serves the verified v3
in-app pack; Android builds 4 and 5 create `yovoice_activity_v3`, build 5 is
available on the internal track, and production `onNotificationCreated` now
targets the v3 activity channel plus the dedicated `yovoice_calls_v1` incoming
call channel. The signed iOS build 5 artifact contains the matching APNs WAV,
but was not uploaded because App Store Connect authorization was unavailable
during that release; build 6 later established the upload path.
Web Hosting receives the in-app pack under the cache-safe `audio/ui/v3/` path;
iOS and Android require clean native builds. Acceptance includes phone
speaker, headphones, silent/DND, active LiveKit, Bluetooth and foreground /
background notification checks. A green waveform test cannot replace the
operator's final listening approval.

## ADR-117: Direct calls are a server-authoritative state machine, not tiny rooms

**Status**: **DEPLOYED 2026-08-27**
**Date**: 2026-08-27

### Context

The phone icon in every direct conversation was deliberately inert because the
product had room audio but no two-party signaling: no ring delivery, answer or
decline authority, busy state, missed-call timeout or guaranteed teardown. A
client shortcut into a Community Room would expose the wrong lifecycle and
leave permissions, simultaneous calls and external LiveKit state racy.

### Decision

`directCalls/{callId}` is a server-owned two-participant state machine. Six
callables own start, answer, decline, cancel, end and token minting. Start and
answer/token issuance revalidate both active accounts, both canonical
friendship guards, both block directions and communication restrictions.
Transactional per-user locks permit one ringing/active call; ringing expires
after 60 seconds.

The callee receives a private inbox mirror and a high-priority call push. Only
an accepted call can mint a five-minute LiveKit token scoped to
`call_<callId>`. Terminal active calls create a retryable control outbox whose
worker deletes the LiveKit room and active-session mirrors. Call documents are
participant-get-only; every client write to calls, signals, locks and control
outbox is denied. A missed notification routes to the DM instead of briefly
opening a terminal call surface.

### Reasoning

Busy exclusion and one canonical transition prevent double answers, stale
tokens and overlapping calls. Rechecking the live social/safety graph at every
authority boundary means an old ringing document never bypasses a new block,
sanction, deleted account or removed friendship. A retryable outbox closes the
Firestore-to-LiveKit side-effect gap without granting clients control-plane
credentials.

### Consequences

Calls currently require confirmed friendship and a foreground-capable app; this
is not yet a CallKit/ConnectionService background telephony integration.
Ringing has a fixed 60-second timeout and active calls an eight-hour safety
ceiling. The release completed in that order: the composite index is READY,
the call Functions are ACTIVE, the released Rules source is byte-identical,
Hosting serves the pinned client bytes, and Android build 5 is available to
the internal tester list. The unauthenticated production callable smoke proves
the deployed start endpoint returns the expected authorization contract; the
first signed-in two-device call remains part of tester acceptance.

## ADR-118: Premium pairs recurring EUR with non-renewing prepaid BLIK

**Status**: Catalog deployed; provider rollout and checkout disabled
**Date**: 2026-08-28

### Context

ADR-067 established the correct security boundary—Stripe owns payment and
cancellation while Firestore owns access—but its commercial catalog no longer
matches the product decision. It modeled two recurring PLN card Prices and had
no truthful path for a member who wants PayPal or wants to pay with BLIK without
authorizing renewal. Extending that catalog by making BLIK recurring would be
misleading: the product being offered is a prepaid term, not a reusable BLIK
mandate.

The replacement also needs a hard environment boundary. YO Voice has one
production Firebase project and no staging Firebase project. Pointing that
project at Stripe test mode would make test objects look like production
billing state to real clients and webhooks.

### Decision

The source catalog has four server-owned offers on one Stripe Premium Product:

| Plan | Method | Price | Entitlement | Renewal |
|---|---|---|---|---|
| Monthly | card or PayPal | EUR 6 | recurring monthly period | automatic until canceled |
| Annual | card or PayPal | EUR 60 | recurring annual period | automatic until canceled |
| Monthly | BLIK | PLN 26 | exactly 30 days prepaid | none |
| Annual | BLIK | PLN 260 | exactly 365 days prepaid | none |

The only client request is `{plan, paymentMethod?}`. `plan` is
`monthly` or `yearly`; omitted `paymentMethod` means `recurring`, while `blik`
selects the prepaid path. Functions map the request to
`STRIPE_MONTHLY_PRICE_ID`, `STRIPE_YEARLY_PRICE_ID`,
`STRIPE_BLIK_MONTHLY_PRICE_ID` or `STRIPE_BLIK_YEARLY_PRICE_ID`. The client
never submits an amount, Price id, Checkout mode, payment-method list, uid or
return URL.

Recurring Checkout uses Stripe subscription mode with the exact
`payment_method_types=[card,paypal]` allowlist; PayPal still appears only when
the live Stripe account/customer is eligible. Its paid Invoice and canonical
Subscription drive `entitlements/{uid}`. The Customer Portal is the management
and cancellation surface; cancellation prevents the next renewal and the
already-paid period remains bounded by `currentPeriodEnd`.

BLIK Checkout uses one-time payment mode and a PLN Price. A signed successful
provider event grants one fixed 30- or 365-day entitlement and writes
`source=stripe_prepaid` with `renewalBehavior=none`. It creates no Subscription,
appears in no subscription-switch Portal flow and never charges again
automatically. At expiry the member must deliberately buy another prepaid term.

Every method uses hosted Checkout. The success redirect is display-only and
cannot grant access. Signed webhooks re-read canonical Stripe state and commit
the private billing binding, entitlement and replay receipt together. Existing
rate limits, Checkout lease/idempotency, canonical Customer binding, late-event
handling and Auth-deletion cancellation remain part of the boundary.

Production `yovoice-ec54a` must fail closed unless
`STRIPE_EXPECTED_MODE=live`, the secret starts with `sk_live_`, all four Prices
are live and the event matches the live webhook secret. `sk_test_`, test Prices,
test events and `STRIPE_EXPECTED_MODE=test` are permitted only with local
emulators or a separately created non-production Firebase project—never in
production.

### Reasoning

Two recurring EUR offers make the comparable subscription prices explicit,
while two PLN BLIK offers reflect how the prepaid product is actually charged
and avoid implying a future debit. Exact 30/365-day wording is more honest than
calling a non-recurring payment a calendar subscription. Keeping one provider
preserves one signed event authority and one canonical customer-to-uid binding;
PayPal is a Stripe Checkout method, not a second entitlement writer.

Separating recurring and prepaid lifecycles in server data prevents UI copy or
a stale redirect from turning BLIK into a subscription. Live-only production
configuration removes the ambiguous state where real Firebase accounts obtain
access from sandbox money.

### Consequences

- ADR-118 supersedes ADR-067's two recurring PLN Prices and corresponding
  rollout/catalog language. ADR-067's server-authoritative ownership,
  signature, idempotency and Portal principles remain valid. The old two-Price
  implementation is not a rollback target.
- Source-ready does not mean purchasable. Checkout remains disabled until the
  live Product/Prices, PayPal/BLIK activation, recurring-only Portal, live
  webhook, reviewed Terms/Privacy and four-path smoke/reconciliation complete
  in the order documented in DEPLOYMENT.md.
- `STRIPE_BILLING_EXPORTS` stays disabled during provider preparation. The
  secret-free catalog was deployed on 2026-08-28 and remains available, but
  the four provider handlers and
  `checkoutAvailable=true` appear only at the explicit live cutover.
- PayPal or BLIK may be absent for an ineligible account/customer even when
  source supports it. The UI must show an honest unavailable state and must not
  fabricate provider availability.
- BLIK access has no cancel-at-period-end action because there is no future
  charge. The account UI must show its exact end date and that renewal requires
  a new purchase.
- Seller/business identity, applicable tax/B2B configuration and customer-facing
  refund/dispute handling are launch decisions outside this ADR. Terms and
  product copy must not invent them; technical financial-event safeguards do
  not become a public refund policy.
- App Store and Google Play purchases remain separate future adapters.
  `verifyPurchase` continues to fail closed until signed store verification is
  implemented.

## ADR-119: Moderator Premium preview is a derived product benefit, not a paid entitlement

**Status**: Implemented; production release pending
**Date**: 2026-08-28

### Context

Moderators and super moderators need to exercise Premium identity, Creator and
Clubs while verifying the member experience. Writing a synthetic subscription
or treating a staff role as billing truth would corrupt renewal, support,
refund and reconciliation state. Treating every staff tier alike would also
couple owner authority to a consumer benefit with no product reason.

### Decision

Only active exact roles `moderator` and `superModerator` derive a
`staffPreview` product overlay. The signed Auth claim and client-immutable
`users/{uid}.role` mirror must match exactly for any acting Rule or callable.
Background cleanup and public projections, which cannot inspect another
account's token, use the server-written mirror only and grant no staff action.

The overlay enables Premium identity, Creator and Clubs with the default
three-Club limit. It is separate from `isPremium`, plan, period, renewal,
provider source and every receipt. It never writes `entitlements/{uid}` and
never grants moderation, ownership or `superAdmin` capability. Paid and preview
sources can coexist. Demotion, ban, disablement or deletion removes the preview;
paid access survives when independently valid. Creator pins/mode are cleaned
on demotion only when no paid Creator authority remains.

Public badge synchronization and backfill additionally require a present,
enabled Firebase Auth identity. A stale private role document cannot republish
an Auth-deleted or disabled account. In the private owner directory,
disablement removes only the derived staff-preview source; independent paid or
admin-grant billing/support truth remains distinguishable.

### Reasoning

One shared resolver in Functions, matching Rules helpers and a separate
Flutter model flag keep effective product access consistent without making a
badge or role a payment authority. Exact claim–mirror equality closes both
self-write and stale-token paths. Keeping raw billing fields unchanged means
support and reconciliation can still answer whether access was purchased.

### Consequences

- `superAdmin`, support, auditor and guide roles receive no automatic Premium
  benefit.
- Existing moderator projections require a bounded badges/profile/directory
  backfill after deployment because deploying new trigger code does not replay
  old user writes.
- A newly promoted moderator may see client presentation from the server
  mirror before their refreshed token can perform an acting operation; that
  operation fails closed until the claim matches.
- Tests must cover claim/mirror mismatch, inactive states, paid-plus-preview,
  expiry/refund, demotion cleanup and billing-field immutability.

## ADR-120: Podcast Studio uses the participant roster as its production state

**Status**: Deployed to web and mobile beta
**Date**: 2026-08-28

### Context

Podcast Room had the correct listen-only audio authority but presented almost
the same composition as Community Room. Its stored episode topic, show format,
guest guidelines and `handRaisingEnabled` decision were not represented in the
live production surface. “Speaking” counted everyone assigned to the stage,
not LiveKit's current speakers. Hosts could answer a request only through a
generic participant sheet. Promotion also disconnected and rejoined as soon
as Firestore delivered the new role, racing the callable's already-supported
in-place LiveKit permission update.

Two raise-hand APIs made that inconsistency easier: the reachable room screen
used `participants/{uid}.isHandRaised`, while an older service wrote a separate
`handRequests/{uid}` collection. Fixing one could leave the other unchanged.
Removing the legacy Rules path immediately, however, would break an installed
older client without a minimum-version migration.

### Decision

Podcast Room becomes a dedicated Podcast Studio composition. The episode topic
is the headline and the persistent show name is context. The hero exposes show
format, live status, host identity, stage size, real LiveKit speaking count and
audience size. Hosts get a producer desk and a request queue beside live chat;
listeners see whether they are listening, waiting for approval or on stage.
Podcast settings own topic, format, guidelines and the request switch while
retaining the shared advanced room controls.

The participant roster is the current client's single production state for
requests. `RoomService.setHandRaised`, producer accept/decline, the Participants
sheet and deprecated `RoomExperienceService` adapters all use
`participants/{uid}.isHandRaised`. Rules allow a listener to raise only in an
active live Podcast whose host has requests enabled; lowering remains allowed
after the host closes the queue. Community speakers cannot forge this state.
The bounded legacy `handRequests` Rules contract remains temporarily for
already-installed clients, but current Flutter source neither writes nor
watches it.

The moderation callable's direct LiveKit permission update is the normal
promotion path. The client waits 900 ms after a role-row mismatch and reconnects
only if transport permission is still stale. Responsive Podcast Studio scrolls
on compact or short canvases; only sufficiently tall canvases give the stage
the remaining fixed-column height.

### Reasoning

A podcast is organized around an episode and a producer-controlled guest flow,
not a generic room roster. Putting those decisions in the first viewport makes
the product legible to both host and audience. One current request field keeps
the queue, listener control and moderation action causally aligned. Keeping a
narrow legacy Rules allowance avoids turning schema consolidation into a
silent outage for an older binary; marking that allowance explicitly prevents
new code from treating it as the canonical path.

Waiting for the server-side permission update removes the ordinary promotion
audio gap. A delayed reconnect still gives a deterministic recovery path when
the LiveKit event is lost. The higher fill threshold follows measured widget
geometry: visual inspection at 1440×900 found stage cards extending into the
audience strip, while a scrollable studio remained correct.

### Consequences

- An older installed client can still create a legacy `handRequests` row, but
  current Podcast Studio does not surface that retired queue. Fully deleting
  the legacy contract requires an enforced minimum app version or a server
  bridge/migration.
- `VoiceRoom` now carries the typed podcast production fields through live
  document updates, so settings changes replace stale launch-time copy without
  reopening the room.
- Hosts can close new requests without trapping a listener's existing raised
  state; that listener may always lower it.
- Real multi-device LiveKit promotion and audio-quality checks remain manual;
  widget tests prove the state composition and the emulator proves the write
  boundary, not the external media transport.

## ADR-121: Direct chat correctness is replay-safe and foreground alerts have one owner

**Status**: Implemented in source; production release pending
**Date**: 2026-08-28

### Context

The direct-chat surface mixed four independent asynchronous systems: a local
text outbox, Firestore snapshots, server-authoritative read/message callables
and FCM. Background read bookkeeping displayed an unactionable snackbar and
ran after outgoing messages. The client ignored the read callable's
`completed=false` page boundary. At-least-once Firestore trigger delivery could
rewrite an existing notification to unread, and a duplicate notification
CloudEvent could send FCM twice. MainShell and foreground FCM also had no
knowledge that the target conversation was already open.

Direct-call start had the same ambiguous-response gap: the server could commit
a ringing call and lose the HTTPS response, after which a retry hit the active
call lock and the caller never learned the call id. Separately, Firestore Rules
described conversation roots as server-owned while still allowing a
participant to update every field except `participantIds`.

### Decision

Text submission remains local-first: the outbox emits its optimistic entry
before preference persistence completes, while persistence still finishes
before enqueue returns. Delivery remains sequential within one conversation;
a retry/backoff in that conversation does not block a due entry in another.

Read receipts run only for incoming messages not already read by the current
user. One screen owns a single-flight drain that coalesces snapshot bursts.
`markConversationRead` consumes the callable response and continues with a new
request id while `completed=false`, requiring a strictly increasing cursor and
stopping at a bounded 100 pages. Receipt failures remain diagnostic and
retryable but never interrupt the conversation UI.

Every server-derived activity event uses the existing atomic event ledger and
notification write. Trigger replay therefore cannot overwrite, re-unread or
resurrect the deterministic inbox row. The source message, room or social edge
is revalidated in the same transaction as a terminal `dispatching` claim just
before FCM. A crash or lost FCM acknowledgement after that claim is never
re-sent; platform collapse identifiers provide a second generation-aware
defence. Confirmed success advances to `sent`, while an ambiguous result stays
honestly `dispatching`. Written and skipped outcomes share the same canonical
30-day ledger, whose `expiresAt` field is managed by a versioned Firestore TTL
policy.

An in-process reference-counted active-conversation registry is consulted only
by foreground presentation. It suppresses a direct-message/reply native alert,
app banner and MainShell overlay when their target conversation is open.
Background and terminated delivery do not consult it. Foreground direct-call
sound is arbitrated between the Firestore coordinator and FCM so exactly one
path owns presentation and the other can take over only after a proven
presentation failure. Completed claims are retained briefly for late duplicate
suppression, active claims time out, and the registry is capped at 64 entries.

One call tap creates one high-entropy request id and persists it before the
first network write, scoped to the signed-in account, peer and conversation.
`startDirectCall` derives a deterministic call document from the caller and
operation identity, stores the input hash, and returns the existing canonical
result for an exact replay, including after a process restart and lost HTTPS
response. Terminal refusal or a canonical response clears the matching local
record; stale records expire after five minutes. Reusing the id with different
input fails. Older clients without `requestId` retain the previous random-id
behavior during rollout.

Photo and voice attachments use an account-scoped durable outbox: the manifest
and private payload survive restart, reserve/upload/finalize identifiers replay
stably, and an authoritatively rejected or expired 15-minute reservation
rotates both request ids plus the message/storage path without moving the
payload. Device clock skew cannot trap the queue. Failed cards expose Retry and
Discard; active uploads expose neither, so a discard/finalize privacy race is
impossible. The outbox is bounded to 12 entries / 64 MiB and failed payloads
remain explicit until the sender chooses.

All writes to `conversations/{id}` roots are Admin-only. Text, media, typing,
read, mute and archive mutations go through their owning callables; clients may
read their conversations but cannot forge another participant's state.

### Consequences

- One millisecond end-to-end delivery is not an accepted SLO. A 60 Hz client
  cannot paint faster than a 16.7 ms frame and a regional HTTPS/Firestore path
  necessarily takes network round trips. Local optimistic latency and remote
  delivery latency are measured separately.
- `bellSuppressed` continues to mean “hide this carrier from the bell feed”,
  not “disable background push”. Active-chat suppression is foreground-only.
- The terminal FCM dispatch claim is at-most-once, not exactly-once. A crash
  after the claim may lose the best-effort push while retaining the
  authoritative inbox event; it cannot create a duplicate retry.
- Installed clients that depended on direct root updates lose those fallback
  writes when Rules deploy. The compatible callables must be active first.
- Durable photo/voice recovery, retry/discard and expiry rotation are shipped.
  Byte-level upload progress remains future work.
- Physical iOS/Android two-device tests are mandatory release evidence for
  background/terminated push, large media, LiveKit audio and mute latency.

## ADR-122: Room covers publish one host-confirmed 21:9 artifact

**Status**: Web deployed and Chrome-verified; native build pending
**Date**: 2026-08-29

### Context

Room creation and Room Settings let a host pick or replace cover art, but both
flows immediately accepted the picker result. Every consumer then applied its
own `BoxFit.cover`, leaving the host unable to decide which part of a portrait
or oversized image survived the wide room card. Reusing profile-banner crop
metadata would have introduced a second rendering contract into existing room
documents, while uploading the original would retain unnecessary bytes and
make every consumer repeat transform logic.

Replacement also spans Storage and Firestore without a cross-service
transaction. A Firestore write can commit while its acknowledgement is lost;
blindly deleting the just-uploaded object in that case would publish a broken
pointer. Conversely, tying superseded-object cleanup to a mounted Settings
widget would leak the old object whenever the host left during upload.

### Decision

Create Community/Podcast Room and Room Settings share `RoomCoverEditor`: pick a
bounded JPG/PNG/WebP source, decode locally, let the host zoom and reposition
inside a fixed 21:9 frame, then return one 1600×686 JPEG. A centered 9:21 guide
marks the narrow area most likely to survive taller compact cards. The room schema
continues to store only `imageUrl`; the original and crop metadata never leave
the device. Cancelling the picker or editor changes nothing, and replacing a
pending create composition uploads only the latest confirmed bytes.

The Storage service accepts only the final bounded JPEG contract and deletes
only an object whose resolved Firebase bucket and exact
`room_images/{roomId}/{file}` path match. After an image URL write error, the
client performs a server-only Firestore read: a matching pointer is success, a
confirmed mismatch permits new-object cleanup, and an unavailable/cache/
pending read preserves the object and original error. Once a pointer commits,
old-object cleanup runs independently of widget lifetime. Settings serializes
cover upload against Save, status and deletion. Closed/archived rooms explain
the active-room Storage rule and offer a nearby confirmed Reopen action;
moderation-suspended rooms expose no host status command. System Back/Escape
cannot pop the crop route while JPEG encoding owns the decoded image, and both
generated images and native codecs are disposed deterministically.

Because room documents feed public card queries, Firestore Rules accept a
cover pointer only when it is null or a bounded string targeting this exact
room under YO Voice's current/legacy Firebase Storage bucket. A Club Lounge may
instead use only the managed avatar URL stored on its live Club root, whose
`loungeRoomId` must name that room; cross-owner and cross-Club substitutions are
denied. The model repeats the managed-path validation defensively so malformed
Admin/legacy data degrades to the gradient without breaking a shared stream or
fetching attacker infrastructure.
The picker checks `XFile.length()` before allocation; the decoder rejects
hostile encoded dimensions and downsamples accepted sources to a 3200 px edge
before materializing a frame.

Corrective amendment (same date): encoded `ImageDescriptor` dimensions cannot
be queried on Flutter Web. Source headers are therefore inspected with the
format-specific package:image decoder only for the pre-allocation limits. JPEG
APP1 orientation is also parsed without materializing a frame, axes 5–8 are
swapped, and the longer displayed edge alone is passed to
`instantiateImageCodec` with upscaling disabled. This deliberately avoids
`instantiateImageCodecWithSize`, whose Web implementation decodes one full
frame before choosing its target. The route launcher, not its lazily mounted
child widget, owns the decoded frame and disposes it only after
`TransitionRoute.completed`. This
covers ordinary Back, the reverse animation and a zero-duration auth-epoch
`pushAndRemoveUntil` without repaint-after-dispose or an unmounted-route leak.

### Reasoning

One canonical artifact preserves every existing consumer and keeps the direct
Firestore schema backward compatible. Local composition gives the host an
honest preview without adding a display-time transform matrix to mobile, web
and desktop. Exact-path cleanup and fail-safe lost-acknowledgement recovery
prefer a recoverable orphan over a broken published URL. Serializing the room
lifecycle with upload follows the deployed Storage authorization boundary
instead of weakening it for a UI convenience.

### Consequences

- Re-cropping requires selecting an image again; the original is intentionally
  not retained in Storage.
- Existing managed room covers and canonical Club Lounge avatars remain valid
  and need no migration.
- External legacy room-cover pointers stop rendering; managed legacy JPG/PNG
  objects in the YO Voice bucket remain valid.
- Closed or archived rooms must be reopened before their art can change.
- Automated tests prove geometry, pixel composition, Rules poisoning defenses,
  bounded/EXIF-oriented decoding, forced-route cleanup, Club-avatar binding
  and state recovery; the local web
  render proves layout, but
  a physical iOS/Android gallery-and-gesture pass remains release evidence for
  the next native tester build. The Firestore Rules hardening is source-only
  until the coordinated backend release.

## ADR-123: Home Voice Moments are an avatar rail, not an empty-state dashboard

**Status**: Implemented in source; native store build pending
**Date**: 2026-08-29

### Context

When no followed account had posted, mobile Home placed a large explanatory
card with Find creators and Record a Moment beside the signed-in avatar.
Desktop repeated that empty state and also appended friend profiles without
audio. The shared social feed admits friends as well as followed accounts, and
mobile rendered one avatar per Moment document, so the rail could show an
unfollowed friend, an unplayable profile or the same person several times.

### Decision

Home treats this section as a story rail. The signed-in avatar is always first;
without a Moment it records, with Moments it opens the active chain, and its
separate plus remains the create action. Every later avatar must be an account
the viewer follows with at least one active document carrying a non-empty audio
URL. Moments are grouped into one oldest-to-newest chain per author and tapping
the avatar opens that complete chain. Friend data may decorate a followed
author with a real presence dot but cannot create a tile. Relationship-stream
failure fails closed to the signed-in avatar only.

The empty explanatory card, inline discovery CTA, desktop profile suggestions
and divider are removed. Recommendations remain optional and are deliberately
absent until a server-backed feed can respect account status and both block
directions while guaranteeing an active playable Moment. The broader Moments
destination keeps its existing social feed; this narrower contract is applied
only on Home.

### Consequences

- A quiet rail is intentionally short rather than visually filled.
- Find creators remains available in the app's existing navigation and Moment
  creation remains available from the signed-in avatar; neither is duplicated
  inside the rail.
- The current social source is globally bounded before the Home filter, so a
  future backend projection is still needed if the product promises exhaustive
  delivery for accounts following many active authors.
- Mobile and desktop share the same identity, playback and fail-closed
  contract. Automated coverage pins followed-only filtering, playable audio,
  per-author chains, 44 px create targets and 320 px layout at 200% text.

## ADR-124: Auth identity is a root navigation epoch, not only an AuthGate child

**Status**: Implemented in source; native store build pending
**Date**: 2026-08-29

### Context

AuthGate occupies the first root Navigator route, while Profile, Settings,
chat, rooms and notification destinations are pushed above it. Firebase logout
therefore replaced MainShell underneath the current route without removing
that route. Its authenticated Firestore streams continued after the token was
cleared and rendered a permission error over the persistent private dock.
App-level notification SnackBars and the singleton LiveKit room transport also
outlived AuthGate, so changing only its child was not a complete session
boundary.

### Decision

The app-level Firebase Auth subscription owns an auth epoch above the root
Navigator. Signed-in → signed-out, signed-in account A → account B, and an auth
stream failure replace the entire route stack with one zero-duration auth
boundary through `pushAndRemoveUntil`; private `PopScope` vetoes cannot retain
a route across that boundary. Logout's replacement AuthGate paints Login on
its first frame rather than crossfading the previous authenticated subtree.
The ordinary startup animation remains, and signed-out → signed-in does not
force a stack reset so registration can retain its deliberate Verify Email
route.

The same transition clears app-level notification SnackBars. Before Firebase
Auth is cleared, the central sign-out service starts local voice disconnect
(which synchronously drops microphone/session state) and best-effort room
roster leave beside presence and FCM cleanup. An active direct call also sends
its authenticated server-side end action before the local service discards
`directCallId`. Every network cleanup is bounded and may fail without trapping
the user in the session. Remote Auth loss and direct A→B replacement can no
longer mutate roster/call state after authority is gone, but still force the
local LiveKit disconnect at the app auth-epoch boundary.

### Consequences

- No authenticated page, bottom navigation, notification banner or local
  LiveKit transport can be inherited by Login or another account.
- Every logout surface continues to call one `AuthService.signOut()`; screens
  never reproduce routing or cleanup logic.
- Root notification navigation and auth routing now intentionally share the
  same Navigator key because both must address routes without a local context.
- Automated regressions cover normal animated routes, a PopScope veto, direct
  A→B replacement, registration preservation, the real immediate Login
  surface, and bounded room/direct-call cleanup while Auth is still valid.

## ADR-125: The mobile dock presents navigation; `MainShell` still owns it

**Status**: Implemented in source; native store build pending
**Date**: 2026-08-29

### Context

YO Voice's visible phone navigation has five positions, but only four are tab
destinations. Home, Chats and Moments map to existing shell domain indexes;
Friends remains reachable elsewhere; the centre YO logo opens the existing
room/Moment action; and More opens guarded navigation UI rather than an empty
content tab. Encoding those visual positions as page indexes would either
break the centre action, fabricate a More page or discard cached destination
state during animation.

### Decision

`MainShell` remains the only owner of selected domain indexes and cached page
instances. `YoFloatingNavigationDock` is a reusable presentation component
with one five-slot configuration list. It maps selectable domain indexes to
visual slots 0, 1 and 3, while More uses slot 4 only for the lifetime of its
actual sheet/popover or a destination opened from it. The centre slot invokes
the existing action callback independently and never mutates tab selection.

One `LayoutBuilder` divides the available dock width into five equal slots and
centres a single 64–72 px capsule within the selected slot; the circular YO
button is painted last. The dock is supplied through `Scaffold.bottomNavigationBar`,
so the Scaffold reserves its calculated 86 px visual height, 12 px top
clearance and the one device bottom inset without duplicating SafeArea padding.
The same component hosts pushed mobile More destinations, whose callbacks pop
before forwarding to the shell.

Tab content remains one keyed set of lazy children. A Stack makes only the
selected and briefly outgoing layers visible, with hidden children Offstage
and their tickers disabled. One shell controller retargets rapid selections;
the incoming layer moves 12 px horizontally and fades from 0.82, while page
objects, scroll controllers and nested state remain mounted. Reduced motion
sets transitions immediately and disables the capsule breathing and centre
ripple.

### Consequences

- Product tab indexes are not coupled to their visual dock positions.
- More can look selected only while More UI is genuinely active; double taps
  still go through the existing transition guard.
- The YO action retains room/call-aware semantics and real behavior without a
  fake destination.
- The fixed dock itself does not rebuild cached destination pages on animation
  frames.
- Automated tests pin geometry, safe-area reservation, large text, keyboard
  behavior, semantics, haptics, rapid taps, reduced motion, back-stack
  forwarding and retained state. Physical platform rendering, haptic feel and
  screen-reader cadence remain release checks for the next native tester build.

## ADR-126: Vibe links are explicit public-HTTPS actions, not trusted rich text

**Status**: Deployed to web Hosting and byte-verified; native store build pending
**Date**: 2026-08-29

### Context

Profiles stored Vibe as one bounded free-form `statusMessage`. Once the field
became visible on full profiles, a pasted YouTube, Spotify or Apple Music URL
still rendered as inert text. Passing the whole user-controlled string to a
launcher would make custom schemes, local endpoints and provider-lookalike
hosts actionable; making the complete Vibe card tappable would also turn
ordinary prose into a surprising external navigation target.

### Decision

One pure parser extracts every explicit `https://` token in source order and
hands only public DNS-style hosts to the launcher. Credentials, custom ports,
IP literals, local/internal suffixes and non-ASCII authorities are refused.
Provider labels use exact or domain-boundary checks; known music hosts receive
their name, while every other accepted destination is labeled External link.
Trailing sentence punctuation is preserved as prose rather than appended to
the URI. No network prefetch, redirect resolution, artwork lookup or custom
music SDK is involved.

The shared Vibe renderer removes accepted URLs from the prose and gives each
destination its own 48 px Material link row, real host, external-link cue,
link/linkUrl semantics and a high-contrast keyboard focus outline. The row
opens the HTTPS universal link through `LaunchMode.externalApplication`, so an
installed service app may claim it and a browser remains the platform
fallback. One single-flight state plus a short successful-handoff cooldown
prevents double launches; a failed handoff is an inline live error that remains
visible inside modal Profile Preview. Own profile, foreign profile and compact
preview use the same component. Creator-directory cards keep supporting text
non-interactive because the whole card already opens a profile.

### Consequences

- Adding a new trusted provider label requires an exact/boundary-safe host and
  a lookalike-domain regression; generic HTTPS links work without one.
- Scheme-less, HTTP and custom-scheme text deliberately stays non-actionable.
- No Firestore field, projection, Security Rule or dependency changes are
  required; this is presentation and local input validation only.
- Vibe is not rendered as primary content on a primary-tinted surface. Its
  container is an opaque semantic surface, its label uses the focus role,
  actionable provider icons use the tertiary role, and inline launch failure
  uses the paired error container roles. Adjacent identity metadata remains
  neutral with accessible external/voice/learning accents; this is a visual
  semantic refinement only and does not change stored profile data or URL
  trust rules.
- Automated coverage pins multiple links, Unicode paths, punctuation,
  malicious hosts, exact launch URI, keyboard/screen-reader semantics,
  double-fire, failure/disposal and 320 px at 200% text. Real-font frames cover
  390 px, 768 px and the 320 px enlarged-text state.

## ADR-127: Pearl uses semantic colour roles and keeps voice/media surfaces explicitly immersive

**Status**: Implemented; web Hosting deployed; native store build pending
**Date**: 2026-08-29

### Context

The device-local Light preference changed Material's brightness but most
visible screens still painted dark literals or white copy. On a light canvas
this produced white-on-white headings, disconnected black cards and white
status-bar icons. Replacing every purple/white/black literal globally would
break text over uploaded images, room scrims, calls and recording workspaces,
where darkness is functional rather than a theme leak.

### Decision

`AppColors` remains the stable brand/status palette. `AppPalette`, a
`ThemeExtension`, owns brightness-dependent semantic roles for canvas,
surfaces, borders, primary/secondary/tertiary copy, navigation, focus, scrim,
shadow and status containers. `AppTheme` installs Dark and Pearl palettes,
removes colour ownership from typography and updates Android/iOS status and
navigation chrome every frame. Pearl uses warm white/plum neutrals and ink
copy; purple is an accent rather than a page tint.

Shared controls and normal journeys migrate complete surface/foreground atoms:
shell, Home/dock, Chats, Friends, Moments, Profile, Settings, Notifications,
Premium and shared modal/state components. Inputs use the strong boundary role;
decorative cards may use the quiet border. Voice rooms, calls, room
creation/settings/entry, recording and review, story viewing, cropping,
achievements, creator discovery/analytics and staff or moderation workspaces
remain complete local dark treatments with their own readable copy, scrims and
system chrome. Those are intentional immersive islands, not permission to
reuse dark literals on a Pearl page.

Light graduates from Beta; Polish remains Beta because colour completeness is
independent of translation completeness. The branded launch splash stays dark
to avoid a plain system-window flash while persisted preference state loads;
Flutter owns correct chrome from the first rendered app frame.

### Consequences

- Essential semantic text pairs meet at least 4.5:1; control/focus boundaries
  meet at least 3:1. Theme-contract tests fail if a token regresses.
- Primary journeys are exercised in Dark and Pearl at 320/768/1440 and 200%
  text, with focused feature matrices for loading, empty, error and populated
  states. Real-font Home renders are inspected in both themes.
- A new normal screen must use `AppPalette`/`ColorScheme`; a new immersive
  screen must own the full dark atom and document why it is immersive.
- The preference remains device-local and keeps the persisted enum introduced
  by ADR-072, so no migration or Firestore write is needed.

## ADR-128: The central YO action is cradled by the dock's actual outline

**Status**: Implemented; web Hosting deployed; native store build pending
**Date**: 2026-08-29

### Context

The redesigned mobile navigation raised the branded YO action above a rounded
floating bar, but the bar itself remained an uninterrupted rectangle. The
button therefore read as a circle laid on top of navigation rather than the
intentional recessed cradle in the approved interaction reference. Adding a
background-coloured mask would only work in one theme and would separate the
visible edge from hit testing, clipping and shadows.

### Decision

The shared `YoFloatingNavigationDock` owns one custom rounded `ShapeBorder`.
Its top edge uses the Material circular-notch tangent construction around the
64/68 px YO control with a five-pixel gap, then continues into the existing
30 px outer corners. The same path paints the semantic Dark/Pearl surface,
border and shadow and clips active decoration. A non-interactive semantic
`surfaceSunken` socket with a strong boundary fills the cut-out behind the
button, so the recess remains visible regardless of page content. The centre
control stays a separate semantic action above that surface; product tab
indexes and routing remain unchanged.

### Consequences

- The cut-out is self-contained and cannot expose a theme-mismatched page or
  masking colour through its five-pixel socket.
- Fill, border, shadow and clipping cannot drift into four approximations of
  the same silhouette.
- Widget coverage asserts the top-centre opening, filled lower centre,
  centring, full tappable edge, 320/768 px layouts and unchanged destination
  semantics. Ordered focus, Enter/Space activation, visible focus chrome and
  the 160%+ two-by-two full-label layout are pinned independently. Real-font
  Dark and Pearl frames cover Home and Chats selection at 320/390/430 px.
- A physical native visual/haptic pass remains release evidence for the next
  coordinated tester build; no native build is created by this source change.

## ADR-129: Dark launch chrome does not globally pin Pearl's iOS runtime

**Status**: Implemented in source; native tester build 12 pending
**Date**: 2026-08-29

### Context

ADR-016 added `UIUserInterfaceStyle=Dark` when YO Voice was a dark-only
product. Pearl later introduced a complete light theme and System preference,
but the native override remained. On iOS that override controls the appearance
reported to Flutter, so a store-installed app could keep resolving System to
Dark even though the Dart theme and per-frame system-overlay handling were
ready for Pearl.

### Decision

Remove the application-wide `UIUserInterfaceStyle` key from `Info.plist`.
Keep the branded launch storyboard and the native window background dark, then
let the persisted Flutter preference own `themeMode` and the rendered frame's
status-bar icon brightness. Add a source-level regression that rejects a new
global iOS appearance pin.

### Reasoning

Making the launch screen adaptive would expose an uninitialized system colour
before local preferences load and could reintroduce the white transition flash
ADR-016 fixed. Keeping the launch atom dark while releasing only the runtime
appearance override preserves that protection without contradicting Pearl.

### Consequences

- System follows iOS appearance and explicit Dark/Pearl remains Flutter-owned.
- Startup stays intentionally dark for the brief preference-loading boundary.
- Immersive rooms, calls, recording and crop routes continue to apply their
  complete local dark theme and system overlay explicitly.
- A physical build-12 Dark/Pearl/System pass remains native release evidence.

## ADR-130: Canonical profile identity converges snapshots and live chat UI

**Status**: Implemented in source; coordinated tester build 13 pending
**Date**: 2026-08-29

### Context

Conversation rows, Club membership records and Voice Moments copy display
name/avatar fields so they can render without joining private account data.
The profile fan-out wrote `event.data.after` into those copies. Firestore
events are at-least-once and may finish out of order, so an old event could
win after a newer photo was already canonical. Chats made the mismatch visible
because its horizontal friend strip read the reactive profile while the row
below read only the stale conversation copy.

### Decision

`users/{uid}` remains the authority for visible identity fields, while Firebase
Auth remains the authority for account existence and enablement. Every fan-out
chunk reads the private profile inside the same Firestore transaction as its
conversation, Club-member and Moment updates. A concurrent edit invalidates
and retries the transaction, making every invocation convergent regardless of
delivery order. Dynamic map keys use `FieldPath`, Club mirrors remain
discovery-only and each canonical member record must assert the same uid.

Conversation snapshots remain an offline fallback, not a UI cache authority.
Chats overlays its already-open friend stream, an open chat watches the
privacy-safe public profile through `ProfileService`, and both mobile and
desktop Home can overlay that projection on recent-chat imagery. Firebase Auth
existence/enablement and the active private profile are both required before a
fan-out or repair may republish identity. A project-pinned bounded script
reports aggregate counts, defaults to dry-run and repairs existing snapshots
only after explicit `--apply`.

### Consequences

- Old and duplicate events cannot restore an obsolete avatar or display name.
- Removing a photo propagates an authoritative empty value instead of falling
  back forever to the old conversation URL.
- Live surfaces update without route recreation, while offline/error states
  continue using the conversation snapshot.
- Fan-out cost is bounded to 150 targets per transaction; large histories are
  processed in retryable chunks and the repair run is capped and resumable.
- Each conversation transaction revalidates exact two-party membership, so a
  stale discovery result cannot inject identity after a delete/recreate race.
- Repair failures emit no document paths or account identifiers to the CLI.
- Build 13 and a two-account Chats/Home smoke test remain native release
  evidence; automated coverage is not represented as physical-device proof.

## ADR-131: Profile identity uses a two-level passport rail, not a badge staircase

**Status**: Deployed to web Hosting and byte-verified; native tester build held
**Date**: 2026-08-29

### Context

The compact Profile header still placed every identity marker in the narrow
column beside a large avatar. An owner with VIP, Creator, Premium and a selected
achievement therefore produced four visually unrelated floors below the
pseudonym. The badges were all truthful, but their layout made authority,
product access and cosmetics look like one undifferentiated stack and pushed
the first content card far below the hero. Pearl exposed adjacent contrast
defects in bright role and fallback-avatar colours.

### Decision

The profile hero becomes one responsive passport composition. Avatar and
pseudonym remain the primary row; the pseudonym sits on a small semantic
surface plate so it stays readable across arbitrary banners and both themes.
Avatar diameter steps down from 96 to 88, 80 and 72 logical pixels as available
width contracts. The display name is the heading and may occupy two lines;
username remains complete whenever its own line fits.

Identity labels use the full 18-pixel-gutter content width below that row. With
an achievement selected, the first level is official authority (role + VIP)
and the second is product/cosmetic identity (account type + Premium + title).
Without a selected title, those compact labels share one Wrap to avoid buying a
second row unnecessarily. Normal phone text fits the complete owner case in two
levels. Enlarged text may wrap further rather than abbreviating, scrolling or
hiding an identity.

Canonical role colours still own tint and border, while Pearl may use a darker
foreground of the same hue to meet contrast. The fallback avatar similarly uses
the Pearl primary surface behind its white initial. None of these presentation
choices changes entitlement or staff authority.

### Consequences

- The densest real owner profile stays below 295 logical pixels at 390 px and
  all five labels remain visible at 320 px/200% text.
- Authority reads first and independently from achievements; a cosmetic title
  can no longer resemble an additional staff tier by placement.
- Badge repository injection is a real lifecycle seam: changing repositories
  detaches the old revision listener, resolves again and cannot retain a
  disposed State.
- Dark/Pearl real-font captures at 320–1440 px plus explicit contrast and
  heading-semantics assertions are release evidence. Physical native evidence
  waits for the next coordinated tester build, not a one-off upload.

## ADR-132: First-run education is a route-aware shell tour, not another onboarding account step

**Status**: Implemented and verified in source; web and native release pending
**Date**: 2026-08-29

### Context

YO Voice opened a newly registered account directly onto Home without
explaining that the centre YO action creates audio, that Moments is a primary
feed, or where Chats and the broader product menu live. Adding another required
registration page would delay the first useful screen and could not point at
the controls users actually need. A generic carousel would have the same
problem, while a global first-run boolean would leak progress between accounts
sharing one device. Startup can also own a room deep link, a pushed route or a
native notification-permission dialog, so an arbitrary delay cannot safely
decide when a guide may appear.

### Decision

The authenticated `MainShell` owns a five-step, skippable product tour. It
starts with one short value statement, then spotlights the real production
anchors for YO creation, Moments, Chats and More on whichever responsive shell
is currently rendered. The overlay blocks interaction underneath it and offers
Skip, Back, Next and Done; Settings exposes **Quick app tour** for deliberate
replay. English and Polish copy share the app localization boundary. Dark and
Pearl use semantic surfaces and a dual-tone, theme-aware spotlight ring.

Automatic presentation is limited to a Firebase account's initial session.
Skip and Done persist in `SharedPreferences` under the normalized uid and tour
version; existing accounts and unreadable local storage fail closed, while a
new version can intentionally teach a materially changed shell later. No
Firestore field, public identity projection or server write is introduced.

The shell waits for its cold-start room hand-off, the full reverse transition
of any route above it, and an explicit future that settles with the native
notification permission prompt plus any cold-start notification destination.
The prompt phase is bounded and releases the barrier on platform hangs. Local
iOS notification initialization no longer asks independently; Firebase
Messaging is the single permission owner. Initial-message lookup and routing
are resolved before token binding, while token registration and other network
work continue in parallel and never delay the shell. One synchronous
single-flight guard is acquired before
the first await and remains held through the guide route's reverse transition,
so auto-start and rapid replay cannot stack dialogs. Anchors are remeasured
after responsive layout changes and never reuse a desktop rectangle on mobile.

The guide is one modal route with closed-loop focus, Escape and arrow-key
shortcuts, a stable Next control across step changes, one live-region route
label, 48 px actions and pinned header/footer around a scrollable copy region.
Reduced motion removes route and progress animation.

### Consequences

- Registration stays short and the guide remains optional, but every new
  account gets an immediate explanation in the context of the real app.
- A device shared by multiple accounts stores independent outcomes; deleting
  local app data can offer the guide again only if the account still satisfies
  the narrow initial-session gate.
- Responsive resize, 320×568 at 200% text, Dark/Pearl contrast, keyboard focus,
  route blocking, duplicate launch, permission success/failure, persistence
  and real dock/sidebar geometry are automated. Twelve real-theme visual
  frames cover phone, accessible phone and desktop.
- Physical VoiceOver/TalkBack behavior remains a native tester smoke item even
  though widget semantics probes pass.
