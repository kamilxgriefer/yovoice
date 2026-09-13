# Servers runtime and offline mapping checkpoint — 2026-09-11

Uncommitted local work above `692aa93f`, preserving the inherited Claude tree.
This is not a deployed feature, complete Servers implementation or store build.

## Reviewed session factories

Five new runtime modules (`session_contract`, `session_authority`,
`session_livekit`, `session_control`, `sessions`) cover scoped start, explicit
join token issuance, current authority/revision validation, generation-safe
end and participant revocation. They remain unexported and inactive.

Independent emulator tests reproduced and closed two defects:

- Duplicate per-identity removal could disconnect a newly admitted presence.
  The durable attempt now has a single owner; timeout/lease expiry cannot
  reclaim it or release admission. This adapter makes one provider attempt
  with SDK failover disabled. Only an owned positive ACK releases the cutoff.
- After whole-generation recovery, the historical recipient kept reporting
  pending cleanup. Exactly `ended + revoked`, after binding/receipt validation,
  now converges read-only without changing the retained attempt or new session.

Fresh independent Node **22.23.2** gate: **83/83**, no skips, 34.075 seconds.
The seven author's file hashes were unchanged during QA. Independent security/
realtime and Principal review found no remaining actionable P0/P1/P2 within
this held factory slice. Tests use Firestore emulator and controlled transport;
they do not certify actual LiveKit, webhook delivery or two physical devices.

## Offline mapping report

`functions/servers/migration_plan.js` consumes bounded operator-provided
metadata snapshots. It retains exact Club/Family identities, computes the
documented standalone room hash, proposes reciprocal channel mapping/repair,
preserves room history/notification identity and allocation provenance, and
reports active sessions, collisions, unresolved privacy and owner conflicts.

It performs no database/network/file I/O and produces no mutation operations.
`applyReady` is always false. Names, message bodies, media URLs and bearer
material do not appear in the report. Its digest binds the mapping report,
not a complete inventory or authorization to apply changes.

Independent tests reproduced incomplete V1 markers incorrectly entering the
legacy path and a bound-room host/root-owner conflict. Both now block mapping.
Fresh independent Node22 gate: **33/33** (19 author +14 independent), no skips,
0.413 seconds; Principal independently reran 33/33 and approved this scope.

## Held access-change convergence bridge

Member/ACL mutations now capture immutable generation-bound cleanup targets in
the same transaction. Archive/transfer capture canonical session end ownership
before clearing pointers. The internal worker follows the token-recipient
ledger, including offline/removed recipients; it cannot complete a page or
release admission after an uncertain provider result. Grant projection uses
current authority, including an A-to-B-to-C owner transfer, rather than replaying
historical owner grants. Content deletion remains explicitly pending after RTC
cleanup; unsupported older job versions stay blocked.

Independent Node22.23.2 emulator gate: **111/111**, no skips, 69.122 seconds,
including ten independently authored regressions. Principal/security/realtime
review found no actionable P0/P1/P2 in the frozen held slice and independently
ran a **28/28** subset, no skips, 16.27 seconds. Author hashes stayed unchanged.

At this stage it was still an **unexported, inactive internal worker**, not a
deployed job dispatcher. Its then twenty-adapter-effects limit did not bound
the reused legacy `endRoom` HTTP fanout. The later terminal refinement below
closes this V1 adapter limit without activating the worker.

## Approved Home redesign — local review complete

The mobile/desktop Home redesign has a fresh **326/326** focused Flutter gate:
73 author cases, 25 independent cases and 228 legacy cases, with no skips.
Analysis of the eleven-file frozen scope is clean. Independent QA verified
unchanged hashes and generated 224 author plus 140 independent real-widget
captures; both themes, narrow/desktop widths, enlarged text, focus and
loading/empty/error/content states were inspected. Final read-only source
review found no actionable P0/P1/P2 within this Home slice.

A reproduced accessibility issue is closed: section errors no longer create
multiple competing polite live regions. One visible-surface scope batches
assertive error announcements, withdraws recovered errors and deduplicates
active episodes. Real callbacks, explicit room prejoin, stable subscriptions,
permission-denied cache removal and expiry recovery remain intact.

This is local source/render evidence, not physical VoiceOver/TalkBack, media
or two-account device acceptance. The earlier 3289-test full-tree run predates
these redesign changes.

