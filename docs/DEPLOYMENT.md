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

### Build 20 coordinated tester release candidate — 2026-09-05

**HELD — SOURCE, WEB AND EMULATOR GATES PASS; NO BUILD 20 DEPLOYMENT, STORE
UPLOAD, TESTER ASSIGNMENT OR NOTIFICATION IS RECORDED HERE.** The candidate
remains blocked on the production index/TTL-override, Functions, Rules and
Hosting sequence plus read-backs; the explicit production friendship
reconciliation; signed-artifact/store-number checks; rendered and physical QA;
and the actual uploads, assignments and notifications. The independent Voice
re-review is complete at 84/84 with an APPROVE decision; the exact release
commit still must be frozen after the shared candidate tree stops moving.

The order below applies specifically to Build 20. It corrects the Build 19
sequence for this candidate because its new query/retention producers depend
on Firestore indexes and both managed TTL overrides being available first. It
does not rewrite the completed Build 19 history below.

#### Required Build 20 production order

1. Freeze and record the exact reviewed commit, production baselines and
   recoverable rule/configuration sources. Re-run the final source gates and
   confirm that the completed 84/84 Voice APPROVE still applies to the frozen
   runtime tree. A dirty or moving candidate is not deployable.
2. Deploy only the required `firestore.indexes.json` changes. The Build 20
   composite indexes are `reelAvailability(status ASC, expiresAt ASC)`,
   `reels(status ASC, sortKey DESC)`,
   `reelCleanupOutbox(status ASC, nextAttemptAt ASC)` and
   `reelCleanupOutbox(status ASC, leaseUntil ASC)`. The two new managed TTL
   overrides are `reelCleanupOutbox.deleteAfter` and
   `voiceMomentReportReceipts.expiresAt`. Read the production index and field-
   override configuration back, wait until every required composite index
   reports `READY`, and verify that both named TTL overrides are enabled. Do
   not start a producer that depends on any of these resources while it is
   creating, missing or inconsistent with the pinned source.
3. Deploy the additive, backward-compatible Cloud Functions from that same
   commit. Confirm every intended revision is active, no unintended export
   changed, prior revisions drained safely, and the protected Functions smoke
   passes against the deployed boundary.
4. Reconcile only the independently reviewed legacy friendship pairs. The
   operator input must be an explicit allowlist; never discover candidates by
   scanning or treat historical client mirrors as authority. Run a no-write
   dry-run, review and retain its aggregate result plus digest, apply only the
   exact digest that was reviewed, then repeat the run as a no-op post-check.
   Any changed digest, conflict, block/restriction, missing bilateral mirror
   or non-no-op post-check stops the release. Shared documentation must not
   contain account ids, pair ids, tokens or manifest contents.
5. Deploy Firestore Rules only after Functions and reconciliation are
   healthy. Read the released source back exactly and repeat the relevant
   allow/deny and production smokes before moving on.
6. Deploy Storage Rules only if the final pinned Build 20 diff actually
   changes `storage.rules`. If it is unchanged, record that fact and do not
   perform a ceremonial Storage deploy. If changed, require the matching
   Storage and family-media gates, an exact source read-back and authenticated
   plus cross-account denial smokes.
7. Release Firebase Hosting only after the exact commit has passed CI and all
   required backend stages/read-backs above are green. Verify the workflow
   artifact and live bytes; update the separate website only from observed
   release facts.
8. Produce signed iOS and Android artifacts from the same pinned commit.
   Inspect package identity, signing, entitlements/permissions and embedded
   `1.0.0 (20)` / version code `20`, then verify that number is unused in both
   store consoles. Upload once, wait for processing, assign the persistent
   tester cohorts, enable the native tester notification where appropriate,
   and verify availability from a non-owner tester account before sending any
   separate release note.

#### Measured candidate gates

| Gate | Result | Evidence boundary |
|---|---:|---|
| Flutter static analysis | clean | source only |
| Complete Flutter VM suite | 2255/2255 | final-tree invocation |
| Chrome browser suite | 18/18 | browser widget/runtime gate |
| Production Flutter Web build | PASS | release-mode artifact compilation |
| Playwright built-artifact smoke | 2/2 PASS | selected smoke against the production Web artifact |
| YO Moments screenshot harness | 50/50 PASS | 320–1440 px, content/error/loading/following/story/detail and 200% text source renders |
| Dock Dark/Pearl screenshot harness | 8/8 PASS | 320/390/430 px, 200% text and 99+ source renders |
| Independent Voice re-review | 84/84, APPROVE | final targeted source/runtime review |
| Cloud Functions | 1277/1277 | non-overlapping shards after an emulator transaction-lock hang; room-control 32/32 and tail 174/174 also passed in isolation |
| Firestore Rules | 524/524 | emulator authorization gate |
| Storage Rules | 67/67 | emulator authorization gate |
| Family media | 11/11 | combined media contract |
| Functions smoke | PASS | local Functions/Auth/Firestore emulator boundary |
| Sound assets | PASS | deterministic asset check |
| Functions production dependency audit | 0 vulnerabilities | completed npm production audit |
| Firestore-test production dependency audit | 0 vulnerabilities | completed npm production audit |

These automated results do not establish production deployment, signed
artifact integrity, store acceptance, tester availability, email delivery,
app-wide/physical visual quality, real notification delivery or two-device
media/call behavior. The bounded PNG review found Frame Echo Clean without
internal lines, skew or observed overlap; it is not physical-device evidence.
The release remains **HELD** until every pending boundary named above is
directly observed and recorded in the Build 20 session ledger.

Detailed candidate ledger:
[Build 20 release-candidate session](Sessions/2026-09-05-build-20-release-candidate.md).

### Build 19 coordinated tester release — 2026-09-03

**TESTER ROLLOUT COMPLETE; NOT A PUBLIC APP STORE OR GOOGLE PLAY RELEASE.**
Build `1.0.0 (19)` was produced from source commit
`7ef9816fd3ee289cd065b37b83bd14d748a44e0c`. The compatible Functions,
required index, Firestore Rules, Storage Rules and Firebase Hosting release
were deployed and read back before the signed artifacts were assigned to the
persistent tester channels. Google Play Internal Testing shows Build 19 as the
latest release, available to the 15-account list since 18:29 CEST. TestFlight
shows Build 19 in `Testing` for the existing one-account internal and
seven-account external cohorts, with Build 19 installs observed in both
cohorts. Physical two-device and mixed-version acceptance remains residual;
none of this is evidence of public store review or public availability.

#### Verified before release

| Gate | Result | Boundary |
|---|---:|---|
| Static analysis | clean | `flutter analyze`; source only |
| Complete Flutter | 2123/2123 | one final-tree invocation |
| Independent Build 19 QA | 229/229 | calls, chat/media, Moments, profile and navigation |
| Reels pagination + catalog | 19/19 | cursor/retry and locale catalog contracts |
| Reels visual/localization review | 40/40 | responsive/source contract |
| Cloud Functions | 1166/1166 | 118 suites on fresh Auth + Firestore emulators |
| Firestore Rules | 523/523 | emulator result |
| Storage Rules | 67/67 | emulator result |
| Reels + atomic moderation | 64/64 | fresh-emulator security result |
| Family media | 11/11 | combined media contract |
| Shared DM media probe | 9/9 | byte/container probe contract |
| Direct media integrity | 38/38 | fresh-emulator reservation/finalization gate |
| Browser media/crop/Reels | 39/39 | Chrome result |
| Flutter production Web | built | release artifact produced |
| Website | 87/87 + clean + built | tests, lint and release build |
| Production dependency audits | 0 known vulnerabilities | Functions + Rules harness |
| Changed Node syntax + diff | 7/7 + clean | `node --check` and `git diff --check` |

The automated and deployed-production gates are complete. The independent
source reviewer approved the legacy direct-message attachment migration after
its 12/12 unit gate, 1/1 Firestore query gate and 67/67 Storage gate; the
production apply and repeat release-ready inventories completed before the
restrictive Storage Rules release. Public release remains separately held for
physical acceptance, the full visual matrix and staged App Check work.

#### Completed production data prerequisite: Voice Moments

The 2026-09-03 dry-run inspected five legacy Voice Moment objects: one ready,
four already migrated and zero conflicts. The ready record migrated; hardening
scanned one, revoked one legacy download token and found zero missing objects.
The post-run classified all five as already migrated. Firestore contains zero
legacy `audioUrl` values. The final inventory is:

| Prefix | Objects | Download tokens |
|---|---:|---:|
| `voice_moments` | 5 | 0 |
| `voice_replies` | 0 | 0 |

No bytes were deleted. Do not add document ids, signed URLs, download tokens or
other bearer material to this log. Re-run the paginated inventory immediately
before restrictive Storage Rules; **any non-zero token count or unresolved
conflict stops the release**.

#### Completed production data prerequisite: direct-message attachments

The pinned read-only pre-cutover scan reached the end of
`message_attachments/` and inspected 5 objects: 5 eligible, 0 already
finalized, 0 invalid, 0 missing and 0 raced. The controlled apply finalized
that set and revoked the legacy download tokens without deleting media bytes.
Repeated null-cursor post-apply scans then reached the end with all 5 already
finalized and 0 eligible, invalid, missing, raced or token-bearing objects;
each reported `releaseReady=true` before restrictive Storage Rules were
deployed.

The migration and inventory portions were executed after the exact Build 19
Functions revision became ACTIVE and its previous revision drained, in the
following order; the legacy/new-client playback clause in step 4 remains part
of the physical mixed-version residual:

1. one complete dry-run from a null cursor; require `reachedEnd=true`, 5
   eligible and no invalid/missing/raced objects;
2. apply with the explicit maintenance confirmation until `reachedEnd=true`;
3. run two new complete dry-runs from null cursors; both must independently
   report `releaseReady=true` and zero eligible/invalid/missing/raced/token
   counts;
4. read the zero-token inventory again immediately before the strict Storage
   Rules deploy, then test one legacy image and voice attachment from Build 18
   and new media from Build 19 after the rules source is read back.

Never deploy Functions and strict Storage Rules together. Never mark an
object manually, restore a bearer token or delete a media byte to make the
inventory green.

#### Required release order

1. Pin the exact commit; freeze unrelated release work; record current
   Functions revisions, Firestore/Storage Rules sources, Hosting release and
   both store baselines. Take aggregate-only inventories and a recoverable
   data/rules backup.
2. Re-run the complete pre-release checklist below against the exact pinned
   tree; do not reuse the focused DM counts after any media-integrity change.
3. Deploy additive/backward-compatible Functions first: DM/Shared Media,
   Voice Moment grants/retry, direct audio/video compatibility, Reels and
   atomic moderation. Confirm every intended export is ACTIVE, no unintended
   export changed, and the prior revision has drained.
4. Freeze direct attachment finalization, execute the controlled legacy DM
   migration above, and obtain two complete `releaseReady=true` scans. Keep
   the freeze through the strict Storage Rules read-back and mixed-version
   media smoke.
5. Run controlled production smokes with legacy and Build 19 clients. Prove
   text/photo/video/voice retry, Shared Media visibility, avatar convergence,
   audio fallback, Voice Moment grant/play and Reels publish/read/report.
   Read back the atomic moderation audit result.
6. Deploy only required indexes and wait for `READY`. Do not deploy the whole
   index file merely because it exists; record the exact diff and query that
   needs each index.
7. Deploy Firestore Rules, read the released source back and diff it
   byte-for-byte against the pinned commit. Repeat the authorization smokes.
8. Re-run the zero-token inventory and production IAM check, then deploy
   Storage Rules. Read back the released source byte-for-byte and repeat
   authenticated upload/grant/playback plus unauthorized/cross-account smokes,
   including Build 18 legacy image/voice playback. Unfreeze attachment traffic
   only after those checks pass.
9. Build and deploy the verified Flutter Web artifact to Firebase Hosting;
   compare the workflow artifact and both live domains byte-for-byte.
10. Update `yovoice-website` separately. Its Updates page may describe only
   verified released behavior; obtain the Vercel production URL/commit and
   responsive visual evidence before marking it live.
11. Produce signed `1.0.0 (19)` artifacts from the same commit. Inspect package,
    signing, entitlements/permissions and version. Upload, wait for processing,
    assign the persistent TestFlight and Google Play internal groups, enable
    the store's tester notification where appropriate, and verify availability
    with a non-owner tester account before sending any separate email.

#### Rollback boundary

- Stop tester assignment/rollout and roll back client/website presentation
  first; keep backend handlers compatible with build 18 while any old client
  remains active.
- Restore the captured Firestore and Storage Rules sources, then verify the
  live ruleset bytes. Do not improvise a permissive rule.
- Roll Functions back only to a revision that understands both old and Build
  19 documents. Keep cleanup/retry workers available while queued operations
  can still settle.
- Do **not** reverse the Voice Moment migration, restore token URLs, delete
  retained moderation evidence or delete media bytes as a release rollback.
  Roll forward from canonical paths/generations instead.
- Record the failed smoke, affected cohort, live revisions and recovery proof
  in the session log before attempting another release.

#### Release checklist and residual acceptance

- [x] Complete Flutter 2123/2123 in one final-tree invocation; independent
      Build 19 QA 229/229; Reels pagination/catalog 19/19 and source review
      40/40.
- [x] Functions 1166/1166 across 118 suites; Firestore Rules 523/523; Storage
      Rules 67/67.
- [x] Reels and atomic moderation fresh-emulator security gate 64/64; Family
      media 11/11.
- [x] Voice Moment migration post-run: 5/5 migrated, legacy `audioUrl` 0,
      token inventory 0, bytes retained.
