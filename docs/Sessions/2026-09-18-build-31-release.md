# The Build 31 fix round, backend deploy and 2.0.0 (31) release — 2026-09-18

## Status

**Five things happened, and they carry four different levels of proof. Read the
level before repeating the claim.**

- **Landed in source and CI-green.** Fourteen commits over `b14397f3` closing
  ten of the thirteen RC-5…RC-17 items the 2026-09-16 outage repair explicitly
  did not fix. `main` `98f9413c`, `pubspec.yaml` `2.0.0+31`. Independent
  read-only gate: READY.
- **Deployed and read back.** Seven named Cloud Functions targets, 15:58–16:00
  UTC. All seven ACTIVE with a later `updateTime`, the six callables answering
  401, the forbidden set untouched, and an empty `severity>=ERROR` window either
  side. No rules, indexes or Storage deploy.
- **Released to users.** Hosting serves `build_number 31` on both hosts with the
  served bytes byte-identical to the local build. iOS build 31 is `VALID`,
  `APPROVED`, in both TestFlight groups, testers auto-notified. The Android AAB
  was published to the Play internal track at 18:30 CEST.
- **Verified by tests only — no device, no simulator, no screenshot.** Every
  client fix in this round is proven by rendered-widget tests and by nothing
  else. Nobody looked at the app.
- **Known to be incomplete.** F-1 caps how much of RC-17 actually works, RC-6
  still needs a data repair nobody has run, and three client fixes landed on
  `main` *after* the binaries were cut.

Nothing in this record claims a device run, a tester-observed recovery or a
WebKit measurement that did not happen.

## What the round was for

`docs/Bugs.md` carried a section titled "what the outage repair did **not**
fix" — thirteen items found while diagnosing the two-day production outage on
2026-09-16, none of which any deploy could have fixed because none of them had
landed in source. This round was that list.

Ranked in `yovoice-evidence/2026-09-16/testers-root-cause.md`, designed in
`b31-design.md`, split into a backend slice (`b31-backend.md`) and a client
slice (`b31-client.md`) run in parallel on disjoint paths, reviewed in
`b31-gate-1.md`, repaired in `b31-fix-1.md`, and cleared in `b31-gate-2.md`.

## What landed

`git log b14397f3..98f9413c` — backend first, client after, the version bump
last and alone:

| Commit | What |
| --- | --- |
| `41bbe057` | trim the canonical display name at the writer, repair it at the reader (RC-8); central `fail()` logging (RC-10 backend) |
| `e714c251` | count and warn when the Voice Moments feed drops every candidate (RC-3(d)) |
| `f383dd64` | retry the direct-message notification within a bounded window (RC-16) |
| `b710fd34` | raise the friend-discovery ceiling, add a burst window (RC-11) |
| `bdea661f` | measure fragmented MP4 from the bytes it actually parsed (RC-17) |
| `71078013` | repair the direct-conversation migration tool; add a read-only identification script (RC-6 tooling) |
| `7137b015` | report terminal callable refusals, tell the truth about data-loss (RC-10 client) |
| `3fddac7e` | keep a refused Yeel draft editable, show the publish stage on screen (RC-5, RC-14) |
| `d70cf055` | one chat-open request id per intent, with backoff (RC-9) |
| `6b3cd783` | an outage must not exhaust the send retry budget (RC-15 MSG-03) |
| `316cee33` | read mute from the conversation, edit text only, stop inventing friendship (RC-15 MSG-01/02/05) |
| `2b4e31b7` | tell a feed the server emptied from one that is empty (RC-3 client) |
| `6332004f` | `chore(release): prepare 2.0.0 build 31` — `pubspec.yaml` only |
| `98f9413c` | evaluate Premium "still active" against the injected clock |