## Voice and immersive Reels — bounded final review

Voice's independently rerun final gate is 132/132, no skips; source frozen at
`c836ffa2d0ecf1bb50699d96d623b488b7149d4ef8121c15593506294442411d`,
analysis of eight files clean. Real controlled regression failures were fixed:
viewed-before-success, a late previous grant overriding current playback,
queued ABA identity changes, native cleanup order, recovery intent adopting
the new identity epoch and older discovery data resurrecting a confirmed
deletion. The delete test retains and exercises opaque continuation paging.

Reels/Share's independent final gate is 76/76, no skips, 25-file clean analysis
and before/after hashes identical. Card source is
`2de8997d62f3a5e014ef6f2483375f40382528872f23e9aa6bbdc7b000bbc53f`.
More/caption link callbacks and private sheets retire on account/expiry/host
boundaries. Hidden source replacement cannot start playback. Authored links
stay separate from chrome/footer and opposite-edge links at the tested sizes,
including the reproduced 1440/200% collision. QA viewed all 20 independent
layout captures and four white-footage captures. Final read-only review has
no actionable P0/P1/P2 within these bounded scopes.

The first subsequent full Flutter run finished 3563 PASS /41 FAIL (3604 total).
All failures were in five older Voice test files; obsolete duplicated-layout
expectations and missing explicit auth fixtures were explicitly adapted,
not silently removed. Independent read-only review retained retry, paging,
engagement, viewed-state and native touch-target assertions. A combined fresh
111/111 run now passes those five files, with zero skips. A fixture-only
1 ms identity batch is drained before unmount instead of suppressing errors.
The subsequent localization audit identified newly exposed untranslated
controls/counters; its correction and full-tree pass are recorded below.
Native audio/video,
accessibility and live provider acceptance are still
separate. Screen control reported a locked Mac; no fresh simulator/store view
was obtained. Existing local Android/archive artifacts are build23 from
September8 and do not contain these changes.

## Complete backend verification on fresh local emulators

Node22.23.2 completed the full Functions suite: 1744/1744, 120 suites,
324.47 seconds, zero failures/skips. Separately, Firestore rules 564/564,
Storage 67/67, Family media 11/11 and additional Servers rules 31/31 passed.
The 280-file Functions manifest hash was identical before and after:
`bb9443cc5f91716b0389f09782baba81960387a48778de8f36fcb4a2327216d6`.
All nine rules/index/harness hashes were also unchanged.

The fresh demo-yovoice emulator suite used Firestore8086/Auth9097/Storage9197
and an explicit Functions bootstrap bucket. The additional Servers rule gate
used its matching demo-yovoice-server-acl suite on8085/9198. Functions ran
before the sequential rules gates. Logs, exact commands and all hashes are in
`/tmp/yovoice-clean-backend-gate-20260911.6upGkR/gate-summary.md`.
Only the newly created hub was stopped after verification.

Initial missing-bucket and then residual-fixture failures did not reproduce
with correct clean configuration; no source/test modification was required.
Full suites are not uniformly rerun-safe against retained fixture data.
Storage cross-service checks require the emulator startup project to match
the Firestore fixture project, not just a client-side project override.
These are local checks, not live provider, deployed rules, data migration or
tester-release evidence.

## Final terminal, localization and complete local gates

Terminal cleanup now commits positive revocation receipts and a strict private
checkpoint before one direct SDK DeleteRoom, followed by a separately fenced
final ACK. Missing readiness resumes scanning; malformed readiness, unsettled
cursor or nonempty tail denies deletion. Lost DeleteRoom/final-commit ACKs
retry only the immutable old generation, not already-settled removals.
At most twenty SDK requests and four concurrent removals are permitted per
invocation; all started requests settle on a failed batch. Live per-identity
uncertainty remains non-reclaimable. See ADR-174's dated clarification.

The two initial RED reproductions pass after the fix. Runtime/bridge union:
128/128; root independent terminal QA: 11/11 twice, no test adaptation/skips.
Final Principal/security/realtime review accepted the frozen source slice.
`session_livekit.js` SHA256 is
`658bcdb545e0c39169d4a03c67d431f9bc8abbef3f6239ea36bc38bad5e610e2`;
`session_control.js` is
`97b28be8d966e605c5867819dc7e9655545aad732573b3a8a3107b2519b142ed`.
The live per-recipient reconcile function and exports remain byte-unchanged.

