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

## Vertical rhythm

`AppRhythm` in `lib/core/theme/app_spacing.dart` names the six vertical
steps a page may use — 4 / 8 / 12 / 16 / 24 / 32 — and what each one MEANS:

| step | value | what it separates |
| --- | --- | --- |
| `hairline` | 4 | inside one lockup (greeting → name, label → value) |
| `tight` | 8 | parts of one control, or two rows in one card |
| `item` | 12 | sibling blocks in a section; a rail's tile pitch |
| `title` | 16 | a section title → its content; card padding; the page's top band |
| `section` | 24 | content → the NEXT section title |
| `page` | 32 | the last content → the end of the scroll |

Only the horizontal gutter varies with width (16 / 24 / 32 above). The
vertical steps do not: they are identical at every breakpoint, every text
scale, in every locale, and in every state.

**The rule the scale depends on: a page child's LAYOUT box equals its INK
box.** Spacing lives BETWEEN boxes, never inside a hit target, so the number
in the source is the number the reader sees. A control that must reserve a
44 px target around smaller ink subtracts that air from the gap it declares
rather than adding it — see `HomeSectionHeader`
(`lib/shared/widgets/layout/home_section_header.dart`),
whose layout box is exactly `section + title-ink + title` whether or not it
carries a "View all" and however the title wraps. Watch for the two usual
sources of invisible air: `MaterialTapTargetSize.padded` inflates a 44 px
button's box to 48, and a rail tile's own padding adds to the pitch the rail
already declares. Shrink-wrap the button; give the tile `EdgeInsets.zero`
and let the rail own the gap.

A heading's trailing "View all" moves under the title only when it would
otherwise cost more than a third of the row — a width test, not a text-scale
one. A phone at 200 % text stacks; a 768 px slate or a 1440 px desktop at the
same text scale keeps the action on its heading's line rather than pushing it
a full row width away from the words it belongs to. **A page never mixes the
two arrangements**, and the mechanism is not that every heading carries the
same words — they do not: Polish declines the object of "see all", so the
friends rail says "Zobacz wszystkich" where servers and chats say "Zobacz
wszystkie". The test is answered against the *widest* "View all" the page can
carry, so every heading on it gets the same answer and the widest label is
the one that decides. Answering it from each heading's own label is what put
"Zobacz wszystkich" on a second row at a 1032 pt window while its two
neighbours kept theirs on the heading line (Build 33 polish, `T-2`).

Home is the reference implementation on both platforms, and
`test/home_rhythm_test.dart` pins it: every gap is asserted against the
named step, not a literal, at 320/390/430/768, at 1.0 and 2.0 text scale, in
English and Polish, empty and populated. `test/.screenshots/home_rhythm_capture.dart`
renders the frames that back the numbers.

Horizontal rails (the people strip, the Moments strip) are **full-bleed**:
the page gutter is the scroll view's own padding, so the first tile's ink
starts exactly at the margin and the rest scroll under the frame's edge.
Everything else on the page is inset to the margin and paints nothing
outside it.

**A section title is a promise about content.** A heading over a single
button is not a section: with no followed Moments, Home draws no "From
people you follow" heading and the rail's Record affordance becomes a
labelled full-width action beside the page's other real routes — under
"Create server" and "Friends", on both form factors, not floating at the top
of a column with nothing above it. The control keeps its key, focus node,
semantics and callback; only its shape and its place change.

## YO Moments creation and Reel identity

Reels has separate Discover and Your Reels filters, a persistent labeled Create
Reel action and an explicit refresh. Your Reels compares canonical author IDs
with the authenticated viewer, never display names. It scans the existing
authorized paginated feed in bounded batches; a scan with more pages offers
Load more rather than claiming the user's library is empty. The format chooser
uses a plus instead of implying that Reels can only create microphone content.

The Reel composer keeps one local draft through Media, Edit and Review stages.
Crop, Audio, Text and links, and Filter expose one tool panel at a time. Preview
and playback use the same 390-unit 9:16 composition canvas. Pinch/drag maps to
the existing normalized crop, with labeled sliders and Reset as alternatives;
pan requires spare pixels from zoom. Local video/original audio/backing audio
share the published playback coordinator, including trim, volume and lifecycle
pause. Native playback controls remain outside the scaled canvas. Imported
audio is user-owned/licensed MP3/M4A/WAV within existing limits, not a streaming
music catalogue. Media replacement retains caption, audio and overlays while
explicitly resetting incompatible crop/trim. Publication remains explicit and
retry-stable, never triggered by editing or preview.

