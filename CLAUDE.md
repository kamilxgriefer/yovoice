# Working on YO Voice

This file is auto-loaded at the start of every session in this repo. The
rules below are not suggestions — follow them exactly.

## What YO Voice is

A premium consumer social **voice-first** product: live voice rooms, voice
moments, and messaging, with a dark/cosmic visual identity. The Flutter app
in this repo is the primary product. Main areas: Home, Rooms
(Community + Broadcast), Chats, Friends, Clubs, Profile, creator/follow,
Settings. Product detail lives in [docs/Vision.md](docs/Vision.md) and
[docs/Features.md](docs/Features.md).

## Product invariants

- **Community rooms and Broadcast rooms are different products**, not two
  labels for one thing. `RoomExperience` (`lib/features/rooms/data/models/room_experience.dart`)
  is a real two-value enum and they route to different screens. Never
  collapse, merge, or "unify" them without being explicitly asked.
- **Never invent backend functionality, fake users, or fake activity.** If
  something has no backend, show it disabled/"Coming soon" (see the Hard
  rules below).
- **The theme code is the single source of truth for the palette** —
  `lib/core/theme/app_colors.dart`. Read it rather than trusting remembered
  hex values; they have already drifted once. The identity is dark,
  premium, slightly cosmic, warm, voice-first.

## Before making significant changes

Read [docs/Vision.md](docs/Vision.md), [docs/Architecture.md](docs/Architecture.md)
and [docs/Roadmap.md](docs/Roadmap.md) first. They answer, respectively:
what this product is for, how it's actually built right now, and what's
done vs. planned. For deeper detail, docs/Architecture.md links to
everything else — Features.md, Firebase.md, Backend.md, Flutter.md, UI.md,
PROJECT_STRUCTURE.md, SECURITY.md, DEPLOYMENT.md, TESTING.md,
DEPENDENCIES.md. If a change touches Firestore rules, Storage rules, or
anything granting a role/permission, read
[docs/SECURITY.md](docs/SECURITY.md) first — this project has a real,
documented history of getting that category of change wrong (see
[docs/Decisions.md](docs/Decisions.md)'s ADR-003 and the checklist at the
end of SECURITY.md). Don't assume — verify against current code when a
doc and the codebase disagree; docs can drift, code is ground truth.

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
- **No user-facing UI feature is complete until its mobile, tablet and
  desktop layouts have been intentionally implemented and verified.**
  Define narrow, medium and wide behavior for every new or modified
  component — desktop is never a stretched phone layout and mobile is
  never a compressed desktop one. Share state, services, permissions
  and business logic across the variants; let only presentation and
  navigation adapt by available width (not device labels). Verify
  navigation, loading, empty, error, populated and long-content states,
  text wrapping, and browser zoom at each breakpoint. Screens rendered
  inside the desktop shell's content slots draw no app bar of their own
  (the shell owns navigation); the same screens pushed as mobile routes
  carry a real app bar with Back — see `isRootTab` on the More
  destinations and ModerationCenterScreen/StaffCenterScreen for the
  established pattern.

## After finishing a feature

Full version, with the reasoning behind each step, in
[docs/DEVELOPMENT_WORKFLOW.md](docs/DEVELOPMENT_WORKFLOW.md). Short
version:

- **Update [docs/Roadmap.md](docs/Roadmap.md)** — move it from
  Planned/In Progress to Done, with the commit or PR it landed in.
- **Update [docs/Decisions.md](docs/Decisions.md)** whenever you make or
  change an architectural decision (schema change, new dependency, new
  pattern that future code should follow, a workaround and why it was
  necessary). It's a numbered ADR log — each entry needs Context,
  Decision, Reasoning, and Consequences; see any existing entry for the
  shape. Short entries are fine — the point is capturing the *why*, not
  writing an essay.
- **Update [docs/Bugs.md](docs/Bugs.md)** whenever you find or fix a bug —
  it's a living list, not a changelog.
- For a substantial multi-step session, consider adding a dated entry under
  `docs/Sessions/` the way past sessions have — see the existing files
  there for the format. Not required for small changes.

## Project-specific conventions already established

- **Git workflow**: never push directly to `main`. Work on a focused branch
  and open a pull request into `main`. Merge only after `verify_and_build`,
  `Playwright against release web build`, and
  `Analyze JavaScript and TypeScript` are green. Use squash merge so
  `main` remains linear. This protected-main policy supersedes ADR-002;
  `.github/rulesets/main-protection.json` is the canonical import recipe and
  GitHub Settings → Rules remains the enforcement authority. Because this is
  a solo repository, zero human approvals are required, but unresolved review
  conversations and all required automated checks still block merge.
- **Verification gate**: `flutter analyze` must be clean before considering
  Dart work done. For UI changes, verify in the iOS Simulator when possible.
- **Visual claims need visual proof.** `flutter analyze`, `flutter test`,
  widget tests, and a successful build prove *code health* — they do not
  prove a screen renders correctly. Never call a visual/UI issue "fixed"
  without having actually opened the screen and looked at it. If it could
  not be inspected (tooling broken, environment blocked), say so and mark
  it UNVERIFIED rather than implying it was checked. Web has an extra
  trap: browsers can serve a stale `main.dart.js`, so confirm the deployed
  bytes actually contain the change before concluding anything from a
  screenshot.
- **Firestore rules changes**: always emulator-tested before deploy — see
  `docs/TESTING.md` and `firestore-tests/README.md`. A passing test suite
  that never exercises a real `collectionGroup()` query does not prove a
  `collectionGroup()` query works; this has bitten the project before
  (`docs/Decisions.md`, ADR-007). Deploys are manual, on purpose — see
  `docs/DEPLOYMENT.md`.

## Repo map

Full breakdown in [docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md).
The essentials:

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
