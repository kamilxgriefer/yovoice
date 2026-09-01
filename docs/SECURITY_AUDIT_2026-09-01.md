# Security audit — 2026-09-01

## Executive result

This audit describes the **current release-candidate worktree**, not an
attestation that every control is already deployed in production. No confirmed
P0 vulnerability, committed production credential or new secret in the release
diff was found.

The previously open private-media bearer-URL design, privileged recent-auth
gate and RTC/Club/room cost-amplification findings are closed in the current
source and covered by automated tests. Direct video remains a gated feature:
the app is private by authorization and WebRTC/LiveKit encrypts transport, but
YO Voice does not yet provide FaceTime-grade application-level E2EE, an
authoritative mixed-version capability gate or physical two-device evidence.

The release is therefore **not security-complete**. The non-video candidate's
final automated Functions and Rules gates are green, but its IAM, migration,
deployment-readback and physical-device checks remain operational gates. A
public video rollout remains NO-GO until every release gate below is closed.
Internal video testing must use a controlled, compatible cohort and still does
not replace the physical-device matrix.

No security review can make an application "100%" or "200%" hacker-proof. The
goal of these controls is to reduce attack surface and blast radius, detect
abuse, fail closed at authorization boundaries and keep residual risk explicit.

## Scope and evidence boundary

The review covered the Flutter client, callable registration and invocation
contracts, Firebase Auth/Functions/Firestore/Storage boundaries, LiveKit token
issuance and cleanup, Club and room lifecycle operations, private media,
dependency state, secret scanning and release Web/Android builds.

Automated tests prove the exercised contracts in the checked worktree. They do
not prove the production IAM configuration, App Check traffic quality, mobile
OS media behavior, NAT traversal, push delivery or Bluetooth routing. Those
items remain separate operational or physical-device gates.

## Closed in the current worktree

### Private media uses short-lived, generation-bound grants

Profile avatars/banners, room covers and published Voice Moment root/reply
audio no longer use durable Firebase download-token URLs as application data.
Canonical records carry a first-party object path, generation, MIME type and
size. Direct Storage reads fail closed except for the uploader's bounded
draft/reservation recovery path.

The authenticated media callables:

- recheck the viewer and owner account state, publication/lifecycle state,
  expiry, restrictions, blocks, visibility and membership where applicable;
- validate the actual Storage object and its generation before signing;
- return a generation-bound V4 URL for at most 90 seconds, with a Voice Moment
  grant additionally capped by the Moment's own deadline;
- revoke legacy Firebase download tokens when the object is encountered; and
- re-authorize after Storage metadata/signing work, so a concurrent block,
  expiry, deletion or media replacement does not leak a newly minted grant.

The Flutter media resolvers cache only bounded grants, invalidate them by media
revision and clear capability state across logout/account changes. A URL that
has already been issued remains a bearer capability until its short expiry;
authorization changes prevent the next grant but cannot recall bytes already
downloaded.

