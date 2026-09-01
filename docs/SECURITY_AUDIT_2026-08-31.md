# Security audit — 2026-08-31

> **Superseded:** This is a historical snapshot. The current release-candidate
> audit is [SECURITY_AUDIT_2026-09-01.md](SECURITY_AUDIT_2026-09-01.md).
> Do not use the findings or verification counts below as the current gate.

## Executive result

The repository and the new direct-video path were reviewed across Flutter,
Firebase Functions, Firestore/Storage authorization assumptions, LiveKit token
issuance, platform permissions, local persistence, notifications and Hosting.
No confirmed P0 issue or committed production secret was found.

The video vertical slice is implemented in source with server-authored media
intent, declared-source-scoped RTC grants, privacy-safe lifecycle cancellation
and bounded teardown. It is not yet a released build and has not completed a
real two-device RTC test. WebRTC/LiveKit provides encryption in transit; YO
Voice does not yet provide application-level E2EE.

## Closed in this worktree

- Direct audio/video intent is immutable and server validated; missing legacy
  data safely defaults to audio.
- Audio tokens allow the declared microphone source. Video tokens allow
  declared microphone and camera sources. Normal voice rooms allow declared
  microphone; screen-share labels are omitted. These grants constrain the
  standard SDK, not a malicious client that deliberately mislabels a track.
- Start, acceptance and token minting revalidate participants, friendship,
  blocks, restrictions and active profiles. Participant-authorized terminal
  transitions deliberately remain available after those relationships change,
  so a user cannot be trapped in a call.
- Active calls expire and queue retryable LiveKit room teardown instead of
  retaining a usable room indefinitely.
- Late permission, token and connect futures cannot resurrect a call after
  hang-up, logout, account switch or replacement join. Microphone teardown
  snapshots direct references to published local tracks and stops those same
  objects again after a delayed SDK `restartTrack()`, even if Room cleanup has
  removed the publications. A not-yet-published camera candidate is owned and
  stopped separately by the camera-enable operation.
- Backgrounding invalidates every pending camera-enable/flip operation, forces
  the camera off and never silently restores it. If track shutdown fails, the
  entire local media session is disposed.
- The RTC endpoint is pinned to the exact production WSS origin and rejects
  credentials, custom ports, unexpected paths, queries and fragments.
- External room links validate bounded IDs, require an informed confirmation
  and connect muted in both LiveKit and the Firestore roster.
- Android backup is disabled; Android, iOS and macOS declare the camera,
  microphone and network capabilities used by the feature.
- Listen-only room members receive a non-publishing token before the client
  decides which OS permissions are needed, so joining a podcast audience does
  not request or start a microphone. Direct audio defaults to the earpiece;
  video and social rooms default to speakerphone, and route changes are
  serialized so teardown from an older call cannot overwrite a newer route.
- APNs and Web direct-call notifications use generic caller-private copy.
  Android retains caller-rich copy but marks the notification as private for
  the lock screen; that behavior still needs a physical OEM lock-screen test.
  Hosting adds clickjacking, MIME-sniffing, referrer, permissions and baseline
  CSP headers.

## Open P1 release gates

### Voice Moment download URLs remain bearer capabilities

Published Moment documents retain Firebase download-token URLs. Anyone who has
copied one may keep fetching the bytes after expiry, logout, a block or later
Rules denial. Store only the object path/generation and issue short-lived
authorized URLs after checking publication, expiry and block state; rotate or
delete the token/object at expiry.

### Privileged staff actions lack a strong-auth freshness gate

Role and server-owned mirrors are checked, but destructive staff/owner
callables do not centrally require verified email, MFA and recent `auth_time`.
Require MFA for staff, recent authentication for destructive operations and
session revocation when privilege or authentication factors change.

### Product claims must not imply FaceTime-grade E2EE

The current path is private by authorization and encrypted in transit, but the
LiveKit SFU is inside the trust boundary. Either implement authenticated,
per-device application-level E2EE with rotation/reconnect tests, or continue to
avoid lock/E2EE claims. Native CallKit/ConnectionService is also not part of
this vertical slice.

### Public video rollout requires recipient capability negotiation

