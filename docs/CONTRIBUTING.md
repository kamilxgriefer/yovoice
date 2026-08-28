# Contributing

## Current reality

YO Voice is, today, a solo project: one person writes the code, decides
what ships, and pushes straight to `main` with no PR process — see
[ADR-002](Decisions.md#adr-002-git-workflow-push-straight-to-main-no-prs)
for why that's a deliberate choice, not an oversight, at this project's
current size. This file is written for two audiences at once: anyone
reading this to understand how the project runs today, and future
contributors if that ever changes. It's honest about which parts of
"contributing" apply right now and which are placeholders for later —
consistent with this project's general rule against pretending something
exists before it does (see
[ADR-012](Decisions.md#adr-012-coming-soon-instead-of-fabricated-data-or-dead-buttons)).

## Getting oriented

Read, in order: [Vision.md](Vision.md) (what this is for),
[Architecture.md](Architecture.md) (how it's built),
[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) (where things live),
[Roadmap.md](Roadmap.md) (what's done vs. planned). Then
[DEVELOPMENT_WORKFLOW.md](DEVELOPMENT_WORKFLOW.md) for how to actually
make a change. Don't trust any doc over the code when they disagree —
docs drift, code doesn't.

## Code style

- **Dart**: `flutter_lints` via `analysis_options.yaml`, enforced by
  `flutter analyze` — zero issues is the bar, not "zero errors." Match the
  patterns already used by sibling files in the feature you're touching
  (which color system a screen uses, whether a service is stream-based or
  future-based) rather than introducing a third convention into a file
  that already has one — see [UI.md](UI.md) for the concrete example of
  this with the app's two parallel color systems.
- **Cloud Functions (Node)**: no linter currently configured in
  `functions/` — match the existing style (region/secret declarations at
  the top of each file, `requireVerifiedStaff()`/`requireProtectedOwner()`
  or `requireAuthentication()` guards first thing inside a handler). Privileged
  handlers must never authorize from a custom claim alone.
- **Comments**: explain *why*, not *what* — the code already says what it
  does. A comment earns its place by capturing a non-obvious constraint, a
  workaround for a specific bug, or a decision that would otherwise look
  like a mistake to the next reader. See `firestore.rules` for real
  examples of this done well (most non-trivial rules there carry a comment
  explaining the incident that shaped them).

## Commit conventions

Write commit messages that explain *why* a change was made, not just a
restatement of the diff. `git log --oneline` in this repo is a reasonable
model to follow. There's no enforced format (no Conventional Commits, no
required prefix) — clarity over convention.

## Documentation is not optional

This project treats documentation as a first-class deliverable, not an
afterthought — see [CLAUDE.md](../CLAUDE.md) for the standing rules. In
practice:

- A new architectural decision gets an ADR in [Decisions.md](Decisions.md)
  (Context/Decision/Reasoning/Consequences), not just a commit message.
- A shipped feature moves its [Roadmap.md](Roadmap.md) entry to Done.
- A found-or-fixed bug updates [Bugs.md](Bugs.md).
- A schema change updates [Firebase.md](Firebase.md) and, if it changes
  what's safe to assume elsewhere, [SECURITY.md](SECURITY.md).

A change that's "done" in code but undocumented isn't actually done by
this project's own standard — see
[Vision.md](Vision.md#what-done-looks-like-for-a-feature) for the parallel
rule applied to features.

## Security

Report a security issue directly to the maintainer rather than opening a
public issue — see [SECURITY.md](SECURITY.md#if-you-find-a-security-issue).
Read [SECURITY.md](SECURITY.md)'s design principles and checklist before
touching `firestore.rules`, `storage.rules`, or any Cloud Function that
grants a role or permission — this codebase has a real, documented history
of getting this category of change wrong, and the checklist exists
specifically so it doesn't happen a second time.

## What changes if this project gains contributors

Everything above still applies. What would additionally need to exist,
the moment a second person is regularly pushing code:

- **A real code review step** — pull requests, not direct pushes to
  `main`. [ADR-002](Decisions.md#adr-002-git-workflow-push-straight-to-main-no-prs)
  is explicit that the current workflow only makes sense with one
  contributor; this is the first thing that should change, not an
  afterthought.
- **Branch protection on `main`** — requiring the CI `flutter analyze`
  check (and ideally the Firestore rules suite) to pass before merge,
  rather than trusting it ran locally.
- **A CODEOWNERS-style routing convention** for who reviews changes to
  `firestore.rules`/`storage.rules`/`functions/` specifically, given the
  stakes described in [SECURITY.md](SECURITY.md) — those files deserve
  more scrutiny than a UI-only change.
- **A shared understanding of this documentation set as mandatory**, not
  optional polish — the ADR log in particular only stays valuable if every
  contributor actually writes an entry instead of leaving it to whoever
  originally set the convention up.

None of this exists yet because it isn't needed yet. If you're reading
this because you're about to become this project's second regular
contributor, that's the signal to build these out — starting with a PR
workflow — rather than continuing to push directly to `main`.

## Questions

For now: ask the maintainer directly
(`kamil.piotr.jaguszewski@gmail.com`). If/when this project grows a real
contributor base, this section should be replaced with wherever
day-to-day discussion actually happens (a Discord, GitHub Discussions,
whatever ends up being real) — not before, per the same "don't document
something that doesn't exist yet" principle the rest of this file follows.
