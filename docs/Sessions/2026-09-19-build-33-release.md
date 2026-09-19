# Build 33 polish round — web live, iOS to testers, Play upload left standing — 2026-09-19

## Status

**Two surfaces moved, one did not, and no backend was touched. Each claim below
carries its own level of proof; read the level before repeating the claim.**

- **Deployed and read back by content.** The web build is live on Firebase
  Hosting — release `ce6c614150a7e8d9` (`2.0.0+33 / main 46d6b330`) at
  `2026-09-19T07:34:38.852Z`. Both `app.yovoice.app` and
  `yovoice-ec54a.web.app` return `build_number "33"` and serve `main.dart.js`
  sha256 `5185fad5…e9847`, which is the exact file that was built.
- **Released to testers, on one store.** iOS build 33 is `VALID` on App Store
  Connect, `betaReviewState APPROVED`, in the internal *and* external beta
  groups, `internalBuildState` and `externalBuildState` both `IN_BETA_TESTING`,
  `autoNotifyEnabled true`. Apple notifies the testers; nothing else is needed
  for iOS.
- **Built, verified, and deliberately not shipped.** The Android App Bundle
  (versionCode 33, upload-key signature identical to Builds 30–32) exists as a
  staged file. No Play Console action was taken, so Play internal testers are
  still on build 32.
- **Nothing was deployed to the backend, and nothing needed to be.**
  `functions/`, `firestore.rules`, `firestore.indexes.json` and `storage.rules`
  all show **0 changed files** across `a18fe789..46d6b330`.
- **Still switched off, on purpose.** `appConfig/accountDeletion` does not
  exist, so self-service deletion is fail-closed everywhere. Build 33's tester
  notes correctly say nothing about it.
- **Verified by tests, CI, API read-backs and a prior rendered-frame audit
  only.** Nobody ran build 33 on a device or in a simulator during this round.
  No screenshot of this binary, no tester report on it.

Nothing here claims a Play release, a device run, or a tester-confirmed fix,
because none of those happened.

## What Build 33 is

`main` `46d6b330dabdee6c672faeabb8e9f27dd06df039`, `pubspec.yaml` `2.0.0+33`,
nine commits over the Build 32 tree `a18fe789`. All three GitHub Actions
workflows are green on that revision — `CodeQL`, `Flutter web browser smoke`,
and `Deploy YO Voice to Firebase Hosting` (the last one builds and verifies; it
does not release, see below).

| Commit | What |
| --- | --- |
| `1c655c6d` | records the Build 32 backend round and client release in the docs |
| `a5bd9c0a` | every avatar resolved from the uid through the viewer-authorized grant; grant validation made tolerant of device clock skew (ADR-208) |
| `497e5743` | the profile banner opens fullscreen, and the app says why there is no photo |
| `4b65e84a` | a face is a door to the person on every surface that shows one |
| `73d6f337` | one localized conversation preview for the list, Home and the overlay |
| `ca0ba6fe` | headings, launcher tiles, the dock caption, and a switch that read as ON |
| `0b18922b` | a Moment hand-off no longer leaves the spinner and the like button dead |
| `3d52d9b2` | this round's findings in Bugs.md; App Check reclassified from deferred to blocked, on measurement |
| `46d6b330` | `2.0.0+33` |

This is the polish round the owner asked for before the Slim redesign starts:
every small thing had to work first.

**The round is client-only, and that was measured rather than asserted.**
`git diff --name-only a18fe789..46d6b330` touches 30 files under `lib/`, 29
under `test/`, 8 under `docs/`, and one line of `pubspec.yaml` — and **zero**
under `functions/`, `firestore.rules`, `firestore.indexes.json`,
`storage.rules`, `android/` or `ios/`. Two consequences were used as controls
during the round: 30 changed Dart files mean the binaries *must* differ from
Build 32's, and zero `android/` changes mean the decoded Android manifest *must*
differ from Build 32's in `versionCode` alone. Both predictions held exactly.

## The part worth keeping: the build worktree

The Slim-redesign session was editing `/Users/kamil/Documents/GitHub/yovoice`
throughout this round — it committed `f5713426` and `89c3d2be` locally while the
iOS build was running. So nothing was built from the checkout. All three
artifacts came from `/private/tmp/yovoice-b33-build`, a clean detached worktree
at `46d6b330`, whose `HEAD` never moved and whose `git status --porcelain` read
**0 lines** before and after every phase.

That isolation removed a class of failure rather than merely working around it:

- **No stale artifact could ship.** `build/web`, `build/app` and `build/ios`
  did not exist in the worktree before the build, so every property recorded
  this round is read off a file this round created. Builds 31 and 32 each had to
  identify a predecessor's artifact by hash and move it aside at exactly this
  step.
