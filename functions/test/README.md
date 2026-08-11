# Cloud Functions tests

Coverage for triggers whose behaviour is not expressible in Firestore
rules. Today that is one function:
`onGlobalMessageModerated`, which writes the `adminAuditLogs` entry for a
moderator removing a public Global Chat message.

Everything about *who may do what* to Global Chat lives in
`../../firestore-tests/rules.test.js`, evaluated against the real
`firestore.rules`. Don't duplicate authorization assertions here.

## Running

The tests call the trigger's handler directly and talk to the
Firestore emulator, so no project credentials and no extra dependency
are involved — `functions/node_modules` is tracked in this repository, so
a devDependency for one test file would land in every future diff.

Start the emulator in one terminal:

```bash
firebase emulators:start --only firestore --project yovoice-fn-test
```

Then, from `functions/`:

```bash
npm test
```

`FIRESTORE_EMULATOR_HOST` defaults to `127.0.0.1:8080` and
`GCLOUD_PROJECT` to `yovoice-fn-test`; override either if your emulator
runs elsewhere.

## Trigger-binding smoke test (separate, deliberate)

`global_chat_trigger.smoke.js` is **not** part of `npm test`: it needs
the functions emulator as well as Firestore, which takes ~90s to boot and
loads every function in the catalogue. Run it when the trigger's wiring
changes, or before a release:

```bash
firebase emulators:start --only functions,firestore --project yovoice-fn-test
node test/global_chat_trigger.smoke.js
```

It writes a real message, soft-deletes it the way a moderator would, and
waits for the audit entry — proving the part the unit tests cannot: that
Firestore actually delivers the event to this handler, and that exactly
one deterministic `globalMessage_<eventId>` document comes out. Exits
non-zero on failure.

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
