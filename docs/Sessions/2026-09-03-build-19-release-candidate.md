# Build 19 coordinated release candidate — 2026-09-03

## Status

**HOLD — not released.** Source integration, complete Flutter, browser,
Rules, Functions, website and release-Web gates below are green. Physical
two-device verification, production rollout/read-back, Hosting/website proof,
signed artifacts, store processing and tester availability are still pending.

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
| Family media | 5/5 | passed |
| Reels + atomic moderation | 64/64 | passed on fresh emulator |
| shared DM media probe | 9/9 | passed |
| direct media integrity | 35/35 | passed on fresh emulator |
| browser media/crop/Reels | 39/39 | passed in Chrome |
| Flutter production Web build | built | passed |
| website tests/lint/build | 87/87 + clean + built | passed |
| dependency audits | 0 known production vulnerabilities | passed |
| changed Node syntax + diff check | 6/6 + clean | passed |
| physical visual/RTL/200% matrix | — | pending |
| physical iOS/Android | — | pending |
| production deploy/read-back | — | pending |
| TestFlight/Google Play availability | — | pending |

DM media hardening is source-verified. The generation-bound probe recognizes
JPEG/PNG/WebP, ISO-BMFF/WebM and MP3/WAV and returns detected type plus track
presence; voice requires audio only and video requires a real video track. A
post-probe metadata read and the transaction revalidate reservation, path,
generation, MIME, kind, size, duration and expiry. The shared contract passed
9/9, fresh-emulator direct integrity passed 35/35, all six changed Node files
passed syntax checking and the diff check passed. Production-object and
physical-device smokes remain pending. If this implementation changes, rerun
every affected Functions/Rules/media gate and replace—not append to—the counts.

The new Reels boundary charges attempts before trusted media probing, verifies
server-observed MIME/tracks/size/generation, caps each feed request to 24
documents and eight distinct authors, uses request-local authorization state,
and performs generation-bound cleanup. App Check enforcement remains staged
off pending telemetry; transactional rate limits and authorization checks
remain active independently.

The legacy direct-message attachment cutover is also source-ready. Its
operator and datastore-query tests passed 12/12 + 1/1, and the complete
Functions result above includes both suites. A production dry-run from the
start of the bucket reached the end and classified all 5 legacy objects as
eligible, with 0 invalid, missing or raced objects and 5 legacy download
tokens. It was read-only: no metadata, token or media byte was changed. The
strict Storage Rules remain held until Functions are deployed and drained,
the migration is applied, and two complete post-apply scans independently
report `releaseReady=true`.

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
[DEPLOYMENT.md](../DEPLOYMENT.md#build-19-pre-release-runbook--not-released)
exactly: pin/freeze → final gates → additive Functions → controlled smokes →
required indexes → Firestore Rules/read-back → zero-token/IAM gate → Storage
Rules/read-back → Hosting → website → signed native artifacts and persistent
tester groups.

Rollback presentation/clients first and restore captured rule sources if
needed. Do not restore legacy token URLs, reverse canonical migration, delete
media bytes or discard moderation audit evidence. Functions must remain
backward-compatible with build 18 while that client is in circulation.

## Final results — complete after direct observation

- Final commit/tag:
- Complete Flutter/browser/visual/physical results:
- DM sniffing/reservation hardening result: source 9/9 + 35/35; production
  smoke pending
- Functions revisions and smoke:
- Index diff/readiness:
- Firestore Rules release/read-back:
- Storage IAM, zero-token recheck, release/read-back:
- Hosting workflow/release/artifact hashes:
- Website commit/Vercel deployment/visual proof:
- iOS artifact/build/groups/non-owner availability:
- Android artifact/build/track/list/non-owner availability:
- Tester notification/email evidence:
- Rollback performed:
- Release decision:
