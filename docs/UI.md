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

## Floating mobile navigation

`YoFloatingNavigationDock` is the only mobile shell navigation surface. Its
central YO action is a real action, not a destination tab, and sits in a
continuous sculpted rise that belongs to the dock's single outer vector path.
There is no circular notch, socket, cradle or detached centre tile. The
official transparent `yo-voice-favicon-512.png` mark rests directly on the
Dark/Pearl dock material with no permanent disc or halo. Its invisible target
is 64 px below 332 logical pixels and 68 px otherwise; the asset may overflow
that target so its measured alpha bounds remain approximately 52–62 px. The
transparent artwork is translated 19 px inside that stable target: the visible
alpha, rather than the PNG canvas, sits approximately 22 px below the rise apex
and keeps approximately 19 px of material beneath it.

The control's visible top edge remains tappable, all five actions keep at least
48x48 logical pixels, and safe-area reservation belongs to the dock rather
than each hosting screen. Dark and Pearl use the same geometry with semantic
navigation surfaces. Ordered keyboard traversal is Home, Chats, YO, Moments,
More; the focused YO action owns a temporary two-pixel semantic focus ring.
The compact layout is icon-only while localized labels remain in semantics.
At 160% text and above the dock grows and exposes fitted labels without
shrinking the requested scale. One 52x52, r18 capsule follows only a
parent-accepted destination; adjacent moves stretch gently, cross-YO moves
fade behind the transparent action, and rapid changes retarget from the
currently rendered position. Reduced motion commits capsule and icon state
immediately and disables the YO ripple.

When a real room is minimized, a non-interactive copy of the same transparent
mark rises from the centre axis and resolves into the one real compact room
bar. It never owns room data or controls. The production bar remains the sole
Chat/Mic/More/Return surface, direct calls are excluded, and Reduce Motion
shows the settled bar immediately. Pushed destinations temporarily own that
bar while the covered shell suppresses its copy, so there is one voice listener
and one latest-message subscription throughout route transitions.

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

The canonical brightness-dependent mapping is:

| Semantic role | Dark | Pearl | Ownership |
| --- | --- | --- | --- |
| `background` | `#080711` | `#F6F2F8` | page canvas |
| `backgroundTop` | `#130A22` | `#FFFCFF` | quiet canvas gradient |
| `surface` | `#17121F` | `#FCFAFD` | standard card/sheet |
| `surfaceMuted` | `#100D18` | `#F1EBF4` | disabled/quiet region |
| `surfaceRaised` | `#21192B` | `#FFFFFF` | dialog/menu/raised card |
| `surfaceSunken` | `#0C0814` | `#E9E1EF` | inset/disabled fill |
| `border` | `#342A43` | `#D6C8DF` | decorative separation |
| `borderStrong` | `#7C6790` | `#967AA9` | control boundary |
| `textPrimary` | `#F8F5FC` | `#211629` | headings/body emphasis |
| `textSecondary` | `#B8AFC2` | `#5D5067` | supporting copy |
| `textTertiary` | `#958B9F` | `#706078` | disabled/tertiary copy |
| `navigationSurface` | `#17111F` | `#FFFCFF` | dock/sidebar fill |
| `navigationOutline` | `#725C86` | `#9A83AA` | persistent chrome edge |
| `navigationInactive` | `#9189A6` | `#594B63` | inactive destination |
| `interactiveForeground` | `#D986FF` | `#6F1DCE` | links/quiet actions |
| `focus` | `#D986FF` | `#6F1DCE` | focus on neutral surfaces |
| `shadow` | `#000000` | `#3D1F50` | elevation shadow source |
| `scrim` | `#09050F` | `#1A1021` | modal/media scrim source |
| `dangerSurface` / `dangerForeground` | `#32131D` / `#FFB3BE` | `#FDEDF1` / `#B4233F` | destructive/error pair |
| `successSurface` / `successForeground` | `#10271C` / `#57D99A` | `#E8F7EF` / `#08784E` | success pair |
| `warningSurface` / `warningForeground` | `#2E2410` / `#FFC94D` | `#FFF4D8` / `#8C5A00` | warning pair |
| `infoSurface` / `infoForeground` | `#102337` / `#6FC3FF` | `#E8F3FF` / `#006B91` | information pair |

Filled primary and danger controls use their Material `onPrimary` / `onError`
foreground as the two-pixel keyboard-focus boundary. This keeps the indicator
above 3:1 against the actual brand or error fill; `focus` remains the correct
ring on neutral surfaces. `navigationOutline` is deliberately not a focus
token.

Voice rooms (including their shared stage and compact live capsule), calls,
recording/review, story viewing, image croppers, the branded auth/startup
curtain and its inbox-confirmation sheet, and the explicitly dark staff/creator
workspaces are intentional immersive-dark islands. They own a complete dark
surface + foreground + scrim treatment; never let an inherited light
foreground leak onto their media, and never use their dark literals for a
normal Pearl page. Development previews may model one of those atoms but do
not define product colour. When migrating legacy UI, migrate the complete
surface atomically rather than mixing semantic and screen-local roles.

`AppImmersiveColors` is the explicit legacy-dark atom for those documented
islands only. Public sheets opened from normal journeys — including content
reporting — always inherit `AppPalette`; being launched from a dark screen is
not enough to classify a component as immersive. The source guard inventories
all 26 roles in both schemes and rejects either scheme's exact raw token value,
the dark atom's container/border literals, and immersive imports throughout
Pearl-capable presentation roots. Its sole line-local exception is an
`uploaded-media` pixel value. Complete immersive atoms are an explicit,
reviewed path allowlist; a normal route cannot add a file-wide or free-form
opt-out.

Room-family swatches in `SpaceIdentity` are stable identity seeds for immersive
rooms. Pearl-capable create and confirmation journeys must call
`SpaceIdentity.resolve(brightness)` and use its paired surface/on-surface,
foreground, boundary and CTA roles. Using the raw Club gold or Family emerald
as body copy or a light-theme button fill is not a supported identity style.

Discover category swatches follow the same identity/presentation split.
`DiscoverCategoryIdentity` owns the stable Talk, Chill, Broadcast, Music,
Gaming, Business, Study and Tech seeds; normal-route badges, compact copy,
meaningful icons, boundaries and actions use `resolve(brightness)` instead of
painting that seed directly. These are feature-derived visuals, not new global
`AppPalette` tokens: ordinary card chrome still uses the semantic palette and
the stable seed remains available only for low-opacity decorative branding.

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
