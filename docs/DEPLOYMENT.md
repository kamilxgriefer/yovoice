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

## Staff Moderation Center

Three targets, and the index must land before the queue is opened or
its first query fails:

```bash
firebase deploy --only firestore:indexes
firebase deploy --only firestore:rules
firebase deploy --only functions:moderateReport
```

No Console step and no data migration: `reports` gained workflow fields,
and a report without them is treated as Open by both the client model
and the Function. Staff access needs a role assigned through the
existing `assignUserRole` flow — it writes both the custom claim and the
`users/{uid}.role` mirror that rules check.

Note the claim propagation direction: a newly promoted moderator sees
the Moderation entry once their ID token refreshes (sign out and in
forces it), while a REVOKED moderator loses access on their next
request, because the server record is checked too.

## Undeployed backend as of 2026-08-11 — the selective manifest

Everything below was **read from the live project**, not inferred from
filenames or from what the repo happens to contain:

```bash
firebase functions:list --project yovoice-ec54a
firebase firestore:indexes --project yovoice-ec54a
firebase hosting:channel:list --project yovoice-ec54a
```

### What production actually has right now

| Target | State | Evidence |
|---|---|---|
| Hosting (Flutter web) | **Already carries Global Chat AND the Moderation Center** | `live` released 2026-08-11 22:16:50; the served `main.dart.js` contains `Claim and review`, `Reports appear as the community files them`, `moderateReport`, `globalChat` |
| `onGlobalMessageModerated` | **Deployed** | in `functions:list`, v2, europe-west1, nodejs22 |
| `moderateReport` | **Not deployed** | absent from `functions:list` |
| `listReportAuditTrail` | **Not deployed** | new in this commit |
| `setUserBan` | Deployed, but **source changed** (token revocation on ban) | in `functions:list`; source diff in `24353d4` |
| `reports` + `adminAuditLogs` indexes | **None deployed** | `firestore.indexes` returns only `notifications` and `rooms` |
| `firestore.rules` | **`24353d4`-era IS deployed; `1e76d36`+ is NOT** | read from Console → Firestore → Rules on 2026-08-12: `globalChat` and `reportLimits` present, `isActiveStaff` absent. There is still no read-only CLI command — the Console is the only way to check. |

Two consequences worth stating plainly, because they are live now:

1. **Hosting is ahead of the backend.** Pushing to `main` auto-deploys
   the web app (see the CI section above), so both milestones' *client*
   code shipped the moment they were pushed, while their Functions,
   indexes and rules did not. A staff account opening Moderation in
   production today gets a queue query with no composite index and a
   `moderateReport` call that resolves to nothing. Nothing is corrupted
   — the actions simply fail — but the feature is not usable until the
   deploys below run.
2. **The next push does the same thing again.** Treat "push to `main`"
   as a Hosting deploy, and sequence the backend first.

### Cloud Functions — the complete selective list

Derived from `functions/index.js` exports, not from file names. Both
undeployed milestones are covered:

| Function | Why | Source |
|---|---|---|
| `moderateReport` | new export, never deployed | `functions/moderation/reports.js` (`1e76d36`) |
| `listReportAuditTrail` | new export, never deployed | `functions/moderation/report_audit.js` (this commit) |
| `onGlobalMessageModerated` | deployed, but its module changed | `functions/moderation/global_chat.js` (`24353d4`) |
| `setUserBan` | deployed, but now revokes refresh tokens on ban | `functions/admin/users.js` (`24353d4`) |
| `onFriendRequestCreated` | new export — friend-request notifications do not exist without it | `functions/notifications/social.js` (ADR-041) |
| `onFriendRequestResolved` | new export — acceptance notifications do not exist without it | `functions/notifications/social.js` (ADR-041) |
| `onFollowerCreated` | new export — follow notifications do not exist without it | `functions/notifications/social.js` (ADR-041) |

`functions/utils/audit.js` also changed — `writeAuditLog` gained an
optional `entryId` for deterministic, replay-safe audit ids. Its other
callers (`admin/clubs.js`, `admin/rooms.js`, `clubs/ownership.js`) pass
no `entryId` and keep the previous `.add()` behaviour exactly, so the
functions exported from those modules do **not** need redeploying. They
will pick the new util up whenever they are next deployed for their own
reasons.

Deploy them by name. A blanket `--only functions` would also redeploy 29
functions that did not change:

```bash
firebase deploy --only functions:onGlobalMessageModerated,functions:setUserBan,functions:moderateReport,functions:listReportAuditTrail,functions:onFriendRequestCreated,functions:onFriendRequestResolved,functions:onFollowerCreated --project yovoice-ec54a
```

All three notification triggers are v2 Firestore document triggers,
`europe-west1`, nodejs22, matching every other function in the project.
They are additive: deploying them before the client is safe, because the
client no longer writes these notifications and the triggers do not
depend on any client change.

**The one ordering constraint that can cause an outage**: the rules
change in this milestone REMOVES `friendRequest`, `friendAccepted` and
`follow` from the client-creatable notification types. Deploying rules
before the Functions would leave a window in which the client is denied
and no trigger exists yet — no social notifications at all. Functions
first, always.

### Firestore indexes

Five new composite indexes, each tied to a query that exists:

| Index | Query that needs it |
|---|---|
| `reports (status, createdAt DESC)` | the unfiltered queue |
| `reports (status, targetType, createdAt DESC)` | queue + target filter |
| `reports (status, reason, createdAt DESC)` | queue + reason filter |
| `reports (status, targetType, reason, createdAt DESC)` | queue + both filters |
| `adminAuditLogs (targetType, targetId, createdAt DESC)` | both scoped queries inside `listReportAuditTrail` |