Five decisions came out of it: [ADR-201](../Decisions.md#adr-201-the-single-refusal-primitive-is-the-single-refusal-signal--and-it-may-log-only-author-written-constants)
(central refusal logging and the privacy rule that makes it safe),
[ADR-202](../Decisions.md#adr-202-a-canonical-display-name-is-repaired-at-the-reader-and-projected-at-the-writer-never-refused-at-either)
(reader repairs, writer projects),
[ADR-203](../Decisions.md#adr-203-a-fragmented-mp4-is-measured-from-bytes-a-trun-claims-and-an-mdat-actually-contains)
(measure fMP4 from claimed and covered bytes),
[ADR-204](../Decisions.md#adr-204-an-outage-defers-a-queued-message-only-a-failure-the-server-answered-spends-the-retry-budget)
(deferral versus retry budget) and
[ADR-205](../Decisions.md#adr-205-one-chat-open-intent-keeps-one-requestid-until-it-succeeds-and-backs-off-locally)
(stable open-intent request id).

## The three things the gate caught, and why they matter more than the fixes

The first pass of this round produced three defects that each recreated the
problem they were meant to solve. All three were found by an independent
read-only review that re-executed the case rather than reading the diff.

1. **RC-8's fix would have made every legacy profile permanently unpublishable.**
   Two prior reviews had recommended asserting the reader's bound at the writer.
   Done alone, that turns an inconvenience into an unrecoverable `data-loss` for
   every row written before the fix. The shipped rule repairs at the reader *and*
   projects at the writer (ADR-202).
2. **RC-17's fix took the uploader's word for the duration.** The fragmented
   branch initially derived the duration from the last `moof`'s `tfdt` — a value
   the uploader controls. Six attack fixtures walked straight through it: a
   zeroed final `tfdt`, every `tfdt` zeroed, 21 s hidden in fragment 1, a 20 MB
   `mdat` no `trun` describes. The shipped rule requires that every claimed range
   be inside a real `mdat` and every `mdat` byte be claimed (ADR-203).
3. **RC-14's test asserted a widget property, and the label was never drawn.**
   The stage label did not exist in the loading branch at all; the test passed
   anyway. The accepted form asserts rendered text in EN and PL at 320 px and
   200 % text scale.

The lesson worth carrying: **a fix for a data-integrity defect is a candidate
for the same class of defect, one level up**, and a test that asserts a property
rather than a render proves the property, not the screen.

## Verification

| Gate | Local on `98f9413c` | CI (Node 22) |
| --- | --- | --- |
| `flutter analyze --no-pub` | No issues found | No issues found |
| Flutter suite | **4965 / 4965** | **4965 passed** |
| Cloud Functions | 10 changed/new suites **257 / 257** | **2282 / 2282**, 133 suites |
| rules / indexes / Storage | unmodified — `git diff --stat` empty | four suites exit 0 |

All three GitHub Actions workflows on `98f9413c` succeeded. Round 1, on
`6332004f`, had been red on five `stripe_billing.test.js` cases —
`buildEntitlements` compared a pinned fixture's period end against the wall
clock, so the suite turned red at a **date**, not at a code change. `98f9413c`
threads the injected clock through, defaults unchanged.

Every fix in the round was proven by reverting its load-bearing line and
observing the named test fail — eleven client mutations plus the backend cases
run against pre-fix source. The convention and the full table are in
[TESTING.md](../TESTING.md#build-31-fix-round-gate--2026-09-18).

## Deploy

Seven targets: `reserveReelDraftV2`, `finalizeReelDraftV2`,
`getVoiceMomentsFeedV2`, `openDirectConversation`, `onDirectMessageCreated`,
`getMutualFriends`, `getFriendSuggestions`. Exact command, dry-run evidence,
read-backs and the must-not-deploy list:
[DEPLOYMENT.md](../DEPLOYMENT.md#build-31-named-target-backend-deploy--2026-09-18).

Two operational findings worth keeping:

- **The command needed `--force`, and failed without it.**
  `onDirectMessageCreated` newly declares `retry: true` while the live function
  was `RETRY_POLICY_DO_NOT_RETRY`, so the deploy *introduces* a failure policy
  and the CLI refuses non-interactively. With a name-scoped `--only`, `--force`
  cannot widen the blast radius — the plan mentions no deletion and no forbidden
  name. Both dry runs are in evidence.
- **Screen the forbidden set by exact match.** `reserveReelDraft` and
  `finalizeReelDraft` are forbidden *and* are proper substrings of the correct
  targets `reserveReelDraftV2` / `finalizeReelDraftV2`. A substring screen blocks
  a correct deploy; module evaluation of `functions/index.js` is ground truth.

**~238 of 245 exports still carry the pre-fix `guards.js`.** RC-10's backend
signal and RC-8's reader repair are in production for the seven only.

## Release

Web is live on both hosts with served bytes byte-identical to the local build.
iOS build 31 is `VALID` / `APPROVED` / `IN_BETA_TESTING` in both groups with
`autoNotifyEnabled true`. Android versionCode 31 is published to the Play
internal track, confirmed by a fresh-reload console read-back.

Three stale-artifact traps fired and were each cleared by identifying the
artifact first and moving it aside, never deleting:

- `build/web` already held a tree labelled `build_number "30"` whose
  `main.dart.js` did **not** match what build 30 shipped — a plain
  `flutter build web` with no `--dart-define`, i.e. **a bundle with web push
  disabled wearing build 30's version number**. `firebase.json` would have
  deployed it verbatim.
- the Gradle output path held build 30's AAB exactly (`90504ca5…`).
- `build/ios/` held build 30's archive and IPA (`d5e039e2…`).

Each was moved aside *before* the build, so every property recorded afterwards
was read off a file this round produced.

## What is still open

- **F-1 (P2, in production).** `probe.js` adds `run.maxCompositionOffset` per run
  *per fragment* and sums across fragments, so a 60-fragment B-frame web
  recording over-reports by ~2 s and lands exactly on
  `MEDIA_DURATION_TOLERANCE_MS = 2000` — the RC-17 symptom returning for B-frame
  content. Fails closed, not a regression, but it caps how much of RC-17 shipped.
  Do not describe the web recorder as fixed without this.
- **RC-6.** Three non-canonical conversation roots. The tool is repaired and a
  read-only identification script exists; **neither has been run against
  production**, the migration callables were not deployed, and N-2/N-3 mean
  `alreadyMigrated` is not an all-clear.
- **N-1 and N-9.** Brand-new copy with wrong plurals in both languages, and a new
  state that can accuse the server falsely when a page's candidates are all
  legitimately withheld for privacy — a false fault claim to the user *and* a
  false signal in the very channel RC-10 built.
- **N-5.** `fail()` now emits a warning at ~300 sites; operator tools emit
  `data-loss` as ordinary control flow. Any alert on `integrity refusal` will be
  noisy until those are separated.
- **MSG-04.** The 250-message thread cap, out of scope by design.

Full entries, with the still-open gate findings and every UNVERIFIED item, in
[Bugs.md](../Bugs.md).

## The finding the next person needs first

**`main` moved to `d406f842` minutes after build 31 was cut, and three commits
that touch `lib/` are not in the binaries testers received:** `a629fd99` (media
long-press reactions), `23b35885` (LiveKit participant name / privacy) and
`87fc8632` (composer keyboard dismissal). The What-to-Test copy asks testers to
re-test chats, so **a tester reporting the composer keyboard or a media
long-press is reporting a bug that is already fixed on `main`**.

Provenance of the binary itself is airtight and was recorded rather than
assumed: the IPA was written at 18:15:36, `HEAD` did not move until 18:19:52, and
`git merge-base --is-ancestor` reports NO for all four new commits against
`98f9413c`. Author date is not presence — `a629fd99` carries an author date
before the build started but was merged into `main` afterwards, from a separate
worktree.

Decide whether to cut **32** before asking testers to exercise chats. Build
number 31 is consumed on Apple and can never be re-used, and `pubspec.yaml` on
`main` still says `2.0.0+31`.
