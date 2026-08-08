# 2026-08-08 — Full product audit + hardening pass

Whole-product review (app, website, Firebase, functions, CI, docs)
followed by execution of the highest-value items. Same-day context: the
P0 bugfix + profile-media-crop pass earlier today
([session log](2026-08-08-p0-bugfixes-and-profile-media-crop.md)).

## Audit scores (1–10, product-readiness lens)

| Area | Score | Notes |
|---|---|---|
| Auth + email verification | 8.5 | Branded action pages, Resend delivery, verified-gating in rules |
| Profile & media | 9 | After today's crop-editor pass; fan-out live |
| Home / Chats / Friends | 8 | Real data, friendly error copy everywhere now |
| Notifications | 8 | Dedupe fixed today; push via function trigger |
| Rooms (Community/Broadcast) | 7.5 | Solid; shared-primitives redesign tracked (Roadmap 0f) |
| Clubs / Moments / Awards | 7.5–8 | Real backends, honest Coming-soons |
| Creator Studio | 7 | Real dashboard; analytics honestly not built |
| Settings | 8 | Deep and real; account deletion still support-email only |
| Premium | 7.5 | Server-authoritative entitlements live; billing adapters blocked on store credentials |
| Website | 8 | Full page catalog, honest download page, live status page |
| **CI** | **5 → 8** | Was analyze-only; now gates on all tests + both rules suites |
| **Observability** | **2 → 6** | Was literally nothing; Crashlytics now on iOS/Android (web still uncovered) |
| Storage rules posture | 6 → 8 | Was 10 MB cap, zero tests; now 2 MB with a 22-check emulator suite |
| First-run / onboarding | 5 | No onboarding flow; usernames seeded from email, duplicates exist |
| Android | UNVERIFIED | Toolchain present, builds, but no flow has ever been eyeballed on-device |

## Documentation vs. reality discrepancies found (and fixed)

1. **Roadmap 0d** claimed the profile identity fan-out was "NOT
   deployed" — `firebase functions:list` shows `onProfileIdentityChanged`
   live. Marked Done.
2. **Backend.md** listed the 25-function admin suite with no hint that
   **none of the 20 admin/moderation functions are deployed** — and no
   admin UI exists in either repo (`yovoice-website/src/app/admin/` is an
   empty `.gitkeep`). Documented as deliberate dormancy: deploy them with
   the first admin surface, not before.
3. **TESTING.md** said "43 rules checks" and "two Dart test files" —
   reality is 91 + 22 rules checks and ~14 Dart test files / 78 tests.
   Rewritten.

## Executed this pass

1. **CI test gate** — `flutter test` + Firestore rules suite + new
   Storage rules suite (real emulators, `demo-yovoice`, no credentials)
   now run before the Hosting deploy. Rules deploys stay manual
   (deliberate, unchanged).
2. **Storage rules** — first emulator suite
   (`firestore-tests/storage.test.js`, 22 checks, all paths); profile
   cap 10 MB → 2 MB (obsolete since ADR-025's re-encode); deployed to
   production after the suite passed. Closes Roadmap 0 and 0b.
3. **Crashlytics** (ADR-027) — `firebase_crashlytics` wired in `main()`
   (`FlutterError.onError` + `PlatformDispatcher.onError`), disabled in
   debug, try/caught so observability can never take the app down, web
   excluded (unsupported). Android gradle plugin added.
4. **Docs truth-pass** — items above plus DEPLOYMENT.md pipeline
   description and Roadmap Done entry.

## Deliberately NOT done, and why

- **Onboarding flow** — the biggest product gap (first-run experience,
  username choice/uniqueness), but a multi-day design+build+migration;
  needs its own pass. Recommended as the next major product investment,
  together with Roadmap 0c (username uniqueness) since they share the
  username-claim schema.
- **Analytics** — deserves an event-design decision, not a drive-by
  `firebase_analytics` install; web config needs a measurementId check.
- **Premium billing adapters** — blocked on App Store/Play Console
  product setup (owner credentials).
- **App Check enforcement** — still needs token-delivery monitoring data
  (ADR-004).
- **Admin functions deploy** — nothing calls them; safer undeployed.
- **Deleting `test/widget_test.dart` boilerplate** — kept (harmless,
  1-line placeholder).

## Verification status

- Storage suite: 22/22 against a fresh emulator; rules deployed after.
- `flutter analyze` clean, `flutter test` 78/78 after Crashlytics.
- iOS + Android builds with Crashlytics: recorded below once the builds
  finish (see the commit that includes this file for the final state).
- New CI gates verify themselves on the next push's Actions run.