- **The checkout's stale trees are now a live trap.**
  `/Users/kamil/Documents/GitHub/yovoice/build/web/version.json` still says
  `32`, with two further stale trees beside it. A `firebase deploy` from the
  main checkout would silently have shipped **build 32 labelled as 33**.
- **The redesign work is provably not in build 33.** `origin/main` is
  `46d6b330`; the redesign commits are local and unpushed.

The cost is cold caches, not correctness: the iOS archive took 731.6 s against
Build 32's 401.7 s, and Gradle `bundleRelease` 464.6 s against 192.1 s. Worth
paying. `flutter clean` was not run anywhere.

## The client round

### Web — deployed, and verified by hash on both hosts

The build reproduces CI's `Build Flutter Web` step byte for byte, including the
empty reCAPTCHA site key (the repository has zero Actions variables, so CI
expands it to the empty string as well). `07:31:56Z → 07:33:57Z`, 121 s, exit 0.

The artifact was accepted by content before anything was deployed:
`version.json` `build_number "33"`, `main.dart.js` sha256 `5185fad5…e9847`
(11 444 060 B), the VAPID key present in `main.dart.js`, 112 files — and
distinct from build 32's `224854be…d5f8d`, which is what makes this a real
release rather than a mislabelled no-op. A hard gate then re-verified `HEAD`,
tree cleanliness, `version.json == 33`, VAPID presence and that exact hash
immediately before the deploy, and would have aborted on any drift.

The deploy was `firebase deploy --only hosting --project yovoice-ec54a
--non-interactive -m "2.0.0+33 / main 46d6b330"`, 17 s, exit 0. **`--only
hosting` is load-bearing**: `firebase.json` carries `functions`, `firestore` and
`storage` blocks beside `hosting`, and the log names exactly one target with no
functions, rules or index line anywhere in it. `found 111 files` against 112
built is the `.last_build_id` file excluded by the `"ignore": ["**/.*"]` rule —
Build 32 deployed the same 111-of-112.

Then the read-back, which is the only claim that matters: both hosts return
`build_number "33"` and serve `main.dart.js` `5185fad5…e9847`, equal to the
built file. Verified by hash, not by the deploy tool's own say-so, and re-read
live while this record was written.

**One open worry from the release-engineering record is now closed.** That
record flagged that the push-triggered `Deploy YO Voice to Firebase Hosting` run
on `46d6b330` was still `in_progress` and might create a Hosting release *later*
than `ce6c614150a7e8d9`, which would move the rollback target. It did not. The
run completed **success** in 28 m 16 s and created no release, because both the
artifact-packaging step and the `deploy_hosting` job are gated
`if: github.event_name == 'workflow_dispatch' && inputs.deploy_hosting`
(`.github/workflows/firebase-hosting-merge.yml:163`, `:171-172`). A push build
proves the build and the suites, never a release. The newest Hosting release is
still `ce6c614150a7e8d9`, re-read while this record was written.

App Check on web remains **disabled** — the empty reCAPTCHA site key means a
release web build activates no provider. Pre-existing since Build 30, and the
only known gap in this bundle.

### iOS — done

Built at `46d6b330` on the first attempt (13 m 23 s), uploaded with `xcrun
altool`, `VALID` 7 m 14 s later, tester notes PATCHed (HTTP 200, 595 chars,
`stored == requested`), attached to the external group (HTTP 204), submitted for
beta review (HTTP 201) and returned `APPROVED`. The notes PATCH was deliberately
done **before** the review submission, because Apple requires tester notes on an
external submission — the same ordering change Builds 31 and 32 made.

Provenance is clean, for the second round running: `HEAD` was `46d6b330` and the
tree clean at build start and still so after every TestFlight write; the IPA's
sha256 (`33d2caec…3e46d7`) has not changed since it was written; the staged copy
matches byte for byte; and the byte count Apple acknowledged (79 182 553) equals
the file's size exactly. The ASC build id equals the altool Delivery UUID, which
links the record Apple processed to the file this round uploaded. The uploaded
binary is provably what `46d6b330` produces — measured, not inferred from
timing.

**This round's tester notes are fully exercisable, which Build 32's were not.**
Every claim traces to a commit in `a18fe789..46d6b330` and every one is
client-side; the single server dependency they lean on,
`getProfileMediaAccess`, was already deployed on 2026-09-19 and re-read `ACTIVE`
during the phase. Nothing in the notes asks a tester to exercise a
server-disabled flow.

Still unfixed after four builds: two provisioning profiles named `YO Voice App
Store` are installed and `ios/ExportOptions.plist` selects by name. Build 33
embedded the documented one (`6a817efe-…`) again, by luck. The durable fix is to
pin the UUID.

