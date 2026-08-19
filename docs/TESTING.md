# Testing

An honest picture of what's actually verified in this project, and how —
deliberately not aspirational. Several separate, unequal layers of coverage
exist; know which one you're relying on before trusting it.

## Current counts (2026-08-17)

One table, so there is a single place to correct when these move. Every
figure is a suite run, not an estimate; file counts are `find`.

| Suite | Command | Count |
|---|---|---|
| Firestore rules | `npm --prefix firestore-tests test` | **446** checks |
| Storage rules | `npm --prefix firestore-tests run test:storage` | **52** checks |
| Family media (combined) | `npm --prefix firestore-tests run test:family-media` | **11** checks |
| Cloud Functions | `npm --prefix functions test` | **593** tests across **98** suites (49 `*.test.js` files) |
| Flutter | `flutter test` | **881** tests across **95** files |

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

> **Movement, 2026-08-17 (ADR-062, the server-only conversation binding).**
> Every row above was re-measured by running all five suites, and three
> were stale by more than this change accounts for — the same drift the
> 2026-08-16 correction was written to stop.
>
> - Rules 318 → **347**. Only **3** checks are from this change (the
>   server-only `conversations` create, the `resource == null` get branch
>   for old installs, and `directConversationPairs` being default-denied).
>   The table had missed 318 → 344 from the two commits before it.
> - Cloud Functions 510/82 → **564/93**. Only **1** test is from this
>   change (pinning the pre-migration fork in
>   `functions/test/direct_integrity.test.js`); the baseline was measured
>   at **563/93** by stashing that one file and re-running, so 510/82 had
>   been stale for two commits. File count 45 → 47 by `find`.
> - Flutter 521/55 → **565/58**. **19** tests and 1 file are from this
>   change: the new `test/direct_conversation_open_test.dart` (18 cases)
>   plus a net +1 in `test/direct_message_send_test.dart`, where one case
>   asserting the defective `not-found` fallback was replaced by two
>   asserting the refusal. The measured baseline was 546/57 — the
>   `8f7aa03` round, recorded in Roadmap but never carried into this
>   table.
> - Storage **46** and family-media **11** re-measured and genuinely
>   unchanged.
>
> If you change a suite, run all five and correct this table in the same
> commit. Two consecutive rounds have now been reconstructed after the
> fact instead.

> **Movement, 2026-08-17 (Family Room creation hardening).** All five
> suites were run again after the Family flow changed. Rules **347 → 351**:
> the old root-only positive case was replaced by the real seven-write
> production batch, a missing-canonical-id probe, and negative root-only,
> incomplete-graph and malformed-channel cases. Flutter **565/58 → 573/59**:
> five lifecycle cases plus banner, concurrent-create and Family success
> screen regressions. Cloud Functions **564/93**, Storage **46** and combined
> family-media **11** were re-measured and remain unchanged.

> **Movement, 2026-08-17 (private DM media and Safari upload recovery).**
> The complete release gates were run again after both chat attachment
> placeholders became real private-media flows and the browser recorder began
> preserving its native Blob. Storage **46 → 53** adds reservation, identity,
> privacy, immutability, MIME/path and size checks for photo and voice
> attachments. Cloud Functions **564 → 572** adds reservation/finalization,
> cleanup, binding and canonical-bucket bootstrap regressions. Flutter
> **573/59 → 591/63** adds upload/finalize retry, media playback/state,
> narrow-screen layout and browser/native audio seam coverage. Firestore rules
> **351** and combined family-media **11** were re-run and remain unchanged.

> **Movement, 2026-08-17 (room creation reliability and shared stage).**
> Firestore **351 → 353** adds an immutable room-experience transition and
> the fail-closed Family artwork graph. Storage is **52/52** after replacing
> the pre-root upload permission with root-first Club media tests and explicit
> Family artwork denial. Functions **572/93 → 579/94** adds the
> generation-pinned `finalizeClubMedia` contract and its attack cases. Flutter
> **591/63 → 620/64** adds the four-identity stage matrix, atomic Podcast
> creation, Family no-media behavior and notification/dock clearance. The
> combined Family media suite remains **11/11**. `flutter analyze` and
> `flutter build web --release` also passed in the same final verification.

> **Movement, 2026-08-17 (consent-backed public website showcase).** Rules
> **353 → 363** add exact owner-controlled profile/Club consent documents and
> a pinned, read-only `publicShowcase/live` projection. Functions **579/94 →
> 593/98** add the bounded one-minute publisher, Auth/status/role revalidation,
> activity-cohort privacy, lifecycle cleanup and transfer-revocation cases.
> Flutter **620/64 → 622/65** adds the exact consent service and its profile/
> Club opt-in behavior. The complete Functions suite, Rules suite, focused
> Flutter tests and full `flutter analyze` were re-run after the final privacy
> review; the website separately passed its exact-schema parser tests, lint and
> a 42-route production build.

