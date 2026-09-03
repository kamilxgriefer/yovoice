# Build 19 coordinated tester release — 2026-09-03

## Status

**GO FOR BOUNDED TESTERS; NOT A PUBLIC STORE RELEASE.** Exact source commit
`7ef9816fd3ee289cd065b37b83bd14d748a44e0c` passed the source gates below.
Functions, the required index, Firestore Rules, Storage Rules and Firebase
Hosting were then deployed and read back before the signed Build 19 artifacts
were assigned to the persistent TestFlight and Google Play Internal Testing
cohorts. Physical two-device/mixed-version and the full visual matrix remain
residual acceptance, not inferred successes.

## Intended coordinated scope

- Shared Media plus DM photo/video/voice, camera/library acquisition and a
  durable replay-safe outbox.
- Canonical avatar refresh and single-flight profile navigation.
- Backward-compatible direct audio/video with truthful audio fallback.
- Voice Moment generation grants, retry recovery and legacy migration.
- Reels publish/read/report/delete MVP with non-destructive edits and only
  user-owned/licensed audio; no Spotify/Apple Music catalogue ingestion.
- Compact achievement/More presentation.
- Production Polish and the guarded 41 additional locale variants.
- Atomic moderation/report/audit hardening.
- A truthful website Updates entry after release evidence exists.

## Measured evidence

| Gate | Result | Status |
|---|---:|---|
| `flutter analyze` | clean | passed |
| complete Flutter suite | 2123/2123 | passed in one final-tree invocation |
| independent Build 19 targeted QA | 229/229 | passed |
| Reels pagination + catalog | 19/19 | passed |
| Reels/localization/visual source review | 40/40 | passed |
| Functions | 1166/1166 | passed across 118 suites on fresh Auth + Firestore emulators |
| Firestore Rules | 523/523 | passed |
| Storage Rules | 67/67 | passed |
| Family media | 11/11 | passed |
| Reels + atomic moderation | 64/64 | passed on fresh emulator |
| shared DM media probe | 9/9 | passed |
| direct media integrity | 38/38 | passed on fresh emulator |
| browser media/crop/Reels | 39/39 | passed in Chrome |
| Flutter production Web build | built | passed |
| website tests/lint/build | 87/87 + clean + built | passed |
| dependency audits | 0 known production vulnerabilities | passed |
| changed Node syntax + diff check | 7/7 + clean | passed |
| physical visual/RTL/200% matrix | — | pending |
| physical iOS/Android | — | pending |
| production deploy/read-back | Functions/index/Rules/Storage/Hosting | passed |
| TestFlight availability | Build 19, external 7 + internal 1 | Testing; installs observed |
| Google Play availability | Build 19, 15-testers list | available since 18:29 CEST |

DM media hardening is source-verified. The generation-bound probe recognizes
JPEG/PNG/WebP, ISO-BMFF/WebM and MP3/WAV and returns detected type plus track
presence; voice requires audio only and video requires a real video track. A
post-probe metadata read and the transaction revalidate reservation, path,
generation, MIME, kind, size, duration and expiry. The shared contract passed
9/9, fresh-emulator direct integrity passed 38/38, all seven changed Node files
passed syntax checking and the diff check passed. Production IAM and Rules
read-back passed; physical-device media smokes remain pending. If this
implementation changes, rerun every affected Functions/Rules/media gate and
replace—not append to—the counts.

The new Reels boundary charges attempts before trusted media probing, verifies
server-observed MIME/tracks/size/generation, caps each feed request to 24
documents and eight distinct authors, uses request-local authorization state,
and performs generation-bound cleanup. App Check enforcement remains staged
off pending telemetry; transactional rate limits and authorization checks
remain active independently.

The legacy direct-message attachment cutover completed. Its operator and
datastore-query tests passed 12/12 + 1/1, and the complete Functions result
above includes both suites. A production dry-run from the start of the bucket
reached the end and classified all 5 legacy objects as eligible, with 0
invalid, missing or raced objects and 5 legacy download tokens. The controlled
apply finalized all 5 and revoked those tokens without deleting media bytes.
Repeated complete post-apply scans from a null cursor independently reached
the end with all 5 already finalized, zero eligible/invalid/missing/raced/token
counts and `releaseReady=true` before strict Storage Rules were deployed.

## Production Voice Moment migration evidence