### Android — built, not uploaded

Exit 0, `versionCode 33`, `versionName 2.0.0`, `jar verified.` exactly once,
signer fingerprint `75:3A:AC:…:AE:1E` identical to Builds 30–32, all four
foreground-service permissions and
`foregroundServiceType="microphone|mediaPlayback|mediaProjection"` present, ABIs
`arm64-v8a` / `armeabi-v7a` / `x86_64`. The AAB is 127 991 091 B, sha256
`a24d8bf0…b92b`, distinct from Build 32's `147a8c60…948a` as the 30 changed Dart
files require. Staged to `yovoice-evidence/2026-09-19/build33/app-release-33.aab`
and independently re-verified there with its own `jarsigner -verify` and
`keytool -printcert`.

Because zero files under `android/` changed since the Build 32 tree, the decoded
manifest had to differ in `versionCode` alone — and it differs by exactly that
one line, which is the strongest control available without `bundletool`. The
same `aapt2`/`bundletool` unavailability as Builds 31 and 32 forced the local
protobuf decoder again; it was re-validated on the retained build-31 and
build-32 bundles (reporting 31 and 32) before being trusted for 33.

**The upload keystore needed staging, and that is recorded because it is a
security action.** `android/app/yovoice-upload-keystore.jks` is git-ignored, so
`git worktree add` did not carry it over and Gradle throws outright without it.
It was copied read-only from the main checkout with `install -m 600`, verified
identical by `cmp` and sha256, used, and **removed 9 minutes later**; a `find`
over the worktree afterwards shows no `.jks` or `.keystore` anywhere. The key's
contents were never read, printed or logged — only size, mode and hash appear in
any log. The keystore password was never read either:
`YOVOICE_UPLOAD_KEY_PASSWORD` was unset, so Gradle took it from the macOS
Keychain.

## What this round did not do, and must not be read as having done

- **No Play action.** No upload, no Play Developer API call, no console step.
  The Play **internal** track still shows `Najnowsza wersja: 32 (2.0.0)`,
  published 2026-09-19 08:35 CEST by the Build 32 round.
- **No backend deploy of any kind** — no functions, rules, indexes or Storage.
  The Build 32 backend deployed at 02:19–02:23Z remains live and was not
  re-verified beyond a single read of `getProfileMediaAccess`.
- **No kill-switch flip.** `appConfig/accountDeletion` is still absent (HTTP 404
  `NOT_FOUND`, re-read during the iOS phase).
- **No commit, push or PR** by the release agents. `origin/main` is `46d6b330`;
  the main checkout's local commits belong to the redesign session and were left
  exactly as found.
- **No device or simulator run of build 33**, and no tester feedback on it yet.
  The avatar, banner and large-text fixes are backed by tests, CI and the
  2026-09-18 rendered-frame audit that motivated them — not by a report against
  this binary.

## Platform skew a human should expect

**Web is on build 33. iOS testers get build 33. Play internal testers are on
build 32.** That is this round's intended order, not a defect. It closes when
someone uploads `app-release-33.aab` and hands over the opt-in link, which
Google does not e-mail.

## Decisions and actions a human still owes

1. **Upload `app-release-33.aab` to the Play internal track**, confirm Play
   parses it as App bundle 33 (2.0.0), API 24+, target 36, and **verify the
   upload-key fingerprint Play reports equals
   `75:3A:AC:CB:B2:8E:65:0B:54:A5:EB:F0:F2:A6:CB:AA:23:3C:5E:B0:EF:00:FB:37:90:83:8E:6E:44:51:AE:1E`
   before promoting. If Play shows anything else, stop.** Then hand testers the
   opt-in link.
2. **Bump `pubspec.yaml` to `2.0.0+34`** before any further store build — build
   number 33 is consumed on Apple and can never be re-uploaded.
3. **Pin the provisioning-profile UUID** in `ios/ExportOptions.plist`, or remove
   the duplicate `1a59a340-…`. Outstanding since Build 30; four builds have now
   run on luck.
4. **`YOVOICE_DELETED_ACCOUNT_DIGEST_SALT` is still the step-4 gap.** The Build
   32 session record said it would move to a Firebase secret in Build 33 — that
   did not happen, because Build 33 changed **no** `functions/` file at all. It
   must be provisioned, and the three account-deletion exports redeployed,
   before anyone writes `appConfig/accountDeletion.enabled = true`.
5. **Do not flip the deletion kill switch because these binaries exist.** The
   gate is iOS *and* Android live in the stores, and Android 33 is not in Play.
