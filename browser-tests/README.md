# YO Voice browser smoke tests

This directory contains Playwright smoke tests for the **compiled Flutter web
artifact**. The tests do not run against a mocked React page or a Flutter dev
preview: GitHub Actions first produces `build/web`, serves those exact files,
and then opens them in Chromium.

## What the suite verifies

- the release web artifact starts without an uncaught browser exception;
- Flutter replaces the HTML bootstrap screen with the real application;
- production metadata such as the manifest and theme colour is present;
- the app fills a 390 × 844 phone viewport without horizontal overflow.

This is deliberately a smoke layer. It proves that a release artifact boots and
that the outer responsive shell is usable; it does not claim that every
authenticated journey, Firebase permission or visual state has been exercised.
Those areas remain covered by the Flutter, Firebase emulator and Functions
suites described in [`docs/TESTING.md`](../docs/TESTING.md).

## Run locally

Build the Flutter web application first:

```bash
flutter pub get
flutter build web --release \
  --dart-define=YOVOICE_WEB_PUSH_VAPID_KEY=BGa6os6npm6shnDdNP4rbqFS8wC5brGTY0RVzt59mZvpOhX3EeaCUpOaZRw2TmQeXK5gpZ1whEKvJEhmSD0mikU \
  --dart-define=YOVOICE_APPLE_SIGN_IN_ENABLED=true
```

Install the pinned test dependencies and Chromium:

```bash
npm --prefix browser-tests ci
npm --prefix browser-tests exec -- playwright install chromium
```

Run the suite:

```bash
npm --prefix browser-tests test
```

Interactive modes:

```bash
npm --prefix browser-tests run test:headed
npm --prefix browser-tests run test:ui
```

On a failure Playwright retains the HTML report, trace, screenshot and video.
The GitHub Actions workflow uploads those files as a short-lived diagnostic
artifact.

## Dependency policy

`@playwright/test` is pinned in this isolated npm package so browser automation
does not alter Flutter's dependency graph. Dependabot checks this directory
weekly, while CI proves each proposed update against the compiled application.