- [x] DM stored-object sniffing and transaction-time reservation recheck:
      shared probe 9/9, fresh-emulator direct integrity 38/38, changed Node
      syntax 7/7 and diff check passed.
- [x] Legacy DM migration source gate: unit 12/12, Firestore query 1/1,
      production dry-run 5 eligible with 0 invalid/missing/raced and no write.
- [x] Legacy DM production apply and repeated complete `releaseReady=true`
      scans passed before strict Storage Rules deployment.
- [x] Complete Flutter suite passes once against the final merged tree.
- [x] Browser media/crop/Reels 39/39 and a production Web build pass.
- [ ] Dark/Pearl 320/390/430/tablet/desktop, 200% text, keyboard and RTL visual
      review passes; no result is inferred from a widget test.
- [ ] Two-account physical iOS/Android matrix passes DM photo/video/voice,
      camera/library, outbox restart, avatars, Voice Moments and Reels.
- [ ] Two-device mixed-version direct audio/video matrix passes, including
      permissions, background/foreground, Bluetooth and APNs/FCM.
- [x] Production dependency audits report zero known vulnerabilities; App
      Check status and residual risks are recorded honestly. Run the final
      staged-diff secret scan again after the release commit is assembled.
- [x] Production Functions/index/Rules/Storage rollout and read-back checks
      passed in the required order.
- [x] Firebase Hosting deployed the exact source commit and live route/header
      checks passed. The separate website commit deployed successfully through
      Vercel and its 43/43 production route/header smoke passed.
- [x] Signed iOS/Android artifacts were processed, assigned to persistent
      tester groups and observed as available.

#### Final results — directly observed

- Source commit: `7ef9816fd3ee289cd065b37b83bd14d748a44e0c`;
  tester release only, no public-release tag or claim.
- Functions/index/Rules/Storage: all 166 intended Functions were ACTIVE,
  including 9/9 Reels exports; the required `messages` composite index was
  `READY`; Firestore Rules and Storage Rules read back byte-identically with
  SHA-256 `4741516c7bf17f9e57f3826d789c14becad0a7386435073fe3530dc79b02b243`
  and `bce9925b397ab6bba0b5ccf8ea8cefd9db4ef02303f28dcd3a574af280`.