6. **Remove the build worktree** `/private/tmp/yovoice-b33-build` when the round
   is closed — and only then, since it is the provenance record for all three
   artifacts.

Two items the Build 32 round left open are now **closed**, by read-back rather
than assumption: build 32's TestFlight notes no longer ask testers to delete an
account (the corrected 612-character `en-US` text reads back live and says the
server-side processing "switches on in the coming days"), and the build-32 web
deploy and Play upload, both outstanding when that record was drafted, were
completed on 2026-09-19.

## Verification run while writing this record

Read-only. No product behaviour was changed, nothing was deployed, committed or
published, and no credential was entered.

| Check | Result |
| --- | --- |
| `app.yovoice.app/version.json`, `yovoice-ec54a.web.app/version.json` | HTTP 200, `build_number "33"` on both |
| served `main.dart.js` sha256 | `5185fad54c05c43f5d304c8543b9f83befaecd0229ae5b78065663e5e00e9847` — equal to the built artifact |
| Hosting releases (newest first) | `ce6c614150a7e8d9` @ `07:34:38.852Z` `"2.0.0+33 / main 46d6b330"`, then `700501f5…` (32), `d8c5da06…` (31), `64101cb5…` (30) — **no later release**, so CI created none |
| `gh run list --commit 46d6b330…` | 3 runs, all `completed success`: CodeQL, Flutter web browser smoke, Deploy YO Voice to Firebase Hosting (28 m 16 s) |
| `firebase-hosting-merge.yml` deploy gate | `if: github.event_name == 'workflow_dispatch' && inputs.deploy_hosting` at lines 163 and 171–172 — a push cannot deploy |
| `GET /v1/builds/b90ddee4-…` | `version 33`, `processingState VALID`, `expired false` |
| `GET …/buildBetaDetail` | `internalBuildState IN_BETA_TESTING`, `externalBuildState IN_BETA_TESTING`, `autoNotifyEnabled true` |
| `GET …/betaAppReviewSubmission` | `betaReviewState APPROVED` |
| internal group `a6c2c254-…` / external `910d0a45-…` | 26 / 16 builds, both with tail `30, 31, 32, 33` |
| `GET /v1/betaBuildLocalizations/a13858b1-…` (build 32's notes) | 612 chars `en-US`, corrected text — no longer asks testers to delete an account |
| staged `build33/app-release-33.aab` | 127 991 091 B, sha256 `a24d8bf099c9e28722440362c68b13878ae5a7eb0b8ed9d7a4ade9bf1ae3b92b` |
| staged `build33/yo_voice-33.ipa` | 79 182 553 B, sha256 `33d2caec56d27d08fdf9367c868f4bdf81aebf15f69e5bbe0709f1bba93e46d7` |
| `git diff --name-only a18fe789..46d6b330` per area | `lib/` 30, `test/` 29, `docs/` 8, `pubspec.yaml` 1, `functions/` **0**, `firestore.rules` **0**, `firestore.indexes.json` **0**, `storage.rules` **0**, `android/` **0**, `ios/` **0** |
| build worktree `/private/tmp/yovoice-b33-build` | `HEAD 46d6b330…`, `git status --porcelain` 0 lines |

One correction to the release-engineering record, made here rather than left to
be repeated: its §I.11 says "Play still serves build 31". It does not — build 32
was published to the Play internal track at 08:35 CEST on 2026-09-19, before
that record was written (`build32-play/play-readback.md`). Its §I.13 item 1 also
says build 32's tester notes still ask testers to delete their account; the live
read-back above shows they were corrected at 08:27 CEST. Everything else in that
record was checked against the logs and held.

## Evidence

- Round: `yovoice-evidence/2026-09-19/build33-2026-09-19.md` (web, Android,
  iOS) and `build33-worktree.md` (worktree preparation), with the `build33-*`
  logs, `.sha256` files and `build33-asc-*.json` beside them.
- Artifacts, staged and hash-verified:
  `yovoice-evidence/2026-09-19/build33/app-release-33.aab` and
  `yovoice-evidence/2026-09-19/build33/yo_voice-33.ipa`.
- Play state carried over from the previous round:
  `yovoice-evidence/2026-09-19/build32-play/play-readback.md`.
- Full commands, gates and read-backs:
  [DEPLOYMENT.md](../DEPLOYMENT.md#build-33-release-round--web-deployed-ios-with-testers-play-upload-outstanding-2026-09-19).
- The round's findings and what is still UNVERIFIED on a device:
  [Bugs.md](../Bugs.md). The grant contract change:
  [ADR-208](../Decisions.md#adr-208-a-profile-media-grant-is-judged-by-plausibility-and-cached-by-the-device-clock).