This is a source-level closure. Production rollout still has to follow the
coordinated callable → migration/inventory → compatible client → restrictive
Rules sequence documented in [SECURITY.md](SECURITY.md#private-media-rollout-gate-source-only-not-deployed).

### Destructive privileged actions require recent authentication

The common privileged-auth gate validates Firebase's server-authored
`auth_time` and rejects destructive staff/owner actions when the underlying
sign-in is older than five minutes. Refreshing an ID token does not refresh
that proof. The role gate still requires an exact signed claim/server-owned
mirror match and an active account; protected-owner actions also require the
configured protected owner UID.

MFA readiness is implemented without pretending it is already universally
enforced. The gate reads Firebase's reserved
`firebase.sign_in_second_factor` claim, supports an explicit
`YOVOICE_PRIVILEGED_MFA_MODE=required` fail-closed mode and rejects an invalid
policy value instead of silently disabling the check. The default rollout mode
remains `optional` so production staff are not locked out before TOTP provider
configuration and enrollment are confirmed. Enabling the provider and
switching the production policy remain deployment operations, not code claims.

Account owners also have a recent-auth protected refresh-token revocation path.
Firebase ID tokens already issued before revocation may remain valid for their
bounded lifetime, so the UI must not promise instantaneous eviction.

### RTC token issuance is quota-, replay- and lifecycle-bounded

Direct-call and room-token paths consume private transactional attempt budgets
before caller-selected call/room/graph reads. A later authorization,
integrity, capacity or conflicting-`requestId` refusal cannot roll back that
charge and become a free denial-of-wallet loop. Exact successful retries are
served through private idempotency state; reusing a key for different input
fails closed after the committed preflight.

Direct calls additionally have per-user locks, bounded device capability
reads, short-lived room-bound/UID-bound JWTs, immutable media intent, active
call expiry and retryable LiveKit teardown. Participant, friendship, block,
restriction and active-profile authority is rechecked at start, acceptance and
token boundaries. A declared LiveKit `TrackSource` is defense in depth for the
normal SDK, not proof of physical capture origin from a malicious client.

### Club operations have committed quotas and bounded lifecycle work

Community Club creation, deletion, ownership transfer, member removal, media
finalization and message moderation consume actor-wide minute/hour attempt
budgets before target reads or Storage/LiveKit work. Ownership guard documents
serialize changes that affect an owner's Club set. Capacity is recomputed from
canonical Club roots with `limit(max + 1)` and fails closed when a legacy set
cannot be established safely.

Deletion/member-removal/media paths use resumable or idempotent state and
bounded pages rather than materializing an unbounded Club, room or projection
set. External cleanup can be retried without granting authority from a client
payload or repeating an already-completed destructive transition.

### Room creation and participant control are bounded

Room creation uses a deterministic room ID and private idempotency ledger tied
to the actor, `requestId` and canonical input. Capacity bootstrap/read paths
use `limit(cap + 1)`, lock/guard state and fail-closed capacity markers instead
of an unbounded scan.

Room participant control consumes a committed actor-wide budget, bounds both
participants and active-session mirrors (`max + 1` probes), and stages
generation-bound teardown/revocation/permission work before calling LiveKit.
Completion checks the same operation marker, so an old retry cannot delete or
overwrite a newer session. Room-cover reserve/finalize/read operations likewise
use exact request identities, committed attempt limits, bounded upload leases
and generation-bound grants.

### Other retained strengths

- Direct-call signaling, locks and incoming mirrors are server-owned; clients
  cannot fabricate call state.
- LiveKit and Stripe secrets remain outside the repository. RTC JWTs are bound
  to the canonical room and UID.
- Bilateral friendship guards, both block directions, active profiles and
  restrictions are checked at privileged communication boundaries.
- Android backup remains disabled and no cleartext transport override,
  permissive certificate callback or broad ATS exception was found.
- The release diff secret scan found no new secret.

## Open release gates

### P1 — no FaceTime-grade application-level E2EE

LiveKit/WebRTC transport encryption protects media in transit, but the SFU is
inside the trust boundary. Product copy must not claim end-to-end encryption or
FaceTime equivalence. A future E2EE claim requires authenticated per-device key
establishment, rotation, participant-change handling, reconnect/rekey tests,
multi-device identity semantics and a recovery design that does not silently
downgrade encryption.

### P1 — recipient video capability and mixed-version enforcement

A legacy client can interpret a new video request as audio while the upgraded
caller enables a camera. Public video enablement requires an authoritative,
server-checked compatible device/build capability for the recipient and an
explicit mixed-version refusal. Safe order: backward-compatible Functions,
capability registration, server enforcement, compatible clients, then the
video feature flag.

### P1 — App Check telemetry and enforcement

Client integration exists, but callable enforcement remains off. First verify
valid-token/invalid-token/missing-token telemetry for iOS, Android and Web and
confirm the Web provider. Then enforce App Check in staged groups, prioritizing
mutating, billing, staff, media and RTC-token endpoints. App Check raises the
cost of scripted abuse; it does not replace Auth, Rules, authorization or rate
limits.

### P1 — physical two-device and network/media matrix

Automated/widget tests do not prove camera quality, microphone ownership, NAT
traversal, reconnect behavior, push delivery, lock-screen privacy or Bluetooth
routing. Before video release run at least iOS↔iOS, Android↔Android and
iOS↔Android, plus supported browser↔mobile pairs. Cover deny/revoke camera and
microphone, background during permission/connect, call replacement, account
switch/logout, poor network, reconnect, speaker/earpiece/Bluetooth, incoming
push while locked, terminal cleanup and post-expiry reconnect denial. Include
an intentional mixed-version pair.

### P2 — least-privilege runtime service accounts

The broad default Functions runtime identity remains a larger blast radius
than necessary. Split media signing/Storage, RTC/LiveKit, billing, moderation
and maintenance workloads into dedicated service accounts with only the IAM
roles each domain needs. Validate deploy/runtime behavior and rollback before
removing the legacy grants.

## Verified evidence for this candidate

Counts below are deliberately not added together: the targeted Node/Functions
runs overlap the broader suite.

| Check | Confirmed result | Status |
|---|---:|---|
| `flutter analyze` | 0 issues | Green |
| Full Flutter suite | 1,925 / 1,925 | Green |
| Final full serial Functions suite | 1,098 / 1,098 (118 suites) | Green |
| Participant-control targeted suite | 32 / 32 | Green |
| Callable invocation contract | 6 / 6 | Green |
| JavaScript syntax validation | 95 / 95 changed/new files | Green |
| `npm audit --omit=dev` | 0 vulnerabilities | Green |
| `gitleaks` release-diff scan | 0 new secrets | Green |
| Release Web build | completed | Green |
| Android App Bundle build | completed | Green |
| `git diff --check` | no errors | Green |
| Final whole Firestore Rules emulator suite | 522 / 522 | Green |
| Final whole Storage Rules emulator suite | 60 / 60 | Green |
| Final cross-service Family-media suite | 11 / 11 | Green |

## Release decision checklist

1. Verify production IAM needed for generation-bound signing without retaining
   broader roles than required.
2. Complete private-media migration/token inventory before the restrictive
   rule cutover, then verify deployed sources and object state.
3. Keep public video disabled until recipient capability enforcement and the
   physical matrix pass.
4. Roll App Check from telemetry to staged enforcement with rollback metrics.
5. Re-run dependency, secret, signed-build and store-delivery checks on the
   exact release commit.

No Hosting, Functions, Rules, TestFlight or Google Play publication is claimed
by this document.
