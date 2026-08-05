# Working on YO Voice

This file is auto-loaded at the start of every session in this repo. The
rules below are not suggestions — follow them exactly.

## Before making significant changes

Read [docs/Vision.md](docs/Vision.md), [docs/Architecture.md](docs/Architecture.md)
and [docs/Roadmap.md](docs/Roadmap.md) first. They answer, respectively:
what this product is for, how it's actually built right now, and what's
done vs. planned. For deeper detail see docs/Features.md, docs/Firebase.md,
docs/Backend.md, docs/Flutter.md, and docs/UI.md — Architecture.md links to
all of them. Don't assume — verify against current code when a doc and the
codebase disagree; docs can drift, code is ground truth.

## Hard rules

- **Never remove existing functionality.** Extending or fixing a screen is
  fine; deleting a feature, a screen, or a working code path is not, unless
  the user explicitly asks for that removal.
- **Keep Material 3 design.** Don't swap the design system or introduce a
  competing one in new work.
- **Never break the existing Firebase schema.** Firestore field names,
  collection names, and document shapes are load-bearing — other clients
  (the website, Cloud Functions, existing app installs) read them. Additive
  changes (new optional fields) are fine; renames/removals need a real
  migration plan, not a silent break. See
  [docs/Decisions.md](docs/Decisions.md) for the `roomMembers` rename as an
  example of how a schema change was actually handled.
- **Preserve backward compatibility** unless the user explicitly asks for a
  breaking change.
- **Write production-ready code.** No TODOs left as the final state, no
  fabricated/fake data standing in for something that isn't built yet —
  if a feature has no backend support, show it disabled and labeled
  "Coming soon" rather than faking it. This project already follows that
  convention (see the Settings/Awards/Creator Studio screens).

## After finishing a feature

- **Update [docs/Roadmap.md](docs/Roadmap.md)** — move it from
  Planned/In Progress to Done, with the commit or PR it landed in.
- **Update [docs/Decisions.md](docs/Decisions.md)** whenever you make or
  change an architectural decision (schema change, new dependency, new
  pattern that future code should follow, a workaround and why it was
  necessary). Short entries are fine — the point is capturing the *why*,
  not writing an essay.
- **Update [docs/Bugs.md](docs/Bugs.md)** whenever you find or fix a bug —
  it's a living list, not a changelog.
- For a substantial multi-step session, consider adding a dated entry under
  `docs/Sessions/` the way past sessions have — see the existing files
  there for the format. Not required for small changes.

## Project-specific conventions already established

- **Git workflow**: push straight to `main`, no feature branches or PRs, in
  both this repo and `yovoice-website`. Back up first (a local tag/branch
  snapshot) before a bigger change — see `docs/Decisions.md`.
- **Verification gate**: `flutter analyze` must be clean before considering
  Dart work done. For UI changes, verify in the iOS Simulator when possible.
- **Firestore rules changes**: always emulator-tested before deploy — see
  `firestore-tests/README.md`. A passing test suite that never exercises a
  real `collectionGroup()` query does not prove a `collectionGroup()` query
  works; this has bitten the project before (`docs/Decisions.md`).

## Repo map

- `lib/` — the Flutter app (this repo).
- `functions/` — Firebase Cloud Functions (Node, region `europe-west1`).
- `firestore.rules`, `firestore.indexes.json`, `storage.rules` — backend
  security/schema, shared by the app, the website, and Cloud Functions.
- `docs/` — project documentation (see `docs/Architecture.md` for the full
  index); `docs/Sessions/` holds dated session logs, `docs/Archive/` holds
  superseded/historical documents kept for reference.
- `/Users/kamiljaguszewski/yovoice-website` — the separate Next.js marketing
  + auth + account site, sharing the same Firebase project. Its own
  `README.md` is authoritative for that repo.
