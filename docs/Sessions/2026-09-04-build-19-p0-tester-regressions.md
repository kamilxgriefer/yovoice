# Build 19 P0 tester regressions — 2026-09-04

## Status

**BUILD 19 TESTER ROLLOUT COMPLETE; BUILD 20 CORRECTIVE SUCCESSOR STILL
HELD.** The current unreleased `1.0.0 (20)` tree fixes the
diagnosed compatibility, media and read-fanout defects and passes the automated
gates below. No Functions deployment, production data reconciliation, Hosting
deployment or successor native-build upload is claimed in this session record. The
historical Build 19 baseline remains pinned to
`7ef9816fd3ee289cd065b37b83bd14d748a44e0c` and remains the version in the
existing TestFlight and Google Play Internal Testing cohorts.

## Tester evidence and diagnosis

The P0 reports were reproduced from production telemetry and tester captures:

- direct audio and video start returned HTTP 400 despite valid authentication
  and App Check;
- friends-only avatars fell back to initials in list/profile surfaces;
- iOS DM video upload reserved and transferred bytes but finalization failed;
- Friends/Chats/profile navigation felt slow and rapid taps could later open
  several copies of the same profile.

The affected direct-call pair had active verified users, an exact v2 direct
conversation and exact bilateral historical friend mirrors, but no bilateral
server-owned `friendshipGuards`. The endpoint therefore failed closed by
design. Client versions were not consulted, so updating the recipient alone
could not repair that missing authority. The same guard absence prevented
friends-only avatar grants.

Two real iOS media forms explained the video failures: one picker returned a
`.MOV` / `video/quicktime` label for MP4-branded (`mp42`) immutable bytes; a
second produced a genuine Apple `qt  ` MOV/HEVC file whose tracks were
recognized while the generic parser omitted duration.

The performance issue combined global avatar-grant invalidation, duplicate
friends/request fanouts and non-single-flight profile routing. Some nested
routes also lost the injected Auth/Firestore/service context and silently
returned to process-global instances.

## Implemented source repair

### Calls and friendship authority

- Direct-call refusals carry safe reason codes for missing canonical
  friendship, missing direct conversation, unverified email and video-protocol
  or installation-binding incompatibility.
- The client maps those reasons to actionable copy across all 43 selectable
  locale variants; a video-only incompatibility offers a real audio fallback.
- Push-token inventory is not treated as a capability registry. A new caller
  offers video protocol v1 and the installation performing `Answer` is the
  authoritative negotiation boundary: a v1 answer retains video, while a
  legacy answer or unavailable camera atomically downgrades the canonical call
  and inbox signal to audio before either side receives a media token.
- New calls use a random 256-bit installation value locally and persist only a
  SHA-256 call-and-participant-scoped binding. Tokens are refused on another
  installation; legacy unbound audio calls retain account-level compatibility.
- An active incoming call on another device never auto-joins or opens local
  media. It requires an explicit `Continue on this device` gesture, terminal
  LiveKit disconnects expose `Retry`, and dismissing the passive route cannot
  end the call running on the answering device.
- An operator-only reconciliation accepts an explicit reviewed manifest only,
  defaults to dry-run, pins the production project, caps input at 100 pairs and
  64 KiB and requires the normalized dry-run SHA-256 digest for apply.
- Auth users, profiles, exact bilateral mirrors/timestamps, blocks,
  restrictions and both guards are re-read; the two guards for one pair are
  created transactionally. The utility never searches for or trusts arbitrary
  legacy mirrors as authority. Its schema-v2 manifest represents the reviewed
  establishment time as exact `{seconds, nanoseconds}`, requires Firestore-
  persistable microsecond alignment, binds both components into the digest and
  writes that exact timestamp to both guards.

### Direct-message video

- The client sniffs selected bytes before creating the reservation instead of
  trusting only filename/picker MIME.
- The backend recognizes MP4 and QuickTime as equivalent only for video and
  only after probing the immutable stored generation.
- Every ISO-BMFF result is corroborated even when the general parser reports a
  positive duration. A bounded parser validates at most eight playable tracks,
  recognizes both `audi` and `soun`, validates sample descriptions, chunk/sample
  maps, self-contained data references and root `mdat` containment, rejects
  cross-track overlap, and conservatively combines movie, track, media, decode,
  composition and edit timelines.
- The parser is capped at 160 generation-bound range reads and 2 MiB of timing
  bytes; fragmented, ambiguous, overflowing, malformed and over-budget files
  fail closed. Generation, size, reservation, kind, track presence, duration,
  expiry and post-probe transaction checks remain enforced. Unrelated MIME
  coercion remains rejected.
- Production-shaped `deadline-exceeded` expiry and `aborted` reservation-change
  refusals are classified as authoritative before the generic ambiguous-error
  path. They rotate both the reservation and `messageId`; genuinely ambiguous
  transport failures keep the existing durable outbox identity for retry.
- A canonical media acknowledgement reconciles an outbox item only when sender,
  conversation, `messageId` and media type all match. Completion deletes the
  private payload before removing the manifest entry, so a delete failure stays
  queued for retry/restart instead of becoming an untracked orphan. Wrong
  sender, conversation or type never suppresses the failed card or cleans up its
  payload; concurrent delivery/reconciliation remains single-completion.

