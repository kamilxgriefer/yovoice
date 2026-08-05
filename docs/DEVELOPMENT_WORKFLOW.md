# Development Workflow

How to actually work on this repo, day to day — the narrative version of
the rules in [CLAUDE.md](../CLAUDE.md). For exact commands, this file
links out to [Flutter.md](Flutter.md), [Firebase.md](Firebase.md), and
[TESTING.md](TESTING.md) rather than repeating them; the goal here is the
*sequence* and the *judgment calls*, not a second copy of the same
command block.

## Before you start

Read [Vision.md](Vision.md), [Architecture.md](Architecture.md), and
[Roadmap.md](Roadmap.md) — in that order, they answer what this product
is for, how it's built, and what's already planned. If what you're about
to build touches Firestore's schema or `firestore.rules`, also read
[SECURITY.md](SECURITY.md) first; the cost of an authorization mistake in
this codebase is unusually high, since rules are the *entire*
authorization layer (see
[ADR-013](Decisions.md#adr-013-clients-write-firestore-directly-cloud-functions-are-reserved-for-privileged-work)).

## Git workflow

Commit and push straight to `main` — no feature branches, no PRs, by
default. This is a deliberate choice for a solo project, not an
oversight; see [ADR-002](Decisions.md#adr-002-git-workflow-push-straight-to-main-no-prs)
for the reasoning and what changes the moment a second contributor joins
(see [CONTRIBUTING.md](CONTRIBUTING.md)).

Before a change big enough to be risky — a schema change, a rules
rewrite, a large refactor — take a backup first: a local git tag or
branch snapshot of `main`. This is the safety net a PR would otherwise
provide, without the ceremony. A tag costs one command and nothing else;
there's no reason to skip it for anything that would be painful to lose.

Write commit messages that explain *why*, not just *what changed* — the
diff already shows what changed. The existing commit history is a decent
model for this (see `git log`).

## Adding a feature, end to end

Most features touch some combination of these layers, roughly in this
order:

1. **Data model** — does this need a new Firestore field, collection, or
   subcollection? If so, check [Firebase.md](Firebase.md) for the current
   schema and think about whether the new shape could ever need a
   `collectionGroup()` query (if two different parent collections might
   ever share a subcollection name, don't let that happen — see
   [ADR-005](Decisions.md#adr-005-roomsroomidmembers-renamed-to-roommembers)
   for exactly what goes wrong).
2. **Firestore rules** — write the rule that authorizes the new read/write
   *before* or alongside the client code that uses it, not after. Default
   to a client-direct write authorized by rules; only reach for a Cloud
   Function if one of ADR-013's four conditions actually applies. If the
   new write can carry any kind of permission/role/ownership claim, make
   sure the rule checks that claim against a real, independently-controlled
   document — see [SECURITY.md](SECURITY.md) for the checklist that came
   out of getting this wrong before.
3. **Service layer** (`lib/features/<feature>/data/services/`) — the Dart
   class wrapping the Firestore/Storage/Functions calls for this feature.
   Match the patterns already used by sibling services rather than
   inventing a new one (stream-based reads, `Future`-based writes with a
   transaction where more than one document needs to change atomically).
4. **UI** (`lib/features/<feature>/presentation/`) — see
   [UI.md](UI.md) for the design-system conventions (which color system
   the screen you're touching already uses, the "Coming soon" pattern for
   anything without real backend support yet, the quality bar from
   [Vision.md](Vision.md#what-done-looks-like-for-a-feature)).
5. **Tests** — see [TESTING.md](TESTING.md) for what's realistic to add
   given current coverage. At minimum, a rules change needs a
   `firestore-tests` case; a non-trivial service method is a good
   candidate for a unit test in the style of
   `test/auth_service_verification_test.dart`.

## Verification checklist before calling something done

1. `flutter analyze` — zero issues. This isn't just local convention: the
   GitHub Actions workflow runs it before every Hosting deploy, so a
   failing analyze blocks the website build going live (see
   [DEPLOYMENT.md](DEPLOYMENT.md)).
2. If `firestore.rules` or `storage.rules` changed: run the emulator test
   suite (`firestore-tests/`) against a **freshly started** emulator — see
   [TESTING.md](TESTING.md) for why "freshly started" matters and why a
   passing suite isn't automatically proof a `collectionGroup()` query
   works ([ADR-007](Decisions.md#adr-007-firestore-rules-changes-are-always-emulator-tested-against-a-real-collectiongroup-query)).
3. For UI-facing changes: actually run it, in the iOS Simulator when
   possible, and look at the golden path plus loading/empty/error states —
   not just that it compiles. If a screen genuinely can't be visually
   verified (no test credentials available, for example), say so
   explicitly rather than claiming it was checked.

## After finishing a feature

- **Update [Roadmap.md](Roadmap.md)** — move the item into Done, note the
  commit.
- **Update [Decisions.md](Decisions.md)** if you made or changed an
  architectural decision — a schema change, a new dependency, a workaround
  and why it was necessary. Use the Context/Decision/Reasoning/
  Consequences format already established there; a short entry is fine, a
  missing one isn't.
- **Update [Bugs.md](Bugs.md)** if you found or fixed a bug — it's a
  living list, not a changelog.
- For a substantial multi-step session, add a dated entry under
  `docs/Sessions/` — see existing files there for the format. Small,
  single-purpose changes don't need this.

## Code review

There currently isn't any — see [ADR-002](Decisions.md#adr-002-git-workflow-push-straight-to-main-no-prs)
for why that's a deliberate tradeoff for a solo project, and
[CONTRIBUTING.md](CONTRIBUTING.md) for what review process would look
like the moment that stops being true. In the meantime, the verification
checklist above is the closest thing this project has to a pre-merge
gate — treat it as non-negotiable specifically because nothing else is
catching mistakes before they reach `main`.
