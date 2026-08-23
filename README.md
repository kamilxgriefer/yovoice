# YO Voice 🎙️

[![Continuous verification](https://github.com/kamilxgriefer/yovoice/actions/workflows/firebase-hosting-merge.yml/badge.svg?branch=main)](https://github.com/kamilxgriefer/yovoice/actions/workflows/firebase-hosting-merge.yml)
[![Flutter web browser smoke](https://github.com/kamilxgriefer/yovoice/actions/workflows/browser-smoke.yml/badge.svg?branch=main)](https://github.com/kamilxgriefer/yovoice/actions/workflows/browser-smoke.yml)
[![CodeQL](https://github.com/kamilxgriefer/yovoice/actions/workflows/codeql.yml/badge.svg?branch=main)](https://github.com/kamilxgriefer/yovoice/actions/workflows/codeql.yml)
[![Dependabot](https://img.shields.io/badge/Dependabot-enabled-025E8C?logo=dependabot&logoColor=white)](https://github.com/kamilxgriefer/yovoice/network/updates)
[![Branch policy](https://img.shields.io/badge/main-PR%20%2B%20required%20checks-6f42c1?logo=github&logoColor=white)](docs/BRANCH_PROTECTION.md)

> **Speak. Connect. Be heard.**

YO Voice is a premium, voice-first social platform built with Flutter and
Firebase. It combines live Community and Broadcast rooms, Voice Moments,
messaging, Clubs, Friends, creator tools and role-aware staff moderation in one
responsive product for mobile, web and desktop.

## ✨ Product scope

- distinct Community and Broadcast voice-room experiences powered by LiveKit;
- Voice Moments, direct messaging, Friends, Clubs and creator/follow flows;
- responsive navigation and purpose-built mobile, tablet and desktop layouts;
- Firebase Authentication, Firestore, Storage, Cloud Functions, Cloud Messaging,
  App Check and Crashlytics integration;
- moderation and Staff Center workflows with role-aware authorization and audit
  trails;
- automated quality, browser, security and dependency checks before changes are
  considered ready for `main`.

## 📚 Project documentation

The repository documents both the product and the engineering decisions behind
it:

- [`SECURITY.md`](SECURITY.md) — private vulnerability reporting and responsible
  disclosure policy;
- [`docs/Vision.md`](docs/Vision.md) — product purpose and quality bar;
- [`docs/Architecture.md`](docs/Architecture.md) — Flutter, Firebase, Cloud
  Functions and LiveKit system map;
- [`docs/Features.md`](docs/Features.md) — implemented feature inventory;
- [`docs/Roadmap.md`](docs/Roadmap.md) — current delivery status and planned
  work;
- [`docs/Decisions.md`](docs/Decisions.md) — architectural decision records and
  the reasons behind important implementation choices;
- [`docs/Bugs.md`](docs/Bugs.md) — living register of discovered and resolved
  defects;
- [`docs/TESTING.md`](docs/TESTING.md) — measured automated-test coverage and
  its known limits;
- [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) — verified build and controlled
  production-release process;
- [`docs/SECURITY.md`](docs/SECURITY.md) — authorization architecture, Firebase
  Rules principles and current security model;
- [`docs/QUALITY_AUTOMATION.md`](docs/QUALITY_AUTOMATION.md) — CI, browser
  automation, SAST, dependency monitoring and portfolio evidence;
- [`docs/BRANCH_PROTECTION.md`](docs/BRANCH_PROTECTION.md) — why `main` is
  deliberately unprotected, and what the local gate has to cover instead.

## 🧱 Technology stack

- **Client:** Flutter, Dart, Material 3 and Riverpod where cross-screen state
  requires it;
- **Backend:** Firebase Authentication, Firestore, Storage, Cloud Functions,
  Cloud Messaging, App Check and Crashlytics;
- **Realtime voice:** LiveKit;
- **Backend runtime:** Node.js 22;
- **Quality and security:** GitHub Actions, Flutter Analyzer, Flutter tests,
  Firebase Emulator Suite, Node test runner, Playwright, CodeQL, npm audit and
  Dependabot.

## 🛡️ Continuous quality and security

Every pull request to `main` and every update of `main` automatically runs the
project's verification gates. The pipeline checks:

- `flutter analyze` and the complete Flutter test suite;
- Firestore, Storage and cross-service authorization rules against Firebase
  emulators;
- Cloud Functions tests and emulator-backed binding smoke tests;
- configured production dependency audits;
- a release Flutter web build;
- Chromium smoke tests against the compiled web artifact;
- CodeQL static security analysis for the JavaScript/TypeScript production
  surfaces.

Dependabot checks Flutter, npm, Playwright and GitHub Actions dependencies every
week. Playwright retains a trace, screenshot, video and HTML report when a
browser check fails.

Production is deliberately not published by an ordinary push or pull request.
Firebase Hosting requires an explicit, verified manual release, while Firestore
Rules, indexes, Storage Rules and Cloud Functions remain deliberate manual
deployments because they form the product's authorization and trusted-backend
boundary.

See [`docs/QUALITY_AUTOMATION.md`](docs/QUALITY_AUTOMATION.md) for the trigger
matrix, limitations and ready-to-use CV wording.

## 🔐 Change workflow and the release boundary

This is a solo-maintained repository and `main` is deliberately **not**
protected. The delivery path is:

```text
local verification (flutter analyze + flutter test + emulator suites)
→ commit
→ push straight to main
→ verify_and_build + Playwright + CodeQL run automatically
```

No feature branch, no pull request, no approval step. The reasoning, and the
trade it makes, are in
[`docs/BRANCH_PROTECTION.md`](docs/BRANCH_PROTECTION.md) and
[ADR-108](docs/Decisions.md#adr-108-main-is-unprotected-again--a-solo-repository-pays-the-pull-request-tax-for-a-review-that-never-happens).
The honest cost: CI now reports **after** `main` moves instead of blocking a
merge, so the local run before pushing is the real gate. Never push on a failed
run, and never force-push `main`.

Dependabot still opens dependency pull requests — that is dependency
monitoring, and it stays. A pull request in this repository means "a bot
proposed a dependency bump", not "the maintainer is waiting for review".

**The release boundary is unchanged and is the one thing still gated.**
Production Hosting is never published by an ordinary push: the deploy job runs
only on `workflow_dispatch` with `deploy_hosting: true`. Firestore rules,
indexes, Storage rules and Cloud Functions are deployed by hand — see
[`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md). Pushing to `main` ships nothing to
users.

## 🚀 Development setup

Requirements:

- Flutter stable matching the repository CI version;
- Node.js 22;
- Java 21 for Firebase emulators;
- Firebase CLI for backend and Rules verification.

Install Flutter dependencies and run the app:

```bash
flutter pub get
flutter run
```

Run the primary Dart quality gates:

```bash
flutter analyze
flutter test
```

Browser-smoke setup and commands live in
[`browser-tests/README.md`](browser-tests/README.md). Complete emulator commands
and current measured suite counts live in [`docs/TESTING.md`](docs/TESTING.md).

## 📸 Screenshots

Product screenshots and store-ready media will be added as release surfaces are
finalised and verified on real devices.

## 👨‍💻 Developer

Developed by **Kamil Jaguszewski** (`kamilxgriefer`).

GitHub: [github.com/kamilxgriefer](https://github.com/kamilxgriefer)

## 📄 License

This project is proprietary. All rights reserved.