Voice recording has distinct Capture and Review surfaces. Review places real
playback before caption/lifetime and exposes a persistent publication footer
when space permits; short/large-text layouts scroll. Tablet keyboard reflow
retains the actual caption editor and focus. The existing recording, silence,
permission, reply, lifetime, retry and microphone-cleanup state machine remains
the owner of behavior. This is a documented immersive-dark atom in either theme.

Creation copy, errors, permission guidance and meter semantics use explicit
locale catalog entries and stable named placeholders. Arbitrary backend errors
are not rendered as user instructions. Sample previews/captures are development
fixtures, not evidence of production upload or physical multi-account delivery.

## Foreground notification banner

`YoTopNotificationHost` owns one top-centered arrival card above the Navigator,
including pushed routes and dialogs. Its tooltip overlay is a sibling of the
Navigator, not its ancestor, so existing root-overlay chat controls cannot
intercept the notification. Normal success/error SnackBars are unchanged.

The card sits 10 px below the safe top inset, with 16 px side gutters and a
520 px maximum width. It uses the shared raised surface, strong boundary and
semantic foregrounds in Dark and Pearl. A type icon or actual message avatar
leads the text; localized Open and Close controls have 44 px targets. Long
content wraps and scrolls within the remaining keyboard-safe height. If there
is insufficient space for the controls, the host rejects presentation rather
than accepting an invisible card; the existing stream can retry when space
returns.

Entry is a 300 ms fade/18 px slide with a restrained .98-to-1 scale; dismissal
is 160 ms. Reduced Motion settles instantly, with no idle animation. Latest
arrivals replace the card; generation-bound timers cannot close a newer one.
Achievements retain their 2-second title-only presentation, other arrivals
use 5 seconds. Hover/focus pauses dismissal; accessible navigation keeps the
card until dismissal. The live region does not request focus on arrival.
F6/Shift-F6 explicitly moves to the notification controls or returns to the
previous focused control; Tab cycles Close/Open within that region. Escape
only dismisses when focus is in the card, preserving modal Escape outside it.
Arrow/Page/Home/End keys scroll long notification content only while focused
inside that region. Replacing a scrolled card resets content to the top while
preserving control focus. Session clear/Open discard the old focus-return target.
The visual F6 hint is shown on desktop or after actual keyboard input, not in
the ordinary touch-phone presentation.
Auth exit and app backgrounding clear content immediately, without an exit
animation. Open clears the card before invoking the existing route callback.

Firestore activity, foreground social pushes and MainShell message arrivals
share this presentation. Existing deduplication, unread baselines, active-chat
suppression and route payloads retain their owners. Native foreground social
delivery prefers this card, with the existing native fallback if unavailable;
calls remain native-first and OS background delivery is unchanged. Delayed
foreground fallback rechecks the captured authenticated UID and identity epoch
before presenting, preventing a stale retry after sign-out/account change.

## Floating mobile navigation

`YoFloatingNavigationDock` is the only mobile shell navigation surface. The
post-Build-20 Meniscus change replaces the fixed central YO action/rise with
five destinations: **Home, Servers, Chats, Your Moments, More**. Their stable
content identities are `0, 13, 1, 5` and a More action; desktop slot identities
and the full More menu stay intact. Servers uses the current `ServersScreen`
root and five-template selector. Your Moments keeps the unified Głos/Yeels
feed; it is not an own-only filter.
Its navigation label is localized in all 43 locales without renaming the
existing YO Moments product heading. Mobile creation onboarding highlights
the real Servers control, including replay after scrolling and layout changes.

Build 27 changes only that Rooms-to-Servers destination identity. The Hub
bar/dock's geometry, interaction model, animation and accessibility behavior
remain the existing component contract.

One circular bead and a continuous concave socket share a spring-driven
position. The trailing shoulder length reacts to velocity; upright icons lift
into the bead and the active label appears below. Tap requests a destination;
drag previews only the chrome and commits once on release. Cancellation,
denied navigation and external route changes restore parent-authoritative
selection. No content query or route is opened while passing intermediate
icons. Reduced Motion settles immediately; there is no idle animation.

