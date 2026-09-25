# Store release workflow (GitHub Actions)

`.github/workflows/store-release.yml` builds YO Voice for the stores from one
commit on `main`. It signs the build and uploads it:

- **Android** goes to the Google Play **internal testing** track as a draft, or
  as a completed release if you choose that.
- **iOS** goes to App Store Connect / TestFlight. The workflow waits until
  Apple's processing reports `VALID`.

It replaces the manual Mac build and upload rounds recorded in
[DEPLOYMENT.md](DEPLOYMENT.md). The alternative is still valid: Kamil can keep
building on the Mac. Decision record: [Decisions.md](Decisions.md), "Store
builds come from a manually dispatched, reviewer-gated workflow".

> **Status: source only. The workflow has never run.** It becomes usable only
> after it is on `main` and the one-time setup below is done. That setup is
> Kamil's work in GitHub, Google Cloud, Play Console, App Store Connect and
> Keychain Access. Nothing here was dispatched, and no secret exists yet.

## What it does and what it does not do

| Does | Does not |
| --- | --- |
| Refuses to start unless `ref` is on `main`, matches `pubspec.yaml`, and is green in CI | Deploy Hosting, Functions, rules or indexes |
| Builds with Flutter 3.44.6. Android builds on `ubuntu-24.04`; iOS builds on `macos-26` with Xcode 26.6 | Pass any `--dart-define` (mobile defaults are correct; GIPHY must stay out, see DEPLOYMENT.md) |
| Signs Android with the upload key and iOS with the Apple Distribution certificate and the `YO Voice App Store` profile, pinned by UUID | Upload any artifact. The repository is public, so hashes go to the job summary instead |
| Uploads the AAB to the Play **internal** track, as `draft` or `completed` | Touch production or any other Play track |
| Uploads the IPA once with `altool` and polls App Store Connect until `VALID` | Attach the build to the external TestFlight group, write "What to Test" or submit for beta review |
| Tags the released commit `store-build-<N>` | Hand testers the Play opt-in link, or e-mail anyone |
| Offers a **dry run** (the default) that builds with no secret at all and uploads nothing (a runner-only Gradle init script also switches off the Crashlytics mapping-file upload) | Retry an upload |

## How one release flows

