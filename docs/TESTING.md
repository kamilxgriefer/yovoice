# Testing

An honest picture of what's actually verified in this project, and how —
deliberately not aspirational. Several separate, unequal layers of coverage
exist; know which one you're relying on before trusting it.

## Current counts (2026-08-17)

One table, so there is a single place to correct when these move. Every
figure is a suite run, not an estimate; file counts are `find`.

| Suite | Command | Count |
|---|---|---|
| Firestore rules | `npm --prefix firestore-tests test` | **318** checks |
| Storage rules | `npm --prefix firestore-tests run test:storage` | **46** checks |
| Family media (combined) | `npm --prefix firestore-tests run test:family-media` | **11** checks |
| Cloud Functions | `npm --prefix functions test` | **510** tests across **82** suites (45 `*.test.js` files) |
| Flutter | `flutter test` | **521** tests across **55** files |

> **Correction, 2026-08-16.** These numbers were wrong in several docs for
> most of a week — TESTING.md claimed 268 rules checks and 43 Storage
> checks, Firebase.md claimed 265, Bugs.md and Roadmap.md claimed 225, and
> Bugs.md additionally claimed Cloud Functions had *zero* automated
> coverage while 510 tests were passing. The rules suite grew
> 268 → 281 (`56e7ea7`) → 295 (`2fc05e5`) → 301 (`952d8e4`) across one
> session and no doc followed it. If you change a suite, change this table
> in the same commit.

> **Movement, 2026-08-17.** Rules 301 → **318** (`c75720a`, the
> account-status gating; the suite ran 310 passed / 8 failed against the
> live ruleset before the fix). Flutter 438/52 → 486/54 (`6ef4380`) →
> **521/55** (`cefa81a`), all from the Voice Moment recording work.
> Storage, family-media and Cloud Functions are unchanged — no
> `storage.rules` or `functions/` change landed in either round.

## Firestore rules — the most mature coverage in the project