Feed localization adds 24 stable keys across 41 additional locale catalogs
(984 explicit values) and reuses existing age/now translations. EN/PL helper
boundaries and real pagination counts are unchanged. Independent focused QA
passed 748/748 plus separate time/catalog and tooltip-geometry diagnostics;
all twelve DE/NL/AR renders were inspected. Thirteen source/test hashes stayed
frozen and their analysis is clean. This is not a whole-app locale audit or
qualified linguistic certification. Older out-of-scope fallbacks are disclosed
in `/tmp/yovoice-feed-locale-review.2AXmhI/report.md`.

After both freezes, the complete Flutter gate passed **3686/3686**, no skips,
4 minutes 28 seconds, and whole-tree analysis is clean. The isolated release
Web build passed in 80.9 seconds; nothing was hosted. The fresh Node22
Functions gate passed **1772/1772**, 120 suites, no failures/skips, 444.824
seconds. Its 287-file manifest is unchanged, SHA256
`d3e87f14386634ab8ca221cac96d95d5ed3bb0638bfb86c267b06777a62fb634`.
Rules/index/harness files match the previous complete gate; they were not
rerun in this last Functions pass. Node22 production dependency audits of
Functions and the rules harness each report zero known vulnerabilities,
which is not an invulnerability claim.

Logs: `/tmp/yovoice-full-gate-20260911.pe6fZn/flutter-final.log`,
`analyze-final.log`, `terminal-delete-independent.log`; complete backend
recipe/log/manifests: `/tmp/yovoice-terminal-full-backend-20260911.LXGLAq/`.
The Mac still reported locked during a repeated screen-control attempt.
No fresh simulator/store UI, physical-device or provider proof was obtained.

## Local native compile preflight — no distribution

Both platforms compile from an isolated, checksum-identical input copy:
iOS release without codesigning passed in 172.1 seconds (unsigned arm64 app,
89.0 MB); Android release APK passed in 5 minutes 31 seconds (three ABIs,
existing v2 signature verified). Both retain 2.0.0 (23) solely for compilation
and are not the next store release. No archive, IPA, new AAB, installation,
TestFlight/Play action or tester mail occurred.

The installed Flutter iOS helper strips Finder/provenance attributes from a
project recursively even with no codesigning. The original-directory build
was therefore never run; the separate copy preserved old release archives.
The Android task plan also revealed automatic Crashlytics mapping upload;
that single task was excluded by CLI, without source/config changes. No other
upload/publish task ran. The temporary encrypted-key copy was deleted after
verification and absent from the APK; original key bytes/metadata stayed intact.

Original archive/AAB and all 1142 native/version files preserve both content
and recorded metadata. All 606 source/assets inputs, native inputs and
dependency locks match their originals. Full commands, artifact hashes and
before/after evidence: `/tmp/yovoice-ios-compile-preflight-20260911.ScpcBz/`
and `/tmp/yovoice-android-compile-preflight-20260911.skQLQ5/`.
The isolated Web main.dart.js SHA256 is
`d0b6901e7fb90eb02bb76cf56d79bfb448a6604d855f8c4f7c37c41fa639f10a`.
Root stopped only its own no-longer-needed Auth emulator on9098; preexisting
8085/9198 and their fixtures were not touched. All active build/test processes
owned by this final preflight have ended.

At this checkpoint the full requested package remains incomplete. The owner
has been asked whether a separate verified-fixes release may proceed with
Servers still disabled; no answer has been received. Default remains HOLD.
Manual Mac unlock is also required for the requested UI/store inspection.
The original overnight follow-up ends around07:00 Europe/Amsterdam; it does
not authorize a partial release, migration or a false completion statement.

## Later heartbeat: pure inventory page integrity

At04:19 UTC the Mac still reported locked, and the owner had not answered the
partial-release question. `git pull --ff-only origin main` reported already
up to date. Work continued only on a bounded local migration prerequisite.

The new pure `migration_inventory.js` validates the fixed six supported related
collection scopes, exact source/read timestamps, bounded cursor/page chains
and record metadata without reading a database or returning record IDs.
Missing or unfinished evidence remains unresolved; malformed/cross-root data
rejects. All completeness/apply/write flags stay false/false/zero. Supplied
claims are not independently verified observations; no collector, media census,
permissions, quota, idle cutover or migration is implemented by this helper.
The exact contract and limits are in Servers.md and ADR-175.

