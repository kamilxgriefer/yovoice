# Backend release, tester outage repair and build 30 — 2026-09-16

## Status

**Four separate things happened in one evening, and they carry four different
levels of proof. Read the level before repeating the claim.**

- **Deployed and independently verified.** The Servers media-collaboration
  backend from `e1a9f3cd`: the Firestore Rules delta and 98 package-selected
  Functions targets, production 241 → 242 ACTIVE.
- **Repaired in production, unconfirmed by a client.** A two-day outage in which
  publishing a Yeel or a Voice Moment, the Voice Moments feed and starting a new
  chat were 100 % dead for every account. Sixteen functions redeployed from
  `22cc2313`; the missing `serverInviteRefs.expiresAt` collection-group index
  declared, deployed and READY. **No signed-in client has exercised the repaired
  paths since**, so the success metric is UNOBSERVED, not passed.
- **Released.** Google Play build 29 published to the internal track at 22:41
  CEST by the owner; a console read-back on 2026-09-17 confirmed it.
- **Built and delivered.** Build 30 (`2.0.0+30`, from `121973fc`): Android AAB
  and iOS archive/IPA verified by identity; the AAB uploaded and Play internal
  release 30 published (~01:26 CEST, 2026-09-17); the IPA upload succeeded and
  App Store Connect shows build 30 `VALID` in both TestFlight groups
  (`externalBuildState IN_BETA_TESTING`). The web client of the same revision
  **is** live on Hosting.
- **Update 2026-09-17 (observed, passed).** A signed-in owner client on the
  iPhone 17 Pro simulator exercised the repaired paths. Chats:
  `sendDirectMessage`, `setDirectMessageReaction`, `editDirectMessage`,
  `deleteDirectMessage`, and a GIF sent then deleted — 19 authenticated
  callables, all HTTP 200 (23:15–23:28 UTC, 2026-09-16). Publishing:
  `reserveMomentDraft`/`finalizeMomentDraft` 200 at 01:17 UTC and
  `reserveReelDraftV2`/`finalizeReelDraftV2` 200 at 01:20 UTC on 2026-09-17;
  both test items appeared in their feeds and were deleted in-app
  (`deleteMoment`/`deleteReel` 200). Zero non-2xx responses in the window.
  Evidence: `yovoice-evidence/2026-09-17/repair-device/` (`publish-report.md`,
  `publish-logs.json`, `session-full.json`). Still unobserved:
  `openDirectConversation` for a brand-new pair (existing threads resolve
  client-side), the comment callables, and any Android client (the Redmi is
  signed out). The empty Voice Moments feed before publishing was correct — all
  24 stored moments are `status: expired`, none published.

Nothing in this record claims a device, a store availability, a two-device call,
an OBS stream or a tester-visible recovery that was not observed.

## What was already true before the evening started, and was not written down

A read-only production audit found that a **complete, undocumented backend
release had been executed on 2026-09-14** from commit `22cc2313`: 115 Cloud
Functions, Firestore and Storage Rules, 12 composite indexes and 2 field
overrides, two TTL policies, a Hosting release of 113 files, and both runtime
gates flipped — `appConfig/gif.enabled = true` and `appConfig/serversV1` to
revision 4 with `callableAccess: "all"` and an empty tester list. The deployed
revision is not an inference: the live ruleset carried the generating path of a
`22cc2313` activation package, and the deployed function-source archives hash
file-by-file to that tree exactly.

Three consequences shaped everything that followed. Production was **further
open than the recorded "Servers for testers only" intent**. `docs/DEPLOYMENT.md`
stated the opposite of production in at least four places. And 126 functions
were left on the 2026-09-08 tree, which is what caused the outage.

The stores were three builds ahead of the repository's record too: 27, 28 and 29
were built and uploaded on 2026-09-14, Play served 28 to internal testers and
TestFlight served 29 to both groups, while `pubspec.yaml` still read `2.0.0+27`.

## The outage, and why it went unnoticed for two days

One of the 115 functions deployed on 2026-09-14, the `users/{uid}` trigger
`onUserPrivacySourceChanged`, rewrites every `publicProfiles/{uid}` document
with a 22nd field. The shared guard `canonicalPublicProfile()` validates that
document against an **exact key set**, and the copy bundled into the 126 stale
functions accepts only the 21-key shape — everything else is `data-loss`, which
the callable protocol returns as HTTP 500. All 32 production profiles carried
the new field within hours, so every stale reader refused every profile, for
everyone, all the time. The publish handlers themselves are byte-identical
across the two revisions: this is deploy skew, not a defect in any commit.

It was invisible from both sides. The framework logs nothing for an explicitly
thrown `HttpsError`, so all 34 production 500s carry no application log line.
Crashlytics records uncaught errors only, and every one of these failures is
caught and turned into a snackbar. And the worst-affected surface produced no
error at all: the Voice Moments feed swallows per-item guard failures, so it
answered **HTTP 200 with an empty page** — 245 bytes, 343 times, from
`2026-09-14T08:53:56Z` to `2026-09-16T21:27:57Z`, while production held 24 Voice
Moments.

