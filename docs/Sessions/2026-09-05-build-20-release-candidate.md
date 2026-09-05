# Build 20 coordinated tester release candidate — 2026-09-05

## Status

**WEB AND BOTH INVITED TESTER CHANNELS RELEASED; ACCEPTANCE GAPS REMAIN.**
The Build 20 mobile/Web runtime is frozen at
commit `941376ef8029030aeec27e1e8ef28a4cead8697b`. Its source, browser,
emulator, release-Web, bounded-render, dependency and sound-asset gates pass;
CI runs `33950203890` and `33950203943` and CodeQL run `33950203888` are
green. The production index/TTL, Functions, explicit friendship repair and
Firestore Rules stages described below are complete. Storage Rules were
unchanged and correctly skipped. Firebase Hosting workflow run `33954305037`
succeeded, and both Hosting domains match the workflow artifact bytes.

Both signed artifacts passed inspection and were uploaded once after checking
build-number uniqueness. Google Play shows Build 20 available to the existing
15-person internal tester cohort, published on 2026-09-05 at 10:36 CEST. The
iOS upload succeeded at 10:29:40 CEST, completed processing and subsequently
reached `Testing` for the existing external cohort of six testers; the
internal cohort of one remains assigned. Five non-owner TestFlight testers
show `Installed 20`, observed at 12:07, 12:11 and 12:13 CEST. The user separately
confirmed availability. Automatic TestFlight notification was enabled/triggered
with submission, but recipient inbox delivery has not been verified. Twenty
individual plain-text English emails to twenty unique recipients have verified
Gmail `SENT` records and a matching sent-mail search count of twenty. Four
Apple-cohort emails have confirmed `5.7.1 Message rejected` hard bounces
referencing Gmail help 69585. The user also reports blocked Apple messages and
Android spam placement. Manual resends were paused immediately: **the email
rollout is not complete and deliverability remains blocked**. Gmail policy
rejection is under investigation; native TestFlight notification is unchanged.
A separate owner-only probe from the authorized `hello@yovoice.app` Workspace
alias reached Inbox in twelve seconds with SPF/DKIM/DMARC PASS; it is not a
tester resend or proof that earlier rejections are solved. Marketing-site
commit `975e5c6` was pushed to its own `main`, deployed successfully on Vercel
and passed live read-back: home, updates, download and features return HTTP 200;
Build 20 content/anchors and the historical Build 19 updates anchor are present.

Post-deploy log review identified a pre-existing P1 in shared cleanup: a valid
expired `.mov` direct-message reservation was rejected by an image/audio-only
extension allowlist. The minimal backend-only fix is commit `06e94c6`, separate
from runtime `941376e`; its scoped two-worker deployment completed successfully
by 09:39:39 UTC on 2026-09-05. Independent production review APPROVED recovery
at 09:59:13 UTC after more than 19 minutes, four HTTP 200 scheduler runs and
zero ERROR entries across both workers. The fresh full Functions suite passes
1279/1279 across 118 suites, focused regression 2/2 and independent Moment
coverage 76/76 pass; Backend/Cybersecurity, separate Adversarial and Principal
review APPROVE.
The earlier Voice 84/84 APPROVE remains scoped source evidence; it did not
establish the later-observed production cleanup health.

The cleanup hold is lifted: the old reservation completed naturally at
09:41:05.343 UTC on attempt one and pending aggregate is zero. External
TestFlight advanced only after this verification, reaching the observed
`Testing`/`Installed 20` states above. No production outbox/media was manually
edited or deleted. No mobile rebuild,
duplicate upload or Hosting redeploy is needed for this server-only fix.

Remaining evidence includes Android non-owner installation, authenticated
production smoke with dedicated QA credentials, physical two-account/
mixed-version iOS/Android call/media QA, and app-wide keyboard/RTL and physical visual QA
beyond the completed bounded harnesses. These are not implied by a store
console status or a green automated suite.

No account identifiers, allowlist contents, signed URLs, tokens or private
store-console identifiers belong in this record. Artifact digests below are
non-secret integrity evidence only.

## Candidate boundary

This is one coordinated successor to Build 19, not a series of uploads after
individual fixes. The candidate combines the Build 19 P0 chat, call, friend,
avatar and direct-media repairs with the Build 20 Voice Moment/YO Moments,
Reels, moderation, localization, sound and navigation work in the current
tree frozen at `941376ef8029030aeec27e1e8ef28a4cead8697b`. Automated coverage
proves the exercised code paths only; it does not
replace the physical device, rendered visual, production read-back or store
availability checks listed above.

