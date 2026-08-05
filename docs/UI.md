# UI / Design System

## Material 3

The app is built on Material 3. Keep it that way — don't introduce a
competing design system in new work (see [CLAUDE.md](../CLAUDE.md)).

## Quality bar

A screen isn't done when it compiles. See
[Vision.md](Vision.md#what-done-looks-like-for-a-feature) for the full
bar: real backend data (never fabricated numbers or placeholder content),
real loading/empty/error states, visible-and-labeled "Coming soon" for
anything genuinely not built, and visual consistency with the rest of the
app. Reference quality bar: Apple, Discord, Notion, Linear, Spotify — not a
typical chat-app UI.

## Two parallel color systems (know which one a screen actually uses)

1. **The shared theme system** — `lib/core/theme/` (`AppColors`,
   `AppTypography`, `AppSpacing`, `AppRadius`, `AppGradients`, `AppTheme`)
   and `lib/shared/widgets/` (`YoButton`, `YoCard`, `YoTextField`,
   `YoAvatar`, `YoBadge`, plus `lib/shared/widgets/states/` —
   `YoLoadingIndicator`, `YoEmptyState`, `YoErrorState`,
   `friendlyErrorMessage()` in `lib/core/helpers/error_messages.dart`).
   This is the intended long-term system.
2. **The inline-hex convention** — most existing screens don't import the
   above yet. Instead they define `static const Color` fields per-screen
   using a consistent palette by convention, not by shared code:
   - Background: `0xFF080711` / `0xFF09050F`
   - Surface: `0xFF12101D` / `0xFF150C1D` / `0xFF17101F`
   - Border: `0xFF3C2C45` / `0xFF382741` / `0xFF30263F`
   - Accent purple: `0xFFB348FF` / `0xFF9D20FF` / `0xFFB932FF` family
   - Muted text: `0xFFA99DB3` / `0xFF9D95AD`

**When touching an existing screen, match what that screen already does**
rather than mixing both systems in one file. When migrating a screen onto
the shared system, migrate the whole screen, not a widget at a time — see
[Roadmap.md](Roadmap.md) for the migration's current status (foundation
done, per-feature-area passes still in progress).

## The "Coming soon" pattern

When a screen needs a feature with no real backend support yet:

- Show it, don't hide it.
- Disable it (reduced opacity is the established visual, e.g. `Opacity(opacity:
  .55)` or similar) and label it "Coming soon" — a small pill/badge, not
  just grayed-out text.
- Never fabricate the data it would show, and never leave a button that
  does nothing with no explanation.

See [Bugs.md](Bugs.md) and [Roadmap.md](Roadmap.md) for the current list of
what's shown this way (2FA, profile visibility, multi-device sessions, app
language, Creator Studio analytics/monetization, self-serve account
deletion).

## Empty/loading/error states

Use the shared `YoLoadingIndicator` / `YoEmptyState` / `YoErrorState` /
`friendlyErrorMessage()` where a screen already imports the shared theme;
otherwise match the screen's existing inline-styled equivalents rather than
introducing a third pattern into one file.

## Verifying visually

For UI changes, start the dev server / simulator and actually look at the
golden path and edge cases before calling a change done — see
[Flutter.md](Flutter.md#verification-checklist-before-calling-dart-work-done).