### Avatars, friends and navigation

- Profile-media epochs are target-scoped, so one refreshed avatar no longer
  invalidates every sibling widget's grant.
- The private profile-media grant cache is auth-bound and capped by a 256-entry
  LRU. Grant expiry and auth/global boundaries clear both the mounted provider
  and its Flutter `ImageCache` entry before any replacement read can be shown.
  Mutual-friend avatars use `UserAvatar` with the current viewer grant instead
  of trusting a legacy public photo URL.
- Friends and requests use account-scoped, ref-counted replay fanouts. The last
  listener releases upstream work; terminal setup/source failures retire and
  evict the generation so a later screen can retry.
- A root friends/requests query failure remains terminal for that shared
  generation: it is forwarded once, then the generation retires and is evicted.
  Child public-profile and presence failures are isolated instead. The child
  projection degrades fail-closed, cancels the failed point listener and retries
  after 250 ms, 500 ms, 1 s, 2 s, then exponentially up to a 30 s cap. Backoff
  resets only after the replacement listener remains healthy for 30 s, avoiding
  a data-then-error hot loop. Malformed child snapshots follow the same
  fail-closed recovery path instead of escaping as an uncaught parsing error.
- Friend removal/re-add, root generation retirement, auth changes and successful
  sign-out cancel child retry/stability timers and subscriptions. Generation and
  child epochs prevent a stale callback or timer from resurrecting removed or
  previous-account data.
- Delivery rechecks the current uid, cache generations clear after successful
  sign-out, and a failed sign-out leaves the still-authenticated session live.
- Friends, Chat, preview and full-profile routes retain the injected
  Auth/Firestore/services.
- Profile and conversation launches are single-flight and release the guard on
  setup failure, preventing delayed stacks after repeated taps. Preview,
  full-profile and social-stat routes each retain an explicit navigation lock.
- Non-blocking P2: the target-scoped epoch map can grow during an unusually long
  session that evicts many unique targets. It is cleared at the global/auth
  boundary (including logout), and does not bypass privacy or affect
  correctness; bounding it remains follow-up housekeeping.

## Measured verification

| Gate | Result |
|---|---:|
| Complete Flutter VM suite | **2192/2192** |
| Direct-call + localization Flutter matrix | **67/67** |
| Friend recovery Flutter matrix | **22/22** |
| Avatar/profile focused review | **91/91**, no P0/P1 |
| DM media/outbox focused aggregate | **68/68**, no blocker |
| Independent cleanup re-review | **41/41**, no P0/P1/P2 |
| Flutter static analysis | **No issues found** |
| `dart format` | **615 files, 0 changed** |
| Complete Cloud Functions suite | **1218/1218**, 118 suites |
| Firestore Rules emulator | **523/523** |
| Storage Rules emulator | **67/67** |
| Family-media emulator | **11/11** |
| Direct calls emulator | **47/47** |
| Direct media integrity emulator | **39/39** |
| Focused trusted media probe | **29/29** |
| Legacy friendship reconciliation emulator | **12/12** |
| Modified/new JavaScript syntax | **8/8** |
| `git diff --check` | clean |

The full Functions run used fresh Auth and Firestore emulators. The Flutter
full-suite count is one final-tree invocation, not a sum of overlapping
buckets. Dependency-update notices are not test failures and no dependency was
upgraded as part of this P0 repair. The current `npm audit` result is
**unavailable**, not green: the npm advisory endpoint ended all three attempts with
`socket hang up`, so this candidate does not inherit Build 19's dependency-audit
claim without a successful rerun.

## Release boundary and remaining evidence

Automated tests cannot prove real APNs/FCM ringing, camera codecs, Bluetooth,
background behavior or two physical accounts. Screen automation could inspect
the public login surface, but the macOS host was locked when the Simulator was
requested, so an authenticated visual/native pass was not fabricated.

Independent security re-review of the final trusted-media parser is approved
with no high- or medium-risk blocker. Independent direct-call review found two
real UI races (a disconnect lost while `Answer` was pending and passive-route
dismissal ending another device's call); both are now repaired and pinned by
focused regression tests. The final private-avatar/profile review passed 91/91
without a P0/P1 finding, the focused media aggregate passed 68/68, and the
post-fix cleanup re-review passed 41/41 without a P0/P1/P2 finding. These are
source-level results; a final physical pass is still required. Before
another tester build:

1. Freeze the exact reviewed source tree and preserve the measured gates.
2. Commit/push the coordinated repair and deploy additive Functions first;
   verify active revisions and safe refusal/read-back behavior.
3. Prepare the minimum independently reviewed friendship allowlist. Run the
   aggregate dry-run, review its digest, apply it once and repeat a no-op
   post-check. Do not record pair ids or token material in shared docs.
4. On two physical devices, verify mixed-version direct audio/video, incoming
   notification/ringing, avatar visibility, photo/voice/video DM upload and
   playback using real iOS camera/library files.
5. Only then build and assign one coordinated successor to both TestFlight and
   Google Play tester cohorts. Do not upload an isolated build after each fix.

Until steps 2–3 complete, affected production friendships still fail closed
for calls and friends-only avatars. This is a known live limitation, not a
claim that the current source test result already changed production.