The full ranked analysis, including the three defects that no deploy can fix,
is `yovoice-evidence/2026-09-16/testers-root-cause.md`; the living list is in
[Bugs.md](../Bugs.md).

## The release round (20:53–21:32 UTC)

Deployed from `e1a9f3cd` through the exact-SHA activation package
(`manifestSha256 33705b8d…`, 391 files, phases 42 / 7 / 48 / 1 = 98 targets),
Rules first, then the four Functions phases, each with a dry run and a
read-back:

- Firestore ruleset `f2a303e2-…` → **`a208a1ba-…`**, `+10` lines, purely the two
  deny-all blocks for `serverBroadcastUsage` and `serverRuntimeCapacity`, the
  live content byte-identical to `git show e1a9f3cd:firestore.rules`.
- Functions 241 → **242**: 97 updated, 1 created
  (`createServerBroadcastIngressV1`), 0 deleted, **0 touched outside the
  selectors**, warm instances 10 → 10.
- Storage rules, indexes, TTL and both `appConfig` documents provably untouched.
- The exclusions were proved by difference, not asserted: the packaged source
  exports 245 functions and production holds 242, and the three missing are
  exactly the D12-blocked Reel voice-comment exports.

An independent reviewer re-read every number from the live APIs afterwards and
returned PASS. Two corrections came out of the round: the plan's
forbidden-target grep fires on the Server podcast *Q&A* callables (narrow it to
`[Pp]odcast(Recording|Episode|Egress)`), and a line dismissing two in-window
`reserveReelDraftV2` 500s as benign empty-payload errors was wrong — they were
authenticated 3,278-byte requests, i.e. the outage.

## The repair round (21:52–22:19 UTC)

Pinned to **`22cc2313`, not HEAD**: that revision already carries the widened
guard, it was already running on 18 production functions at wave time, and it avoids
shipping HEAD's unauthorized warm `acceptDirectCall`. The activation package
cannot express these waves — it takes no target list — so this was a
named-target deploy from a clean detached worktree, with every selector
hand-typed, sorted, diffed against the wave table and intersected with the
13-name forbidden list. Every diff and every intersection was empty.

| Wave | Targets | Unblocks |
| --- | --- | --- |
| A | `reserveReelDraftV2`, `finalizeReelDraftV2`, `reserveMomentDraft`, `finalizeMomentDraft` | publishing |
| B | `getVoiceMomentsFeedV2`, `getVoiceMomentViewV2`, `getVoiceMomentMediaAccess`, `openDirectConversation` | the empty feed, new chats |
| C | `createReelComment`, `createMomentComment`, `reserveVoiceCommentDraft`, `finalizeVoiceCommentDraft` | comments and Voice replies |
| D | `reserveDirectMessageAttachment`, `editDirectMessage`, `deleteDirectMessage`, `setDirectMessageReaction` | disarms the GIF cross-revision trap |

Read-backs: 4 updating / 4 successful / 0 create / 0 delete per wave; 16 moved
end to end and **0 outside the selectors**; total 242 → 242; warm 10 → 10 with
identical membership; Cloud Run 16/16 Ready on a single new revision at 100 %
traffic; four unauthenticated boot probes answered `401`, not `500`. The
independent verification added a chain-of-custody signal the deploy report did
not cite: all 16 targets now carry the same `firebase-functions-hash` as the
2026-09-14 `22cc2313` round, so nothing was accidentally deployed from HEAD.

`sweepExpiredServerInvitesSchedule` was fixed in the same round. It had failed
**every** run since `2026-09-14T06:13Z` — 250 consecutively, ~93 % of all
error-level log volume — because a collection-group query on
`serverInviteRefs.expiresAt` needs a hand-declared exemption that
`firestore.indexes.json` had never contained. Redeploying the function first
proved the point by failing again 3½ minutes later. The override was deployed at
22:14 UTC, reached READY at 22:18:55Z, and the next two scheduled runs returned
200.

## Build 30 and the stores

`pubspec.yaml` moved to `2.0.0+30` in `121973fc` — the only delta from the
deployed backend revision. Four stale-artifact traps were cleared first (a build
24 archive, an empty IPA directory, a versionCode 27 bundle, and a `build/web`
tree that was byte-identical to what Hosting was serving and would have let a
failed build silently re-deploy build 28).

- **Android:** AAB built and verified — versionCode 30, upload-key signature,
  `jarsigner -verify` clean, foreground-service types
  `microphone|mediaPlayback|mediaProjection`. Uploaded through the Play Console
  and published as internal release 30 at ~01:26 CEST on 2026-09-17 (read-back
  observed in-session, not captured to a file).
