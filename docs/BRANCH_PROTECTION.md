# Main branch protection

YO Voice keeps its default branch behind an importable GitHub repository
ruleset. The canonical recipe is:

```text
.github/rulesets/main-protection.json
```

This policy supersedes the earlier solo-project convention of pushing directly
to `main` (ADR-002). The repository remains solo-maintained, but changes now
pass through the same automated evidence before reaching the default branch.

## Enforced policy

The ruleset targets only the default branch:

- changes reach `main` through a pull request;
- only squash merge is allowed;
- the branch must be current with `main` before merge;
- `verify_and_build`, `Playwright against release web build`, and
  `Analyze JavaScript and TypeScript` must pass;
- unresolved review conversations block merge;
- force pushes and branch deletion are blocked;
- history must remain linear.

The required approval count is intentionally zero. GitHub does not let an
author approve their own pull request, so requiring one approval in a
single-maintainer repository would deadlock every change without adding an
independent reviewer. The full Flutter/Firebase verification, compiled-browser
smoke test, CodeQL analysis and resolved conversations remain mandatory.

Verified signatures remain visible in GitHub but are not a merge requirement.
Requiring signed commits can prevent the maintainer from squash-merging a pull
request authored by an automation account such as Dependabot, which would make
the dependency-update workflow needlessly brittle.

## Applying or restoring the ruleset

Repository administration is performed in GitHub:

1. Open **Settings → Rules → Rulesets**.
2. Choose **New ruleset → Import a ruleset**.
3. Import `.github/rulesets/main-protection.json`.
4. Confirm the target is the default branch and enforcement is **Active**.
5. Create the ruleset.

The committed JSON documents the intended policy and makes it reproducible,
but GitHub repository settings are the actual enforcement authority. After an
import, verify that the repository no longer reports `main` as unprotected.

## Release boundary

Branch protection does not publish production. A pull request and ordinary
push run verification only. Firebase Hosting still requires the existing
explicit manual dispatch with `deploy_hosting: true`; Firestore Rules, indexes,
Storage Rules and Cloud Functions remain deliberate manual deployments.

## Changing CI names

Required status checks are matched by their exact job names. If a workflow job
is renamed, update the ruleset file and the active GitHub ruleset together in
the same maintenance change.
