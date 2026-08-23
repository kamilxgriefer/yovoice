# Continuous quality, security and release automation

YO Voice uses an event-driven CI/DevSecOps pipeline rather than relying on
manual checks performed on one developer machine. In this document,
**continuous** means that the relevant checks start automatically on every
source change and on scheduled security/dependency scans; it does not mean a
process polls the repository every second.

## Automation map

| Automation | Trigger | What it proves |
|---|---|---|
| Core verification and release build | Every push to `main`, every pull request to `main`, and manual dispatch | Flutter dependencies resolve, `flutter analyze` is clean, the full Flutter suite passes, Firestore/Storage/cross-service rules pass against Firebase emulators, Cloud Functions tests and binding smoke tests pass, production Node dependencies pass the configured audit threshold, and a release Flutter web artifact builds. |
| Compiled-web Playwright smoke | Every push to `main`, every pull request to `main`, and manual dispatch | The exact release web artifact starts in Chromium, replaces the bootstrap screen, exposes the expected production metadata and avoids horizontal overflow at a phone viewport. |
| CodeQL static application security testing | Pushes and pull requests affecting the repository, a weekly schedule, and manual dispatch | JavaScript and TypeScript in the production Functions/web surfaces is analysed with GitHub's `security-extended` query suite. Dart is not presented as covered by CodeQL; it is checked by Flutter Analyzer and the Flutter test suite. |
| Dependabot | Weekly | Flutter/Dart packages, Cloud Functions packages, Firebase rules-test packages, Playwright packages and GitHub Actions are checked for maintainable version updates. |
| Production Hosting release | Explicit manual dispatch after verification | The same verified revision is rebuilt, packaged and deployed through the protected `production` environment. A normal push never publishes production Hosting by itself. Firestore rules, indexes, Storage rules and Cloud Functions remain deliberate manual releases. |

## Failure evidence

The pipeline is designed to leave useful evidence rather than only a red icon:

- Flutter, emulator and Functions failures retain their complete GitHub Actions
  logs;
- Playwright failures retain an HTML report, trace, screenshot and video;
- CodeQL findings appear in GitHub code-scanning alerts with the affected path
  and data flow;
- Dependabot opens reviewable dependency pull requests instead of modifying the
  default branch silently.

The Playwright layer intentionally has zero retries. A first-attempt failure is
reported as a failure instead of being hidden by a lucky second run.

## Security and release boundaries

Automation is not treated as proof of things it cannot observe:

- Firebase emulators do not enforce production composite indexes;
- a browser smoke test does not prove every signed-in journey or visual state;
- CodeQL scans the JavaScript/TypeScript surfaces, not Dart or Firebase Rules;
- a successful build does not prove a production deployment happened;
- backend and Rules releases stay manual because an authorization mistake has a
  larger blast radius than a reversible web presentation error.

These limits are documented so a green dashboard is read as evidence for the
checks actually performed, not as a magical certificate that the entire product
is bug-free.

## Local commands

Core application and backend verification is documented in
[`TESTING.md`](TESTING.md). The browser layer has its own isolated package and
instructions in [`browser-tests/README.md`](../browser-tests/README.md).

Common commands include:

```bash
flutter analyze
flutter test
npm --prefix firestore-tests test
npm --prefix functions test
npm --prefix browser-tests test
```

## Portfolio / CV evidence

The workflows, test files, pinned action revisions and dependency-update policy
are committed to this public repository, so the claim can be verified rather
than existing only as a CV sentence.

A concise English CV description:

> Designed and maintained a CI/DevSecOps pipeline for a Flutter/Firebase
> voice-first social platform using GitHub Actions, Flutter Analyzer, more than
> one thousand automated Flutter tests, emulator-backed Firestore and Storage
> authorization tests, Cloud Functions tests, Playwright browser smoke tests,
> CodeQL SAST, dependency auditing, Dependabot and gated production release
> artifacts.

A concise Polish description:

> Zaprojektowałem i utrzymywałem pipeline CI/DevSecOps dla platformy społecznościowej
> Flutter/Firebase, obejmujący GitHub Actions, analizę statyczną Dart, ponad tysiąc
> testów Flutter, testy reguł Firestore i Storage na emulatorach, testy Cloud
> Functions, testy przeglądarkowe Playwright, CodeQL, audyt zależności,
> Dependabot oraz kontrolowany proces wydania produkcyjnego.

When suite counts change, use the measured figures in
[`TESTING.md`](TESTING.md) rather than copying an old number from this page.

## Validating automation changes

Product work in this solo repository lands directly on `main` — there is no
pull-request step and agents must not introduce one
([ADR-108](Decisions.md#adr-108-main-is-unprotected-again--a-solo-repository-pays-the-pull-request-tax-for-a-review-that-never-happens)).

A change to `.github/workflows` is the one case where a pull request would buy
something a direct push cannot: it is the only way to exercise the
`pull_request` trigger itself. **Prefer `workflow_dispatch`** — all three
quality workflows declare it, so a manual run proves the job, its permissions
and its steps without a branch. Open a pull request for this only if the
maintainer asks for one; the `pull_request` trigger is exercised continuously
by Dependabot's own pull requests in any case. When one is used deliberately,
it proves the trigger, read-only token permissions and that all three
independent quality workflows behave as documented;
a successful push run cannot validate a PR-only execution path.
