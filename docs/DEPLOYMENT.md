# Deployment

What deploys automatically, what's manual, and exactly how — for both
deployables described in
[ADR-014](Decisions.md#adr-014-two-deployables-one-firebase-project).

## Summary

| What | How | Trigger |
|---|---|---|
| Flutter web build → Firebase Hosting | GitHub Actions | Automatic, on push to `main` |
| Firestore rules + indexes | `firebase deploy --only firestore:rules,firestore:indexes` | Manual |
| Cloud Functions | `firebase deploy --only functions` | Manual |
| Storage rules | `firebase deploy --only storage` | Manual |
| `yovoice-website` | Vercel | Automatic, on push to `main` (separate repo) |

## Flutter web → Firebase Hosting (automatic)

`.github/workflows/firebase-hosting-merge.yml` runs on every push to
`main`:

```
checkout → install Flutter (stable channel) → flutter pub get
  → flutter analyze → flutter test
  → Firestore + Storage rules suites against the real emulators
  → flutter build web --release
  → deploy to Firebase Hosting (channel: live)
```

**Every step before the build is a real gate, not just a step**: a
failing `flutter analyze`, a failing widget/unit test, or a failing
rules test stops the workflow before anything deploys — a broken `main`
means the web build doesn't ship, full stop. (Until 2026-08-08 only
`flutter analyze` gated the deploy; the test and rules-suite gates were
added in the product-audit pass. Note the rules suites *verify* the
rules in the repo — rules **deploys** remain manual, see below.) See
[TESTING.md](TESTING.md) and
[DEVELOPMENT_WORKFLOW.md](DEVELOPMENT_WORKFLOW.md#verification-checklist-before-calling-something-done).

Deploys to the `live` channel using
`firebaseServiceAccount: '${{ secrets.FIREBASE_SERVICE_ACCOUNT_YOVOICE_EC54A }}'`
— a repo-level GitHub secret, not anything checked into the repo.

This workflow deploys **Hosting only**. It does not touch Firestore rules,
indexes, Storage rules, or Cloud Functions — those are separate, manual
steps, on purpose (see below).

## Why rules/functions are not in CI

Auto-deploying `firestore.rules` on every push to `main` would mean a
single bad rules change goes live the moment it's pushed, with no
verification step in between beyond whatever the pusher ran locally.
Given that Security Rules are this project's entire authorization layer
([ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work)),
that's a meaningfully higher-stakes automatic action than redeploying a
web build — a bad Hosting deploy is annoying and reversible; a bad rules
deploy can be a live security hole or a locked-out user base. Keeping
rules/functions deploys manual and deliberate is the current tradeoff;
revisit this if the emulator test suite (see
[TESTING.md](TESTING.md)) ever becomes trusted enough to gate an automatic
deploy the way `flutter analyze` gates the Hosting one.

## Firestore rules and indexes (manual)

Always run the emulator test suite against a **freshly-started** emulator
before deploying a rules change — see
[TESTING.md](TESTING.md#firestore-rules--the-most-mature-coverage-in-the-project)
for why a passing suite isn't automatically sufficient proof, particularly
for anything touching `collectionGroup()` queries.

```bash
firebase deploy --only firestore:rules,firestore:indexes --project yovoice-ec54a
```

## Cloud Functions (manual)

```bash
firebase deploy --only functions --project yovoice-ec54a
```

**Gotcha worth knowing before you reach for it**:
`functions/package.json`'s `deploy` script —
`npm run deploy` run from inside `functions/` — only deploys
`createLiveKitToken`, not every function:

```json
"scripts": {
  "deploy": "firebase deploy --only functions:createLiveKitToken",
  "serve": "firebase emulators:start --only functions"
}
```

This is a convenience shortcut for the function that changes most often
during voice-feature work, not a full-deploy command. For a real full
deploy, run the `--only functions` command above from the **repo root**,
not `npm run deploy` from inside `functions/`.

## Storage rules (manual)

```bash
firebase deploy --only storage --project yovoice-ec54a
```

## `yovoice-website` (automatic, separate repo)

Deploys to Vercel automatically on push to `main` in the
`yovoice-website` repo. Environment variables (including
`NEXT_PUBLIC_APP_URL` — see
[ADR-009](Decisions.md#adr-009-next_public_app_url-as-an-env-var-website-repo))
are managed per-environment (production/preview/development) in the
Vercel dashboard, not in this repo. See that repo's own README for its
build/deploy specifics.

## Domains

```
yovoice.app            → Vercel (yovoice-website)
auth.yovoice.app        → Firebase Hosting — shared Auth domain, live
app.yovoice.app          → Firebase Hosting — configured, waiting on a
                          Cloudflare DNS record only the domain owner can
                          add — see Roadmap.md
```

## Global Chat

Global Chat needs **no manual Firestore Console step**. The canonical
channel is `globalChat/main/messages`; Firestore addresses a
subcollection independently of its parent, so the `globalChat/main`
document does not have to exist and is never created — by anyone. The
channel id is pinned to `main` inside `firestore.rules`, and clients are
denied `write` on `globalChat/{channelId}` entirely, so no second
"global" channel can be stood up either. A rules test asserts the
channel works with the parent document absent.

Shipping it is therefore the ordinary two deploys:

```bash
firebase deploy --only firestore:rules
firebase deploy --only functions:onGlobalMessageModerated
```

The trigger is what writes an `adminAuditLogs` entry when a moderator
removes someone else's message. Rules alone cannot log, so skipping the
functions deploy means moderator removals happen with no audit trail.

## App Check rollout (not enabled — staged plan)

App Check enforcement is **off** on every Cloud Function
(`enforceAppCheck: false`) and not enabled for Cloud Firestore. That is
deliberate: turning it on before clients reliably produce valid tokens
locks out real users. See
[ADR-004](Decisions.md#adr-004-firebase-app-check-integrated-client-side-enforcement-deliberately-off).

What App Check does and does not do: it attests that a request comes
from a genuine instance of **your** app, which raises the cost of
scripted abuse against a public surface like Global Chat. It is **not**
authentication, and it replaces none of the layers that actually
authorize: Firebase Auth, Firestore rules, the account-status check,
moderation, or the rate limits. A stolen token from a real client still
passes App Check.

Stages, in order — do not skip ahead:

1. **Register every legitimate app variant** in the Firebase Console:
   Flutter web (reCAPTCHA Enterprise, on every origin that serves the
   app, including preview channels), iOS (App Attest, with DeviceCheck
   as the fallback for older OS versions), and Android (Play Integrity)
   if and when those ship. A variant that is not registered is a variant
   that gets locked out at step 4.
2. **Ship clients that mint tokens.** Activate App Check at startup
   before any Firebase call, release, and wait for meaningful adoption —
   old installs keep running until users update, and their requests will
   count as "outdated" below.
3. **Monitor**, in Console → App Check → Metrics, per service (Firestore
   and each Function). Four buckets matter: *verified* (good),
   *outdated client* (real users on old builds — must fall to near zero
   before enforcing), *unknown* (usually an unregistered origin or a
   platform you forgot), and *invalid* (either abuse, or a
   misconfiguration). Watch for at least one full release cycle so
   weekly-active users are represented, not just daily-active ones.
4. **Enable enforcement**, Firestore first, then Functions one at a
   time, starting with the least critical. Global Chat's send path is
   pure Firestore, so Firestore enforcement is what covers it.
5. **Rollback and debug tokens.** Enforcement is a Console toggle and
   takes effect within minutes — turning it back off is the rollback,
   and it should be the immediate response to any spike in denied
   requests from real users. For local development and CI, register
   **debug tokens** per machine rather than disabling enforcement;
   treat a debug token as a credential (it bypasses attestation), never
   commit one, and revoke it when the machine or contributor changes.

## Rollback

There's no automated rollback pipeline for any of the four manual deploy
targets above. For Hosting, Firebase keeps previous release versions
browsable/promotable from the Firebase Console. For Firestore
rules/indexes and Cloud Functions, the practical rollback is redeploying
the previous version from git history (`git checkout <previous-commit> --
firestore.rules && firebase deploy --only firestore:rules`, or the
equivalent for `functions/`) — there's no one-command "undo the last
deploy." This is a real gap for a project this project's size to not have
yet; worth building out if a bad rules or functions deploy ever actually
happens in production.

## Environment configuration

Firebase project config (`yovoice-ec54a`) is baked into
`lib/firebase_options.dart`, generated via `flutterfire configure` and
already committed — there's no separate staging/production Firebase
project today. Every environment (local dev, CI, production) talks to the
same live Firebase backend. This is a real risk worth naming: there is no
sandboxed environment for trying a risky change against real
infrastructure short of the Firestore emulator (rules only) — see
[Bugs.md](Bugs.md) and consider this a candidate for a future "add a
staging Firebase project" decision if the team or user base ever grows
enough to justify the added complexity.
