# Build 32 release round — backend deployed, iOS to testers, web and Play left standing — 2026-09-19

## Status

**Three surfaces moved and two did not. Each claim below carries its own level
of proof; read the level before repeating the claim.**

- **Deployed and read back.** Two Firestore composite indexes, `firestore.rules`
  and **nine named Cloud Functions**, from `main` `a18fe789`, between
  `01:35:31Z` and `02:23:43Z`. Every function read back ACTIVE with an
  `updateTime` after the start, the five callables answer 401, exactly nine of
  245 functions carry a post-start `updateTime`, and the `severity>=ERROR`
  window is empty.
- **Released to testers, on one platform.** iOS build 32 is `VALID` on App Store
  Connect, `betaReviewState APPROVED`, in the internal *and* external beta
  groups, `autoNotifyEnabled true`. Apple notifies the testers; nothing else is
  needed for iOS.
- **Built, verified, and deliberately not shipped.** The Android App Bundle
  (versionCode 32, upload-key signature identical to Builds 30 and 31) exists as
  a file; no Play Console action was taken. The web bundle is complete and
  content-verified in `build/web`; Hosting was not deployed and `live` still
  serves build 31.
- **Still switched off, on purpose.** `appConfig/accountDeletion` does not exist,
  so self-service deletion is fail-closed everywhere. That is the intended
  rollout order, not a regression.
- **Verified by automated suites and API read-backs only.** Nobody ran build 32
  on a device or in a simulator during this round. No screenshot, no tester
  report, no observed deletion.

Nothing here claims a Play release, a Hosting release, a device run or a working
end-to-end deletion, because none of those happened.

## What Build 32 is

`main` `a18fe7898246604c6a5bb64b0a5be0d874dcc828`, `pubspec.yaml` `2.0.0+32`,
thirteen commits over the Build 31 tree `98f9413c`. All three GitHub Actions
workflows are green on that revision
(`yovoice-evidence/2026-09-18/b32/ci-a18fe789.txt`).

The seven commits of the account-deletion and invites slice
(`git log 7efbc5e0..a18fe789`):

| Commit | What |
| --- | --- |
| `7efbc5e0` | the staged, leased deletion pipeline in `functions/account/` |
| `f974a865` | Settings → Delete account, with the retained set stated on screen |
| `6e41c7bd` | a member may invite to a Server anyone may already join |
| `d7930d8e` | ADR-206 (deletion) and ADR-207 (invite widening) |
| `6793809c` | `2.0.0+32` |
| `f2c5cbcc` | profile media answers a block as "no media", not `failed-precondition` |
| `bffa8db6` | hide message-less threads other people opened; order Chats by last message |

Plus, from the six commits before `7efbc5e0`, the three client fixes that landed
after build 31 was cut and that build 31's testers were asked to re-test without:
`a629fd99` (media long-press reactions), `23b35885` (LiveKit participant name /
privacy), `87fc8632` (composer keyboard dismissal). That gap, recorded in the
Build 31 roadmap entry, is closed by this build.

## The backend round (primary session, 01:35Z–02:23Z)

From a clean detached worktree at `a18fe789`, `npm ci --omit=dev`,
`functions/.env*` checksums unchanged, under Application Default Credentials —
`firebase login:list` reports no authorized accounts, and no password, secret or
2FA prompt occurred at any point.

Order was **indexes → rules → functions**, which is the order the enablement
runbook requires.

- **Indexes.** The first attempt died on a transient
  `firebaserules.googleapis.com/…:test` request failure and applied nothing; the
  retry succeeded. The read-back lists 47 composite indexes, **all `READY`**,
  including both new `accountDeletionOutbox` composites —
  `(status, leaseUntil)` and `(status, nextAttemptAt)`.
- **Rules.** Released; the live release read back as ruleset
  `7c57cc65-d286-4a0e-a99f-922472c8f95e`, `updateTime 2026-09-19T02:19:26Z`. The
  Storage release still points at the 2026-09-14 ruleset, which is the positive
  proof that `storage:rules` was not deployed.