Reels is the bounded photo/video MVP with user-owned or appropriately licensed
uploaded audio, not Instagram feature parity or a licensed streaming-music
catalog. No Spotify/Apple Music extraction is part of this release. Likewise,
the existing LiveKit/WebRTC transport is not a claim of application-level
end-to-end encryption.

Build 19 remains the historical tester baseline. Nothing in this session
changes its recorded deployment or availability evidence.

The backend cleanup follow-up `06e94c6` changes the shared direct-attachment
extension allowlist and its regression tests only. It does not change the
Build 20 mobile/Web artifact hashes or require replacing those packages.

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
| Backend cleanup follow-up full Functions | **1279/1279, 118 suites** | fresh Auth/Firestore emulator run for `06e94c6`; 0 failed, 0 skipped, 196.7 s; not added to the frozen-source count |
| Cleanup focused regression | **2/2 PASS** | valid video cleanup and malformed/unsupported path rejection |
| Cleanup independent Moment review | **76/76 — APPROVE** | Backend/Cybersecurity, separate Adversarial and Principal reviewers approved the narrow follow-up; no P0–P3 finding in scope |
| Cleanup production health | **APPROVE at 09:59:13 UTC** | more than 19 minutes after deploy; natural completion, pending aggregate 0, four HTTP 200 scheduler runs, 0 ERROR entries across both workers |
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
The later full 1279/1279 invocation exercises the cleanup follow-up plus its
two new tests in one fresh emulator run; keep it separate from the frozen
1277-test history rather than combining candidates.

The generated PNGs were inspected rather than inferred from test completion.
Frame Echo Clean rendered without internal lines or skew, and no overlap
was observed in the bounded YO Moments/dock matrices. Those source-rendered
results do not substitute for physical-device, keyboard, RTL or full-app QA.

## Production and artifact progress

| Boundary | Observed result | Remaining boundary |
|---|---|---|
| Frozen source and CI | Commit `941376ef8029030aeec27e1e8ef28a4cead8697b`; CI `33950203890` and `33950203943` green; CodeQL `33950203888` green | none for this frozen source |
| Firestore indexes | all four Build 20 composites read back as `READY` | none |
| Managed TTL | `reelCleanupOutbox.deleteAfter` and `voiceMomentReportReceipts.expiresAt` read back as `ACTIVE` | none |
| Cloud Functions at runtime release | 173/173 exported Functions active; 17 critical Cloud Run services on their latest ready revision with 100% traffic; seven unauthenticated callable probes returned `401` | authenticated live smoke still requires dedicated QA credentials; later cleanup finding below is not contradicted by ACTIVE status |
| Backend cleanup follow-up | `06e94c6`; full fresh suite 1279/1279, focused 2/2, independent Moment 76/76; required reviews APPROVE; both scoped workers deployed successfully by 09:39:39 UTC; independent natural recovery and more-than-19-minute health observation APPROVED 09:59:13 UTC | browser CI `33958465500`, CodeQL `33958465503` and full verification `33958465563` succeeded; no outstanding cleanup gate |
| Friendship reconciliation | one explicitly reviewed pair repaired with two canonical guards; repeat run was a no-op | no identifiers or manifest contents retained here |
| Firestore Rules | deployed successfully on 2026-09-05 at 07:44 UTC; production source read-back matched SHA-256 `b396c54ca9ccded08e2e2484e9551e5c55a5ed5deb7d98f10c967882a2cce114`; four anonymous probes against server-owned collections returned `403` | authenticated allow-path smoke remains part of the credential-bound residual |
| Storage Rules | unchanged in the frozen diff, so no deployment was performed | none |
| Firebase Hosting | workflow `33954305037` succeeded; both `app.yovoice.app` and `yovoice-ec54a.web.app` match its `main.dart.js`, `index.html`, `version.json` and service-worker bytes; required cache/security headers verified | no missing artifact/read-back gate |
| Android artifact and distribution | signed AAB, code 20, 115,597,935 bytes, SHA-256 `bf61bb8438b5db8c89d3894019d007b06ce88dd39dc1143d310667f214e3ddd9`; uniqueness checked, uploaded once, Play confirms available to the existing 15-person internal cohort at 10:36 CEST; user separately confirmed availability | non-owner Android installation and physical acceptance not observed |
| iOS artifact and distribution | signed `1.0.0 (20)` IPA, 56,657,912 bytes, SHA-256 `3cd39243d6900997ebd91e375ded9e7f79a98a8f39608d932baba9d9502c66cd`; uniqueness checked, upload succeeded 10:29:40 CEST, processing complete, internal cohort one assigned, external cohort six `Testing`; five non-owner testers show `Installed 20` at 12:07/12:11/12:13 CEST observations | installation does not establish physical functional or mixed-version acceptance |
| Tester notifications | automatic TestFlight notification enabled/triggered; twenty unique individual plain-text emails verified `SENT`, sent-mail search count twenty; four Apple-cohort hard bounces `5.7.1 Message rejected` referencing Gmail help 69585; manual resends paused | email rollout incomplete/deliverability blocked; Android spam placement is user-reported, not independently mailbox-verified |
| Authorized domain-sender probe | one owner-only test from the existing `hello@yovoice.app` Workspace alias, sent 13:05:51 CEST and received in Inbox 13:06:03; recipient-side independent read confirms Inbox, actual From and original SPF/DKIM/DMARC PASS | proves one authenticated owner inbox delivery only; no tester resend or settings change; earlier rejection cause remains unverified |
| Marketing website | commit `975e5c6` pushed to its own `main`, Vercel deployment succeeded; live `/`, `/updates`, `/download` and `/features` HTTP 200; Build 20 content/anchors present and historical Build 19 updates anchor retained | no outstanding deployment/read-back gate; no broader visual or device claim inferred from HTTP/content checks |