Independent QA passed78/78 (18 author +27 independent +33 existing mapper),
zero skips,618.596ms. Principal/adversarial review read all three files,
reran78/78 and reported no actionable P0/P1/P2 within the narrow slice. Root
independently reran51/51 author/mapping cases. Source SHA256:
`20e3a99a682875d48cd975510b06d307be4a5d73bb24740305aafd714b787f0e`;
independent test:
`55dd3564d1508d05293e9a7063c0a66706ec49fffe0604065e20d20925d4dd3a`.
Full independent evidence:
`/tmp/yovoice-inventory-independent-qa-20260911.DHYpiV/gate-summary.md`.

All287 earlier Functions baseline files and9 rules/harness fingerprints still
matched before root started a new clean local full-backend gate. The new helper
and two new tests are the only code delta; no Flutter, native, global export,
Rules, existing mapper/runtime, provider or production state changed. Earlier
native/Web results therefore retain their original source-input identity.

The new full backend run then passed1817/1817,120 suites, zero failures/skips,
341.642 seconds, exit0. All127 test files ran, including the45 new inventory
cases. The290-file manifest is identical before/after, SHA256
`bc39b5ab80d609e28e9a1cff7faa87f9f0ce0ea4b047ac2b93d13f86b8ee5ed2`;
all287 previous Functions files and9 Rules/harness files still match. Evidence:
`/tmp/yovoice-inventory-gate-20260911.odBTMR/gate-summary.md`.
The user reported only3% usage remaining. No further feature slice was started;
source and exact checkpoint were preserved, without pretending that quota
was the only blocker. Full Servers, real-device acceptance and scope decision
remain open; no update was uploaded or emailed.

Root then cleanly stopped only its verified fresh emulator process27164; no
retained emulator or user data was removed. On the owner's next instruction,
the existing heartbeat was updated rather than duplicated: check the main
Codex remaining limit every30minutes and produce the complete Claude handoff
when a window reaches1% remaining or less. The current tool reading was97%
used (3% remaining); Spark is a separate bucket. After07:00 the heartbeat
performs only this lightweight monitor, not automatic feature work. It must
pause after delivering the handoff. This supersedes the older schedule-end
paragraph above; it does not approve a partial release or production migration.

## Remaining product and release gates

Global RTC consumers, dispatcher/activation and actual provider acceptance
are still open. Full related-record/media inventory, membership/
ACL conversion, shared legacy allocation integration, resumable apply, safe
rollback, compatible-client cutover, provider setup and physical acceptance
are not implemented or verified by these two slices.

The accepted Home/Voice Moments/Reels redesign has local source/test evidence using
[the handoff](../agent_handoffs/2026-09-11-approved-home-moments-reels.md).
The website redesign has separate local evidence; it is not published here.
No production migration, backend activation, commit, push, tester upload or
email occurred in this checkpoint. The conditional tester-build authorization
in Roadmap remains gated on completion and verification of the full scope.

## Usage-threshold handoff — 2026-09-11 afternoon

At15:31 UTC the main Codex pool reported99% used (1% remaining), meeting the
owner's requested handoff threshold. No further implementation or full test
run was started. Current main HEADs remain692aa93f (application,2.0.0+23) and
975e5c6f (website). Before this documentation addition, status listed313 app
paths (133 tracked/180 untracked) and25 website paths (19 tracked/6 untracked).
Both whitespace checks passed. The latest test reports and five key source
hashes were read/verified again, not represented as a new complete test gate.

Screen-control getState now succeeds and lists available applications, so the
earlier locked-Mac observation is historical rather than a confirmed current
blocker. No simulator screen, physical-device flow or current store state was
inspected. All three existing specialists are completed; no new work was sent.

The complete Polish continuation/release prompt is saved in
[claude-continuation-at-codex-limit.md](../agent_handoffs/claude-continuation-at-codex-limit.md)
for the owner to copy. No code or data was transmitted to Claude. The prompt
preserves full-scope HOLD, unfinished Servers, separate production approvals,
test limitations and both-platform tester acceptance. After the handoff link
was delivered, the existing automation was paused through the app; read-back
confirmed PAUSED with its name, prompt, schedule and target preserved.
No commit, push, deploy,
activation, production migration, store action or tester email occurred.