The normal dock is 92 px plus 4 px top clearance and safe bottom reservation,
capped at 460 px wide with 14 px outer gutters. Beads are 44/48 px with five
non-overlapping touch controls of at least 48 px width. End sockets clear
the 14 px endcaps. Larger text uses a full-width active-label row rather
than shrinking the requested scale. Semantics and ordered keyboard traversal
expose all five localized labels; focus uses the semantic two-pixel boundary.
RTL mirrors visual order and unread placement. Dark/Pearl share geometry,
semantic chrome and theme-invariant brand accents. No YO logo remains in
the navigation bar.

When a real room is minimized, a non-interactive copy of the same transparent
mark rises from the centre axis and resolves into the one real compact room
bar. It never owns room data or controls. The production bar remains the sole
Chat/Mic/More/Return surface, direct calls are excluded, and Reduce Motion
shows the settled bar immediately. Pushed destinations temporarily own that
bar while the covered shell suppresses its copy, so there is one voice listener
and one latest-message subscription throughout route transitions.

### Mobile Back behavior

Ordinary pushed pages retain Flutter's native Cupertino leading-edge Back and
their existing pop guards. Retained mobile root sections additionally keep a
session-local, bounded history: Home → Rooms → Chats returns Chats → Rooms →
Home. Selecting Home explicitly clears the trail. Back applies the original
selection callback without recording a new visit, preserving mounted tab state
and service ownership; focus is released from the departing root.

`YoEdgeBackGesture` listens only in the leading 24 px (or larger safe inset),
mirrored for RTL, and only for touch input. Its translucent edge listener joins
the horizontal gesture arena ahead of child media while preserving vertical
scrolling and taps. Center-screen media gestures and the separate dock are not
claimed. A small safe-inset-aware Back indicator follows drag progress; release
commits once after distance/velocity acceptance. Cancellation, a changed
destination, a covering route or disabled state cannot commit stale navigation.
System Back consumes root history before normal root exit behavior. Desktop
layout changes normalize the trail; onboarding seeds its actual visible root
instead of recording artificial tour visits. Call, recording, processing and
full-screen media dismissal/confirmation rules are unchanged.

### Normal-page brand canvas

`YoPageBackground` renders the official transparent YO asset once, behind
normal page content, static and excluded from hit testing and semantics.
The optional `YoPageSection` selects original bundled scenery: Home welcome
lounge, Rooms sofa/podcast lounge, Chats private corner, Moments recording
studio and More/Settings quiet study. Scenery replaces the standalone mark
(it does not stack another neon/logo over it), at `.18/.07` Dark/Pearl alpha.
Five optimized WebP assets total 224,674 bytes; decode width is capped at
864 px and there are no network reads, animated backgrounds or blur filters.
High contrast omits all decorative imagery. Nested feed canvases paint once.
Normal Friends/profile, own Profile, Clubs and the notification inbox retain
the standalone logo at `.025/.018`. Immersive call/media/camera/auth stages
keep their own backgrounds. The mobile More sheet has scenery behind its
controls; the small desktop More popover remains a plain semantic surface.
Deeper settings routes are not claimed as converted.

### Live-first Home

The approved Home concept is implemented as real widgets, not a screenshot:
compact greeting and own/followed playable-Moment avatars, one leading real
room, two Create room/Friends actions, a genuine followed-Moment recap, recent
chats and preserved owned-room management. Additional real rooms remain below.
No mockup names, room titles, online counts or users are production content.
Missing room data shows loading/error/empty independently; an empty account
does not acquire a fake live hero. Actual room covers take precedence over the
decorative lounge fallback. All existing join/create/profile/message callbacks
and Community/Broadcast separation remain in their original owners.

Home uses a single column at compact widths and deliberate 3:2 columns when
the desktop content slot has at least 850 px. At enlarged text, actions stack
and primary text wraps. Chats can scroll its header/search/friend rail together
with the lazy conversation list on short screens; enlarged-text conversation
names receive their own full-width row. Decorative live-room pulses stop for
Reduced Motion, accessible navigation and offstage content.

## Shared primitives (Slim redesign, phase 0)

One state = one primitive. A state that already has a canonical widget is
extended in place; a second drawing of the same state is a bug, not a variant.
The table lives in ADR-209 (`Decisions.md#adr-209`); the entries below are the
rules a screen author needs.