The live Web bundle is 8,588,352 bytes, SHA-256
`11d7b9570834fd0897f1ffee1987d6c25052e8e15732d821efa37b6de01509af`, and
reports version `1.0.0`, build `20`. Both store timestamps above are on
2026-09-05 in CEST (UTC+02:00).

### Signed-artifact inspection and residual symbols

Android ZIP/signature validation passed with the established upload
certificate; package `app.yovoice`, version `1.0.0`, code `20`, min SDK 24 and
target SDK 36 were verified. The iOS archive passed strict/deep code-signature
verification with package `app.yovoice`, `1.0.0 (20)`, arm64, minimum iOS 15.0,
production APNs, Apple Sign In, `get-task-allow=false` and the expected
distribution identity/profile. Neither upload failed.

The iOS uploader reported missing dSYMs for seven vendored libraries:
FirebaseFirestoreInternal, RecaptchaEnterpriseSDK, WebRTC, absl, grpc, grpcpp
and openssl_grpc. App/Runner/Flutter/objective_c symbols exist and matched;
the vendor packages supply no matching dSYMs. This limits symbolication of
third-party crash frames, not signing, processing or runtime availability.
Do not rebuild or duplicate-upload Build 20 solely to regenerate unavailable
vendor symbols.

### Separate tester-email outcome — deliverability blocked

Twenty individual plain-text update emails were submitted to twenty unique
recipients. Gmail returned `SENT`, and a separate sent-mail search verified
twenty messages. Those observations prove sender-side submission only; they
do not establish receipt, inbox placement or completion of the notification
rollout.

The user reported blocked Apple-cohort messages and Android-cohort spam
placement. Mailbox inspection independently confirmed four hard-bounce notices
for the Apple cohort, each with status `5.7.1`, `Message rejected` and a
reference to Gmail help 69585. Android spam placement remains a user report,
not an independently inspected recipient mailbox result. No inference is made
that the remaining sixteen messages were delivered.

Manual resends were paused immediately. The Gmail policy rejection is being
diagnosed; neither a root cause nor a tester-wide deliverability fix is yet
verified. Native automatic TestFlight notification remains enabled and
unchanged, and the already-observed store availability/installations remain
valid. Do not record the separate email rollout as complete or resume repeated
sending while this rejection remains unresolved. Recipient addresses are not
retained in this record.

A separate, owner-only diagnostic probe used the existing authenticated
Workspace mailbox's authorized `hello@yovoice.app` alias. It was sent at
13:05:51 CEST on 2026-09-05 and received at 13:06:03 CEST: twelve seconds. Gmail
shows the received message in Inbox, and the original message's authentication
results show SPF PASS, DKIM PASS with `yovoice.app`, and DMARC PASS. No DNS,
sender, account or security settings were changed. This probe was not a tester
resend and is not part of the twenty-message tester wave.

An independent recipient-side Gmail direct-read also confirms Inbox-only
placement, actual From `hello@yovoice.app` and the original message's same
SPF/DKIM/DMARC PASS results.

