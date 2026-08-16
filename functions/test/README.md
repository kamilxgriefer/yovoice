# Cloud Functions tests

Automated coverage for callable functions, Firestore triggers and security
critical backend helpers. The suite covers moderation, staff authorization,
social graph mutations, Club ownership and quotas, notifications, Premium
expiry, media deletion validation, private-profile projections/search quotas
and LiveKit room/session enforcement.

Firestore and Storage authorization are tested separately against the real
rules in `../../firestore-tests/`; Functions tests must still validate every
server-side authorization check because Admin SDK writes bypass those rules.

## Running

The tests call handlers directly and talk to fresh Auth/Firestore emulators.
No production credentials are used. Dependencies are installed from
`package-lock.json`; `node_modules` is deliberately not committed.

Start the emulator in one terminal:

```bash
firebase emulators:start --only auth,firestore --project demo-yovoice
```

Then, from `functions/`:

```bash
npm test
```

`FIRESTORE_EMULATOR_HOST` defaults to `127.0.0.1:8080`. CI and the documented
commands set `GCLOUD_PROJECT` to the credential-safe `demo-yovoice` project.

## Trigger-binding smoke test (separate, deliberate)

The binding smoke scripts are **not** part of `npm test`: they need the
Functions emulator as well as Auth/Firestore and load the full exported
catalogue. Run them before a release (CI runs the same command):

```bash
firebase emulators:exec --only functions,auth,firestore --project demo-yovoice \
  'npm --prefix functions run test:smoke'
```

The smoke set proves Firestore event delivery, moderation callable transport,
and the social-graph callable bindings, including replay-safe friendship
counters. It exits non-zero on any missing export or runtime failure.

## What is covered

- an author deleting their own message is **not** audited (that is
  ordinary use, not moderation);
- a moderator soft deletion records the moderator, the message, the
  original author and the removed text;
- unrelated updates to a live message record nothing;
- re-touching an already-deleted message records nothing;
- a **retried** delivery of the same CloudEvent cannot duplicate the
  audit record — Firestore triggers are at-least-once, so the entry id is
  derived from the event id rather than auto-generated;
- two genuinely different removals are recorded separately;
- the export is reachable from `functions/index.js` and carries the
  expected trigger metadata (region, document path, event type), so a
  deploy actually ships it.
- `publicProfiles` and `socialPresence` are exact, idempotent projections with
  no private-field leakage; inactive/Auth-deleted accounts are removed, blocked
  profiles are hidden from verified-only search, concurrent searches cannot
  exceed the transaction-backed budget, and the Auth-aware dry-run/apply
  backfill stays page/batch bounded and resumable;
- canonical friendship acceptance creates paired private guards, legacy mirror
  pairs cannot mint them, remove/block retires them atomically, graph caps and
  private transactional quotas fail closed, and mutual/suggestion reads remain
  bounded;
- the legacy-identity scrub is dry-run by default, page-bounded, resumable and
  aggregate-only, while apply mode removes request email, neutralizes DM email
  snapshots and rewrites follow edges to the exact uid/time schema;
- staff directory email is Auth-authoritative and staff display requires the
  Auth role claim to agree with the server-owned role mirror.