`firestore-tests/` — a standalone Node project running regression and
attack-scenario checks against `firestore.rules` via
`@firebase/rules-unit-testing` and the Firestore emulator — **318 checks
passing** — plus `storage.test.js`, the same treatment for `storage.rules`
against the Storage emulator (46 checks: path ownership, size caps,
content-type allowlists, read gating, default deny), plus 11 combined
family-media checks. All three run in CI on every push to `main` and gate
the Hosting release (see [DEPLOYMENT.md](DEPLOYMENT.md)). Full workflow in
[`firestore-tests/README.md`](../firestore-tests/README.md) and
[Firebase.md](Firebase.md#firestore-rules-testing); the short version:

```bash
brew install openjdk           # one-time, needed for the emulator's JVM
export PATH="/usr/local/opt/openjdk/bin:$PATH"
firebase emulators:start --only firestore --project yovoice-ec54a
cd firestore-tests && npm install && npm test
```

For the same verification as CI:

```bash
./firestore-tests/node_modules/.bin/firebase emulators:exec --only firestore --project demo-yovoice 'npm --prefix firestore-tests test'
./firestore-tests/node_modules/.bin/firebase emulators:exec --only firestore,storage --project demo-yovoice 'npm --prefix firestore-tests run test:storage'
./firestore-tests/node_modules/.bin/firebase emulators:exec --only firestore,storage --project demo-yovoice 'npm --prefix firestore-tests run test:family-media'
./firestore-tests/node_modules/.bin/firebase emulators:exec --only auth,firestore --project demo-yovoice 'npm --prefix functions test'
./firestore-tests/node_modules/.bin/firebase emulators:exec --only functions,auth,firestore --project demo-yovoice 'npm --prefix functions run test:smoke'
```

**Why this layer exists and matters more than usual for this project**:
Security Rules are the entire authorization layer here, not a secondary
check behind an API ([ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work)).
A bug in a rule is not a bug in one feature — it's a bug in the
authorization system itself. This suite is what stands between a rules
change and finding that out in production.

**The non-obvious failure mode this suite specifically guards against**:
a check that calls `getDoc()`/`getDocs()` on a fully-specified path proves
nothing about whether the same collection is safely queryable via
`collectionGroup()` — those are genuinely different code paths inside
Firestore's rule evaluator. A 40-check suite, entirely green, once shipped
a completely broken `collectionGroup()` query to production because none
of the 40 checks exercised that path
([ADR-007](Decisions.md#adr-007-firestore-rules-changes-are-always-emulator-tested-against-a-real-collectiongroup-query)).
Any rule touching a collection that's ever queried via `collectionGroup()`
needs a real `collectionGroup()` check, not just a direct-path one.

The current 318-case rules suite also pins the Premium boundary introduced in
ADR-053: a normal full profile bootstrap and a partial presence-first create
are allowed, forged Creator/Premium/staff first documents are denied, and an
active subscription with a disabled Creator or Clubs feature flag cannot use
that capability. Its Club-creation case commits the production-shaped batch —
Club root, owner member, user projection, three default channels and lounge
room — proving the `getAfter()` owner/channel checks work atomically after the
unused root-user `clubCount` write was removed. It also proves that accepting a
Club invitation can create only a plain `member` with the exact production
membership shape: attempts to self-assign owner/co-owner/admin or smuggle
permission fields are rejected. The matching Club-counter update must be in
the same batch as membership creation and invite deletion, can change no Club
metadata, and increments both counters exactly once. *(Until 2026-08-16 this
paragraph ended "the 2026-08-16 `firestore.rules` update still needs a manual
production deploy." That deploy has now happened — twice on 2026-08-16, at
20:40 and 21:06, per Console → Firestore → Rules version history. Passing
locally still does not deploy a rule.)*

### What the 2026-08-16 hardening pass added (`56e7ea7` → `2fc05e5` → `952d8e4`)

Each of these was a case that failed before its fix, on rules that were
live in production:

- Club manager role updates carry `role`, `roleUpdatedAt` and
  `roleUpdatedBy`, so an allowlist of only `['role','updatedAt']` denied
  **every** promotion and demotion.
- `canAccessRoom()` had no `isRoomMember` branch: a Community room flipped
  to private became unreadable to its own members, and one unreadable room
  emptied the entire Communities list because `watchMyCommunities()`
  hydrates every id in a single `Future.wait`.
- `isRoomMember()` had no account-status check, so widening
  `canAccessRoom()` handed private rooms to banned and disabled accounts.
- Role attribution was forgeable by omitting the field or resending the
  stored value — `diff().affectedKeys()` reports only fields whose *value*
  changed, so a `hasAny()`-gated guard never fires on a resent value.
  Attribution is now required unconditionally against the post-write
  document.
- `roomMembers` update had no field allowlist: a host could repoint their
  own membership row at a victim's uid, permanently and remotely emptying
  the victim's Communities tab with no action available to the victim.
- The rules-level eviction path added in `2fc05e5` was removed entirely in
  `952d8e4` — see
  [ADR-056](Decisions.md#adr-056-a-moderation-action-belongs-in-a-callable-that-completes-the-whole-removal-not-in-a-rule-that-deletes-one-row).
- The `collectionGroup()` PROOF cases are built by transforming the live
  ruleset, and the variant helper now **asserts each snippet is present
  before substituting** — so a reformatted rule fails loudly instead of
  silently running a control that proves nothing. Test scaffolding that
  can degrade into a no-op is worse than no test.

ADR-054 adds the private-profile boundary cases: an account can read its own
raw root, while ordinary users, moderators and super-admin clients cannot get
foreign roots, list `users`, or query by email/username. Public projections are
known-id get only, server-write-only and contain no private fields; inactive
targets and unauthenticated callers fail closed. Presence requires both
server-owned friendship guards; client-created mirror pairs cannot grant it.
Exact public-profile, presence and follow-edge schemas fail closed on extra
fields, while friendship guards and private quota documents are invisible and
immutable to all clients.

### What the 2026-08-17 account-status pass added (`c75720a`)

Seventeen checks, and the suite ran **310 passed / 8 failed** against the
then-live ruleset before the fix — the failures are the evidence, not the
fix's own green run. They cover a banned or disabled host attempting a room
metadata edit and a voice start, an inactive account attempting host-
admitted participation, `roomMembers` create, and a message reaction
update.

The `roomMembers` create case is the one worth copying. It was already
gated — on `isRestrictedAccount()`, which reads `banned` only and returns
**false when the account document does not exist**, so a disabled account
passed a check that read as though it covered account status. A test that
only exercises a *banned* account passes against that rule. **When a
status helper has more than one failing state, every state needs its own
case**; otherwise the suite proves the helper is called, not that it is
right.

**Always run against a freshly-started emulator.** A long-running emulator
can accumulate state between runs that makes a check pass or fail for the
wrong reason.

## Cloud Functions — real coverage, unevenly distributed

`functions/test/` — **510 tests across 82 suites in 45 files**, run with
`node --test test/*.test.js` against the Auth + Firestore emulators, and
gating the Hosting release in CI like the rules suites do. A separate
`npm --prefix functions run test:smoke` drives three trigger smoke scripts
against the Functions emulator.

**A real trap this suite has already sprung, worth knowing before you add
to it.** `node --test test/*.test.js` runs the files **concurrently
against one shared emulator**. Any assertion on an *absolute* count over a
collection that another file also writes is therefore load-bearing on
interleaving: it passes locally and fails on the runner, or vice versa.
`legacy_identity_scrub.test.js` asserted `scanned === 1` while
`scrubIdentitySnapshots` scans the whole `conversations` collection and
takes no uid or prefix scope, so it could not isolate itself the way its
own `wipe()` isolates its fixtures. That turned CI red on three
consecutive pushes — including a docs-only commit, which is what gave it
away, since 509 of 510 passed every time. Fixed in `38b29f7` by measuring
the **delta** around the test's own write, which keeps the assertion
exactly as strong (one document scanned, one scrub planned, nothing
written) while being independent of what else exists.

The general rule: assert on a delta or on a scoped fixture, never on an
absolute count over a collection your file does not exclusively own.

## Dart tests — real, but narrow

`test/` — **521 tests across 55 files**, green in local verification,
grown mostly
out of real bugs rather than an even coverage discipline. The
pattern throughout: fake the Firebase backends
(`firebase_auth_mocks` / `fake_cloud_firestore` /
`firebase_storage_mocks`), drive the real production code. Highlights:

- **`profile_save_e2e_test.dart`** — drives the REAL EditProfileScreen
  through pick → crop editor → Save → Storage → Firestore → stream
  emission; asserts the stored objects are the cropped 1024²/1920×1080
  JPEGs.
- **`friend_accept_notification_test.dart`** — the friend-request
  notification lifecycle (sender notified on accept, dedupe, retirement,
  silent decline).
- **`error_messages_test.dart`** — no raw exception text can reach the
  UI (includes the exact web-interop wrapper string users once saw).
- **`more_destination_nav_test.dart`** — More destinations keep the
  shell bottom navigation; bar taps pop back to the shell first.
- **`image_crop_test.dart`**, **`profile_image_rules_test.dart`** —
  crop geometry / output dimensions, validation budgets.
- Plus layout-regression suites (message-bubble overflow, profile
  header at 7 widths, auth link tap targets) and
  `auth_service_verification_test.dart`, the original template for the
  service-with-mocks shape.
- **`identity_badges_test.dart`** — the authoritative identity-badge
  system (ADR-045): exact role labels and hex colors, role×VIP
  coexistence and ordering, owner wire-value mapping, USER fallback,
  repository batching (one request per flush window, 50-uid chunking,
  in-flight dedup), cache invalidation and account-switch clearing,
  overflow at 120px, and achievement cosmetics being unable to replace
  official badges. `global_chat_test.dart` additionally proves message
  rows badge by SENDER UID from the projection, not by message flags.
- **`profile_journey_card_test.dart`** — imports the production compact
  journey list and renders it at 320/390/768/1024/1440 px, asserting no
  overflow and a bounded, width-independent height.
- **`premium_entitlements_test.dart`**, **`mobile_staff_parity_test.dart`**,
  **`desktop_shell_test.dart`** and **`family_room_test.dart`** — capability
  flags, complimentary-VIP non-access, locked More entries on mobile/desktop,
  navigation/direct-destination guards, save-time Creator expiry, Premium Club
  creation and the free Family Room exception.
- **`public_profile_privacy_test.dart`** — self profile reads stay on private
  `users`, foreign identity reads use `publicProfiles`, friend presence joins
  only `socialPresence`, public search goes through its injectable callable and
  discards injected private fields, new conversations contain no email
  snapshot, historical email snapshots are ignored, and follow identity is
  resolved from current public projections rather than stale edge fields.

- **`voice_moment_recording_seam_test.dart`**,
  **`record_voice_moment_screen_test.dart`** and
  **`record_voice_moment_accessibility_test.dart`** (2026-08-17) — the
  recording platform seam driven through `VoiceRecorderBackend` and
  `AudioCapture` test doubles rather than the plugin, which is the only
  way recording hardware is reachable from a widget test. They pin the
  MIME negotiation rule (`audio/mp4;codecs=mp4a` unsupported /
  `audio/mp4;codecs=mp4a.40.2` supported, codec parameter normalized away
  before the allowlist comparison), each `MicrophoneOutcome` mapping to its
  own copy, the timer never rendering `0:60`, and the amplitude stream
  reaching the waveform. **What they cannot prove**: that a real browser
  refuses in the way the mapping expects, or that a real microphone
  produces bytes Storage accepts.

**What this means in practice**: coverage is regression-driven — deep
where something once broke (profile media, notifications, navigation,
error copy, moment recording), absent where nothing has broken yet (rooms,
clubs, moment feeds and services). `test/widget_test.dart` is still the
generated boilerplate and provides nothing.

Run with:

```bash
flutter test
```

## Static analysis — the actual baseline gate

`flutter analyze` is the one form of verification that's both
consistently applied and enforced outside of human discipline: the GitHub
Actions Hosting-deploy workflow runs it before every deploy and fails the
build if it's not clean (see [DEPLOYMENT.md](DEPLOYMENT.md)). Zero issues
is the bar — not "zero errors, some warnings are fine."

## Manual verification — UI and voice flows

There are widget/layout regression tests, but no `integration_test/` suite and
no golden-image baseline. UI changes still need manual verification: run the
app (iOS Simulator when possible), exercise the actual golden path plus
loading/empty/error states. Voice-room flows (joining, muting, hand-raise,
moderation) are
particularly hard to cover automatically since they need a real LiveKit
connection and multiple simulated participants — these have historically
been verified with two real accounts on two real devices/simulators
rather than any automated harness.

**If a screen or flow genuinely can't be verified** (no test credentials
available in a given session, for example), that should be stated
explicitly rather than claimed as checked — an unverifiable claim of
"tested" is worse than an honest "couldn't verify this part."

## What has zero coverage today

Worth naming plainly rather than leaving implicit:

- Cloud Functions coverage is now present but uneven. The Node suites execute
  security-sensitive modules against the Firestore emulator; ADR-054 covers
  exact profile derivation, trigger replay/idempotency, block-filtered callable
  search, concurrent transactional quota/window reset and bounded dry-run/apply
  backfill. This is not a deployed-environment integration test and many older
  functions still lack focused coverage.
- Premium store purchase verification: no IAP client or App Store/Google Play
  adapter is configured, so there is no real checkout path to exercise.
  `verifyPurchase` deliberately declines and only the admin grant path works.
- Crash visibility on web: Crashlytics (added 2026-08-08) covers iOS and
  Android only — the Flutter web build still has no crash/error
  reporting channel beyond the browser console.
- **Real browsers and real microphones.** `flutter test` runs on the VM, so
  nothing in the suite executes `dart:js_interop`, `MediaRecorder`,
  `getUserMedia` or a `DOMException`. The web recording path is verified by
  seam tests plus a manual Chromium 148 check of the MIME negotiation;
  Safari, Firefox, an actual permission refusal, an unplugged or busy
  input device, and an end-to-end publish into production Storage and
  Firestore are all **UNVERIFIED**. No screen reader has been run against
  any screen in this project, on any platform; keyboard behavior is
  widget-tested only.
- **No test proves anything about what is deployed.** Every suite above
  runs against an emulator or a fake. A green run is evidence about the
  *repository*, never about production. On 2026-08-16 the deployed
  scheduled `expirePremiumIdentity` had been failing on a missing
  composite index — Premium never expired for any account — while every
  suite was green, because the emulator does not require composite
  indexes. Production claims need production evidence: `firebase
  functions:list`, the Console's rules version history, or fingerprinting
  the served bytes (see
  [ADR-055](Decisions.md#adr-055-the-2026-08-16-production-cutover--order-the-deploy-by-what-fails-closed-and-verify-by-fingerprinting-served-bytes)).
- **`voiceMinutes` has no writer at all**, so nothing can test it
  end-to-end. `receiveLiveKitAchievementWebhook` exists in
  `functions/achievements/livekit_http.js` but is never exported from
  `functions/index.js`, so the voice-achievement category and Creator
  Studio's "Voice time" tile are permanently zero. See
  [Bugs.md](Bugs.md#achievements).
- Broad service coverage remains uneven despite the 52 regression files;
  rooms, live audio and multi-user club flows still rely heavily on manual
  checks.
- Any cross-cutting integration flow (the join-room → LiveKit token flow
  described in [Architecture.md](Architecture.md#data-flow-a-concrete-example-joining-a-broadcast-room),
  for example) is verified manually end-to-end, not by any test.

This is a real gap, not a hidden one — see [Roadmap.md](Roadmap.md) and
[Bugs.md](Bugs.md) for related tracked items. Expanding coverage should
prioritize the same places `firestore-tests/` already treats as
high-stakes: anything touching authorization, permissions, or money
(Roadmap's monetization item, whenever that starts).
