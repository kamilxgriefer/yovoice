# Testing

An honest picture of what's actually verified in this project, and how —
deliberately not aspirational. Three separate, unequal layers of coverage
exist; know which one you're relying on before trusting it.

## Firestore rules — the most mature coverage in the project

`firestore-tests/` — a standalone Node project running regression and
attack-scenario checks against `firestore.rules` via
`@firebase/rules-unit-testing` and the Firestore emulator — 91 checks as
of 2026-08-08 — plus `storage.test.js`, the same treatment for
`storage.rules` against the Storage emulator (22 checks: per-path
ownership, size caps, content-type allowlists, read gating, default
deny). Both suites also run in CI on every push to `main` and gate the
Hosting deploy (see [DEPLOYMENT.md](DEPLOYMENT.md)). Full workflow in
[`firestore-tests/README.md`](../firestore-tests/README.md) and
[Firebase.md](Firebase.md#firestore-rules-testing); the short version:

```bash
brew install openjdk           # one-time, needed for the emulator's JVM
export PATH="/usr/local/opt/openjdk/bin:$PATH"
firebase emulators:start --only firestore --project yovoice-ec54a
cd firestore-tests && npm install && npm test
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

**Always run against a freshly-started emulator.** A long-running emulator
can accumulate state between runs that makes a check pass or fail for the
wrong reason.

## Dart tests — real, but narrow

`test/` — 78 tests across ~14 files as of 2026-08-08, grown almost
entirely out of real bugs rather than an even coverage discipline. The
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

**What this means in practice**: coverage is regression-driven — deep
where something once broke (profile media, notifications, navigation,
error copy), absent where nothing has broken yet (rooms, clubs,
moments services). `test/widget_test.dart` is still the generated
boilerplate and provides nothing.

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

There is no automated UI test coverage (no `integration_test/`, no golden
tests). UI changes are verified manually: run the app (iOS Simulator when
possible), exercise the actual golden path plus loading/empty/error
states. Voice-room flows (joining, muting, hand-raise, moderation) are
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

- Cloud Functions (`functions/`) have no automated tests at all — nothing
  in `functions/package.json` runs anything beyond `firebase emulators:start`.
  Correctness here currently rests entirely on manual verification plus
  the Firestore rules suite covering the data these functions read.
- Crash visibility on web: Crashlytics (added 2026-08-08) covers iOS and
  Android only — the Flutter web build still has no crash/error
  reporting channel beyond the browser console.
- Almost all Flutter services and widgets beyond `AuthService`'s
  verification methods.
- Any cross-cutting integration flow (the join-room → LiveKit token flow
  described in [Architecture.md](Architecture.md#data-flow-a-concrete-example-joining-a-broadcast-room),
  for example) is verified manually end-to-end, not by any test.

This is a real gap, not a hidden one — see [Roadmap.md](Roadmap.md) and
[Bugs.md](Bugs.md) for related tracked items. Expanding coverage should
prioritize the same places `firestore-tests/` already treats as
high-stakes: anything touching authorization, permissions, or money
(Roadmap's monetization item, whenever that starts).