> **Movement, 2026-08-19 (ADR-082, direct messages are server-only).** Both
> changed rows were re-measured by running the suites, and both were stale
> by far more than this change accounts for — the drift the 2026-08-16
> correction was written to stop, for the fourth round running.
>
> - Rules **363 → 446**, of which **0** are from this change: it replaced
>   six DM-privacy checks with six server-only denial checks and rewrote one
>   regression case in place, so the count is unchanged by it. The measured
>   baseline at `b3c27fd` was already **446**; the table had missed 363 →
>   446 across several commits, the last of them the club chat moderation
>   pass.
> - Flutter **622/65 → 881/95**, of which **19** tests and 1 file are from
>   this change: the new `test/message_outbox_test.dart` (16 cases) plus a
>   net +3 in `test/direct_message_send_test.dart`, where the six
>   client-fallback cases became nine outbox cases. The measured baseline at
>   `b3c27fd` was **862/95**, so 622/65 had been stale for several rounds.
>
> Both baselines were re-measured twice, because `main` moved underneath
> this work mid-review (`b123aec` → `3d54bc3` → `b3c27fd`) and the club chat
> commit touched `firestore.rules` and `firestore-tests/rules.test.js` — the
> same two files. The figures above are from the rebased tree, not from the
> first measurement.
> - Storage **52**, family-media **11** and Cloud Functions **593/98** are
>   untouched — this change edits no `storage.rules` and no `functions/`
>   file.
>
> Re-measure before editing this table. Do not add your delta to the number
> already written here; four consecutive rounds have now found it wrong.

## Firestore rules — the most mature coverage in the project

`firestore-tests/` — a standalone Node project running regression and
attack-scenario checks against `firestore.rules` via
`@firebase/rules-unit-testing` and the Firestore emulator — **446 checks
passing** — plus `storage.test.js`, the same treatment for `storage.rules`
against the Storage emulator (52 checks: path ownership, size caps,
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

The current 351-case rules suite also pins the Premium boundary introduced in
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

### What ADR-082 changed here — direct messages became server-only

Six DM-privacy checks that asserted a client-direct send SUCCEEDS in the
permitted privacy modes now assert it is denied, and one older
`a verified user can still send a message` regression became a denial too.
The count did not move; what each check proves did.

The finding behind it: `conversations/{id}/messages/{id}` create checked
`isVerified()` — a token claim that says an email was confirmed once and
nothing about whether the account may still speak — but not the sender's
standing. `activeProfile()` and `assertNotRestricted()` run *inside*
`sendDirectMessage`, and `message_service.dart`'s `_sendTextMessageDirectly`
wrote the message document straight from the client whenever the callable
was unreachable. A banned or communication-muted account kept full direct
messaging by taking that path.

**The fix could not be "add the missing check", and that is the part worth
remembering.** Adding `canCommunicate()` to the rule was measured against
the emulator and exceeded Firestore's per-request document access-call
budget: the friends-privacy path had exactly one access call of headroom
(verified by adding synthetic `exists()` probes — +1 passed, +2 failed),
and a complete sender-status check costs more than one. An exhausted rule
does not skip the check; it errors, and an error denies — so the "fix"
broke legitimate friends-mode sends, failing
`SECURITY DM PRIVACY: friends requires both canonical guard halves` with
`Service call error. Function: [exists]`. Consolidating the rule's five
redundant re-reads of the conversation document, collapsing
`accountIsActive()` to one `get`, and collapsing `canonicalFriendshipGuard`'s
seven access calls were each tried; none freed enough.

Two lessons generalize:

1. **A server-side check inside a callable is not a control if a client
   fallback writes the same document.** Ask of every callable, "what happens
   when this is unavailable?" If the answer is a direct client write, the
   rule must repeat every check the callable makes — because the rule is the
   one that will actually run.
2. **A rule has a budget, and authorization that does not fit in it belongs
   somewhere else.** When a rule cannot afford all of its checks, the answer
   is not to ship the subset it can afford; it is to move the write behind
   something that can afford all of them.

Losing the fallback must not mean losing the message, so the client keeps a
bounded local outbox instead — see the Flutter section below.

## Cloud Functions — real coverage, unevenly distributed

`functions/test/` — **593 tests across 98 suites in 49 files**, run with
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

`test/` — **881 tests across 95 files**, green in local verification,
grown mostly
out of real bugs rather than an even coverage discipline. The
pattern throughout: fake the Firebase backends
(`firebase_auth_mocks` / `fake_cloud_firestore` /
`firebase_storage_mocks`), drive the real production code. Highlights:

- **`message_outbox_test.dart`**, **`direct_message_send_test.dart`**
  (2026-08-19, ADR-082) — the client no longer writes a direct message to
  Firestore under any circumstance, so "the callable is unavailable" had to
  stop meaning "write it yourself" without starting to mean "lose it". The
  outbox suite covers the three states (Pending / Retrying / Failed), the
  bound (it refuses past capacity, and evicts a FAILED entry rather than an
  unsent one to make room), persistence across a restart, a corrupt queue
  being dropped rather than thrown, and one unreadable entry not stranding
  the rest. The send suite covers the seam: nothing is written to Firestore,
  the message is queued, and a later flush delivers it exactly once.

  Two cases are the ones worth keeping if the rest were ever trimmed. The
  first is that a retry reuses the ORIGINAL `requestId` — the callable keys
  its idempotency ledger on it, so a regenerated id would turn every
  ambiguous failure into a duplicate message. The second is
  `_LosesTheResponse`, which commits the server write and *then* throws:
  the client cannot distinguish "never arrived" from "arrived and the
  acknowledgement was dropped", so it retries, and the test proves the
  replay leaves one message rather than two. A backoff case is included
  precisely because the others zero the backoff to make a same-tick flush
  due — without it, "no delay" would be untestable and a real regression in
  the delay could hide behind the convenience.

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
  creation and the free Family Room exception. `family_room_lifecycle_test.dart`
  additionally drives the complete create/reopen/invite accept/decline flow and
  proves that a second create does not fork the deterministic Family graph.
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
