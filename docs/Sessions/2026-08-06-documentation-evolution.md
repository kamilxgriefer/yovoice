# 2026-08-06 — Documentation evolution: from audit to engineering knowledge base

Follow-up to the same day's earlier documentation audit
([docs/DOCUMENTATION_AUDIT.md](../DOCUMENTATION_AUDIT.md)). That pass
established where things live; this one is about depth — making the docs
answer *why*, not just *what*, to the standard of "would a senior engineer
joining this project understand it, and could a new developer become
productive after reading it." No application code was touched — this was
a documentation-only pass, verified against the repository throughout
rather than written from memory.

## What changed

**`docs/Decisions.md`** rewritten as a proper, numbered ADR log —
Context/Decision/Reasoning/Consequences for all 12 existing decisions,
reordered chronologically (oldest first, ADR-001 → ADR-012) using real
commit dates pulled from `git log --reverse`, not guessed. Added 3 new
ADRs capturing architecture that was always true but never written down:
`ADR-013` (clients write Firestore directly; Cloud Functions are reserved
for privileged/secret/fan-out work), `ADR-014` (two deployables sharing
one Firebase project, and why), `ADR-015` (feature-based folder structure
over layer-based, and what it costs). An index table at the top makes the
whole log scannable without reading top to bottom.

**`docs/Roadmap.md`** — every In Progress and Planned/Backlog item now
carries status, description, dependencies, priority (with the reasoning
behind the priority, not just a label), and future considerations. Done
items stay a lighter changelog-style list on purpose — re-litigating
"status: Done" for 12 shipped items would have been noise, and the file
says so explicitly rather than leaving the inconsistency unexplained.

**`docs/Architecture.md`** substantially expanded: a stated core
architectural choice (client-direct Firestore writes, rules as the
authorization layer) up front, a real authentication-flow diagram, a full
concrete data-flow walkthrough (joining a Broadcast Room, traced from tap
to Firestore transaction to the `createLiveKitToken` Cloud Function to the
LiveKit connection — the one flow that touches every layer), and expanded
sections on Firestore/Cloud Functions/LiveKit interaction and website
integration. Deployment detail moved out to the new `DEPLOYMENT.md`
rather than duplicated.

**Seven new docs**, each created because it filled a real gap rather than
for coverage's sake:

- `PROJECT_STRUCTURE.md` — the full repo tree, including root-level
  scripts and the `.yovoice_backups/` folder that predate current
  conventions (documented, not deleted — see "what wasn't done" below).
- `DEVELOPMENT_WORKFLOW.md` — the narrative version of `CLAUDE.md`'s
  rules: how a feature actually gets built end to end across the data
  model → rules → service → UI → tests chain.
- `TESTING.md` — an honest accounting of test coverage: the 43-check
  Firestore rules suite is mature; `test/auth_service_verification_test.dart`
  is real but narrow; `test/widget_test.dart` is unfilled boilerplate;
  Cloud Functions have zero automated coverage. Written plainly rather
  than implying more coverage exists than does.
- `DEPLOYMENT.md` — what's automatic (Hosting via GitHub Actions, gated on
  `flutter analyze` passing) versus manual (rules, indexes, functions,
  storage), and a real gotcha found while verifying this doc:
  `functions/package.json`'s `deploy` script only deploys
  `createLiveKitToken`, not every function.
- `DEPENDENCIES.md` — curated "why this one," not a `pubspec.yaml` mirror.
- `SECURITY.md` — the security model as a whole, five rules-design
  principles each traced back to the specific incident that produced it,
  a checklist for new privileged write paths, and current posture.
- `CONTRIBUTING.md` — honest about the current solo/push-to-`main`
  reality, with an explicit section on what changes the moment a second
  contributor joins.

**Explicitly not created**: `SYSTEM_OVERVIEW.md`. The task listed it as an
example, but by the time `Architecture.md` had the high-level-architecture
diagram, data flow, auth flow, and per-layer interaction sections the task
also asked for, a separate overview document would have duplicated it
almost entirely — one topic, one source of truth, so `Architecture.md`
absorbed that role instead of gaining a sibling.

**Existing docs polished**: `Firebase.md`, `Backend.md`, `Flutter.md`,
`UI.md`, `Vision.md`, `Features.md`, and `Bugs.md` all got cross-links
into the new ADR numbers and the new docs, and a few duplicated
explanations were trimmed in favor of linking to the one place that now
owns that explanation (e.g. the verification checklist used to be written
out fully in both `Flutter.md` and implicitly elsewhere — it now lives
once, in `DEVELOPMENT_WORKFLOW.md`).

## What wasn't done, on purpose

- **`.yovoice_backups/`, `install_room_types.py`, `patch_room_screen.py`,
  `yovoice_vscode_cleanup.sh`** were documented as legacy artifacts in
  `PROJECT_STRUCTURE.md`, not removed — the task was documentation-only,
  and deleting tracked files (even clearly superseded ones) is a
  code/repo-hygiene decision, not a docs one.
- **`docs/DOCUMENTATION_AUDIT.md`** was left in place rather than merged
  or archived — it's still an accurate record of that specific pass — with
  one banner added pointing forward to this file so nobody mistakes it for
  the current full picture of `docs/`.

## Verification

A link-and-anchor checker (Python, not a package — this repo doesn't
depend on a markdown-link-check tool) was run across every `.md` file in
the repository twice: once for plain file-path links (same check as the
original audit), once more after adding real GitHub-slug anchor
resolution, specifically because the ADR rewrite introduced dozens of
`#adr-NNN-...` anchor links that needed to actually match the headings
they pointed to. The second pass caught one real mistake (`UI.md` linking
to a `Flutter.md` heading that had been reworded during this same pass)
and two false positives from the checker's own slugify function
incorrectly stripping underscores from inline-code headings — both
verified by hand before concluding they weren't real breaks. Final run:
zero broken links, zero broken anchors, across the whole repository.