1. **Backend first, by hand, only when it changed.** Deploy indexes, then
   rules, then Functions, and read each one back, exactly as
   [DEPLOYMENT.md](DEPLOYMENT.md) orders it ("4. The app — only after 1–3 are
   read back"). The workflow cannot deploy the backend. It **refuses** a store
   release while `functions/`, `firestore.rules`, `firestore.indexes.json` or
   `storage.rules` differ from the last store release, unless you dispatch it
   with `backend_confirmed=true`.
2. **Web from the same commit.** Hosting deploys whatever `main` points at when
   `firebase-hosting-merge.yml` is dispatched. Deploy it while `main` is at the
   release commit:

   ```bash
   gh workflow run firebase-hosting-merge.yml -R kamilxgriefer/yovoice --ref main -f deploy_hosting=true
   gh run list -R kamilxgriefer/yovoice --workflow firebase-hosting-merge.yml -L 1 --json headSha,conclusion,status
   ```

   The store workflow **refuses** unless a `deploy_hosting` job succeeded on
   exactly `ref`. This keeps web and store from drifting to different SHAs.
   Set `web_confirmed=true` only if Hosting was deployed from this SHA by hand
   (`firebase deploy --only hosting`), or if you deliberately accept a skew.
3. **Dry run** (optional, recommended for the first release and after any
   workflow change):

   ```bash
   gh workflow run store-release.yml -R kamilxgriefer/yovoice --ref main \
     -f ref=<40-char SHA> -f build_number=<N> -f dry_run=true
   ```

4. **Real release.**

   ```bash
   gh workflow run store-release.yml -R kamilxgriefer/yovoice --ref main \
     -f ref=<40-char SHA> -f build_number=<N> -f dry_run=false \
     -f platforms=both -f play_release_status=draft
   ```

   Add `-f backend_confirmed=true` and/or `-f web_confirmed=true` only when
   the matching statement is true.
5. **One approval.** Preflight runs first with no secret. The Android and iOS
   jobs then both wait on the `store-release` environment, and one review
   ("Review deployments", then "Approve and deploy") releases both. Read the
   preflight summary before approving (see [Before you approve](#before-you-approve)).
6. **After the run** (manual, as in every earlier round):
   - Play Console → YO Voice → Testing → Internal testing. Check that release
     `N (X.Y.Z)` is there and that Play shows the upload-key fingerprint
     `75:3A:…:1E`. With `draft`, roll it out yourself. Hand testers the
     opt-in link, because Google does not e-mail the list.
   - TestFlight: the internal group gets the build automatically. For the
     external group, follow the "What to Test", attach and submit sequence in
     [DEPLOYMENT.md](DEPLOYMENT.md) (the Build 33 iOS record). Apple e-mails
     the external testers after the beta review.

## Inputs

Every input reaches the scripts through `env:`. None is interpolated into a
`run:` script (`tool/test/release_workflow.test.mjs` enforces this).

| Input | Default | Meaning |
| --- | --- | --- |
| `ref` | (required) | Full 40-character lowercase SHA of a commit already on `main` |
| `build_number` | (required) | Must equal the `+N` in `pubspec.yaml` at `ref`; build names are read from the pubspec |
| `platforms` | `both` | `both`, `android` or `ios` |
| `dry_run` | `true` | `true`: throwaway key or `--no-codesign`, no secret, no upload (not even the Crashlytics mapping file) |
| `play_release_status` | `draft` | `draft` (uploaded, not rolled out) or `completed` (rolled out to internal testers) |
| `backend_confirmed` | `false` | You deployed and read back the backend changes since the last store release |
| `web_confirmed` | `false` | Hosting was deployed from this SHA outside `deploy_hosting`, or the skew is deliberate |
| `since_ref` | empty | Override for the backend baseline; empty means the newest `store-build-<M>` tag with `M < N` |

## The gates

### Preflight (no secret, read-only token)

Hard failures in both modes:

- an input with the wrong shape;
- a real run dispatched from a branch other than `main`;
- `ref` not on `main`;
- `build_number` not equal to the pubspec `+N`;
- the Gradle configuration cache switched on at `ref`. It would serialise the
  upload-key password into the build tree.

Release-order gates. These are hard failures on a real run and warnings on a
dry run:

- **CI green on exactly `ref`:** the newest `verify_and_build` and
  `Playwright against release web build` check runs, created by GitHub
  Actions, concluded `success`. Only check runs from a workflow run on `main`
  started by a `push` or a `workflow_dispatch` on exactly `ref` count.
  Preflight reads the workflow runs for `ref` (`actions: read`) and keeps only
  those check suites. Both CI workflows also run on `pull_request`, which
  attaches check runs to the PR head SHA but tests `refs/pull/N/merge`, so a
  pull-request run can never turn a red push result green. Only the head SHA
  of a push gets runs. A run cancelled by a newer push (both workflows cancel
  in progress per ref) never turns green, so release the newer SHA.
- **Backend:** no change under the four backend paths since the baseline, or
  `backend_confirmed=true`. A missing baseline refuses (fail closed). An empty
  baseline would make the diff compare nothing and pass silently.
- **Web:** a successful `deploy_hosting` job on exactly `ref`, in a
  `workflow_dispatch` run on `main`, or `web_confirmed=true`.
- **Build number:** no `store-build-<N>` tag on a different commit.

Preflight also runs the tooling's own unit tests (`node --test
tool/test/release_*.test.mjs`) and writes a summary for the approver.

### Android, before upload

- exactly one `.aab`;
- `jarsigner -verify` prints `jar verified.`;
- the signer's SHA-256 equals the upload certificate Play has registered,
  `75:3A:AC:CB:B2:8E:65:0B:54:A5:EB:F0:F2:A6:CB:AA:23:3C:5E:B0:EF:00:FB:37:90:83:8E:6E:44:51:AE:1E`;
- the bundle's own protobuf manifest says `app.yovoice`, `versionCode N` and
  `versionName X.Y.Z` (`tool/release/aab_manifest.mjs`, checked against the
  retained bundles 33 and 34).

Then `tool/release/play.mjs` runs:

1. `edits.insert`, then `bundles.list`. It refuses if `N` is already in Play.
2. One `bundles.upload`. Play's reply must carry `N` and the local SHA-256.
3. `tracks.update` on `internal`.
4. `edits.commit`. It commits once more with `changesNotSentForReview=true`
   only if Play says so.
5. Read-back in a fresh edit.

Any failure before the commit deletes the edit.

### iOS, before upload

- Xcode 26.6 is selected and asserted.
- CocoaPods is 1.17.0 (`ios/Podfile.lock`).
- The profile secret is the `YO Voice App Store` App Store profile for
  `C3R59P53KB.app.yovoice`: `aps-environment=production`,
  `get-task-allow=false`, Sign in with Apple, no device list, and more than a
  day before expiry.
- No other profile with that name is installed.
- The export options are a copy of `ios/ExportOptions.plist` with the profile
  pinned **by UUID** and `destination=export`. The repository file is not
  edited.

After the build:

- exactly one `.ipa`;
- the archive and the app both carry `CFBundleVersion N`, and the app carries
  `X.Y.Z` and `app.yovoice`;
- `codesign --verify --deep --strict` passes;
- the authority is `Apple Distribution: … (C3R59P53KB)`;
- the entitlements are `aps-environment=production` and `get-task-allow=false`;
- the embedded profile UUID equals the installed one.

Then `asc.mjs assert-build-free` runs, followed by **one** `xcrun altool
--upload-app`, never retried. Last, `asc.mjs wait-valid` polls for 45
minutes at most. `INVALID` or `FAILED` fails the job. At the deadline it
depends on whether App Store Connect ever showed the build:

- **seen at least once** (for example still `PROCESSING`): a warning only. The
  binary is with Apple and the number is consumed either way;
- **never seen**: the job **fails**. `altool` said success, but nothing proves
  the binary reached Apple, so the `record` job does not tag the commit. Check
  App Store Connect by hand (see the failure table).

### After a successful real run

The `record` job tags `ref` as `store-build-<N>`. It needs `contents: write`,
runs no repository code and holds no secret. The next preflight diffs the
backend against that tag. The tag already existing on the same commit is fine
(for example, an iOS-only run after an Android-only one). A tag on another
commit fails the job.

## One-time setup (Kamil)

Everything below happens outside the repository. Run the commands in the main
checkout on the Mac, with `gh` logged in as `kamilxgriefer`. Each command pipes
the value straight into `gh secret set`, so nothing is printed. `gh secret
set` reads stdin when it is piped, and prompts with hidden input when it is
not.

### 1. The `store-release` environment

GitHub → `kamilxgriefer/yovoice` → Settings → Environments → **New
environment** → `store-release`:

- **Required reviewers:** `kamilxgriefer`.
- **Prevent self-review:** **off**. Every run is dispatched by
  `kamilxgriefer`, whether Kamil or a session using his token dispatches it.
  With this on, nobody could approve.
- **Allow administrators to bypass configured protection rules:** **off**.
- **Deployment branches and tags:** "Selected branches and tags" → add branch
  `main`.
- **Environment secrets:** the nine below. Put them **only** here, never as
  repository secrets. A repository secret is readable by every workflow
  without review.

The same setup from the command line:

```bash
KAMIL_ID="$(gh api users/kamilxgriefer --jq .id)"
printf '{"reviewers":[{"type":"User","id":%s}],"prevent_self_review":false,"can_admins_bypass":false,"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' "$KAMIL_ID" \
  | gh api --method PUT repos/kamilxgriefer/yovoice/environments/store-release --input -
gh api --method POST repos/kamilxgriefer/yovoice/environments/store-release/deployment-branch-policies \
  -f name=main -f type=branch
gh api repos/kamilxgriefer/yovoice/environments/store-release \
  --jq '{protection_rules, deployment_branch_policy, can_admins_bypass}'
```

The dry-run jobs use no environment, so there is nothing to create for them.
If a real run starts before `store-release` exists, GitHub creates the
environment unprotected with no secrets. The run then stops at its first
secret check ("… is not set in the store-release environment"). It fails
closed, but create the environment first anyway.

While you are there: the existing `production` environment, used by the
Hosting deploy and the backfill, has **no** protection rules today. Give it
the same reviewer. DEPLOYMENT.md has asked for this since the Hosting
workflow landed.

### 2. The nine secrets

| # | Secret (exact name) | What it is | Command |
| --- | --- | --- | --- |
| 1 | `ANDROID_UPLOAD_KEYSTORE_BASE64` | The upload keystore, 4312 B, sha256 `e7f284e5…3126` | `base64 -i /Users/kamil/Documents/GitHub/yovoice/android/app/yovoice-upload-keystore.jks \| gh secret set ANDROID_UPLOAD_KEYSTORE_BASE64 --env store-release -R kamilxgriefer/yovoice` |
| 2 | `ANDROID_UPLOAD_KEY_PASSWORD` | Store **and** key password (one value; `android/app/build.gradle.kts` uses it for both) | `printf '%s' "$(security find-generic-password -a yovoice -s yovoice-upload-keystore -w)" \| gh secret set ANDROID_UPLOAD_KEY_PASSWORD --env store-release -R kamilxgriefer/yovoice` |
| 3 | `PLAY_SERVICE_ACCOUNT_JSON` | JSON key of a new, dedicated Play service account | [section 3](#3-play-service-account-secret-3) |
| 4 | `ASC_KEY_ID` | App Store Connect API key ID (10 characters) | `printf '%s' '<KEY ID>' \| gh secret set ASC_KEY_ID --env store-release -R kamilxgriefer/yovoice` |
| 5 | `ASC_ISSUER_ID` | The Issuer ID above the key list | `gh secret set ASC_ISSUER_ID --env store-release -R kamilxgriefer/yovoice` (paste at the hidden prompt) |
| 6 | `ASC_PRIVATE_KEY_P8` | The key's `.p8` file contents | `gh secret set ASC_PRIVATE_KEY_P8 --env store-release -R kamilxgriefer/yovoice < ~/.appstoreconnect/private_keys/AuthKey_<KEY ID>.p8` |
| 7 | `IOS_DIST_CERT_P12_BASE64` | "Apple Distribution: Kamil Jaguszewski (C3R59P53KB)" **with its private key**, as `.p12` | [section 5](#5-distribution-certificate-and-profile-secrets-7-9) |
| 8 | `IOS_DIST_CERT_P12_PASSWORD` | The password chosen when exporting the `.p12` | `gh secret set IOS_DIST_CERT_P12_PASSWORD --env store-release -R kamilxgriefer/yovoice` (hidden prompt) |
| 9 | `IOS_APPSTORE_PROFILE_BASE64` | Profile `YO Voice App Store`, UUID `6a817efe-d05c-443b-a10b-3f91ca381322`, expires 2027-08-15 | [section 5](#5-distribution-certificate-and-profile-secrets-7-9) |

Check before secret 1 that you are about to upload the right file:
`shasum -a 256 /Users/kamil/Documents/GitHub/yovoice/android/app/yovoice-upload-keystore.jks`
must start `e7f284e5`. Afterwards list what exists (names only, never values):
`gh secret list --env store-release -R kamilxgriefer/yovoice`.

These are **not** secrets and live in the YAML: the key alias `upload`, Apple
app ID `6801898909`, team `C3R59P53KB`, bundle ID `app.yovoice` and the
upload-certificate fingerprint. The iOS keychain password is random per run.
Do **not** reuse `FIREBASE_SERVICE_ACCOUNT_YOVOICE_EC54A`. It is the Hosting
deployer and has no Play access.

### 3. Play service account (secret 3)

```bash
gcloud services enable androidpublisher.googleapis.com --project=yovoice-ec54a
gcloud iam service-accounts create yovoice-play-release \
  --display-name="YO Voice Play release (GitHub Actions)" --project=yovoice-ec54a
gcloud iam service-accounts keys create /dev/stdout \
  --iam-account=yovoice-play-release@yovoice-ec54a.iam.gserviceaccount.com \
  | gh secret set PLAY_SERVICE_ACCOUNT_JSON --env store-release -R kamilxgriefer/yovoice
```

The service account needs **no** Google Cloud IAM role. If key creation is
blocked by the organisation policy `iam.disableServiceAccountKeyCreation`,
this path does not work (UNVERIFIED whether it is enforced). The keyless
alternative is Workload Identity Federation, which needs a workflow change.

Then, in Play Console → **Users and permissions** → **Invite new users**:

- e-mail `yovoice-play-release@yovoice-ec54a.iam.gserviceaccount.com`;
- **App permissions** → YO Voice (`app.yovoice`) → **Release apps to testing
  tracks**, plus the default view access.

Do **not** grant "Release to production" or any account-level permission.
Google says a new grant can take up to about a day to apply (UNVERIFIED for
this account).

### 4. App Store Connect API key (secrets 4-6)

Reusing `BGK5YPN6V4` works: it uploaded 3.0.0, and its `.p8` is in
`~/.appstoreconnect/private_keys/` on the Mac. A dedicated key is better,
because you can revoke it without breaking the Mac path.

1. App Store Connect → Users and Access → Integrations → App Store Connect
   API → Team Keys → **+**.
2. Name it "YO Voice CI" and give it the **App Manager** role.
3. Download the `.p8`. Apple offers it **once**.
4. Run commands 4-6, then delete the download:
   `rm ~/Downloads/AuthKey_<KEY ID>.p8`.

The workflow reads builds (`GET /v1/builds`) and uploads through `altool`.
The existing key got 403 on some other reads (DEPLOYMENT.md), which this
workflow does not make.

### 5. Distribution certificate and profile (secrets 7-9)

1. Keychain Access → login → My Certificates → **Apple Distribution: Kamil
   Jaguszewski (C3R59P53KB)**. Expand it and check that the private key is
   underneath.
2. Right-click → Export → `yovoice-distribution.p12` on the Desktop, with a
   new strong password.
3. Upload it, set the password, and delete the file:

   ```bash
   base64 -i ~/Desktop/yovoice-distribution.p12 \
     | gh secret set IOS_DIST_CERT_P12_BASE64 --env store-release -R kamilxgriefer/yovoice
   gh secret set IOS_DIST_CERT_P12_PASSWORD --env store-release -R kamilxgriefer/yovoice
   rm ~/Desktop/yovoice-distribution.p12
   ```

4. Check that the profile is the documented one (**not** the duplicate
   `1a59a340-…`), then upload it:

   ```bash
   P="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/6a817efe-d05c-443b-a10b-3f91ca381322.mobileprovision"
   [ -f "$P" ] || P="$HOME/Library/MobileDevice/Provisioning Profiles/6a817efe-d05c-443b-a10b-3f91ca381322.mobileprovision"
   security cms -D -i "$P" | plutil -extract Name raw -o - -   # YO Voice App Store
   base64 -i "$P" | gh secret set IOS_APPSTORE_PROFILE_BASE64 --env store-release -R kamilxgriefer/yovoice
   ```

   If the file is in neither place, download the profile from
   developer.apple.com → Certificates, Identifiers & Profiles → Profiles.

When the profile or certificate is renewed, re-run the matching commands. The
workflow refuses a profile that expires within a day.

### 6. Baseline tag (once)

The backend gate compares against the newest `store-build-<M>` tag below the
requested build. None exists yet, so create the first one by hand, on the
commit the last store build was cut from:

```bash
git tag store-build-35 <SHA that 3.0.0+35 was built from>   # if 35 ships from the Mac
git push origin store-build-35
# or, if 35 never ships: the 3.0.0+34 commit
git tag store-build-34 f71a2ae2 && git push origin store-build-34
```

From then on the workflow tags each release itself. After any **manual** Mac
release, tag it the same way. Otherwise the gate compares against an older
baseline, which is safe but asks for `backend_confirmed` more often.

### 7. Recommended: a separate credential for sessions

Today sessions run `gh` with Kamil's classic token (scopes `repo`,
`workflow`). With that token a session can dispatch a run, **approve its own
pending deployment** through the API, and push a changed workflow to `main`.
**So the reviewer gate does not bind a session that uses Kamil's token.** To
make the approval a real control, give sessions a fine-grained personal
access token instead:

- repository: `kamilxgriefer/yovoice` only;
- **Actions: Read and write** (dispatch) and **Contents: Read and write**
  (the normal push-to-main workflow);
- **no** Workflows, Deployments, Environments, Secrets or Administration
  permission.

Such a token cannot approve a deployment or change a workflow file. Kamil
still approves in the GitHub web UI or the mobile app with his own login.
This remains an honest limit: code a session pushes to `tool/release/`,
`android/` or `ios/` runs next to the secrets. The approval is the only
barrier, which is why the preflight summary lists those changes.

## Before you approve

The approval prompt does not show a diff. Open the run's preflight summary and
check:

- **Mode** says REAL RELEASE, and the **version** and **app commit** are the
  ones you meant.
- **Commits since the baseline** has nothing you do not recognise.
- **Review before approving** shows what changed in `android/`, `ios/`, the
  pubspec, the sound generator and `tool/release/` or this workflow since the
  last release. That code runs next to the signing secrets.
- Every gate row is `success`, or carries a confirmation you actually gave.

## Security model

- **The repository is public.** Actions logs, job summaries and artifacts are
  world-readable. Therefore:
  - no artifact is uploaded, signed or not;
  - there is no `set -x`;
  - secrets are passed only to the step that uses them;
  - decoded material goes under `RUNNER_TEMP` with `umask 077` and is removed
    in `always()` steps;
  - the throwaway dry-run password and the per-run keychain password are
    masked with `::add-mask::`.
- **Script injection.** Every input goes through `env:`. Preflight also
  validates every input against a strict pattern before any output is
  written. The outputs later jobs use (`sha`, `build_name`, `build_number`)
  are therefore plain hex and digits.
- **Cache poisoning.** No job reads or writes any cache: Flutter
  `cache: false`, `package-manager-cache: false`, no `actions/cache`, no
  `setup-gradle`. Nothing a pull-request run could write reaches a signing
  job.
- **Tooling from `main`.** `tool/release/*.mjs` is checked out from the
  workflow commit. The app is checked out separately from `ref`. An older
  `ref` without the tooling still releases.
- **Least exposure inside a job.** The Android keystore and password exist
  only for the build. They are deleted, and the Gradle daemon is stopped,
  before the Play credential is written. The iOS `.p12` file is deleted right
  after import into a temporary keychain, and that keychain is deleted at the
  end.
- **App code sees the signing material.** Gradle scripts and the Xcode build
  run with the key available. That is how signing works. It is why only
  commits already on `main` can be released and why the approver reviews the
  summary.
- **If the repository ever becomes private** on a free personal plan, required
  reviewers and environment secrets stop being available. The protection
  disappears, not just the free minutes. Check the plan before changing
  visibility.

## Failure, re-run and rollback

| Situation | What to do |
| --- | --- |
| Preflight refused | Read the summary. It names the gate and the fix |
| Android failed before "committed" | Nothing reached Play, and the edit was deleted. Fix, then re-run. Whether a failed upload inside a deleted edit consumes the versionCode is UNVERIFIED; if Play later refuses `N`, bump to `N+1` |
| Android failed after "committed" | Look in Play Console. The release is probably there, and only the read-back failed |
| `altool` failed | The binary may or may not have reached Apple. Look for build `N` in App Store Connect first. A re-run is refused by `assert-build-free` once the build is visible. **Never** force a second upload ("Redundant Binary Upload") |
| Processing timed out (warning) | The build was seen in App Store Connect, so the upload succeeded. Watch TestFlight. Do not re-upload |
| Build never appeared in App Store Connect (iOS failed) | `altool` reported success but build `N` was never visible within 45 min, so nothing was tagged. Look for build `N` in App Store Connect → TestFlight and for an Apple e-mail about a processing problem. If it shows up and processes, the release happened: tag it by hand (`git tag store-build-<N> <ref> && git push origin store-build-<N>`) once every requested platform is in its store. If it never shows up, the number may still be consumed: re-cut as `N+1`. **Never** re-run the iOS job with the same `N` while you are unsure |
| One platform succeeded, the other failed | Nothing is tagged. Re-run with `platforms=` the failed one and the same `N`. The succeeded store refuses a duplicate anyway |
| Bad Android build | Internal track: roll back to the previous release, or halt it. `draft`: do not roll it out. versionCodes are never reusable, so re-cut as `N+1` |
| Bad iOS build | Remove it from the external group, or expire it (DEPLOYMENT.md, Build 33 rollback table). Re-cut as `N+1` |

Build numbers are never reusable on either store. Every re-cut is a pubspec
bump on `main`.

## Leaked or retired credentials

- **Stop the workflow:**
  `gh workflow disable store-release.yml -R kamilxgriefer/yovoice`.
- **Remove the secrets:**
  `gh secret delete <NAME> --env store-release -R kamilxgriefer/yovoice`, for
  each of the nine.
- **ASC key:** revoke it in App Store Connect → Integrations.
- **Play:**
  `gcloud iam service-accounts keys list --iam-account=yovoice-play-release@yovoice-ec54a.iam.gserviceaccount.com`,
  then `gcloud iam service-accounts keys delete <KEY_ID> --iam-account=…`, then
  remove the account in Play Console → Users and permissions.
- **Distribution certificate:** revoke it at developer.apple.com. This
  invalidates the profile, so regenerate the profile and re-set secrets 7-9.
- **Android upload key:** the most sensitive of the nine. It can only be
  replaced through a Play Console **upload-key reset** request to Google.

## What is verified and what is not

Verified in the repository:

- The YAML parses with two independent parsers.
- The unit tests pass: `node --test tool/test/release_*.test.mjs` (preflight
  against a real throwaway git repository, the Play and App Store Connect
  clients against mocked APIs, and the manifest decoder).
- The structural test holds: no `${{ }}` in any `run:`, pinned actions, no
  cache or artifact, no secret in the dry-run jobs, every secret documented
  here.
- The manifest decoder reads the retained bundles 33 and 34 correctly.
- The dry run's Gradle init script disables a task named
  `uploadCrashlyticsMappingFileRelease` and records it, while the task still
  runs without the script. Checked with Gradle 9.3.1 on a stand-in project,
  not with the real Crashlytics plugin.

**UNVERIFIED until the first runs:**

- that `macos-26` carries `/Applications/Xcode_26.6.app`;
- that CocoaPods 1.17.0 installs over the image's version;
- the first Linux Gradle release build (NDK provisioning, memory under
  `-Xmx8G` on a 16 GB runner, the Crashlytics plugin);
- that the Crashlytics plugin names its mapping upload
  `uploadCrashlyticsMappingFile<Variant>`. The dry-run summary row
  "Crashlytics mapping upload" names the tasks it switched off; a warning and
  "no upload task was configured" mean the name changed or the build is not
  minified, so check the Gradle log;
- run times: roughly 15-25 min for Android and 30-45 min for iOS plus up to
  45 min of processing, all estimates;
- that one review approves both waiting jobs, which is how GitHub documents
  it, but it has not been observed here;
- the Play API behaviour on this app: draft releases, `changesNotSentForReview`;
- the role of `BGK5YPN6V4`;
- key-creation policy in Google Cloud;
- everything that depends on the secrets.

The first dry run proves the build half. The first real run, with
`play_release_status=draft`, proves the signing and upload half. Read both
consoles back after it.
