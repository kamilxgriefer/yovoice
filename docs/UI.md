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

## Responsive layout contract

Responsive decisions are based on the content slot available to a widget,
not on a platform check. Full-screen backgrounds and gradients may fill the
viewport; readable and interactive content must use
`ResponsiveContentFrame` from
`lib/shared/widgets/layout/responsive_content_frame.dart`.

- Narrow (`< 600 px`): 16 px horizontal gutter and a single-column flow.
- Medium (`600–1099 px`): 24 px gutter; use a second column only when each
  item keeps a useful minimum width.
- Wide (`>= 1100 px`): 32 px gutter inside a centered workspace capped at
  1440 px, after the desktop sidebar has been removed from the available
  width.
- Forms and focused actions use `form` (720 px); lists and reading surfaces
  use `list` (880 px); feeds and detail screens use `feed` (1040 px);
  dashboards use `dashboard` (1200 px); staff/moderation workbenches use
  `workbench` (1440 px).
- Root lists such as Notifications, Chats, Friends, Clubs and Settings are
  top-left aligned within the centered workspace. Profiles, authentication,
  Premium and form flows are centered. Voice rooms remain immersive, while
  their stage and controls keep a bounded internal width.
- Desktop bottom sheets and menus must use
  `ResponsiveContentFrame.adaptiveModalConstraints`; mobile sheets still fill
  the available width.

Every responsive change must be checked at 320, 390, 430, 768, 1100, 1440
and 2560 px where relevant, plus a 2.0 text scale. The acceptance bar is no
overflow, no clipped primary text, 44x44 minimum interactive targets,
keyboard/focus access on desktop, and preserved safe-area/keyboard insets.

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

This is a product-quality rule, not just a visual convention — see
[ADR-012](Decisions.md#adr-012-coming-soon-instead-of-fabricated-data-or-dead-buttons)
for the full reasoning (a convincing fake erodes trust in every *other*
number on the screen, real ones included, the moment it's noticed). See
[Bugs.md](Bugs.md) and [Roadmap.md](Roadmap.md) for the current list of
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
[DEVELOPMENT_WORKFLOW.md](DEVELOPMENT_WORKFLOW.md#verification-checklist-before-calling-something-done).