- **iOS:** the first archive failed on missing gRPC/absl headers because a
  second Flutter/Xcode build ran `clean` in the same workspace and `BUILD_DIR`
  mid-archive; the retry succeeded. IPA staged. The upload started at 00:55:24
  CEST and **succeeded** (Delivery UUID `89a4f953-6581-4322-9ea5-1e166e5c4026`);
  App Store Connect reports build 30 `processingState VALID` (01:02:46 CEST),
  automatically in `YO Voice Internal Testers`, and — after an API
  `relationships/betaGroups` POST (204) plus a beta-review submission (201) —
  in `YO Voice Beta Testers` with `externalBuildState IN_BETA_TESTING`
  (~01:33 CEST). Evidence: the `build30-asc-*-after.json` read-backs.
- **Web:** built to the CI runbook's dart-defines and deployed. Both domains
  serve `build_number 30` and the new `main.dart.js` hash. This release also
  **restored web push**, which had been silently off since 2026-09-14 because
  that Hosting release was a manual local deploy built without the VAPID define.

## Decisions recorded

- [ADR-195](../Decisions.md#adr-195-a-shared-integrity-guard-is-a-deployment-unit--a-projection-writer-never-ships-ahead-of-its-readers) —
  a shared integrity guard is a deployment unit; a projection writer never ships
  ahead of its readers.
- [ADR-196](../Decisions.md#adr-196-a-composer-draft-is-locked-by-a-server-reservation-never-by-an-attempt) —
  a composer draft is locked by a server reservation, never by an attempt (not
  yet implemented).
- [ADR-197](../Decisions.md#adr-197-the-2026-09-16-owner-decisions-on-servers-exposure-warm-instances-and-the-obs-canary) —
  the owner's decisions: Servers stay open to all signed-in accounts, the
  two-device test is waived, `acceptDirectCall` stays cold, the OBS capacity
  document waits for the canary.
- [ADR-198](../Decisions.md#adr-198-a-collection-group-query-is-an-index-declaration-plus-a-test-that-runs-it-adr-007-reaffirmed) —
  a collection-group query is an index declaration plus a test that runs it.

## Evidence

All under `/Users/kamil/Documents/GitHub/yovoice-evidence/2026-09-16/`:
`release-backend-delta.md` and `release-store-state.md` (the read-only audits
that found the 2026-09-14 round and the true store state), `release-gates.md`
(the gates on `e1a9f3cd`), `deploy-backend-2026-09-16.md` and
`deploy-verify-2026-09-16.md` (the release and its independent verification),
`testers-prod-logs.md`, `testers-contract-mismatch.md`, `testers-chats-health.md`
and `testers-root-cause.md` (the outage diagnosis and the ranked RC list),
`repair-00-gate.md`, `repair-2026-09-16.md` and `repair-verify-2026-09-16.md`
(the repair and its verification), `build30-2026-09-16.md` plus the `build30-*`
logs and artefacts. Gate numbers are in
[TESTING.md](../TESTING.md#release-repair-and-build-30-gate--2026-09-16);
the deploy records are in
[DEPLOYMENT.md](../DEPLOYMENT.md#servers-phase-backend-release-from-e1a9f3cd--2026-09-16).

## Handoff — what a human still has to do

1. **Confirm the repair on a real device.** The only thing that can close the
   outage is a signed-in client: a `200` on `reserveReelDraftV2` and
   `reserveMomentDraft`, and a `getVoiceMomentsFeedV2` response over 500 bytes.
   The exact commands are in the DEPLOYMENT entry, and the guided device script
   is `testers-root-cause.md` §6.
2. **Confirm build 30 in App Store Connect**, and add it to
   `YO Voice Beta Testers` if the external cohort is meant to have it. Upload
   the Android AAB and create the Play release if build 30 is meant to ship
   there.
3. **File the Play foreground-service declaration**, including `mediaProjection`
   with a demonstration video, before that manifest rolls out — one of eleven
   outstanding "Zawartość aplikacji" items. EU trader status is a separate
   owner-only App Store Connect item.
4. **Land the client fixes the repair could not make:** RC-5 (the composer
   lock), RC-10 (no `data-loss` copy and no non-fatal), RC-14 (the 95 % progress
   bar) and the five RC-15 chat defects.
5. **Land the backend fixes the repair could not make:** RC-8 (re-trim the
   truncated display name), RC-9 (do not charge a rolled-back attempt), RC-11
   (the 2-per-minute friend discovery limit), RC-16 (`retry: true` on
   `onDirectMessageCreated`).
6. **Repair the three non-canonical conversation roots (RC-6).** Data work, not
   a deploy, and `migrateDirectIntegrityConversation` must be fixed before its
   apply path is used.
7. **Give `rooms.expiresAt` the ADR-198 treatment** before anyone reconnects
   `fetchFreshVoiceSessions`.
8. **Decide the OBS canary** (LiveKit Ingress enablement and billing, then the
   capacity document) and the warm `acceptDirectCall` quote, whenever those are
   wanted.
