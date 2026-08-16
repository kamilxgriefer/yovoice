# 2026-08-16 — The privacy cutover, seven rules defects, and the first real production deploy

**Scope:** the largest single day in this repo's history. It runs from
ADR-051 (the canonical logo mark) through ADR-052, ADR-053, ADR-054 —
splitting private account records from server-owned public profiles — and
`c1d6cd9`'s server-authoritative Stage B set, then through three rounds of
Firestore/Storage rules hardening, and ends with an executed production
cutover: Cloud Functions 51 → 111, indexes 14 → 15 composites, both rules
files deployed, and the Flutter web client released to `app.yovoice.app`.

Two new decision records came out of it:
[ADR-055](../Decisions.md#adr-055-the-2026-08-16-production-cutover--order-the-deploy-by-what-fails-closed-and-verify-by-fingerprinting-served-bytes)
(cutover ordering and verification) and
[ADR-056](../Decisions.md#adr-056-a-moderation-action-belongs-in-a-callable-that-completes-the-whole-removal-not-in-a-rule-that-deletes-one-row)
(why rules-level room eviction was deleted rather than fixed). ADR-005 was
corrected after being disproved by experiment.

## 1. A belief in our own ADR was wrong, and wrong in the dangerous direction

ADR-005 claimed that OR-ing an `exists()`-based clause into a top-level
wildcard rule would fail Firestore's collection-group provability check —
that is, fail closed. Three independent emulator runs reproduce **the
opposite**: the rule is accepted, becomes a tautology for the query, and
returns **every document in that collection group across the whole
database**. The failure mode is silent full enumeration.

An engineer trusting the old wording would have believed such an edit was
safe to try. That paragraph was also the origin of two spurious defect
reports filed against a rule that was never the problem.

The discriminating experiment, now executable rather than described: set
the **top-level** rule to `if false` *while* the nested, parent-scoped
rule is `if true` — the collection-group query is still denied. Setting
the nested rule to `if false` proves nothing, because Firestore unions
allow-rules. This matches Firebase's documented behaviour that rules for
`/parent/{id}/coll/{doc}` take no part in authorizing a collection-group
query.

Corrected in `794454b`, with the fail-open warning added to SECURITY.md
principle 3 and a note that the two top-level wildcard rules are a live
containment boundary, not housekeeping.

## 2. Seven rules defects, every one of them live in production

Each was pinned by a case that failed first. In landing order:

**`56e7ea7`**

- `clubs/{clubId}/members` manager updates allowlisted only
  `['role','updatedAt']`, while both the deployed client and this tree
  write `role`, `roleUpdatedAt`, `roleUpdatedBy`. **Every club promotion
  and demotion was denied** — club role management was entirely
  non-functional. Also closed an unknown-role string falling through
  `clubRolePower`'s else branch.
- `canAccessRoom()` had no `isRoomMember` branch, so a Community room
  flipped to private became unreadable to its own members. The blast
  radius came from the client: `watchMyCommunities()` hydrates every id in
  a single `Future.wait`, so **one** unreadable room emptied the entire
  Communities list.
- `storage.rules` `validClubImageUpload()` accepted only the bare
  `avatar`/`banner` object name while the deployed client uploads
  `{kind}_{millis}.{ext}` — every club image upload was denied.

**`2fc05e5`** (closing review findings on `56e7ea7`)

- `isRoomMember()` had no account-status check, so widening
  `canAccessRoom()` handed private rooms, rosters and participant lists to
  **banned and disabled accounts**. Now requires `isActiveAccount()`. This
  also withdraws room chat and voice-start from suspended accounts, which
  is the point: a suspension that stops at the Club lounge door but not
  the Community room door is not a suspension.
- Role attribution was forgeable by omitting the field or resending the
  stored value, because `diff().affectedKeys()` reports only fields whose
  **value** changed and the guards were gated on `hasAny()`. Attribution
  is now required unconditionally against the post-write document. This
  became [SECURITY.md principle 6](../SECURITY.md#firestore-security-rules--design-principles).
- `roomMembers` update had no field allowlist on either branch. A host
  could repoint their own membership row at a **victim's** uid; the
  victim's `collectionGroup` query then returned a row whose room they
  cannot read, and `Future.wait` emptied their entire Communities tab —
  permanently, remotely, with no action available to the victim.

**`952d8e4`** — and this one is the interesting failure, because the fix
in `2fc05e5` created it.

`2fc05e5` added self-leave and host-eviction, each requiring the room's
`memberCount` to decrement in the same commit — the counter transition
being what bound the two writes together. But hosts can write
`memberCount` directly. So a host could drive it to zero in three plain
writes while rows remained, after which **nobody could leave and nobody
could be removed**. A banned host could do it too, since the room-update
host branch checks no account status. And it fired **with no attacker at
all**: any room whose stored counter had drifted below its true row count
was silently un-leavable, legacy rooms carrying no `memberCount` field
being the clearest case.

The fix was to **delete the eviction path, not guard it**. Underneath the
counter bug was a design error: deleting a roster row is not a removal.
The evicted account stayed connected to the live audio, kept chat through
`isRoomParticipant`, and could rejoin a public room immediately.
`removeRoomParticipantSelf` already does the whole job. No client ever
called the rules path, so removing it broke nothing — and it was the
single source of all three review findings (the starvation primitive, a
batch pairing that could not bind, a bypass of the staff moderation
freeze).

Self-leave stays, because it binds correctly: `!existsAfter` on the
caller's own row rather than on a counter anyone else can move.

**Accepted trade, stated plainly:** `memberCount` can now overcount if a
client deletes a row without pairing the room write. It can never
undercount below a real departure. A wrong number beats a trapped member.

## 3. Test scaffolding that could quietly stop testing

The `collectionGroup()` PROOF cases are built by transforming the live
ruleset. The variant helper now **asserts each snippet is present before
substituting**, so a reformatted rule fails loudly instead of silently
running the control that proves nothing. A test that can degrade into a
no-op is worse than a missing test, because it reports green.

## 4. CI was red on three consecutive pushes — including a docs-only commit

509 of 510 Functions tests passed every time, and the failure was always
the same case: `legacy_identity_scrub.test.js` asserting `scanned === 1`
and getting 2. The docs-only commit is what gave it away.

`scrubIdentitySnapshots` scans the whole `conversations` collection and
takes no uid or prefix scope, so that file cannot isolate itself the way
its own `wipe()` isolates its fixtures. `node --test test/*.test.js` runs
files **concurrently against one emulator**, so a conversation seeded by
any other file was counted here too — the assertion held or broke purely
on interleaving. Green locally, red on the runner.

Fixed in `38b29f7` by measuring the **delta** around this test's own
write: exactly as strong an assertion (one document scanned, one scrub
planned, nothing written), independent of what else exists.

## 5. The cutover

Verified from the live project, not inferred:

| Target | Before | After | Evidence |
|---|---|---|---|
| Cloud Functions | 51 | **111** | `firebase functions:list` |
| Composite indexes | 14 | **15** | `firebase firestore:indexes` |
| `fieldOverrides` | 1 | **3** | same |
| `firestore.rules` | pre-ADR-053 | deployed **twice** (20:40, 21:06) | Console → Firestore → Rules history |
| `storage.rules` | pre-`56e7ea7` | deployed | — |
| Hosting | commit `9fdd8a9` | current | `main.dart.js`, 5,139,256 bytes, containing `publicProfiles`, `searchPublicProfiles`, `selectMyAchievementTitle` |

The ~60 new functions are the whole ADR-054 privacy layer
(`onUserPrivacySourceChanged`, `searchPublicProfiles`, `onAuthUserDeleted`),
every social-graph callable, every `onAchievement*` trigger, the club and
room self-service callables, and the entire Stage B set from `c1d6cd9`.

The two data steps ran the same evening, completing the sequence 5/5:

| Step | Result | Verification |
|---|---|---|
| Backfill projections | 14 accounts, **28 writes** | re-run planned **0**, all 33 unchanged |
| Legacy identity scrub | **21 documents**, 4 phases, 0 conflicts | re-run planned **0** in every phase |

### The apparent gap was less than half what the console suggested

33 `users` against 1 `publicProfiles` reads as 32 missing projections. The
backfill's dry run said otherwise: **18 of the 33 are Auth orphans**, with
no Firebase Auth account behind them, so they correctly receive no
projection. The real gap was **14**. Comparing the sizes of two
collections is not a measurement when one of them is derived under
conditions — the derivation's own dry run is the measurement.

### Unblocking it exposed a permission boundary worth keeping

`gcloud` had never been installed on the machine, which is the entire
reason `gcloud auth application-default login` "did not work". Beyond
installing it, ADC also needed
`gcloud auth application-default set-quota-project`, because both scripts
join Firebase Auth and `identitytoolkit.googleapis.com` refuses user-ADC
without one — and it fails at the Auth join, which reads like a Firestore
permission problem.

The CI path added earlier that day (`4f9ad47`) was dispatched first and
failed with `7 PERMISSION_DENIED`: the Hosting service-account secret has
no Firestore access. It was deliberately **not** granted any. Widening it
would mean anyone with repository write access could reach all production
data through a secret that today reaches only Hosting. Local operator
credentials were the narrower instrument, so they were the right one.

### The index deploy fixed a defect nobody had reported

`entitlements(isPremium, currentPeriodEnd)` backs the scheduled
`expirePremiumIdentity` query at
`functions/premium/entitlements.js:163`. It had never been deployed, so
every run threw `FAILED_PRECONDITION` and **Premium never expired for any
account** — for the entire life of the feature. The function looked
healthy in `functions:list`; 510 Functions tests were green throughout,
because the emulator does not require composite indexes. The failure
existed only in the scheduler logs.

### The ordering lesson changed direction, and no document noticed

Until `409c7ee`, pushing to `main` published Hosting, and every deployment
document here was written on that premise — the 2026-08-11 manifest's
central warning is literally "treat push to `main` as a Hosting deploy,
and sequence the backend first." `409c7ee` split verification from
release. Nothing updated the docs, so the project kept operating on a
model in which the client ships itself, and it had silently stopped doing
so.

The failure that produced is the mirror image of the old one: `main` moved
through four ADRs while production served `9fdd8a9`, and ~60 functions sat
deployed and **inert** because no client called them. Client-ahead-of-backend
gives visibly broken features. Backend-ahead-of-client gives invisible dead
code — worse to diagnose, because nothing looks wrong.

Two rules that survive both directions, now in ADR-055:

1. **Order by what fails closed.** Functions and projections first,
   clients next, restrictive rules last.
2. **Verify by fingerprinting the served bytes, never by trusting deploy
   output.** `firebase deploy` reporting success means an upload
   succeeded. Fetch the artifact and grep it for a symbol only the new
   build contains.

## 6. Known open, recorded rather than smoothed over

- **18 `users` documents have no Firebase Auth account.** Surfaced as
  `authOrphans: 18` by the backfill. Stale personal data with no owner, so
  a retention question rather than a tidiness one. Decide deliberately;
  do not fold it into an unrelated migration.
- **Host eviction does not exist anywhere**, deliberately (ADR-056).
- **`memberCount` can overcount**, deliberately.
- **Pre-existing and still live**: the room-update host branch selects on
  `resource.data.hostId == request.auth.uid` with no account-status check,
  so a banned host can still edit room metadata and start voice.
- **`voiceMinutes` is written by nothing.**
  `receiveLiveKitAchievementWebhook` exists in
  `functions/achievements/livekit_http.js` but is never exported from
  `functions/index.js`, so Creator Studio's "Voice time" tile and the
  voice achievement category are permanently zero.
- **`publishPublicStatsSchedule`** (`cb4651a`) is committed and
  deliberately **not** deployed, behind three preconditions — including
  that its data source is known wrong.
- **UNVERIFIED**: `NEXT_PUBLIC_APP_URL` in the website repo's three Vercel
  environments. `app.yovoice.app` resolves and serves, but whether the
  website points at it could not be checked from this repo.
- **UNVERIFIED**: no successful `expirePremiumIdentity` run has been
  observed in Console → Functions → Logs since the index deploy.
- **UNVERIFIED**: the native adoption window. No App Store or Play build
  carrying the new client is confirmed released, so native installs
  predating the cutover fail closed on foreign-profile reads.

## 7. Verification

| Suite | Result |
|---|---|
| Firestore rules | **301** passed / 0 failed (268 → 281 → 295 → 301 across the day) |
| Storage rules | **46** |
| Family media | **11** |
| Cloud Functions | **510** across 82 suites (487 → 510) |
| Flutter | **438** across 52 files |

Several docs had drifted badly against these: TESTING.md claimed 268 and
43, Firebase.md claimed 265, Bugs.md and Roadmap.md claimed 225, and
Bugs.md additionally asserted that Cloud Functions had *zero* automated
coverage while 510 tests were passing. Counts now live in one table,
[TESTING.md](../TESTING.md#current-counts-2026-08-16), so there is a
single place to correct.

## 8. Documentation corrections made in this pass

Recorded as dated corrections rather than quiet rewrites, because this
project has now been bitten twice by trusting its own stale claims:

- **`Architecture.md`** told the sibling `yovoice-website` repo it could
  query user profiles directly from Firestore under the same rules.
  Highest-priority correction: that is false since the ADR-054 cutover and
  would break that repo. Replaced with the actual paths
  (`publicProfiles` get, `socialPresence` get, `searchPublicProfiles`
  callable) and the projection-gap warning.
- **`PROJECT_STRUCTURE.md`** claimed `npm run deploy` in `functions/`
  deploys only `createLiveKitToken`. It runs `firebase deploy --only
  functions` — all 111, with no `--project` pin. It read as a safety
  reassurance while describing the opposite.
- **`DEPLOYMENT.md`**'s "Undeployed backend as of 2026-08-11" manifest was
  entirely obsolete. Marked superseded, with its still-valid ordering and
  rollback reasoning kept.
- **`Bugs.md`** claimed zero Cloud Functions coverage, and described
  `app.yovoice.app` as DNS-blocked.
- **Roadmap's Done list** had never received ADR-054 or `c1d6cd9`.
- Every "FIXED IN SOURCE, PENDING RULES DEPLOY" marker was cleared.

**Outside `docs/` and NOT edited** (reported for the owning engineer):
`functions/integrity/STAGE_A_ROLLOUT.md:3-4` still says Stage B is
"deliberately not exported from `functions/index.js` yet." That has been
false since `c1d6cd9` and Stage B is now deployed.
