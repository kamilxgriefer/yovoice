# Testing

An honest picture of what's actually verified in this project, and how —
deliberately not aspirational. Three separate, unequal layers of coverage
exist; know which one you're relying on before trusting it.

## Firestore rules — the most mature coverage in the project

`firestore-tests/` — a standalone Node project running regression and
attack-scenario checks against `firestore.rules` via
`@firebase/rules-unit-testing` and the Firestore emulator. 43 checks as of
this writing. Full workflow in
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

`test/` — two files, two very different levels of maturity:

- **`test/auth_service_verification_test.dart`** — real unit test
  coverage for `AuthService`'s email-verification methods
  (`resendVerificationEmail`, `reloadCurrentUser`, `register`'s
  verification-failure handling), using `firebase_auth_mocks` and
  `fake_cloud_firestore` to fake Firebase without touching real
  infrastructure. This is the pattern to follow for testing a service in
  isolation — see the file itself for the mock-setup shape
  (`_buildService()`).
- **`test/widget_test.dart`** — the default Flutter-generated boilerplate
  (`expect(true, isTrue)`), never replaced with anything real. Exists, but
  provides zero actual coverage.

**What this means in practice**: almost none of `lib/features/` has unit
test coverage today. The one exception (`AuthService`'s verification
methods) exists because that specific flow had a real, confusing bug
during development and a unit test was the fastest way to pin down its
contract — not because of a general testing discipline applied evenly
across the app. Treat that file as a template for adding real coverage to
another service, not as evidence that services are broadly tested.

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