A legacy client ignores `mediaType` and can present/accept a new video request
as audio while the upgraded caller starts a camera. Internal testing is safe
only when every device in the cohort runs the compatible build. Broad rollout
is NO-GO until the backend verifies an authoritative recipient device/build
capability. Deploy in this order: backward-compatible Functions, capability
registration and server enforcement, compatible clients, then video
enablement.

## P2 hardening backlog

- LiveKit `canPublishSources` trusts the `TrackSource` declared by the client.
  A modified client can relabel media, so exact AUDIO/MICROPHONE and
  VIDEO/CAMERA enforcement requires trusted track inspection and immediate
  removal (or a different media architecture), plus an adversarial publish
  test. Do not treat the current source allowlist as capture-origin proof.
- Roll out App Check with telemetry first, including a working web provider,
  then enforce it on mutating, billing, staff, media and RTC-token endpoints.
- Add transactional rate limits/idempotent leases for LiveKit token minting.
- Encrypt or purge plaintext DM outboxes, attachment payloads and offline audio
  on logout/account switch; exclude sensitive iOS files from backup.
- Validate magic bytes and decode/re-encode uploaded images/audio with pixel,
  duration and codec limits; remove EXIF metadata.
- Restrict avatars to managed storage or an image proxy to prevent external
  tracking pixels.
- Add explicit TTL/retention for ended direct calls, incoming signals and
  completed control outbox records.
- Split the broad default Functions runtime service account by domain and
  grant least privilege.
- Add a strict allowlist for Stripe checkout/portal destinations.
- Complete a tested full CSP after inventorying Flutter/CanvasKit, Firebase and
  LiveKit connections.
- Upgrade the Functions dependency chain in a controlled change; production
  dependencies currently report eight moderate advisories and no high or
  critical advisories.

## Verified strengths

- Direct-call signaling documents are server-owned; clients cannot fabricate
  call state.
- LiveKit and Stripe secrets are held outside the repository.
- Short-lived call JWTs are bound to both the canonical call room and UID.
- Bilateral friendship, both block directions and account restrictions are
  checked at the privileged boundaries.
- DM attachment reservations and private conversation membership are enforced
  server-side.
- No cleartext transport override, permissive certificate callback or ATS
  exception was found.
- A full-history `gitleaks` scan reported only classified public Firebase API
  identifiers, a public web-push VAPID key and test/example fixture strings; no
  private key, Stripe secret or LiveKit secret was confirmed. Public client
  keys still require provider-side origin/application restrictions and quota
  monitoring.

## Verification and limits

The final worktree passed `flutter analyze` with no issues, all 1,890 Flutter
tests, all 950 Cloud Functions tests in serial Auth/Firestore emulator
execution, JavaScript syntax checks, plist/entitlement/Hosting JSON validation
and `git diff --check`. Fresh post-review builds passed for release Web,
unsigned iOS debug device and Android debug APK. `npm audit --omit=dev` exits
non-zero because production Functions dependencies report eight moderate
advisories; it reports no high or critical advisories.

```text
flutter analyze
flutter test
firebase --project yovoice-fn-test emulators:exec --only auth,firestore "npm --prefix functions test"
node --check functions/calls/direct_calls.js
node --check functions/livekit/token.js
node --check functions/notifications/push.js
node --check functions/notifications/push_payload.js
npm audit --omit=dev
flutter build web --release
flutter build ios --debug --no-codesign
flutter build apk --debug
```

These checks do not prove camera quality, NAT traversal, Bluetooth routing,
APNs/FCM delivery or lifecycle behavior on physical phones. Before release, run
at least one iOS↔iOS, Android↔Android and iOS↔Android two-device matrix,
including deny/revoke camera, background during permission, reconnect, account
switch, speaker/Bluetooth, locked-screen notification privacy, End/expiry
outbox room deletion and reconnect denial. Also test Chrome/Safari↔mobile when
web remains a release target, a mixed-version pair, and a signed macOS runtime
smoke if macOS is distributed. Keep video gated until recipient capability is
authoritative.

No Hosting, Functions, TestFlight or Google Play artifact was published by
this audit.