The result establishes one authenticated inbox delivery from the domain
mailbox, not delivery to the tester cohort, an inbox-placement guarantee or
the cause of the earlier `5.7.1` rejection. The intended sender for future
tester email is the existing domain mailbox's authorized `hello@yovoice.app`
alias. A personal Gmail connector cannot assume that company-sender authority.
All tester resends remain paused; the four hard bounces and Android spam report
remain unresolved. Obtain explicit user direction before any bounded tester
retry; no such retry has been performed.

### P1 found during post-deploy cleanup observation

`processPendingContentCleanupSchedule` produced an error every five minutes
on both the prior and newly deployed revision. A read-only production query
for pending outbox entries succeeded (HTTP 200), ruling out the suspected
missing-index explanation for this case. One canonical expired direct-message
attachment reservation for a `.mov` object remained pending with zero
attempts. The cleanup validator accepted only `jpg|png|webp|m4a`, while the
upload contract already accepts `mp4|mov|webm` too.

Follow-up `06e94c6` aligns only that extension allowlist. Canonical root,
conversation, message, owner and object-path checks remain unchanged. Its two
tests cover expired video reservation cleanup and continued malformed or
unsupported-path rejection. Required review is complete; the deployment of
`processPendingContentCleanupSchedule` and `onContentCleanupOutboxCreated`
completed with exit 0 by 09:39:39 UTC. Independent review APPROVED the
production boundary at 09:59:13 UTC:

- latest ready revisions `oncontentcleanupoutboxcreated-00012-xoj` and
  `processpendingcontentcleanupschedule-00012-rum` both serve 100% traffic;
- the old `.mov` reservation completed automatically at 09:41:05.343 UTC,
  attempt one, and the pending aggregate is zero;
- scheduler invocations at 09:41, 09:46, 09:51 and 09:56 UTC returned HTTP 200;
- neither worker recorded an ERROR over the more-than-19-minute post-deploy
  window.

This cleared the cleanup-specific external TestFlight/announcement hold before
the observed external rollout. It
does not replace authenticated or physical-media acceptance. Browser CI
`33958465500` and CodeQL `33958465503` passed for `06e94c6`; full verification
run `33958465563` succeeded at 09:50:19 UTC, including Flutter, rules,
Functions, smoke and Web-build gates. Hosting deployment correctly skipped;
the production mobile/Web runtime remains `941376e`.

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
- [x] Exact source commit is pinned at
      `941376ef8029030aeec27e1e8ef28a4cead8697b`; both CI runs and CodeQL are
      green.
- [x] All four required Firestore composite indexes are read back as `READY`;
      `reelCleanupOutbox.deleteAfter` and
      `voiceMomentReportReceipts.expiresAt` are both read back as `ACTIVE`
      before their producers run.
- [x] All 173 exported Functions are active; 17 critical Cloud Run services
      are on their latest ready revision with 100% traffic; seven
      unauthenticated callable probes fail closed with `401`.
- [ ] Complete the authenticated production smoke when dedicated QA
      credentials are available.
- [x] Explicit friendship allowlist dry-run/digest/apply/no-op post-check is
      complete with no conflict; only aggregate evidence is recorded.
- [x] Firestore Rules deployed successfully at 07:44 UTC and the byte-exact
      production read-back matches the recorded source hash; four anonymous
      server-collection probes fail closed with `403`.
- [x] Storage Rules are unchanged in the frozen diff and were not deployed.
- [x] Firebase Hosting workflow `33954305037` succeeded; both domains match
      the workflow artifact bytes and required security/cache headers.
- [x] Cleanup follow-up `06e94c6` passes focused 2/2, independent Moment 76/76
      and fresh full Functions 1279/1279; required independent reviews APPROVE.
- [x] Scoped deployment of both cleanup workers from `06e94c6` completed
      successfully by 09:39:39 UTC.
- [x] Independent cleanup recovery APPROVED 09:59:13 UTC: latest revisions at
      100% traffic, automatic completion on attempt one, pending aggregate
      zero, four scheduler HTTP 200 results and zero worker ERROR entries over
      more than 19 minutes. No manual outbox/media mutation was performed.
- [x] Follow-up browser CI `33958465500` and CodeQL `33958465503` passed.
- [x] Follow-up full verification CI `33958465563` succeeded at 09:50:19 UTC;
      its Hosting deployment correctly skipped.
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
- [x] Fresh Android AAB identifies version code 20 and passes the completed
      signing inspection; its size and SHA-256 are recorded above.
