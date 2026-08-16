# Firestore rules tests

Regression + attack-scenario coverage for `../firestore.rules`, run against
the Firestore emulator via `@firebase/rules-unit-testing`. Each check either
asserts a legitimate write/read from the app's own services still succeeds
("regression"), or that an exploit described in `../docs/Archive/SECURITY_AUDIT.md`
is blocked ("SECURITY").

Treat this suite as the authorization baseline and add a regression or attack
case whenever a rule changes, before deploying.

## Setup (one-time)

```bash
cd firestore-tests
npm install
```

Requires a JVM for the Firestore emulator. On macOS, if `java` isn't already
on your PATH:

```bash
brew install openjdk
export PATH="/usr/local/opt/openjdk/bin:$PATH"   # add to your shell profile to make this permanent
```

## Running

Start the emulator in one terminal:

```bash
firebase emulators:start --only firestore --project demo-yovoice
```

Then, in another terminal:

```bash
cd firestore-tests
npm test
```

Exits non-zero if anything fails. Prints `OK`/`FAIL` per check plus a
`<n> passed, <n> failed` summary.

## Family Moment media (combined Firestore + Storage)

`family-media.test.js` is the only suite that proves the cross-service
gate: `family_moments/{clubId}/{uid}/…` in `storage.rules` is authorised by
a `firestore.exists()` lookup against the family room's member document.

Both emulators must run in the SAME hub, started with the SAME project id
the harness uses, or the lookup silently resolves to nothing and EVERY
case denies — which looks like a pass for every "must be denied" check and
proves nothing. That is why this suite asserts the allowed uploads too;
if those go red, the gate is not being consulted.

```bash
firebase emulators:start --only firestore,storage --project demo-yovoice
npm --prefix firestore-tests run test:family-media
```

A green run here is the precondition for deploying `storage.rules`.

## Private-profile boundary

The ADR-054 cases prove document-level privacy rather than relying on client
field filtering: self root get succeeds; foreign get and every `users` list or
query fail for ordinary users, moderators and super-admin clients; public
profiles are known-id-get/server-write only; unauthenticated and inactive
targets fail; friend presence requires both graph mirrors; and Admin-only
search quotas cannot be read, reset or forged. Keep these negative cases when
adding fields to `users` or changing staff capabilities.

## Adding a case

Each check is a `check("description", async () => { ... })` call — see
existing ones for the pattern. Use `assertSucceeds()` for writes/reads that
must work and `assertFails()` for ones that must not. Seed any documents the
check depends on via `testEnv.withSecurityRulesDisabled(...)` first.

A few non-obvious things this file's existing cases lean on, worth knowing
before adding more:

- **Same-batch/transaction visibility.** `exists()`/`get()` inside a rule see
  the state *before* the current transaction/batch's writes are applied, even
  for other writes in that same transaction. `getAfter()`/`existsAfter()` see
  the state *after*. Get this backwards and a case will pass for the wrong
  reason (or fail for a confusing one).
- **`collectionGroup()` queries** are rejected outright unless every
  collection they span has a read rule Firestore can prove from the query's
  own filter, without extra reads. A rule needing an extra `exists()`/`get()`
  check (like club membership) can't satisfy that — see the
  `clubs/{clubId}/members` cases for the pattern used to route around it.