On 2026-09-03 the dry-run found 5 total legacy objects: 1 ready, 4 already
migrated and 0 conflicts. The ready record was applied successfully. Hardening
scanned 1 object, revoked 1 legacy token and found 0 missing objects. The
post-run reported all 5 already migrated. Firestore legacy `audioUrl` count is
0. Final bucket inventory:

| Prefix | Objects | Download tokens |
|---|---:|---:|
| `voice_moments` | 5 | 0 |
| `voice_replies` | 0 | 0 |

No bytes were deleted. This record intentionally excludes document ids,
object URLs, signed URLs and token material.

## Release and rollback

Follow
[DEPLOYMENT.md](../DEPLOYMENT.md#build-19-coordinated-tester-release--2026-09-03)
exactly: pin/freeze → final gates → additive Functions → controlled smokes →
required indexes → Firestore Rules/read-back → zero-token/IAM gate → Storage
Rules/read-back → Hosting → website → signed native artifacts and persistent
tester groups.

Rollback presentation/clients first and restore captured rule sources if
needed. Do not restore legacy token URLs, reverse canonical migration, delete
media bytes or discard moderation audit evidence. Functions must remain
backward-compatible with build 18 while that client is in circulation.

## Final results — directly observed

- Source commit: `7ef9816fd3ee289cd065b37b83bd14d748a44e0c`;
  no public-release tag or public-store claim.
- Automated gates: Flutter 2123/2123; Build 19 QA 229/229; browser 39/39;
  Functions 1166/1166; Firestore 523/523; Storage 67/67; Family 11/11;
  Reels/moderation 64/64; shared probe 9/9; direct integrity 38/38; changed
  Node syntax 7/7; clean analysis and diff.
- Visual/physical result: automated and source visual gates passed; the full
  Dark/Pearl/RTL/200% physical matrix and two-device mixed-version paths remain
  residual.
- DM migration: production apply completed; repeat null-cursor inventories
  reported 5 already finalized and zero eligible/invalid/missing/raced/token
  counts with `releaseReady=true`; no media bytes were deleted.
- Functions: all 166 intended exports were ACTIVE; 9/9 Reels exports were
  included. Unauthenticated probes for 15 protected callables returned 401.
- Index: the required `messages` collection composite (`type ASC`, `sentAt
  DESC`, `__name__ DESC`) was `READY`.
- Firestore Rules: production source read back byte-identically, SHA-256
  `4741516c7bf17f9e57f3826d789c14becad0a7386435073fe3530dc79b02b243`.
- Storage: minimal service-agent IAM was present; zero-token inventories were
  clean; production Rules read back byte-identically, SHA-256
  `bce9925b397ab6bba0b5ccf8ea8cefd9db4ef02303f28dcd3a574af280`.
- Hosting: workflow
  [33757422008](https://github.com/kamilxgriefer/yovoice/actions/runs/33757422008)
  succeeded for the exact source commit; production routes and security
  headers were verified.
- Website: commit `9cc6d72550ce6e0b603136f7bb71e7e11891ab47` deployed through
  successful Vercel deployment `6248731984`; the live tester-availability
  entry plus 43/43 production route/security-header smoke passed. The page
  explicitly distinguishes invited testing from public store release.
- iOS: signed IPA, 56,525,856 bytes, SHA-256
  `dbb99e55d38d26098a3e7f7f26dbeda1cafd9edcb4e1aee026d82c2b5d95724b`;
  TestFlight Build 19 is `Testing` for persistent external 7 and internal 1
  cohorts, and Build 19 installs were observed. This is not App Store release
  evidence.
- Android: signed AAB, 115,020,041 bytes, SHA-256
  `3850766844521330eb4ae8ed04ecc79c344ee89d5ade0af1c165d3be639c8b7f`;
  Google Play Internal Testing shows Build 19 available to the persistent
  15-account tester list, published 2026-09-03 at 18:29 CEST. This is not a
  public Google Play release.
- Notifications/email: TestFlight external automatic notification was
  enabled. Six manual Apple emails were attempted and four later bounced with
  SMTP 5.7.1, so complete delivery is not claimed. No new Build 19 Android
  email wave was sent; email is not used as availability evidence.
- Rollback performed: no.
- Decision: **GO for bounded tester acceptance; HOLD any public store release
  until the residual physical/mixed-version and full visual matrix passes.**