- Hosting: workflow
  [33757422008](https://github.com/kamilxgriefer/yovoice/actions/runs/33757422008)
  succeeded for the exact source commit; production routes and required
  security headers were verified.
- Website: commit `9cc6d72550ce6e0b603136f7bb71e7e11891ab47` deployed through
  Vercel deployment `6248731984`; the live Build 19 tester-availability page
  and 43/43 production route/security-header smoke passed. Its copy explicitly
  says this is not a public App Store or Google Play release.
- iOS: signed IPA 56,525,856 bytes, SHA-256
  `dbb99e55d38d26098a3e7f7f26dbeda1cafd9edcb4e1aee026d82c2b5d95724b`;
  TestFlight Build 19 is `Testing` for the persistent external 7 and internal
  1 tester cohorts, with installs observed. This is not an App Store release.
- Android: signed AAB 115,020,041 bytes, SHA-256
  `3850766844521330eb4ae8ed04ecc79c344ee89d5ade0af1c165d3be639c8b7f`;
  Google Play Internal Testing shows Build 19 available to 15 testers,
  published 2026-09-03 at 18:29 CEST. This is not a public Play release.
- Notifications/email: TestFlight external-group automatic notification was
  enabled. Six manual Apple messages were attempted; four later returned SMTP
  5.7.1, so delivery to all recipients is not claimed. No new Build 19 Android
  email wave was sent; prior invitations and the persistent tester list remain
  the access path. Email is not used as store-availability evidence.
- Rollback needed: no.
- Final decision: **GO for the bounded tester cohorts; HOLD public store
  release** until the physical two-device/mixed-version and full visual matrix
  residuals pass.

Detailed evidence ledger:
[Build 19 release-candidate session](Sessions/2026-09-03-build-19-release-candidate.md).

### Released 2026-09-02: coordinated mobile build 18

**WEB, SCOPED BACKEND AND BOTH PERMANENT MOBILE TESTER CHANNELS RELEASED from
`d9a731956acb03da02020a223ef06a4c26cf3d31`.** Build 18 combines the
chat/outbox and avatar-refresh fixes, durable friend search and relationship
state, explicit room prejoin with chat visible by default, listener-safe
Podcast entry, guided permissions, email-verification routing, profile-photo
viewing, room-cover cropping, direct-call reliability, Polish production
localization and the expanded 41-locale catalogue. Restrictive
Firestore/Storage migrations, billing/Stripe, App Check enforcement,
private-media IAM changes and public video remain outside this release.

Hosting workflow
[33600125808](https://github.com/kamilxgriefer/yovoice/actions/runs/33600125808)
passed for the exact source commit and deployed Firebase Hosting release
version `e419b65a4b172e56`. The exact commit also passed
[push verification](https://github.com/kamilxgriefer/yovoice/actions/runs/33598800596),
[CodeQL](https://github.com/kamilxgriefer/yovoice/actions/runs/33598800623)
and the
[Chrome browser smoke](https://github.com/kamilxgriefer/yovoice/actions/runs/33598800777).

Eight scoped Functions were deployed and read back **ACTIVE** in
`europe-west1` on Node 22: `createLiveKitToken`, `startDirectCall`,
`createDirectCallToken`, `sendDirectMessage`, `sendRoomMessage`,
`getMutualFriends`, `getFriendSuggestions` and `searchPublicProfiles`.
`minInstances=1` is limited to `createLiveKitToken`, `startDirectCall`,
`createDirectCallToken`, `sendDirectMessage` and `sendRoomMessage`; the three
search/suggestion callables remain at zero with `maxInstances=20`. Firestore
Rules, indexes, Storage Rules, billing/Stripe, App Check enforcement and
public video were not deployed.

Google Play Internal Testing reports `18 (1.0.0)` as active and available to
internal testers. The persistent 14-account `YO Voice Internal Testers` list
was checked and remains assigned. Testers join through
`https://play.google.com/apps/internaltest/4700922314668761556` while signed in
to an authorized Google account. The 111,076,228-byte AAB SHA-256 is
`79d39bc2e8d569de626a9b52455f7eacf7fdf3285c9cafb541fe2134c422248a`;
its package is `app.yovoice`, version code 18, min SDK 24 and target SDK 36.
Camera, camera-any, autofocus, front-camera and microphone hardware remain
optional.

App Store Connect accepted and processed `1.0.0 (18)` and shows it as
**Testing** in both permanent groups: the one-account `YO Voice Internal
Testers` group and the six-account external `YO Voice Beta Testers` group.
Automatic tester notification was enabled for the external group. The
55,963,651-byte IPA SHA-256 is
`c887a6d87ce440e94d9a035318ed5d6c4edeef51d2cb4138a4b26da3ff02cba1`;
inspection confirmed bundle `app.yovoice`, minimum iOS 15.0, production APNs,
`get-task-allow=false` and `ITSAppUsesNonExemptEncryption=false`.

Release verification passed Flutter VM **2044/2044** in one invocation,
Functions **1100/1100** across 118 suites with Auth and Firestore emulators,
Firestore Rules **522/522**, Storage Rules **60/60**, combined Family media
**11/11**, Chrome media/crop **18/18**, Playwright compiled-web smoke **2/2**
and room visual harness **55/55**. `flutter analyze --no-pub`, the production
web build, sound-asset generation check, iOS plist/Podfile/platform checks,
`git diff --check` and staged-diff gitleaks scan were green. Production
dependency audits reported zero known vulnerabilities for Functions and the
Firestore test harness. Bluetooth routing on Android 12+, network-loss/process
restart and a complete two-physical-device call remain explicit tester
acceptance rather than inferred emulator or browser results.

### Released 2026-08-29: compact active-room YO Live Capsule

**WEB HOSTING RELEASED from
`838bddb293508c5d8038cf9f5f4e3d7f8cb06297`; NATIVE TESTER BUILD HELD.**
The collapsed phone/tablet live-room surface is now one 82 px capsule with an
isolated room-return area and circular 48 px Chat, Mic and More controls.
Latest chat, session-local unread, audience and reconnecting state remain
visible without the previous multi-row panel covering Home. Return and
truthful Leave/End actions live in a compact modal; exact-route ownership and
room-id guards prevent remote-session cleanup from dismissing an underlying
screen or disconnecting a replacement room.

Hosting workflow
[33257269683](https://github.com/kamilxgriefer/yovoice/actions/runs/33257269683)
passed the complete pinned gate and deployed its packaged artifact. The
artifact, `https://yovoice-ec54a.web.app/main.dart.js` and
`https://app.yovoice.app/main.dart.js` are byte-identical: SHA-256
`1835920f7c1c55058c073c3c19231ad1bc68d6656865a63eecc5ca5b723a2715`,
6,476,304 bytes. Push verification, CodeQL and the Chrome browser smoke also
passed. Local release evidence is Flutter VM **1644/1644**, focused capsule
**26/26**, render harness **18/18**, clean analysis and a successful release
web build. Dark/Pearl captures cover 320/360/390/430 px, 200% text, long copy,
reconnecting, muted, unread, More and expanded states. No iOS or Android
package was created because native distribution remains queued for the next
coordinated tester build.

### Released 2026-08-29: sculpted central YO dock cradle

**WEB HOSTING RELEASED from
`17b386bb9176621f3b13872f4a5b57dd654f0561`; NATIVE TESTER BUILD PENDING.**
The shared mobile dock now owns one tangent notched outline for its fill,
border, shadow and clipping, with a recessed semantic socket behind the
64/68 px YO action. The entire circular ring remains tappable. Ordered
keyboard focus, an explicit centre focus boundary and a full-label two-by-two
layout at 160%+ text complete the accessibility pass without changing the
five product destinations or their routing.

Hosting workflow
[33238217610](https://github.com/kamilxgriefer/yovoice/actions/runs/33238217610)
passed the full pinned verification and deployed the artifact. The live
`https://app.yovoice.app/main.dart.js` matches the workflow artifact at
SHA-256
`4e9f3c2abe99ce25c306d4a9afad92d9ff0f7311b8fc2903840d9496ce7605eb`.
Push verification, CodeQL and the Chrome browser smoke all passed; local
release evidence is Flutter VM **1617/1617**, targeted dock **14/14**, real
Chrome audio **1/1**, Playwright **2/2**, clean analysis and a successful
release web build. Dark/Pearl real-font captures cover 320/390/430 px,
including 200% text. No iOS or Android package was created because native
distribution remains intentionally queued for the next coordinated tester
build.

### Released 2026-08-28: direct-chat reliability and mobile build 11

**WEB, BACKEND AND BOTH PERMANENT MOBILE TESTER CHANNELS RELEASED from
`a67036b5678c02dc9991328ff15463d5b9611689`.** Direct chats now use an
optimistic, fair text outbox; silent paged read receipts; restart-safe private
photo and voice-message payloads; active-conversation foreground-alert
suppression; and a crash-safe one-to-one call lifecycle with atomic busy locks
and replacement-call protection. The recurring unread-count warning was
removed rather than shown during recoverable background reconciliation.

Hosting workflow
[33210891530](https://github.com/kamilxgriefer/yovoice/actions/runs/33210891530)
passed the full pinned verification gate and deployed the exact build-11 web
artifact. `https://yovoice-ec54a.web.app/version.json` reports `1.0.0 (11)`;
its live `main.dart.js` is 6,398,623 bytes. The public marketing origin
`yovoice.app` is a separate Vercel/Next.js deployment and deliberately does
not expose Flutter's `version.json` endpoint.

The managed Firestore field override now has TTL enabled for
`notificationDeliveryEvents.expiresAt`. Ten direct-message, room, invite and
direct-call producers plus `onNotificationCreated` are **ACTIVE** in
`europe-west1` on Node 22 at source hash
`b45c89c53b16d46d57e4588b890e95e8350c49e7`; notification delivery retry is
enabled only after the new terminal dispatch claim made replay safe. Storage
rules were unchanged. The new Firestore Rules are intentionally **not yet
deployed**: App Store Connect still reports active installs on builds 2, 3 and
10, whose client-side fallback writes the hardened rules remove. Deploying the
rules before those testers update would trade a security migration for a
known compatibility outage.

Google Play Internal Testing reports `11 (1.0.0)` as **Available to internal
testers**, published on 28 August at 23:15 CEST. The persistent 11-account
`YO Voice Internal Testers` list remains selected and includes
`mikegabrielpl@gmail.com`. The 104,548,700-byte AAB SHA-256 is
`cea7778417c4e584bd4b6166ee6db29b539297d92024298317d983d089ce228a`;
its package is `app.yovoice`, version code 11, min SDK 24 and target SDK 36.

App Store Connect accepted and processed `1.0.0 (11)`, then showed it as
**Testing** in both permanent groups: `YO Voice Internal Testers` and the
six-account external `YO Voice Beta Testers`. Automatic tester notification
was enabled when build 11 was submitted to the external group. The
54,531,746-byte IPA SHA-256 is
`0d75f0c570e8435ff919e0e13cb8046078082922e394ff54f4628f47cd2a1a5a`;
inspection confirmed bundle `app.yovoice`, build 11 and iOS 15 minimum. Xcode
reported `Upload succeeded`; missing third-party framework dSYM warnings did
not block TestFlight but may limit symbolication inside those frameworks.

Release verification passed Flutter VM **1461/1461**, Functions **907/907**,
Firestore Rules **519/519**, Storage Rules **60/60**, combined Family media
**11/11**, the real-Chrome audio lifecycle **1/1**, sound generation checks,
release compilation and `flutter analyze`. Independent backend, release and
principal reviews returned **SHIP** with no P0-P3 findings. No physical iOS or
Android device was connected to this workstation, so an end-to-end two-device
APNs/FCM, image/voice transfer and LiveKit call-latency smoke remains explicit
tester acceptance rather than a fabricated verification result.

### Released 2026-08-28: saved Vibe and mobile build 10

**WEB AND BOTH MOBILE TESTER CHANNELS RELEASED from
`5fd845a522962cf1f4cf6ec2a347adb0b3238efa`.** Saved profile Vibe now renders
on both the signed-in full profile and the full friend-profile route, shares
one responsive headline, respects the 80-character editor limit at 320 px and
200% text, and no longer treats a website-only identity as empty.

Hosting workflow
[33198255075](https://github.com/kamilxgriefer/yovoice/actions/runs/33198255075)
deployed the pinned artifact. The live 6,350,453-byte `main.dart.js` matches
the workflow artifact at SHA-256
`6bc415a7047416ab93874e90e84055217e12b3ba1d7bf2e3b3ee99e6f44c5b2f`,
and `version.json` reports `1.0.0 (10)`. Exact-SHA Flutter verification,
browser smoke and CodeQL workflows all passed; the full Flutter VM suite was
1,410/1,410 and `flutter analyze` was clean.

App Store Connect accepted and processed signed build `1.0.0 (10)`. It is
**Testing** in both permanent groups: `YO Voice Internal Testers` and the
external `YO Voice Beta Testers`; automatic tester notification was enabled.
All six existing external testers were consolidated into that permanent
group, including the four accounts previously stranded on builds 2/3. Two
accounts still marked `Invited` were reinvited and must accept the latest
TestFlight email using the same Apple ID before the update appears. The
54,478,469-byte IPA SHA-256 is
`db49d11c1822c96b693468c7eeba0957c30a86dba57c45321db1e89a25ac44ba`;
inspection confirmed bundle `app.yovoice`, iOS 15 minimum, production APNs,
Apple Sign-In and `get-task-allow=false`.

Google Play Internal Testing reports `10 (1.0.0)` as **Available to internal
testers**, published on 28 August at 20:22 CEST. The selected 11-account
`YO Voice Internal Testers` list includes `mikegabrielpl@gmail.com`. The
104,305,258-byte AAB SHA-256 is
`e90b9b62b5bc27dd74505f30c2c4f8c7aa52e08b77ebdf137dbb781d28f2bfa1`;
its package is `app.yovoice`, version code 10, min SDK 24 and target SDK 36.
Production App Store and Google Play submissions remain separate from these
tester releases.

### Released 2026-08-28: Podcast Studio and mobile build 9

**WEB, RULES AND MOBILE BETA RELEASED.** Podcast Studio was deployed from
`39b320727a450358a5b41a27fe353e2e41b0058e`; the shared native build number was
then raised to 9 in `e2fd878c403466c9bbdd78fff6ab146a8958ad3a` because both
stores had already accepted build 8. The release makes Podcast a producer-led
show surface with an editorial episode hero, real stage/audience/speaker
counts, an in-room producer desk, a live stage-request queue, listener state
and dedicated Podcast settings.

Firestore Rules deployed as
`projects/yovoice-ec54a/rulesets/c6736f68-dfd8-4489-b3dd-00dd0d3a9f20`.
The live Rules source was read back byte-for-byte and matches repository
SHA-256 `09b5bace9c1522ad5e47a274041184e73f95d84d5ca0901d35b262733198428b`.
Hosting workflow
[33188999220](https://github.com/kamilxgriefer/yovoice/actions/runs/33188999220)
deployed the pinned 6,348,593-byte `main.dart.js`; both live origins match the
workflow artifact at SHA-256
`973ad8d8dfdd5870afcbbc4be0bf3cabd62e3b6af13a278ff33058a9b485345c`.
A follow-up pinned Hosting deployment from build-9 revision `e2fd878`, workflow
[33192629289](https://github.com/kamilxgriefer/yovoice/actions/runs/33192629289),
completed successfully. Both origins serve its exact `main.dart.js` at the
same SHA-256 above. Their byte-identical `version.json` reports
`1.0.0 (9)` and has SHA-256
`ea6c149682a1728980b1956fd3a2d582a90a7dff617adc4b20d2683f2aec1fc8`.

App Store Connect accepted the signed `1.0.0 (9)` package at 18:49 CEST,
finished processing it, and shows it as **Testing** in the permanent
`YO Voice Internal Testers` group with a 90-day window. The 54,481,227-byte
IPA SHA-256 is
`3702a6c272bcc4570e3f52e5e2ce2bc2c3e9a4a27f5eea2c19488d31ad94a492`;
inspection confirmed bundle `app.yovoice`, Apple Distribution team
`C3R59P53KB`, production APNs, build 9 and
`ITSAppUsesNonExemptEncryption=false`. Xcode's upload succeeded; warnings for
missing third-party framework dSYMs do not block TestFlight but may limit
symbolication inside those frameworks.

Google Play Internal Testing reports `9 (1.0.0)` as **Available to internal
testers**, published at 18:57 CEST. The selected `YO Voice Internal Testers`
email list contains 11 accounts, including `mikegabrielpl@gmail.com`, and uses
the existing internal-test opt-in link. The 104,300,235-byte signed AAB
SHA-256 is
`3168978aeccc856baeda0686b39ba868fc727f98db94da993c51bfeac227944e`;
its package is `app.yovoice`, version code 9, min SDK 24 and target SDK 36.
Google Play reported zero newly unsupported devices and retained 12,294
supported phones.

Release verification passed 1,407 Flutter VM tests, 512 Firestore Rules tests,
892 Cloud Functions tests, 60 Storage Rules tests, 11 combined Family media
tests, the real-Chrome audio lifecycle test, the 49-test focused Podcast/model
pass, `flutter analyze`, the release web build, 55 responsive visual frames,
signed artifact inspection, browser smoke and CodeQL. Production App Store and
Google Play submissions remain separate from these tester releases.

### Uploaded 2026-08-28: iOS build 7 and mobile beta access audit

**APP STORE CONNECT UPLOAD ACCEPTED from
`9a92072b8032271f031a8520b8078f9f86341ff4`.** The signed iOS
`1.0.0 (7)` archive passed bundle, version, distribution-signature and
production APNs entitlement inspection. App Store Connect completed package
analysis, accepted all 54,407,157 bytes and reported `Upload succeeded` at
13:34 CEST; Apple then moved the package into processing. The IPA SHA-256 is
`302abfb857592b0eb0fc55374b7a7f245bfdeb60592ee04ad3d936b0def0403f`.
This is a TestFlight upload, not an App Store production submission.

Do not describe build 7 as available in TestFlight until App Store Connect
finishes processing and the build is visibly assigned to the intended tester
group. The upload session does not expose that later group-assignment state,
so this remains an explicit release gate. Xcode also warned that several
prebuilt third-party frameworks did not include matching dSYMs; the binary was
accepted, but crash symbolication for those frameworks may be incomplete.

The matching Android binary did not need a duplicate upload: Google Play was
re-checked directly and still reports `7 (1.0.0)` as active and available on
Internal Testing, with the existing 10-account list selected. Testers must use
the Internal Testing opt-in link while signed in to one of those Google
accounts; the draft application is not discoverable through normal Play Store
search. Google rejects addresses that are not registered Google accounts.

The exact SHA passed the full Flutter analysis/test and web build workflow
[33166426929](https://github.com/kamilxgriefer/yovoice/actions/runs/33166426929),
[browser smoke](https://github.com/kamilxgriefer/yovoice/actions/runs/33166426905)
and [CodeQL](https://github.com/kamilxgriefer/yovoice/actions/runs/33166426942).
There were no mobile-client changes after Android build 7; the intervening
Premium commits are backend/catalog work with live checkout still disabled.

### Released 2026-08-28: Android adaptive launcher safe area and build 7

**ANDROID INTERNAL DEPLOYED from
`ca15697ab3fec8e291b755b44f1d0518c74ea653`.** Android 8+ now applies a
16% adaptive-foreground inset instead of 8%, keeping the complete YO mark
inside Android's 66dp safe area across circle, squircle and rounded-square OEM
masks. The iOS/App Store artwork, canonical transparent mark, legacy Android
rasters and backend are unchanged; no web-facing code or assets changed.

Google Play internal testing reports `7 (1.0.0)` as available to the existing
10-tester list, published on 28 August at 06:23 CEST. Play's release preview
showed zero newly unsupported devices and retained all 12,294 supported
phones. The signed 104,037,451-byte AAB SHA-256 is
`795785e569410398c5fced1dc68dc9475484fb01ffa393f55c25e50a3dbaadad`;
its package is `app.yovoice`, version code 7, and upload-certificate SHA-1 is
`AF:E0:BF:45:DC:13:36:C2:CC:1D:72:EE:55:4B:D9:AE:C7:09:44:85`.
Bundle inspection confirmed that the packaged adaptive XML contains the 16%
inset.

Release verification passed 1,382 Flutter tests, the 9 focused launcher/icon
tests, `flutter analyze`, artifact signature/version/hash inspection, circle
and squircle safe-area previews, CodeQL, browser smoke, and independent QA,
DevOps and principal reviews. The exact-SHA
[Hosting workflow](https://github.com/kamilxgriefer/yovoice/actions/runs/33141379949),
[browser smoke](https://github.com/kamilxgriefer/yovoice/actions/runs/33141380054)
and [CodeQL](https://github.com/kamilxgriefer/yovoice/actions/runs/33141379922)
all passed. The Hosting workflow performed its automatic verification/build
gates only; no manual Hosting, Firebase backend or iOS deployment belongs to
this Android-only release. A Play-installed launcher check on update and fresh
install remains tester acceptance because this workstation has no Android
device or emulator.

### Released 2026-08-28: Google/Apple authentication recovery and build 6

**DEPLOYED from `91353d71ae10d0de13926894a3d65c70fc7425ca`.** Build 6
restores federated login and registration parity, keeps a valid
Firebase identity when Firestore profile creation is temporarily unavailable,
and gates authenticated entry on a bounded, retried canonical profile
bootstrap. Provider names are normalized to Firestore Rules' UTF-16 length
contract without splitting graphemes; an in-flight account switch cannot
retarget provider data. Apple provider outages are retriable, Android uses the
Firebase-hosted Apple OAuth flow, and iOS carries an explicit `GIDClientID`.

Hosting workflow
[33120682376](https://github.com/kamilxgriefer/yovoice/actions/runs/33120682376)
repeated every verification/build gate, then deployed only its pinned artifact.
Both live origins serve the exact 6,276,276-byte workflow `main.dart.js`,
SHA-256
`560e48a682fdf1b7114b01d4743a9db0f4a7d73bc1997084bc965703d14e8490`.
The automatic Hosting verification, browser smoke and CodeQL runs also passed
for the same release SHA.

Google Play internal testing reports `6 (1.0.0)` available to the existing
10-tester list. The signed AAB SHA-256 is
`700e3f413410d19a70d269ae710707796a9e31046f5e3816dd511aef8c0b2e54`.
The signed iOS `1.0.0 (6)` IPA is retained at SHA-256
`15ea8f770d333e8862084b39e09a0589f5a66c6bcee7717a62fe44839bdbe7d8`;
its distribution signature, production profile, Apple Sign-In entitlement and
Google client configuration passed artifact inspection. The export completed
with `EXPORT SUCCEEDED`, and App Store Connect accepted build 6 for TestFlight
processing. External-tester availability and real-account acceptance remain
separate checks; the earlier `Failed to Use Accounts` note no longer describes
the final upload attempt.

Release verification passed 1,382 Flutter tests, the 46 focused auth/profile
tests, `flutter analyze`, the full CI rules/Functions suite, browser smoke,
CodeQL, signed-artifact inspection and independent security, QA, DevOps and
principal reviews. The public Firebase provider probes route to the canonical
Google and Apple authorization hosts. A controlled new/returning-account OAuth
completion on web and store-installed builds was not fabricated and remains
tester acceptance. No Functions, Firestore/Storage Rules, indexes or
production data changed in this release.

### Released 2026-08-27: direct friend calls and Android build 5

**DEPLOYED from `cbe3e463f9209ea9e1fcc97b5fe27dad2cd8a5ef`.** The
`directCalls(status ASC, expiresAt ASC)` index reports READY. The eight direct
call lifecycle/control exports, updated notification owner and reciprocal
friend-request fix are ACTIVE in `europe-west1`. Firestore Rules release
`projects/yovoice-ec54a/rulesets/83c05c23-587e-4eb9-827a-ace8770c804d`
was read back through the Rules API and is byte-identical to the pinned
`firestore.rules`, SHA-256
`b91a23640c3e8c566b618f9720ee5f6f7b1376c15ecda45ca6a7028c7f6ea936`.
An unauthenticated request to the live `startDirectCall` endpoint returns the
expected callable `UNAUTHENTICATED` contract rather than a missing or stale
binding.

Hosting workflow
[33115756128](https://github.com/kamilxgriefer/yovoice/actions/runs/33115756128)
passed every verification/build gate and deployed the pinned artifact. Both
live origins return the same 6,269,582-byte `main.dart.js` as the release
build, SHA-256
`2f9f68801eb19d512fc81dcf657a4d1861d7a4e5b4d8c4b595dbe9534d4a7d34`.
Google Play internal testing now reports version `5 (1.0.0)` as available to
the selected 10-tester list. The signed AAB SHA-256 is
`904285c22488ef9c29854c54cb94850cc968f494bebd77f1035d12bbd2a11f6d`.

Release verification passed 1,370 Flutter tests, 802 Functions tests, 499
Firestore Rules tests, `flutter analyze`, the full Hosting workflow and the
Google Play artifact validation. A signed iOS build 5 IPA was also produced at
SHA-256
`356cb411148d368e838425abf6532e07b5ea9b2331f543725350bf40d6fb85ad`;
it was not uploaded during that release because App Store Connect upload
authorization was then unavailable. A production two-account ringing/answer/end
smoke was not fabricated without controlled disposable accounts; build 5
exposes that final real-device acceptance path to the tester cohort.

### Released 2026-08-27: Voice Moment local review, custom availability and authoritative capacity

**DEPLOYED from `65c1c5f906e6d3dd569dc96b092dead9f8424f9e`.** The
`voiceMoments(authorId ASC, isPublished ASC)` index reached READY and the real
production query succeeded; all thirteen ordered Functions reached ACTIVE on
their latest-ready revisions with 100% traffic; Firestore and Storage Rules
were read back byte-for-byte; and controlled production smokes covered a
25-hour publish/replay, like/unlike, text and voice comment lifecycle, cleanup,
draft privacy, server-only root mutation, reservation-bound media and legacy
read compatibility. Hosting workflow
[33043536603](https://github.com/kamilxgriefer/yovoice/actions/runs/33043536603)
rebuilt every gate from the pinned commit and deployed the verified artifact.
Both live origins serve the same 6,213,146-byte `main.dart.js` with SHA-256
`a1255cfcf05864a76761a38f3bf6ef4892684dd0d7db7ed5933e4036950468af`.

Durable backend read-back evidence:

- index `CICAgNi4-ZIK` is READY;
- Firestore release
  `projects/yovoice-ec54a/rulesets/4786aefc-8d18-487c-9f5a-465a9ed5ba8e`
  matches `firestore.rules` at SHA-256
  `10dc84f502adec1d0b8f2329d75654f0e67f6c706d46d5b6214a004237da600c`;
- Storage release
  `projects/yovoice-ec54a/rulesets/9619c567-d221-4094-835e-827a469e8741`
  matches `storage.rules` at SHA-256
  `e713b9d46ce0cf6af2c702297b3a9ecb421d7bb521b95e1bafea0c99b342312c`;
- the thirteen serving revisions are `reservemomentdraft-00007-rej`,
  `finalizemomentdraft-00007-big`, `deletemoment-00007-jec`,
  `expirevoicemomentsschedule-00003-bad`, `setmomentlike-00007-sem`,
  `createmomentcomment-00007-ban`,
  `reservevoicecommentdraft-00007-wep`,
  `finalizevoicecommentdraft-00007-keq`,
  `deletemomentcomment-00007-nen`,
  `expireabandonedmomentdraftsschedule-00007-xah`,
  `expireabandonedvoicecommentdraftsschedule-00007-des`,
  `processpendingcontentcleanupschedule-00007-xog` and
  `oncontentcleanupoutboxcreated-00007-wax`.

Physical mobile review/playback and store delivery were not performed in this
rollout; that remaining validation does not weaken the now-live server
authority. The ordered procedure below is retained as the recovery and future
release runbook.

The load-bearing order is:

> **Index READY and query-proved → Functions ACTIVE and
> callable/concurrency-smoked → Firestore Rules read back → Storage Rules
> IAM/read-smoked → client/Hosting.**

1. Run the full Flutter VM suite **and** the separate Flutter browser suite
   listed in [TESTING.md](TESTING.md#current-counts), plus Functions, Firestore
   Rules, Storage Rules, family media, `flutter analyze` and a release web
   build. Pin the release commit. Capture the live Firestore and Storage Rules
   sources and the current
   serving revisions/traffic of `reserveMomentDraft`, `finalizeMomentDraft`,
   `deleteMoment`, `expireVoiceMomentsSchedule`, `setMomentLike`,
   `createMomentComment`, `reserveVoiceCommentDraft` and
   `finalizeVoiceCommentDraft`, plus `deleteMomentComment`. Also record the
   ACTIVE revisions of
   `expireAbandonedMomentDraftsSchedule`,
   `expireAbandonedVoiceCommentDraftsSchedule`,
   `processPendingContentCleanupSchedule` and
   `onContentCleanupOutboxCreated`: stricter Storage Rules deliberately leave
   all media deletion to these Admin workers. Use the revision procedure in
   the Friends runbook below; `firebase functions:list` alone is not serving
   revision evidence.
2. Deploy indexes only:

   ```bash
   firebase deploy --only firestore:indexes --project yovoice-ec54a
   ```

   Wait until `voiceMoments(authorId ASC, isPublished ASC)` is READY/Enabled.
   Then execute the exact production query
   `where('authorId','==',SMOKE_UID).where('isPublished','==',true)` with an
   Admin SDK smoke account. READY without a successful real query is not a
   release gate.
3. Deploy the nine compatible Moment owners and the four cleanup exports that
   bundle the same integrity implementation, then verify all thirteen new ACTIVE
   latest-ready revisions and 100% traffic:

   ```bash
   firebase deploy --only functions:reserveMomentDraft,functions:finalizeMomentDraft,functions:deleteMoment,functions:expireVoiceMomentsSchedule,functions:setMomentLike,functions:createMomentComment,functions:reserveVoiceCommentDraft,functions:finalizeVoiceCommentDraft,functions:deleteMomentComment,functions:expireAbandonedMomentDraftsSchedule,functions:expireAbandonedVoiceCommentDraftsSchedule,functions:processPendingContentCleanupSchedule,functions:onContentCleanupOutboxCreated --project yovoice-ec54a
   ```

4. With controlled test accounts, verify: absent/default 24 hours; at least one
   non-preset value such as 25 or 48 hours; `permanent` with no `expiresAt`;
   exact request replay; two concurrent finalizations competing for the tenth
   slot; and delete releasing a slot. Retry the same unfinished invalid root
   and reply finalize through its attempt budget and prove the next attempt is
   rejected before another Storage read; replay one completed finalize and
   prove it is free and performs no second Storage read. Against a controlled
   finite deadline, prove like/text-comment/voice-reserve/voice-finalize work at
   deadline minus 1 ms and fail at the deadline and after it, while owner delete
   remains available. Verify `deleteMomentComment` and all four cleanup exports
   captured in step 1 are ACTIVE on their new revisions; smoke like/unlike plus
   text/voice comment create/delete, one event-driven cleanup-outbox deletion,
   and one abandoned root/reply cleanup through the deployed schedules. The
   next Rules stages remove every direct engagement and media-delete fallback.
   Do not continue if any required callable revision, cleanup worker or smoke
   is ambiguous.
5. Deploy Firestore Rules only and read the released source back byte-for-byte
   using the standard Rules API procedure in this document:

   ```bash
   firebase deploy --only firestore:rules --project yovoice-ec54a
   ```

   Smoke author draft reads, foreign draft denial, published signed-in reads,
   and denial of client root create/update/delete plus capacity-ledger access.
6. Confirm the Firebase Storage service agent still has the narrow
   `roles/firebaserules.firestoreServiceAgent` grant, then deploy and read-smoke
   Storage Rules:

   ```bash
   firebase deploy --only storage --project yovoice-ec54a
   ```

   Require author draft upload/read, outsider draft denial, published signed-in
   read, expired outsider denial, and refusal by both author and outsider to
   client-delete an uploading, published or expired object. Seed one existing
   20-character mixed-case legacy Moment id and prove its published signed-in
   read plus author-only uploading-draft read remain compatible; every client
   delete and new mixed-case allocation must still be denied.
   For voice replies, seed one canonical unexpired server reservation and prove
   allowed-MIME upload and refusal of client deletion even before finalize;
   refuse missing, expired and identity/path-mismatched reservations. After
   simulating finalize (comment created, reservation removed), continue to
   refuse owner deletion while preserving signed-in read. A seeded mixed-case
   legacy reply remains read-only (including when its allowed MIME is M4A): it
   receives neither a new-allocation nor a client-cleanup exception; a
   lowercase exactly reserved M4A upload remains valid. Finally prove the
   deployed abandoned-upload worker can remove the unfinished canonical root
   and reply as Admin authority; Rules success alone does not prove cleanup.
7. Only after all backend gates pass, dispatch the pinned Hosting build. On a
   physical mobile device and a real browser, prove preview play/pause/seek
   creates no Firestore draft or Storage object, publish a non-preset duration
   and an Until deleted Moment, then delete one and verify cleanup. Keep a
   finite Moment surface open across a controlled deadline (or use the pinned
   short-deadline staging fixture) and prove it disappears/stops playing while
   the server refuses new engagement without waiting for the sweeper. Headless
   widget/player doubles do not prove real `audioplayers` behavior.

Rollback uses the captured live rule sources and serving revisions, never a
guessed commit. Before the Functions stage, indexes may remain harmlessly. If
the Functions stage must be rolled back, withdraw the new client first; old
Functions cannot accept non-preset values. The server-only mutex documents may
remain because they are version records, not capacity data. Once stricter
Rules are live, restore the captured Firestore/Storage sources only as part of
an explicit coordinated rollback; do not mix an old permissive root writer
with a new client and call that a safe intermediate state.

### Released 2026-08-27: Velvet Prism product sound

**HOSTING, ANDROID INTERNAL AND FCM CUTOVER DEPLOYED.** The verified Hosting
artifact contains exactly the eight cache-safe `audio/ui/v3` WAVs, and both
live origins return byte-identical client bytes while the old root-level path
resolves only to the SPA fallback. Android builds 4 and 5 carry the v3 native
assets/channel; build 5 is available to 10 internal testers. Production
`onNotificationCreated` targets `yovoice_activity_v3`, while incoming calls use
the separate maximum-priority `yovoice_calls_v1` channel. The signed iOS build
5 artifact contains the matching WAV but was retained without upload because
App Store Connect authorization was unavailable during that release; build 6
later established the upload path. Physical speaker/headphone/DND listening
remains an acceptance check for the tester cohort, not a claim supplied by
automated waveform tests.

1. Run the full Flutter/Functions gates plus:

   ```bash
   python3 tool/generate_ui_sounds.py --check
   flutter test test/ui_sound_service_test.dart \
     test/foreground_stream_banner_test.dart \
     test/room_voice_entry_screen_test.dart
   node --test functions/test/push_payload.test.js
   ```

   Require exactly eight app WAVs under `assets/audio/ui/v3/` and no legacy
   root-level UI WAVs; 48 kHz/stereo/duration/loudness/tail checks;
   byte-identical app, Android and iOS notification masters; and one common
   `yovoice_activity_v3` value in Flutter, Functions and AndroidManifest.
   Delete ignored native build output before the acceptance build so an old
   archived v1/v2 Flutter asset cannot be mistaken for the new source.
2. Build Hosting from a clean artifact and confirm it contains only the eight
   `assets/audio/ui/v3/` WAVs. Ship the mobile clients and Hosting **before**
   changing the server payload.
   On an upgraded Android device prove v3 exists with the custom sound. On a
   fresh install, while Functions still sends v2, prove the missing requested
   channel safely falls back to the manifest's v3 channel. Verify the iOS
   bundle contains the new `yovoice_notification.wav` bytes.
3. On phone speaker and headphones listen to all eight cues, then repeat with
   an active LiveKit room, Bluetooth/AirPods, iOS silent switch and Android
   DND. Confirm create-room produces one cue, participant bursts remain quiet,
   and one foreground notification produces exactly one sound. Automated PCM
   checks do not replace this operator approval.
4. Only when the minimum supported Android population has created v3 (or a
   forced upgrade excludes older builds), deploy the payload owner and verify
   its serving revision/traffic:

   ```bash
   firebase deploy --only functions:onNotificationCreated \
     --project yovoice-ec54a
   ```

   Send one controlled Android background push, one iOS background push and
   one focused-platform push. Verify v3/custom sound on Android, the packaged
   APNs sound on iOS, and exactly one focused presentation.

Rollback is asymmetric. The v3 client/channel and new WAVs are harmless while
Functions still targets v2. If post-cutover delivery fails, restore only the
captured `onNotificationCreated` revision so Android payloads target v2 again;
do not try to mutate or delete channels already owned by the OS. A later
client rollback may leave v3 installed, which is expected.

### Friends notification single-writer rollout — executed 2026-08-25

ADR-114 is **DEPLOYED** from commit `5377aa688b030211ea36ba600142b82c792ae227`.
The ordered production rollout below completed on 2026-08-25 with the
documented step-8 physical-FCM exception. Evidence:

- Firestore Rules release
  `projects/yovoice-ec54a/rulesets/264042f0-5952-4b09-809e-ed72af354af1`
  was read back through the Rules API and is byte-identical to the repository
  source (SHA-256
  `c5ce8978748206684e2fc0794a865c7e099890bd934def683255e3f49def3c8d`);
- all five ordered Functions stages reached `ACTIVE`, their Cloud Run
  latest-created/latest-ready revisions matched, and 100% traffic served those
  revisions; the retired `onFriendRequestCreated`,
  `onFriendRequestResolved` and `onFollowerCreated` exports were then deleted
  and their production count verified as zero;
- the two-account production journey passed before and after trigger deletion:
  send/cancel, decline, accept/unfriend, follow/unfollow/refollow, generation
  pointers, bell cleanup and fixture cleanup;
- `notifications` was exported before the sweep to
  `gs://yovoice-ec54a-admin-backups-europe-west4/friends-notifications-pre-sweep-20260825T223745Z`
  (102 documents, successful export, restricted bucket with seven-day soft
  delete). The source-aware sweep removed 2 retired rows; a fresh full pass
  reached the end with 0 planned deletions;
- Hosting workflow run
  [32810379503](https://github.com/kamilxgriefer/yovoice/actions/runs/32810379503)
  rebuilt and verified the pinned commit, then deployed the verified artifact
  to `live`. The artifact, `yovoice-ec54a.web.app` and `app.yovoice.app`
  served the same 6,114,305-byte `main.dart.js` with SHA-256
  `b5a5e9e02bfe1c4802d21693ab6ff209e1ff089f5cc92d86256ae9e2fff8e06a`.

The release owner explicitly allowed Hosting to proceed without the final
physical two-device FCM smoke. Durable in-app state and production lifecycle
were verified, but OS-level FCM presentation on two real devices remains
**not performed** and must not be inferred from this release record.

The rollout removed three previously deployed trigger exports, so Hosting
alone was insufficient and a generic Functions update could not prove
deletion. The executed order remains the recovery and future-release runbook:

1. run the full Flutter, Functions, Firestore and Storage suites plus the
   callable two-user smoke. Pin the release commit and capture the live
   Firestore release/ruleset source using the Rules API procedure below. Also
   record `state`, `updateTime`, the underlying Cloud Run service and its
   serving revision for all Functions in stages 3a-3e and the three legacy
   triggers before changing anything:

   ```bash
   gcloud functions describe FUNCTION_NAME --gen2 --region=europe-west1 \
     --project=yovoice-ec54a \
     --format='yaml(name,state,updateTime,serviceConfig.service)'
   gcloud run services describe CLOUD_RUN_SERVICE_NAME \
     --region=europe-west1 --project=yovoice-ec54a \
     --format='yaml(metadata.name,status.latestCreatedRevisionName,status.latestReadyRevisionName,status.traffic)'
   ```

   Use the first command's `serviceConfig.service` as
   `CLOUD_RUN_SERVICE_NAME` in the second command. For a healthy serving
   revision, `latestCreatedRevisionName` and `latestReadyRevisionName` match,
   and `status.traffic` sends 100% to that expected latest-ready revision.

   Save this aggregate-only pre-state in the approved release record. A later
   `firebase functions:list` proves presence/absence and ACTIVE state only; it
   does not prove which revision is serving.
2. deploy the backward-compatible Firestore Rules widening first. It accepts
   both the deployed `{uid, followedAt}` follow edge and the new optional,
   bounded, server-owned `notificationId` pointer; clients still cannot write
   either edge shape:

   ```bash
   firebase deploy --only firestore:rules --project yovoice-ec54a
   ```

3. update Functions in the ordered selective stages below. Firebase does not
   make a comma-separated Functions deploy atomic, so do not collapse these
   commands:

   a. deploy `onNotificationCreated` plus the four direct-message callables
      that validate the follow edge for
      `messagePrivacy=peopleYouFollow`, then verify every export is ACTIVE at
      the new revision. During this intentionally short fail-closed window,
      the compatibility-aware push guard still permits a genuine legacy row
      only while its live source has no generation pointer. Once a new
      callable writes a pointer, the same guard suppresses/deletes the old
      trigger's duplicate and accepts only the exact generation row:

   ```bash
   firebase deploy --only functions:onNotificationCreated,functions:openDirectConversation,functions:sendDirectMessage,functions:reserveDirectMessageAttachment,functions:finalizeDirectMessageAttachment --project yovoice-ec54a
   firebase functions:list --project yovoice-ec54a
   ```

   Describe each of those five Functions and its Cloud Run service with the
   two commands from step 1. Require `state: ACTIVE`, a changed `updateTime`,
   matching expected latest-created/latest-ready revisions, and 100% serving
   traffic on that revision before continuing. Inspect logs for callable errors,
   `onNotificationCreated failed` and `Skipped stale social notification
   cleanup` after every stage.

   b. only after that verification, deploy the backward-compatible cleanup
      consumers first. They understand both the deployed pointer-less graph
      and the new generation pointers, but do not introduce a new producer:

   ```bash
   firebase deploy --only functions:cancelFriendRequest,functions:removeFriend,functions:setUserBlock --project yovoice-ec54a
   firebase functions:list --project yovoice-ec54a
   ```

   Describe all three and verify their new ACTIVE revisions before stage c.

   c. deploy and verify the request resolver next. It consumes both legacy and
      generation-bound requests and writes the upgraded friendship mirrors:

   ```bash
   firebase deploy --only functions:respondToFriendRequest --project yovoice-ec54a
   firebase functions:list --project yovoice-ec54a
   ```

   Describe it and verify its new ACTIVE revision before stage d.

   d. deploy and verify follow lifecycle handling. The widened DM validators
      are already live before `setFollow` can create a three-field edge:

   ```bash
   firebase deploy --only functions:setFollow --project yovoice-ec54a
   firebase functions:list --project yovoice-ec54a
   ```

   Describe it and verify its new ACTIVE revision before stage e.

   e. deploy `sendFriendRequest` last, after every production consumer can
      retire its generation-bound request and notification atomically:

   ```bash
   firebase deploy --only functions:sendFriendRequest --project yovoice-ec54a
   firebase functions:list --project yovoice-ec54a
   ```

   Describe it and verify its new ACTIVE revision before the journey smoke.

   A blanket Functions deploy may offer to delete the legacy triggers too
   early and is not a substitute for these verified stages. Do not combine
   stages b-e: a comma-separated deploy is not atomic, and a new producer
   reaching production before its cleanup consumer can strand an alert.

4. verify send → cancel, send → decline, send → accept and unfriend with two
   test accounts, including bell counts. During this compatibility window the
   old triggers may still create their retired pair-lifetime ids; the corrected
   push trigger must delete those rows without a second push, while the
   generation-specific callable row remains the single visible event;
5. explicitly delete the retired `europe-west1` triggers, confirm the prompt,
   and verify they are absent from `firebase functions:list`:

   ```bash
   firebase functions:delete onFriendRequestCreated onFriendRequestResolved onFollowerCreated --region europe-west1 --project yovoice-ec54a
   firebase functions:list --project yovoice-ec54a
   ```

6. after the retired triggers are confirmed absent, take a managed Firestore
   export of the `notifications` collection group to an approved restricted
   backup location, or record explicit release-owner acceptance that removing
   retired notification history is irreversible. Then run the bounded
   aggregate-only compatibility sweep in dry-run mode as a sample, and apply
   it page by page until `reachedEnd` is true. The sweep reuses the same source-
   generation predicate as push: it preserves a genuine legacy request,
   friendship or follow whose live source has no pointer, and deletes only a
   source-less row or a legacy duplicate of an upgraded source. This closes
   the case where a legacy trigger wrote its deterministic row but the non-
   retrying push trigger hit a transient cleanup error:

   ```bash
   npm --prefix functions run scrub:retired-social-notifications -- \
     --project yovoice-ec54a --max-documents 5000
   npm --prefix functions run scrub:retired-social-notifications -- \
     --project yovoice-ec54a --apply --restart --max-documents 5000
   npm --prefix functions run scrub:retired-social-notifications -- \
     --project yovoice-ec54a --apply --max-documents 5000
   ```

   The dry-run does not persist a cursor and cannot prove a full dataset larger
   than 5000 documents. Continue the apply command while `reachedEnd` is false.
   Then begin a separate verification pass with `--apply --restart`, continue
   it page by page to `reachedEnd: true`, and require `plannedDeletes: 0` on
   every page. If any verification page deletes a row, finish that pass and
   start a new verification pass from the beginning; only an all-zero pass to
   `reachedEnd: true` is completion. `--restart` without `--apply` is a no-op.
   Deletes carry each scanned document's `lastUpdateTime` precondition, so a
   concurrent rewrite aborts the page without advancing its cursor. The
   command never prints a uid or document path.
7. repeat send → cancel/decline/accept → unfriend and follow → unfollow →
   follow after deletion. Confirm notification document ids carry a generation
   suffix and no exact `friendRequest_{actor}`, `friendAccepted_{actor}` or
   `follow_{actor}` row remains;
8. run a two-device FCM smoke, then release the verified Hosting artifact.

### Friends rollout abort and rollback boundaries

- Before stage 3b, no new social producer is live. The captured pre-release
  Rules, push and DM revisions may be restored as a consistent set.
- From stage 3b onward, prefer a forward fix. If a social rollback is required,
  restore all six pre-ADR social callables from the same pinned source revision;
  never mix restored legacy triggers with only some new social callables.
- Once `setFollow` has written any three-field edge, keep the widened Rules and
  all four widened DM validators live. The old exact two-field versions would
  deny follower lists and `peopleYouFollow` DMs. They may be restored only
  after a separately verified migration removes every notification pointer.
- After step 5, a full rollback also requires restoring all three legacy
  triggers from the same pinned pre-release source alongside the six old
  social callables. Do not improvise a dual-writer mix; pause and use the
  incident process if that coordinated restoration cannot be verified.
- Sweep deletes are irreversible without the step-6 export. Restoring code or
  triggers does not restore removed history.

At any abort point, capture the affected Functions' revisions and logs before
changing them again, stop before Hosting, and rerun the two-account journey
against the final serving revisions.

No index change belongs to this rollout. The Rules change is a
backward-compatible read-schema widening and must precede Functions because
new follow edges carry `notificationId`; old rows need no migration and use
the legacy cleanup fallback. Do not delete the legacy triggers before the
corrected callables are verified live.

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

   ADR-114's deployed source keeps legacy two-field edges valid and permits one
   optional bounded `notificationId`. Re-running the scrub preserves that
   server-owned pointer; it never strips the active notification generation.

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

- Google: the Firebase Android app contains debug, release/upload, and Google
  Play App Signing SHA-1 plus SHA-256 fingerprints. The Play fingerprints were
  registered and `google-services.json` was refreshed on 2026-08-26 after the
  first internal-track upload. Deploy the Flutter Hosting build and verify that
  the production popup reaches Google's account chooser without
  `redirect_uri_mismatch`. A real Play-installed Google Sign-In smoke test is
  still required for each release candidate.
- Apple: the `app.yovoice.web` Service ID, dedicated Sign in with Apple key,
  enabled Firebase `apple.com` provider, `app.yovoice` capability and matching
  `YO Voice App Store` provisioning profile are configured. Configured shipped
  targets enable Apple by default; an unconfigured build must pass
  `YOVOICE_APPLE_SIGN_IN_ENABLED=false` and fails closed. A confirmed missing
  provider disables the control, while transient probe failures remain
  retriable. After each auth release, smoke-test a real Apple account on web,
  Play-installed Android and a signed iOS build. The APNs key documented below
  is notification-only and is not valid for Apple Auth.

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
| `publishPublicStatsSchedule` | **Deployed 2026-08-20** | present in `functions:list` as a v2 scheduled function in `europe-west1`; `publicStats/live` verified against independent `count()` aggregates |
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

### RELEASED 2026-08-20: `publishPublicStatsSchedule`

**This section is superseded. It described `cb4651a`; the function was
rewritten afterwards and all three preconditions below were designed out
rather than waited on.** It deployed on 2026-08-20 and is running.

Verified in production one minute after deploy — `publicStats/live` holds
`{schemaVersion: 2, activeAccounts: 18, existingRooms: 45}`, and independent
`count()` aggregates returned exactly 18 and 45. The numbers are real.

How each precondition was retired:

1. **Public read rule** — `publicStats/live` is now one of two pinned publicly
   readable documents, alongside `publicShowcase/live`.
2. **`COLLECTION_GROUP` index on `activeVoiceSessions`** — no longer needed.
   The function aggregates `publicProfiles` and `rooms`, and touches
   `activeVoiceSessions` not at all.
3. **The wrong data source** — removed rather than published. There is still no
   honest live-presence figure, so the document carries **no** `peopleTalkingNow`
   field at all. `activeAccounts` counts `publicProfiles` (not `users`, which
   retains banned, disabled and Auth-orphan rows and would overstate by roughly
   two to one), and `existingRooms` counts every room rather than filtering on
   `isLive`, because nothing reliably clears `isLive` after a crash.

Retained below for the reasoning, which still explains why a live-presence
number is not published:

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

### RELEASED 2026-08-23: the fixed desktop rail and the timezone world-map card

**Hosting only.** No Cloud Functions, Firestore rules, index or Storage change
was part of this release — the change is entirely client-side
([ADR-107](Decisions.md#adr-107-the-desktop-rail-owns-its-scroll-position-and-sizes-its-decoration-from-the-rail-not-the-window)).

| Artifact | Command | Verification |
|---|---|---|
| Flutter web | `gh workflow run firebase-hosting-merge.yml --ref main -f deploy_hosting=true` | `verify_and_build: success`, `deploy_hosting: success` (run `32655096468`) |

**Verified by fingerprinting the served bytes, not the deploy log.** The
repository's own standing rule — a green deploy means the upload succeeded,
nothing more:

| | before | after |
|---|---|---|
| `https://app.yovoice.app/main.dart.js` | 6,060,653 B, sha256 `1ee69af6…` | 6,091,200 B, sha256 `c293968af468f1ae` |
| `resolvedOptions` (the new timezone reader) | **0** | **1** |
| `Intl.DateTimeFormat` binding | **0** | **1** |

`cmp` reports the served artifact is byte-identical to the locally built
release. The before-column is what production had been serving since the
2026-08-20 wave, which is how this release was found to be needed at all.

**Why this needed a deploy at all, stated plainly:** the fix had been sitting
in `main` since `7308fff` with CI green, and the Roadmap entry said
"SOURCE ONLY". Source being correct is not the same as users having it — the
gap is invisible in every console and shows up only when the served bytes are
fingerprinted.

**Not deployed, and unchanged by this release:** `sweepStrandedLiveRoomsSchedule`
remains pending (see the section below), and the DM server-only change from
`claude/silly-hugle-e8a52c` touches `firestore.rules`, which was NOT deployed
here. Rules in production still predate that merge.

### RELEASED 2026-08-23T18:53:33Z: server-only Direct Message rules

`firestore.rules` in `main` makes DM creation server-only
(`conversations/{id}/messages/{id}` → `allow create: if false`). It was audited
for production deployment and **deliberately not deployed**. One gate did not
reach PROVEN SAFE.

**The delta is exactly one authorization.** The deployed ruleset was read from
the live project (ruleset `8178e94d-f20b-46be-bdc4-c92005ea86a6`, released
2026-08-22T12:17:28Z) and is byte-identical to `git show e399867:firestore.rules`.
`diff` against `main` is two hunks: one comment-only, one the `create` rule.
The `update`, `read` and `delete` rules are **byte-identical** — no secondary
operation changes.

**What passed.**

| Gate | Result |
|---|---|
| Firestore rules suite (against the NEW rules) | 485 passed / 0 failed |
| Storage rules | 52 / 0 |
| Cross-service family media | 11 / 0 |
| Cloud Functions | 783 / 0 |
| `flutter analyze` | clean |
| `flutter test` | 1208 passed |
| Production callable | `sendDirectMessage` ACTIVE, v2, `europe-west1`; all 10 DM callables ACTIVE |
| Served web bundle | sha256 `c293968a…`, contains `sendDirectMessage`, contains `_sendTextMessageDirectly` **0 times** |
| Website (`yovoice-website`) | zero `collection(` across all 78 commits and all branches; 4 doc paths, none DM |
| Store clients | none exist — Roadmap: "*Not started — no published iOS/Android builds exist yet*"; 0 releases, 0 version tags, no mobile CI job |
| Secondary ops (edit / delete / react / markRead) | field sets checked against the update allowlist — all four PASS |
| Callable sender identity | `senderId: auth.uid`; a client-supplied `senderId` is **rejected** by `requireExactInput`, not merely overridden |

**The blocker: stale browser sessions.** A tab or installed PWA loaded before
the 2026-08-23 Hosting release runs a build that still contains the
direct-write fallback. Nothing in the product forces a reload, Firebase Auth
refreshes tokens indefinitely, and there is no `minimumVersion`, `forceUpdate`
or kill-switch anywhere in `lib/`, `functions/`, `web/` or `firestore.rules`.

Production shows that fallback firing for real: on 2026-08-18 one account sent
via the callable at 20:46:15 and then wrote three DM documents **directly** at
20:49:07 / 20:49:11 / 20:49:24. Those documents are the legacy 14-field shape
(the server writes 16, adding `schemaVersion` and `sequence`).

**Two corrections to the first audit pass, both material:**

1. An audit agent read those 2026-08-18 writes as proof the *current* client
   falls back. It is not. `d5909bf` — the commit that removed
   `_sendTextMessageDirectly` — is dated **2026-08-19**, a day later. Those
   writes are the pre-migration client behaving as designed at the time. The
   currently served bundle contains that symbol **zero** times.
2. The same pass called the failure mode "silent". It is not, for the case
   that matters: `chat_screen.dart:242` catches the error and shows it, and
   `_controller.clear()` runs only on success, so the text survives. The old
   client at `7308fff` has the same handling. A stale tab would fail
   **loudly** and recover on reload (`cache-control: no-cache` is set on
   `main.dart.js`, confirmed live).

**Why it is still not deployed.** "Small, visible and self-healing" is not the
same as proven. The population of stale sessions is unmeasured, and the
project bar for a production rules change is PROVEN SAFE.

**How to close it — any one of these is sufficient:**

1. **Ask the testers to hard-reload.** Production holds 5 conversations, 62
   lifetime messages and roughly 4 active accounts, all maintainer-owned test
   accounts. Direct confirmation is stronger than any inference available here
   and takes minutes.
2. **Revoke refresh tokens** for those accounts, forcing a fresh load.
3. **Observe.** Since 2026-08-18T20:49:24Z every DM has been server-written —
   four consecutive messages across four days. Extend that window and re-run
   the enumeration; a stated quiet period with zero 14-field documents bounds
   the risk empirically.

**Rollback, pre-staged and unused.** Prior ruleset:
`projects/yovoice-ec54a/rulesets/8178e94d-f20b-46be-bdc4-c92005ea86a6`, source
byte-identical to `git show e399867:firestore.rules`. Restore with
`firebase deploy --only firestore:rules --project yovoice-ec54a` from that
commit. Note the asymmetry that makes the gate matter: the rules change is
instantly reversible, but a message a user believed they sent is not.

**DEPLOYED.** The blocker below was closed on 2026-08-23 and the rules shipped.

| | |
|---|---|
| Command | `firebase deploy --only firestore:rules --project yovoice-ec54a` |
| Commit | `57ac1e87aab650a981bb1fa1b0620d82037de10b` |
| Ruleset before | `8178e94d-f20b-46be-bdc4-c92005ea86a6` |
| Ruleset after | `9257845f-a355-4f3f-80eb-4b51e47b47e9` (released 18:53:33Z) |
| Live source | sha256 `dd0857906500ff33` — **byte-identical** to `git show 57ac1e8:firestore.rules`, read back from the Rules API |
| Delta on the live ruleset | 2 hunks; **0** changes to `read`/`update`/`delete` |

**How the stale-client gate was closed — by code, not by traffic.** The
observation window was empty (zero new DMs since 2026-08-22T13:04:28Z), so
"no legacy writes appeared" proved nothing on its own and was not used as
evidence. What closed it:

1. Web is the only client surface — no store build exists, and the website has
   no DM capability.
2. **No caching service worker has ever been registered by this app.**
   `serviceWorkerSettings` has never appeared in `web/` in any commit, no
   historical `web/index.html` references a service worker, and a live browser
   at `app.yovoice.app` reports `serviceWorkers: 0` and `caches: []`.
3. `cache-control: no-cache` on `main.dart.js`, confirmed live.
4. Therefore a hard refresh **must** fetch current bytes — there is no
   mechanism that could keep old JavaScript alive.
5. The served bundle contains `_sendTextMessageDirectly` **zero** times.
6. Therefore a refreshed client is structurally incapable of a direct DM
   write, and the maintainer confirmed every test account was refreshed.

**Token revocation was deliberately NOT performed.** Revoking refresh tokens
forces re-authentication but does **not** force a JavaScript reload — the page
keeps running whatever bundle it already has. Against a stale-code risk it
would be theatre, and it would have inconvenienced the accounts for nothing.

**Post-deploy verification, and its limits, stated plainly.** Confirmed:
ruleset id changed; live source byte-identical to the commit; delta is
create-only; `sendDirectMessage` still ACTIVE; zero `PERMISSION_DENIED` or
`failed-precondition` in Cloud Functions logs; zero new client-written
documents. The 485-case rules suite validated exactly these bytes before
release.

**NOT verified by the deploying session: the positive path.** Sending,
receiving, opening a conversation and read-state changes were not exercised,
because that needs authenticated test-account credentials and none were
requested or used. The structural reason this is low-risk rather than unknown:
`sendDirectMessage` writes through the **Admin SDK**
(`direct_integrity.js:1` → `firebase-admin/firestore`), which bypasses
Security Rules entirely, so `allow create: if false` cannot reach the
callable's writes. A human smoke test of send/receive is still the honest
closing step.

**Rollback, prepared and unused.** Previous ruleset
`8178e94d-f20b-46be-bdc4-c92005ea86a6`, source byte-identical to
`git show e399867:firestore.rules` (sha256 `0ce4b5fd10567cc5`). Restore by
deploying rules from `e399867`. Note the asymmetry: the rules change reverses
in seconds, but a message a user believed they sent does not come back.

**Only Firestore rules were deployed.** No Hosting, Functions, indexes,
Storage rules or Remote Config. `sweepStrandedLiveRoomsSchedule` remains
pending and untouched.

---

**The pre-deployment audit that gated this release is retained below.**


### Pending release: `sweepStrandedLiveRoomsSchedule`

The scheduled repair for a room left `isLive: true` with an empty
`participants` subcollection — the `RoomVoiceEntryCoordinator` start→join
window, and any process death inside it. Full reasoning in
[ADR-092](Decisions.md#adr-092-a-scheduled-sweep-closes-the-room-no-client-can-close-and-the-roster-is-still-the-only-thing-that-proves-it-empty).

**Cloud Scheduler is NOT a new deploy dependency, and the note that said it
would be is wrong.** ADR-091 recorded this sweeper as "the first scheduled
function in `functions/`". It would not have been. Seven `onSchedule`
functions already exist and ship from this codebase:

| Function | Source |
|---|---|
| `publishPublicStatsSchedule` | `stats/public_stats.js` |
| `publishPublicShowcaseSchedule` | `marketing/public_showcase.js` |
| `expirePremiumIdentity` | `premium/entitlements.js` |
| `reconcileAchievementsV1` | `achievements/migration.js` |
| `processPendingContentCleanupSchedule` | `integrity/stage_b_functions.js` |
| `expireAbandonedMomentDraftsSchedule` | `integrity/stage_b_functions.js` |
| `expireAbandonedVoiceCommentDraftsSchedule` | `integrity/stage_b_functions.js` |

`publishPublicStatsSchedule` is confirmed ACTIVE in production in
`europe-west1` (see the 2026-08-20 table above), so the Cloud Scheduler API,
its service account and its region are all already provisioned on
`yovoice-ec54a`. This release adds an eighth schedule to an existing
mechanism. ADR-091's note is corrected in place.

**No index deploy is required, and that was checked rather than assumed.**

- The discovery query is a **bare equality** — `rooms.where("isLive","==",true)`
  — served by Firestore's automatic single-field index. `rooms.isLive` has no
  `fieldOverrides` entry, so the [indexing
  trap](Firebase.md#a-fieldoverrides-entry-replaces-automatic-single-field-indexing)
  does not apply to it; only `rooms.roomId` is overridden.
- Two already-deployed functions run a **strictly harder** version of the same
  query today — `getAdminDashboard` and `getStaffOverview` both filter
  `status == "active"` **and** `isLive == true`. If those work in production,
  this one does.
- `deleteActiveVoiceSessionsForRoom()` is reused unchanged and its
  `collectionGroup("rooms").where("roomId","==",…)` lookup is backed by the
  **existing** `rooms.roomId` `COLLECTION_GROUP` override.

This matters because the comparable mistake is on the record: the
`entitlements(isPremium, currentPeriodEnd)` composite had never been deployed,
so the scheduled `expirePremiumIdentity` failed every run and **Premium never
expired for any account** — invisibly, because the emulator does not enforce
composite indexes. A schedule that throws `FAILED_PRECONDITION` on its first
production run looks identical in `functions:list` to one that works.

**The query deliberately does not filter on `status`.** 25 of the 45
production rooms carry no `status` field, and a `where("status","==","active")`
clause would drop every one of them — the same defect `roomIsActive()` was
written to fix in `b7c6d99`. The filter is applied in memory instead. Note in
passing that the two dashboard queries above **do** carry that clause, so both
undercount live rooms on the legacy shape; that is pre-existing and untouched
by this release. *(Closed in source on 2026-08-20, after this release and not
yet deployed: `getAdminDashboard` and `getStaffOverview` now share
`listLiveActiveRoomDocs()`, which makes exactly the query described in this
paragraph. See
[ADR-097](Decisions.md#adr-097-a-live-room-count-that-must-honour-an-absent-status-is-a-bounded-read-not-a-count-aggregate).)*

Safe release order:

1. Deploy Cloud Functions and confirm `sweepStrandedLiveRoomsSchedule` appears
   in `firebase functions:list` as a v2 scheduled function in `europe-west1`.
2. Confirm the Cloud Scheduler job exists and is ENABLED, then watch **one**
   run complete. A first run that throws is the failure this section exists to
   catch, so read the log rather than trusting the deploy output.
3. Nothing else. There is no client, rules, index or Storage change in this
   release, and no ordering constraint against the app — the function only
   ever *narrows* what Home and Discover show, so an older client cannot break
   on it.

**Rollback is deleting the Cloud Scheduler job**, not redeploying: the
function is idempotent and stateless, and pausing the job stops all writes
immediately. Nothing it writes needs undoing — `isLive: false` with a stamped
`endedAt` is the same state a normal leave produces.

**Verify the grace period before widening it.** `GRACE_PERIOD_SECONDS` is 300
and the floor is 60. Lowering it toward the start→join window is the one
change to this file that could make it evict a real user; raising it only
makes ghosts linger longer.

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

**A POST-RELEASE AUDIT FOUND A DEFECT IN THIS WAVE, fixed and redeployed in
`b7c6d99`.** Five callables gated on a bare `room.status !== "active"` while
the ruleset reads `.get('status','active')`, and 25 of 45 production rooms have
no `status` field. The rules authorised the `isLive: true` write and the token
endpoint then refused the same room with *"This room is not currently live."* —
so for those 25 rooms the wave did not fix the reported bug, it relocated it,
and left the room flipped live with no way to switch it off. See
[ADR-093](Decisions.md#adr-093-an-absent-status-means-active--one-reading-of-the-field-shared-by-the-rules-and-every-callable).

**`sweepStrandedLiveRoomsSchedule` IS DEPLOYED, and it got there by accident —
worth reading before trusting any deploy record in this file.** A concurrent
session was writing the sweeper into the working tree while this session ran
`git add -A` to commit the `status` fix. Its 331 lines of implementation, its
342 lines of tests and its `index.js` export were swept into `b7c6d99`, whose
message describes only the `status` fix, and the `firebase deploy --only
functions` that followed put a **scheduled function that closes rooms** into
production without its author ever verifying or releasing it.

Checked after the fact rather than assumed, because the state was live either
way:

| Question | Answer |
|---|---|
| Is it actually deployed? | Yes — `sweepStrandedLiveRoomsSchedule`, v2 scheduled, `europe-west1`, in `functions:list` |
| Has it closed anything wrongly? | No. **Zero** rooms carry an `endedAt` inside the last 12 hours |
| Does it skip occupied rooms? | Yes. All 3 live production rooms have a roster of 1 and were left alone |
| Do its tests pass? | 15 dedicated cases; 727 Functions tests overall, 0 failures |
| Is its logic sound? | It closes only `isLive == true` with an **empty roster**, re-read inside the transaction, past a grace period, skipping `deletionInProgress` |

So the outcome is fine and the function is staying. The process was not: **`git
add -A` is unsafe in a tree another session is writing to**, and a commit
message that does not describe everything in the commit makes the deploy record
downstream of it wrong. Stage explicit paths when sessions share a tree.

The version running in production is `b7c6d99`'s. The working tree has since
gained a logging fix (passing the Error as an argument so `entryFromArgs` does
not overwrite `message`) and formatting; the room-closing logic is byte-identical,
so production behaviour is equivalent and the redeploy is for log quality.

Two things this says about the release above: the byte-exact read-backs proved
the right BYTES shipped and proved nothing about whether they WORK, and the
production shape census — run for the rules and not for the callables — would
have caught it had it been applied to both sides. New rooms were never
affected: `createRoom` writes `status`, `roomType` and `experience`.

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

**Every production room type is covered by the fix**, which is what the "check
every room type" request actually needed answering:

| `roomKind` / `experience` in production | Count | Screen it opens |
|---|---:|---|
| no `roomKind`, no `experience` | 27 | Community — `RoomExperience.fromValue` defaults there |
| `experience: community` | 8 | Community |
| `experience: podcast` | 4 | **Broadcast** — `fromValue` maps the legacy `podcast` value onto `broadcast`, so these are Broadcast Rooms, not a third product |
| `experience: broadcast` | 3 | Broadcast |
| `roomKind: clubLounge`, `experience: community` | 3 | Community, with lounge teardown |

45 of 45. Both screens received the liveness, authority, ended-state and
audio-ownership fixes, so there is no room in production that reaches the old
"This room is not currently live." path on unmute.

The room from the original report is `club_lounge_family_H6S…` — `clubLounge`,
`isLive: false`, `status: active`, `participantCount: 0`,
`membersCanStartVoice: true`, not deleting. That is exactly the dormant-startable
state photographed in `voice-family-dormant-startable-390.png`: it now offers
**Start voice**, not a microphone that fails.

**The two Moments indexes finished building at 01:53 and were then EXERCISED,
not merely read as `READY`.** Both feed queries were run against production
through the Admin SDK — `where('isPublished','==',true).orderBy('likeCount','desc')`
and the `createdAt` variant — and both returned without `FAILED_PRECONDITION`.
They return 0 documents because no Voice Moment has been published yet, which
is why the app renders the "No Voice Moments yet" empty state rather than a feed.

**Read the collection name carefully: it is `voiceMoments`, not `moments`.**
The first verification attempt queried `moments`, got `FAILED_PRECONDITION` on
both queries, and looked exactly like the club-invite defect. The probe was
wrong, not the deployment. `MomentDiscoveryService` queries `voiceMoments`
(`moment_discovery_service.dart:127`), the repo declares the indexes under that
name, and the deployed resources are `collectionGroups/voiceMoments/indexes/...`.

**The REST endpoint below is a trap.** `collectionGroups/{anything}/indexes`
returns **every** index in the database regardless of the name in the path, so
reading its output without checking each resource's own `name` attributes
indexes to the wrong collection. Check state and identity together:

```
TOKEN=$(gcloud auth application-default print-access-token)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://firestore.googleapis.com/v1/projects/yovoice-ec54a/databases/(default)/collectionGroups/voiceMoments/indexes" \
  | python3 -c "import sys,json; [print(i['state'], i['name'].split('collectionGroups/')[1]) for i in json.load(sys.stdin)['indexes']]"
```

An index reporting `READY` is still not proof the query works. Run the query.

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

> **Superseded 2026-08-16; its social-trigger instructions were superseded
> again by ADR-114 on 2026-08-24.** Everything listed below was deployed —
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

Web App Check has a separate release prerequisite. Register the production
web app with reCAPTCHA v3 in Firebase Console, then define the public site key
as the repository variable `YOVOICE_WEB_RECAPTCHA_SITE_KEY`. Hosting CI passes
it as `--dart-define=YOVOICE_WEB_RECAPTCHA_SITE_KEY=...`. A missing value keeps
the application usable but leaves App Check disabled, so Functions enforcement
must remain off until a verified build sends valid tokens and telemetry shows
that the tester cohort is attested. Debug web builds use Firebase's debug App
Check provider and its emitted token must be registered in Firebase Console.

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
`6a817efe-d05c-443b-a10b-3f91ca381322`, expires 2027-08-15), Apple
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

### Mobile beta release status — 2026-08-26

Commit `e7f3cd45ea4e97b27a0e9b784a82ca9c93cab859` produced mobile build
`1.0.0 (3)`. The exact commit passed the full verification workflow, browser
smoke workflow, and CodeQL workflow before upload.

- **iOS:** TestFlight build `1.0.0 (3)` is in `Testing`, with the existing
  internal group and two individual testers assigned. The export-compliance
  declaration is complete. IPA SHA-256:
  `a9d6bb849f8e296744cf27daafba12204a86a4041ab5517b799d4ce6e840d98d`.
- **Android:** Google Play internal testing is active for version code `3`
  (`1.0.0`), with five validated tester accounts assigned. The store may show
  the temporary name `app.yovoice (unreviewed)` until the application setup and
  review are complete. AAB SHA-256:
  `3231cdd6533339fb1e43ece4d835aaf362a4f93b9c9feed35f3f188d5efead87`.
- **Scope:** this is a test-channel release, not a production-store release.
  Premium purchases are inactive; Apple Sign-In was intentionally disabled in
  this historical build 3 Android beta (superseded by build 6); and the known
  non-host room-message permission error remains disclosed to testers.
- **Acceptance gate:** perform the physical iPhone-to-Android notification,
  live-room, deep-link, Google Sign-In, and audio smoke tests after both builds
  are installed from their store test channels. Do not describe the release as
  production-ready until those checks and the remaining store-listing/policy
  work pass.

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

## Stripe Premium rollout (source-ready; provider rollout disabled)

The secret-free `getPremiumBillingContext` callable was deployed and verified
on 2026-08-28 with `checkoutAvailable=false`; none of the four Stripe mutation
handlers was exported or deployed. No live Stripe object, credential, webhook
or checkout is proven by that catalog deployment or by source readiness. Keep
billing disabled until the seller/business, applicable tax and
customer-facing refund/dispute handling have been approved and configured; do
not publish claims this repository does not establish. Then release in this
order:

1. Re-run the source gates below. Confirm the client request is exactly
   `{plan, paymentMethod?}`, with `paymentMethod` defaulting to
   `recurring` and accepting only `blik` otherwise. Amount, currency, Price,
   Customer, payment-method list and return URLs must remain server-owned.
2. In **live** Stripe create one Premium Product and four immutable Prices:
   EUR 600/month recurring, EUR 6000/year recurring, PLN 2600 one-time and PLN
   26000 one-time. The one-time Prices back the 30-day and 365-day BLIK offers;
   they must not carry a recurring interval or reusable mandate. All four must
   match the source validator and the same live Product. Configure business,
   receipt/invoice and tax settings only from approved real account data.
3. Activate cards and PayPal for both recurring EUR Prices. Complete any Stripe
   [PayPal activation](https://docs.stripe.com/payments/paypal/activate) and
   [recurring approval](https://docs.stripe.com/payments/paypal/set-up-future-payments#enable-recurring-payments),
   then prove it is actually offered to an eligible live customer; merely
   seeing PayPal in Dashboard is not evidence. Confirm the source sends exactly
   `payment_method_types=[card,paypal]` for recurring Checkout and prove no
   other enabled Dashboard method leaks into this product. Activate
   [BLIK](https://docs.stripe.com/payments/blik) for the two one-time PLN Prices
   and prove Checkout presents it only on the prepaid path. Do not market
   provider availability before these account/country checks pass.
4. Create one active Customer Portal configuration for the two recurring EUR
   Prices. It must allow cancellation and only approved recurring plan changes.
   Neither BLIK Price belongs in Portal subscription updates because BLIK does
   not renew.
5. Publish the reviewed Terms and Privacy copy before exposing Checkout. The
   copy must distinguish recurring card/PayPal from prepaid BLIK, state the
   paid terms (30 or 365 days), and explain cancellation without inventing tax
   or refund rules.
6. Set Firebase parameters `STRIPE_MONTHLY_PRICE_ID`,
   `STRIPE_YEARLY_PRICE_ID`, `STRIPE_BLIK_MONTHLY_PRICE_ID`,
   `STRIPE_BLIK_YEARLY_PRICE_ID`, `STRIPE_PORTAL_CONFIGURATION_ID` and
   `STRIPE_EXPECTED_MODE=live`. Set Secret Manager values
   `STRIPE_SECRET_KEY=sk_live_…` and the **live endpoint's**
   `STRIPE_WEBHOOK_SECRET`. Read every value back without printing secret
   material and verify all four Price ids resolve to live objects.
   Keep `STRIPE_BILLING_EXPORTS` disabled throughout this preparation; the
   secret-free catalog must still return `checkoutAvailable=false`.
7. Register the live signed webhook for the exact Checkout, asynchronous
   payment, Subscription, Invoice and financial-risk events handled by the
   source. Only after the endpoint, secrets and four live Price ids are ready,
   set `STRIPE_BILLING_EXPORTS=enabled`. Deploy Firestore Rules first if their
   billing denial changed, then only the Premium billing Functions and
   Auth-deletion cancellation. Read back the export list and context; all four
   mutation handlers must be ACTIVE and checkout must become available only at
   this explicit cutover. Do not expose a compatible client beforehand.
8. With explicitly authorized internal live accounts, smoke each of the four
   offers: EUR monthly card, EUR annual PayPal, PLN monthly BLIK and PLN annual
   BLIK. Prove card/PayPal create one canonical Subscription and Portal access;
   cancel-at-period-end must show `ends` while retaining the paid window. Prove
   BLIK creates no Subscription or Portal action, grants exactly 30/365 days,
   writes `source=stripe_prepaid` plus `renewalBehavior=none`, exposes the exact
   end date and requires a new purchase after expiry. A redirect
   before webhook confirmation must grant nothing.
9. Exercise failed/abandoned Checkout, async payment failure, webhook replay,
   duplicate/concurrent Checkout, suspended payer Portal access and Auth
   deletion. Confirm no duplicate Customer/subscription, no extension from an
   unpaid renewal, no replayed prepaid grant and no recreated deleted user.
10. Reconcile Stripe against `billingAccounts`, `entitlements` and
    `stripeWebhookEvents`. Every Customer must map to exactly one uid; every
    recurring entitlement needs its paid canonical Invoice; every BLIK
    entitlement needs one successful one-time payment receipt and the exact
    fixed end date. Resolve every failed event before enabling general access,
    then monitor Checkout failures, webhook retries and entitlement drift.

Predeploy gates:

```bash
node --check functions/premium/billing_context.js
node --check functions/premium/stripe_billing.js
node --test functions/test/stripe_billing.test.js
firebase emulators:exec --only firestore --project demo-yovoice \
  "node firestore-tests/rules.test.js"
```

Run Stripe test mode only against the Functions emulator or a separate
non-production Firebase project. **Never** put `sk_test_`, test Price ids, a
test webhook secret or `STRIPE_EXPECTED_MODE=test` in `yovoice-ec54a`; do not
send Stripe CLI test events to the production webhook. Production smoke uses
live objects and therefore requires explicit operator authorization.

With `STRIPE_BILLING_EXPORTS` disabled, deployment discovery must export the
secret-free catalog but no Checkout, Portal, webhook or Stripe Auth-deletion
handler. With it enabled in an isolated/predeploy environment, discovery must
export exactly those four additional handlers and require the live rollout
configuration. A UI-only hidden button is not a billing launch gate.

Rollback: stop creation of new Checkout sessions first, while leaving the live
webhook and recurring Customer Portal available so existing payers can cancel
and late provider events can reconcile. Do not revoke an already-paid BLIK term
merely because new sales are paused. Restore only a revision that understands
all four Prices and both lifecycle shapes; the superseded ADR-067 two-Price PLN
implementation is not a valid rollback target. Never delete
`billingAccounts`, entitlements or webhook receipts. Archive Prices only after
no active Subscription or paid prepaid term depends on them.

## ADR-119 moderator Premium-preview rollout (source complete; release pending)

This runbook releases the derived product preview for active exact
`moderator` and `superModerator` roles. It does **not** create a subscription,
rewrite `entitlements/{uid}` or enable Stripe. Source readiness, a successful
local test and a CLI deploy response are not production evidence; do not mark
ADR-119 deployed until every readback below is complete.

### Prerequisites and evidence capture

1. Pin the reviewed commit and run the complete release gates in
   [TESTING.md](TESTING.md#current-counts) against fresh emulators. Update the
   recorded counts only from those completed runs. Keep
   `STRIPE_BILLING_EXPORTS` in its already-approved state; ADR-119 must not be
   used to turn payment mutation handlers on.
2. Configure Application Default Credentials for `yovoice-ec54a`. Inject
   `YOVOICE_PROTECTED_OWNER_UID` into the operator shell through the approved
   secret path without printing it; the badges and directory backfills refuse
   to derive the protected owner without this guard.
3. Fetch and retain the currently released Firestore rules source using
   [the Rules API procedure](#reading-the-deployed-ruleset-the-verification-standard).
   Record the current Functions revisions as the rollback boundary.
4. Select authorized test accounts for exact `moderator` and
   `superModerator` roles plus a disposable account for the demotion smoke.
   Before changing anything, capture their `users`, `entitlements`,
   `publicBadges`, `publicProfiles`, `userDirectory` and
   `creatorPinnedPosts` state. The entitlement snapshots are the proof that
   preview rollout never rewrites billing truth.

### Release order

1. **Deploy Functions first.** The shared claim/mirror and effective-access
   resolvers are bundled into each deployed Function, so a partial deploy can
   leave old triggers overwriting new projections. Deploy the exact reviewed
   Functions manifest while Stripe export configuration remains unchanged:

   ```bash
   firebase deploy --only functions --project yovoice-ec54a
   firebase functions:list --project yovoice-ec54a
   ```

   Confirm the affected revisions are ACTIVE, including Club creation and
   ownership transfer, Creator pins and cleanup, Premium entitlement expiry,
   profile search/projection, public-badge and directory triggers, and report
   moderation/audit. Do not continue if deployment discovery unexpectedly
   adds Stripe mutation exports.
2. **Deploy Firestore Rules second.** This is the acting-client boundary for
   Creator mode and known-id Creator pins. Run the fresh emulator suite before
   this command, then fetch the released ruleset through the Rules API and
   compare its source byte-for-byte with the pinned `firestore.rules`:

   ```bash
   firebase deploy --only firestore:rules --project yovoice-ec54a
   ```

   A CLI success message without the API readback is not completion evidence.
3. **Converge all existing projections.** New triggers do not replay old user
   documents, so each of the following migrations is mandatory. Review every
   dry-run aggregate before applying; do not apply over an invalid role or
   schema conflict.

   **Public badges:** the first and third commands are read-only. The final
   report must plan zero creates, updates and deletes.

   ```bash
   node functions/scripts/backfill_badges.js --project yovoice-ec54a
   node functions/scripts/backfill_badges.js --project yovoice-ec54a --apply
   node functions/scripts/backfill_badges.js --project yovoice-ec54a
   ```

   **Public profiles and presence:** this script is bounded. For each of the
   three phases below, begin without `--start-after`, record the aggregate
   output, and repeat with the exact returned `nextCursor` until
   `reachedEnd=true`. Start the apply phase and the post-apply no-op phase from
   the beginning again; never reuse a cursor from the preceding phase. Every
   page of the final phase must plan zero profile/presence creates, updates or
   deletes.

   ```bash
   # Dry-run phase; repeat with --start-after '<nextCursor>' until reachedEnd.
   node functions/scripts/backfill_public_profiles.js --project yovoice-ec54a --max-users 500

   # Apply phase; start again from the beginning, then page its own cursor.
   node functions/scripts/backfill_public_profiles.js --project yovoice-ec54a --max-users 500 --apply

   # Post-apply no-op; start from the beginning and page to reachedEnd again.
   node functions/scripts/backfill_public_profiles.js --project yovoice-ec54a --max-users 500
   ```

   **Staff directory:** the first and third commands are read-only. The final
   report must plan zero creates, updates and deletes.

   ```bash
   node functions/scripts/backfill_directory.js --project yovoice-ec54a
   node functions/scripts/backfill_directory.js --project yovoice-ec54a --apply
   node functions/scripts/backfill_directory.js --project yovoice-ec54a
   ```

4. **Perform production readback before releasing a client.** For one active
   exact moderator and one active exact super moderator, verify:

   - `users/{uid}.role` has the expected exact value and the Auth custom claim
     matches after a token refresh, and
     `users/{uid}.roleTransitionInProgress=false`;
   - `publicBadges/{uid}` has that staff role and `isVip=true`;
   - `publicProfiles/{uid}.premiumIdentity=true` and
     `userDirectory/{uid}.isVip=true`;
   - the before/after `entitlements/{uid}` documents are field-for-field
     unchanged; no preview-only account acquired `isPremium`, a plan, period,
     renewal or billing provider;
   - a refreshed/restarted client can enter Creator and Clubs, create no more
     than the effective three-Club limit, and receives no owner or super-admin
     capability from the preview.

5. **Prove demotion convergence.** On the authorized disposable account,
   change `moderator` or `superModerator` to `user` through the audited role
   callable, refresh its token and wait for all three projection triggers.
   With no independent paid entitlement, verify the VIP presentation and
   Creator/Clubs access disappear, `publicProfiles.premiumIdentity` and
   `userDirectory.isVip` are false, and an otherwise-empty `publicBadges`
   document is removed. A pin and Creator account mode must be cleaned up.
   Repeat the readback on a paid-plus-preview fixture if one is authorized:
   demotion must remove only the preview while valid paid access, plan and
   period survive unchanged.

   Also exercise one privileged-to-privileged change (for example,
   `superModerator` to `moderator`). A failed/retried test must never expose
   authority while claim and mirror differ, and the completed retry must leave
   `roleTransitionInProgress=false`. If the marker remains true, retry the same
   audited assignment; do not edit the claim or mirror independently.
6. Only after steps 1–5 pass, release Hosting and the regenerated native build
   8. Verify the IPA/AAB themselves carry build/version code 8; for iOS also
   verify `ITSAppUsesNonExemptEncryption=false` in the packaged Runner plist
   and confirm TestFlight does not enter Missing Compliance.

### Rollback

Stop client rollout first. Restore the captured pre-release Firestore rules so
new preview-only acting requests fail closed, then restore the pinned previous
Functions revisions. Do not delete or edit `entitlements`, billing accounts,
provider records or receipts: ADR-119 did not create them and rollback must not
touch paid access.

After the previous projection derivation is live, run its matching badges,
public-profile and directory backfills through the same dry-run → apply →
post-apply no-op sequence to remove preview-only public state. If the defect is
limited to one projection, keep the secure Rules/Functions boundary and repair
only that projection rather than widening authorization. Record the restored
ruleset, Function revisions and aggregate backfill reports before declaring
rollback complete.

## Direct 1:1 call rollout

Direct calls add server-only signaling, a scheduled expiry query, LiveKit
control-plane cleanup and client reads, so release them in this order:

1. Deploy `firestore.indexes.json` and wait for the
   `directCalls(status, expiresAt)` index to report READY.
2. Deploy `startDirectCall`, `acceptDirectCall`, `declineDirectCall`,
   `cancelDirectCall`, `endDirectCall`, `createDirectCallToken`,
   `expireDirectCallsSchedule`, `onDirectCallControlCreated` and the updated
   `onNotificationCreated`. Confirm every revision is ACTIVE.
3. Smoke a two-user ringing→accept→token→end lifecycle and confirm both
   `directCallLocks` are removed plus the control outbox reaches `complete`.
4. Deploy Firestore Rules, read them back and prove participant get / outsider
   denial against production-safe disposable data.
5. Release Hosting and native build 5. Verify foreground incoming presentation,
   background push, answer/decline/cancel/end, mute latency, busy refusal,
   60-second missed call and notification-to-DM routing.

Rollback the clients first if their call UI is unhealthy, then restore Rules
and Functions from the pinned pre-release revision. Keep the scheduled expiry
and control worker running until no `ringing`/`active` call or pending control
outbox remains; removing cleanup first can strand locks or LiveKit rooms.

## Direct chat reliability rollout (ADR-121)

This release changes notification replay, durable media/direct-call
idempotency and the conversation/message write boundary. Use the exact reviewed
commit and keep the order below. Rules are intentionally last: old clients that
still depend on fallback writes can break if the server-only boundary lands
before build 11 is available to their permanent tester group.

1. Run the complete Flutter, Functions, Firestore Rules and Storage Rules gates
   from [TESTING.md](TESTING.md). In addition, run the focused lost-response,
   notification replay, active-conversation and media suites. Record failures
   from shared-emulator pollution separately and prove each isolated suite on a
   fresh emulator before accepting it as unrelated.
2. Compare production `firebase firestore:indexes` with the complete pinned
   `firestore.indexes.json`. The only expected addition is the managed TTL for
   `notificationDeliveryEvents.expiresAt`; existing 27 composites and five
   field overrides must remain byte-for-byte equivalent after normalizing
   generated `__name__`, `density` and `ttl:false` fields. Deploy without
   `--force`, then read it back:

   ```bash
   firebase deploy --only firestore:indexes --project yovoice-ec54a
   firebase firestore:indexes --project yovoice-ec54a --json
   ```

   The read-back must contain `notificationDeliveryEvents / expiresAt /
   ttl:true / indexes:[]` before any new producer writes ledger rows. Managed
   TTL activation/deletion is asynchronous; absence from read-back blocks the
   notification rollout.
3. Deploy notification producers and direct-call callables before the push
   consumer:

   ```bash
   firebase deploy --only \
     functions:onDirectMessageCreated,functions:onRoomLiveChanged,\
     functions:sendClubInvite,functions:onClubInviteCreated,\
     functions:onClubMemberCreated,functions:startDirectCall,\
     functions:acceptDirectCall,functions:declineDirectCall,\
     functions:cancelDirectCall,functions:endDirectCall \
     --project yovoice-ec54a
   firebase functions:list --project yovoice-ec54a
   ```

   Confirm new ACTIVE revisions and retain the prior revision names. Then deploy
   `functions:onNotificationCreated` alone as the final backend cutover. Send a
   disposable message and replay its trigger in a non-production/emulator
   fixture: the inbox row must keep its original read state, source removal must
   end as `skipped:invalid-source`, and an ambiguous FCM result must remain one
   terminal `dispatching` claim. Start/accept/cancel with a repeated request and
   verify one canonical call and desired terminal state.
4. Release Hosting and native build 11 from the same commit. Confirm build 11
   is actually **Testing** in both permanent TestFlight groups with tester
   notification enabled, and **Available to internal testers** on the existing
   Google Play list. Upload completion alone is not release evidence. On two authorized
   accounts and two physical devices verify:
   - rapid text A/B order, recipient visibility and no duplicate after a
     temporary network loss;
   - active same-chat: no local banner, shell overlay or notification sound;
     different screen/background/terminated: exactly one alert and correct DM
     routing;
   - photo near the size limit and a voice recording preview then send on Wi-Fi
     and throttled cellular;
   - call start, lost-response replay, ringing, accept, mute, end and busy
     refusal, with exactly one foreground ring.
5. After build 11 is available and the intended tester cohort is no longer
   pinned to build 3/10, deploy Firestore Rules, fetch the released ruleset
   through the Rules API and compare it with the pinned source. A participant
   read must still succeed; direct updates to conversation roots and message
   edit/delete/reaction/read fields must fail. If adoption cannot be confirmed,
   hold this step rather than breaking an installed client.
6. Observe callable latency, `unavailable`/`deadline-exceeded`, notification
   replay/claim counts, instance count, cost and call-lock cleanup for at least
   one tester cycle. Build 18 deliberately deploys `minInstances=1` only for
   `sendDirectMessage`, `sendRoomMessage`, `createLiveKitToken`,
   `startDirectCall` and `createDirectCallToken`; search/suggestion callables
   remain at zero. If the measured improvement does not justify the recurring
   cost, redeploy those five endpoints with `minInstances: 0`.

Rollback clients first, then restore Rules only after the previous compatible
Functions are restored. Do not delete notification ledgers, call documents or
locks manually. Keep call expiry/control cleanup running until no active call
or pending control row remains.

## Build 17 tester release evidence (2026-09-01)

Build 17 supersedes the unpublished Android build 16 candidate. Google Play's
pre-publication review showed that the new `CAMERA` permission implicitly made
camera and autofocus hardware mandatory, excluding 425 previously supported
devices. The manifest now declares camera, camera-any, front-camera and
autofocus hardware optional, with a regression test that prevents this device
coverage loss from returning.

- source commit: `2eb063d9a74b5f94d7af81f4575119e312bdafa8`;
- Android: `app.yovoice`, `1.0.0 (17)`, min SDK 24, target SDK 36,
  SHA-256 `511a46b3901daf7c15ff3f9ce9c159ffcc00a8114422383b4137ee8d7087ec9e`;
- iOS: `app.yovoice`, `1.0.0 (17)`, minimum iOS 15.0,
  SHA-256 `8fa12cddf4a07cd8e68b1080180cb589c324a2e78fe4ebdddd7755a6c7b2acc7`;
- local compatibility regression and `flutter analyze`: green;
- the exact commit's CI full Flutter, Functions and Rules gates must be green
  before Hosting or either tester channel is declared delivered.

Functions are deployed first. Restrictive Firestore/Storage Rules remain held
until the private-media IAM, signed-read, migration, zero-token inventory and
compatible-client adoption gates in [SECURITY.md](SECURITY.md) are complete.
