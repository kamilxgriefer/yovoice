# `main` policy: direct pushes, protected against destructive Git

**Current policy: commit and push straight to `main`. No feature branch, no
pull request.** If you are an agent reading this to decide how to deliver a
change, stop here — you already have your answer. Do not open a pull request
unless the maintainer asks for one in that session, and do not add a
pull-request rule to the ruleset.

This file described the opposite between 2026-08-23 and 2026-08-24. The
reasoning for the reversal is in
[ADR-108](Decisions.md#adr-108-main-is-unprotected-again--a-solo-repository-pays-the-pull-request-tax-for-a-review-that-never-happens).

## Default workflow

```text
synchronize main   (git pull --ff-only origin main)
→ implement
→ verify locally
→ commit on main
→ push directly   (git push origin main)
→ GitHub Actions verify the pushed commit
→ fix any failure immediately with another direct commit
```

## Repository protections

`main` is **not** unprotected — it simply does not require a pull request. An
active ruleset named `Protect main` enforces three rules:

| Rule | Effect |
|---|---|
| `deletion` | `main` cannot be deleted |
| `non_fast_forward` | force pushes are rejected |
| `required_linear_history` | merge commits on `main` are rejected; history stays linear |

Ordinary fast-forward pushes are allowed. There is **no** `pull_request` rule
and **no** `required_status_checks` rule, which is what makes a direct push
possible. `bypass_actors` is empty on purpose: nobody, including an
administrator, is exempt from the three rules above.

Verify the live state at any time:

```bash
gh api repos/kamilxgriefer/yovoice/rules/branches/main --jq '[.[].type]'
```

## Automated verification

After each push to `main`, GitHub automatically runs:

| Check | Workflow | Covers |
|---|---|---|
| `verify_and_build` | `firebase-hosting-merge.yml` | Flutter Analyzer, the Flutter suite, Firestore/Storage/cross-service rules against the emulators, Cloud Functions tests and binding smoke tests, production Node dependency audit, and a release Flutter web build |
| `Playwright against release web build` | `browser-smoke.yml` | the compiled release artifact boots in Chromium, replaces the bootstrap screen, and avoids horizontal overflow at a phone viewport |
| `Analyze JavaScript and TypeScript` / `CodeQL` | `codeql.yml` | `security-extended` SAST over the Functions and web surfaces |

**These checks validate the revision after it is pushed. They do not block the
push, and they cannot — there is no required-status-check rule.** That is the
deliberate trade: the gate moved from the server to your terminal.

If a check fails:

- `main` is temporarily red;
- investigate immediately — do not start unrelated work on top of it;
- commit the fix and push it directly;
- never ignore, hide, or re-run-until-green a real failure.

Because nothing on the server will stop a bad push, **run the local gate
first**:

```bash
flutter analyze
flutter test
firebase emulators:exec --only auth,firestore --project demo-yovoice 'npm --prefix functions test'
```

For a change touching `firestore.rules`, `storage.rules` or indexes, also run
the rules suites — see [TESTING.md](TESTING.md). For a UI change, look at the
screen; a green suite is not visual proof.

Before a risky change — a schema change, a rules rewrite, a large refactor —
snapshot `main` with a local tag or branch first. That is the safety net the
pull request used to provide, at the cost of one command.

## Pull requests

Pull requests remain available and are **optional**. Use one when:

- the maintainer explicitly asks for one;
- an external reviewer participates;
- a risky migration genuinely deserves isolated review;
- a release or security change benefits from extra scrutiny.

Do not create one for ordinary development. Dependabot keeps opening
dependency pull requests — that is dependency monitoring, not a review gate on
the maintainer's own work, and it stays enabled.

## Deployment boundary

**A source push authorizes nothing in production.** Pushing to `main` ships
nothing to users:

- **Hosting** deploys only on `workflow_dispatch` with `deploy_hosting: true`
  (`.github/workflows/firebase-hosting-merge.yml`);
- **Cloud Functions**, **Firestore Rules**, **Firestore indexes** and
  **Storage Rules** are deployed by hand, deliberately — see
  [DEPLOYMENT.md](DEPLOYMENT.md).

This separation is what makes a briefly-red `main` an acceptable cost rather
than an outage, and it is not affected by this policy.

## GitHub Settings and the versioned file

Two things must stay synchronized:

- **[`.github/rulesets/main-protection.json`](../.github/rulesets/main-protection.json)**
  is the reproducible, reviewable statement of intended policy. It changes
  nothing by itself.
- **GitHub Settings → Rules → Rulesets → `Protect main`** is the *actual*
  enforcement authority.

Editing the JSON does not change GitHub. Apply it explicitly:

```bash
gh api -X POST repos/kamilxgriefer/yovoice/rulesets \
  --input .github/rulesets/main-protection.json
```

If the two ever disagree, the live ruleset wins in practice and the file is a
lie — reconcile them the same day.

## If a second contributor ever joins

Reinstate the pull-request requirement that day.
[CONTRIBUTING.md](CONTRIBUTING.md) already names it as the first thing that
should change. This policy is contingent on the repository having exactly one
author, not on review being a bad idea.
