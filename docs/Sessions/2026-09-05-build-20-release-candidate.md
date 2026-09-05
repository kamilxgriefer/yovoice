# Build 20 coordinated tester release candidate — 2026-09-05

## Status

**HELD.** The current Build 20 candidate has passed the measured source,
browser, emulator, release-Web, bounded-render, dependency and sound-asset
gates in this record, but it has not been deployed, signed, uploaded, assigned
to testers or announced. The exact source commit is not pinned in this document
because the shared candidate tree still must be frozen. The final independent
Voice re-review is complete: 84/84
targeted tests passed and the reviewer returned APPROVE with no P0, P1 or P2
finding in scope.

The release cannot move to production until all of the following are directly
completed and recorded:

- production index/TTL-override, Functions, Rules and Hosting stages plus their
  required read-backs;
- explicit allowlisted legacy friendship reconciliation in production;
- signed IPA/AAB inspection and Build 20 uniqueness checks in both stores;
- remaining app-wide keyboard/RTL visual QA beyond the completed YO Moments
  and dock screenshot harnesses;
- physical two-account and mixed-version iOS/Android call/media QA;
- store processing, persistent tester assignment, availability verification
  and native/separate notification outcomes.

No account identifiers, allowlist contents, signed URLs, tokens, artifact
hashes or store-console identifiers belong in this pre-release record.

## Candidate boundary

This is one coordinated successor to Build 19, not a series of uploads after
individual fixes. The candidate combines the Build 19 P0 chat, call, friend,
avatar and direct-media repairs with the Build 20 Voice Moment/YO Moments,
Reels, moderation, localization, sound and navigation work in the current
tree. Automated coverage proves the exercised code paths only; it does not
replace the physical device, rendered visual, production read-back or store
availability checks listed above.

Build 19 remains the historical tester baseline. Nothing in this session
changes its recorded deployment or availability evidence.

## Measured evidence

| Gate | Result | Interpretation |
|---|---:|---|
| `flutter analyze --no-pub` | clean | no analyzer issues in the tested tree |
| Complete Flutter VM suite | **2255/2255** | passed as the complete Flutter gate |
| Chrome browser suite | **18/18** | passed the selected browser/runtime matrix |
| Production Flutter Web build | **PASS** | release-mode Web artifact compiled successfully |
| Playwright built-artifact smoke | **2/2 PASS** | selected smoke passed against the production Web artifact |
| YO Moments screenshot harness | **50/50 PASS** | 320/360/390/430/768/1100/1440 px plus populated, empty, error, loading, following, story, detail and 200% text renders |
| Dock Dark/Pearl screenshot harness | **8/8 PASS** | 320/390/430 px, 200% text and 99+ renders |
| Independent Voice re-review | **84/84 — APPROVE** | no P0, P1 or P2 finding in the targeted source/runtime scope |
| Cloud Functions | **1277/1277** | passed as non-overlapping shards after the monolithic emulator process hit a transaction-lock hang |
| Isolated room-control shard | **32/32** | independently passed; included in the sharded Functions evidence, not an extra total |
| Isolated Functions tail | **174/174** | independently passed; included in the sharded Functions evidence, not an extra total |
| Firestore Rules | **524/524** | passed on the Firestore emulator |
| Storage Rules | **67/67** | passed on the Storage emulator |
| Family media | **11/11** | passed the combined media contract |
| Functions smoke | **PASS** | passed on the local Functions/Auth/Firestore emulator boundary |
| Sound asset check | **PASS** | generated assets match the deterministic sound manifest/check |
| Functions production dependency audit | **0 vulnerabilities** | npm audit completed successfully for the production dependency tree |
| Firestore-test production dependency audit | **0 vulnerabilities** | npm audit completed successfully for the rules-harness production dependency tree |

The Functions suite was sharded because the all-in-one emulator run stopped
on an emulator transaction-lock hang. The reported 1277/1277 is the complete
non-overlapping test count across those shards. The isolated 32/32
room-control and 174/174 tail reruns confirm the affected boundaries; they are
not added again to inflate the total. This is test-infrastructure evidence,
not proof that a production deployment or physical call succeeded.

The generated PNGs were inspected rather than inferred from test completion.
Frame Echo Clean rendered without internal lines or skew, and no overlap
was observed in the bounded YO Moments/dock matrices. Those source-rendered
results do not substitute for physical-device, keyboard, RTL or full-app QA.

## Build 20 release sequence