`firestore.indexes.json` also regained `rooms (isLive, visibility,
createdAt DESC)`, which exists in production but had drifted out of the
file. It backs `RoomService.watchLivePublicRooms()` — the Home live-rooms
list. Keeping the file a superset of production means an index deploy can
never be the thing that removes it.

### Recommended order

Backend first, client last, and the audit trigger before anything that
lets a moderator remove content — otherwise removals happen in a window
where nothing records them.

```bash
# 1. Indexes first: they build asynchronously and the queue's first
#    query fails until they are READY. Watch Console → Firestore →
#    Indexes and wait for Enabled before step 4.
firebase deploy --only firestore:indexes --project yovoice-ec54a

# 2. The audit trigger, so a removal can never be unlogged, plus the
#    three social notification triggers. These MUST precede the rules
#    deploy in step 3, which withdraws the client's ability to write
#    those notification types.
firebase deploy --only functions:onGlobalMessageModerated,functions:onFriendRequestCreated,functions:onFriendRequestResolved,functions:onFollowerCreated --project yovoice-ec54a

# 3. Rules: staff read access to `reports`, the create-only report path,
#    and `adminAuditLogs` denied to every client.
#    Run the emulator suite against a FRESH emulator first.
cd firestore-tests && npm test && cd ..
firebase deploy --only firestore:rules --project yovoice-ec54a

# 4. The privileged callables.
firebase deploy --only functions:moderateReport,functions:listReportAuditTrail --project yovoice-ec54a

# 5. Immediate ban revocation.
firebase deploy --only functions:setUserBan --project yovoice-ec54a

# 6. The client. Already live via CI in this case — redeploy only if a
#    newer build needs to ship:
flutter build web --release && firebase deploy --only hosting --project yovoice-ec54a
```

Then verify with a real staff account: the queue loads, each filter
combination returns without a `FAILED_PRECONDITION`, one claim/release
round trip succeeds, and the audit timeline shows that action. Watch
Console → Functions → Logs for permission denials and errors on the four
functions, and Firestore usage for index-missing errors.

### Rollback, and what must never be deleted

Reversible by redeploying the previous revision from git history:

- **Functions** — `git checkout <previous-commit> -- functions/` then
  redeploy the same named list. Cloud Run keeps previous revisions, so a
  bad deploy can also be rolled back per function in the Console.
- **Rules** — `git checkout <previous-commit> -- firestore.rules` and
  redeploy. Rulesets are versioned in Console → Firestore → Rules with a
  history view.
- **Hosting** — previous releases are promotable from the Console.

**Not reversible, and not to be "cleaned up" during a rollback:**

- `adminAuditLogs` entries. They are the record of who did what, they
  are append-only by design, and deleting them to tidy a failed deploy
  destroys the only evidence a moderation decision ever happened.
- `reports` documents. Reporter evidence is immutable by rule; a
  rollback must not delete or rewrite it. Workflow fields (`status`,
  `assignedTo`, `resolution`) may legitimately move forward again after
  a redeploy.
- Soft-deleted Global Chat messages (`isDeleted: true` with the original
  text retained). The retained text IS the audit evidence.

Removing an index is safe but not instant to rebuild; removing a
Function only makes its clients fail, it destroys nothing.

## Web push configuration (required before web push works)

`web/firebase-messaging-sw.js` is in the repository and is copied into
`build/web` by `flutter build web`. The remaining prerequisite is the
**VAPID public key**. The production key is included in the Hosting build
command because it is public client configuration (the private half remains
inside Firebase):

- **Where to get it**: Firebase Console → Project settings → Cloud
  Messaging → Web configuration → *Web Push certificates*. Use the
  **public** key of the key pair.
- **Where to supply it**: as a build-time define:

```bash
flutter build web --release --dart-define=YOVOICE_WEB_PUSH_VAPID_KEY=THE_PUBLIC_KEY
```

  The Hosting CI workflow already supplies the production public key, so
  builds from `main` ship with web push enabled. Local release builds must
  pass the same define when they are intended for deployment.
- **Behaviour without it**: the app skips web push setup entirely — it
  does not request notification permission (a browser only grants that
  prompt once), does not call `getToken()`, and writes no token. It logs
  one line saying why. The in-app activity feed, badge, iOS and Android
  push are all unaffected.

Android's default notification channel is declared in
`AndroidManifest.xml`. The production iOS app is registered as
`app.yovoice` under Apple Team `C3R59P53KB`, and its Firebase app ID is
`1:80235878542:ios:0b3303647c76596a1351df`. APNs key `3288VCBHFD` is
uploaded in Firebase for both Development and Production. The private
`.p8` is intentionally outside the repository in the operator secret
backup (`~/Documents/YO Voice Secrets/AuthKey_3288VCBHFD.p8`) and cannot
be downloaded from Apple a second time. `remote-notification` is enabled
in `UIBackgroundModes`.

App Store releases use manual signing for the Release configuration with
the `YO Voice App Store` provisioning profile (UUID
`1a59a340-37ab-43a5-bdb2-bdc29d60600d`, expires 2027-08-15), Apple
Distribution, and `ios/ExportOptions.plist`. Build an uploadable IPA with:

```sh
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
```

The App Store Connect record is `YO Voice` (Apple ID `6801898909`). To upload
an already-built archive directly to App Store Connect/TestFlight, run:

```sh
xcodebuild -exportArchive \
  -archivePath build/ios/archive/Runner.xcarchive \
  -exportPath build/ios/app-store-upload \
  -exportOptionsPlist ios/ExportOptionsUpload.plist
```

The matching distribution private key, certificate, CSR, and provisioning
profile are intentionally stored outside the repository under
`~/Documents/YO Voice Secrets/`. Keep that directory backed up securely;
without the private key this Mac cannot use the distribution certificate.

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