- [x] Signed IPA identifies `1.0.0 (20)` and passes signing plus
      entitlement/permission inspection.
- [x] Build 20 was confirmed unused in both store consoles before upload;
      each artifact was uploaded once.
- [x] Play processing/release completed, with code 20 available to the existing
      internal cohort of 15 testers at 10:36 CEST.
- [x] TestFlight processing completed, with `Ready to Submit` status and the
      existing internal cohort of one assigned.
- [x] The existing six-person external TestFlight cohort has Build 20 `Testing`;
      five non-owner testers show `Installed 20` in the recorded observations.
- [x] The user separately confirmed tester availability.
- [ ] Observe Android installation from a non-owner tester account; TestFlight
      non-owner installations are already observed, not functional acceptance.
- [x] Automatically notify testers was selected on the external TestFlight
      submission and the native notification enabled/triggered with release;
      recipient inbox delivery has not been verified.
- [x] Twenty individual plain-text English emails to twenty unique recipients
      have verified Gmail `SENT` records and a matching sent-search count.
- [ ] Resolve separate email deliverability: four Apple-cohort hard bounces
      are confirmed, the user reports Android spam, and manual resends remain
      paused. Sender-side `SENT` is not delivery or completed rollout.
- [x] One owner-only probe from authorized `hello@yovoice.app` reached Inbox
      in twelve seconds with original SPF/DKIM/DMARC PASS. No settings changed
      and no tester resend occurred; tester deliverability is not established.
- [x] Marketing-site commit `975e5c6` was pushed to its own `main`; Vercel
      deployment succeeded.
- [x] Marketing live read-back passed: `/`, `/updates`, `/download` and
      `/features` return HTTP 200; Build 20 content/anchors are present and
      `/updates` retains the historical Build 19 anchor.
- [ ] Verify remaining notification/delivery outcomes; do not infer inbox
      placement or delivery of the other sixteen messages from their `SENT`
      status or absence of a recorded bounce.

## Claims deliberately not made

- ACTIVE Functions and passing suites alone did not establish cleanup health.
  The older P1 discovered after Android publication was separately repaired
  and its natural recovery observed; that bounded recovery is not a general
  guarantee that every production operation is correct.
- Google Play console availability and the user's separate confirmation are
  not an observed non-owner Android installation. TestFlight `Testing` and
  five non-owner `Installed 20` observations establish that bounded external
  rollout, not functional device acceptance. Neither channel is a public
  store release.
- Authenticated production behavior is not inferred from anonymous denial
  probes; the dedicated-credential smoke remains outstanding.
- Automatic TestFlight notification was enabled/triggered; its recipient inbox
  delivery is unverified. Twenty separate emails were sent, but four confirmed
  hard bounces and reported spam mean email rollout is not complete. The
  remaining sixteen messages are not assumed delivered.
- The authorized-domain owner probe proves one authenticated Inbox delivery,
  not tester delivery, a fix for the original rejection or a configuration
  change. Personal Gmail sender authority does not imply company-alias
  authority.
- Automated tests do not prove real APNs/FCM, camera codecs, Bluetooth,
  background/foreground recovery, LiveKit media or mixed-version behavior.
- A source-level security review cannot guarantee that no attacker can ever
  enter the system; it reduces measured risk within the reviewed boundaries.

## Release decision

Current decision: **BOTH INVITED TESTER CHANNELS AND MARKETING UPDATE LIVE;
TESTER EMAIL DELIVERABILITY STILL BLOCKED**. Twenty separate
emails have verified sender-side `SENT` evidence, but four confirmed hard
bounces and reported spam prevent a completed-delivery claim. Manual resends
are paused; a separate authorized-domain probe reached the owner's Inbox with
SPF/DKIM/DMARC PASS but does not resolve tester delivery. Native TestFlight
notification is unchanged. Marketing commit `975e5c6` deployed successfully
and passed live read-back. A bounded tester retry awaits explicit user
direction; none has been performed. Web, Android internal testing
and external TestFlight are released. Five non-owner TestFlight testers have
Build 20 installed; Android non-owner installation remains unobserved. The
production cleanup follow-up `06e94c6` is separate from frozen mobile/Web
runtime `941376e`; its scoped deployment and independent
natural recovery/health observation passed. Follow-up full CI also passed.
Authenticated production smoke and physical/mixed-version acceptance remain
unverified. Record each later
boundary as observed; never combine evidence from different candidates or
describe this invited rollout as complete device acceptance.