- **NA ŻYWO = `YoBadge(variant: YoBadgeVariant.live)`**
  (`lib/shared/widgets/badges/yo_badge.dart`). A filled `AppColors.live` pill
  with `AppColors.onLive` copy, `labelSmall` (10 px) at w800, letter-spacing
  .8, 8/3 padding, `AppRadius.pill`, no border, and a 6 px dot that pulses
  (opacity .55 → 1, 1.2 s) only while motion is allowed — under Reduce
  Motion, accessible navigation or a disabled `TickerMode` the controller is
  stopped and parked, so no frame is scheduled. Both tokens are
  brightness-independent, so Dark and Pearl draw the same marker. The label
  is rendered verbatim, one line, never wrapped, eliding rather than breaking
  the word; the caller owns the copy (`copy.serverLivePill`,
  `copy.text('LIVE', 'NA ŻYWO')`, the hero's `'LIVE NOW' / 'TERAZ NA ŻYWO'`)
  and the `isLive` gate. `icon` is ignored for this variant — the dot is its
  icon. Marker keys pass through `key:`; the badge adds no key and no
  semantics of its own, because the word already voices the state. On server
  surfaces mount `ServerLivePill(label:)`
  (`servers/presentation/widgets/server_channel_scene.dart`): it is the same
  badge under the counted `server-live-pill` key that every server test
  addresses (header pill, stage marker and the channel row's trailing marker
  share it), and it is never mounted on `CreateServerScreen`
  (`test/server_creation_gate_test.dart`). Contracts:
  `test/yo_badge_live_test.dart`, `test/shared_component_accessibility_test.dart`
  (AA contrast of the paired roles), `test/server_podcast_test.dart`
  (taller than 26 px at 320 px / 200 %).
- **Presence dot = `AvailabilityDot(status:)`**
  (`lib/shared/widgets/profile/availability_dot.dart`). A filled circle in
  `PeopleStatus.foreground(palette)` — the same ink `PeopleStatusAvatar`
  paints as a ring — so `successForeground` online, `warningForeground` be
  right back, `dangerForeground` do not disturb, `textTertiary` offline or
  invisible, in both themes; never `AppColors.success` and never a second
  grey. The caller owns the gate (hide when offline, or draw it grey — both
  exist and both are kept per surface), the status (`PeopleStatus.fromPresence`
  for others, `fromOwnAvailability` for the signed-in account), the
  `Positioned` offset, the `size` (8–16 px on avatars) and the halo:
  `borderColor` is the surface the avatar sits on (`background`, `surface`,
  `surfaceRaised`, `surfaceSunken`) and `borderWidth` 0 draws a bare disc
  (the profile preview's "● Dostępny" row). Defaults (10 px, `surfaceRaised`
  1.5) are the availability picker's. One presence mark per avatar: a dot OR
  a `PeopleStatusAvatar` ring, never both, and no dot where the source has no
  presence (servers). The dot carries no semantics, tooltip or key of its
  own — the row already says "name, online" — so keys pass through `key:`.
  Contracts: `test/availability_dot_test.dart` (colours, defaults, halo, no
  semantics), `test/people_status_ring_theme_test.dart` (the ring host holds
  exactly one circle), `test/home_blocking_defects_test.dart` (own Start tile
  is a dot, not a ring).
- **Waveform (bars) = `YoWaveform(color:)`**
  (`lib/shared/widgets/waveform/yo_waveform.dart`). One `CustomPainter`, exact
  `height` × `width` (null = the parent's width; an explicit width is kept even
  in a tight parent), two layouts: flex (`barWidth` null — `barCount` bars share
  the width with `barGap` between them) and tiled (`barWidth` set — fixed pitch,
  as many bars as fit, run centred). **No amplitude = static.** No per-Moment or
  per-message amplitude exists, so the shape is always a fixed `silhouette`
  (`YoWaveform.bars`, the 30-entry story list; `YoWaveform.ramp(n)` for the
  Start motif; the podcast stage's five heights) and the widget owns no
  controller, timer or randomness — never invent a shape from a duration or an
  id, never animate it. The only real value is `progress`: leave it null unless
  you hold the player's position; then the bars behind the playhead take
  `playedColor` (`AppColors.secondary`) or `playedGradient`
  (`palette.audioProgressGradient`), one whole bar at a time, mirrored in RTL.
  The caller owns the colour (a palette role, an `AppColors` constant at an
  alpha, an identity visual), the play / pause state, the seek gesture, any
  slider overlay and any `Semantics` label; the widget is `ExcludeSemantics`
  and adds no key, so marker keys (`server-podcast-waveform`) pass through
  `key:`. Moment players mount `StoryWaveform(progress:)` — the same widget
  with the player defaults (44 px, gap 3, radius 2, `AppColors.primary` at .32
  unplayed), pinned by type in `test/moment_feed_card_redesign_test.dart` and
  `test/moment_position_single_source_test.dart`. Real audio level is a
  different state: `RoomEnergyWave`, the recorder's level meter and
  `VoiceCore` are not this widget. Glyph badges (`Icons.graphic_eq_rounded` in
  a circle: the mini player's `_WaveformBadge`, `HomeFriendTile`'s
  `_ContentBadge`) are not this widget either. Contracts:
  `test/yo_waveform_test.dart` (exact box, explicit width, no frame scheduled,
  no semantics, key pass-through, the ramp, the `StoryWaveform` defaults),
  `test/server_podcast_test.dart` (the mark exists only for the speaking
  person). Frames: `flutter test test/waveform_screenshot.dart` →
  `test/.screenshots/waveform-{dark,pearl}-{ltr,rtl}-600.png`, to be copied to
  `yovoice-evidence/2026-09-19/slim-0-waveform-frames/after/` by the visual
  verification step (pending at the implementation commit; see
  `docs/Sessions/2026-09-19-slim-redesign.md`).
- **Section heading = `HomeSectionHeader(title:)`**
  (`lib/shared/widgets/layout/home_section_header.dart`; Home-era name kept,
  it is the heading for every scrolling page). Its layout box is exactly
  `AppRhythm.section` (24) + title ink + `AppRhythm.title` (16) — with or
  without a "View all", with a trailer, with a subtitle, however the title
  wraps, at any text scale, in any locale — so a caller removes every
  vertical `Padding` / `SizedBox` around it and keeps only the horizontal
  gutter; the list above it adds no top air of its own and card gaps sit
  only *between* cards. Slots: `onSeeAll` + `seeAllLabel` (+ `seeAllKey`)
  for the way through to the full list, 44 × 44 target shrink-wrapped,
  stacking under the title only when the page's widest action would cost
  more than a third of the row — outside Home pass `seeAllVocabulary`, the
  labels that page carries, so every heading on it arranges identically;
  `trailing` for a mark that is not an action (a count pill, a category icon
  box), centred on the title ink and exclusive with `onSeeAll`; `leading`
  for a 16–18 px glyph on the title line; `subtitle` for one `textSecondary`
  line that is part of the heading ink; `live` for the 6 px `AppColors.live`
  dot; `scale` compact (17 px) on phones and in the desktop secondary column,
  expanded (19 px) for desktop page headings. Never add a scale value, a
  `topGap` or a private copy; count pills stay with their screen until
  `YoMetricPill` exists. The title is the heading's semantics name (header
  flag); leading, trailing and subtitle are not merged into it. Contracts:
  `test/home_rhythm_test.dart` (the frozen 24 / ink / 16 and stacking
  verdicts), `test/home_section_heading_semantics_test.dart`,
  `test/home_section_header_slots_test.dart` (the three slots and the
  vocabulary), `test/desktop_shell_test.dart` (Voice Trending renders
  "See all rooms", never a second "View all").
- **Story ring = `MomentStoryTile` / `MomentSeenAvatar` / `MomentAuthorCapsule`**
  (all in `lib/features/moments/presentation/widgets/moment_story_tile.dart`;
  `moment_discover_tiles.dart` re-exports `MomentSeenAvatar`). THE RING IS
  THE LISTENED STATE — this account's own `users/{uid}/momentViews` through
  `MomentViewsService`, resolved once per rail by `MomentViewedIds` (pass
  `viewedIds` through when the surface already owns the set; unknown state
  renders as unheard, fail open) — and never presence: a person's
  availability is `PeopleStatusAvatar` / `AvailabilityDot`, and Home's
  friend tile draws "new content" as its own cyan `join.ring` on a presence
  tile, on purpose (ADR-155, ADR-209). The stops come from
  `MomentStoryTile.ringColors(context, seen:)` and are painted through
  `MomentStoryTile.ringGradient(context, seen:)` — unheard is the brand
  gradient (`AppColors.primary` → `AppColors.secondary` at
  `AppGradients.primary`'s angle), heard is `palette.border` twice at the
  same angle, with the avatar dimmed to .62 and the name in
  `textSecondary` — and nowhere else: never `AppGradients.primary` directly
  around an avatar, never a `Border.all`, never a painter, never a
  story-look gradient on a rail that carries no Moments state (a rail with
  nothing to say wears a 2 px `palette.border` band, as the Chats rail
  does). Three shapes, one state: `MomentSeenAvatar(seen:, diameter:)` is
  the disc (feed card 48 / 56 pt at the 2 / 1.5 defaults; the tile passes
  2.5 / 2 for its 60 pt disc, 56 below 360 px; `ringKey` lands on the
  painted `Container` whose `BoxDecoration` carries the gradient, which is
  where a test reads it); `MomentStoryTile` is the disc plus name, optional
  caption / identity badge / online dot, the real chain-count badge and the
  `+` with its own 44 pt record target (constructor and `discFor` /
  `widthFor` / `heightFor` statics frozen); `MomentAuthorCapsule` is the
  feed strip's 48 pt pill whose border is the ring (2 px unheard, 1 px
  heard) with static, never-cyan bars. The caller owns chain building
  (`buildMomentChains`), the keys (`home-your-moment`, `home-moment-<id>`,
  `home-record-moment`, `moments-capsule-<author>`, `moment-row-chain-<id>`),
  the `copy` semantic label (the primitive appends "not heard yet" /
  "already heard" itself; `MomentSeenAvatar.stateLabel` gives the same
  words to a caller that wraps the disc in its own tap region) and the tap
  callbacks. Contracts: `test/moment_story_tile_test.dart` (stops in both
  themes, opacity, labels, disc sizes, 44 pt targets, fail-open),
  `test/moment_author_capsules_test.dart` (border stops == `ringColors`,
  bars static and `AppColors.primary` @ .32), `test/moments_discover_layout_test.dart`
  (`seen` per row, unheard is a two-stop gradient of distinct colours),
  `test/moment_seen_avatar_test.dart` (`ringGradient`'s stops and angle in
  both themes, the `ringKey` contract, the tile's 2.5 / 2 hand-down, the
  capsule's angle, the re-export), `test/desktop_home_test.dart` (no
  `MomentStoryTile` on desktop Home today).
- **Inline voice clip = `VoicePlayerRow(status:, durationSeconds:,
  semanticsLabel:, onTap:, style:)`**
  (`lib/shared/widgets/voice/voice_player_row.dart`). One row for "an audio
  clip you can play here": play/pause disc, waveform, `m:ss` clock — the chat
  bubble, the shared-media Voice tab, a Voice Moment reply and a Yeel voice
  comment. **Presentation only.** The caller keeps the `AudioPlayer` and its
  factory seam, the media grant, the playback arbitration and its stale-grant
  tokens, the retry and snackbar paths, the `ValueKey` (`tapKey`, which lands
  on the `InkWell` spanning the whole row, so it is also the ≥ 44 px target
  and the long-press path to a context-action wrapper), the localized label
  and the mapping of its own booleans to a `VoicePlayerRowStatus` (`loading`
  wins over everything, `paused` draws what `idle` draws, `failed` is the
  retry glyph). Two shapes, through `VoicePlayerRowStyle`: `.contained(palette,
  colorScheme)` is the thread row (`surfaceMuted` card, `border` hairline,
  bordered 40 px disc on `surfaceRaised`, `audioAccent` spinner, waveform
  filling the rest) and `.inline(foreground:, mutedForeground:,
  errorForeground:)` is the bubble (no surface of its own, bare 44 px icon
  box, inks injected because the same row is white on the outgoing gradient
  and `textPrimary` on an incoming one, and a waveform bounded to 48–126 px so
  the bubble keeps shrink-wrapping). `progress` is the player's REAL position
  or nothing: a surface without a position stream passes null and gets a still
  `YoWaveform` silhouette — never a fill invented from the duration — while a
  surface with one gets `StoryWaveform` swept by `audioProgressGradient`. Copy
  never enters this file (`lib/shared/` is under the localization guard), so
  `semanticsLabel` arrives localized; `semanticsContainer` /
  `excludeChildSemantics` / `toggled` choose between the thread row's own
  node, which also carries the tap action, and the bubble's plain labelled
  button whose children stay findable. Use `formatVoiceClock(seconds)`
  wherever a clip's length is printed. Not this widget: transport buttons with
  no waveform (the recorder preview, the album rows, the podcast episode
  board), real audio level (`RoomEnergyWave`, the level meter, `VoiceCore`).
  Contracts: `test/voice_player_row_test.dart` (statuses, the spinner's own
  ink, the formatter, the key on the full-row target, both semantics shapes,
  shrink-wrap vs. fill), `test/message_bubble_media_state_test.dart` (the
  incoming spinner is `textPrimary` in both themes; no overflow and the
  reaction pill stays below the clock at 320–1440 px / 200 %),
  `test/moments_semantics_activation_test.dart` (the thread row is activated
  through `SemanticsAction.tap`), `test/voice_reply_mini_player_test.dart`.
- **Channel row = `YoChannelRow` / `YoVoiceChannelRow`**
  (`lib/shared/widgets/rows/yo_channel_row.dart`). A `ListTile`: 48 px floor,
  12 px content padding, `AppRadius.md`, 21 px glyph, the name in
  `bodyMedium` on one unwrapped line that elides (`labelMaxLines: 2` only for
  a label that is a sentence, the family home board). The caller owns the key
  and passes it as `tileKey`, so it lands on the `ListTile` that
  `test/server_workspace_test.dart` reads by type; the row draws no `Material`,
  so the selected wash composites over the list's own surface (the AA check in
  that test). The caller also owns the glyph (`serverChannelIcon(kind)`, or
  `Icons.lock_outline` with `copy.serverChannelRestricted` as
  `iconSemanticLabel`), the identity ink and wash, every string and the tap —
  which selects, never joins. Media channels mount `YoVoiceChannelRow`, which
  before joining draws **only what the channel document carries** (ADR-177):
  the `liveBadge` the caller builds (`ServerLivePill`, so `server-live-pill`
  stays one key per marker), the clock `od 19:40`
  (`copy.serverLiveSinceShort(serverLiveClock(...))`) and, once in, the
  `audioAccent` connection glyph. It never prints the quiet copy and never a
  face or a count before joining — `participants` is ignored unless
  `connected`. For the connected channel alone the caller maps
  `ServerSessionController.participants` to `YoVoiceRowParticipant` (with the
  localized `name, mówi` / `name, Mikrofon wyłączony` label) inside a
  `ListenableBuilder` scoped to that row: up to four 22 px avatars, a 2 px
  `AppColors.success` ring while speaking, a crossed microphone when muted, a
  real `+n` for the rest. `onJoin` adds a 44 px icon control (label as tooltip
  and semantics, glyph from `serverJoinIcon`, label from `serverJoinLabel` —
  the same switch as the scene's `server-join`) under its own
  `server-channel-join-<id>` key; it is null on a held server, a restricted
  channel, the channel you are in and a stage you may not start, and it steps
  aside below 240 px of row or above 1.5× text so the name keeps its measure.
  Not this widget: the create-server seed preview (a template preview, not a
  channel) and the retired clubs row. Contracts: `test/yo_channel_row_test.dart`
  (key on the `ListTile`, selection pass-through, no own `Material`, the lock's
  label, silence when idle, one marker when live, no face before joining,
  ring / mic / `+n` when connected, the join key, target, select-only tap and
  the width / text-scale floor), `test/server_workspace_test.dart` (selected
  contrast; held roots: one inert `server-join`, no marker, no names),
  `test/server_shell_test.dart` (exactly one marker for one live channel, no
  quiet copy on a live row), `test/server_independent_qa_test.dart` (tapping
  every row reaches no provider).

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

## Server media sheets and call Picture in Picture (source only, 2026-09-16)

- **OBS setup (ADR-192).** The Community stage action row places **OBS**
  beside **Share screen**; the row wraps on narrow widths. OBS opens a
  scroll-controlled modal bottom sheet with the setup guide, then the server URL
  and a Stream Key that stays masked until the host reveals it, each with a copy
  button and copy feedback. Refusals show localized copy, never the backend
  message or code, and re-enable the setup button.
- **Live whiteboard ink (ADR-193)** reuses the existing board canvas; other
  members' in-progress strokes render beside the local stroke. A preview
  disappears when its sender clears it, sends nothing for 2 seconds, or the
  meeting connection ends.
- **Call Picture in Picture (ADR-194).** While the system PiP window is shown,
  the direct call screen renders only the remote video surface (or the
  "camera is off" label), without call controls.
- **Screen share availability.** The Company meeting shows an explicit note
  when the platform cannot start a share, and a host-only note to a connected
  participant without the screen grant.

- **Whiteboard toolbar.** Tools, ink colors and line widths wrap onto further
  runs at every width instead of scrolling, so no control is cut off at a
  phone edge; the zoom pill over the canvas is opaque.

Evidence is widget tests plus capture-harness frames at 390x844, 1440x900 and
320x760 at 200% text (`yovoice-evidence/2026-09-16/community-frames` and
`company-frames`), and whiteboard toolbar frames at 402x874 in both themes
(`wip-fix-1-frames`). An iOS Simulator smoke on 2026-09-16 (iPhone 17 Pro,
402 pt, light theme, English; `wip-verify-device.md`) rendered Servers, the
Company whiteboard, the Community stage before joining, a direct message with
its call buttons and Notifications with no overflow or Flutter exception. It
found the toolbar clipping that the wrapping layout above fixes (the fix itself
has harness frames only) and pre-existing phone defects, all recorded in
[Bugs.md](Bugs.md). It could not reach the OBS button and sheet, screen share,
the direct call screen, PiP or live ink from other members without ringing a
real user or starting a production session, so those statements stay
**UNVERIFIED**. The Accessibility review of these surfaces is still pending.

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

## Finishing a text field while the keyboard is up

**Every text field must offer a visible way to finish typing, and the
screen's primary action must never be stranded behind the keyboard.** A
tester's words for the failure: writing should be straightforward, not a
puzzle about how to hide the keyboard. Never rely on tap-outside or
drag-to-dismiss as the only exit — neither is discoverable, and on native
iOS and Android a touch outside a field does not unfocus at all.

Exactly one of three mechanisms applies, chosen by the kind of field, not by
the screen:

- **R1 — the return key completes the field.** Every single-line field and
  every short caption declares its action rather than inheriting one:
  `search` for a search box, `next` for a field followed by another, `done`
  for the last one, `send` for a composer. A short caption also sets
  `keyboardType: TextInputType.text` so the platform draws a confirm key
  instead of a newline arrow even though `maxLines > 1`.
- **R2 — the primary action is docked above the keyboard.** An adjacent send
  button (chat and comment composers), an app-bar action (Edit profile or
  Server settings), or a pinned footer (Create server or a stage settings
  sheet). Only fields covered by R2 or R3 may keep Return
  as a line break.
- **R3 — the shared `YoKeyboardDoneBar`** (`lib/shared/widgets/inputs/`),
  for genuinely long-form fields: bios, Server descriptions,
  guidelines, moderator notes. It renders only while a field has focus and
  the keyboard is open, and can carry the screen's primary action next to
  Done (`action:`) when the screen's own footer has nowhere to sit.

Left to the multiline default Flutter sends `TextInputAction.newline`, and
`performAction` deliberately ignores newline — so on such a field `Return`
can only insert a line break and an `onSubmitted` callback is dead code.
Declare the action or delete the callback; do not ship both.

### Placement invariant

**`Scaffold` does not lift `bottomNavigationBar` above the keyboard.** It
shrinks the body and leaves the bottom slot pinned to the bottom of the
window, so bottom chrome placed there is drawn *behind* the keyboard —
present in the widget tree, invisible on the device. Measured on 390x844
with a 336 px keyboard: a bare `bottomNavigationBar` lands at y 796–844,
entirely covered.

Bottom chrome that must stay visible while typing therefore sits in one of
three places, and a widget test measures its rendered rectangle against the
top of the keyboard:

1. `Scaffold.bottomNavigationBar` wrapped in `YoKeyboardSafeBottomBar`,
   which pads it by the keyboard inset (same surface: y 460–508).
2. The last child of a `Column` inside `Scaffold.body` whose other child is
   `Expanded` — the body has already been shrunk above the keyboard.
3. The last child of a sheet's `Column` inside its own `viewInsets` padding.

`Scaffold` strips the bottom view inset from the **body** slot, so in
placement 2 the inherited `viewInsets.bottom` reads 0 while the keyboard is
open; `YoKeyboardDoneBar` falls back to the `FlutterView`'s own inset for
exactly that case. A bar that only checks `MediaQuery.viewInsetsOf` renders
nothing there.

Full reasoning:
[ADR-169](Decisions.md#adr-169-one-keyboard-contract-for-every-text-field-and-bottom-chrome-that-is-actually-above-the-keyboard).

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
