# Deployment

What deploys automatically, what's manual, and exactly how — for both
deployables described in
[ADR-014](Decisions.md#adr-014-two-deployables-one-firebase-project).

## Summary

| What | How | Trigger |
|---|---|---|
| Flutter web verification/build | GitHub Actions | Automatic, on push to `main` |
| Verified Flutter web artifact → Firebase Hosting | GitHub Actions | Manual `workflow_dispatch` after backend readiness |
| Firestore rules + indexes | `firebase deploy --only firestore:rules,firestore:indexes` | Manual |
| Cloud Functions | `firebase deploy --only functions` | Manual |
| Storage rules | `firebase deploy --only storage` | Manual |
| `yovoice-website` | Vercel | Automatic, on push to `main` (separate repo) |

## Flutter web verification and Hosting release

`.github/workflows/firebase-hosting-merge.yml` runs the complete verification
pipeline on every push to `main`:

```
checkout → install Flutter (stable channel) → flutter pub get
  → flutter analyze → flutter test
  → Firestore rules → Storage rules → combined Family media rules
  → Firebase Functions tests against Auth + Firestore emulators
  → flutter build web --release
```

**Every step before the build is a real gate, not just a step**: a
failing `flutter analyze`, a failing widget/unit test, a failing
rules test or a failing Functions test stops the workflow. A push never
publishes Hosting by itself. (Until 2026-08-08 only
`flutter analyze` gated the deploy; the test and rules-suite gates were
added in the product-audit pass. Note the rules suites *verify* the
rules in the repo — rules **deploys** remain manual, see below.) See
[TESTING.md](TESTING.md) and
[DEVELOPMENT_WORKFLOW.md](DEVELOPMENT_WORKFLOW.md#verification-checklist-before-calling-something-done).

After the required indexes, Functions and rules have been deployed and
verified, start the same workflow manually with `deploy_hosting: true`.
That run rebuilds the exact selected revision, packages the verified
`build/web` artifact, then a separate `production` job deploys that artifact
to the `live` channel using
`firebaseServiceAccount: '${{ secrets.FIREBASE_SERVICE_ACCOUNT_YOVOICE_EC54A }}'`
— a repo-level GitHub secret, not anything checked into the repo.

The workflow pins Flutter, Firebase CLI and every third-party Action to an
exact version/commit. It deploys **Hosting only** and only on the explicit
manual release path. It does not touch Firestore rules, indexes, Storage
rules, or Cloud Functions — those remain separate deliberate steps (see
below).

Repository administrators must also configure GitHub's `production`
environment with a required reviewer and protect `main` with required status
checks. The YAML names the environment, but reviewer and branch policies live
in GitHub settings and cannot be guaranteed by a repository file. Until those
settings are enabled, the manual dispatch is the release confirmation; never
grant the Hosting service-account secret to a different environment.

### DM media and Safari Voice Moment rollout order

The private photo/voice DM client depends on two new callables and a new
Storage path, while Voice Moment finalization depends on the corrected Admin
bucket bootstrap. Release this revision in the following order:

1. deploy all Cloud Functions and verify that
   `reserveDirectMessageAttachment`, `finalizeDirectMessageAttachment` and
   the cleanup schedule are ACTIVE;
2. deploy `storage.rules` and run an authenticated participant/non-participant
   smoke test against `message_attachments`;
3. only then deploy the Flutter Hosting artifact;
4. on the deployed build, send one photo and one voice DM between two test
   accounts, then publish a one-second Voice Moment from a physical iPhone
   Safari session.

Reversing steps 1–3 exposes working-looking attachment buttons to a client
whose trusted backend or Storage contract is not live yet. Firestore rules and
indexes are unchanged by this particular media rollout.

### Room creation and Club media rollout order

This revision changes all four layers at once: Podcast/Family creation in the
Flutter client and Firestore Rules, ordinary Club creation/finalization in
Cloud Functions, and root-first Club/Family privacy in Storage Rules. It also
intentionally rejects the old pre-root Club upload flow. Treat it as a
coordinated cutover, not four independent deploys.

1. Verify the exact revision with all five emulator suites, `flutter test`,
   `flutter analyze` and `flutter build web --release`.
2. Release the verified Hosting client first. During this short compatibility
   window the new client can create a Club root even if finalization is not
   live yet; artwork may wait for retry, but the Club remains usable. Do not
   leave this window open longer than the deployment session.
3. Deploy all Cloud Functions and verify `createCommunityClub` and
   `finalizeClubMedia` are ACTIVE in `europe-west1`.
4. Deploy `firestore.rules`, then `storage.rules`. The Firestore release fixes
   deterministic Family missing-document probing and pins Family media null;
   the Storage release closes pre-root orphan uploads and all Family artwork
   access.
5. Invalidate/refresh the PWA and smoke-test with real accounts: create one
   Community room, one Podcast, one ordinary Club with JPG/PNG/WebP artwork,
   and one Family Room without artwork; reopen each and join from a second
   authorized account. Confirm an anonymous request cannot fetch seeded
   Family artwork.

Old cached clients are not compatible with the final root-first Storage rule.
If the product cannot force a minimum web version, keep the cutover window
brief and instruct open sessions to refresh. Do not restore the pre-root
exception as a compatibility fix: it is an orphan-storage abuse path. Do not
restore Family download-token URLs: they bypass membership revocation.

### Display-name cooldown rollout order

The 30-day name limit spans a new callable, a new private user field and a
Rules cutoff for the old direct-write path. Release it in this order:

1. Run the focused `functions/test/display_name.test.js` suite and the complete
   Firestore Rules emulator suite against a fresh, isolated emulator project.
2. Deploy Cloud Functions first and verify `updateMyDisplayName` is ACTIVE in
   `europe-west1`. At this point old clients still work through the previous
   direct write, while new clients are not yet released.
3. Deploy `firestore.rules`. From this point an established
   `users/{uid}.displayName` cannot change directly and
   `displayNameChangedAt` is server-only. Unchanged merged values and initial
   profile bootstrap remain compatible; an old client attempting a real rename
   now fails closed.
4. Release the Flutter and website clients that call `updateMyDisplayName`.
   Smoke-test one verified legacy account (first change succeeds), an immediate
   second different name (structured cooldown), and a same-name replay
   (idempotent success with unchanged timestamps). Confirm an eleventh
   profile-reaching, locally valid same-name attempt inside one fixed server
   minute returns `resource-exhausted`, while the first immediate Auth-sync
   retry remains available.
5. Confirm the canonical value converges in Firebase Auth,
   `publicProfiles/{uid}`, `userDirectory/{uid}` and a previously materialized
   identity snapshot. A transient Auth-sync error is repaired by replaying the
   same canonical name; do not manually clear or advance the Firestore
   timestamp.

Do not reverse steps 2 and 3: Rules without the callable strand every rename.
Do not release clients before step 2: there is no permitted direct-write
fallback once the server answers or the Rules cutoff is live.

## Why rules/functions are tested but not auto-deployed

Auto-deploying `firestore.rules` on every push to `main` would mean a
single bad rules change goes live the moment it's pushed, with no
verification step in between beyond whatever the pusher ran locally.
Given that Security Rules are this project's entire authorization layer
([ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work)),
that's a meaningfully higher-stakes automatic action than redeploying a
web build — a bad Hosting deploy is annoying and reversible; a bad rules
deploy can be a live security hole or a locked-out user base. Keeping
rules/functions deploys manual and deliberate is the current tradeoff;
revisit this if the emulator test suite (see
[TESTING.md](TESTING.md)) ever becomes trusted enough to gate an automatic
deploy the way `flutter analyze` gates the Hosting one.

## Firestore rules and indexes (manual)

Always run the emulator test suite against a **freshly-started** emulator
before deploying a rules change — see
[TESTING.md](TESTING.md#firestore-rules--the-most-mature-coverage-in-the-project)
for why a passing suite isn't automatically sufficient proof, particularly
for anything touching `collectionGroup()` queries.

```bash
firebase deploy --only firestore:rules,firestore:indexes --project yovoice-ec54a
```

### Before editing `fieldOverrides`, read the trap

A `fieldOverrides` entry **replaces** Firestore's automatic single-field
indexing for that field instead of adding to it, and three of the four
overrides live today declare `COLLECTION_GROUP` scope only — so
`rooms.roomId`, `participants.userId` and `roomMembers.userId` currently
have **no collection-scoped index in production**. Harmless right now (no query
needs one), invisible in every emulator run, and a `FAILED_PRECONDITION`
in production the day someone adds one. When that day comes, extend the
existing entry rather than adding a second one. Full explanation, the
verified per-field state and the correct entry shape:
[Firebase.md](Firebase.md#a-fieldoverrides-entry-replaces-automatic-single-field-indexing).

### Reading the deployed ruleset: the verification standard

**The deployed ruleset can be read back exactly.** Until 2026-08-17 this
file and [SECURITY.md](SECURITY.md) both said the Console's version
history was the only way to see what is live, and that there was no
read-only command. That was wrong. With Application Default Credentials
configured (see the ADC prerequisite below — `gcloud` *and* a quota
project), the Firebase Rules API returns both the released ruleset's name
and its full source:

```bash
# 1. Which ruleset is currently released to Firestore?
curl -s -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  https://firebaserules.googleapis.com/v1/projects/yovoice-ec54a/releases/cloud.firestore

# 2. The full source of that ruleset. RULESET_NAME is the `rulesetName`
#    field from step 1, e.g. projects/yovoice-ec54a/rulesets/<uuid>.
curl -s -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  "https://firebaserules.googleapis.com/v1/RULESET_NAME"
```

Two things this changes, both of which were previously open problems:

1. **A pre-deploy snapshot is now possible.** Fetch the live source into a
   file *before* any rules deploy. That file is the rollback artifact — the
   exact bytes that were serving, independent of whether the repository
   state matches what was deployed. The cutover planning had to proceed
   without one; it no longer does.
2. **A post-deploy diff against HEAD is the verification standard.** Do not
   conclude a rules deploy succeeded from the CLI's own output. Fetch the
   released source and diff it against `firestore.rules` at the deployed
   commit. `c75720a` was verified this way on 2026-08-17 and came back
   **byte-identical**. This is the rules-layer equivalent of fingerprinting
   `main.dart.js` for a Hosting release
   ([ADR-055](Decisions.md#adr-055-the-2026-08-16-production-cutover--order-the-deploy-by-what-fails-closed-and-verify-by-fingerprinting-served-bytes)).

The response body carries the source with escaped newlines; extract the
`content` field before diffing (`jq -r '.source.files[].content'`).

## Cloud Functions (manual)

```bash
firebase deploy --only functions --project yovoice-ec54a
```

`functions/package.json`'s deploy script is the same full deployment, so
either command below is valid:

```json
"scripts": {
  "deploy": "firebase deploy --only functions",
  "serve": "firebase emulators:start --only functions"
}
```

Run the top-level command when an explicit `--project` is desirable; run
`npm run deploy` from `functions/` only when the active Firebase project has
already been verified with `firebase use`.

## Storage rules (manual)

Cloud Storage rules in this project call `firestore.get()` and
`firestore.exists()` for account, upload-reservation and ownership authority.
That cross-service evaluation has a separate production IAM prerequisite; a
green emulator suite and a successful rules deploy do not prove the binding
exists. Verify it before every Storage-rules rollout:

```bash
PROJECT_ID=yovoice-ec54a
PROJECT_NUMBER=80235878542
STORAGE_RULES_AGENT="service-${PROJECT_NUMBER}@gcp-sa-firebasestorage.iam.gserviceaccount.com"

gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten='bindings[].members' \
  --filter="bindings.role:roles/firebaserules.firestoreServiceAgent AND bindings.members:serviceAccount:${STORAGE_RULES_AGENT}" \
  --format='value(bindings.role,bindings.members)'
```

The command must print the exact service-agent role and Storage service
account. An empty result means every Storage rule branch that reads Firestore
will fail closed with `storage/unauthorized`, including Voice Moments, profile
artwork, room artwork and private message media. Restore only the documented
service-agent binding, never loosen the Storage rules as a workaround:

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${STORAGE_RULES_AGENT}" \
  --role='roles/firebaserules.firestoreServiceAgent'
```

Wait for IAM propagation, then run a real authenticated upload smoke test that
exercises a Firestore-backed rule before deploying the client. This role is
granted only to the Google-managed Firebase Storage service agent and carries
only the Firestore entity-read permission required for cross-service Rules.

```bash
firebase deploy --only storage --project yovoice-ec54a
```

## Private-profile projection cutover (strict order) — EXECUTED 2026-08-16

> **Status, 2026-08-16: all five steps are complete and verified.** This
> section previously ended "No command in this section was run as part of
> implementing ADR-054"; that sentence is now false and has been replaced
> with per-step status and per-step numbers. Keep the order below for any
> future repeat — and read the ordering warning under step 3, which is the
> sharpest lesson the cutover produced.

### Prerequisite the next operator will hit: ADC needs `gcloud` *and* a quota project

Steps 2 and 3 run `firebase-admin` scripts locally, which authenticate
through Application Default Credentials. Two non-obvious things blocked
this on 2026-08-16 and cost the cutover a day:

1. **`gcloud` was never installed on this machine.** That is the entire
   reason `gcloud auth application-default login` "did not work" — the
   command did not exist. Install it first (Homebrew here), then run the
   login and complete the browser consent as the operator.
2. **`gcloud auth application-default set-quota-project yovoice-ec54a` is
   required, not optional.** Both scripts join Firebase Auth, and
   `identitytoolkit.googleapis.com` refuses user-ADC without a quota
   project. Skipping this fails at the Auth join, not at Firestore, which
   makes it look like a permissions problem with the wrong service.

```bash
brew install --cask google-cloud-sdk   # the cask actually used on 2026-08-16
gcloud auth application-default login
gcloud auth application-default set-quota-project yovoice-ec54a
```

These are **user credentials**, deliberately — see the CI note under step 2
for why the repository's service-account secret was not used and must not
be widened.

The `users/{uid}` privacy boundary is not a rules-only deploy. Old clients read
foreign root user documents, while new clients require server-owned
`publicProfiles` and `socialPresence`. Use this order so no released client is
pointed at an empty projection and no source change can race the backfill:

1. **DONE 2026-08-16.** Deploy the projection triggers, bounded search callable
   and all social-graph functions whose safe profile summaries/no-email request
   shape changed. In the event this was folded into a full
   `--only functions` deploy that took the project from 51 to 111 functions;
   the selective list below remains the right shape for a repeat:

   ```bash
   firebase deploy --only \
functions:onUserPrivacySourceChanged,functions:onAuthUserDeleted,\
functions:searchPublicProfiles,\
functions:getMutualFriends,functions:getFriendSuggestions,\
functions:sendFriendRequest,functions:respondToFriendRequest,\
functions:cancelFriendRequest,functions:removeFriend,\
functions:setFollow,functions:setUserBlock \
--project yovoice-ec54a
   ```

2. **DONE 2026-08-16.** Backfill the `publicProfiles` and `socialPresence`
   projections. Measured, one page, `reachedEnd: true`:

   | | dry run | apply | verification re-run |
   |---|---|---|---|
   | `scannedUsers` | 33 | 33 | 33 |
   | `authOrphans` | 18 | 18 | 18 |
   | `profileCreates` | 14 | 14 | **0** |
   | `profileUnchanged` | 19 | 19 | **33** |
   | `appliedWrites` | 0 | **28** | 0 |

   **Correct the arithmetic before repeating this anywhere.** A console count
   of 33 `users` against 1 `publicProfiles` looks like 32 missing projections.
   It was 14. **18 of the 33 `users` documents are Auth orphans** — no
   corresponding Firebase Auth account — so they correctly receive no
   projection and never were part of the gap. Those orphans are a separate,
   still-open housekeeping question (see
   [Bugs.md](Bugs.md#data-integrity)); `onAuthUserDeleted` only covers
   deletions occurring after it was deployed on 2026-08-16.

   The verification re-run is the proof that matters: a second dry run
   planned zero writes and reported all 33 unchanged, so the script is
   idempotent against real production data, not just in the emulator.

   `4f9ad47` added `.github/workflows/public-profile-backfill.yml` as a
   credential-free path — `workflow_dispatch` only, `apply` defaulting to
   false, same `production` environment as the Hosting deploy. **It was
   dispatched and it failed with `7 PERMISSION_DENIED`**: the
   `FIREBASE_SERVICE_ACCOUNT_YOVOICE_EC54A` secret is scoped to Hosting and
   has no Firestore access. It was deliberately **not** granted any, because
   that would let anyone with repository write access reach all production
   data through a secret that today reaches only Hosting. The backfill ran
   from the operator's local ADC instead. **Treat that workflow as present
   but non-functional** until someone consciously decides to widen the
   service account or provision a migration-only one.

   Backfill in bounded pages. Dry-run is the default and performs zero writes.
   Record `nextCursor` from the JSON response; apply the same page, then repeat
   with `--start-after CURSOR` until `reachedEnd` is true. Each page is capped
   at 200 users/400 operations in memory and per write batch; each invocation
   defaults to at most 500 users and has an absolute explicit cap of 5,000.

   ```bash
   npm --prefix functions run backfill:public-profiles -- \
     --project yovoice-ec54a --max-users 500

   npm --prefix functions run backfill:public-profiles -- \
     --project yovoice-ec54a --apply --max-users 500

   npm --prefix functions run backfill:public-profiles -- \
     --project yovoice-ec54a --start-after LAST_UID --max-users 500
   ```

   `--uid-prefix PREFIX` is available for a deliberately scoped recovery. Each
   page joins Firebase Auth before deriving a projection; a missing Auth user is
   counted as `authOrphans` and its projections are removed in apply mode.
   Source deletions after step 1 are also cleaned by `onAuthUserDeleted`.

3. **DONE 2026-08-16 — and this step is more urgent than "cleanup" implies.**
   Measured, all four phases dry-run then `--apply`, `conflicts: 0`
   throughout, `reachedEnd: true`: conversations 5/5, friendRequests 6/6,
   following 5/5, followers 5/5 — **21 documents**. A verification re-run
   reported `plannedScrubs: 0` in all four phases.

   > **Ordering warning, learned the hard way.** This step was run *after*
   > step 5, and that was a mistake with live consequences. The new rules
   > require a follow edge to carry exactly `['uid','followedAt']`, and
   > Firestore evaluates list rules **per document**, denying the entire
   > query if any single document fails. So between the rules deploy and
   > this scrub, one legacy five-key edge emptied a user's whole
   > followers/following list. The scrub is not hygiene — while rules are
   > ahead of it, it is an active outage. Run it before step 5, or accept
   > that follower lists are broken in the window between.

   No Firestore export was taken first. Stated plainly because it was a
   judgement call: the `gcloud` CLI keeps a credential store separate from
   ADC and was not logged in, and everything the scrub removes is a
   denormalized duplicate whose authoritative copy is untouched — emails
   live in `users` and Firebase Auth, and `displayName`/`photoUrl` on follow
   edges now live in `publicProfiles`. For a larger dataset, take the export.

   Run dry-run first, then `--apply`; repeat until `reachedEnd` is true. Output is
   aggregate-only, apply cursors stay in Admin-only `privateMigrationState`,
   and each invocation is bounded (500 documents by default, hard cap 5,000):

   ```bash
   for PHASE in conversations friendRequests following followers; do
     npm --prefix functions run scrub:legacy-identity -- \
       --project yovoice-ec54a --phase "$PHASE"
     npm --prefix functions run scrub:legacy-identity -- \
       --project yovoice-ec54a --phase "$PHASE" --apply
   done
   ```

   Do not blindly backfill `friendshipGuards` from legacy friend mirrors. Only
   canonical server-side acceptance may create guards. Existing mirror-only
   relationships stay fail-closed for presence until explicitly reconciled
   from trusted evidence or re-established through the normal request flow.

4. **DONE 2026-08-16, and fingerprinted.** Release Flutter/web clients that
   read `publicProfiles`, join the narrower friend-only `socialPresence`, and
   call `searchPublicProfiles`. Verify profile, friends, direct-message
   creation, search and staff-owner lookup against the populated production
   projections. Allow the required native adoption window before step 5; old
   native builds fail closed after the cutover.

   Verified by fetching the artifact, not by reading the deploy log:
   `https://app.yovoice.app/main.dart.js` is 5,139,256 bytes and contains
   `publicProfiles`, `searchPublicProfiles` and `selectMyAchievementTitle`.
   Production had been serving commit `9fdd8a9` until this release.

   **UNVERIFIED**: the native adoption window. No App Store or Play build
   carrying the new client has been confirmed released, so any native install
   predating this cutover fails closed on foreign-profile reads. Treat native
   as un-migrated until someone checks.

5. **DONE 2026-08-16.** Deploy Firestore rules last:

   ```bash
   firebase deploy --only firestore:rules --project yovoice-ec54a
   ```

   Deployed twice that day — 20:40 by the operator and 21:06 covering the
   `952d8e4` room-eviction removal — per Console → Firestore → Rules version
   history.

After step 5, only an account owner can get its own `users/{uid}` root and no
client can list it; staff tools use protected callables. Do not reverse steps 1
and 5.

## `yovoice-website` (automatic, separate repo)

Deploys to Vercel automatically on push to `main` in the
`yovoice-website` repo. Environment variables (including
`NEXT_PUBLIC_APP_URL` — see
[ADR-009](Decisions.md#adr-009-next_public_app_url-as-an-env-var-website-repo))
are managed per-environment (production/preview/development) in the
Vercel dashboard, not in this repo. See that repo's own README for its
build/deploy specifics.

## Domains

```
yovoice.app            → Vercel (yovoice-website)
auth.yovoice.app        → Firebase Hosting — shared Auth domain, live
app.yovoice.app          → Firebase Hosting — LIVE as of 2026-08-16
```

`auth.yovoice.app` remains the branded domain for Auth action links. It is not
currently the Flutter Web OAuth popup handler: Google Sign-In must use the
registered `https://yovoice-ec54a.firebaseapp.com/__/auth/handler` through the
web `authDomain` in `firebase_options.dart`. Do not switch that value back to
the custom domain unless the exact redirect is first added to the Google OAuth
client and verified with a real popup flow.

### Social sign-in release gates

- Google: confirm the Firebase Android app contains debug and release/upload
  SHA-1 plus SHA-256 fingerprints, download the resulting
  `google-services.json`, deploy the Flutter Hosting build, and verify that the
  production popup reaches Google's account chooser without
  `redirect_uri_mismatch`. Add the Google Play App Signing fingerprints before
  distributing a Play-signed build.
- Apple: the `app.yovoice.web` Service ID, dedicated Sign in with Apple key,
  enabled Firebase `apple.com` provider, `app.yovoice` capability and matching
  `YO Voice App Store` provisioning profile are configured. Production Hosting
  builds pass `YOVOICE_APPLE_SIGN_IN_ENABLED=true`; local/default builds remain
  fail-closed. After each auth release, smoke-test a real Apple account on web
  and a signed iOS build. The APNs key documented below is notification-only
  and is not valid for Apple Auth.

### TOTP two-factor release gate

Do not enable project MFA ahead of compatible Flutter and website clients. The
order is:

1. Run the TOTP enrollment/challenge suites, full `flutter analyze`, website
   tests/lint, and both production builds.
2. Verify both clients handle Firebase's `multi-factor-auth-required` resolver
   for email/password sign-in.
3. Enable Identity Platform MFA with only the TOTP provider and one adjacent
   interval; do not enable SMS implicitly.
4. Deploy Firebase Hosting and the website immediately, invalidate caches, and
   smoke-test with a dedicated account: enroll, fresh sign-in challenge on both
   clients, wrong code, correct code, removal and sign-in after removal.
5. Confirm an account without an enrolled factor still signs in normally.

If either client or smoke test fails, stop new enrollment before changing the
provider. Never disable the only resolver for already-enrolled accounts and
strand them without a separately approved recovery process.

**CORRECTION, 2026-08-16.** This block, [Roadmap.md](Roadmap.md) and
[Bugs.md](Bugs.md) all described `app.yovoice.app` as blocked on a
Cloudflare DNS record only the domain owner could add. **It is no longer
blocked.** The CNAME resolves to `yovoice-ec54a.web.app` and HTTPS returns
200; the Flutter web client was fetched from it and fingerprinted on
2026-08-16 (5,139,256 bytes).

One step remains, and it is **UNVERIFIED** — it lives in the website repo
and could not be checked from here: `NEXT_PUBLIC_APP_URL`
([ADR-009](Decisions.md#adr-009-next_public_app_url-as-an-env-var-website-repo))
must be flipped to `https://app.yovoice.app` in **all three** Vercel
environments (production, preview, development — easy to update one and
forget the others), then redeployed, then the redirect verified
end-to-end rather than assumed from the env var change. Until someone
confirms that, treat the website as still pointing at the default
`web.app` domain.

## Global Chat

Global Chat needs **no manual Firestore Console step**. The canonical
channel is `globalChat/main/messages`; Firestore addresses a
subcollection independently of its parent, so the `globalChat/main`
document does not have to exist and is never created — by anyone. The
channel id is pinned to `main` inside `firestore.rules`, and clients are
denied `write` on `globalChat/{channelId}` entirely, so no second
"global" channel can be stood up either. A rules test asserts the
channel works with the parent document absent.

Shipping it is therefore the ordinary two deploys:

```bash
firebase deploy --only firestore:rules
firebase deploy --only functions:onGlobalMessageModerated
```

The trigger is what writes an `adminAuditLogs` entry when a moderator
removes someone else's message. Rules alone cannot log, so skipping the
functions deploy means moderator removals happen with no audit trail.

## Staff Moderation Center

Three targets, and the index must land before the queue is opened or
its first query fails:

```bash
firebase deploy --only firestore:indexes
firebase deploy --only firestore:rules
firebase deploy --only functions:moderateReport
```

No Console step and no data migration: `reports` gained workflow fields,
and a report without them is treated as Open by both the client model
and the Function. Staff access needs a role assigned through the
existing `assignUserRole` flow — it writes both the custom claim and the
`users/{uid}.role` mirror that rules check.

Note the claim propagation direction: a newly promoted moderator sees
the Moderation entry once their ID token refreshes (sign out and in
forces it), while a REVOKED moderator loses access on their next
request, because the server record is checked too.

## Production state as of 2026-08-16 (post-cutover)

Everything in this section was **read from the live project**, not inferred
from filenames or from what the repo happens to contain:

```bash
firebase functions:list --project yovoice-ec54a
firebase firestore:indexes --project yovoice-ec54a
firebase hosting:channel:list --project yovoice-ec54a
curl -s https://app.yovoice.app/main.dart.js | wc -c   # fingerprint the client
```

| Target | State | Evidence |
|---|---|---|
| Cloud Functions | **111 deployed** (was 51) | `firebase functions:list`. The ~60 new ones are the whole ADR-054 privacy layer (`onUserPrivacySourceChanged`, `searchPublicProfiles`, `onAuthUserDeleted`), every social-graph callable (`setFollow`, `sendFriendRequest`, `setUserBlock`, …), every `onAchievement*` trigger, the club and room self-service callables, and the entire Stage B set from `c1d6cd9`. `functions/index.js` names 87 exports directly and adds the rest via `Object.assign(exports, createStageBFunctions())` |
| Firestore indexes | **15 composites, 3 fieldOverrides** (was 14 / 1). Re-read 2026-08-17: still 3, and all three declare `COLLECTION_GROUP` scope *only* — see the [indexing trap](Firebase.md#a-fieldoverrides-entry-replaces-automatic-single-field-indexing) | `firebase firestore:indexes` |
| `firestore.rules` | **Deployed twice on 2026-08-16** — 20:40 by the operator, 21:06 covering `952d8e4` | Console → Firestore → Rules version history. *(This row said "still no read-only CLI command; the Console remains the only way to check" until 2026-08-17. The Firebase Rules API returns the full deployed source — see [Reading the deployed ruleset](#reading-the-deployed-ruleset-the-verification-standard).)* |
| `storage.rules` | **Deployed** | includes `validClubImageUpload()` accepting the timestamped `{kind}_{millis}.{ext}` names the shipped client actually writes |
| Hosting (Flutter web) | **Deployed and fingerprinted** | `https://app.yovoice.app/main.dart.js` is 5,139,256 bytes and contains `publicProfiles`, `searchPublicProfiles`, `selectMyAchievementTitle`. Production previously served commit `9fdd8a9` |
| `publishPublicStatsSchedule` | **Committed (`cb4651a`), deliberately NOT deployed** | absent from `functions:list`; three preconditions in that commit message |
| `receiveLiveKitAchievementWebhook` | **Not deployed, and not deployable** | exists in `functions/achievements/livekit_http.js`, never exported from `functions/index.js` |

**The index deploy fixed a live defect.** `entitlements(isPremium,
currentPeriodEnd)` backs the scheduled `expirePremiumIdentity` query at
`functions/premium/entitlements.js:163`. It had never been deployed, so
every run failed on the missing composite index and **Premium never
expired for any account**. No suite could have caught it: the emulator
does not require composite indexes.

### Changes since — 2026-08-17

| Target | State | Evidence |
|---|---|---|
| `firestore.rules` | **Deployed, covering `c75720a`** (account-status gating on four room write paths) | The released ruleset source was fetched through the Firebase Rules API and diffed against `firestore.rules` at HEAD: **byte-identical**. This is stronger evidence than the version-history timestamp used on 2026-08-16 |
| Hosting (Flutter web) | **Deployed from `6ef4380`** — the first build in which recording works on web at all | Released before the accessibility and visual reviews returned; see the note below |
| Hosting — does production carry `cefa81a`? | **YES, verified 2026-08-17** | Fingerprinted, not inferred from deploy output: the served `https://app.yovoice.app/main.dart.js` is 5,159,938 bytes, byte-for-byte the size of the local `build/web/main.dart.js`, and contains `No sound detected`, `No microphone was found` and `Discard this take` — three strings that exist only in `cefa81a`. The accessibility and visual fixes are live |
| Cloud Functions, indexes, `storage.rules` | **Unchanged in production since 2026-08-16** | No `functions/`, index or Storage-rules deploy happened in either 2026-08-17 round |
| `firestore.indexes.json` vs production | **A gap opened here and closed the next day.** `invites.inviteeId` was added to the file by `84d1feb` (2026-08-17 07:44) *after* that day's production reading, so for a day the repo was one `fieldOverrides` entry ahead of production while `84d1feb` was fixing a production defect. The 2026-08-18 index deploy landed it | A live `firebase firestore:indexes` read on **2026-08-19** returned **19 composites, 4 fieldOverrides** — identical to the repo file, `invites.inviteeId` included. The lesson stands: a superset file is by design, but committing an index that fixes a production defect is not the same as deploying it |

**A process failure worth recording plainly.** The web client was deployed
from `6ef4380` *before* the accessibility and visual reviews returned, on
the reasoning that recording was totally broken and a working screen with
defects beats no screen. That reasoning holds and the deploy was not
reverted — but **both reviews came back FAIL**, and waiting would have put
the fixed version in users' hands directly instead of shipping a screen
that announced a success-sounding line on a failed publish. The rule going
forward, and it is a rule and not a suggestion: **for a UI change, review
precedes deploy, exactly as it does for rules.** Recorded as
[ADR-059](Decisions.md#adr-059-a-ui-change-is-reviewed-before-it-is-deployed-on-the-same-terms-as-a-rules-change).

### The ordering lesson, restated because it changed direction

Until `409c7ee`, pushing to `main` published Hosting, so the *client* was
always ahead of the backend and this document's standing advice was
"sequence the backend first, the client ships itself." **That is no longer
how this repo behaves.** Hosting is now a manual `workflow_dispatch`, and
the failure it produced instead is the opposite one: `main` moved through
ADR-051 → ADR-054 while production kept serving commit `9fdd8a9`, and
~60 Cloud Functions sat deployed and *inert* because no client called
them. A deployed function that nothing invokes looks identical, in every
console, to a working one.

Two rules that survive both directions:

1. **Order by what fails closed.** Deploy the thing whose absence is a
   silent no-op before the thing whose absence is a denial. Functions and
   projections first, clients next, restrictive rules last.
2. **Verify by fingerprinting the served bytes, never by trusting deploy
   output.** `firebase deploy` reporting success means the upload
   succeeded. Fetch the artifact and grep it for a symbol that only exists
   in the new build — `curl -s https://app.yovoice.app/main.dart.js | grep
   -c searchPublicProfiles`. Same for Functions: `functions:list` is the
   evidence, not the deploy log.

Full decision:
[ADR-055](Decisions.md#adr-055-the-2026-08-16-production-cutover--order-the-deploy-by-what-fails-closed-and-verify-by-fingerprinting-served-bytes).

### Deliberately held back: `publishPublicStatsSchedule`

Committed in `cb4651a`, **not deployed**, and it should stay that way
until three things are true. Do not sweep it into the next
`--only functions` deploy without reading this:

1. `publicStats/live` needs `allow read: if true; allow write: if false`.
   That would be the project's **first publicly readable document** —
   grepping `firestore.rules` for `if true` currently returns nothing — so
   it needs its own ADR and its own emulator coverage first.
2. The live count needs a `COLLECTION_GROUP` index on `rooms.expiresAt`,
   or the first run throws `FAILED_PRECONDITION`. (Compare the
   `expirePremiumIdentity` defect above — this is the same failure mode,
   known in advance this time.)
3. **The data source is known to be wrong.**
   `activeVoiceSessions.expiresAt` is a token-issuance TTL, written once at
   join and never renewed, and nothing removes a row when a client
   crashes. Counting by freshness drops everyone who has been in a room
   longer than five minutes — a full room reports zero — while counting
   without it reports ghosts forever. What it would publish today is an
   honest lower bound, not a measurement.

The real fix is the same unexported webhook that would repair
`voiceMinutes`: `receiveLiveKitAchievementWebhook` in
`functions/achievements/livekit_http.js`, whose sessions are closed by
LiveKit's own `participant_left` / `participant_connection_aborted`
events, which the SFU emits on a crash.

### Pending release: consent-backed public showcase

`publicShowcase/live` is a separate pinned, server-owned projection for the
marketing website. It must never be populated by widening reads on
`users`, `publicProfiles`, `socialPresence`, `clubs`, or either consent
collection. The publisher revalidates Auth existence, account status,
ordinary-user role, profile/Club state and explicit owner consent, and emits
only bounded names, account type, an honest coarse activity label and Club
name/member count. It emits no uid, username, email, image URL, staff badge,
last-seen time, owner id or Club id.

Safe release order:

1. Deploy `publishPublicShowcaseSchedule` and verify it is ACTIVE.
2. Deploy `firestore.rules`; verify anonymous GET of exactly
   `publicShowcase/live` and denial of list/siblings/client writes.
3. Release the Flutter consent controls. Absence of consent is the safe
   default, so the publisher legitimately emits empty arrays until people
   explicitly opt in.
4. Release the marketing website consumer last. It must hide an invalid or
   expired payload and show the neutral sign-up CTA; fixtures and fabricated
   fallback identities are prohibited.

The one-minute publisher uses a three-minute document TTL and fails closed
when its bounded consent scan is exceeded. Scale that scan with a reviewed
pagination/fair-sampling design before raising the current cap; never silently
publish a partial cohort. Removing an account/Club or transferring Club
ownership deletes its grant server-side.

### RELEASED 2026-08-20: the reachability wave

`3d54bc3` → `8aabc07`. **This wave is deployed.** The section below was
written while it was still pending; the manifest is kept because it explains
what each artifact was for, but every "Absence today" cell describes the
state BEFORE this release, not now.

**What was deployed, in this order, and how each was verified:**

| Artifact | Command | Verification |
|---|---|---|
| `firestore.rules` | `firebase deploy --only firestore:rules` | Read back through `firebaserules.googleapis.com` and compared to the working tree: **byte-exact** (sha256 `7306fe2b3a9a537f`). 10 `deletionInProgress` guards present in the deployed ruleset |
| Cloud Functions | `firebase deploy --only functions` | All updated; `leaveRoomSelf` and `endRoomVoiceSelf` re-deployed individually and confirmed as v2 callables in `europe-west1` |
| `firestore.indexes.json` | `firebase deploy --only firestore:indexes` | The two Moments composites (`isPublished`+`createdAt` desc, `isPublished`+`likeCount` desc) accepted; **both were still `CREATING` at deploy time** — see the caveat below |
| Flutter web | `flutter build web --release` + `firebase deploy --only hosting` | Deployed `main.dart.js` fetched from `https://yovoice-ec54a.web.app` and compared to the local build: **byte-exact** (sha256 `8cbaae85b1584a9e`, 5,969,115 bytes). App loads, login screen renders, **zero console errors** |

**Rules were deployed BEFORE Functions**, deliberately: the rules change is
tightening-only, so nothing permitted under the old ruleset became newly
permitted, whereas the reverse order leaves a window in which a stale client
can still flip `isLive` on a deleting room.

**Before deploying rules, both message-create allowlists were checked against
the code the deployed client actually runs** — this was the one ordering
decision in the wave that could have turned working sends into denials.
`RoomService.sendRoomMessage` writes exactly the six allowlisted keys and
resolves `senderName` from `users/{uid}.displayName` byte for byte (the same
document `displayNameMatchesCanonical` compares against), and its write shape
last changed in `714946b`, long before this wave. `ClubChatService` writes
nine keys, all within its allowlist, with `isDeleted: false` and
`editedAt: null`. Neither allowlist refuses anything the shipped client sends.

**UNVERIFIED, and it matters.** No production round trip was performed for
room voice: signing in requires entering a password, which the operating
agent does not do. Every claim about rooms rests on 1052 Flutter tests, 709
Functions tests, 471 rules cases and 61 inspected screenshots — not on a real
LiveKit session. **The first person to sign in should enter a dormant room
they host and press Start voice.**

**Post-deploy production read (read-only, Admin SDK, 2026-08-20).** 45 rooms:

| Measure | Count | What it settles |
|---|---:|---|
| missing `status` | 25 / 45 | The `.get(field, default)` form in `roomVoiceStartAllowed()` is **required**, not stylistic. A bare `resource.data.status` read would deny the majority of live production rooms |
| missing `roomType` | 24 / 45 | same |
| missing `experience` | 27 / 45 | same |
| missing `hostId` | 0 / 45 | Every room has an owner who can start and end it |
| `isLive: true` | 3 | |
| `isLive: true` with `participantCount: 0` | **0** | No stuck-live rooms exist right now, so the generalised teardown ships with a clean slate rather than a backlog to sweep |
| `deletionInProgress: true` | 1 | The new guard is not hypothetical — there is a real room it now refuses to reanimate |
| `membersCanStartVoice: true` | 3 | The member-start branch is genuinely reachable, which is what made the missing teardown a real defect rather than a theoretical one |
| lounges with the `club_lounge_` prefix but no `clubId` FIELD | **0** | All 3 club lounges carry the field, so resolving Club start authority from `storedClubId` costs nothing in production while removing the mismatch class |

This is the evidence the emulator could not supply: the fixtures were designed
around a legacy shape, and the legacy shape is in fact the majority.

**The two Moments indexes were still building when this was written.** Until
both report `READY`, the Moments discovery feed throws `FAILED_PRECONDITION`
exactly the way club invites did. Check with:

```
gcloud auth application-default print-access-token
curl -H "Authorization: Bearer $TOKEN" \
  "https://firestore.googleapis.com/v1/projects/yovoice-ec54a/databases/(default)/collectionGroups/moments/indexes"
```

What is waiting, and what each piece is:

| Artifact | Change | Absence today |
|---|---|---|
| `firestore.indexes.json` | Two composites for the Moments discovery feed: `isPublished`+`likeCount` desc and `isPublished`+`createdAt` desc (`cef05e6`). The repo file now holds **21 composites, 4 fieldOverrides**; the last production read, 2026-08-19, returned **19 and 4**, so the file is exactly these two ahead | The feed's queries throw `FAILED_PRECONDITION` on first run. The emulator does not require composite indexes, so no suite can catch this — same failure mode as `expirePremiumIdentity` |
| Cloud Functions | `createContentReport` only (`2c086c7`): email-verification gate relaxed, `roomMessage`/`clubMessage` targets added, access checked before existence, optional bounded `note` | Reporting stays verified-only, room/club messages stay unreportable, and the endpoint stays an existence oracle |
| `firestore.rules` | 403 → 446 → **466**: club chat moderation with disjoint branches and a create allowlist (`b3c27fd`), room chat write validation and the `clubs` `list` rule (`01c0ab2`) | Club owners cannot remove abusive messages; room chat stays forgeable; club discovery stays denied for everyone |
| Hosting (Flutter web) | Room voice liveness (`b0f1062`), reporting UI (`9f3ce7f`), Moments as a primary destination (`cef05e6`), club moderation UI (`b3c27fd`/`f817b41`), sign-out cleanup (`3d54bc3`), club-discovery rail states (`155ad61`) | Voice does not work in any Community room or lounge; nothing is reportable; a signed-out account stays online to its friends |

**Release blockers — these are gates, not cautions.**

1. **CLEARED before the Hosting release.** This gate read "the club
   moderation UI (`f817b41`) and the Moments destination and feed
   (`cef05e6`) have never been rendered". Half of that was already stale
   when written, and the other half was closed before deploying:

   - **Club moderation UI — was already rendered.** 44 frames exist under
     `test/.screenshots/clubchat/` from the visual specialist's pass, across
     390/1440/2560 at 1.0x/1.3x/2.0x/3.0x text. The removal-confirmation
     dialog was re-inspected at 390: long author names truncate, role badges
     render, the destructive action is clearly separated from Cancel.
   - **Moments — genuinely had no rendering, and now has one.**
     `test/moments_discovery_screenshot.dart` (commit `8aabc07`) photographs
     loading, empty, error, populated and long content at 390/768/1100/1440,
     plus 2x text. 16 frames, inspected. The desktop composition carries a
     real side list rather than a stretched phone layout, and the empty state
     states plainly that nobody has published one — no fabricated activity.

   Room voice was never blocked: 45 screenshots at 320/390/768/1100/1440 and
   200% text, with the real typeface, were rendered and inspected.
2. **Room voice has had no round trip of any kind.** Rules were read, not
   executed; `fake_cloud_firestore` evaluates no rules, so every "the client
   may start voice" test proves the client's mirror of the rule and not the
   server's answer. Before or immediately after the Hosting release,
   `startRoomVoice`'s three-key liveness update must be exercised against the
   emulator or a real account. No real LiveKit connection, device run,
   reconnect or device-routing check has happened.
3. **Confirm the deployed client's payloads against the two new create
   allowlists before deploying rules.** The room-message rule now demands an
   exact six-key document and the club-message rule an exact shape. If the
   client currently in production writes anything else, the rules deploy
   turns working sends into permission denials. This is the one ordering
   decision in this wave that can break a live surface.

**Order.** ADR-055's rule still applies — deploy the thing whose absence is a
silent no-op before the thing whose absence is a denial:

1. **Indexes first.** They build asynchronously and the discovery feed's
   first query fails until they are READY. Watch Console → Firestore →
   Indexes and wait for Enabled.
2. **`createContentReport`.** Its absence is a no-op for every existing
   client, and the new client cannot report anything until it is live.
   Verify with `firebase functions:list`, not the deploy log. The
   idempotency-hash change is backward compatible **by construction** — new
   fields fold into the ledger hash only when the target carries them, pinned
   by a regression test that recomputes the legacy hash
   ([ADR-087](Decisions.md#adr-087-an-idempotency-key-derived-from-a-request-payload-is-a-compatibility-surface--new-fields-fold-in-only-when-the-target-carries-them)) —
   so reports already filed in production keep replaying rather than
   answering `already-exists`.
3. **Blocker 3 above**, then **`firestore.rules`** against a freshly started
   emulator (466 checks), then deploy. Verify by fetching the released
   ruleset through the Firebase Rules API and diffing it byte-for-byte
   against `firestore.rules` at HEAD — the standard set on 2026-08-17, which
   is stronger than a version-history timestamp. The `clubs` `list` widening
   is safe in either order (it is currently `if false`, so no client can be
   relying on it); the two create allowlists are the restrictive half.
4. **Hosting**, once blocker 1 is cleared. Fingerprint the served bytes
   rather than trusting the deploy output: `curl -s
   https://app.yovoice.app/main.dart.js` and grep for a symbol that exists
   only in this build.

**Verification that will still be outstanding after a clean deploy**, and
should be stated as such rather than assumed:

- Presence actually flipping when a user signs out — needs two real accounts
  on two devices (`3d54bc3`).
- Voice actually connecting in a Community room, and a room's liveness
  transition being accepted by the deployed rules (`b0f1062`).
- The Moments empty state at any width — the state most users on a
  pre-launch product will hit (`cef05e6`).
- The Moderation Center's handling of a v2 report. It is known to render one
  badly today: `targetType` parses to null so the queue title is blank, and
  `reportedUserId` defaults to empty so the detail pane says "This account no
  longer exists". That is a **client-side defect this wave introduces the
  data for**, and it lands the moment `createContentReport` is deployed and a
  v2 report is filed. See Roadmap item 0o — it is a reasonable argument for
  fixing the queue in the same release.

---

## Historical: the 2026-08-11 selective manifest (SUPERSEDED)

> **Superseded 2026-08-16.** Everything listed below is now deployed —
> `moderateReport`, `listReportAuditTrail`, `setUserBan`, the three social
> notification triggers, and all five `reports`/`adminAuditLogs` indexes.
> The **inventory** is obsolete; the **ordering reasoning and the rollback
> rules** below are still correct and still worth reading before any
> multi-target deploy. Kept for that reason rather than deleted.
>
> Note also that the "Hosting is ahead of the backend / pushing to `main`
> auto-deploys the web app" premise this section was written on stopped
> being true in `409c7ee` — see the corrected ordering lesson above.

### Cloud Functions — the complete selective list

Derived from `functions/index.js` exports, not from file names. Both
undeployed milestones are covered:

| Function | Why | Source |
|---|---|---|
| `moderateReport` | new export, never deployed | `functions/moderation/reports.js` (`1e76d36`) |
| `listReportAuditTrail` | new export, never deployed | `functions/moderation/report_audit.js` (this commit) |
| `onGlobalMessageModerated` | deployed, but its module changed | `functions/moderation/global_chat.js` (`24353d4`) |
| `setUserBan` | deployed, but now revokes refresh tokens on ban | `functions/admin/users.js` (`24353d4`) |
| `onFriendRequestCreated` | new export — friend-request notifications do not exist without it | `functions/notifications/social.js` (ADR-041) |
| `onFriendRequestResolved` | new export — acceptance notifications do not exist without it | `functions/notifications/social.js` (ADR-041) |
| `onFollowerCreated` | new export — follow notifications do not exist without it | `functions/notifications/social.js` (ADR-041) |

`functions/utils/audit.js` also changed — `writeAuditLog` gained an
optional `entryId` for deterministic, replay-safe audit ids. Its other
callers (`admin/clubs.js`, `admin/rooms.js`, `clubs/ownership.js`) pass
no `entryId` and keep the previous `.add()` behaviour exactly, so the
functions exported from those modules do **not** need redeploying. They
will pick the new util up whenever they are next deployed for their own
reasons.

Deploy them by name. A blanket `--only functions` would also redeploy 29
functions that did not change:

```bash
firebase deploy --only functions:onGlobalMessageModerated,functions:setUserBan,functions:moderateReport,functions:listReportAuditTrail,functions:onFriendRequestCreated,functions:onFriendRequestResolved,functions:onFollowerCreated --project yovoice-ec54a
```

All three notification triggers are v2 Firestore document triggers,
`europe-west1`, nodejs22, matching every other function in the project.
They are additive: deploying them before the client is safe, because the
client no longer writes these notifications and the triggers do not
depend on any client change.

**The one ordering constraint that can cause an outage**: the rules
change in this milestone REMOVES `friendRequest`, `friendAccepted` and
`follow` from the client-creatable notification types. Deploying rules
before the Functions would leave a window in which the client is denied
and no trigger exists yet — no social notifications at all. Functions
first, always.

### Firestore indexes

Five new composite indexes, each tied to a query that exists:

| Index | Query that needs it |
|---|---|
| `reports (status, createdAt DESC)` | the unfiltered queue |
| `reports (status, targetType, createdAt DESC)` | queue + target filter |
| `reports (status, reason, createdAt DESC)` | queue + reason filter |
| `reports (status, targetType, reason, createdAt DESC)` | queue + both filters |
| `adminAuditLogs (targetType, targetId, createdAt DESC)` | both scoped queries inside `listReportAuditTrail` |

`firestore.indexes.json` also regained `rooms (isLive, visibility,
createdAt DESC)`, which exists in production but had drifted out of the
file. It backs `RoomService.watchLivePublicRooms()` — the Home live-rooms
list. Keeping the file a superset of production means an index deploy can
never be the thing that removes it.

### Recommended order

Backend first, client last, and the audit trigger before anything that
lets a moderator remove content — otherwise removals happen in a window
where nothing records them.

```bash
# 1. Indexes first: they build asynchronously and the queue's first
#    query fails until they are READY. Watch Console → Firestore →
#    Indexes and wait for Enabled before step 4.
firebase deploy --only firestore:indexes --project yovoice-ec54a

# 2. The audit trigger, so a removal can never be unlogged, plus the
#    three social notification triggers. These MUST precede the rules
#    deploy in step 3, which withdraws the client's ability to write
#    those notification types.
firebase deploy --only functions:onGlobalMessageModerated,functions:onFriendRequestCreated,functions:onFriendRequestResolved,functions:onFollowerCreated --project yovoice-ec54a

# 3. Rules: staff read access to `reports`, the create-only report path,
#    and `adminAuditLogs` denied to every client.
#    Run the emulator suite against a FRESH emulator first.
cd firestore-tests && npm test && cd ..
firebase deploy --only firestore:rules --project yovoice-ec54a

# 4. The privileged callables.
firebase deploy --only functions:moderateReport,functions:listReportAuditTrail --project yovoice-ec54a

# 5. Immediate ban revocation.
firebase deploy --only functions:setUserBan --project yovoice-ec54a

# 6. The client. Already live via CI in this case — redeploy only if a
#    newer build needs to ship:
flutter build web --release && firebase deploy --only hosting --project yovoice-ec54a
```

Then verify with a real staff account: the queue loads, each filter
combination returns without a `FAILED_PRECONDITION`, one claim/release
round trip succeeds, and the audit timeline shows that action. Watch
Console → Functions → Logs for permission denials and errors on the four
functions, and Firestore usage for index-missing errors.

### Rollback, and what must never be deleted

Reversible by redeploying the previous revision from git history:

- **Functions** — `git checkout <previous-commit> -- functions/` then
  redeploy the same named list. Cloud Run keeps previous revisions, so a
  bad deploy can also be rolled back per function in the Console.
- **Rules** — `git checkout <previous-commit> -- firestore.rules` and
  redeploy. Rulesets are versioned in Console → Firestore → Rules with a
  history view.
- **Hosting** — previous releases are promotable from the Console.

**Not reversible, and not to be "cleaned up" during a rollback:**

- `adminAuditLogs` entries. They are the record of who did what, they
  are append-only by design, and deleting them to tidy a failed deploy
  destroys the only evidence a moderation decision ever happened.
- `reports` documents. Reporter evidence is immutable by rule; a
  rollback must not delete or rewrite it. Workflow fields (`status`,
  `assignedTo`, `resolution`) may legitimately move forward again after
  a redeploy.
- Soft-deleted Global Chat messages (`isDeleted: true` with the original
  text retained). The retained text IS the audit evidence.

Removing an index is safe but not instant to rebuild; removing a
Function only makes its clients fail, it destroys nothing. Note that
editing a `fieldOverrides` entry can *remove* indexes without looking
like a removal in the diff — see the
[indexing trap](Firebase.md#a-fieldoverrides-entry-replaces-automatic-single-field-indexing).

## Web push configuration (required before web push works)

`web/firebase-messaging-sw.js` is in the repository and is copied into
`build/web` by `flutter build web`. The remaining prerequisite is the
**VAPID public key**. The production key is included in the Hosting build
command because it is public client configuration (the private half remains
inside Firebase):

- **Where to get it**: Firebase Console → Project settings → Cloud
  Messaging → Web configuration → *Web Push certificates*. Use the
  **public** key of the key pair.
- **Where to supply it**: as a build-time define:

```bash
flutter build web --release --dart-define=YOVOICE_WEB_PUSH_VAPID_KEY=THE_PUBLIC_KEY
```

  The Hosting CI workflow already supplies the production public key, so
  builds from `main` ship with web push enabled. Local release builds must
  pass the same define when they are intended for deployment.
- **Behaviour without it**: the app skips web push setup entirely — it
  does not request notification permission (a browser only grants that
  prompt once), does not call `getToken()`, and writes no token. It logs
  one line saying why. The in-app activity feed, badge, iOS and Android
  push are all unaffected.

Android's default notification channel is declared in
`AndroidManifest.xml`. The production iOS app is registered as
`app.yovoice` under Apple Team `C3R59P53KB`, and its Firebase app ID is
`1:80235878542:ios:0b3303647c76596a1351df`. APNs key `3288VCBHFD` is
uploaded in Firebase for both Development and Production. The private
`.p8` is intentionally outside the repository in the operator secret
backup (`~/Documents/YO Voice Secrets/AuthKey_3288VCBHFD.p8`) and cannot
be downloaded from Apple a second time. `remote-notification` is enabled
in `UIBackgroundModes`.

App Store releases use manual signing for the Release configuration with
the `YO Voice App Store` provisioning profile (UUID
`1a59a340-37ab-43a5-bdb2-bdc29d60600d`, expires 2027-08-15), Apple
Distribution, and `ios/ExportOptions.plist`. Build an uploadable IPA with:

```sh
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
```

The App Store Connect record is `YO Voice` (Apple ID `6801898909`). To upload
an already-built archive directly to App Store Connect/TestFlight, run:

```sh
xcodebuild -exportArchive \
  -archivePath build/ios/archive/Runner.xcarchive \
  -exportPath build/ios/app-store-upload \
  -exportOptionsPlist ios/ExportOptionsUpload.plist
```

The matching distribution private key, certificate, CSR, and provisioning
profile are intentionally stored outside the repository under
`~/Documents/YO Voice Secrets/`. Keep that directory backed up securely;
without the private key this Mac cannot use the distribution certificate.

## App Check rollout (not enabled — staged plan)

App Check enforcement is **off** on every Cloud Function
(`enforceAppCheck: false`) and not enabled for Cloud Firestore. That is
deliberate: turning it on before clients reliably produce valid tokens
locks out real users. See
[ADR-004](Decisions.md#adr-004-firebase-app-check-integrated-client-side-enforcement-deliberately-off).

What App Check does and does not do: it attests that a request comes
from a genuine instance of **your** app, which raises the cost of
scripted abuse against a public surface like Global Chat. It is **not**
authentication, and it replaces none of the layers that actually
authorize: Firebase Auth, Firestore rules, the account-status check,
moderation, or the rate limits. A stolen token from a real client still
passes App Check.

Stages, in order — do not skip ahead:

1. **Register every legitimate app variant** in the Firebase Console:
   Flutter web (reCAPTCHA Enterprise, on every origin that serves the
   app, including preview channels), iOS (App Attest, with DeviceCheck
   as the fallback for older OS versions), and Android (Play Integrity)
   if and when those ship. A variant that is not registered is a variant
   that gets locked out at step 4.
2. **Ship clients that mint tokens.** Activate App Check at startup
   before any Firebase call, release, and wait for meaningful adoption —
   old installs keep running until users update, and their requests will
   count as "outdated" below.
3. **Monitor**, in Console → App Check → Metrics, per service (Firestore
   and each Function). Four buckets matter: *verified* (good),
   *outdated client* (real users on old builds — must fall to near zero
   before enforcing), *unknown* (usually an unregistered origin or a
   platform you forgot), and *invalid* (either abuse, or a
   misconfiguration). Watch for at least one full release cycle so
   weekly-active users are represented, not just daily-active ones.
4. **Enable enforcement**, Firestore first, then Functions one at a
   time, starting with the least critical. Global Chat's send path is
   pure Firestore, so Firestore enforcement is what covers it.
5. **Rollback and debug tokens.** Enforcement is a Console toggle and
   takes effect within minutes — turning it back off is the rollback,
   and it should be the immediate response to any spike in denied
   requests from real users. For local development and CI, register
   **debug tokens** per machine rather than disabling enforcement;
   treat a debug token as a credential (it bypasses attestation), never
   commit one, and revoke it when the machine or contributor changes.

## Rollback

There's no automated rollback pipeline for any of the four manual deploy
targets above. For Hosting, Firebase keeps previous release versions
browsable/promotable from the Firebase Console. For Firestore
rules/indexes and Cloud Functions, the practical rollback is redeploying
the previous version from git history (`git checkout <previous-commit> --
firestore.rules && firebase deploy --only firestore:rules`, or the
equivalent for `functions/`) — there's no one-command "undo the last
deploy." This is a real gap for a project this project's size to not have
yet; worth building out if a bad rules or functions deploy ever actually
happens in production.

**Corrected 2026-08-17 — a rules rollback artifact now exists.** The
paragraph above described git history as the only source for a previous
ruleset, which assumes the repository and production agree. They do not
always: production served commit `9fdd8a9` while the tree was far ahead,
as the 2026-08-16 cutover found. Snapshot the *live* source with the
Firebase Rules API before every rules deploy
([above](#reading-the-deployed-ruleset-the-verification-standard)) and
keep the file until the deploy is verified. That snapshot is what a
rollback should restore, because it is what was actually running.

## Environment configuration

Firebase project config (`yovoice-ec54a`) is baked into
`lib/firebase_options.dart`, generated via `flutterfire configure` and
already committed — there's no separate staging/production Firebase
project today. Every environment (local dev, CI, production) talks to the
same live Firebase backend. This is a real risk worth naming: there is no
sandboxed environment for trying a risky change against real
infrastructure short of the Firestore emulator (rules only) — see
[Bugs.md](Bugs.md) and consider this a candidate for a future "add a
staging Firebase project" decision if the team or user base ever grows
enough to justify the added complexity.

## Stripe Premium rollout (blocked; no live mutations performed)

Do not deploy billing until seller/VAT/refund/dispute decisions are approved.
Then roll out in this order:

1. In live Stripe create one Premium Product and two recurring PLN Prices:
   1999/month and 19999/year, both `tax_behavior=inclusive`. Do not add manual
   `currency_options`; this implementation uses Checkout Adaptive Pricing.
2. Configure Stripe Tax registrations/business identity and verify the final
   customer receipt/invoice wording. Tax ID collection remains off until a B2B
   policy exists.
3. Create one active Customer Portal configuration. Enable cancellation and
   Price updates; allow exactly both Prices on the same Product. Verify both
   have the identical inclusive tax behavior.
4. Set Firebase parameters `STRIPE_MONTHLY_PRICE_ID`,
   `STRIPE_YEARLY_PRICE_ID`, `STRIPE_PORTAL_CONFIGURATION_ID` and
   `STRIPE_EXPECTED_MODE=live`; set Secret Manager values
   `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET`. Never point
   `yovoice-ec54a` at test mode.
5. Deploy Firestore Rules first (operational billing collections are denied to
   clients), then only the billing Functions plus Auth-deletion cancellation,
   then clients. Register the live Stripe webhook endpoint for Checkout
   completed/async succeeded/async failed, Subscription lifecycle and Invoice
   paid/payment failed events, plus `charge.refunded` and
   `charge.dispute.created`.
6. Smoke with a new disposable account: monthly Checkout in PLN and a Stripe-
   localized country, paid entitlement, Portal monthly→yearly, cancel-at-period
   end showing `ends`, cancellation, failed payment, webhook replay, suspended
   payer Portal access, and Auth deletion canceling the subscription. Confirm
   no duplicate Customers/subscriptions and no recreated deleted `users` doc.
   Send signed test events for a full refund (access revoked, all subscriptions
   canceled), partial refund (access preserved, support review recorded), and
   dispute creation (access revoked).
7. Reconcile Stripe subscriptions against `billingAccounts` and
   `entitlements`; every Stripe Customer must map to exactly one uid, every
   active entitlement must have a paid canonical latest Invoice, and all event
   failures must be retried to a `stripeWebhookEvents` receipt.

Predeploy gates:

```bash
node --check functions/premium/stripe_billing.js
node --test functions/test/stripe_billing.test.js
firebase emulators:exec --only firestore --project demo-yovoice \
  "node firestore-tests/rules.test.js"
```

Rollback: disable new Checkout entry points first, keep Portal and webhook
available so existing payers can cancel, restore the prior Functions/rules
from the predeploy snapshot, and continue processing signed provider events.
Do not delete `billingAccounts` or webhook receipts; they are required for
reconciliation, refunds and replay. Stripe Product/Prices should be archived
only after no active subscription references them.
