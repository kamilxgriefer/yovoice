# Claude round integration — 2026-09-10

> **Outcome (added 2026-09-16).** This integration landed in `001626e7`
> (tester build 2.0.0 (24), 2026-09-12) and `c2206c05` (2026-09-12). The
> "not committed" and "GIF provider remains `none`" statements below are
> dated facts about base `692aa93f`. Current source pins the `yovoice`
> provider (ADR-172 amendment).

## Scope and source

User request: finish what Claude had introduced. Base `main`/`origin/main`
`692aa93ff647f9342f96ad1acb423d1f6037d953`; version `2.0.0+23`.
Preserved the inherited dirty tree, including unrelated assets and configuration.
No version bump, provider-secret change, store upload, production deployment,
tester email, commit or push was performed in this integration session.

## Implemented

- Reels: silent autoplay retained; connected own-feed server scope,
  caught-up/replay, genuine playback-based seen writes, inline primary grants,
  identity-scoped cache, neighbor warming and expired-grant recovery.
- GIF: Direct/Room/Club canonical sends through existing writers, stable
  request IDs on in-session retry, received rendering and privacy preference,
  honest provider-off state. GIFs never enter attachment upload/storage cleanup.
- Moderation: atomic asset blocking/report/audit, active-profile and report
  quotas, digest IDs/evidence bounds, canonical GIF tombstones and conditional
  latest DM preview, atomic owner-removal attribution.
- GIF client lifecycle: short-input cancellation, single-flight paging,
  delayed-catalog query retention, tab search restoration; moderation search
  remains visible and consistent when returning from narrow detail view.
- Home/keyboard: preserved and verified Claude's rhythm/owned-room fixes;
  closed large-text Chat header, moderation editor, Club card and Podcast
  dropdown defects found in real render captures. Done remains above the
  simulated software keyboard, including the Reel composer.
- Added all 37 missing shared GIF phrases to 41 translated catalogs, plus
  EN/PL callsites (43 locale variants). All newly introduced integration copy
  is catalog-backed; structural coverage is not native-speaker certification.

## Verification

Backend was run serially against isolated local Auth/Firestore/Storage
emulators, with Node 22 and demo projects, never production.

| Final gate | Result |
|---|---:|
| Complete Functions | 1580/1580; 120 suites; no skips |
| Firestore rules | 564/564 |
| Storage rules | 67/67 |
| Family media | 11/11 |
| Focused atomic admin + Club + GIF | 165/165 |
| Full Flutter analysis | clean, 16.1 seconds |
| Complete Flutter suite | 3289/3289, 2 minutes 44 seconds |
| Flutter release Web build | passed, 103.7 seconds; Wasm dry run succeeded |
| Latest client lifecycle regressions | 136/136 |
| Adjacent UI/moderation/localization | 162/162 |
| Independent strict keyboard/GIF render gate | 142/142, zero collected layout errors |
| Corrected Reel keyboard/focus render gate | 12/12 |

Targeted counts overlap; do not add them to a full-suite total. The full
Flutter suite and release Web build ran on the final stable Dart source.
Commands: `flutter analyze --no-pub`,
`flutter test --no-pub --reporter expanded`,
`flutter build web --release --no-pub`.

Backend exact commands/logs and unchanged-source manifests:
`/private/tmp/yovoice-backend-qa-final.JfCPN2/QA-EVIDENCE.md`.
Client focused log: `/tmp/yovoice-final-client-focused.log`.
Full Flutter logs: `/tmp/yovoice-flutter-final.GtfXr0/full-tests.log` and
`/tmp/yovoice-flutter-final.GtfXr0/web-build.log`.
Independent visual report and actual PNGs:
`test/.screenshots/visual-final-review.md`.

Visual matrix includes 320/390/430/768/1100/1440/2560 as relevant,
Dark/Pearl, PL/AR and 200% text; real Flutter widgets, fonts and fake test
services. No native Simulator was booted for this review. Mock backend and
test font caveats are explicitly recorded by the visual reviewer.

Independent security review closed all current source findings. Principal
review also closed five client lifecycle findings after deterministic
regressions, inspected the final test/build logs and representative PNGs,
and approved the **source/local verification gate** with no actionable
findings. `git diff --check` excluding the untouched inherited `.env` is clean;
the amended provider-smoke helper passes syntax inspection without a live call.

## Remaining external acceptance, not claimed complete

- GIF provider remains `none`: owner account/terms/key, live provider smoke,
  enabled exports/secret bindings and coordinated backend/client rollout.
- Production own-feed composite index `READY`, `reelViews.expiresAt` and
  `gifQueryCache.expiresAt` TTL policies must be explicitly verified; no TTL on
  `gifAssets`. Source declarations/emulators do not prove those services live.
- Physical iOS/Android, two-account GIF delivery/moderation, native voice
  recording/playback, live-call coexistence, real keyboard, browser autoplay
  and browser zoom are not equivalent to widget captures.
- GIF retry survives an open screen session, not process termination.
- GIPHY receives device metadata when hotlinked GIF bytes load. Turning
  auto-load off prevents byte requests until the user opts in. Blocking an
  asset does not erase previously sent hotlinks; remove the individual message.
- Ranking weights lack product-traffic validation; existing account-data
  erasure/export gaps are not solved by a seen-history TTL.

See ADR-173 and the pending rollout sections in `docs/DEPLOYMENT.md`.