- **Functions.** Three created (`deleteAccountSelfV1`,
  `onAccountDeletionOutboxCreated`, `processAccountDeletionOutboxSchedule`) and
  six updated (`onAuthUserDeleted` — gen1 — `createServerInviteV1`,
  `revokeServerInviteV1`, `respondToServerInviteV1`, `onServerInviteWritten`,
  `getProfileMediaAccess`), `updateTime` `02:22:43Z`–`02:23:24Z`.
- **`--force` was needed for exactly one reason:**
  `onAccountDeletionOutboxCreated` declares `retry: true`, so the deploy
  introduces a failure policy and the CLI refuses non-interactively. Proven both
  ways by dry run before anything was deployed. With `--only` scoped to nine
  names, `--force` cannot widen the blast radius.

**A twelve-minute window of logged failures, and why it was harmless.** Between
about 02:23Z and 02:35Z — after the functions deploy, while the two composites
were still building — `processAccountDeletionOutboxSchedule` logged
`FAILED_PRECONDITION` on every two-minute tick. The queue was empty and the
feature is switched off, so no user was affected. The four ticks after the
indexes went `READY` are all HTTP 200, and the error window since is empty. It
is still worth naming: had real rows existed, that is precisely the sweep outage
the index step exists to prevent.

Full command, tables and read-backs:
[DEPLOYMENT.md](../DEPLOYMENT.md#build-32-release-round--backend-deployed-ios-web-and-play-with-testers-2026-09-19).

## The client round

### iOS — done

Built at `a18fe789` on the first attempt (8 m 48 s), uploaded with
`xcrun altool`, `VALID` nine minutes later, attached to the external group
(HTTP 204), submitted for beta review (HTTP 201) and returned `APPROVED`. Tester
notes were PATCHed **before** the review submission, because Apple requires them
on an external submission.

The part worth keeping: **provenance is clean for the first time in three
rounds.** `HEAD` was `a18fe789` and the tree clean at build start and still so
after every TestFlight write; the IPA hash has not changed since it was written;
the staged copy matches; and the byte count Apple acknowledged equals the file's
size. The uploaded binary is provably what `a18fe789` produces — measured, not
inferred from timing.

Still unfixed after three builds: two provisioning profiles named
`YO Voice App Store` are installed and `ios/ExportOptions.plist` selects by
name. Build 32 embedded the documented one again, by luck.

### Android — built, not uploaded

Exit 0, `versionCode 32`, `jar verified.`, signer fingerprint identical to
Builds 30 and 31, all four foreground-service permissions and
`foregroundServiceType="microphone|mediaPlayback|mediaProjection"` present.
Because zero files under `android/` changed since the Build 31 tree, the decoded
manifest had to differ from Build 31's in `versionCode` alone — and it differs
by exactly that one line, which is the strongest control available without
`bundletool`. The local protobuf decoder was validated on the retained build-30
and build-31 bundles before being trusted for 32.

### Web — built and verified, not deployed

The stale-artifact trap fired again. `firebase.json` sets
`"public": "build/web"`, and the tree already there was the genuine build-31
bundle — harmless, but deploying it would have been a no-op release labelled 32.
It was moved aside to `build/web.stale-b31-1789794710` and **must not be
restored and deployed**.

The runbook build then completed (`✓ Built build/web`, exit 0,
`05:12:06Z → 05:16:36Z`). Verified by content while this record was written:
`version.json` says `build_number "32"`, `main.dart.js` is sha256
`224854be…d5f8d` (11 394 969 B, distinct from the live build-31 file), the VAPID
key occurs once, 112 files. The release-engineering record's §W.2/§W.9 say the
compile had not finished and the directory was "absent or partial"; the log and
the tree say otherwise, and the tree is the ground truth.

So the only thing missing on web is the deploy itself. Note that a push to
`main` never performs one: the Hosting workflow's deploy job is gated on
`workflow_dispatch` with `deploy_hosting: true`, so the green
"Deploy YO Voice to Firebase Hosting" run on `a18fe789` proves the build and the
suites, not a release.

## What this round did not do, and must not be read as having done

- **No Play action.** No upload, no Play Developer API call, no console step.
- **No Hosting deploy.** `live` is still `d8c5da0668b90a18`
  (`2.0.0+31 / main 98f9413c`); both hosts serve `build_number 31`, re-read on
  2026-09-19.
- **No kill-switch flip.** `appConfig/accountDeletion` is still absent (HTTP 404,
  re-read 2026-09-19).
- **No commit, push or PR.** `HEAD` is `a18fe789` and the tree was clean
  throughout; the documentation changes from this round are left uncommitted for
  the primary session.
- **No device or simulator run**, and no tester feedback yet.

## Two things a human owes a decision on

1. **The tester notes promise a deletion the server refuses.** The stored "What
   to Test" text asks testers to exercise `Settings → Delete account` and says
   the request "is processed within a few minutes". With the kill switch off
   that is not true — the screen degrades to the e-mail route. Either accept it
   for this round or `PATCH` the localization; no rebuild is involved. Recorded
   in [Bugs.md](../Bugs.md).
2. **`YOVOICE_DELETED_ACCOUNT_DIGEST_SALT` is still unset.** Absent from
   `functions/.env` and from all three deployed account-deletion exports' runtime
   environment. A `.env` value is baked in at deploy time, so setting it means an
   edit *and* a redeploy of those exports — and it must happen before
   `appConfig/accountDeletion.enabled = true`, or deleting a banned account
   silently resets the ban.

## Verification run while writing this record

Read-only. No product behaviour was changed.

| Check | Result |
| --- | --- |
| `git status --porcelain` / `git rev-parse HEAD` | clean / `a18fe789` |
| `functions`: `node --test test/servers_contract.test.js test/servers_convergence_contract.test.js` | **11/11 pass**, 0 fail |
| `app.yovoice.app/version.json`, `yovoice-ec54a.web.app/version.json` | HTTP 200, `build_number "31"` on both |
| served `main.dart.js` sha256 | `2bf0914f…0f7db2` — still build 31 |
| `build/web` content | `build_number "32"`, `main.dart.js` `224854be…d5f8d`, VAPID ×1, 112 files |
| `GET appConfig/accountDeletion` | HTTP 404 NOT_FOUND |
| Firestore / Storage rules releases | `7c57cc65-…` @ `02:19:26Z` / `6765c5fd-…` @ `2026-09-14T06:08:23Z` |
| nine deploy read-backs re-parsed | 9 ACTIVE, `updateTime` `02:22:43Z`–`02:23:24Z` |
| `deploy-functions-list-POST.json` re-counted | 245 functions, exactly 9 with a post-start `updateTime` |
| `deploy-indexes-readback.json` re-parsed | 47 composites, 47 `READY` |

## Evidence

- Backend: `yovoice-evidence/2026-09-18/b32/deploy-backend.md`,
  `deploy-*.log`, `deploy-readback-*.json`, `deploy-functions-list-POST.json`,
  `deploy-indexes-readback.json`, `ci-a18fe789.txt`, `gate-4.md`.
- Clients: `yovoice-evidence/2026-09-19/build32-2026-09-19.md` and the
  `build32-*` logs; artifacts staged at
  `yovoice-evidence/2026-09-19/build32/app-release-32.aab` and
  `yo_voice-32.ipa`.

**Completion (added by the primary session, ~08:40 CEST):** Hosting was deployed afterwards (both hosts serve build 32, `main.dart.js` `224854be…`) and the AAB was published to the Play internal track at 08:35 CEST (`Najnowsza wersja: 32 (2.0.0)`); TestFlight already held build 32 in both groups. Statements above about Hosting not being deployed or the AAB not being uploaded describe the state when this record was drafted. The account-deletion kill switch remains OFF (salt not yet provisioned — moving to a Firebase secret in Build 33).
