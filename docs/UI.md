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

## Semantic colour ownership

`AppColors` owns stable brand and status colours. `AppPalette`, installed as a
`ThemeExtension` by `AppTheme`, owns every brightness-dependent role:
backgrounds, raised/muted surfaces, borders, readable copy, navigation chrome,
focus, scrims and status containers. Shared components and normal product
screens must request those roles through `context.appPalette` or
`Theme.of(context).colorScheme`; a raw dark hex is not a theme.

Pearl is a warm daylight theme (`#F6F2F8` canvas, white cards, ink copy and a
restrained plum shadow), not an inverted Dark theme. Status/navigation bars
follow the selected brightness through `AppTheme.systemOverlayStyle`. Inputs
and controls use the stronger semantic boundary; decorative card borders may
use the quieter one. Essential text pairs meet 4.5:1 and focus/control
boundaries meet 3:1.

Voice rooms, calls, recording/review, story viewing and image croppers are
intentional immersive-dark islands. They own a complete dark surface +
foreground + scrim treatment; never let an inherited light foreground leak
onto their media, and never use their dark literals for a normal Pearl page.
When migrating legacy UI, migrate the complete surface atomically rather than
mixing semantic and screen-local roles.

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

## Announcing status to assistive technology

**One polite live region per screen, and errors on the assertive channel.**
Flutter web has no per-node `aria-live`: `LiveRegion` writes into a single
*shared* announcement element and clears it after 300 ms, so two live
regions changing in the same frame overwrite each other and which one
survives is a race. This shipped once as a failed publish announcing a
success-sounding line. A screen that seems to need two polite regions needs
one region and a composed message. Full reasoning and the failure it came
from:
[ADR-058](Decisions.md#adr-058-one-polite-live-region-per-screen-and-errors-go-out-on-the-assertive-channel).

## Verifying visually

For UI changes, start the dev server / simulator and actually look at the
golden path and edge cases before calling a change done — see
[DEVELOPMENT_WORKFLOW.md](DEVELOPMENT_WORKFLOW.md#verification-checklist-before-calling-something-done).

Two traps this project has actually hit, both of which produce screenshots
that look like proof:

- **A preview harness that does not install the production theme.** The
  recording screen's harness rendered under `ThemeData.dark` rather than
  `AppTheme.darkTheme`, so its screenshots showed neither production
  typography nor the real input field. Check the harness before trusting
  its output.
- **A stale `main.dart.js`.** Confirm the deployed bytes contain the
  change before concluding anything from a browser screenshot (see
  [CLAUDE.md](../CLAUDE.md)).

**Review precedes deploy for a UI change**, on the same terms as a rules
change — [ADR-059](Decisions.md#adr-059-a-ui-change-is-reviewed-before-it-is-deployed-on-the-same-terms-as-a-rules-change).
