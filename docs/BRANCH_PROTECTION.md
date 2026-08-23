# `main` is not protected, and that is the decision

**Current policy: commit and push straight to `main`. No feature branch, no
pull request.** If you are an agent reading this to decide how to deliver a
change, stop here — you already have your answer. Do not open a pull request
unless the maintainer asks for one in that session.

This file used to describe the opposite. It was replaced on 2026-08-22, and
the reasoning is in
[ADR-108](Decisions.md#adr-108-main-is-unprotected-again--a-solo-repository-pays-the-pull-request-tax-for-a-review-that-never-happens).

## What is enforced on the default branch

Nothing. There is no repository ruleset and no classic branch protection:

```bash
gh api repos/kamilxgriefer/yovoice/rulesets            # -> []
gh api repos/kamilxgriefer/yovoice/branches/main/protection   # -> 404 Branch not protected
```

The ruleset that used to live here (`Protect main`, id `21232425`, created
2026-08-23) was deleted, along with the `.github/rulesets/main-protection.json`
recipe that would have let a future session re-import it. **Removing the recipe
was deliberate**: a versioned "how to restore protection" file is exactly what
gets re-applied by an agent trying to be helpful.

## What is still enforced, and it is not nothing

CI did not go anywhere. Every push to `main` still runs, automatically:

| Check | Workflow |
|---|---|
| `verify_and_build` | `.github/workflows/firebase-hosting-merge.yml` |
| `Playwright against release web build` | `.github/workflows/browser-smoke.yml` |
| `CodeQL` / `Analyze JavaScript and TypeScript` | `.github/workflows/codeql.yml` |

All three declare both `push: branches: [main]` and `pull_request:`, so they
run on a direct push and on a Dependabot pull request alike. Dependabot keeps
opening dependency pull requests — that is dependency monitoring, not a review
gate on the maintainer's own work, and it stays.

**The difference is when the signal arrives, not whether it arrives.** Under
the pull-request workflow CI ran *before* `main` moved. Now it runs *after*.
That is a real trade and the mitigation is the local gate below, which must be
green before you push — not after.

## The local gate replaces the merge gate

Run these before pushing. They are the same checks CI runs, so a green local
run means a green `main`:

```bash
flutter analyze
flutter test
firebase emulators:exec --only auth,firestore --project demo-yovoice 'npm --prefix functions test'
```

For a change touching `firestore.rules`, `storage.rules` or indexes, also run
the rules suites — see [TESTING.md](TESTING.md). For a UI change, look at the
screen; a green suite is not visual proof (see the standing rule in
`CLAUDE.md`).

**Do not push on a failed local run**, and do not force-push `main`. Nothing on
the server will stop you now; that is the point of the trade.

Before a change big enough to be risky — a schema change, a rules rewrite, a
large refactor — take a local tag or branch snapshot of `main` first. That is
the safety net the pull request used to provide, at the cost of one command.

## Release boundary

Unchanged, and unaffected by any of this. Production Hosting is **never**
published by an ordinary push. The deploy job is gated on
`github.event_name == 'workflow_dispatch' && inputs.deploy_hosting`
(`.github/workflows/firebase-hosting-merge.yml`), so shipping to production
remains a deliberate manual dispatch. Firestore rules, indexes, Storage rules
and Cloud Functions are deployed by hand — see [DEPLOYMENT.md](DEPLOYMENT.md).

## If a second contributor ever joins

Reinstate protection that day. [CONTRIBUTING.md](CONTRIBUTING.md) already says
so and names it as the first thing that should change. The policy here is
contingent on the repository having exactly one author, not on protection being
a bad idea.