Follow the Build 20-only order in
[DEPLOYMENT.md](../DEPLOYMENT.md#build-20-coordinated-tester-release-candidate--2026-09-05):

1. freeze the exact commit and confirm the completed 84/84 Voice APPROVE still
   applies to that frozen runtime tree;
2. deploy the four required composite indexes first:
   `reelAvailability(status ASC, expiresAt ASC)`,
   `reels(status ASC, sortKey DESC)`,
   `reelCleanupOutbox(status ASC, nextAttemptAt ASC)` and
   `reelCleanupOutbox(status ASC, leaseUntil ASC)`; deploy the two new managed
   TTL overrides, `reelCleanupOutbox.deleteAfter` and
   `voiceMomentReportReceipts.expiresAt`; read back the index and field-
   override configuration, wait for every required index to become `READY`
   and verify that both TTL overrides are enabled;
3. deploy additive Functions from the same commit and verify active revisions
   plus the protected smoke;
4. run the explicit friendship allowlist as dry-run → reviewed digest → apply
   that exact digest → no-op post-check;
5. deploy and read back Firestore Rules, then repeat authorization smokes;
6. deploy Storage Rules only when `storage.rules` changed in the frozen diff;
7. release Hosting only after exact-commit CI and all required backend stages
   are green;
8. sign and inspect Build 20 artifacts, verify store-number uniqueness,
   upload once, wait for processing, assign persistent tester cohorts and
   verify non-owner availability before any separate announcement.

The index/TTL-override-first order is intentional: Build 20 introduces
producers whose queries and retention depend on those resources. A green
emulator cannot prove that the four production composite indexes are `READY`
or that both managed TTL overrides are enabled.

## Explicit friendship reconciliation boundary

The reconciliation is a production prerequisite, not a convenience backfill.
Only pairs in a separately reviewed explicit allowlist may be considered. The
operator must not scan for candidates, infer friendship from arbitrary legacy
documents, broaden the manifest after seeing a dry-run, or place manifest
contents in this log.

The release record may retain only aggregate outcomes and the reviewed digest.
Apply must bind to that exact digest. The post-check must be a no-op; any
changed digest, invalid pair, missing bilateral mirror, block/restriction,
concurrent change or additional proposed write returns the release to
**HELD**.

## Remaining acceptance checklist

- [x] Independent Voice re-review: 84/84 targeted tests, APPROVE, with no P0,
      P1 or P2 finding in scope.
- [ ] Exact source commit and production baselines are pinned.
- [ ] All four required Firestore composite indexes are read back as `READY`;
      `reelCleanupOutbox.deleteAfter` and
      `voiceMomentReportReceipts.expiresAt` are both read back as enabled
      before their producers run.
- [ ] Additive Functions are active and the deployed protected smoke passes.
- [ ] Explicit friendship allowlist dry-run/digest/apply/no-op post-check is
      complete with no conflict; only aggregate evidence is recorded.
- [ ] Firestore Rules are deployed, read back exactly and authorization
      smokes pass.
- [ ] Storage decision is recorded: unchanged and not deployed, or changed
      with 67/67 + 11/11 gates, exact read-back and production smokes.
- [ ] Exact-commit CI passes before Hosting; deployed bytes and required
      security headers are verified.
- [x] YO Moments source-rendered matrix: 50/50 across 320–1440 px, required
      content states and 200% text; generated PNGs inspected.
- [x] Dock Dark/Pearl source-rendered matrix: 8/8 across 320/390/430 px, 200%
      text and 99+; Frame Echo Clean has no internal lines/skew or observed
      overlap in the inspected PNGs.
- [ ] Remaining app-wide keyboard/RTL and physical visual surfaces are
      inspected directly rather than inferred from bounded widget harnesses.
- [ ] Two physical accounts exercise text/photo/video/voice DMs, avatars,
      YO Moments and audio/video calls on the required iOS/Android and
      mixed-version matrix.
- [ ] Signed IPA and AAB identify `1.0.0 (20)` / version code `20`, pass
      signing and entitlement/permission inspection, and that number is
      confirmed unused in both consoles before upload.
- [ ] Both uploads finish processing and are assigned to the persistent
      tester cohorts.
- [ ] A non-owner tester observes availability on each platform before the
      native notification or separate English update is treated as sent.
- [ ] Notification and email outcomes are recorded as observed; delivery and
      spam placement are never inferred from an attempted send.

## Claims deliberately not made

- Build 20 is not recorded as deployed to Firebase or either store.
- Build 20 is not recorded as signed, processed, assigned or available.
- No tester notification or email is recorded as delivered.
- Automated tests do not prove real APNs/FCM, camera codecs, Bluetooth,
  background/foreground recovery, LiveKit media or mixed-version behavior.
- A source-level security review cannot guarantee that no attacker can ever
  enter the system; it reduces measured risk within the reviewed boundaries.

## Release decision

Current decision: **HOLD Build 20**. Change this only after the remaining
checklist is completed against one frozen commit and the deployment/store
results are observed directly. If any prerequisite changes the source tree,
rerun the affected gates and replace the evidence above rather than combining
counts from different candidates.
